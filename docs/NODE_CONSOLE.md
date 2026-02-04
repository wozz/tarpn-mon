# BPQ Node Console Protocol

This document describes the BPQ Node console commands and TNC2 emulation API for implementing a node terminal interface in tarpn-mon.

## Overview

The Node Console provides direct access to the BPQ node command interface, allowing users to:
- View network status (nodes, routes, links)
- Connect to other stations and nodes
- Monitor port activity
- Access TNC2 emulation mode
- Execute sysop commands (with authentication)

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   BPQ Node      │     │   tarpn-mon     │     │  Mobile/Web     │
│   Command Prompt│◄───►│   Go Backend    │◄───►│  Client         │
│   (Port 8010)   │     │   (Port 8212)   │     │                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘
      Telnet              WebSocket /ws/node
```

## Connection Flow

1. **Connect** to BPQ telnet port (default 8010)
2. **Authenticate** with callsign and password
3. **Receive node prompt** - e.g., `N0CALL de MYNODE>`
4. **Execute commands** at the node prompt
5. **Enter applications** - BBS, CHAT, etc.
6. **Return to node** - or disconnect

## Node Prompt Commands

### Connection Commands

| Command | Description |
|---------|-------------|
| `C CALL` | Connect to station |
| `C PORT CALL` | Connect via specific port |
| `C 2 CALL` | Force Layer 2 connection |
| `C PORT CALL VIA DIGI` | Connect via digipeaters |
| `ATTACH PORT` | Gain exclusive port control |
| `BYE` / `QUIT` | Disconnect from node |

**Connect Examples:**
```
C W1ABC           # Connect to W1ABC via best route
C 2 W1ABC         # Layer 2 connect to W1ABC
C 3 W1ABC VIA W2DIGI  # Connect via port 3 using digipeater
```

### Network Information

| Command | Description |
|---------|-------------|
| `N` or `NODES` | List NETROM nodes table |
| `N CALL` | Filter nodes by callsign |
| `N ALIAS` | Filter nodes by alias |
| `N Q>50` | Filter nodes by quality (>50) |
| `N T` | Show round-trip times |
| `R` or `ROUTES` | List direct neighbor routes |
| `L` or `LINKS` | Show active AX.25 sessions |
| `U` or `USERS` | Show connected users |
| `P` or `PORTS` | List configured ports |

**Nodes Output Example:**
```
N0CALL de MYNODE>N
Nodes:
  W1ABC:ABCND  Q:200  Port 2
  W2XYZ:XYZND  Q:180  Port 3
  W3DEF:DEFND  Q:150  via W1ABC
```

**Routes Output Example:**
```
N0CALL de MYNODE>R
Routes:
  Port 2: W1ABC-1 (Q:200, 15 frames)
  Port 3: W2XYZ-1 (Q:180, 8 frames)
```

### Heard Stations (MHEARD)

| Command | Description |
|---------|-------------|
| `MH PORT` | List heard stations on port |
| `MH PORT CALL` | Filter by callsign prefix |
| `MHV PORT` | Verbose output |
| `MHU PORT` | UTC timestamps |
| `MHL PORT` | Local timestamps |

**MHEARD Output Example:**
```
N0CALL de MYNODE>MH 2
Port 2 Heard:
  W1ABC-7   12:30:45  15 frames
  W2XYZ     12:28:12   8 frames
  N0CALL-9  12:25:00   3 frames
```

### Monitoring

| Command | Description |
|---------|-------------|
| `LISTEN PORT` | Monitor port traffic |
| `UNPROTO DEST` | Send UI frame |
| `UNPROTO DEST VIA DIGI` | Send UI via digipeater |

### System Information

| Command | Description |
|---------|-------------|
| `I` or `INFO` | Display node information |
| `S` or `STATS` | Display system statistics |
| `V` or `VERSION` | Display software version |
| `ARP` | Display IP ARP table |
| `AXMHEARD` | Display AXIP heard lists |

### Application Access

| Command | Description |
|---------|-------------|
| `BBS` | Enter BBS/mail application |
| `CHAT` | Enter chat application |
| `NODE` | Return to node prompt (from app) |

## TNC2 Emulation Mode

BPQ provides TNC2 emulation for compatibility with applications expecting a real TNC.

### Entering TNC Mode

From the node prompt, the TNC emulation is accessed through the telnet interface. The mode is typically entered by connecting to a specific TNC port configured in BPQ.

### TNC2 Commands

#### Monitoring

| Command | Description |
|---------|-------------|
| `MONITOR` | Display all frame activity |
| `MALL` | Monitor all frames |
| `MCOM` | Monitor command frames |
| `MCON` | Monitor connection frames |
| `BBSMON` | Compact monitor (calls only) |
| `MTX` | Monitor transmitted frames |

#### Connection Control

| Command | Description |
|---------|-------------|
| `CONOK ON/OFF` | Enable/disable incoming connections |
| `HOSTOK` | Allow sysop connections |
| `NODE` or `K` | Return to node mode |

#### Transmission

| Command | Description |
|---------|-------------|
| `CONV` | Enter conversation mode |
| `TRANS` | Enter transmit mode |
| `UNPROTO DEST` | Set unproto destination |
| `SENDPAC` | Send packet |

#### Configuration

| Command | Description |
|---------|-------------|
| `ECHO ON/OFF` | Toggle local echo |
| `AUTOLF ON/OFF` | Toggle auto line feed |
| `CTEXT` | Set connection text |
| `CMSG` | Set connection message |
| `PASS` | Set password |
| `CHANNELS` | Configure stream count (max 26) |

## Sysop Commands

These commands may require authentication or elevated privileges:

| Command | Description |
|---------|-------------|
| `AGWSTATUS` | AGW emulator status |
| `TELSTATUS PORT` | Telnet server status |
| `PING a.b.c.d` | ICMP ping (IP Gateway) |
| `AXRESOLVER PORT` | AXIP resolver table |

## Protocol Details

### Prompt Format

The node prompt format:
```
USERCALL de NODECALL>
```

Example:
```
N0CALL de MYNODE>
```

### Command Parsing

- Commands are case-insensitive
- Single-letter abbreviations are supported (C for CONNECT, N for NODES)
- Parameters are space-separated
- Some commands support filters and modifiers

### Response Format

**Node List:**
```
Nodes:
  CALL:ALIAS  Q:quality  Port N [via RELAY]
```

**Routes:**
```
Routes:
  Port N: CALL-SSID (Q:quality, N frames)
```

**Links:**
```
Links:
  CALL1 <-> CALL2  Port N  duration  bytes
```

**Users:**
```
Users:
  N0CALL  connected 00:15:30  via Port 2
```

## Implementation Notes

### State Machine

```
DISCONNECTED
    │
    ▼ (connect + auth)
NODE_PROMPT ◄──────────────────────────┐
    │                                   │
    ├── (N, R, L, U, P, etc.) ──────────┤ (info response)
    │                                   │
    ├── (C CALL) ───► CONNECTING        │
    │                    │              │
    │                    ▼              │
    │               CONNECTED ──────────┤ (disconnect)
    │                                   │
    ├── (BBS) ───► BBS_MODE             │
    │                 │                 │
    │                 ▼ (NODE or B)     │
    │                ─┘─────────────────┤
    │                                   │
    ├── (CHAT) ──► CHAT_MODE            │
    │                 │                 │
    │                 ▼ (/bye)          │
    │                ─┘─────────────────┤
    │                                   │
    ├── (LISTEN) ──► MONITORING         │
    │                 │                 │
    │                 ▼ (Ctrl+C)        │
    │                ─┘─────────────────┘
    │
    ▼ (BYE/QUIT)
DISCONNECTED
```

### Output Parsing

**Node list parsing:**
- Lines with callsign:alias pattern
- Quality indicated by Q:number
- Port or via routing information

**MHEARD parsing:**
- Callsign with optional SSID
- Timestamp (format varies by MHU/MHL option)
- Frame count

### Interactive vs Batch Mode

The node console can operate in:
- **Interactive mode** - Real-time terminal with prompts
- **Batch mode** - Send command, receive response, process

For a web/mobile interface, batch mode is typically more practical:
1. Send command
2. Collect response lines until prompt returns
3. Parse and display formatted results

## Go Implementation Plan

### Files to Create

- **`node.go`** - Node console client implementation
- **`node_websocket.go`** - WebSocket handler for node API

### NodeClient Struct

```go
type NodeClient struct {
    hostname     string
    port         int
    callsign     string
    password     string

    conn         net.Conn
    connected    bool
    mu           sync.RWMutex

    prompt       string  // Current node prompt

    ctx          context.Context
    cancel       context.CancelFunc
}

type NodeInfo struct {
    Call     string `json:"call"`
    Alias    string `json:"alias"`
    Quality  int    `json:"quality"`
    Port     int    `json:"port"`
    Via      string `json:"via,omitempty"`
}

type RouteInfo struct {
    Port     int    `json:"port"`
    Call     string `json:"call"`
    Quality  int    `json:"quality"`
    Frames   int    `json:"frames"`
}

type HeardStation struct {
    Call      string `json:"call"`
    Timestamp string `json:"timestamp"`
    Frames    int    `json:"frames"`
}
```

### WebSocket API

Endpoint: `/ws/node`

**Client Commands:**

```json
// Execute raw command
{"cmd": "exec", "command": "N"}

// Get nodes list
{"cmd": "nodes"}

// Get routes
{"cmd": "routes"}

// Get heard stations
{"cmd": "mheard", "port": 2}

// Get users
{"cmd": "users"}

// Get links
{"cmd": "links"}

// Connect to station
{"cmd": "connect", "call": "W1ABC"}

// Enter BBS mode
{"cmd": "bbs"}

// Enter Chat mode
{"cmd": "chat"}

// Send text (when connected)
{"cmd": "send", "text": "Hello"}

// Disconnect
{"cmd": "disconnect"}

// Get status
{"cmd": "status"}
```

**Server Messages:**

```json
// Command output
{"type": "node_output", "lines": ["...", "..."]}

// Nodes list
{"type": "node_nodes", "nodes": [...]}

// Routes list
{"type": "node_routes", "routes": [...]}

// Heard stations
{"type": "node_mheard", "stations": [...]}

// Connection status
{"type": "node_status", "connected": true, "prompt": "N0CALL de MYNODE>"}

// Error
{"type": "node_error", "message": "Connection failed"}
```

## React Native UI Plan

### NodeScreen.js

Features:
- Terminal-style interface with scrolling output
- Command input at bottom
- Quick-action buttons for common commands
- Connection status indicator
- Port selection for port-specific commands

### Terminal View

```
┌────────────────────────────────────┐
│ Node Console              [Status] │
├────────────────────────────────────┤
│ N0CALL de MYNODE>N                 │
│ Nodes:                             │
│   W1ABC:ABCND  Q:200  Port 2       │
│   W2XYZ:XYZND  Q:180  Port 3       │
│                                    │
│ N0CALL de MYNODE>MH 2              │
│ Port 2 Heard:                      │
│   W1ABC-7   12:30:45  15 frames    │
│   W2XYZ     12:28:12   8 frames    │
│                                    │
│ N0CALL de MYNODE>_                 │
├────────────────────────────────────┤
│ [Nodes][Routes][MH][Users][Links]  │
├────────────────────────────────────┤
│ [Command input...            ][>]  │
└────────────────────────────────────┘
```

### Quick Actions Bar

Common commands as tap-able buttons:
- **Nodes** - Execute `N`
- **Routes** - Execute `R`
- **MH** - Execute `MH` (with port picker)
- **Users** - Execute `U`
- **Links** - Execute `L`
- **Info** - Execute `I`
- **Stats** - Execute `S`

### Connection Mode

When connected to another station, the UI changes:
- Show "Connected to CALL" status
- Input sends text to connected station
- Add "Disconnect" button
- Optionally show connection duration

## Integration with Existing Features

### Relationship to Chat

The Node Console and Chat are separate but related:
- Both connect to same BPQ telnet port
- Node Console is the "outer" layer
- Chat is entered via `CHAT` command from node
- Can switch between them using `NODE` and `CHAT` commands

### Relationship to BBS

Similar to Chat:
- BBS is entered via `BBS` command from node
- Return to node with `NODE` or `B` command
- Both share the same telnet connection

### Connection Sharing

Consider whether to:
1. **Separate connections** - Each feature has its own telnet session
2. **Shared connection** - Single connection, multiplex between modes

Current implementation (chat) uses separate connection. This is simpler but uses more resources.

## References

- [BPQ32 Node Commands](https://www.cantab.net/users/john.wiseman/Documents/NodeCommands.html)
- [BPQ Host Mode Emulator](https://www.cantab.net/users/john.wiseman/Documents/BPQ%20Host%20Mode%20Emulator.htm)
- [BPQ Configuration File](https://www.cantab.net/users/john.wiseman/Documents/BPQCFGFile.html)
- [TARPN G8BPQ TNC2 Emulation](https://tarpn.net/t/builder/g8bpq/g8bpq_tnc2_emulation.html)
- [LinBPQ Cmd.c](https://github.com/g8bpq/linbpq/blob/master/Cmd.c)
