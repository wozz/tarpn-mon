# BPQ BBS (Mail Server) Protocol

This document describes the BPQ BBS protocol for implementing mail/message functionality in tarpn-mon.

## Overview

The BPQ BBS (Bulletin Board System) provides packet mail services including:
- Personal messages (P) - Private messages to specific callsigns
- Bulletins (B) - Public messages to categories
- NTS Traffic (T) - National Traffic System formatted messages

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   BPQ Node      │     │   tarpn-mon     │     │  Mobile/Web     │
│   BBS Server    │◄───►│   Go Backend    │◄───►│  Client         │
│   (Port 8010)   │     │   (Port 8212)   │     │                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘
      Telnet              WebSocket /ws/bbs
```

## Accessing the BBS

### Connection Sequence

1. **Connect** to BPQ telnet port (default 8010)
2. **Authenticate** with callsign and password
3. **Send `BBS` command** to enter mail mode
4. **Receive BBS prompt** - ready for mail commands
5. **Send `B` or `NODE`** to exit BBS mode

### Example Session

```
Connecting to node...
callsign: N0CALL
password: ****
N0CALL de MYNODE>
BBS
[LinBPQ-6.0.24.1-B2FHIM$]
N0CALL de MYNODE:MYBBS>
LM
Msg#  TS   Date   From    Size  To      Subject
1234  PN  Jan 01  W1ABC   1234  N0CALL  Hello!
R 1234
From: W1ABC
To: N0CALL
Subject: Hello!
Date: 2024-01-01 12:00

Message body here...

B
N0CALL de MYNODE>
```

## BBS Commands

### List Commands (L)

| Command | Description |
|---------|-------------|
| `L` | List new messages since last login |
| `LM` | List messages addressed to you |
| `LB` | List bulletins |
| `LL n` | List last n messages |
| `LT` | List NTS traffic messages |
| `LR` | List messages in reverse order |
| `L< CALL` | List messages from callsign |
| `L> CALL` | List messages to callsign |
| `L@ BBS` | List messages via BBS |
| `L n-m` | List messages between numbers n and m |
| `Lx` | List messages with status x (D, F, N, Y, $) |

### Read Commands (R)

| Command | Description |
|---------|-------------|
| `R n` | Read message number n |
| `R n m` | Read messages n through m |
| `RM` | Read new messages addressed to you |
| `RH n` | Read message n with full headers |

### Send Commands (S)

| Command | Description |
|---------|-------------|
| `S CALL` | Send private message to callsign |
| `SP CALL` | Send private message (explicit) |
| `S CALL @ BBS` | Send via another BBS |
| `SB CAT` | Send bulletin to category (max 6 chars) |
| `SR n` | Reply to message number n |
| `SC n CALL @ BBS` | Copy message n to another station |

### Delete Commands (K)

| Command | Description |
|---------|-------------|
| `K n` | Kill (delete) message number n |
| `KM` | Kill all read messages addressed to you |

### Navigation Commands

| Command | Description |
|---------|-------------|
| `B` or `Bye` | Exit BBS, disconnect |
| `NODE` | Exit BBS, return to node prompt |
| `?` or `Help` | Show available commands |

## Message Format

### List View Format

```
Msg#  TS   Date   From    Size  To      Subject
1234  PN  Jan 01  W1ABC   1234  N0CALL  Hello World
```

Fields:
- **Msg#** - Unique message number
- **T** - Type: P (Personal), B (Bulletin), T (Traffic)
- **S** - Status: N (New), Y (Read), F (Forwarded), K (Killed), H (Held), D (Delivered)
- **Date** - Message date
- **From** - Sender callsign
- **Size** - Message size in bytes
- **To** - Recipient callsign or category
- **Subject** - Message subject line

### Message Types

| Type | Character | Description |
|------|-----------|-------------|
| Personal | `P` | Private message to specific callsign |
| Bulletin | `B` | Public message to a category |
| Traffic | `T` | NTS formatted traffic message |

### Message Status

| Status | Character | Description |
|--------|-----------|-------------|
| New | `N` | Not yet read or delivered |
| Read | `Y` | Has been read by recipient |
| Forwarded | `F` | Has been forwarded to all stations |
| Killed | `K` | Deleted by housekeeping |
| Held | `H` | Held by sysop, not forwardable |
| Delivered | `D` | NTS message has been delivered |
| Pending | `$` | Bulletin pending delivery |

### Full Message Format

When reading a message with `R` or `RH`:

```
From: W1ABC
To: N0CALL
Type/Status: PN
Date/Time: 01-Jan-2024 12:00Z
BID: 12345_W1ABC
Subject: Hello World

Message body text here.
Can be multiple lines.

73, W1ABC
```

### Message Addressing

Simple format: `TO @ AT`

- **TO** - Destination callsign or category
- **AT** - Destination BBS for forwarding

Examples:
- `N0CALL` - Direct to callsign on local BBS
- `N0CALL @ W1BBS` - To callsign via W1BBS
- `TECH @ WW` - Bulletin to TECH category, worldwide distribution

Hierarchical addressing:
- `N0CALL @ W1BBS.#EPA.PA.USA.NOAM`

## Composing Messages

### Send Workflow

1. **Initiate** - Send command like `S N0CALL`
2. **Title prompt** - BBS prompts: `Title:`
3. **Enter subject** - Type subject line, press Enter
4. **Body prompt** - BBS prompts: `Enter message:`
5. **Type body** - Enter message text (multiple lines)
6. **Terminate** - End with Ctrl+Z or `/EX` on a new line

### Example Compose Session

```
S N0CALL
Title: Meeting tomorrow
Enter message:
Hi John,

Just wanted to confirm our meeting tomorrow at 2pm.

73,
Mike
/EX
Message saved as #1235
```

### Message Termination

Two ways to end a message:
- **Ctrl+Z** (ASCII 0x1A) - Send the control character
- **/EX** - Type `/EX` on a new line and press Enter

## Protocol Details

### BBS Server Identification

On entering BBS mode, server sends SID (System ID):

```
[LinBPQ-6.0.24.1-B2FHIM$]
```

Format: `[Software-Version-Capabilities]`

Capability flags:
- `B` - BBS mode
- `2` - B2 forwarding protocol
- `F` - FBB forwarding
- `H` - Hierarchical routing
- `I` - Immediate forwarding
- `M` - MBL/RLI forwarding
- `$` - WL2K (Winlink)

### Message ID (BID/MID)

Each message has a unique identifier:
- Format: `number_callsign`
- Example: `12345_W1ABC`

Used for:
- Duplicate detection during forwarding
- Message tracking across BBS network

### Routing Headers

Messages may contain routing information:

```
R:240101/1200Z @:W1BBS.#EPA.PA.USA.NOAM [LinBPQ-6.0.24]
R:240101/1130Z @:W2BBS.#WNY.NY.USA.NOAM [LinBPQ-6.0.24]
```

Format: `R:YYMMDD/HHmmZ @:BBS.hierarchical.address [Software]`

- Lowest line = message origin
- Topmost line = most recent relay

## Implementation Notes

### State Machine

The BBS client needs to track state:

```
DISCONNECTED
    │
    ▼ (connect + auth)
NODE_PROMPT
    │
    ▼ (send "BBS")
BBS_PROMPT ◄─────────────┐
    │                    │
    ├── (L commands) ────┤ (list response)
    │                    │
    ├── (R commands) ────┤ (message content)
    │                    │
    ├── (S command) ─────┼──► COMPOSING_TITLE
    │                    │         │
    │                    │         ▼ (enter title)
    │                    │    COMPOSING_BODY
    │                    │         │
    │                    │         ▼ (Ctrl+Z or /EX)
    │                    ◄─────────┘
    │
    ▼ (send "B" or "NODE")
NODE_PROMPT / DISCONNECTED
```

### Parsing Responses

**List response parsing:**
- Lines starting with digits are message entries
- Parse fixed-width fields or use regex
- Handle continuation if list spans multiple screens

**Message parsing:**
- Headers end with blank line
- Body follows headers
- Look for routing lines starting with `R:`

### Error Handling

Common error responses:
- `Invalid command` - Unknown command
- `Message not found` - Invalid message number
- `Not authorized` - Permission denied
- `No new messages` - Empty list result

## Go Implementation Plan

### Files to Create

- **`bbs.go`** - Main BBS client implementation
- **`bbs_websocket.go`** - WebSocket handler for BBS API

### BBSClient Struct

```go
type BBSClient struct {
    hostname     string
    port         int
    callsign     string
    password     string

    conn         net.Conn
    connected    bool
    inBBSMode    bool
    mu           sync.RWMutex

    messages     []BBSMessage  // Cached message list
    messagesMu   sync.RWMutex

    ctx          context.Context
    cancel       context.CancelFunc
}

type BBSMessage struct {
    Number    int       `json:"number"`
    Type      string    `json:"type"`      // P, B, T
    Status    string    `json:"status"`    // N, Y, F, K, H, D
    Date      string    `json:"date"`
    From      string    `json:"from"`
    Size      int       `json:"size"`
    To        string    `json:"to"`
    Subject   string    `json:"subject"`
    Body      string    `json:"body,omitempty"`
    Headers   []string  `json:"headers,omitempty"`
}
```

### WebSocket API

Endpoint: `/ws/bbs`

**Client Commands:**

```json
// List messages
{"cmd": "list", "type": "LM"}

// Read message
{"cmd": "read", "number": 1234}

// Send message
{"cmd": "send", "to": "N0CALL", "subject": "Hello", "body": "Message text"}

// Send bulletin
{"cmd": "bulletin", "category": "TECH", "subject": "New feature", "body": "..."}

// Delete message
{"cmd": "delete", "number": 1234}

// Get status
{"cmd": "status"}
```

**Server Messages:**

```json
// Message list
{"type": "bbs_list", "messages": [...]}

// Message content
{"type": "bbs_message", "message": {...}}

// Send confirmation
{"type": "bbs_sent", "number": 1235}

// Error
{"type": "bbs_error", "message": "Not found"}

// Status
{"type": "bbs_status", "connected": true, "inBBSMode": true}
```

## React Native UI Plan

### BBSScreen.js

Features:
- Message list with type/status indicators
- Pull-to-refresh for new messages
- Tap message to read full content
- Compose button for new messages
- Reply button on message view
- Delete with confirmation
- Filter by type (Personal/Bulletin/Traffic)

### Message List View

```
┌────────────────────────────────────┐
│ Mail                    [Compose]  │
├────────────────────────────────────┤
│ [All] [Personal] [Bulletins]       │
├────────────────────────────────────┤
│ PN  W1ABC      Jan 01              │
│     Hello World                    │
├────────────────────────────────────┤
│ BF  TECH@WW    Dec 31              │
│     New software release           │
├────────────────────────────────────┤
│ PN  N0XYZ      Dec 30              │
│     Re: Question about...          │
└────────────────────────────────────┘
```

### Message Detail View

```
┌────────────────────────────────────┐
│ ←  Message #1234         [Delete]  │
├────────────────────────────────────┤
│ From: W1ABC                        │
│ To: N0CALL                         │
│ Date: Jan 01, 2024 12:00 UTC       │
│ Subject: Hello World               │
├────────────────────────────────────┤
│                                    │
│ Hi there,                          │
│                                    │
│ This is the message body.          │
│                                    │
│ 73, W1ABC                          │
│                                    │
├────────────────────────────────────┤
│          [Reply]                   │
└────────────────────────────────────┘
```

### Compose View

```
┌────────────────────────────────────┐
│ ←  New Message            [Send]   │
├────────────────────────────────────┤
│ To: [N0CALL              ] [P/B]   │
├────────────────────────────────────┤
│ Subject: [                      ]  │
├────────────────────────────────────┤
│                                    │
│ [Message body input area...]       │
│                                    │
│                                    │
│                                    │
└────────────────────────────────────┘
```

## References

- [BPQ Mail Server User Commands](https://www.cantab.net/users/john.wiseman/Documents/BBSUserCommands.html)
- [BPQ Mail Server Configuration](https://www.cantab.net/users/john.wiseman/Documents/MailServerConfiguration.html)
- [LinBPQ MailCommands.c](https://github.com/g8bpq/linbpq/blob/master/MailCommands.c)
- [LinBPQ BBSUtilities.c](https://github.com/g8bpq/linbpq/blob/master/BBSUtilities.c)
- [FBB Protocol](https://www.f6fbb.org/protocole.html)
- [Winlink B2F Protocol](https://winlink.org/B2F)
