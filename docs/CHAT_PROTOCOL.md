# LinBPQ Chat Protocol Specification

This document describes the LinBPQ chat server protocol for implementing a compatible chat node.

## Overview

The LinBPQ chat system is a distributed mesh network where nodes form peer-to-peer connections and propagate user events and messages using a simple text-based protocol. Messages are flooded to all connected nodes with loop prevention via node tracking.

## Network Architecture

### Mesh Topology
- Nodes are **explicitly configured** - no auto-discovery
- Each node defines its peer nodes in configuration
- Links are bidirectional - both sides must configure each other
- Messages flood through the mesh with loop prevention

### Key Concepts
- **Node**: A chat server instance (identified by callsign)
- **Link**: A connection between two nodes (p_linked)
- **User**: A person connected to a node (p_user)
- **Topic**: A chat room/channel (default: "General")
- **Circuit**: An active connection (can be link or user)

## Protocol Format

All control messages use this format:
```
<FORMAT><TYPE><data>\r
```

Where:
- `FORMAT` = 0x01 (Ctrl-A)
- `TYPE` = Single ASCII character identifying message type
- `data` = Space-delimited fields
- `\r` = Carriage return terminator

## Message Types

### User Messages

| Type | Format | Description |
|------|--------|-------------|
| `J` | `^AJ<node> <user> <name> <qth>` | User joined chat |
| `L` | `^AL<node> <user> <name> <qth>` | User left chat |
| `D` | `^AD<node> <user> <text>` | Broadcast message to topic |
| `S` | `^AS<node> <from> <to> <text>` | Private message |
| `T` | `^AT<node> <user> <topic>` | User changed topic |
| `I` | `^AI<node> <user> <name> <qth>` | User info update |

### Node Messages

| Type | Format | Description |
|------|--------|-------------|
| `N` | `^AN<node> <newnode> <alias> [version]` | Node link established |
| `Q` | `^AQ<node> <lostnode>` | Node link dropped |

### Link Maintenance

| Type | Format | Description |
|------|--------|-------------|
| `K` | `^AK<srcnode> <destnode> [version]` | Keepalive (every 10 min) |
| `P` | `^AP<srcnode> <destnode>` | Poll request (after 60s idle) |
| `R` | `^AR<srcnode> <destnode>` | Poll response |

Note: `^A` represents ASCII 0x01.

## Connection Handshake

### Incoming Connection (we are the server)

```
Remote                              Us
  |                                  |
  |--- (TCP connect) --------------->|
  |<-- [BPQCHATSERVER-x.x.x.x] ------|  (SID)
  |--- *RTL ------------------------>|  (request link)
  |--- ^AK TheirNode OurNode Ver --->|  (keepalive)
  |<-- OK ---------------------------|  (accept)
  |<-- ^AK OurNode TheirNode Ver ----|  (our keepalive)
  |<-- ^AN OurNode Node1 Alias ------|  (our known nodes)
  |<-- ^AJ OurNode User1 Name QTH ---|  (our known users)
  |--- ^AN TheirNode Node2 Alias --->|  (their known nodes)
  |--- ^AJ TheirNode User2 Name ---->|  (their known users)
```

### Outgoing Connection (we are the client)

1. Connect to peer (may require connect script for multi-hop)
2. Wait for SID: `[BPQCHATSERVER-x.x.x.x]`
3. Send `*RTL\r`
4. Send keepalive: `^AK<OurNode> <TheirNode> <Version>\r`
5. Wait for `OK\r`
6. Exchange state (nodes and users)

### Validation Rules
- Reject if node already known (loop prevention)
- Reject if not in configured peer list
- Reject if `*RTL` not received within timeout

## Message Routing

### Flooding Algorithm
When receiving a control message:
1. Check if from known node (reject if unknown)
2. Check for duplicates (5-second window, same user+text)
3. Process locally (update state, notify local users)
4. Forward to all other linked nodes EXCEPT:
   - The circuit it came from
   - Circuits where the source node is reachable (loop prevention)

### Loop Prevention
Each circuit tracks which nodes are reachable through it:
- When a node announces via a circuit, associate node with that circuit
- Never forward messages back toward their source node
- Reference counting handles nodes reachable via multiple paths

### Topic-Based Filtering
- Track which topics have users on each circuit
- Only forward messages to circuits with users in that topic
- Topics are created on first use, removed when empty

## Duplicate Detection

```go
type DupEntry struct {
    Time time.Time
    User string    // First 10 chars
    Text string    // First 100 chars
}

const (
    MaxDups     = 10
    DupWindow   = 5 * time.Second
)
```

Check before processing any received message. Store after processing.

## Keepalive/Polling

### Keepalive (every 10 minutes)
- Send `^AK<OurNode> <TheirNode> <Version>\r` to all links
- Only if local users are connected
- If no users, close all links instead

### Polling (after 60 seconds of inactivity)
1. Send `^AP<OurNode> <TheirNode>\r`
2. Wait up to 30 seconds for `^AR` response
3. If no response, disconnect the link

### Responding to Keepalive/Poll
- On `^AK`: Send `^AR<OurNode> <TheirNode>\r`
- On `^AP`: Send `^AR<OurNode> <TheirNode>\r`

## State Management

### Node Tracking
```go
type Node struct {
    Call    string
    Alias   string
    Version string
    Circuits []Circuit  // Which links can reach this node
}
```

### User Tracking
```go
type User struct {
    Call      string
    Name      string
    QTH       string
    Node      *Node      // Which node they're connected to
    Circuit   *Circuit   // Which link they came from (nil if local)
    Topic     *Topic
    LastMsg   time.Time
    Connected time.Time
}
```

### Topic Tracking
```go
type Topic struct {
    Name     string
    Users    []*User
    Circuits map[*Circuit]int  // Reference count per circuit
}
```

## User-Facing Commands

Local users can send these commands:

| Command | Description |
|---------|-------------|
| `/users` | List all connected users |
| `/nodes` | List all known nodes |
| `/t <topic>` | Change topic |
| `/n <name>` | Set display name |
| `/q <qth>` | Set QTH/location |
| `/quit` or `/bye` | Disconnect |
| `/msg <user> <text>` | Private message |
| `/keepalive` | Toggle keepalive messages |

## Anti-Storm Protection

- Ignore `^AL` (leave) if user connected < 3 seconds
- Ignore `^AQ` (unlink) if node connected < 3 seconds
- Duplicate detection prevents message loops

## Configuration

### Required Settings
- `OurNode`: Our callsign (e.g., "WA2M-9")
- `OurAlias`: Our alias (e.g., "BOT")
- `Peers`: List of peer nodes to connect to

### Peer Configuration Format
```
ALIAS:CALLSIGN|ConnectCmd1|ConnectCmd2|...
```

Examples:
- Simple: `RDGCHT:GB7RDG-1` (connects directly)
- With script: `RDGCHT:GB7RDG-1|C STHGTE|C RDGCHT` (multi-hop)

---

# Implementation Plan

## Phase 1: Core Data Structures

```go
package chatserver

type ChatServer struct {
    OurNode     string
    OurAlias    string
    Version     string

    nodes       map[string]*Node      // All known nodes
    users       map[string]*User      // All known users
    links       map[string]*Link      // Configured peers
    circuits    map[int]*Circuit      // Active connections
    topics      map[string]*Topic     // Active topics

    dupCache    *DupCache

    mu          sync.RWMutex
}

type Circuit struct {
    ID          int
    Conn        net.Conn
    Type        CircuitType  // LinkIncoming, LinkOutgoing, LocalUser
    Link        *Link        // If node link
    User        *User        // If local user
    Nodes       map[string]*Node  // Nodes reachable via this circuit
    Topics      map[string]int    // Topics with users on this circuit
}

type Link struct {
    Alias         string
    Call          string
    ConnectScript []string
    State         LinkState  // Disconnected, Connecting, Connected
    Circuit       *Circuit
    LastReceived  time.Time
    PollSent      time.Time
}
```

## Phase 2: Connection Handling

1. **Listener**: Accept incoming connections on configured port
2. **Outgoing Manager**: Periodically try to connect to configured peers
3. **Handshake Handler**:
   - Send/receive SID
   - Process `*RTL`
   - Exchange state

```go
func (s *ChatServer) handleIncoming(conn net.Conn) {
    // Send SID
    fmt.Fprintf(conn, "[BPQCHATSERVER-%s]\r", s.Version)

    // Read first line - expect *RTL or user input
    line := readLine(conn)

    if line == "*RTL" {
        s.handleNodeLink(conn)
    } else {
        s.handleLocalUser(conn, line)
    }
}

func (s *ChatServer) handleNodeLink(conn net.Conn) {
    // Validate against configured peers
    // Check for loops
    // Send OK
    // Exchange state
    // Start message loop
}
```

## Phase 3: Message Processing

```go
func (s *ChatServer) processMessage(circuit *Circuit, msg []byte) {
    if msg[0] != 0x01 {
        // Plain text from local user
        s.handleUserText(circuit, string(msg))
        return
    }

    msgType := msg[1]
    data := string(msg[2:])

    switch msgType {
    case 'J': s.handleJoin(circuit, data)
    case 'L': s.handleLeave(circuit, data)
    case 'D': s.handleData(circuit, data)
    case 'N': s.handleNodeLink(circuit, data)
    case 'Q': s.handleNodeUnlink(circuit, data)
    case 'T': s.handleTopic(circuit, data)
    case 'K': s.handleKeepalive(circuit, data)
    case 'P': s.handlePoll(circuit, data)
    case 'R': s.handlePollResponse(circuit, data)
    // ...
    }
}
```

## Phase 4: Message Forwarding

```go
func (s *ChatServer) forward(fromCircuit *Circuit, sourceNode string, msg []byte) {
    node := s.nodes[sourceNode]
    if node == nil {
        return
    }

    for _, circuit := range s.circuits {
        // Skip source circuit
        if circuit == fromCircuit {
            continue
        }

        // Skip if node reachable via this circuit (loop prevention)
        if _, ok := circuit.Nodes[sourceNode]; ok {
            continue
        }

        // For data messages, check topic filtering
        // ...

        circuit.Conn.Write(msg)
    }
}
```

## Phase 5: Local User Handling

```go
func (s *ChatServer) handleLocalUser(conn net.Conn, firstLine string) {
    // Create user
    user := &User{
        Call: extractCall(conn),
        // ...
    }

    // Prompt for name if new
    // Add to default topic
    // Announce to network (^AJ)
    // Start message loop
}

func (s *ChatServer) handleUserText(circuit *Circuit, text string) {
    user := circuit.User

    if strings.HasPrefix(text, "/") {
        s.handleCommand(circuit, text)
        return
    }

    // Create data message
    msg := fmt.Sprintf("\x01D%s %s %s\r", s.OurNode, user.Call, text)

    // Send to local users in same topic
    s.sendToTopic(user.Topic, user, text)

    // Forward to linked nodes
    s.forwardToLinks(user.Topic, msg)
}
```

## Phase 6: Timers and Maintenance

```go
func (s *ChatServer) runMaintenance() {
    keepaliveTicker := time.NewTicker(10 * time.Minute)
    pollTicker := time.NewTicker(10 * time.Second)

    for {
        select {
        case <-keepaliveTicker.C:
            s.sendKeepalives()

        case <-pollTicker.C:
            s.checkIdleLinks()
        }
    }
}

func (s *ChatServer) checkIdleLinks() {
    now := time.Now()

    for _, circuit := range s.circuits {
        if circuit.Type != LinkType {
            continue
        }

        idle := now.Sub(circuit.Link.LastReceived)

        if idle > 60*time.Second {
            if circuit.Link.PollSent.IsZero() {
                // Send poll
                s.sendPoll(circuit)
            } else if now.Sub(circuit.Link.PollSent) > 30*time.Second {
                // No response - disconnect
                s.disconnectCircuit(circuit)
            }
        }
    }
}
```

## Phase 7: WebSocket API

```go
func (s *ChatServer) setupWebSocket() {
    http.HandleFunc("/ws/chat", s.handleWebSocket)
}

func (s *ChatServer) handleWebSocket(w http.ResponseWriter, r *http.Request) {
    // Upgrade connection
    // Create virtual local user
    // Bridge WebSocket <-> chat protocol
}
```

## Phase 8: Integration with LinBPQ

Two options for connecting to the packet network:

### Option A: Via Telnet to LinBPQ
- Connect to LinBPQ telnet port
- Authenticate
- The chat server acts as a client to LinBPQ
- LinBPQ handles RF/AX.25

### Option B: Direct BPQ32 Integration
- Use TNCPORT/COMPORT interface
- Requires deeper integration
- More complex but lower latency

Recommendation: Start with Option A for simplicity.

---

## File Structure

```
chatserver/
  cmd/
    chatserver/
      main.go           # Entry point
  internal/
    protocol/
      messages.go       # Message parsing/formatting
      handshake.go      # Connection handshake
    server/
      server.go         # Main server logic
      circuit.go        # Circuit management
      routing.go        # Message routing
      users.go          # User management
      topics.go         # Topic management
    storage/
      users.go          # User persistence
  api/
    websocket.go        # WebSocket API
    handlers.go         # HTTP handlers
```

## Testing Strategy

1. **Unit tests**: Message parsing, duplicate detection, routing logic
2. **Integration tests**: Two chat servers connecting to each other
3. **Compatibility tests**: Connect to real LinBPQ chat network
