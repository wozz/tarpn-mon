//! NetROM L3/L4 protocol implementation
//!
//! This module implements the NetROM network and transport layer protocols
//! used by amateur radio packet networks. NetROM provides:
//! - L3 (Network): Routing between nodes via callsign addressing
//! - L4 (Transport): Reliable connection-oriented sessions
//!
//! Reference: LinBPQ source code (asmstrucs.h, L4Code.c, L3Code.c)

use std::fmt;

/// NetROM PID (Protocol ID) - marks frames as NetROM
pub const NETROM_PID: u8 = 0xCF;

/// Default TTL for L3 frames (hop count)
pub const DEFAULT_TTL: u8 = 24;

/// Default window size for L4 sessions (matches TARPN's L4WINDOW=3)
pub const DEFAULT_WINDOW: u8 = 3;

/// Maximum L4 data payload size
pub const MAX_L4_DATA: usize = 236;

/// L4 Opcodes (stored in low 4 bits of L4FLAGS)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum L4Opcode {
    ConnectRequest = 1,
    ConnectAck = 2,
    DisconnectRequest = 3,
    DisconnectAck = 4,
    Information = 5,
    InformationAck = 6,
    Reset = 7,         // Paula's extension
    ConnectRequestEx = 8, // Paula's extension
}

impl L4Opcode {
    pub fn from_flags(flags: u8) -> Option<Self> {
        match flags & 0x0F {
            1 => Some(Self::ConnectRequest),
            2 => Some(Self::ConnectAck),
            3 => Some(Self::DisconnectRequest),
            4 => Some(Self::DisconnectAck),
            5 => Some(Self::Information),
            6 => Some(Self::InformationAck),
            7 => Some(Self::Reset),
            8 => Some(Self::ConnectRequestEx),
            _ => None,
        }
    }
}

/// L4 Flags (stored in high 4 bits of L4FLAGS)
#[derive(Debug, Clone, Copy, Default)]
pub struct L4Flags {
    /// BNA (Busy, No Ack) - Don't send more data
    pub busy: bool,
    /// NAK - Negative acknowledgment
    pub nak: bool,
    /// MORE - More data follows (fragmentation)
    pub more: bool,
    /// COMP - Data is compressed (BPQ extension)
    pub compressed: bool,
}

impl L4Flags {
    pub fn from_byte(flags: u8) -> Self {
        Self {
            busy: (flags & 0x80) != 0,
            nak: (flags & 0x40) != 0,
            more: (flags & 0x20) != 0,
            compressed: (flags & 0x10) != 0,
        }
    }

    pub fn to_byte(&self) -> u8 {
        let mut flags = 0u8;
        if self.busy {
            flags |= 0x80;
        }
        if self.nak {
            flags |= 0x40;
        }
        if self.more {
            flags |= 0x20;
        }
        if self.compressed {
            flags |= 0x10;
        }
        flags
    }
}

/// AX.25-format callsign (7 bytes: 6 chars + SSID)
#[derive(Clone, PartialEq, Eq, Hash)]
pub struct Callsign {
    /// Raw bytes: 6 shifted ASCII chars + SSID byte
    pub raw: [u8; 7],
}

impl Callsign {
    /// Create a callsign from a string like "WA2M-9"
    pub fn from_str(s: &str) -> Self {
        let mut raw = [0x40u8; 7]; // Space shifted left = 0x40

        let (base, ssid) = if let Some(pos) = s.find('-') {
            let ssid_str = &s[pos + 1..];
            let ssid: u8 = ssid_str.parse().unwrap_or(0);
            (&s[..pos], ssid)
        } else {
            (s, 0u8)
        };

        // Copy base callsign (up to 6 chars), shifted left by 1 bit
        for (i, c) in base.chars().take(6).enumerate() {
            raw[i] = (c.to_ascii_uppercase() as u8) << 1;
        }

        // SSID byte: bits 1-4 contain SSID
        // LinBPQ uses (ssid << 1) without the 0x60 "reserved" bits that AX.25 uses
        raw[6] = ssid << 1;

        Self { raw }
    }

    /// Convert to display string like "WA2M-9"
    pub fn to_string(&self) -> String {
        let mut s = String::with_capacity(10);

        // Extract base callsign (6 chars, shifted right by 1)
        for i in 0..6 {
            let c = (self.raw[i] >> 1) as char;
            if c != ' ' {
                s.push(c);
            }
        }

        // Extract SSID from bits 1-4
        let ssid = (self.raw[6] >> 1) & 0x0F;
        if ssid != 0 {
            s.push('-');
            s.push_str(&ssid.to_string());
        }

        s
    }

    /// Create from raw 7-byte AX.25 format
    pub fn from_raw(raw: [u8; 7]) -> Self {
        Self { raw }
    }

    /// Check if this is a valid callsign (not empty/null)
    pub fn is_valid(&self) -> bool {
        // First char should be a letter or number when unshifted
        let first = (self.raw[0] >> 1) as char;
        first.is_ascii_alphanumeric()
    }

    /// Return a normalized copy with clean SSID encoding
    /// Strips the 0x60 reserved bits that AX.25 uses but NetROM over TCP does not
    pub fn normalized(&self) -> Self {
        let mut raw = self.raw;
        // Keep only the SSID (bits 1-4) in the SSID byte
        let ssid = (raw[6] >> 1) & 0x0F;
        raw[6] = ssid << 1;
        Self { raw }
    }
}

impl fmt::Debug for Callsign {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Callsign({})", self.to_string())
    }
}

impl fmt::Display for Callsign {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.to_string())
    }
}

/// L3 (Network layer) header
#[derive(Debug, Clone)]
pub struct L3Header {
    /// Source node callsign
    pub source: Callsign,
    /// Destination node callsign
    pub dest: Callsign,
    /// Time to live (hop count)
    pub ttl: u8,
}

impl L3Header {
    pub const SIZE: usize = 15; // 7 + 7 + 1

    pub fn parse(data: &[u8]) -> Option<Self> {
        if data.len() < Self::SIZE {
            return None;
        }

        let mut source_raw = [0u8; 7];
        let mut dest_raw = [0u8; 7];
        source_raw.copy_from_slice(&data[0..7]);
        dest_raw.copy_from_slice(&data[7..14]);

        Some(Self {
            source: Callsign::from_raw(source_raw),
            dest: Callsign::from_raw(dest_raw),
            ttl: data[14],
        })
    }

    pub fn encode(&self, buf: &mut Vec<u8>) {
        buf.extend_from_slice(&self.source.raw);
        buf.extend_from_slice(&self.dest.raw);
        buf.push(self.ttl);
    }
}

/// L4 (Transport layer) header
#[derive(Debug, Clone)]
pub struct L4Header {
    /// Circuit index (our side)
    pub circuit_index: u8,
    /// Circuit ID (our side)
    pub circuit_id: u8,
    /// Transmit sequence number
    pub tx_seq: u8,
    /// Receive (ACK) sequence number
    pub rx_seq: u8,
    /// Opcode
    pub opcode: L4Opcode,
    /// Flags
    pub flags: L4Flags,
}

impl L4Header {
    pub const SIZE: usize = 5;

    pub fn parse(data: &[u8]) -> Option<Self> {
        if data.len() < Self::SIZE {
            return None;
        }

        let opcode = L4Opcode::from_flags(data[4])?;
        let flags = L4Flags::from_byte(data[4]);

        Some(Self {
            circuit_index: data[0],
            circuit_id: data[1],
            tx_seq: data[2],
            rx_seq: data[3],
            opcode,
            flags,
        })
    }

    pub fn encode(&self, buf: &mut Vec<u8>) {
        buf.push(self.circuit_index);
        buf.push(self.circuit_id);
        buf.push(self.tx_seq);
        buf.push(self.rx_seq);
        buf.push(self.flags.to_byte() | (self.opcode as u8));
    }
}

/// Connect Request payload (in L4DATA)
#[derive(Debug, Clone)]
pub struct ConnectRequest {
    /// Proposed window size
    pub window: u8,
    /// Originating user callsign
    pub origin_user: Callsign,
    /// Originating node callsign (same as L3 source usually)
    pub origin_node: Callsign,
    /// T1 retransmission timeout (in seconds per LinBPQ - NOT 1/3-second units)
    pub timeout: u16,
    /// Compression supported flag
    pub compression: bool,
}

impl ConnectRequest {
    pub fn parse(data: &[u8]) -> Option<Self> {
        if data.len() < 17 {
            return None;
        }

        let mut origin_user_raw = [0u8; 7];
        let mut origin_node_raw = [0u8; 7];
        origin_user_raw.copy_from_slice(&data[1..8]);
        origin_node_raw.copy_from_slice(&data[8..15]);

        let timeout = u16::from_le_bytes([data[15], data[16] & 0xBF]);
        let compression = (data[16] & 0x40) != 0;

        Some(Self {
            window: data[0],
            origin_user: Callsign::from_raw(origin_user_raw),
            origin_node: Callsign::from_raw(origin_node_raw),
            timeout,
            compression,
        })
    }

    pub fn encode(&self, buf: &mut Vec<u8>) {
        buf.push(self.window);
        buf.extend_from_slice(&self.origin_user.raw);
        buf.extend_from_slice(&self.origin_node.raw);
        let timeout_bytes = self.timeout.to_le_bytes();
        buf.push(timeout_bytes[0]);
        let mut flags = timeout_bytes[1];
        if self.compression {
            flags |= 0x40;
        }
        buf.push(flags);
    }
}

/// Connect Acknowledge payload
/// CACK payload contains window byte + optional L3 TTL (LinBPQ sends both).
/// The user callsign was already exchanged in the CREQ.
#[derive(Debug, Clone)]
pub struct ConnectAck {
    /// Accepted window size
    pub window: u8,
    /// L3 TTL to use for this session (LinBPQ includes this)
    pub l3ttl: u8,
}

/// Default L3 TTL for CACK (LinBPQ uses 25)
pub const CACK_DEFAULT_TTL: u8 = 25;

impl ConnectAck {
    pub fn parse(data: &[u8]) -> Option<Self> {
        if data.is_empty() {
            return None;
        }

        Some(Self {
            window: data[0],
            // L3TTL is optional, default to 25 if not present
            l3ttl: data.get(1).copied().unwrap_or(CACK_DEFAULT_TTL),
        })
    }

    pub fn encode(&self, buf: &mut Vec<u8>) {
        buf.push(self.window);
        buf.push(self.l3ttl);
    }
}

/// Complete NetROM frame (L3 + L4 + data)
#[derive(Debug, Clone)]
pub struct NetromFrame {
    pub l3: L3Header,
    pub l4: L4Header,
    pub data: Vec<u8>,
}

/// NODES broadcast signature byte
pub const NODES_SIGNATURE: u8 = 0xFF;

/// A route entry in a NODES broadcast (21 bytes)
#[derive(Debug, Clone)]
pub struct NodesRouteEntry {
    /// Destination callsign (7 bytes AX.25 format)
    pub dest_call: Callsign,
    /// Destination alias (6 bytes ASCII, space-padded)
    pub dest_alias: [u8; 6],
    /// Best neighbour for this destination (7 bytes AX.25)
    pub neighbour: Callsign,
    /// Quality (0-255, 0 means remove route)
    pub quality: u8,
}

impl NodesRouteEntry {
    pub const SIZE: usize = 21;

    /// Create a route entry from callsign strings
    pub fn new(dest_call: &str, dest_alias: &str, neighbour: &str, quality: u8) -> Self {
        let mut alias_bytes = [0x20u8; 6]; // Space-padded
        for (i, c) in dest_alias.chars().take(6).enumerate() {
            alias_bytes[i] = c.to_ascii_uppercase() as u8;
        }

        Self {
            dest_call: Callsign::from_str(dest_call),
            dest_alias: alias_bytes,
            neighbour: Callsign::from_str(neighbour),
            quality,
        }
    }

    /// Encode to bytes (21 bytes)
    pub fn encode(&self, buf: &mut Vec<u8>) {
        buf.extend_from_slice(&self.dest_call.raw);
        buf.extend_from_slice(&self.dest_alias);
        buf.extend_from_slice(&self.neighbour.raw);
        buf.push(self.quality);
    }

    /// Parse from bytes
    pub fn parse(data: &[u8]) -> Option<Self> {
        if data.len() < Self::SIZE {
            return None;
        }

        let mut dest_raw = [0u8; 7];
        let mut alias = [0u8; 6];
        let mut neighbour_raw = [0u8; 7];

        dest_raw.copy_from_slice(&data[0..7]);
        alias.copy_from_slice(&data[7..13]);
        neighbour_raw.copy_from_slice(&data[13..20]);

        Some(Self {
            dest_call: Callsign::from_raw(dest_raw),
            dest_alias: alias,
            neighbour: Callsign::from_raw(neighbour_raw),
            quality: data[20],
        })
    }
}

/// NODES broadcast packet
///
/// NODES broadcasts have a special format:
/// - L3 header (15 bytes): source (7) + dest "NODES " (7) + TTL (1)
/// - 0xFF signature (1 byte)
/// - Sender alias (6 bytes ASCII, space-padded)
/// - Route entries (21 bytes each)
#[derive(Debug, Clone)]
pub struct NodesBroadcast {
    /// Source node callsign (L3 source)
    pub source: Callsign,
    /// Sending node's alias (6 bytes ASCII, space-padded)
    pub sender_alias: [u8; 6],
    /// Route entries
    pub routes: Vec<NodesRouteEntry>,
}

impl NodesBroadcast {
    /// Create a new NODES broadcast
    pub fn new(source_call: &str, sender_alias: &str) -> Self {
        let mut alias_bytes = [0x20u8; 6]; // Space-padded
        for (i, c) in sender_alias.chars().take(6).enumerate() {
            alias_bytes[i] = c.to_ascii_uppercase() as u8;
        }

        Self {
            source: Callsign::from_str(source_call),
            sender_alias: alias_bytes,
            routes: Vec::new(),
        }
    }

    /// Add a route entry announcing ourselves as a destination
    pub fn add_self_route(&mut self, our_call: &str, our_alias: &str, quality: u8) {
        // When announcing ourselves, we are both the destination AND the neighbour
        // (i.e., to reach us, go through us - we're directly reachable)
        self.routes.push(NodesRouteEntry::new(
            our_call,
            our_alias,
            our_call, // neighbour = self for direct destination
            quality,
        ));
    }

    /// Encode to bytes including L3 header
    /// Format: L3 header (15) + 0xFF + alias (6) + routes (21 each)
    pub fn encode(&self) -> Vec<u8> {
        let mut buf = Vec::with_capacity(L3Header::SIZE + 7 + self.routes.len() * NodesRouteEntry::SIZE);

        // L3 header with destination "NODES " (broadcast address)
        let dest = Callsign::from_str("NODES");
        let l3 = L3Header {
            source: self.source.clone(),
            dest,
            ttl: DEFAULT_TTL,
        };
        l3.encode(&mut buf);

        // NODES signature
        buf.push(NODES_SIGNATURE);

        // Sender alias
        buf.extend_from_slice(&self.sender_alias);

        // Route entries
        for route in &self.routes {
            route.encode(&mut buf);
        }
        buf
    }

    /// Parse from bytes (expects L3 header + 0xFF + data)
    pub fn parse(data: &[u8]) -> Option<Self> {
        if data.len() < L3Header::SIZE + 7 {
            return None;
        }

        let l3 = L3Header::parse(data)?;

        // Check for NODES signature after L3 header
        if data[L3Header::SIZE] != NODES_SIGNATURE {
            return None;
        }

        let mut sender_alias = [0u8; 6];
        sender_alias.copy_from_slice(&data[L3Header::SIZE + 1..L3Header::SIZE + 7]);

        let mut routes = Vec::new();
        let mut offset = L3Header::SIZE + 7;
        while offset + NodesRouteEntry::SIZE <= data.len() {
            if let Some(entry) = NodesRouteEntry::parse(&data[offset..]) {
                routes.push(entry);
            }
            offset += NodesRouteEntry::SIZE;
        }

        Some(Self {
            source: l3.source,
            sender_alias,
            routes,
        })
    }
}

/// INP3 RIF (Routing Information Frame) entry
/// Used to announce a destination (callsign) to a neighbor via TCP NETROMPORT
#[derive(Debug, Clone)]
pub struct Inp3RifEntry {
    /// Destination callsign (7 bytes AX.25)
    pub call: Callsign,
    /// Hop count (1 = directly connected)
    pub hops: u8,
    /// Round-trip time in 10ms units (0 for locally hosted)
    pub rtt: u16,
    /// Alias (up to 6 chars)
    pub alias: String,
}

impl Inp3RifEntry {
    /// Create a new RIF entry for announcing ourselves
    pub fn new_self(call: &str, alias: &str, rtt: u16) -> Self {
        Self {
            call: Callsign::from_str(call),
            hops: 1,
            rtt,
            alias: alias.trim().to_string(),
        }
    }

    /// Encode to bytes
    /// Format: call(7) + hops(1) + rtt_hi(1) + rtt_lo(1) + len+2(1) + 0(1) + alias(n) + null(1)
    pub fn encode(&self, buf: &mut Vec<u8>) {
        buf.extend_from_slice(&self.call.raw);
        buf.push(self.hops);
        buf.push((self.rtt >> 8) as u8);    // RTT high byte
        buf.push((self.rtt & 0xff) as u8);  // RTT low byte

        // Alias: length+2, 0, alias bytes, null terminator
        let alias_bytes = self.alias.as_bytes();
        let alias_len = alias_bytes.len().min(6);
        buf.push((alias_len + 2) as u8);
        buf.push(0);
        buf.extend_from_slice(&alias_bytes[..alias_len]);
        buf.push(0); // Null terminator
    }
}

/// INP3 RIF message (Routing Information Frame)
/// Sent over TCP NETROMPORT to announce destinations
///
/// This is how tarpn-chat registers itself as a connectable destination
/// when connected via LinBPQ's NETROMPORT (TCP).
#[derive(Debug, Clone)]
pub struct Inp3Rif {
    pub entries: Vec<Inp3RifEntry>,
}

impl Default for Inp3Rif {
    fn default() -> Self {
        Self::new()
    }
}

impl Inp3Rif {
    pub fn new() -> Self {
        Self { entries: Vec::new() }
    }

    /// Add an entry for announcing ourselves as a destination
    pub fn add_self(&mut self, call: &str, alias: &str) {
        self.entries.push(Inp3RifEntry::new_self(call, alias, 0));
    }

    /// Encode to bytes
    /// Format: 0xFF + entries...
    pub fn encode(&self) -> Vec<u8> {
        let mut buf = Vec::new();
        buf.push(NODES_SIGNATURE); // 0xFF = INP3 RIF flag
        for entry in &self.entries {
            entry.encode(&mut buf);
        }
        buf
    }
}

// =============================================================================
// INP3 RTT (Round-Trip Time) Protocol
// =============================================================================

/// L3RTT destination callsign in AX.25 format
/// This is "L3RTT" with SSID 0, encoded per AX.25 (each char << 1)
pub const L3RTT_CALL: [u8; 7] = [
    0x98, // 'L' << 1
    0x66, // '3' << 1
    0xA4, // 'R' << 1
    0xA8, // 'T' << 1
    0xA8, // 'T' << 1
    0x40, // ' ' << 1
    0xE0, // SSID byte (SSID 0, with reserved bits set)
];

/// RTT message payload size
pub const RTT_MSG_SIZE: usize = 236;

/// INP3 RTT Message
///
/// RTT messages are used by INP3 to measure link latency and keep connections alive.
/// The protocol works by:
/// 1. Node A sends an RTT request with a timestamp
/// 2. Node B echoes the frame back unchanged
/// 3. Node A calculates RTT from the returned timestamp
///
/// The frame is sent to destination "L3RTT" with the sender's callsign as source.
/// Reply detection: if L3SRCE == our callsign, it's a reply (echoed back to us)
#[derive(Debug, Clone)]
pub struct RttMessage {
    /// Transmit timestamp (10ms units, monotonic)
    pub tx_time: u32,
    /// Smoothed RTT (exponential moving average)
    pub srtt: u32,
    /// Last measured RTT
    pub last_rtt: u32,
    /// Message ID counter
    pub rtt_id: u32,
    /// Node alias (up to 6 chars)
    pub alias: String,
}

impl RttMessage {
    /// Create a new RTT request message
    pub fn new(tx_time: u32, srtt: u32, last_rtt: u32, rtt_id: u32, alias: &str) -> Self {
        Self {
            tx_time,
            srtt,
            last_rtt,
            rtt_id,
            alias: alias.to_string(),
        }
    }

    /// Encode RTT message to 236-byte payload
    ///
    /// Format (space-filled):
    /// - "L3RTT: " (7 bytes)
    /// - timestamp (10 bytes, right-justified decimal)
    /// - " " + SRTT (11 bytes)
    /// - " " + lastRTT (11 bytes)
    /// - " " + RTTID (11 bytes)
    /// - " " + alias (8 bytes, space-padded)
    /// - "LEVEL3_V2.1 " (12 bytes)
    /// - software version (9 bytes)
    /// - flags "$M90000 $N $H6      " (20 bytes)
    /// - padding (137 bytes of spaces)
    pub fn encode(&self) -> Vec<u8> {
        let mut buf = vec![b' '; RTT_MSG_SIZE];

        // "L3RTT: " at offset 0
        buf[0..7].copy_from_slice(b"L3RTT: ");

        // Format the 4 numeric fields with spaces: "timestamp srtt lastrtt rttid "
        let stamp = format!(
            "{:>10} {:>10} {:>10} {:>10} ",
            self.tx_time, self.srtt, self.last_rtt, self.rtt_id
        );
        buf[7..51].copy_from_slice(&stamp.as_bytes()[..44]);

        // Alias (6 chars, space-padded) at offset 51
        let alias_bytes = self.alias.as_bytes();
        let alias_len = alias_bytes.len().min(6);
        buf[51..51 + alias_len].copy_from_slice(&alias_bytes[..alias_len]);
        buf[57] = b' ';

        // Version strings
        buf[58..70].copy_from_slice(b"LEVEL3_V2.1 ");
        buf[70..79].copy_from_slice(b"TARPNCHT ");  // Our software ID

        // Flags: $M<maxrtt> $N $H<maxhops>
        buf[79..99].copy_from_slice(b"$M90000 $N $H6      ");

        // Rest is already space-filled
        buf
    }

    /// Parse RTT message from 236-byte payload
    pub fn parse(data: &[u8]) -> Option<Self> {
        if data.len() < RTT_MSG_SIZE {
            return None;
        }

        // Verify "L3RTT: " header
        if &data[0..7] != b"L3RTT: " {
            return None;
        }

        // Parse the numeric fields from the stamp region
        let stamp_str = std::str::from_utf8(&data[7..51]).ok()?;
        let parts: Vec<&str> = stamp_str.split_whitespace().collect();
        if parts.len() < 4 {
            return None;
        }

        let tx_time = parts[0].parse().ok()?;
        let srtt = parts[1].parse().ok()?;
        let last_rtt = parts[2].parse().ok()?;
        let rtt_id = parts[3].parse().ok()?;

        // Parse alias (offset 51-57)
        let alias = std::str::from_utf8(&data[51..57])
            .ok()?
            .trim()
            .to_string();

        Some(Self {
            tx_time,
            srtt,
            last_rtt,
            rtt_id,
            alias,
        })
    }
}

/// Check if a frame is an RTT message (destination is L3RTT)
pub fn is_rtt_frame(frame: &NetromFrame) -> bool {
    frame.l3.dest.raw == L3RTT_CALL
}

/// Check if an RTT frame is a reply to our request
/// (source callsign matches our callsign)
pub fn is_rtt_reply(frame: &NetromFrame, our_call: &Callsign) -> bool {
    frame.l3.source.raw == our_call.raw
}

/// Create an RTT request frame
pub fn create_rtt_request(
    our_call: &Callsign,
    tx_time: u32,
    srtt: u32,
    last_rtt: u32,
    rtt_id: u32,
    alias: &str,
) -> NetromFrame {
    let rtt_msg = RttMessage::new(tx_time, srtt, last_rtt, rtt_id, alias);

    NetromFrame {
        l3: L3Header {
            source: our_call.clone(),
            dest: Callsign::from_raw(L3RTT_CALL),
            ttl: 2,
        },
        l4: L4Header {
            circuit_index: 0,
            circuit_id: 0,
            tx_seq: 0,
            rx_seq: 0,
            opcode: L4Opcode::Information,
            flags: L4Flags::default(),
        },
        data: rtt_msg.encode(),
    }
}

impl NetromFrame {
    /// Parse a NetROM frame from raw bytes (after 0xCF PID)
    pub fn parse(data: &[u8]) -> Option<Self> {
        let l3 = L3Header::parse(data)?;
        let l4_start = L3Header::SIZE;
        let l4 = L4Header::parse(&data[l4_start..])?;
        let data_start = l4_start + L4Header::SIZE;

        let payload = if data.len() > data_start {
            data[data_start..].to_vec()
        } else {
            Vec::new()
        };

        Some(Self {
            l3,
            l4,
            data: payload,
        })
    }

    /// Encode frame to bytes (without 0xCF PID prefix)
    pub fn encode(&self) -> Vec<u8> {
        let mut buf = Vec::with_capacity(L3Header::SIZE + L4Header::SIZE + self.data.len());
        self.l3.encode(&mut buf);
        self.l4.encode(&mut buf);
        buf.extend_from_slice(&self.data);
        buf
    }

    /// Create a CONNECT REQUEST frame
    pub fn connect_request(
        our_node: &Callsign,
        dest_node: &Callsign,
        our_user: &Callsign,
        circuit_index: u8,
        circuit_id: u8,
        window: u8,
        timeout: u16,
    ) -> Self {
        let creq = ConnectRequest {
            window,
            origin_user: our_user.clone(),
            origin_node: our_node.clone(),
            timeout,
            compression: false,
        };

        let mut data = Vec::new();
        creq.encode(&mut data);

        Self {
            l3: L3Header {
                source: our_node.clone(),
                dest: dest_node.clone(),
                ttl: DEFAULT_TTL,
            },
            l4: L4Header {
                circuit_index,
                circuit_id,
                tx_seq: 0,
                rx_seq: 0,
                opcode: L4Opcode::ConnectRequest,
                flags: L4Flags::default(),
            },
            data,
        }
    }

    /// Create a CONNECT ACK frame
    /// CACK payload contains window + L3TTL (LinBPQ format).
    pub fn connect_ack(
        our_node: &Callsign,
        dest_node: &Callsign,
        our_index: u8,
        our_id: u8,
        their_index: u8,
        their_id: u8,
        window: u8,
    ) -> Self {
        let cack = ConnectAck { window, l3ttl: CACK_DEFAULT_TTL };

        let mut data = Vec::new();
        cack.encode(&mut data);

        Self {
            l3: L3Header {
                source: our_node.clone(),
                dest: dest_node.clone(),
                ttl: DEFAULT_TTL,
            },
            l4: L4Header {
                // In CACK: circuit_index/id = sender's circuit (theirs, from CREQ)
                //          tx_seq/rx_seq = responder's circuit (ours, new)
                circuit_index: their_index,
                circuit_id: their_id,
                tx_seq: our_index,
                rx_seq: our_id,
                opcode: L4Opcode::ConnectAck,
                flags: L4Flags::default(),
            },
            data,
        }
    }

    /// Create an INFO frame
    pub fn information(
        our_node: &Callsign,
        dest_node: &Callsign,
        their_index: u8,
        their_id: u8,
        tx_seq: u8,
        rx_seq: u8,
        data: Vec<u8>,
        more: bool,
    ) -> Self {
        Self {
            l3: L3Header {
                source: our_node.clone(),
                dest: dest_node.clone(),
                ttl: DEFAULT_TTL,
            },
            l4: L4Header {
                circuit_index: their_index,
                circuit_id: their_id,
                tx_seq,
                rx_seq,
                opcode: L4Opcode::Information,
                flags: L4Flags {
                    more,
                    ..Default::default()
                },
            },
            data,
        }
    }

    /// Create an INFO ACK frame
    pub fn information_ack(
        our_node: &Callsign,
        dest_node: &Callsign,
        their_index: u8,
        their_id: u8,
        rx_seq: u8,
    ) -> Self {
        Self {
            l3: L3Header {
                source: our_node.clone(),
                dest: dest_node.clone(),
                ttl: DEFAULT_TTL,
            },
            l4: L4Header {
                circuit_index: their_index,
                circuit_id: their_id,
                tx_seq: 0,
                rx_seq,
                opcode: L4Opcode::InformationAck,
                flags: L4Flags::default(),
            },
            data: Vec::new(),
        }
    }

    /// Create a DISCONNECT REQUEST frame
    pub fn disconnect_request(
        our_node: &Callsign,
        dest_node: &Callsign,
        their_index: u8,
        their_id: u8,
    ) -> Self {
        Self {
            l3: L3Header {
                source: our_node.clone(),
                dest: dest_node.clone(),
                ttl: DEFAULT_TTL,
            },
            l4: L4Header {
                circuit_index: their_index,
                circuit_id: their_id,
                tx_seq: 0,
                rx_seq: 0,
                opcode: L4Opcode::DisconnectRequest,
                flags: L4Flags::default(),
            },
            data: Vec::new(),
        }
    }

    /// Create a DISCONNECT ACK frame
    pub fn disconnect_ack(
        our_node: &Callsign,
        dest_node: &Callsign,
        their_index: u8,
        their_id: u8,
    ) -> Self {
        Self {
            l3: L3Header {
                source: our_node.clone(),
                dest: dest_node.clone(),
                ttl: DEFAULT_TTL,
            },
            l4: L4Header {
                circuit_index: their_index,
                circuit_id: their_id,
                tx_seq: 0,
                rx_seq: 0,
                opcode: L4Opcode::DisconnectAck,
                flags: L4Flags::default(),
            },
            data: Vec::new(),
        }
    }

    /// Create a RESET frame (Paula's extension)
    ///
    /// Used to tell the remote end that we don't have a session they think we have.
    /// The remote end will search for a session with matching FAR circuit info and close it.
    ///
    /// # Arguments
    /// * `our_node` - Our node callsign
    /// * `dest_node` - Destination node callsign
    /// * `their_index` - The circuit index from the incoming frame (what they think our index is)
    /// * `their_id` - The circuit id from the incoming frame (what they think our id is)
    pub fn reset(
        our_node: &Callsign,
        dest_node: &Callsign,
        their_index: u8,
        their_id: u8,
    ) -> Self {
        Self {
            l3: L3Header {
                source: our_node.clone(),
                dest: dest_node.clone(),
                ttl: DEFAULT_TTL,
            },
            l4: L4Header {
                // The circuit_index/id fields are 0 since this isn't addressing a specific circuit
                circuit_index: 0,
                circuit_id: 0,
                // Per LinBPQ: tx_seq holds their index, rx_seq holds their id
                tx_seq: their_index,
                rx_seq: their_id,
                opcode: L4Opcode::Reset,
                flags: L4Flags::default(),
            },
            data: Vec::new(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_callsign_from_str() {
        let call = Callsign::from_str("WA2M-9");
        assert_eq!(call.to_string(), "WA2M-9");

        let call = Callsign::from_str("N0CALL");
        assert_eq!(call.to_string(), "N0CALL");

        let call = Callsign::from_str("KB1ABC-15");
        assert_eq!(call.to_string(), "KB1ABC-15");
    }

    #[test]
    fn test_callsign_roundtrip() {
        let original = "TEST4-1";
        let call = Callsign::from_str(original);
        let raw = call.raw;
        let parsed = Callsign::from_raw(raw);
        assert_eq!(parsed.to_string(), original);
    }

    #[test]
    fn test_l4_opcode_from_flags() {
        assert_eq!(L4Opcode::from_flags(0x01), Some(L4Opcode::ConnectRequest));
        assert_eq!(L4Opcode::from_flags(0x02), Some(L4Opcode::ConnectAck));
        assert_eq!(L4Opcode::from_flags(0x05), Some(L4Opcode::Information));
        assert_eq!(L4Opcode::from_flags(0x85), Some(L4Opcode::Information)); // With BUSY flag
        assert_eq!(L4Opcode::from_flags(0x00), None);
    }

    #[test]
    fn test_l4_flags() {
        let flags = L4Flags::from_byte(0xF5); // All flags + INFO opcode
        assert!(flags.busy);
        assert!(flags.nak);
        assert!(flags.more);
        assert!(flags.compressed);

        let encoded = flags.to_byte();
        assert_eq!(encoded & 0xF0, 0xF0);
    }

    #[test]
    fn test_frame_encode_decode() {
        let our_node = Callsign::from_str("TEST1-1");
        let dest_node = Callsign::from_str("TEST2-1");
        let our_user = Callsign::from_str("TEST1-9");

        let frame = NetromFrame::connect_request(
            &our_node,
            &dest_node,
            &our_user,
            1, // circuit_index
            42, // circuit_id
            4, // window
            300, // timeout
        );

        let encoded = frame.encode();
        let decoded = NetromFrame::parse(&encoded).unwrap();

        assert_eq!(decoded.l3.source.to_string(), "TEST1-1");
        assert_eq!(decoded.l3.dest.to_string(), "TEST2-1");
        assert_eq!(decoded.l4.opcode, L4Opcode::ConnectRequest);
        assert_eq!(decoded.l4.circuit_index, 1);
        assert_eq!(decoded.l4.circuit_id, 42);
    }

    #[test]
    fn test_connect_request_payload() {
        let creq = ConnectRequest {
            window: 4,
            origin_user: Callsign::from_str("USER-1"),
            origin_node: Callsign::from_str("NODE-1"),
            timeout: 300,
            compression: true,
        };

        let mut buf = Vec::new();
        creq.encode(&mut buf);

        let parsed = ConnectRequest::parse(&buf).unwrap();
        assert_eq!(parsed.window, 4);
        assert_eq!(parsed.origin_user.to_string(), "USER-1");
        assert_eq!(parsed.origin_node.to_string(), "NODE-1");
        assert!(parsed.compression);
    }
}
