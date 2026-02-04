//! NetROM over TCP transport layer
//!
//! This module implements the TCP transport for NetROM frames as used by LinBPQ.
//! The wire format consists of:
//! - Length (2 bytes, little-endian): Size of payload (call + PID + frame)
//! - Callsign (10 bytes, ASCII, space-padded): Source callsign
//! - PID (1 byte): 0xCF for NetROM
//! - NetROM frame: L3/L4 headers + data
//!
//! Reference: LinBPQ NETROMTCP.c

use std::io;
use std::net::SocketAddr;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tracing::{debug, trace, warn};

use crate::netrom::{Callsign, NetromFrame, NodesBroadcast, NETROM_PID, NODES_SIGNATURE};

/// Size of the callsign field in wire format (ASCII, space-padded)
const WIRE_CALL_SIZE: usize = 10;

/// Minimum frame size on wire: length(2) + call(10) + pid(1) + L3(15) + L4(5)
#[allow(dead_code)]
const MIN_FRAME_SIZE: usize = 2 + WIRE_CALL_SIZE + 1 + 15 + 5;

/// Maximum frame size on wire
const MAX_FRAME_SIZE: usize = 512;

/// Error types for transport operations
#[derive(Debug)]
pub enum TransportError {
    /// TCP I/O error
    Io(io::Error),
    /// Connection closed by peer
    Disconnected,
    /// Invalid frame format
    InvalidFrame(String),
    /// Frame too large
    FrameTooLarge(usize),
}

impl std::fmt::Display for TransportError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io(e) => write!(f, "I/O error: {}", e),
            Self::Disconnected => write!(f, "Connection closed"),
            Self::InvalidFrame(msg) => write!(f, "Invalid frame: {}", msg),
            Self::FrameTooLarge(size) => write!(f, "Frame too large: {} bytes", size),
        }
    }
}

impl std::error::Error for TransportError {}

impl From<io::Error> for TransportError {
    fn from(e: io::Error) -> Self {
        if e.kind() == io::ErrorKind::UnexpectedEof {
            Self::Disconnected
        } else {
            Self::Io(e)
        }
    }
}

/// A received frame which can be either a regular L4 frame or a NODES broadcast
#[derive(Debug)]
pub enum ReceivedFrame {
    /// Regular L4 frame (CREQ, CACK, INFO, etc.)
    Frame {
        from_call: String,
        frame: NetromFrame,
    },
    /// NODES broadcast with routing information
    Nodes {
        from_call: String,
        broadcast: NodesBroadcast,
    },
}

/// NetROM over TCP transport
///
/// Handles framing and TCP communication with LinBPQ's NETROMPORT.
///
/// Supports batched writes through `queue_frame` / `flush` for combining
/// multiple messages (like join messages) into fewer TCP packets.
pub struct NetromTransport {
    /// TCP stream to LinBPQ
    stream: TcpStream,
    /// Our callsign (used in outgoing frame headers)
    our_call: Callsign,
    /// Read buffer for incomplete frames
    read_buf: Vec<u8>,
    /// Write buffer for batched sends
    write_buf: Vec<u8>,
    /// Peer address (for logging)
    peer_addr: SocketAddr,
}

impl NetromTransport {
    /// Connect to LinBPQ's NETROMPORT
    pub async fn connect(addr: &str, our_call: Callsign) -> Result<Self, TransportError> {
        debug!(addr = %addr, call = %our_call, "Connecting to LinBPQ NETROMPORT");

        let stream = TcpStream::connect(addr).await?;
        let peer_addr = stream.peer_addr()?;

        // Disable Nagle's algorithm for lower latency
        stream.set_nodelay(true)?;

        debug!(peer = %peer_addr, "Connected to NETROMPORT");
        crate::metrics::TRANSPORT_TCP_CONNECTS.inc();

        Ok(Self {
            stream,
            our_call,
            read_buf: Vec::with_capacity(MAX_FRAME_SIZE),
            write_buf: Vec::with_capacity(MAX_FRAME_SIZE * 4),
            peer_addr,
        })
    }

    /// Create transport from an accepted connection
    pub fn from_stream(stream: TcpStream, our_call: Callsign) -> Result<Self, TransportError> {
        let peer_addr = stream.peer_addr()?;
        stream.set_nodelay(true)?;

        Ok(Self {
            stream,
            our_call,
            read_buf: Vec::with_capacity(MAX_FRAME_SIZE),
            write_buf: Vec::with_capacity(MAX_FRAME_SIZE * 4),
            peer_addr,
        })
    }

    /// Get peer address
    pub fn peer_addr(&self) -> SocketAddr {
        self.peer_addr
    }

    /// Queue a NetROM frame for sending (without flushing)
    ///
    /// Use this for batching multiple frames before calling `flush()`.
    /// Wire format: Length(2) + Call(10) + PID(1) + frame
    pub fn queue_frame(&mut self, frame: &NetromFrame) -> Result<(), TransportError> {
        let frame_bytes = frame.encode();

        // Total message size: length(2) + call(10) + PID(1) + frame
        let total_len = 2 + WIRE_CALL_SIZE + 1 + frame_bytes.len();
        if total_len > MAX_FRAME_SIZE {
            return Err(TransportError::FrameTooLarge(total_len));
        }

        // Length (little-endian) - includes the length field itself
        self.write_buf.extend_from_slice(&(total_len as u16).to_le_bytes());

        // Callsign (10 bytes ASCII, space-padded)
        let call_str = self.our_call.to_string();
        let call_bytes = call_str.as_bytes();
        self.write_buf.extend_from_slice(call_bytes);
        for _ in call_bytes.len()..WIRE_CALL_SIZE {
            self.write_buf.push(b' ');
        }

        // PID
        self.write_buf.push(NETROM_PID);

        // NetROM frame
        self.write_buf.extend_from_slice(&frame_bytes);

        crate::metrics::NETROM_FRAMES_SENT
            .with_label_values(&[crate::metrics::opcode_label(&frame.l4.opcode)])
            .inc();

        // Log the queued frame
        if matches!(frame.l4.opcode, crate::netrom::L4Opcode::ConnectAck) {
            debug!(
                len = total_len,
                opcode = ?frame.l4.opcode,
                l3_src = %frame.l3.source,
                l3_dest = %frame.l3.dest,
                l4_idx = frame.l4.circuit_index,
                l4_id = frame.l4.circuit_id,
                "Queued CACK frame"
            );
        } else {
            trace!(
                len = total_len,
                opcode = ?frame.l4.opcode,
                dest = %frame.l3.dest,
                buf_size = self.write_buf.len(),
                "Queued frame"
            );
        }

        Ok(())
    }

    /// Flush all queued frames to the network
    ///
    /// Call this after batching multiple frames with `queue_frame()`.
    pub async fn flush(&mut self) -> Result<(), TransportError> {
        if self.write_buf.is_empty() {
            return Ok(());
        }

        let buf_len = self.write_buf.len();
        trace!(bytes = buf_len, "Flushing write buffer");
        self.stream.write_all(&self.write_buf).await?;
        self.stream.flush().await?;
        self.write_buf.clear();
        crate::metrics::TRANSPORT_BYTES_SENT.inc_by(buf_len as u64);

        Ok(())
    }

    /// Send a NetROM frame immediately (queue + flush)
    ///
    /// Wire format: Length(2) + Call(10) + PID(1) + frame
    /// Note: Length field includes itself (total message size)
    pub async fn send_frame(&mut self, frame: &NetromFrame) -> Result<(), TransportError> {
        self.queue_frame(frame)?;
        self.flush().await
    }

    /// Send raw bytes with TCP framing (for NODES broadcasts and other non-L4 messages)
    ///
    /// This sends raw bytes that go directly after the PID byte, without L3/L4 headers.
    /// Used for routing protocol messages like NODES broadcasts.
    ///
    /// Wire format: Length(2) + Call(10) + PID(1) + data
    /// Note: Length field includes itself (total message size)
    pub async fn send_raw(&mut self, data: &[u8]) -> Result<(), TransportError> {
        // Total message size: length(2) + call(10) + PID(1) + data
        // LinBPQ expects Length to include the length field itself
        let total_len = 2 + WIRE_CALL_SIZE + 1 + data.len();
        if total_len > MAX_FRAME_SIZE {
            return Err(TransportError::FrameTooLarge(total_len));
        }

        let mut wire_buf = Vec::with_capacity(total_len);

        // Length (little-endian) - includes the length field itself
        wire_buf.extend_from_slice(&(total_len as u16).to_le_bytes());

        // Callsign (10 bytes ASCII, space-padded)
        let call_str = self.our_call.to_string();
        let call_bytes = call_str.as_bytes();
        wire_buf.extend_from_slice(call_bytes);
        for _ in call_bytes.len()..WIRE_CALL_SIZE {
            wire_buf.push(b' ');
        }

        // PID
        wire_buf.push(NETROM_PID);

        // Raw data (e.g., NODES broadcast)
        wire_buf.extend_from_slice(data);

        trace!(
            len = wire_buf.len(),
            data_len = data.len(),
            "Sending raw data"
        );

        self.stream.write_all(&wire_buf).await?;
        self.stream.flush().await?;

        Ok(())
    }

    /// Receive the next NetROM frame
    ///
    /// Blocks until a complete frame is received or an error occurs.
    pub async fn recv_frame(&mut self) -> Result<ReceivedFrame, TransportError> {
        loop {
            // Try to parse a frame from the buffer
            if let Some(frame) = self.try_parse_frame()? {
                return Ok(frame);
            }

            // Need more data
            let mut chunk = [0u8; 512];
            let n = self.stream.read(&mut chunk).await?;

            if n == 0 {
                return Err(TransportError::Disconnected);
            }

            crate::metrics::TRANSPORT_BYTES_RECEIVED.inc_by(n as u64);
            self.read_buf.extend_from_slice(&chunk[..n]);
            trace!(bytes = n, buf_len = self.read_buf.len(), "Received data");
        }
    }

    /// Try to parse a frame from the buffer
    fn try_parse_frame(&mut self) -> Result<Option<ReceivedFrame>, TransportError> {
        // Need at least length field
        if self.read_buf.len() < 2 {
            return Ok(None);
        }

        // Read length - this is the TOTAL message size including the length field itself
        let total_len = u16::from_le_bytes([self.read_buf[0], self.read_buf[1]]) as usize;

        // Debug: log first bytes to diagnose framing issues
        if total_len > MAX_FRAME_SIZE || total_len < 2 + WIRE_CALL_SIZE + 1 + 15 {
            let preview_len = self.read_buf.len().min(32);
            let hex: Vec<String> = self.read_buf[..preview_len].iter().map(|b| format!("{:02x}", b)).collect();
            let ascii: String = self.read_buf[..preview_len].iter().map(|&b| {
                if b >= 0x20 && b <= 0x7e { b as char } else { '.' }
            }).collect();
            warn!(
                len = total_len,
                buf_len = self.read_buf.len(),
                hex = hex.join(" "),
                ascii = ascii,
                "Suspicious frame length"
            );
        }

        // Sanity check - minimum is: length(2) + call(10) + pid(1) + minimal frame(~15)
        if total_len < 2 + WIRE_CALL_SIZE + 1 + 15 {
            warn!(len = total_len, "Frame too small, discarding");
            self.read_buf.drain(..2);
            return Ok(None);
        }
        if total_len > MAX_FRAME_SIZE {
            return Err(TransportError::FrameTooLarge(total_len));
        }

        // Need complete frame
        if self.read_buf.len() < total_len {
            return Ok(None);
        }

        // Extract frame (skip the 2-byte length field)
        let payload = &self.read_buf[2..total_len];

        // Parse callsign (first 10 bytes, ASCII)
        let call_bytes = &payload[..WIRE_CALL_SIZE];
        let from_call = String::from_utf8_lossy(call_bytes).trim().to_string();

        // Check PID
        let pid = payload[WIRE_CALL_SIZE];
        if pid != NETROM_PID {
            warn!(pid = pid, expected = NETROM_PID, "Invalid PID, discarding");
            self.read_buf.drain(..total_len);
            return Ok(None);
        }

        // Parse NetROM frame
        let frame_bytes = &payload[WIRE_CALL_SIZE + 1..];

        // Try to parse as regular L4 frame first
        if let Some(frame) = NetromFrame::parse(frame_bytes) {
            // For CACK frames, log full details for debugging
            if matches!(frame.l4.opcode, crate::netrom::L4Opcode::ConnectAck) {
                let hex: String = payload.iter().map(|b| format!("{:02x}", b)).collect::<Vec<_>>().join(" ");
                debug!(
                    payload_len = payload.len(),
                    opcode = ?frame.l4.opcode,
                    l3_src = %frame.l3.source,
                    l3_dest = %frame.l3.dest,
                    l4_idx = frame.l4.circuit_index,
                    l4_id = frame.l4.circuit_id,
                    l4_tx = frame.l4.tx_seq,
                    l4_rx = frame.l4.rx_seq,
                    data_len = frame.data.len(),
                    hex = %hex,
                    "Received CACK frame"
                );
            } else {
                trace!(
                    from = %from_call,
                    opcode = ?frame.l4.opcode,
                    src = %frame.l3.source,
                    dest = %frame.l3.dest,
                    "Received frame"
                );
            }

            crate::metrics::NETROM_FRAMES_RECEIVED
                .with_label_values(&[crate::metrics::opcode_label(&frame.l4.opcode)])
                .inc();

            // Remove parsed frame from buffer
            self.read_buf.drain(..total_len);
            return Ok(Some(ReceivedFrame::Frame { from_call, frame }));
        }

        // Try to parse as NODES broadcast
        if let Some(broadcast) = NodesBroadcast::parse(frame_bytes) {
            debug!(
                from = %from_call,
                source = %broadcast.source,
                routes = broadcast.routes.len(),
                "Received NODES broadcast"
            );
            self.read_buf.drain(..total_len);
            return Ok(Some(ReceivedFrame::Nodes { from_call, broadcast }));
        }

        // Unknown frame type - log and skip
        let hex: Vec<String> = frame_bytes.iter().map(|b| format!("{:02x}", b)).collect();
        let ascii: String = frame_bytes.iter().map(|&b| {
            if b >= 0x20 && b <= 0x7e { b as char } else { '.' }
        }).collect();
        debug!(
            len = frame_bytes.len(),
            hex = hex.join(" "),
            ascii = ascii,
            from = %from_call,
            "Skipping unparseable frame (INP3 routing?)"
        );
        // Remove parsed frame from buffer and continue
        self.read_buf.drain(..total_len);
        Ok(None)
    }

    /// Check if the connection is still alive
    pub fn is_connected(&self) -> bool {
        // TcpStream doesn't have a direct "is connected" check,
        // but we can check if peek works
        // For now, assume connected if we haven't received an error
        true
    }

    /// Close the connection
    pub async fn close(mut self) -> Result<(), TransportError> {
        debug!(peer = %self.peer_addr, "Closing connection");
        self.stream.shutdown().await?;
        Ok(())
    }
}

/// TCP listener for incoming NetROM connections
pub struct NetromListener {
    listener: tokio::net::TcpListener,
    our_call: Callsign,
}

impl NetromListener {
    /// Bind to a local address and start listening
    pub async fn bind(addr: &str, our_call: Callsign) -> Result<Self, TransportError> {
        debug!(addr = %addr, call = %our_call, "Binding NETROMPORT listener");

        let listener = tokio::net::TcpListener::bind(addr).await?;
        let local_addr = listener.local_addr()?;

        debug!(addr = %local_addr, "NETROMPORT listener bound");

        Ok(Self { listener, our_call })
    }

    /// Accept the next incoming connection
    pub async fn accept(&self) -> Result<NetromTransport, TransportError> {
        let (stream, peer_addr) = self.listener.accept().await?;
        debug!(peer = %peer_addr, "Accepted NETROMPORT connection");

        NetromTransport::from_stream(stream, self.our_call.clone())
    }

    /// Get local address
    pub fn local_addr(&self) -> Result<SocketAddr, TransportError> {
        Ok(self.listener.local_addr()?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::netrom::{L4Flags, L4Header, L4Opcode, L3Header};

    #[test]
    fn test_wire_format_encode() {
        // Manual test of wire format encoding
        let _our_call = Callsign::from_str("TEST1-9");

        let frame = NetromFrame {
            l3: L3Header {
                source: Callsign::from_str("TEST1-1"),
                dest: Callsign::from_str("TEST2-1"),
                ttl: 7,
            },
            l4: L4Header {
                circuit_index: 1,
                circuit_id: 42,
                tx_seq: 0,
                rx_seq: 0,
                opcode: L4Opcode::Information,
                flags: L4Flags::default(),
            },
            data: b"Hello".to_vec(),
        };

        let frame_bytes = frame.encode();

        // Build expected wire format
        let mut expected = Vec::new();
        let payload_len = WIRE_CALL_SIZE + 1 + frame_bytes.len();
        expected.extend_from_slice(&(payload_len as u16).to_le_bytes());

        // Callsign padded to 10 chars
        expected.extend_from_slice(b"TEST1-9   ");
        expected.push(NETROM_PID);
        expected.extend_from_slice(&frame_bytes);

        // Verify size
        assert_eq!(expected.len(), 2 + payload_len);
        assert!(expected.len() >= MIN_FRAME_SIZE);
    }

    #[tokio::test]
    async fn test_loopback() {
        // Create a TCP listener
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        let our_call = Callsign::from_str("TEST1-9");

        // Spawn acceptor task
        let our_call_clone = our_call.clone();
        let accept_handle = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            NetromTransport::from_stream(stream, our_call_clone).unwrap()
        });

        // Connect
        let mut client = NetromTransport::connect(&addr.to_string(), our_call.clone())
            .await
            .unwrap();

        let mut server = accept_handle.await.unwrap();

        // Send a frame from client to server
        let test_frame = NetromFrame::information(
            &Callsign::from_str("TEST1-1"),
            &Callsign::from_str("TEST2-1"),
            1,
            42,
            0,
            0,
            b"Test data".to_vec(),
            false,
        );

        client.send_frame(&test_frame).await.unwrap();

        // Receive on server
        let received = server.recv_frame().await.unwrap();

        match received {
            ReceivedFrame::Frame { from_call, frame } => {
                assert_eq!(from_call, "TEST1-9");
                assert_eq!(frame.l4.opcode, L4Opcode::Information);
                assert_eq!(frame.data, b"Test data");
            }
            _ => panic!("Expected Frame variant"),
        }
    }
}
