# TARPN Monitor Chat Client

This document describes the chat client implementation in tarpn-mon, which enables real-time chat with other users connected to BPQ packet nodes.

## Overview

The chat feature consists of three main components:

1. **Go Backend Chat Client** (`chat.go`, `chat_websocket.go`) - Connects to the BPQ node and handles the chat protocol
2. **WebSocket API** (`/ws/chat`) - Exposes chat functionality to web/mobile clients
3. **React Native Chat Screen** (`ChatScreen.js`) - User interface for sending and receiving messages

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   BPQ Node      │     │   tarpn-mon     │     │  Mobile/Web     │
│   Chat Server   │◄───►│   Go Backend    │◄───►│  Client         │
│   (Port 8010)   │     │   (Port 8212)   │     │                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘
      Telnet              WebSocket /ws/chat
```

## BPQ Chat Protocol

The BPQ chat protocol was reverse-engineered from the LinBPQ source code, specifically:

- **Protocol Definitions**: [`bpqchat.h`](https://github.com/g8bpq/linbpq/blob/master/bpqchat.h) (lines 204-244)
- **Message Processing**: [`HanksRT.c`](https://github.com/g8bpq/linbpq/blob/master/HanksRT.c) (function `ProcessChatLine`, `chkctl`)
- **Connection Handling**: [`ChatUtils.c`](https://github.com/g8bpq/linbpq/blob/master/ChatUtils.c) (function `Connected`, `ProcessLine`)

### Protocol Format

Control messages use a binary format:

| Byte | Name | Description |
|------|------|-------------|
| 0 | FORMAT | Always `0x01` (Ctrl-A) |
| 1 | TYPE | Message type character |
| 2+ | DATA | Space-separated fields |

### Message Types

From `bpqchat.h` lines 214-224:

| Type | Char | Format | Description |
|------|------|--------|-------------|
| `id_join` | `J` | `^AJ<node> <user> <name> <qth>` | User joins chat |
| `id_leave` | `L` | `^AL<node> <user> <name> <qth>` | User leaves chat |
| `id_data` | `D` | `^AD<node> <user> <text>` | Broadcast message to all users |
| `id_send` | `S` | `^AS<node> <from> <to> <text>` | Private message to one user |
| `id_topic` | `T` | `^AT<node> <user> <topic>` | User changes topic |
| `id_link` | `N` | `^AN<node> <node> <alias>` | Node joins network |
| `id_unlink` | `Q` | `^AQ<node> <node>` | Node leaves network |
| `id_user` | `I` | `^AI<node> <user> <name> <qth>` | User login information |
| `id_keepalive` | `K` | | Node-to-node keepalive |
| `id_poll` | `P` | | Link validation poll |
| `id_pollresp` | `R` | | Link validation poll response |

### Connection Sequence

Based on `ChatUtils.c` `Connected()` function:

1. **Connect** to BPQ node telnet port (default 8010)
2. **Authenticate** with callsign and password
3. **Enter chat mode** by sending "CHAT" command
4. **Receive SID** like `[BPQChatServer-6.0.24.1]`
5. **New user prompt** - If first time, server asks for name
6. **Ready** - Start sending/receiving messages

### User Commands

Commands are prefixed with `/` (from `HanksRT.c` `rt_cmd()` function):

| Command | Description |
|---------|-------------|
| `/bye` or `/b` | Leave chat, return to node |
| `/quit` or `/q` | Leave chat and disconnect |
| `/topic <name>` or `/t` | Change to named topic |
| `/users` or `/u` | List connected users |
| `/history <minutes>` or `/hi` | Show message history |
| `/alert` or `/a` | Toggle bell on user join/leave |
| `/echo` or `/e` | Toggle echo of own messages |
| `/colour` or `/c` | Toggle color codes |
| `/keepalive` or `/k` | Toggle keepalive messages |
| `/shownames` | Toggle showing names with calls |
| `/time` | Toggle timestamps |
| `/codepage <cp>` or `/cp` | Set character encoding |
| `/utf-8` | Toggle UTF-8 mode |

## Go Backend Implementation

### Files

- **`chat.go`** - Main chat client implementation
- **`chat_websocket.go`** - WebSocket handler for chat API

### ChatClient Struct

```go
type ChatClient struct {
    hostname     string      // BPQ node hostname
    port         int         // Telnet port (default 8010)
    callsign     string      // User's callsign
    password     string      // Node password
    userName     string      // Display name

    conn         net.Conn    // TCP connection to BPQ
    connected    bool        // Connection status
    users        map[string]*ChatUser  // Connected users
    currentTopic string      // Current chat topic

    ctx          context.Context  // For cancellation
    cancel       context.CancelFunc
    messageSeq   int64       // Message sequence counter
}
```

### Protocol Mapping

| BPQ Protocol | Go Implementation |
|--------------|-------------------|
| `^AJ` (join) | `handleUserJoin()` in `chat.go:280` |
| `^AL` (leave) | `handleUserLeave()` in `chat.go:303` |
| `^AD` (data) | `handleDataMessage()` in `chat.go:325` |
| `^AT` (topic) | `handleTopicChange()` in `chat.go:346` |
| Control message parsing | `processControlMessage()` in `chat.go:232` |
| Regular message parsing | `parseUserMessage()` in `chat.go:366` |

### Message Types Sent to Clients

```go
type ChatMessage struct {
    Seq       int64      `json:"seq"`       // Sequence number
    Type      string     `json:"type"`      // Message type
    Timestamp string     `json:"timestamp"` // HH:MM:SS
    From      string     `json:"from"`      // Sender callsign
    FromName  string     `json:"fromName"`  // Sender name
    To        string     `json:"to"`        // Recipient (private msg)
    Topic     string     `json:"topic"`     // Topic name
    Message   string     `json:"message"`   // Message content
    Node      string     `json:"node"`      // Origin node
    Users     []ChatUser `json:"users"`     // User list
    Connected bool       `json:"connected"` // Status flag
}
```

Message types:
- `chat_msg` - Regular chat message
- `chat_join` - User joined
- `chat_leave` - User left
- `chat_topic` - Topic changed
- `chat_users` - User list response
- `chat_status` - Connection status
- `chat_error` - Error message

## WebSocket API

### Endpoint

`/ws/chat` - WebSocket endpoint for chat

### Client Commands

Send JSON messages to control the chat:

#### Sync (get history)
```json
{"cmd": "sync", "last_seq": 0}
```

#### Send message
```json
{"cmd": "send", "message": "Hello everyone!"}
```

#### Send command
```json
{"cmd": "command", "message": "/topic General"}
```

#### Get user list
```json
{"cmd": "users"}
```

#### Get connection status
```json
{"cmd": "status"}
```

### Server Messages

All messages from server include:
- `seq` - Sequence number for sync
- `type` - Message type
- `timestamp` - Time string

## React Native Client

### ChatScreen.js

Located at `tarpn-app/src/screens/ChatScreen.js`

Features:
- Real-time message display using FlashList
- Connection status indicator (green/red dot)
- User count display
- Text input with send button
- Keyboard-avoiding view for mobile
- Support for system messages (joins/leaves/topics)
- Message history sync on reconnect

### Message Rendering

```javascript
const ChatMessageRow = React.memo(({ item }) => {
    // Different styling based on message type:
    // - chat_join/leave/topic: Gray italic system message
    // - chat_status: Green status message
    // - chat_error: Red error message
    // - chat_msg: Normal message with timestamp, callsign, name, content
});
```

## Configuration

### Command Line Flags

| Flag | Default | Description |
|------|---------|-------------|
| `-chat` | `false` | Enable chat client |
| `-chat-port` | `8010` | BPQ telnet port for chat |
| `-chat-call` | (uses `-call`) | Callsign for chat login |
| `-chat-password` | (uses `-password`) | Password for chat login |
| `-chat-name` | (uses callsign) | Display name in chat |

### Example Usage

```bash
# Basic usage - uses same credentials as monitor
./tarpn-mon -call N0CALL -host 192.168.1.100 -chat

# With custom chat settings
./tarpn-mon -call N0CALL -host 192.168.1.100 \
    -chat \
    -chat-port 8010 \
    -chat-name "John"

# Using different callsign for chat
./tarpn-mon -call N0CALL -host 192.168.1.100 \
    -chat \
    -chat-call N0CALL-7 \
    -chat-name "John Mobile"
```

### BPQ Node Configuration

For the chat client to work, your BPQ node must have:

1. **Chat Server Enabled** - The BPQ Chat application must be configured
2. **Telnet Access** - Telnet port (usually 8010) must be accessible
3. **User Account** - Valid callsign and password for telnet login

In your BPQ configuration, ensure:
- Chat application is assigned an ApplNum
- Telnet port is configured and accessible
- User has permission to access chat

## Troubleshooting

### Connection Issues

**"Chat connection failed"**
- Check that the BPQ node is reachable at the specified host/port
- Verify telnet port is correct (usually 8010, not 8011 which is for monitor)
- Ensure callsign and password are correct

**"Timeout waiting for chat server response"**
- The BPQ node may not have chat enabled
- The telnet port may be blocked by firewall
- Try connecting manually with telnet to debug

### Message Issues

**Messages not appearing**
- Check WebSocket connection in browser developer tools
- Verify the `/ws/chat` endpoint is responding
- Check Go backend logs for errors

**Cannot send messages**
- Verify chat client shows "Connected" status
- Check that you're authenticated to the BPQ node

## Development Notes

### Adding New Message Types

1. Add constant in `chat.go` (e.g., `ID_NEWTYPE = 'X'`)
2. Add case in `processControlMessage()` switch
3. Create handler function `handleNewType()`
4. Add message type string in `ChatMessage.Type`
5. Update `ChatScreen.js` to render new type

### Testing Without BPQ Node

For development, you can create a mock telnet server that simulates BPQ chat responses. The protocol is simple text-based, making it easy to mock.

## BPQ Application Modes

BPQ supports two fundamentally different ways for applications to connect:

### 1. Internal/Embedded Applications (Port-based)

These applications run **inside the BPQ process** and use the native BPQ Stream API:

**Characteristics:**
- Configured with an **ApplNum** (1-32) which maps to an **ApplMask** (`1 << (ApplNum - 1)`)
- Pre-allocate BPQ streams at startup using `FindFreeStream()`
- Register with `SetAppl(stream, flags, ApplMask)`
- Communicate via internal message queues (`SendMsg()`/`GetMsg()`)
- Run in the same process as BPQ or as linked DLLs
- Examples: BPQ Chat Server, BPQ Mail Server

**Code example from `bpqchat.c:1333`:**
```c
ChatApplMask = 1 << (ChatApplNum - 1);
SetAppl(conn->BPQStream, 3, ChatApplMask);
```

**Configuration:**
```
APPLICATION 1,CHAT,CHAT,CHAT
```

### 2. Telnet-Connected Applications (External)

These are **external applications** that connect via TCP sockets:

**Characteristics:**
- Connect via TCP to a configured telnet port (e.g., 8010)
- BPQ's TelnetV6 driver handles the socket-to-stream bridge
- Streams allocated on-demand when connection is established
- Uses standard telnet protocol with login authentication
- Completely separate process from BPQ
- Examples: External clients, tarpn-mon chat client

**Connection flow:**
1. External app connects to BPQ telnet port
2. TelnetV6 accepts socket, creates `ConnectionInfo` structure
3. Login prompt sent, user authenticates with callsign/password
4. BPQ stream allocated when needed for packet switching
5. Data flows: Socket ↔ ConnectionInfo buffer ↔ BPQ stream

**Key source files:**
- [`TelnetV6.c`](https://github.com/g8bpq/linbpq/blob/master/TelnetV6.c) - Telnet server implementation (7000+ lines)
- `Socket_Accept()` function handles incoming connections (lines 3276-3504)

### Comparison

| Aspect | Internal Applications | Telnet-Connected (External) |
|--------|----------------------|----------------------------|
| **Location** | Inside BPQ process | Separate process |
| **Configuration** | ApplNum (1-32) | Host:Port |
| **Stream allocation** | Pre-allocated at startup | On-demand per connection |
| **Data path** | Internal BPQ queues | Socket I/O with telnet protocol |
| **Protocol** | BPQ native API | Telnet with IAC commands |
| **Network exposure** | None (internal only) | Requires open TCP port |
| **Connection method** | `SetAppl()` + `ConnectUsingAppl()` | `accept()` on listening socket |

### Our Implementation

The tarpn-mon chat client uses the **telnet-connected (external)** approach:

- We connect to BPQ as an external client via the telnet port (default 8010)
- We authenticate with callsign and password
- We enter chat mode by sending "CHAT" command
- We see chat from a **user perspective**, not as a linked node

**Advantages of this approach:**
- Simple to implement - no BPQ modifications required
- Works with any BPQ node that has telnet enabled
- Can run on a separate machine from BPQ
- Standard TCP/IP connection

**Limitations:**
- We're a client, not a native BPQ application
- We go through telnet authentication on each connection
- We don't receive node-to-node protocol messages directly

### Node-to-Node Linking (Advanced)

If we wanted to act as a **linked chat node** (like another BPQ node connecting to the chat network), we would need to:

1. Connect via telnet
2. Send `*RTL` command to initiate node-to-node link protocol
3. Handle the full control message protocol (`^AJ`, `^AL`, `^AD`, etc.)
4. Be configured as a known node in BPQ's chat configuration (`OtherChatNodes`)
5. Implement keepalive and poll/response for link validation

This is documented in `bpqchat.h` lines 246-257:
```
// Connect protocol:
// 1. Connect to node.
// 2. Send *RTL
// 3. Receive OK. Will get disconnect if link is not allowed.
// 4. Go to it.
```

The current tarpn-mon implementation does **not** use node-to-node linking - we connect as a regular user client, which is simpler and sufficient for most use cases.

## BPQ Internals Deep Dive

This section provides detailed technical information about BPQ's internal architecture for developers who want to understand how the system works at a deeper level.

### BPQ Stream API

The BPQ Stream API is the core mechanism for applications to communicate with the packet switch. Key functions from [`bpq32.h`](https://github.com/g8bpq/linbpq/blob/master/bpq32.h):

| Function | Signature | Description |
|----------|-----------|-------------|
| `GetMsg` | `int GetMsg(int stream, char* msg, int* len, int* count)` | Retrieves messages from a stream's receive queue |
| `SendMsg` | `int SendMsg(int stream, char* msg, int len)` | Transmits a message on a stream |
| `SessionControl` | `int SessionControl(int stream, int command, int param)` | Controls stream lifecycle |
| `SessionState` | `int SessionState(int stream, int* state, int* change)` | Queries current stream state |
| `FindFreeStream` | `int FindFreeStream()` | Allocates an available stream |
| `SetAppl` | `void SetAppl(int stream, int flags, int mask)` | Registers an application on a stream |

**SessionControl Commands:**
- `1` - Connect to a destination
- `2` - Disconnect the stream
- `3` - Return to Node (exit application but stay connected to BPQ)

**Stream Architecture:**
- Maximum 64 application streams supported (`BPQHOSTSTREAMS = 64`)
- Streams numbered externally 1-64, internally indexed 0-63
- Each stream maintains bidirectional queues:
  - `BPQtoPACTOR_Q` - Node to client direction
  - `PACTORtoBPQ_Q` - Client to node direction

### Connection State Machine

BPQ maintains connection state through flags and callbacks. Key structures from [`bpqchat.h`](https://github.com/g8bpq/linbpq/blob/master/bpqchat.h):

**Session Type Indicators:**
| Constant | Description |
|----------|-------------|
| `Sess_L2LINK` | Layer 2 link connection |
| `Sess_SESSION` | Regular user session |
| `Sess_UPLINK` | Outbound connection to remote node |
| `Sess_DOWNLINK` | Inbound connection from remote node |
| `Sess_BPQHOST` | Internal BPQ host application |
| `Sess_PACTOR` | PACTOR mode connection |

**Connection Flags (in ChatConnectionInfo):**
| Flag | Description |
|------|-------------|
| `p_user` | User connection (vs. node-to-node link) |
| `p_linked` | Active link to remote node |
| `p_linkini` | Link initialization in progress |
| `p_linkwait` | Waiting for link response |
| `p_linkfailed` | Link connection failed |

**Chat-Specific States:**
- `GETTINGUSER` - Server waiting for new user details
- `Watchdog = 900` - 15-minute inactivity timeout (in seconds)
- `Secure_Session` - Set after successful authentication

**State Transition Callbacks:**
```c
// Called when a stream connects - initializes ChatCIRCUIT structure
Connected(stream_number) {
    memset(conn, 0, sizeof(ChatCIRCUIT));
    // Initialize connection state
}

// Called on disconnect - clears queues, notifies other users
Disconnected(stream_number) {
    // Clear queues
    // Call link_drop() for node cleanup
    // Broadcast leave message
}
```

### Application Configuration

**ApplNum and ApplMask:**

Applications are registered with a number (1-32) that maps to a bitmask:

```c
// From bpqchat.c line 1333
ChatApplMask = 1 << (ChatApplNum - 1);
SetAppl(conn->BPQStream, 3, ChatApplMask);
```

| ApplNum | ApplMask (hex) | ApplMask (binary) |
|---------|----------------|-------------------|
| 1 | 0x00000001 | 00000001 |
| 2 | 0x00000002 | 00000010 |
| 5 | 0x00000010 | 00010000 |
| 8 | 0x00000080 | 10000000 |

**Stream Allocation Pattern (Internal Applications):**
```c
// Pre-allocate streams at startup
for (i = 0; i < MaxChatStreams; i++) {
    conn = &ChatConnections[i];
    conn->BPQStream = FindFreeStream();    // Allocate stream
    NumberofChatStreams++;
    BPQSetHandle(conn->BPQStream, hWnd);   // Register for events
    SetAppl(conn->BPQStream, 3, ChatApplMask);  // Register application
}
```

**Configuration File (BPQChatServer.cfg):**
- `MaxChatStreams` - Maximum simultaneous connections (default 64)
- `OtherChatNodes` - List of linked chat nodes
- Welcome message (supports `$W` for line breaks)

### TelnetV6 Connection Handling

The TelnetV6 driver ([`TelnetV6.c`](https://github.com/g8bpq/linbpq/blob/master/TelnetV6.c)) bridges TCP sockets to BPQ streams.

**Socket_Accept Flow (lines 3276-3504):**

1. **Socket Allocation** - Finds free session slot in `TNC->Streams[n].ConnectionInfo` array
2. **Non-blocking Setup** - `ioctl(sock, FIONBIO, &param)` enables non-blocking I/O
3. **Authentication State Machine:**

| LoginState | Action |
|------------|--------|
| 0 | Send username prompt, match against `TCP->UserRecPtr` array |
| 1 | Send password prompt (not echoed), compare to `USER->Password` |
| 2 | Call `ProcessIncommingConnect()`, set `Secure_Session` flag |

**ConnectionInfo Structure Fields:**
- Socket file descriptor
- BPQ stream identifier
- `InputBuffer` - Accumulates incoming data
- `FromHostBuffer` - Dynamic buffer (grows by 10KB chunks)
- `InputLen` - Current buffer fill level
- Login state and user authentication context
- Connection type flags (HTTP, FBB, relay, etc.)
- `SESSPACLEN` - Per-stream packet length limit

**Buffer Management:**
- Accumulates data until CR/LF found
- Handles multiple messages per read cycle via `memmove()`
- Removes backspace characters before processing
- Exception handling with graceful disconnect on errors

**Special Modes:**
- **HTTP mode** - `HTTPMode = TRUE` bypasses login
- **FBB mode** - Binary frame processing, immediate send
- **Telnet IAC** - Processed separately from user data

### Chat Protocol Parsing

**ProcessChatLine Function (HanksRT.c):**

Handles user input and message routing:
- UTF-8 validation and conversion
- Slash-prefixed input routes to `rt_cmd()` command handler
- Regular messages broadcast to topic subscribers via `ChatWriteLogLine()`

**chkctl Function (HanksRT.c):**

Processes node-to-node control messages:

```c
void chkctl(ChatCIRCUIT *ckt_from, char* Buffer, int Len) {
    // Parse control message type (first byte after FORMAT)
    // Dispatch to appropriate handler
    // Relay to other connected nodes if needed
}
```

| Message Type | Handler Action |
|--------------|----------------|
| `id_data` (D) | Broadcast with duplicate suppression |
| `id_join` (J) | Add user to node's user list |
| `id_leave` (L) | Remove user, notify other nodes |
| `id_link` (N) | Update node topology |
| `id_unlink` (Q) | Remove node from topology |
| `id_user` (I) | Update user name/location |
| `id_topic` (T) | Propagate topic change |
| `id_keepalive` (K) | Link validation heartbeat |
| `id_poll` (P) | Link validation check |
| `id_pollresp` (R) | Poll response |

### User List and Message Broadcasting

**User Tracking Structure:**
- `UserRecPtr` - Pointer to user records array
- `NumberofUsers` - Total active users counter
- Per-user fields: callsign, topic, last activity, terminal preferences

**Connection Tracking (ChatConnections array):**
- Maximum 64 simultaneous connections
- Per-connection state:
  - `conn->InputBuffer` - Accumulates user input
  - `conn->InputLen` - Current buffer fill
  - `conn->Active` - Boolean connection status
  - `conn->Watchdog` - 900 second (15 min) timeout

**Message Broadcasting Flow:**

1. **Receive** - `DoReceivedData()` accumulates data, processes complete messages
2. **Parse** - Identifies message type (user data vs control)
3. **Relay:**
   - Broadcast to all users on same topic
   - Relay to linked nodes
   - Update `LastMessageIndextoForward` for optimization

**Message Queue Architecture:**
- `MsgHddrPtr` - Message header array
- `FirstMessageIndextoForward` - Reduces search overhead for relaying
- `ChatWriteLogLine()` - Message logging function

### Window Message Integration

BPQ uses Windows message pump for asynchronous event handling:

```c
// Register window handle for stream events
BPQSetHandle(conn->BPQStream, hWnd);

// Custom message registration
BPQMsg = RegisterWindowMessage("BPQMSG");

// Window procedure dispatches events:
// - Connected(wParam) on stream connection
// - Disconnected(wParam) on stream disconnection

// Semaphore protects concurrent access
ConSemaphore = CreateSemaphore(...);
```

### Key Source Files Reference

| File | Description | Key Functions |
|------|-------------|---------------|
| [`bpq32.h`](https://github.com/g8bpq/linbpq/blob/master/bpq32.h) | API definitions | GetMsg, SendMsg, SessionControl |
| [`bpqchat.h`](https://github.com/g8bpq/linbpq/blob/master/bpqchat.h) | Chat protocol constants | Message type definitions |
| [`bpqchat.c`](https://github.com/g8bpq/linbpq/blob/master/bpqchat.c) | Chat server core | Initialise, Connected, Disconnected |
| [`HanksRT.c`](https://github.com/g8bpq/linbpq/blob/master/HanksRT.c) | Message processing | ProcessChatLine, chkctl, rt_cmd |
| [`ChatUtils.c`](https://github.com/g8bpq/linbpq/blob/master/ChatUtils.c) | Chat utilities | ProcessLine, link helpers |
| [`TelnetV6.c`](https://github.com/g8bpq/linbpq/blob/master/TelnetV6.c) | Telnet driver | Socket_Accept, authentication |

## References

- [LinBPQ Source Code](https://github.com/g8bpq/linbpq)
- [BPQ32 Documentation](https://www.cantab.net/users/john.wiseman/Documents/)
- [AX.25 Protocol](https://www.tapr.org/pdf/AX25.2.2.pdf)
