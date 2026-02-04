# $TH Presence/Status Protocol

## Overview

The `$TH` protocol is a presence and status signaling mechanism used by **TARPN Home** (the web UI for TARPN nodes). It allows chat users running TARPN Home to advertise their current activity status to other users on the chat network.

$TH messages are sent as regular chat text — they travel over the BPQ chat network and are visible to all connected chat participants. They are **not** a separate transport; they piggyback on the existing LinBPQ chat infrastructure.

### Key Characteristics

- **Broadcast via chat**: $TH messages are ordinary chat messages sent to the chat room. Every connected node sees them.
- **Receive-side interpretation**: Recipients parse $TH messages locally to update their user status display. There is no acknowledgment or request/response — it's fire-and-forget.
- **Not used for leave detection**: $TH messages do not signal that a user has left. Leave detection uses the standard BPQ chat `*** Left` messages instead (see [User Tracking](#user-tracking) below).
- **Status updates only**: $TH is purely for activity/presence status (idle, active, away, etc.).

## Message Format

```
V<version> > $TH:<status><timestamp>
```

### Fields

| Field | Description | Example |
|-------|-------------|---------|
| `V<version>` | TARPN Home version string | `V2.3.3` |
| ` > $TH:` | Literal delimiter (space-gt-space-dollar-TH-colon) | ` > $TH:` |
| `<status>` | 3-character status code | `IDL` |
| `<timestamp>` | Time the status last changed, format `%m-%d-%Y %H:%M` | `01-25-2025 16:04` |

### Example Messages

```
V2.3.3 > $TH:IDL01-25-2025 16:04
V2.3.3 > $TH:ACT01-25-2025 16:10
V2.3.3 > $TH:AFK01-25-2025 16:15
```

### Parsing

Given a chat message, find the substring ` > $TH:`. Let `pos` be the index of that substring.

```
status    = message[pos+7 : pos+10]     # 3-character status code
timestamp = message[pos+10:]            # remaining text, strip \r\n
```

The timestamp format is `%m-%d-%Y %H:%M` (month-day-year hour:minute, local time of the sender).

## Status Codes

| Code | Meaning | Trigger |
|------|---------|---------|
| `IDL` | Idle | Default state on startup. Also set when `ACT` status ages beyond 9 minutes without new activity. |
| `ACT` | Active | Set when the local user types/sends a chat message. |
| `AFK` | Away from keyboard | Set when the user (or another user with the same callsign) sends a message containing ` : away\r\n` or ` : afk\r\n`. |
| `BBS` | In BBS | Set when the user enters BBS mode via the TARPN Home UI (`bbs_enter` command). Cleared on `bbs_exit`. |
| `LFT` | Left | Set **locally** when a `*** Left` message is received for a tracked user. Not sent as a $TH broadcast — this is a receive-side status. |
| `OUT` | Timed out | Set **locally** when a user with `LFT` status has been gone for more than 15 minutes. Not sent as a $TH broadcast — this is a receive-side status. |

### Status Transition Diagram

```
                    ┌─────────────────────────────┐
                    │                             │
                    ▼                             │
    ┌───────┐  user types  ┌───────┐  9 min idle │
    │  IDL  │─────────────>│  ACT  │─────────────┘
    └───────┘              └───────┘
        ▲                      │
        │                      │ ": away" or ": afk"
        │ bbs_exit             ▼
    ┌───────┐              ┌───────┐
    │  BBS  │              │  AFK  │
    └───────┘              └───────┘
        ▲
        │ bbs_enter
        │
    (from any status)

    --- Receive-side only (not broadcast via $TH) ---

    ┌───────┐  15 min  ┌───────┐
    │  LFT  │─────────>│  OUT  │
    └───────┘          └───────┘
        ▲
        │ "*** Left" message
        │
    (from any status)
```

## Timers and Keepalives

TARPN Home runs two periodic timers related to chat presence:

### Chat Keepalive (every 1200 seconds / 20 minutes)

Sends a keepalive message to BPQ chat to maintain the connection:

```
/S <callsign> Keepalive!!
```

This is a standard `/S` (send) command to BPQ chat. It keeps the chat connection alive but does **not** carry $TH status information. The timestamp embedded in this keepalive is derived from `datLastChatTyped` (when the user last typed), not the current time.

### $TH Status Broadcast (every 5400 seconds / 90 minutes)

Sends the current $TH status message to the chat network:

```
V2.3.3 > $TH:IDL01-25-2025 16:04
```

This is the periodic re-broadcast of the user's current status. The timestamp reflects when the current status was last set (from `datLastChatTyped`), not the current wall clock time.

### Idle Check (every ~120 seconds)

A periodic scan of the local chatter list that applies time-based status transitions:

| Current Status | Time Since Last Update | Action |
|---------------|----------------------|--------|
| `ACT` | > 9 minutes | Transition to `IDL` |
| `LFT` | > 15 minutes | Transition to `OUT` |
| Other (not `ACT`, not `LFT`) | > 4 minutes | Periodic UI refresh (see below) |

For non-ACT, non-LFT statuses that have been unchanged for more than 4 minutes, TARPN Home sends periodic `sendChatStatusToScreens` updates to refresh the local web UI at decreasing frequency:

| Time Since Update | Refresh Interval |
|-------------------|-----------------|
| 5–15 minutes | Every 5 minutes |
| 16–60 minutes | Every 10 minutes |
| 1–24 hours | Every 60 minutes |
| > 24 hours | Every 24 hours (1440 minutes) |

These UI refreshes are purely local — they don't send anything to the chat network.

## User Tracking

TARPN Home maintains a local list of chat users (`lstChatter`), where each entry is a JSON object:

```json
{
    "Name": "Bob",
    "Call": "WA2M",
    "Color": "#FF0000",
    "Status": "ACT",
    "Time": "01-25-2025 16:10",
    "TimeLeft": "01-25-2025 16:10"
}
```

### Fields

| Field | Description |
|-------|-------------|
| `Name` | Display name (from chat join message or BPQ chat user list) |
| `Call` | Amateur radio callsign (no SSID) |
| `Color` | Hex color assigned for display |
| `Status` | Current status code (IDL, ACT, AFK, BBS, LFT, OUT) |
| `Time` | Timestamp of the last status change (`%m-%d-%Y %H:%M`) |
| `TimeLeft` | Timestamp of when the user left (set on `*** Left`); same as `Time` for active users |

### How Users Are Added

Users are added to `lstChatter` when a `*** Joined Chat,` message is received. The join message is parsed for callsign and name. New users start with status `IDL` and empty time fields.

### How Users Are Tracked

1. **Chat messages**: When a message from a known callsign is received (and it's not a `*** Left` or `*** Joined` message), the user's status is set to `ACT` with the current time.

2. **$TH messages**: When a $TH message is received from a known callsign, the user's status and time are updated to match the received values. Both `Time` and `TimeLeft` are set to the received timestamp.

3. **`*** Left` messages**: When received, the user's status is set to `LFT`, and `TimeLeft` is set to the current local time. The original `Time` field is preserved (it retains the timestamp of their last status before leaving).

4. **Idle timeout**: The periodic idle check transitions `ACT` users to `IDL` after 9 minutes and `LFT` users to `OUT` after 15 minutes.

### Callsign Parsing

TARPN Home uses this regex to extract callsigns from chat messages:

```regex
([AWKN][A-Z]?[0-9][A-Z]{1,3})( {1,4})(.{0,15})(:|> )
```

This matches US amateur callsigns starting with A, W, K, or N, followed by optional second letter, digit, and 1-3 suffix letters. The regex captures the callsign, spacing, name (up to 15 chars), and the separator (`:` or `> `).

### Sort Order

The chatter list is sorted by time in reverse order (most recently active first), using the `Time` field as the sort key.

## Interaction with BPQ Chat

TARPN Home connects to LinBPQ's chat server via a serial/telnet connection through SWITCH. The connection lifecycle:

1. Connect to SWITCH → `*** CONNECTED to SWITCH`
2. Join chat → `*** Joined Chat,` messages for existing users
3. Request user list → `Station(s) connected:\r\n` response
4. Normal chat operation with keepalives
5. Periodic $TH broadcasts

### Message Flow

```
TARPN Home ──── Serial/Telnet ────> LinBPQ Chat Server ──── RF/Network ────> Other Nodes
     │                                     │
     │  /S WA2M Keepalive!!               │  (keepalive, every 20 min)
     │  V2.3.3 > $TH:ACT01-25-2025 16:10 │  ($TH broadcast, every 90 min)
     │  Hello everyone!                    │  (normal chat message)
     │                                     │
     │  <── WA2M : Hello everyone!         │  (incoming chat)
     │  <── V2.3.3 > $TH:IDL01-25...      │  (incoming $TH from other node)
     │  <── WA2M : *** Left                │  (user left notification)
     │  <── WA2M : *** Joined Chat,...     │  (user joined notification)
```

### $TH Message Consumption

When TARPN Home receives a $TH message, it:
1. Parses the status code and timestamp
2. Updates the matching entry in `lstChatter`
3. Sends a `chat_status` update to connected web browser screens
4. **Consumes the message** — it is not forwarded to the web UI as visible chat text (the message string is set to empty)

This means $TH messages are invisible to end users — they only affect the status display.

## Data Prefix Protocol (WebSocket to Browser)

TARPN Home communicates with its local web browser clients via WebSocket using a prefix-based protocol:

| Prefix | Hex | Purpose |
|--------|-----|---------|
| NODE_PREFIX | `\x10` | Node/terminal data |
| CHAT_PREFIX | `\x11` | Chat messages |
| HIDDEN_PREFIX | `\x12` | Hidden channel (BBS commands) |
| DATA_PREFIX | `\x13` | Structured data (status, settings, etc.) |

Chat status updates are sent as:
```
\x13chat_status<index>:<json>
```

Where `<index>` is the position in the chatter list and `<json>` is the user's JSON object.

The full chatter list is sent via `sendChatListToScreens` when the sort order changes.

## Implementation Notes

- **Source**: Reverse-engineered from `tarpn_home.pyc` (Python 3.9 bytecode, version 2.3.3) using `pycdas` disassembler
- **Config file**: `/usr/local/etc/tarpn_home.ini`
- **Chat log**: `/usr/local/etc/tarpn_home_chat.log`
- **Raw chat log**: `/var/log/tarpn_home_chat_raw.log`
- **Web UI port**: 8085 (Tornado WebSocket server)
- **Dev mode**: Enabled when running as user `pi` (for debug logging)
