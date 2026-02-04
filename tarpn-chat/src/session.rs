//! NetROM L4 session state machine
//!
//! This module implements the transport layer session management for NetROM.
//! Each session represents a connection between two user callsigns (not nodes).
//!
//! Sessions progress through states:
//! - Disconnected: No active connection
//! - Connecting: CREQ sent, awaiting CACK
//! - Connected: Active data transfer
//! - Disconnecting: DREQ sent, awaiting DACK
//!
//! The session handles sequence numbers, flow control, and retransmission.

use std::collections::VecDeque;
use std::time::{Duration, Instant};
use tracing::{debug, trace, warn};

use crate::netrom::{
    Callsign, ConnectAck, ConnectRequest, L4Flags, L4Header, L4Opcode, NetromFrame,
    DEFAULT_TTL, DEFAULT_WINDOW, MAX_L4_DATA,
};

/// Session state
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SessionState {
    /// No active connection
    Disconnected,
    /// CREQ sent, waiting for CACK
    Connecting,
    /// Active session
    Connected,
    /// DREQ sent, waiting for DACK
    Disconnecting,
}

/// Unique session identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct SessionId {
    /// Our circuit index
    pub our_index: u8,
    /// Our circuit ID
    pub our_id: u8,
}

impl SessionId {
    pub fn new(index: u8, id: u8) -> Self {
        Self {
            our_index: index,
            our_id: id,
        }
    }
}

impl std::fmt::Display for SessionId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}:{}", self.our_index, self.our_id)
    }
}

/// A frame waiting to be acknowledged
#[derive(Debug, Clone)]
struct UnackedFrame {
    seq: u8,
    data: Vec<u8>,
    sent_at: Instant,
    retries: u8,
}

/// Event returned by session when handling frames
#[derive(Debug)]
pub enum SessionEvent {
    /// Session connected successfully
    Connected,
    /// Session disconnected (clean or error)
    Disconnected { reason: String },
    /// Data received from peer
    DataReceived(Vec<u8>),
    /// Frames to transmit
    Transmit(Vec<NetromFrame>),
}

/// L4 session state machine
pub struct L4Session {
    /// Session identifier
    pub id: SessionId,
    /// Current state
    pub state: SessionState,
    /// Our user callsign (e.g., WA2M-9 for chat)
    pub local_user: Callsign,
    /// Remote user callsign
    pub remote_user: Callsign,
    /// Our node callsign (e.g., WA2M-1)
    pub local_node: Callsign,
    /// Remote node callsign
    pub remote_node: Callsign,
    /// Their circuit index
    pub their_index: u8,
    /// Their circuit ID
    pub their_id: u8,
    /// Next transmit sequence number
    tx_seq: u8,
    /// Expected receive sequence number
    rx_seq: u8,
    /// Agreed window size
    window: u8,
    /// Frames waiting to be ACKed
    unacked: VecDeque<UnackedFrame>,
    /// Received data waiting to be delivered (for future use with fragmentation)
    #[allow(dead_code)]
    rx_queue: VecDeque<Vec<u8>>,
    /// Data waiting to be sent (fragmented into window-sized chunks)
    tx_queue: VecDeque<Vec<u8>>,
    /// Session timeout value (from CREQ)
    timeout: Duration,
    /// Time of last activity
    last_activity: Instant,
    /// Retry timeout
    retry_timeout: Duration,
    /// Maximum retries
    max_retries: u8,
    /// Created time (for diagnostics)
    #[allow(dead_code)]
    created_at: Instant,
    /// Whether this is an outbound session (we sent CREQ)
    is_outbound: bool,
}

impl L4Session {
    /// Create a new session for an outbound connection
    ///
    /// # Arguments
    /// * `session_timeout` - Inactivity timeout in seconds (like LinBPQ's L4LIMIT)
    /// * `t1_timeout` - T1 retransmission timeout in seconds
    pub fn new_outbound(
        id: SessionId,
        local_user: Callsign,
        local_node: Callsign,
        remote_user: Callsign,
        remote_node: Callsign,
        session_timeout: Duration,
        t1_timeout: Duration,
    ) -> Self {
        Self {
            id,
            state: SessionState::Disconnected,
            local_user,
            remote_user,
            local_node,
            remote_node,
            their_index: 0,
            their_id: 0,
            tx_seq: 0,
            rx_seq: 0,
            window: DEFAULT_WINDOW,
            unacked: VecDeque::new(),
            rx_queue: VecDeque::new(),
            tx_queue: VecDeque::new(),
            timeout: session_timeout,
            last_activity: Instant::now(),
            retry_timeout: t1_timeout,
            max_retries: 2,
            created_at: Instant::now(),
            is_outbound: true,
        }
    }

    /// Create a new session from an incoming CREQ
    ///
    /// # Arguments
    /// * `session_timeout` - Inactivity timeout (like LinBPQ's L4LIMIT)
    /// * `t1_timeout` - T1 retransmission timeout
    pub fn new_inbound(
        id: SessionId,
        local_user: Callsign,
        local_node: Callsign,
        creq_frame: &NetromFrame,
        session_timeout: Duration,
        t1_timeout: Duration,
    ) -> Option<Self> {
        let creq = ConnectRequest::parse(&creq_frame.data)?;

        let session = Self {
            id,
            state: SessionState::Connected, // Inbound goes straight to connected
            local_user,
            // Normalize the SSID encoding - LinBPQ sends with extra bits (0x60)
            // but expects clean SSID in responses
            remote_user: creq.origin_user.normalized(),
            local_node,
            remote_node: creq_frame.l3.source.normalized(),
            their_index: creq_frame.l4.circuit_index,
            their_id: creq_frame.l4.circuit_id,
            tx_seq: 0,
            rx_seq: 0,
            window: creq.window.min(DEFAULT_WINDOW),
            unacked: VecDeque::new(),
            rx_queue: VecDeque::new(),
            tx_queue: VecDeque::new(),
            timeout: session_timeout,
            last_activity: Instant::now(),
            retry_timeout: t1_timeout,
            max_retries: 2,
            created_at: Instant::now(),
            is_outbound: false,
        };

        debug!(
            id = %session.id,
            remote_user = %session.remote_user,
            remote_node = %session.remote_node,
            window = session.window,
            "Created inbound session"
        );

        Some(session)
    }

    /// Start an outbound connection
    pub fn connect(&mut self) -> Vec<NetromFrame> {
        if self.state != SessionState::Disconnected {
            warn!(id = %self.id, state = ?self.state, "Cannot connect: wrong state");
            return vec![];
        }

        debug!(
            id = %self.id,
            remote_user = %self.remote_user,
            remote_node = %self.remote_node,
            "Starting outbound connection"
        );

        self.state = SessionState::Connecting;
        self.last_activity = Instant::now();

        // CREQ timeout is the T1 retransmission timer (in seconds per LinBPQ)
        // Use our configured retry_timeout (TARPN default: 120s)
        let t1_seconds = self.retry_timeout.as_secs() as u16;

        let frame = NetromFrame::connect_request(
            &self.local_node,
            &self.remote_node,
            &self.local_user,
            self.id.our_index,
            self.id.our_id,
            self.window,
            t1_seconds,
        );

        vec![frame]
    }

    /// Generate a CACK response frame
    pub fn accept(&self) -> NetromFrame {
        debug!(
            id = %self.id,
            our_idx = self.id.our_index,
            our_id = self.id.our_id,
            their_idx = self.their_index,
            their_id = self.their_id,
            local_node = %self.local_node,
            remote_node = %self.remote_node,
            "Generating CACK"
        );
        NetromFrame::connect_ack(
            &self.local_node,
            &self.remote_node,
            self.id.our_index,
            self.id.our_id,
            self.their_index,
            self.their_id,
            self.window,
        )
    }

    /// Send data (queues for transmission)
    pub fn send(&mut self, data: &[u8]) -> Vec<NetromFrame> {
        if self.state != SessionState::Connected {
            warn!(id = %self.id, state = ?self.state, "Cannot send: not connected");
            return vec![];
        }

        // Fragment into chunks if needed
        for chunk in data.chunks(MAX_L4_DATA) {
            self.tx_queue.push_back(chunk.to_vec());
        }

        self.flush_tx_queue()
    }

    /// Flush pending transmit queue within window limits
    fn flush_tx_queue(&mut self) -> Vec<NetromFrame> {
        let mut frames = Vec::new();

        while !self.tx_queue.is_empty() && self.unacked.len() < self.window as usize {
            if let Some(data) = self.tx_queue.pop_front() {
                let seq = self.tx_seq;
                self.tx_seq = self.tx_seq.wrapping_add(1);

                let frame = NetromFrame::information(
                    &self.local_node,
                    &self.remote_node,
                    self.their_index,
                    self.their_id,
                    seq,
                    self.rx_seq,
                    data.clone(),
                    false,
                );

                self.unacked.push_back(UnackedFrame {
                    seq,
                    data,
                    sent_at: Instant::now(),
                    retries: 0,
                });

                debug!(
                    id = %self.id,
                    tx_seq = seq,
                    rx_seq = self.rx_seq,
                    unacked_count = self.unacked.len(),
                    "Sending new INFO frame"
                );
                frames.push(frame);
            }
        }

        frames
    }

    /// Handle an incoming L4 frame
    pub fn handle_frame(&mut self, frame: &NetromFrame) -> Vec<SessionEvent> {
        self.last_activity = Instant::now();
        let mut events = Vec::new();

        match frame.l4.opcode {
            L4Opcode::ConnectAck => {
                events.extend(self.handle_cack(frame));
            }
            L4Opcode::DisconnectRequest => {
                events.extend(self.handle_dreq(frame));
            }
            L4Opcode::DisconnectAck => {
                events.extend(self.handle_dack());
            }
            L4Opcode::Information => {
                events.extend(self.handle_info(frame));
            }
            L4Opcode::InformationAck => {
                events.extend(self.handle_iack(frame));
            }
            _ => {
                trace!(id = %self.id, opcode = ?frame.l4.opcode, "Ignoring frame");
            }
        }

        events
    }

    fn handle_cack(&mut self, frame: &NetromFrame) -> Vec<SessionEvent> {
        if self.state != SessionState::Connecting {
            warn!(id = %self.id, state = ?self.state, "CACK in wrong state");
            return vec![];
        }

        // Parse CACK payload (just contains window byte)
        if let Some(cack) = ConnectAck::parse(&frame.data) {
            self.their_index = frame.l4.tx_seq; // CACK uses tx_seq for their index
            self.their_id = frame.l4.rx_seq;    // CACK uses rx_seq for their id
            self.window = self.window.min(cack.window);
            // Note: remote_user was already set when we created the outbound session
        }

        self.state = SessionState::Connected;
        debug!(
            id = %self.id,
            their_index = self.their_index,
            their_id = self.their_id,
            "Session connected"
        );

        let mut events = vec![SessionEvent::Connected];

        // Flush any pending data
        let frames = self.flush_tx_queue();
        if !frames.is_empty() {
            events.push(SessionEvent::Transmit(frames));
        }

        events
    }

    fn handle_dreq(&mut self, _frame: &NetromFrame) -> Vec<SessionEvent> {
        debug!(id = %self.id, "Received DREQ");

        let dack = NetromFrame::disconnect_ack(
            &self.local_node,
            &self.remote_node,
            self.their_index,
            self.their_id,
        );

        self.state = SessionState::Disconnected;

        vec![
            SessionEvent::Transmit(vec![dack]),
            SessionEvent::Disconnected {
                reason: "Remote disconnect".to_string(),
            },
        ]
    }

    fn handle_dack(&mut self) -> Vec<SessionEvent> {
        if self.state != SessionState::Disconnecting {
            return vec![];
        }

        debug!(id = %self.id, "Received DACK");
        self.state = SessionState::Disconnected;

        vec![SessionEvent::Disconnected {
            reason: "Disconnect acknowledged".to_string(),
        }]
    }

    fn handle_info(&mut self, frame: &NetromFrame) -> Vec<SessionEvent> {
        if self.state != SessionState::Connected {
            warn!(id = %self.id, state = ?self.state, "INFO in wrong state");
            return vec![];
        }

        let seq = frame.l4.tx_seq;
        let piggybacked_ack = frame.l4.rx_seq;

        debug!(
            id = %self.id,
            their_seq = seq,
            their_ack = piggybacked_ack,
            our_rx_seq = self.rx_seq,
            unacked_count = self.unacked.len(),
            "Received INFO frame"
        );

        // Check sequence number
        if seq == self.rx_seq {
            trace!(id = %self.id, seq, "Received INFO in sequence");

            self.rx_seq = self.rx_seq.wrapping_add(1);

            // Process their ACK of our frames
            self.process_ack(frame.l4.rx_seq);

            // Queue data for delivery
            let mut events = Vec::new();
            if !frame.data.is_empty() {
                events.push(SessionEvent::DataReceived(frame.data.clone()));
            }

            // Send ACK
            let ack = NetromFrame::information_ack(
                &self.local_node,
                &self.remote_node,
                self.their_index,
                self.their_id,
                self.rx_seq,
            );
            events.push(SessionEvent::Transmit(vec![ack]));

            // Flush any pending transmits
            let tx_frames = self.flush_tx_queue();
            if !tx_frames.is_empty() {
                events.push(SessionEvent::Transmit(tx_frames));
            }

            events
        } else {
            // Distinguish duplicate (already received) from gap (future frame)
            // Like LinBPQ: FramesMissing = received_seq - expected_seq
            let diff = seq.wrapping_sub(self.rx_seq) as i16;
            let frames_missing = if diff > 128 { diff - 256 } else { diff };

            if frames_missing < 0 {
                // Duplicate/repeat - already processed this frame
                // Send plain IACK (no NAK) to re-confirm our rx_seq
                debug!(id = %self.id, expected = self.rx_seq, got = seq, "Duplicate frame, re-ACKing");
                crate::metrics::NETROM_DUPLICATES.inc();

                let ack = NetromFrame::information_ack(
                    &self.local_node,
                    &self.remote_node,
                    self.their_index,
                    self.their_id,
                    self.rx_seq,
                );
                vec![SessionEvent::Transmit(vec![ack])]
            } else {
                // Gap - frames were skipped, send NAK to request retransmit
                warn!(id = %self.id, expected = self.rx_seq, got = seq, frames_missing, "Gap detected, sending NAK");
                crate::metrics::NETROM_NAKS_SENT.inc();

                let nak = NetromFrame {
                    l3: crate::netrom::L3Header {
                        source: self.local_node.clone(),
                        dest: self.remote_node.clone(),
                        ttl: DEFAULT_TTL,
                    },
                    l4: L4Header {
                        circuit_index: self.their_index,
                        circuit_id: self.their_id,
                        tx_seq: 0,
                        rx_seq: self.rx_seq,
                        opcode: L4Opcode::InformationAck,
                        flags: L4Flags {
                            nak: true,
                            ..Default::default()
                        },
                    },
                    data: Vec::new(),
                };

                vec![SessionEvent::Transmit(vec![nak])]
            }
        }
    }

    fn handle_iack(&mut self, frame: &NetromFrame) -> Vec<SessionEvent> {
        if self.state != SessionState::Connected {
            return vec![];
        }

        let ack_seq = frame.l4.rx_seq;
        debug!(
            id = %self.id,
            ack_seq,
            unacked_count = self.unacked.len(),
            nak = frame.l4.flags.nak,
            "Received standalone IACK"
        );

        // Handle NAK
        if frame.l4.flags.nak {
            warn!(id = %self.id, ack_seq, "Received NAK");
            // Retransmit unacked frames
            return self.retransmit_from(ack_seq);
        }

        self.process_ack(ack_seq);

        // Flush more data if we have it
        let frames = self.flush_tx_queue();
        if !frames.is_empty() {
            vec![SessionEvent::Transmit(frames)]
        } else {
            vec![]
        }
    }

    fn process_ack(&mut self, ack_seq: u8) {
        // Remove acked frames from unacked queue
        // ACK means "I've received up to ack_seq - 1"
        let initial_count = self.unacked.len();
        while let Some(front) = self.unacked.front() {
            // Calculate if this frame is acked
            // Frame is acked if its seq < ack_seq (with wraparound handling)
            let diff = ack_seq.wrapping_sub(front.seq);
            if diff > 0 && diff < 128 {
                // Acked
                debug!(id = %self.id, seq = front.seq, ack_seq, "Frame acknowledged");
                self.unacked.pop_front();
            } else {
                break;
            }
        }
        if initial_count > 0 && self.unacked.is_empty() {
            debug!(id = %self.id, "All frames acknowledged, unacked queue empty");
        } else if !self.unacked.is_empty() {
            debug!(
                id = %self.id,
                ack_seq,
                remaining = self.unacked.len(),
                first_unacked = self.unacked.front().map(|f| f.seq),
                "Processed ACK, frames still pending"
            );
        }
    }

    fn retransmit_from(&mut self, from_seq: u8) -> Vec<SessionEvent> {
        let mut frames = Vec::new();

        for unacked in &mut self.unacked {
            if unacked.retries >= self.max_retries {
                // Too many retries, disconnect
                return vec![SessionEvent::Disconnected {
                    reason: "Max retries exceeded".to_string(),
                }];
            }

            // Retransmit if seq >= from_seq
            let diff = unacked.seq.wrapping_sub(from_seq);
            if diff < 128 {
                unacked.retries += 1;
                unacked.sent_at = Instant::now();
                crate::metrics::NETROM_RETRANSMISSIONS.inc();

                let frame = NetromFrame::information(
                    &self.local_node,
                    &self.remote_node,
                    self.their_index,
                    self.their_id,
                    unacked.seq,
                    self.rx_seq,
                    unacked.data.clone(),
                    false,
                );

                debug!(id = %self.id, seq = unacked.seq, retries = unacked.retries, max_retries = self.max_retries, "Retransmitting frame");
                frames.push(frame);
            }
        }

        if frames.is_empty() {
            vec![]
        } else {
            vec![SessionEvent::Transmit(frames)]
        }
    }

    /// Initiate disconnect
    pub fn disconnect(&mut self) -> Vec<NetromFrame> {
        if self.state == SessionState::Disconnected {
            return vec![];
        }

        debug!(id = %self.id, "Disconnecting");
        self.state = SessionState::Disconnecting;
        // Reset activity timer so disconnect timeout starts fresh
        self.last_activity = Instant::now();

        vec![NetromFrame::disconnect_request(
            &self.local_node,
            &self.remote_node,
            self.their_index,
            self.their_id,
        )]
    }

    /// Check for timeouts and generate retransmits
    pub fn tick(&mut self) -> Vec<SessionEvent> {
        // Already disconnected - nothing to do
        if self.state == SessionState::Disconnected {
            return vec![];
        }

        let now = Instant::now();

        // Check for session timeout
        // Don't timeout sessions in Disconnecting state - they're waiting for DACK
        // and we don't want to create "unknown session" errors for late frames
        if self.state != SessionState::Disconnecting
            && now.duration_since(self.last_activity) > self.timeout
        {
            warn!(id = %self.id, state = ?self.state, "Session timed out");
            self.state = SessionState::Disconnected;
            return vec![SessionEvent::Disconnected {
                reason: "Timeout".to_string(),
            }];
        }

        // For Disconnecting sessions, use a shorter timeout (T1 * max_retries)
        // to eventually give up waiting for DACK
        if self.state == SessionState::Disconnecting {
            let disconnect_timeout = self.retry_timeout * (self.max_retries as u32 + 1);
            if now.duration_since(self.last_activity) > disconnect_timeout {
                warn!(id = %self.id, "Disconnect timeout (no DACK received)");
                self.state = SessionState::Disconnected;
                return vec![SessionEvent::Disconnected {
                    reason: "Disconnect timeout".to_string(),
                }];
            }
        }

        // Check for retransmit timeout on unacked frames
        let mut need_retransmit = false;
        for unacked in &self.unacked {
            let elapsed = now.duration_since(unacked.sent_at);
            if elapsed > self.retry_timeout {
                debug!(
                    id = %self.id,
                    seq = unacked.seq,
                    elapsed_secs = elapsed.as_secs(),
                    t1_secs = self.retry_timeout.as_secs(),
                    retries = unacked.retries,
                    "Frame timeout, triggering retransmit"
                );
                need_retransmit = true;
                break;
            }
        }

        if need_retransmit {
            if let Some(first) = self.unacked.front() {
                return self.retransmit_from(first.seq);
            }
        }

        vec![]
    }

    /// Check if the session is idle (for cleanup)
    pub fn is_idle(&self, max_idle: Duration) -> bool {
        Instant::now().duration_since(self.last_activity) > max_idle
    }

    /// Get session state
    pub fn state(&self) -> SessionState {
        self.state
    }

    /// Check if this is an outbound session (we initiated)
    pub fn is_outbound(&self) -> bool {
        self.is_outbound
    }

    /// Get remote user callsign
    pub fn remote_user(&self) -> &Callsign {
        &self.remote_user
    }

    /// Get remote node callsign
    pub fn remote_node(&self) -> &Callsign {
        &self.remote_node
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_test_session() -> L4Session {
        L4Session::new_outbound(
            SessionId::new(1, 42),
            Callsign::from_str("TEST1-9"),
            Callsign::from_str("TEST1-1"),
            Callsign::from_str("TEST2-9"),
            Callsign::from_str("TEST2-1"),
            Duration::from_secs(900), // 15 min inactivity timeout
            Duration::from_secs(120), // 120s T1 retransmission timeout (TARPN L4TIMEOUT)
        )
    }

    #[test]
    fn test_connect_sequence() {
        let mut session = make_test_session();

        // Initial state
        assert_eq!(session.state, SessionState::Disconnected);

        // Start connect
        let frames = session.connect();
        assert_eq!(frames.len(), 1);
        assert_eq!(frames[0].l4.opcode, L4Opcode::ConnectRequest);
        assert_eq!(session.state, SessionState::Connecting);

        // Receive CACK
        let cack = NetromFrame::connect_ack(
            &Callsign::from_str("TEST2-1"),
            &Callsign::from_str("TEST1-1"),
            2, // their index
            99, // their id
            1, // our index (in tx_seq)
            42, // our id (in rx_seq)
            4,
        );

        let events = session.handle_frame(&cack);
        assert!(events.iter().any(|e| matches!(e, SessionEvent::Connected)));
        assert_eq!(session.state, SessionState::Connected);
        assert_eq!(session.their_index, 2);
        assert_eq!(session.their_id, 99);
    }

    #[test]
    fn test_data_transfer() {
        let mut session = make_test_session();
        session.state = SessionState::Connected;
        session.their_index = 2;
        session.their_id = 99;

        // Send data
        let frames = session.send(b"Hello, world!");
        assert_eq!(frames.len(), 1);
        assert_eq!(frames[0].l4.opcode, L4Opcode::Information);
        assert_eq!(frames[0].l4.tx_seq, 0);
        assert_eq!(session.unacked.len(), 1);

        // Receive ACK
        let ack = NetromFrame::information_ack(
            &Callsign::from_str("TEST2-1"),
            &Callsign::from_str("TEST1-1"),
            1,
            42,
            1, // ack seq 0
        );

        session.handle_frame(&ack);
        assert_eq!(session.unacked.len(), 0);
    }

    #[test]
    fn test_disconnect() {
        let mut session = make_test_session();
        session.state = SessionState::Connected;
        session.their_index = 2;
        session.their_id = 99;

        // Initiate disconnect
        let frames = session.disconnect();
        assert_eq!(frames.len(), 1);
        assert_eq!(frames[0].l4.opcode, L4Opcode::DisconnectRequest);
        assert_eq!(session.state, SessionState::Disconnecting);

        // Receive DACK
        let dack = NetromFrame::disconnect_ack(
            &Callsign::from_str("TEST2-1"),
            &Callsign::from_str("TEST1-1"),
            1,
            42,
        );

        let events = session.handle_frame(&dack);
        assert!(events.iter().any(|e| matches!(e, SessionEvent::Disconnected { .. })));
        assert_eq!(session.state, SessionState::Disconnected);
    }

    #[test]
    fn test_inbound_session() {
        // Create a CREQ frame
        let creq = NetromFrame::connect_request(
            &Callsign::from_str("TEST2-1"),
            &Callsign::from_str("TEST1-1"),
            &Callsign::from_str("TEST2-9"),
            2,
            99,
            4,
            300,
        );

        let session = L4Session::new_inbound(
            SessionId::new(1, 42),
            Callsign::from_str("TEST1-9"),
            Callsign::from_str("TEST1-1"),
            &creq,
            Duration::from_secs(900), // 15 min inactivity timeout
            Duration::from_secs(120), // 120s T1 retransmission timeout (TARPN L4TIMEOUT)
        );

        assert!(session.is_some());
        let session = session.unwrap();
        assert_eq!(session.state, SessionState::Connected);
        assert_eq!(session.remote_user.to_string(), "TEST2-9");
        assert_eq!(session.their_index, 2);
        assert_eq!(session.their_id, 99);
    }
}
