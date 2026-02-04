//! LinBPQ Chat Protocol message types and parsing
//!
//! Protocol format: <FORMAT><TYPE><data>\r
//! - FORMAT = 0x01 (Ctrl-A)
//! - TYPE = Single ASCII character identifying message type
//! - data = Space-delimited fields
//!
//! Note: LinBPQ uses CR (`\r`) as the line terminator, not LF or CRLF.
//!
//! ## ChatConnection
//!
//! The `ChatConnection` struct handles the application-level protocol over
//! a reliable byte stream (provided by the L4 transport layer). It:
//! - Buffers incoming bytes until CR delimiter
//! - Manages handshake state (SID, *RTL, OK sequence)
//! - Parses chat protocol messages
//!
//! This provides clean separation between L4 (reliable delivery) and
//! application protocol (chat messages).

use thiserror::Error;
use tokio::io::{AsyncBufRead, AsyncBufReadExt};
use tracing::{debug, trace, warn};

/// Control byte that prefixes all protocol messages
pub const FORMAT_BYTE: u8 = 0x01;

/// Protocol version string used in SID and keepalive messages.
/// Format: "X.Y.Z-tarpn" where X.Y.Z comes from Cargo.toml version.
/// LinBPQ parses everything after "[BPQCHATSERVER-" up to "]", so the
/// "-tarpn" suffix is safe and helps identify tarpn-chat nodes.
pub const VERSION: &str = concat!(env!("CARGO_PKG_VERSION"), "-tarpn");

/// Request to link as a node
pub const RTL_COMMAND: &str = "*RTL";

/// Read a CR-terminated line from the reader.
///
/// LinBPQ uses `\r` (CR, 0x0D) as the line terminator, not `\n` (LF).
/// This function reads until it encounters `\r` and returns the line
/// without the terminator.
///
/// Returns the number of bytes read (including the CR), or 0 on EOF.
pub async fn read_cr_line<R: AsyncBufRead + Unpin>(
    reader: &mut R,
    buf: &mut String,
) -> std::io::Result<usize> {
    let mut total = 0;
    loop {
        let available = reader.fill_buf().await?;
        if available.is_empty() {
            // EOF
            return Ok(total);
        }

        // Look for CR in the buffer
        if let Some(pos) = available.iter().position(|&b| b == b'\r') {
            // Found CR - append everything up to it
            let line_bytes = &available[..pos];
            buf.push_str(&String::from_utf8_lossy(line_bytes));
            total += pos + 1; // Include the CR in the count
            reader.consume(pos + 1);
            return Ok(total);
        } else {
            // No CR found - consume entire buffer and continue
            buf.push_str(&String::from_utf8_lossy(available));
            let len = available.len();
            total += len;
            reader.consume(len);
        }
    }
}

#[derive(Debug, Error)]
pub enum ProtocolError {
    #[error("Invalid message format: {0}")]
    InvalidFormat(String),
    #[error("Unknown message type: {0}")]
    UnknownType(char),
    #[error("Missing required field: {0}")]
    MissingField(&'static str),
}

/// All protocol message types
#[derive(Debug, Clone, PartialEq)]
pub enum Message {
    // User messages
    Join(JoinMessage),
    Leave(LeaveMessage),
    Data(DataMessage),
    Private(PrivateMessage),
    Topic(TopicMessage),
    Info(InfoMessage),

    // Node messages
    NodeLink(NodeLinkMessage),
    NodeUnlink(NodeUnlinkMessage),

    // Link maintenance
    Keepalive(KeepaliveMessage),
    Poll(PollMessage),
    PollResponse(PollResponseMessage),
}

/// User joined chat - ^AJ<node> <user> <name> <qth>
#[derive(Debug, Clone, PartialEq)]
pub struct JoinMessage {
    pub node: String,
    pub user: String,
    pub name: String,
    pub qth: String,
}

/// User left chat - ^AL<node> <user> <name> <qth>
#[derive(Debug, Clone, PartialEq)]
pub struct LeaveMessage {
    pub node: String,
    pub user: String,
    pub name: String,
    pub qth: String,
}

/// Broadcast message to topic - ^AD<node> <user> <text>
#[derive(Debug, Clone, PartialEq)]
pub struct DataMessage {
    pub node: String,
    pub user: String,
    pub text: String,
}

/// Private message - ^AS<node> <from> <to> <text>
#[derive(Debug, Clone, PartialEq)]
pub struct PrivateMessage {
    pub node: String,
    pub from: String,
    pub to: String,
    pub text: String,
}

/// User changed topic - ^AT<node> <user> <topic>
#[derive(Debug, Clone, PartialEq)]
pub struct TopicMessage {
    pub node: String,
    pub user: String,
    pub topic: String,
}

/// User info update - ^AI<node> <user> <name> <qth>
#[derive(Debug, Clone, PartialEq)]
pub struct InfoMessage {
    pub node: String,
    pub user: String,
    pub name: String,
    pub qth: String,
}

/// Node link established - ^AN<node> <newnode> <alias> [version]
#[derive(Debug, Clone, PartialEq)]
pub struct NodeLinkMessage {
    pub node: String,
    pub new_node: String,
    pub alias: String,
    pub version: Option<String>,
}

/// Node link dropped - ^AQ<node> <lostnode>
#[derive(Debug, Clone, PartialEq)]
pub struct NodeUnlinkMessage {
    pub node: String,
    pub lost_node: String,
}

/// Keepalive - ^AK<srcnode> <destnode> [version]
#[derive(Debug, Clone, PartialEq)]
pub struct KeepaliveMessage {
    pub src_node: String,
    pub dest_node: String,
    pub version: Option<String>,
}

impl KeepaliveMessage {
    /// Create a poll response message for this keepalive.
    /// The response swaps src/dest: we become src, the original sender becomes dest.
    pub fn make_response(&self, our_node: &str) -> Message {
        Message::PollResponse(PollResponseMessage {
            src_node: our_node.to_string(),
            dest_node: self.src_node.clone(),
        })
    }
}

/// Poll request - ^AP<srcnode> <destnode>
#[derive(Debug, Clone, PartialEq)]
pub struct PollMessage {
    pub src_node: String,
    pub dest_node: String,
}

impl PollMessage {
    /// Create a poll response message for this poll.
    /// The response swaps src/dest: we become src, the original sender becomes dest.
    pub fn make_response(&self, our_node: &str) -> Message {
        Message::PollResponse(PollResponseMessage {
            src_node: our_node.to_string(),
            dest_node: self.src_node.clone(),
        })
    }
}

/// Poll response - ^AR<srcnode> <destnode>
#[derive(Debug, Clone, PartialEq)]
pub struct PollResponseMessage {
    pub src_node: String,
    pub dest_node: String,
}

impl Message {
    /// Parse a raw protocol message
    pub fn parse(data: &[u8]) -> Result<Self, ProtocolError> {
        // Must start with format byte
        if data.is_empty() || data[0] != FORMAT_BYTE {
            return Err(ProtocolError::InvalidFormat(
                "Message must start with FORMAT byte (0x01)".into(),
            ));
        }

        if data.len() < 2 {
            return Err(ProtocolError::InvalidFormat("Message too short".into()));
        }

        let msg_type = data[1] as char;
        // Rest of message after type byte, trimmed of CR/LF
        let payload = String::from_utf8_lossy(&data[2..])
            .trim_end_matches(|c| c == '\r' || c == '\n')
            .to_string();

        Self::parse_typed(msg_type, &payload)
    }

    /// Parse a message with known type
    fn parse_typed(msg_type: char, payload: &str) -> Result<Self, ProtocolError> {
        match msg_type {
            'J' => Self::parse_join(payload),
            'L' => Self::parse_leave(payload),
            'D' => Self::parse_data(payload),
            'S' => Self::parse_private(payload),
            'T' => Self::parse_topic(payload),
            'I' => Self::parse_info(payload),
            'N' => Self::parse_node_link(payload),
            'Q' => Self::parse_node_unlink(payload),
            'K' => Self::parse_keepalive(payload),
            'P' => Self::parse_poll(payload),
            'R' => Self::parse_poll_response(payload),
            _ => Err(ProtocolError::UnknownType(msg_type)),
        }
    }

    /// Parse join message: <node> <user> <name> <qth>
    fn parse_join(payload: &str) -> Result<Self, ProtocolError> {
        let parts: Vec<&str> = payload.splitn(4, ' ').collect();
        if parts.len() < 4 {
            return Err(ProtocolError::MissingField("join requires node, user, name, qth"));
        }
        Ok(Message::Join(JoinMessage {
            node: parts[0].to_string(),
            user: parts[1].to_string(),
            name: parts[2].to_string(),
            qth: parts[3].to_string(),
        }))
    }

    /// Parse leave message: <node> <user> <name> <qth>
    fn parse_leave(payload: &str) -> Result<Self, ProtocolError> {
        let parts: Vec<&str> = payload.splitn(4, ' ').collect();
        if parts.len() < 4 {
            return Err(ProtocolError::MissingField("leave requires node, user, name, qth"));
        }
        Ok(Message::Leave(LeaveMessage {
            node: parts[0].to_string(),
            user: parts[1].to_string(),
            name: parts[2].to_string(),
            qth: parts[3].to_string(),
        }))
    }

    /// Parse data message: <node> <user> <text>
    fn parse_data(payload: &str) -> Result<Self, ProtocolError> {
        let parts: Vec<&str> = payload.splitn(3, ' ').collect();
        if parts.len() < 3 {
            return Err(ProtocolError::MissingField("data requires node, user, text"));
        }
        Ok(Message::Data(DataMessage {
            node: parts[0].to_string(),
            user: parts[1].to_string(),
            text: parts[2].to_string(),
        }))
    }

    /// Parse private message: <node> <from> <to> <text>
    fn parse_private(payload: &str) -> Result<Self, ProtocolError> {
        let parts: Vec<&str> = payload.splitn(4, ' ').collect();
        if parts.len() < 4 {
            return Err(ProtocolError::MissingField("private requires node, from, to, text"));
        }
        Ok(Message::Private(PrivateMessage {
            node: parts[0].to_string(),
            from: parts[1].to_string(),
            to: parts[2].to_string(),
            text: parts[3].to_string(),
        }))
    }

    /// Parse topic message: <node> <user> <topic>
    fn parse_topic(payload: &str) -> Result<Self, ProtocolError> {
        let parts: Vec<&str> = payload.splitn(3, ' ').collect();
        if parts.len() < 3 {
            return Err(ProtocolError::MissingField("topic requires node, user, topic"));
        }
        Ok(Message::Topic(TopicMessage {
            node: parts[0].to_string(),
            user: parts[1].to_string(),
            topic: parts[2].to_string(),
        }))
    }

    /// Parse info message: <node> <user> <name> <qth>
    fn parse_info(payload: &str) -> Result<Self, ProtocolError> {
        let parts: Vec<&str> = payload.splitn(4, ' ').collect();
        if parts.len() < 4 {
            return Err(ProtocolError::MissingField("info requires node, user, name, qth"));
        }
        Ok(Message::Info(InfoMessage {
            node: parts[0].to_string(),
            user: parts[1].to_string(),
            name: parts[2].to_string(),
            qth: parts[3].to_string(),
        }))
    }

    /// Parse node link message: <node> <newnode> <alias> [version]
    fn parse_node_link(payload: &str) -> Result<Self, ProtocolError> {
        let parts: Vec<&str> = payload.splitn(4, ' ').collect();
        if parts.len() < 3 {
            return Err(ProtocolError::MissingField("node_link requires node, newnode, alias"));
        }
        Ok(Message::NodeLink(NodeLinkMessage {
            node: parts[0].to_string(),
            new_node: parts[1].to_string(),
            alias: parts[2].to_string(),
            version: parts.get(3).map(|s| s.to_string()),
        }))
    }

    /// Parse node unlink message: <node> <lostnode>
    fn parse_node_unlink(payload: &str) -> Result<Self, ProtocolError> {
        let parts: Vec<&str> = payload.split(' ').collect();
        if parts.len() < 2 {
            return Err(ProtocolError::MissingField("node_unlink requires node, lostnode"));
        }
        Ok(Message::NodeUnlink(NodeUnlinkMessage {
            node: parts[0].to_string(),
            lost_node: parts[1].to_string(),
        }))
    }

    /// Parse keepalive message: <srcnode> <destnode> [version]
    fn parse_keepalive(payload: &str) -> Result<Self, ProtocolError> {
        let parts: Vec<&str> = payload.splitn(3, ' ').collect();
        if parts.len() < 2 {
            return Err(ProtocolError::MissingField("keepalive requires srcnode, destnode"));
        }
        Ok(Message::Keepalive(KeepaliveMessage {
            src_node: parts[0].to_string(),
            dest_node: parts[1].to_string(),
            version: parts.get(2).map(|s| s.to_string()),
        }))
    }

    /// Parse poll message: <srcnode> <destnode>
    fn parse_poll(payload: &str) -> Result<Self, ProtocolError> {
        let parts: Vec<&str> = payload.split(' ').collect();
        if parts.len() < 2 {
            return Err(ProtocolError::MissingField("poll requires srcnode, destnode"));
        }
        Ok(Message::Poll(PollMessage {
            src_node: parts[0].to_string(),
            dest_node: parts[1].to_string(),
        }))
    }

    /// Parse poll response message: <srcnode> <destnode>
    fn parse_poll_response(payload: &str) -> Result<Self, ProtocolError> {
        let parts: Vec<&str> = payload.split(' ').collect();
        if parts.len() < 2 {
            return Err(ProtocolError::MissingField("poll_response requires srcnode, destnode"));
        }
        Ok(Message::PollResponse(PollResponseMessage {
            src_node: parts[0].to_string(),
            dest_node: parts[1].to_string(),
        }))
    }

    /// Encode message to bytes for transmission
    pub fn encode(&self) -> Vec<u8> {
        let mut buf = Vec::new();
        buf.push(FORMAT_BYTE);

        match self {
            Message::Join(m) => {
                buf.push(b'J');
                buf.extend(format!("{} {} {} {}", m.node, m.user, m.name, m.qth).as_bytes());
            }
            Message::Leave(m) => {
                buf.push(b'L');
                buf.extend(format!("{} {} {} {}", m.node, m.user, m.name, m.qth).as_bytes());
            }
            Message::Data(m) => {
                buf.push(b'D');
                buf.extend(format!("{} {} {}", m.node, m.user, m.text).as_bytes());
            }
            Message::Private(m) => {
                buf.push(b'S');
                buf.extend(format!("{} {} {} {}", m.node, m.from, m.to, m.text).as_bytes());
            }
            Message::Topic(m) => {
                buf.push(b'T');
                buf.extend(format!("{} {} {}", m.node, m.user, m.topic).as_bytes());
            }
            Message::Info(m) => {
                buf.push(b'I');
                buf.extend(format!("{} {} {} {}", m.node, m.user, m.name, m.qth).as_bytes());
            }
            Message::NodeLink(m) => {
                buf.push(b'N');
                let base = format!("{} {} {}", m.node, m.new_node, m.alias);
                if let Some(ref ver) = m.version {
                    buf.extend(format!("{} {}", base, ver).as_bytes());
                } else {
                    buf.extend(base.as_bytes());
                }
            }
            Message::NodeUnlink(m) => {
                buf.push(b'Q');
                buf.extend(format!("{} {}", m.node, m.lost_node).as_bytes());
            }
            Message::Keepalive(m) => {
                buf.push(b'K');
                let base = format!("{} {}", m.src_node, m.dest_node);
                if let Some(ref ver) = m.version {
                    buf.extend(format!("{} {}", base, ver).as_bytes());
                } else {
                    buf.extend(base.as_bytes());
                }
            }
            Message::Poll(m) => {
                buf.push(b'P');
                buf.extend(format!("{} {}", m.src_node, m.dest_node).as_bytes());
            }
            Message::PollResponse(m) => {
                buf.push(b'R');
                buf.extend(format!("{} {}", m.src_node, m.dest_node).as_bytes());
            }
        }

        buf.push(b'\r');
        buf
    }
}

// ============================================================================
// ChatConnection - Application-level protocol handler
// ============================================================================

/// State of the chat connection handshake
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChatState {
    /// Waiting for SID from remote (outbound connections)
    WaitingSid,
    /// Received SID, sent *RTL, waiting for OK (outbound connections)
    WaitingOk,
    /// Sent SID, waiting for *RTL from remote (inbound connections)
    WaitingRtl,
    /// Handshake complete, exchanging messages
    Linked,
    /// Connection closed or errored
    Closed,
}

/// Events produced by ChatConnection when processing incoming data
#[derive(Debug)]
pub enum ChatEvent {
    /// Handshake completed successfully
    HandshakeComplete,
    /// Received a chat protocol message
    Message(Message),
    /// Need to send data to the peer
    Send(Vec<u8>),
    /// Error occurred
    Error(String),
}

/// Application-level chat protocol handler
///
/// Sits on top of the L4 transport layer. Receives raw bytes,
/// buffers until CR delimiter, handles handshake, parses messages.
pub struct ChatConnection {
    /// Our node callsign
    our_node: String,
    /// Our node alias
    our_alias: String,
    /// Remote node callsign (set after handshake)
    remote_node: Option<String>,
    /// Whether this is an outbound connection (we initiated)
    is_outbound: bool,
    /// Current handshake state
    state: ChatState,
    /// Buffer for incomplete lines
    buffer: String,
    /// Remote's version string (from SID)
    remote_version: Option<String>,
}

impl ChatConnection {
    /// Create a new chat connection handler
    ///
    /// # Arguments
    /// * `our_node` - Our chat node callsign (e.g., "TEST4-9")
    /// * `our_alias` - Our chat node alias (e.g., "T4CHAT")
    /// * `is_outbound` - True if we initiated the connection
    /// * `remote_node` - Remote node callsign if known (for Keepalive messages)
    pub fn new(our_node: &str, our_alias: &str, is_outbound: bool, remote_node: Option<&str>) -> Self {
        let initial_state = if is_outbound {
            ChatState::WaitingSid
        } else {
            ChatState::WaitingRtl
        };

        Self {
            our_node: our_node.to_string(),
            our_alias: our_alias.to_string(),
            remote_node: remote_node.map(|s| s.to_string()),
            is_outbound,
            state: initial_state,
            buffer: String::new(),
            remote_version: None,
        }
    }

    /// Get the current state
    pub fn state(&self) -> ChatState {
        self.state
    }

    /// Get the remote node callsign (if known)
    pub fn remote_node(&self) -> Option<&str> {
        self.remote_node.as_deref()
    }

    /// Check if handshake is complete
    pub fn is_linked(&self) -> bool {
        self.state == ChatState::Linked
    }

    /// Called when L4 connection is established
    ///
    /// Both inbound and outbound connections send the SID immediately.
    /// The connecting party (outbound) must send SID first per LinBPQ chat protocol.
    pub fn on_connected(&mut self) -> Vec<ChatEvent> {
        let mut events = Vec::new();

        // Always send our SID - the connecting party sends first, but we send regardless
        let sid = format!("[BPQCHATSERVER-{}]\r", VERSION);
        debug!(
            sid = %sid.trim(),
            is_outbound = self.is_outbound,
            "Sending SID"
        );
        events.push(ChatEvent::Send(sid.into_bytes()));

        events
    }

    /// Process incoming bytes from the L4 layer
    ///
    /// Returns a list of events (messages to process, data to send, etc.)
    pub fn receive_data(&mut self, data: &[u8]) -> Vec<ChatEvent> {
        if self.state == ChatState::Closed {
            return vec![];
        }

        // Append to buffer
        let text = String::from_utf8_lossy(data);
        self.buffer.push_str(&text);

        let mut events = Vec::new();

        // Process complete lines (CR-delimited)
        while let Some(cr_pos) = self.buffer.find('\r') {
            let line = self.buffer[..cr_pos].to_string();
            self.buffer = self.buffer[cr_pos + 1..].to_string();

            if line.is_empty() {
                continue;
            }

            trace!(line = %line, state = ?self.state, "Processing line");
            events.extend(self.process_line(&line));
        }

        events
    }

    /// Process a single CR-delimited line
    fn process_line(&mut self, line: &str) -> Vec<ChatEvent> {
        match self.state {
            ChatState::WaitingSid => self.handle_waiting_sid(line),
            ChatState::WaitingOk => self.handle_waiting_ok(line),
            ChatState::WaitingRtl => self.handle_waiting_rtl(line),
            ChatState::Linked => self.handle_linked(line),
            ChatState::Closed => vec![],
        }
    }

    /// Handle data while waiting for SID (outbound)
    fn handle_waiting_sid(&mut self, line: &str) -> Vec<ChatEvent> {
        // Look for SID: [BPQChatServer-x.x.x] or [BPQCHATSERVER-x.x.x]
        let line_upper = line.to_uppercase();
        if line.starts_with('[') && line_upper.contains("CHATSERVER") {
            // Extract version
            if let Some(version) = Self::parse_sid(line) {
                debug!(version = %version, "Received SID");
                self.remote_version = Some(version);
            }

            // Send *RTL
            let rtl = format!("{}\r", RTL_COMMAND);
            debug!("Sending *RTL");

            // Send keepalive with our info
            let keepalive = Message::Keepalive(KeepaliveMessage {
                src_node: self.our_node.clone(),
                dest_node: self.remote_node.clone().unwrap_or_else(|| "*".to_string()),
                version: Some(VERSION.to_string()),
            });

            self.state = ChatState::WaitingOk;

            vec![
                ChatEvent::Send(rtl.into_bytes()),
                ChatEvent::Send(keepalive.encode()),
            ]
        } else {
            // Unexpected data before SID - might be error message
            warn!(line = %line, "Unexpected data while waiting for SID");
            if line.contains("Refusing") || line.contains("Error") {
                self.state = ChatState::Closed;
                vec![ChatEvent::Error(line.to_string())]
            } else {
                vec![]
            }
        }
    }

    /// Handle data while waiting for OK (outbound)
    fn handle_waiting_ok(&mut self, line: &str) -> Vec<ChatEvent> {
        // Check for error/rejection messages first
        if line.contains("Refusing") || line.contains("loop") || line.contains("Error") {
            warn!(line = %line, "Connection refused by remote");
            self.state = ChatState::Closed;
            return vec![ChatEvent::Error(line.to_string())];
        }

        if line == "OK" {
            debug!("Received OK, handshake complete");
            self.state = ChatState::Linked;

            // Send our NodeLink to announce ourselves
            let node_link = Message::NodeLink(NodeLinkMessage {
                node: self.our_node.clone(),
                new_node: self.our_node.clone(),
                alias: self.our_alias.clone(),
                version: Some(VERSION.to_string()),
            });

            vec![
                ChatEvent::Send(node_link.encode()),
                ChatEvent::HandshakeComplete,
            ]
        } else if line.starts_with('\x01') {
            // Chat protocol message during handshake - process it
            // This can happen if the remote sends keepalive before OK
            self.parse_and_handle_message(line)
        } else {
            warn!(line = %line, "Unexpected data while waiting for OK");
            if line.contains("Refusing") || line.contains("Error") {
                self.state = ChatState::Closed;
                vec![ChatEvent::Error(line.to_string())]
            } else {
                vec![]
            }
        }
    }

    /// Handle data while waiting for *RTL (inbound)
    fn handle_waiting_rtl(&mut self, line: &str) -> Vec<ChatEvent> {
        if line == RTL_COMMAND {
            debug!("Received *RTL, sending OK");
            self.state = ChatState::Linked;

            // Send OK
            let ok = "OK\r";

            // Send our NodeLink
            let node_link = Message::NodeLink(NodeLinkMessage {
                node: self.our_node.clone(),
                new_node: self.our_node.clone(),
                alias: self.our_alias.clone(),
                version: Some(VERSION.to_string()),
            });

            vec![
                ChatEvent::Send(ok.as_bytes().to_vec()),
                ChatEvent::Send(node_link.encode()),
                ChatEvent::HandshakeComplete,
            ]
        } else if line.starts_with('\x01') {
            // Chat protocol message - might be keepalive sent with *RTL
            self.parse_and_handle_message(line)
        } else if line.starts_with('[') && line.contains("CHATSERVER") {
            // Remote is also a tarpn-chat node - they sent their SID
            // This happens when both sides send SID simultaneously
            // Store their version and wait for *RTL
            debug!(line = %line, "Received SID from remote tarpn-chat node while waiting for *RTL");
            self.remote_version = Some(line.to_string());
            vec![]
        } else {
            warn!(line = %line, "Unexpected data while waiting for *RTL");
            vec![]
        }
    }

    /// Handle data in linked state
    fn handle_linked(&mut self, line: &str) -> Vec<ChatEvent> {
        if line.starts_with('\x01') {
            self.parse_and_handle_message(line)
        } else {
            // Non-protocol data - could be error message
            warn!(line = %line, "Non-protocol data in linked state");
            if line.contains("Disconnecting") {
                self.state = ChatState::Closed;
                vec![ChatEvent::Error(line.to_string())]
            } else {
                vec![]
            }
        }
    }

    /// Parse a ^A message and return appropriate events
    fn parse_and_handle_message(&mut self, line: &str) -> Vec<ChatEvent> {
        match Message::parse(line.as_bytes()) {
            Ok(msg) => {
                // Track remote node from NodeLink or Keepalive
                match &msg {
                    Message::NodeLink(nl) => {
                        if self.remote_node.is_none() {
                            self.remote_node = Some(nl.node.clone());
                            debug!(remote = %nl.node, "Learned remote node");
                        }
                    }
                    Message::Keepalive(ka) => {
                        if self.remote_node.is_none() {
                            self.remote_node = Some(ka.src_node.clone());
                            debug!(remote = %ka.src_node, "Learned remote node from keepalive");
                        }
                    }
                    _ => {}
                }
                vec![ChatEvent::Message(msg)]
            }
            Err(e) => {
                warn!(line = %line, error = %e, "Failed to parse message");
                vec![]
            }
        }
    }

    /// Parse SID to extract version
    fn parse_sid(sid: &str) -> Option<String> {
        // Format: [BPQChatServer-6.0.25.16] or [BPQCHATSERVER-1.0.0]
        let start = sid.find('-')?;
        let end = sid.find(']')?;
        if start < end {
            Some(sid[start + 1..end].to_string())
        } else {
            None
        }
    }

    /// Create a message to send to this connection
    pub fn encode_message(&self, msg: &Message) -> Vec<u8> {
        msg.encode()
    }

    /// Mark connection as closed
    pub fn close(&mut self) {
        self.state = ChatState::Closed;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_keepalive() {
        let data = b"\x01KWA2M-9 KB1ABC 1.0.0\r";
        let msg = Message::parse(data).unwrap();
        assert_eq!(
            msg,
            Message::Keepalive(KeepaliveMessage {
                src_node: "WA2M-9".into(),
                dest_node: "KB1ABC".into(),
                version: Some("1.0.0".into()),
            })
        );
    }

    #[test]
    fn test_parse_join() {
        let data = b"\x01JWA2M-9 N0CALL John Somewhere\r";
        let msg = Message::parse(data).unwrap();
        assert_eq!(
            msg,
            Message::Join(JoinMessage {
                node: "WA2M-9".into(),
                user: "N0CALL".into(),
                name: "John".into(),
                qth: "Somewhere".into(),
            })
        );
    }

    #[test]
    fn test_parse_data() {
        let data = b"\x01DWA2M-9 N0CALL Hello everyone!\r";
        let msg = Message::parse(data).unwrap();
        assert_eq!(
            msg,
            Message::Data(DataMessage {
                node: "WA2M-9".into(),
                user: "N0CALL".into(),
                text: "Hello everyone!".into(),
            })
        );
    }

    #[test]
    fn test_encode_roundtrip() {
        let original = Message::Keepalive(KeepaliveMessage {
            src_node: "WA2M-9".into(),
            dest_node: "KB1ABC".into(),
            version: Some("1.0.0".into()),
        });
        let encoded = original.encode();
        let parsed = Message::parse(&encoded).unwrap();
        assert_eq!(original, parsed);
    }

    #[test]
    fn test_encode_node_link() {
        let msg = Message::NodeLink(NodeLinkMessage {
            node: "WA2M-9".into(),
            new_node: "KB1ABC".into(),
            alias: "BOT".into(),
            version: None,
        });
        let encoded = msg.encode();
        assert_eq!(encoded, b"\x01NWA2M-9 KB1ABC BOT\r");
    }

    #[test]
    fn test_keepalive_make_response() {
        let ka = KeepaliveMessage {
            src_node: "KB1ABC".into(),
            dest_node: "WA2M-9".into(),
            version: Some("1.0.0".into()),
        };
        let response = ka.make_response("WA2M-9");
        assert_eq!(
            response,
            Message::PollResponse(PollResponseMessage {
                src_node: "WA2M-9".into(),
                dest_node: "KB1ABC".into(),
            })
        );
    }

    #[test]
    fn test_poll_make_response() {
        let poll = PollMessage {
            src_node: "KB1ABC".into(),
            dest_node: "WA2M-9".into(),
        };
        let response = poll.make_response("WA2M-9");
        assert_eq!(
            response,
            Message::PollResponse(PollResponseMessage {
                src_node: "WA2M-9".into(),
                dest_node: "KB1ABC".into(),
            })
        );
    }

    // ChatConnection tests

    #[test]
    fn test_chat_connection_outbound_handshake() {
        let mut conn = ChatConnection::new("TEST4-9", "T4CHAT", true, Some("TEST5-9"));
        assert_eq!(conn.state(), ChatState::WaitingSid);

        // Receive SID
        let events = conn.receive_data(b"[BPQChatServer-6.0.25]\r");
        assert_eq!(conn.state(), ChatState::WaitingOk);

        // Should have sent *RTL and keepalive
        assert!(events.iter().any(|e| matches!(e, ChatEvent::Send(_))));

        // Receive OK
        let events = conn.receive_data(b"OK\r");
        assert_eq!(conn.state(), ChatState::Linked);

        // Should have HandshakeComplete and sent NodeLink
        assert!(events.iter().any(|e| matches!(e, ChatEvent::HandshakeComplete)));
        assert!(events.iter().any(|e| matches!(e, ChatEvent::Send(_))));
    }

    #[test]
    fn test_chat_connection_inbound_handshake() {
        let mut conn = ChatConnection::new("TEST4-9", "T4CHAT", false, Some("TEST5-9"));
        assert_eq!(conn.state(), ChatState::WaitingRtl);

        // on_connected sends SID for inbound
        let events = conn.on_connected();
        assert!(events.iter().any(|e| {
            if let ChatEvent::Send(data) = e {
                String::from_utf8_lossy(data).contains("BPQCHATSERVER")
            } else {
                false
            }
        }));

        // Receive *RTL
        let events = conn.receive_data(b"*RTL\r");
        assert_eq!(conn.state(), ChatState::Linked);

        // Should have sent OK and NodeLink
        assert!(events.iter().any(|e| matches!(e, ChatEvent::HandshakeComplete)));
    }

    #[test]
    fn test_chat_connection_buffering() {
        let mut conn = ChatConnection::new("TEST4-9", "T4CHAT", true, Some("TEST5-9"));

        // Receive partial SID
        let events = conn.receive_data(b"[BPQChat");
        assert!(events.is_empty()); // No complete line yet
        assert_eq!(conn.state(), ChatState::WaitingSid);

        // Receive rest of SID
        let events = conn.receive_data(b"Server-6.0.25]\r");
        assert_eq!(conn.state(), ChatState::WaitingOk); // Now processed
    }

    #[test]
    fn test_chat_connection_multiple_messages() {
        let mut conn = ChatConnection::new("TEST4-9", "T4CHAT", true, Some("TEST5-9"));

        // Fast forward to linked state
        conn.receive_data(b"[BPQChatServer-6.0.25]\r");
        conn.receive_data(b"OK\r");
        assert_eq!(conn.state(), ChatState::Linked);

        // Receive multiple messages in one chunk
        let events = conn.receive_data(b"\x01NTEST6-9 TEST6-9 T6CHAT 6.0.25\r\x01JTEST6-9 ALICE Alice QTH\r");

        // Should have two messages
        let messages: Vec<_> = events
            .iter()
            .filter_map(|e| {
                if let ChatEvent::Message(m) = e {
                    Some(m)
                } else {
                    None
                }
            })
            .collect();
        assert_eq!(messages.len(), 2);
    }

    #[test]
    fn test_parse_sid() {
        // LinBPQ format (4-part numeric version)
        assert_eq!(
            ChatConnection::parse_sid("[BPQChatServer-6.0.25.16]"),
            Some("6.0.25.16".to_string())
        );
        assert_eq!(
            ChatConnection::parse_sid("[BPQCHATSERVER-1.0.0]"),
            Some("1.0.0".to_string())
        );
        // tarpn-chat format (semver with -tarpn suffix)
        assert_eq!(
            ChatConnection::parse_sid("[BPQCHATSERVER-1.1.1-tarpn]"),
            Some("1.1.1-tarpn".to_string())
        );
        // Verify our VERSION constant parses correctly
        let our_sid = format!("[BPQCHATSERVER-{}]", VERSION);
        assert!(ChatConnection::parse_sid(&our_sid).is_some());
    }
}
