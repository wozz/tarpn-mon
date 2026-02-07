# TARPN Terminal

Monitoring and chat application for [TARPN](http://tarpn.net) (Terrestrial Amateur Radio Packet Network) nodes running LinBPQ.

Replaces the original tarpn-mon Vue.js app with a universal React Native frontend, a Go backend, and a standalone Rust chat server that connects via NetROM.

## Components

| Component | Language | Description |
|-----------|----------|-------------|
| **tarpn-mon** | Go | Backend server. Connects to LinBPQ's monitor and telnet ports, parses AX.25 frames and TNC stats, proxies Chat/BBS/Node connections, serves the embedded web frontend. Default port 8212. |
| **tarpn-terminal** | React Native (Expo) | Universal frontend (Web, Android, iOS). Monitor screen, stats/charts, chat, BBS, node access, settings. |
| **tarpn-chat** | Rust | Standalone NetROM chat server. Connects to LinBPQ via NetROM for peer-to-peer chat routing between nodes. |
| **send-routes-via-cq** | Go | TARPNstat link quality broadcaster. Reads the routes table and sends bilateral link stats via CQ on each active port. Runs on a 15-minute systemd timer. |

## Architecture

```
LinBPQ (packet node software)
  ├── Telnet :8010 ──── tarpn-mon (Go) ──── WebSocket ──── tarpn-terminal (React Native)
  ├── Monitor :8011 ──┘      :8212                           Web / Android / iOS
  ├── HTTP :8080
  └── NetROM :63119 ── tarpn-chat (Rust)
                            :8513 ──── WebSocket ──── tarpn-terminal
```

## Install

On a Raspberry Pi running a standard TARPN installation:

```bash
curl -sSL https://tarpn-terminal.s3.us-east-1.amazonaws.com/latest/scripts/install.sh | sudo bash
```

With options:

```bash
# Specify chat callsign
curl -sSL https://tarpn-terminal.s3.us-east-1.amazonaws.com/latest/scripts/install.sh | sudo bash -s -- --call N0CALL-9

# Install only the monitor (no chat server)
curl -sSL https://tarpn-terminal.s3.us-east-1.amazonaws.com/latest/scripts/install.sh | sudo bash -s -- --skip-chat

# Preview what would be installed without making changes
curl -sSL https://tarpn-terminal.s3.us-east-1.amazonaws.com/latest/scripts/install.sh | sudo bash -s -- --dry-run

# Force reinstall even if already up to date
curl -sSL https://tarpn-terminal.s3.us-east-1.amazonaws.com/latest/scripts/install.sh | sudo bash -s -- --force
```

The installer is idempotent -- run it again to update to the latest version. Existing configuration is preserved.

Supports ARM32 (Raspberry Pi OS 32-bit), ARM64 (64-bit), and x86_64.

### What the installer does

- Downloads binaries to `/opt/tarpn-mon` and `/opt/tarpn-chat`
- Creates systemd services for automatic startup and restart
- Auto-detects your callsign from `bpq32.cfg`
- Patches `bpq32.cfg` to add the NetROM port for tarpn-chat
- Optionally upgrades LinBPQ to a version supporting NETROMPORT
- Replaces the legacy `sendroutestocq` binary with the Go rewrite

### Uninstall

```bash
curl -sSL https://tarpn-terminal.s3.us-east-1.amazonaws.com/latest/scripts/install.sh | sudo bash -s -- --uninstall
```

## Post-install

Access the web interface at `http://<node-ip>:8212`.

Configuration files:
- `/opt/tarpn-mon/tarpn-mon.env` -- monitor settings (callsign, ports)
- `/opt/tarpn-chat/config.toml` -- chat server settings (callsign, alias, peers)

Service management:
```bash
sudo systemctl status tarpn-mon
sudo systemctl status tarpn-chat
sudo systemctl restart tarpn-mon
journalctl -u tarpn-mon -f      # follow logs
journalctl -u tarpn-chat -f
```

## Development

### Go backend

```bash
go run *.go -call N0CALL
```

### React Native frontend

```bash
cd tarpn-terminal && npm install && npx expo start --web
```

### tarpn-chat (Rust)

```bash
source ~/.cargo/env
cd tarpn-chat && cargo build
RUST_LOG=debug cargo run -- --config config.toml
```

### Build for release

```bash
# Build all components and upload to S3
deploy/build-release.sh --version v1.3.5

# Build without uploading
deploy/build-release.sh --version v1.3.5 --dry-run

# Build only the monitor (skip chat)
deploy/build-release.sh --version v1.3.5 --skip-chat
```

### Version management

```bash
# Bump version in all files, commit, and tag
deploy/scripts/bump-version.sh v1.3.5
```

This updates `tarpn-terminal/package.json` and `tarpn-chat/Cargo.toml`, commits the changes, and creates a git tag. The Go binaries (tarpn-mon, send-routes-via-cq) get their version from the git tag at build time via linker flags.
