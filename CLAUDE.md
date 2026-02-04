# TARPN Terminal Project Overview

This document provides context for Claude sessions working on this codebase.

## What is TARPN?

**TARPN** (Terrestrial Amateur Radio Packet Network) is a network of amateur radio packet nodes, typically running on Raspberry Pi computers. Each node runs **LinBPQ** (a packet node software) connected to radio TNCs (Terminal Node Controllers) that communicate via VHF/UHF radio links.

Key characteristics:
- **Point-to-point RF links**: Each radio port connects to exactly one neighbor
- **NetROM Layer 3 routing**: Nodes discover and route to each other
- **Amateur Radio**: All traffic is unencrypted, callsigns are required
- **No Internet**: TARPN philosophy is terrestrial radio only (though LinBPQ supports TCP tunneling)

## Repository

- **GitHub (origin)**: https://github.com/wozz/tarpn-mon.git
- **Gitea (gitea)**: git@git.ghost.fish:wozz/tarpn-mon.git
- **Branches**: `main` (stable), `react-native` (active development)

## This Repository: tarpn-terminal

This is a **replacement monitoring application** for TARPN nodes. The original `tarpn-mon` was a Vue.js web app; we've rebuilt it as a universal React Native (Expo) application.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  LinBPQ (packet node software)                              │
│  - Telnet port 8010 (node/chat/BBS - same port, different   │
│    application commands after connect)                      │
│  - Telnet port 8011 (monitor stream for packet logging)     │
│  - HTTP port 8080 (web admin interface)                     │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│  Go Backend (main.go)                                       │
│  - Connects to LinBPQ monitor port                          │
│  - Parses AX.25 frames and TNC status                       │
│  - Parses TARPNstat bilateral link quality messages         │
│  - Collects L2 link statistics                              │
│  - WebSocket API for frontend                               │
│  - Proxies Chat/BBS/Node connections via telnet to LinBPQ   │
│  - Persists chat messages and link stats                    │
│  - Serves embedded web app                                  │
│  - Default port: 8212                                       │
└─────────────────────┬───────────────────────────────────────┘
                      │ WebSocket
                      ▼
┌─────────────────────────────────────────────────────────────┐
│  React Native Frontend (tarpn-terminal/)                    │
│  - Universal: Web, Android, iOS                             │
│  - Monitor screen: AX.25 packet display                     │
│  - Stats screen: TNC stats, link quality charts             │
│  - Chat/BBS/Node screens: Feature connections               │
│  - Settings screen: Connection and display config           │
│  - Built with Expo                                          │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  tarpn-chat (Rust)                                          │
│  - Standalone NetROM chat server                            │
│  - Connects to LinBPQ via NetROM (not telnet)               │
│  - Peer-to-peer chat routing between nodes                  │
│  - WebSocket API for frontend integration                   │
└─────────────────────────────────────────────────────────────┘
```

### Key Files

**Go Backend:**
- `main.go` - Main server entry point
- `websocket.go` - WebSocket handler
- `telnet.go` - Telnet connection to LinBPQ
- `tarpn_stat.go` - Parses `[TARPNstat V2]~CALL~>~tx~ret~buf~` messages
- `tnc_parser.go` - Parses TNC status information
- `chat.go`, `bbs.go`, `node.go` - Feature connection handlers (telnet to LinBPQ)
- `chat_websocket.go`, `bbs_websocket.go`, `node_websocket.go` - Feature WebSocket handlers
- `link_stats.go`, `link_stats_parser.go`, `link_stats_storage.go` - L2 link statistics
- `stats_encoding.go` - Statistics encoding/decoding
- `chat_storage.go` - Chat message persistence
- `feature_status.go` - Feature status tracking
- `settings.go` - Settings management
- `buffer.go` - Circular buffer for message history
- `logger.go`, `colors.go`, `metrics.go` - Utilities

**React Native Frontend:**
- `tarpn-terminal/src/screens/` - MonitorScreen, StatsScreen, ChatScreen, BBSScreen, NodeScreen, SettingsScreen
- `tarpn-terminal/src/context/AppContext.js` - Global state, WebSocket connection
- `tarpn-terminal/src/utils/ax25Utils.js` - AX.25 frame parsing

**tarpn-chat (Rust):**
- `tarpn-chat/src/server.rs` - Chat server implementation
- `tarpn-chat/src/netrom.rs` - NetROM protocol
- `tarpn-chat/src/protocol.rs` - Chat protocol
- `tarpn-chat/src/routing.rs` - Routing logic
- `tarpn-chat/src/session.rs` - Session management
- `tarpn-chat/src/transport.rs` - Transport layer
- `tarpn-chat/docker-testnet/` - Podman-based test network

**Deployment:**
- `deploy/build-release.sh` - Release build script
- `deploy/install.sh` - Installation script
- `deploy/config/` - Configuration files
- `deploy/scripts/` - Deployment scripts
- `deploy/systemd/` - Systemd unit files

---

## LinBPQ

LinBPQ is the packet node software that TARPN nodes run. Key concepts:

### What LinBPQ Does
- **AX.25 Layer 2**: Frame construction, sequencing, acknowledgments, retries
- **NetROM Layer 3/4**: Routing, node discovery, transport
- **KISS TNC interface**: Communicates with radio modems
- **Applications**: Chat server, BBS, telnet access

### Key Parameters (bpq32.cfg)
| Parameter | Purpose |
|-----------|---------|
| FRACK | Frame ACK timeout (T1 timer) in ms |
| RETRIES | Max retransmissions before disconnect (N2) |
| MAXFRAME | Outstanding frames before ACK required (1-7) |
| PACLEN | Maximum packet data length |
| RESPTIME | Delayed ACK timer (T2) in ms |

### TARPN's Architecture
- **One neighbor per port**: Simplifies tuning (port settings = neighbor settings)
- **Dedicated RF links**: No CSMA contention, can use PERSIST=255
- **TARPNstat**: Bilateral link quality monitoring via CQ broadcasts

See: [linbpq-analysis/README.md](linbpq-analysis/README.md) for deep dive.

---

## TARPN Install Scripts Analysis

We've analyzed the TARPN install/update scripts to understand:
- How the system is deployed
- What blocks Bookworm and 64-bit OS support
- What could be simplified with native systemd

### Key Findings

**32-bit Binary Blockers:**
1. `pilinbpq.dms` - LinBPQ binary (can be recompiled from GitHub source)
2. `rx_tarpnstatapp` - Stats broadcaster (source available on request)

**Script Issues:**
- Wrapper scripts could be replaced with systemd (70% reduction)
- Explicit 32-bit and Bullseye version checks
- Boot paths need updating for Bookworm

See:
- [tarpn-scripts-analysis/docs/BOOKWORM_64BIT_ANALYSIS.md](tarpn-scripts-analysis/docs/BOOKWORM_64BIT_ANALYSIS.md)
- [tarpn-scripts-analysis/docs/SYSTEMD_ANALYSIS.md](tarpn-scripts-analysis/docs/SYSTEMD_ANALYSIS.md)
- [tarpn-scripts-analysis/docs/ISSUES.md](tarpn-scripts-analysis/docs/ISSUES.md)

---

## TARPNstat Protocol

Each node broadcasts its local link statistics, enabling bilateral monitoring:

```
Node A broadcasts: [TARPNstat V2]~A-1~>~tx500~ret10~buf2~
Node B broadcasts: [TARPNstat V2]~B-2~>~tx480~ret5~buf1~

Both nodes see both broadcasts via monitor port.
Result: Each node knows both sides' perspective on link health.
```

The Go backend parses these and sends `tarpn_stat` messages to the frontend.

---

## Development Commands

### Environment Setup

**Rust**: Cargo is installed via rustup in `~/.cargo/bin`. Source the environment before using Rust tools:

```bash
# Source cargo environment (required for rust/cargo commands)
source ~/.cargo/env

# Or use full path
~/.cargo/bin/cargo build
```

### Go Backend

```bash
# Run Go backend
go run *.go -call N0CALL
```

### React Native Frontend

```bash
# Run React Native (web)
cd tarpn-terminal && npx expo start --web

# Run React Native (Android)
cd tarpn-terminal && npx expo start --android

# Build web for embedding
cd tarpn-terminal && npx expo export -p web
```

### tarpn-chat (Rust)

```bash
# Build tarpn-chat
source ~/.cargo/env
cd tarpn-chat && cargo build

# Run with debug logging
RUST_LOG=debug cargo run -- --config config.toml
```

### Docker Testnet (uses Podman)

The docker testnet in `tarpn-chat/docker-testnet/` uses **podman-compose**, not docker-compose:

```bash
# Start the testnet
cd tarpn-chat/docker-testnet && podman-compose up -d

# View logs
podman-compose logs -f node4

# Stop the testnet
podman-compose down

# Rebuild after code changes
source ~/.cargo/env
cd tarpn-chat && cargo build --release --target x86_64-unknown-linux-musl
cp target/x86_64-unknown-linux-musl/release/tarpn-chat dist/tarpn-chat-x86_64-musl
cd docker-testnet && podman-compose up -d --force-recreate node4 node5
```

---

## Key Design Decisions

1. **tarpn-terminal is independent of LinBPQ lifecycle** - We handle reconnection ourselves; don't kill the app when LinBPQ restarts (preserves buffer history)

2. **Client-initiated feature connections** - Chat/BBS/Node connections are initiated by frontend request, not auto-connected

3. **NetROM-only chat** - tarpn-chat connects via NetROM only (legacy telnet/listener/RHP modes removed as of v1.3.4+)

4. **WebSocket-only frontend** - Chat frontend uses WebSocket connections only (telnet/app modes removed as of v1.3.1)

5. **Connection settings on backend** - Connection configuration (host, ports) managed server-side since v1.3.0

6. **RETRIES coordination** - When tuning, remember the **lower** retry count between neighbors dominates. Both sides need high RETRIES for resilient links.

7. **INP3 protocol** - Useful for mesh networks with multiple paths; not beneficial for linear/tree topologies

---

## Related Documentation

| Document | Purpose |
|----------|---------|
| [linbpq-analysis/README.md](linbpq-analysis/README.md) | Deep dive on LinBPQ: AX.25 params, layer responsibilities, INP3, TARPNstat |
| [tarpn-scripts-analysis/docs/BOOKWORM_64BIT_ANALYSIS.md](tarpn-scripts-analysis/docs/BOOKWORM_64BIT_ANALYSIS.md) | Blockers for OS upgrades |
| [tarpn-scripts-analysis/docs/SYSTEMD_ANALYSIS.md](tarpn-scripts-analysis/docs/SYSTEMD_ANALYSIS.md) | How to replace wrapper scripts with systemd |
| [tarpn-scripts-analysis/docs/ISSUES.md](tarpn-scripts-analysis/docs/ISSUES.md) | 100+ issues catalogued in install scripts |
| [tarpn-terminal/README.md](tarpn-terminal/README.md) | How to run the React Native app |
| [tarpn-chat/docs/](tarpn-chat/docs/) | tarpn-chat Rust server documentation |
| [deploy/](deploy/) | Deployment scripts, systemd units, installer |
