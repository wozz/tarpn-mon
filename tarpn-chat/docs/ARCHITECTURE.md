# tarpn-chat Architecture

## Overview

tarpn-chat is a NetROM chat node that connects to LinBPQ via "NetROM over TCP". It participates in the BPQ Chat network, exchanging messages with other chat nodes and serving local clients via WebSocket.

## Layer Model

```
┌─────────────────────────────────────────────────────────────────┐
│                     Application Layer                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │ Chat Proto  │  │ Client API  │  │ State Management        │  │
│  │ (protocol.rs)│  │(client_api) │  │ (users, nodes, topics)  │  │
│  └──────┬──────┘  └──────┬──────┘  └───────────┬─────────────┘  │
│         │                │                      │                │
│         └────────────────┼──────────────────────┘                │
│                          │                                       │
│                    ┌─────▼─────┐                                 │
│                    │  server.rs │ (orchestration)                │
│                    └─────┬─────┘                                 │
└──────────────────────────┼───────────────────────────────────────┘
                           │
              ═══════════════════════════  Stream Interface
                           │                (AsyncRead/AsyncWrite
                           │                 or channel of bytes)
┌──────────────────────────┼───────────────────────────────────────┐
│                    Transport Layer (L4)                          │
│                    ┌─────▼─────┐                                 │
│                    │ session.rs │                                │
│                    └─────┬─────┘                                 │
│    - CREQ/CACK handshake │                                       │
│    - INFO/IACK reliable  │                                       │
│      data transfer       │                                       │
│    - DREQ/DACK disconnect│                                       │
│    - Sequence numbers    │                                       │
│    - Retransmission      │                                       │
│    - Flow control        │                                       │
└──────────────────────────┼───────────────────────────────────────┘
                           │
┌──────────────────────────┼───────────────────────────────────────┐
│                    Network Layer (L3)                            │
│                    ┌─────▼─────┐                                 │
│                    │ netrom.rs  │                                │
│                    └─────┬─────┘                                 │
│    - L3 header (src/dest│node, TTL)                              │
│    - L4 header (circuit,│seq, opcode)                            │
│    - Frame parsing      │                                        │
└──────────────────────────┼───────────────────────────────────────┘
                           │
┌──────────────────────────┼───────────────────────────────────────┐
│                    Link Layer (TCP Framing)                      │
│                    ┌─────▼──────┐                                │
│                    │transport.rs │                               │
│                    └─────┬──────┘                                │
│    - Length-prefixed     │                                       │
│      frames              │                                       │
│    - TCP connection      │                                       │
│      management          │                                       │
└──────────────────────────┼───────────────────────────────────────┘
                           │
                           ▼
                    ┌─────────────┐
                    │   LinBPQ    │
                    │ NETROMPORT  │
                    └─────────────┘
```

## Layer Responsibilities

### Link Layer (`transport.rs`)

**Purpose**: Reliable delivery of NetROM frames over TCP.

**Wire Format** (NetROM over TCP):
```
┌──────────────┬─────────────┬─────┬────────────────────┐
│ Length (2B)  │ Call (10B)  │ PID │ NetROM Frame       │
│ little-end   │ ASCII pad   │ CF  │ (L3 + L4 headers   │
│              │             │     │  + payload)        │
└──────────────┴─────────────┴─────┴────────────────────┘
```

**Interface**:
```rust
impl NetromTransport {
    async fn connect(addr: &str, our_call: &Callsign) -> Result<Self>;
    async fn send_frame(&mut self, frame: &NetromFrame) -> Result<()>;
    async fn recv_frame(&mut self) -> Result<ReceivedFrame>;
}
```

**Does NOT**:
- Interpret frame contents beyond basic routing
- Manage sessions or circuits
- Handle retransmission

### Network Layer (`netrom.rs`)

**Purpose**: Frame structure definitions and parsing.

**L3 Header** (15 bytes):
```
Dest Node Call (7B) + Source Node Call (7B) + TTL (1B)
```

**L4 Header** (5 bytes):
```
Circuit Index (1B) + Circuit ID (1B) + TX Seq (1B) + RX Seq (1B) + Opcode+Flags (1B)
```

**Opcodes**:
| Opcode | Name | Purpose |
|--------|------|---------|
| 1 | CREQ | Connection request |
| 2 | CACK | Connection acknowledge |
| 3 | DREQ | Disconnect request |
| 4 | DACK | Disconnect acknowledge |
| 5 | INFO | Data frame |
| 6 | IACK | Data acknowledge |

**Interface**:
```rust
impl NetromFrame {
    fn parse(data: &[u8]) -> Option<Self>;
    fn encode(&self) -> Vec<u8>;
    fn connect_request(...) -> Self;
    fn connect_ack(...) -> Self;
    fn info(...) -> Self;
    // etc.
}
```

### Transport Layer (`session.rs`, `routing.rs`)

**Purpose**: Reliable, ordered byte stream between two endpoints.

**Session State Machine**:
```
                    ┌──────────────┐
                    │ Disconnected │
                    └──────┬───────┘
                           │ connect()
                           ▼
                    ┌──────────────┐
            ┌───────│  Connecting  │
            │       └──────┬───────┘
            │              │ recv CACK
            │              ▼
            │       ┌──────────────┐
            │       │  Connected   │◄─────────┐
            │       └──────┬───────┘          │
            │              │ disconnect()     │ recv INFO
            │              ▼                  │ send INFO
            │       ┌──────────────┐          │
            │       │Disconnecting │──────────┘
            │       └──────┬───────┘
            │              │ recv DACK
            │              ▼
            └──────►┌──────────────┐
                    │ Disconnected │
                    └──────────────┘
```

**Interface to Application Layer**:
```rust
/// Events delivered to the application
enum SessionEvent {
    /// L4 connection established - ready to send/receive data
    Connected,
    /// L4 connection closed
    Disconnected { reason: String },
    /// Data received from peer (reliable, in-order bytes)
    DataReceived(Vec<u8>),
}

/// Methods available to application
impl Session {
    /// Send data to peer (will be delivered reliably, in-order)
    fn send(&mut self, data: &[u8]) -> Vec<NetromFrame>;
}
```

**Key Principle**: The application layer receives `DataReceived(bytes)` events. These bytes are:
- **Reliable**: Guaranteed to arrive (or connection closes)
- **Ordered**: Delivered in the order sent
- **Stream-oriented**: May be fragmented differently than sent

The transport layer handles:
- Sequence numbers and acknowledgments
- Retransmission on timeout
- Flow control (window)
- Circuit management

**Does NOT**:
- Parse the data contents
- Know about chat protocol
- Handle application-level handshakes

### Application Layer (`server.rs`, `protocol.rs`)

**Purpose**: Chat protocol implementation.

**Chat Protocol Format**:
```
Messages are CR-delimited text:
    <message>\r<message>\r<message>\r

Control messages start with ^A (0x01):
    ^A<type><space-separated-args>\r

Types:
    K - Keepalive    ^KNODE DEST VERSION\r
    N - NodeLink     ^NNODE NEWNODE ALIAS VERSION\r
    J - Join         ^JNODE USER NAME QTH\r
    L - Leave        ^LNODE USER\r
    T - Topic        ^TNODE USER TOPIC\r
    D - Data         ^DNODE USER TEXT\r
    ...
```

**Connection Handshake** (application level, over L4 stream):
```
Outbound:
    1. L4 Connected event
    2. Wait for SID: "[BPQChatServer-x.x.x]\r"
    3. Send: "*RTL\r"
    4. Send: "^KOURNODE THEIRNODE VERSION\r"
    5. Wait for: "OK\r"
    6. Send: "^NOURNODE OURNODE OURALIAS VERSION\r"
    7. Exchange messages...

Inbound:
    1. L4 Connected event
    2. Send SID: "[BPQCHATSERVER-x.x.x]\r"
    3. Wait for: "*RTL\r"
    4. Send: "OK\r"
    5. Send: "^NOURNODE OURNODE OURALIAS VERSION\r"
    6. Exchange messages...
```

**Interface**:
```rust
/// Receives stream of bytes from L4, parses into messages
struct ChatConnection {
    /// Buffer for incomplete messages
    buffer: String,
    /// Connection state (handshaking, linked, etc.)
    state: ChatState,
}

impl ChatConnection {
    /// Process bytes from L4 DataReceived
    fn receive_data(&mut self, data: &[u8]) -> Vec<ChatEvent>;

    /// Encode a chat message to send
    fn encode_message(&self, msg: &Message) -> Vec<u8>;
}

enum ChatEvent {
    HandshakeComplete,
    Message(Message),
    Error(String),
}
```

## Data Flow Examples

### Outbound Connection

```
1. Config has peer: TEST6-9

2. Server creates L4 session:
   session_mgr.create_outbound("TEST6-9", "TEST6-1")

3. Server initiates connection:
   frames = session_mgr.connect(&session_id)
   transport.send_frames(frames)  // sends CREQ

4. Transport receives CACK:
   frame = transport.recv_frame()
   events = session_mgr.handle_frame(frame)
   // events = [Connected]

5. Application receives Connected:
   // Create ChatConnection for this session
   // Wait for SID...

6. Transport receives INFO with SID:
   frame = transport.recv_frame()
   events = session_mgr.handle_frame(frame)
   // events = [DataReceived("[BPQChatServer-6.0.25]\r")]

7. Application processes:
   chat_events = chat_conn.receive_data(data)
   // chat_events = [ReceivedSid("6.0.25")]
   // Send *RTL, keepalive, wait for OK, send NodeLink...
```

### Inbound Connection

```
1. Transport receives CREQ:
   frame = transport.recv_frame()
   events = session_mgr.handle_frame(frame)
   // Creates session, returns [Transmit([CACK]), Connected]

2. Transport sends CACK:
   transport.send_frames(cack_frames)

3. Application receives Connected:
   // Create ChatConnection
   // Send SID

4. Transport receives INFO with *RTL:
   events = session_mgr.handle_frame(frame)
   // events = [DataReceived("*RTL\r^K...\r")]

5. Application processes:
   chat_events = chat_conn.receive_data(data)
   // Send OK, NodeLink...
```

## File Organization

```
src/
├── main.rs          # Entry point, config loading
├── lib.rs           # Module declarations
│
├── transport.rs     # TCP framing (Link layer)
├── netrom.rs        # Frame structures (Network layer)
├── session.rs       # L4 state machine (Transport layer)
├── routing.rs       # Session manager, circuit allocation
│
├── protocol.rs      # Chat message parsing (Application)
├── server.rs        # Orchestration, chat handshake (Application)
├── state.rs         # Shared state (users, nodes, topics)
├── client_api.rs    # WebSocket API for local clients
│
├── config.rs        # Configuration structures
└── utils.rs         # Utilities
```

## Key Design Decisions

1. **Clean Layer Separation**: L4 provides bytes, application interprets them. No chat-specific code in transport layer.

2. **Session Events**: The transport layer communicates via events (Connected, DataReceived, Disconnected), not callbacks.

3. **Buffering**: Message reassembly from CR-delimited stream happens in the application layer, not transport.

4. **Error Handling**: L4 errors result in Disconnected events. Application decides whether to reconnect.

5. **Multiple Sessions**: The session manager tracks multiple concurrent sessions (to different peers).
