# TARPN Enhanced Deployment

This directory contains the deployment scripts for TARPN Enhanced (tarpn-mon + tarpn-chat).

## Quick Install

Run this command on your TARPN node:

```bash
curl -sSL https://tarpn-terminal.s3.us-east-1.amazonaws.com/latest/scripts/install.sh | sudo bash
```

Or with options:

```bash
curl -sSL https://tarpn-terminal.s3.us-east-1.amazonaws.com/latest/scripts/install.sh | sudo bash -s -- --call N0CALL-9
```

## What Gets Installed

### tarpn-mon
Enhanced monitoring backend with web interface.

- **Binary**: `/opt/tarpn-mon/tarpn-mon`
- **Config**: `/opt/tarpn-mon/tarpn-mon.env`
- **Logs**: `/var/log/tarpn-mon.log`
- **Service**: `tarpn-mon.service`
- **Web UI**: `http://<your-pi-ip>:8212`

### tarpn-chat
LinBPQ-compatible chat server with improvements.

- **Binary**: `/opt/tarpn-chat/tarpn-chat`
- **Config**: `/opt/tarpn-chat/config.toml`
- **Logs**: `/var/log/tarpn-chat.log`
- **Service**: `tarpn-chat.service`

## Installation Options

```
--call CALL       Node callsign for chat (e.g., N0CALL-9)
--alias ALIAS     Node alias for chat (default: derived from callsign)
--skip-mon        Skip tarpn-mon installation
--skip-chat       Skip tarpn-chat installation
--skip-bpq-patch  Don't modify bpq32.cfg
--force           Force reinstall even if up to date
--uninstall       Remove installed components
--dry-run         Show what would be done without doing it
--help            Show help message
```

## Updating

The installer is idempotent - just run it again to update:

```bash
curl -sSL https://tarpn-terminal.s3.us-east-1.amazonaws.com/latest/scripts/install.sh | sudo bash
```

The script will:
- Check for newer versions
- Skip if already up to date
- Preserve existing configuration
- Update only the binary

## Uninstalling

```bash
curl -sSL https://tarpn-terminal.s3.us-east-1.amazonaws.com/latest/scripts/install.sh | sudo bash -s -- --uninstall
```

Or manually:

```bash
sudo systemctl stop tarpn-mon tarpn-chat
sudo systemctl disable tarpn-mon tarpn-chat
sudo rm -rf /opt/tarpn-mon /opt/tarpn-chat
sudo rm /etc/systemd/system/tarpn-mon.service
sudo rm /etc/systemd/system/tarpn-chat*.service /etc/systemd/system/tarpn-chat*.path
sudo systemctl daemon-reload
```

## How It Works

### Architecture
```
┌─────────────────────────────────────────────────────────────┐
│  LinBPQ (existing TARPN installation)                       │
│  - CMDPORT connects to tarpn-chat on port 63005             │
│  - Monitor port (8011) provides packet stream               │
└─────────────────────┬───────────────────────────────────────┘
                      │
          ┌───────────┴───────────┐
          │                       │
          ▼                       ▼
┌─────────────────────┐  ┌─────────────────────┐
│  tarpn-chat         │  │  tarpn-mon          │
│  - Chat server      │◄─┤  - Web interface    │
│  - Listener mode    │  │  - Packet monitor   │
│  - Port 63005       │  │  - Chat client      │
│  - Client API 8513  │  │  - Port 8212        │
└─────────────────────┘  └─────────────────────┘
                                  │
                                  ▼
                         ┌─────────────────────┐
                         │  Web Browser        │
                         │  or Mobile App      │
                         └─────────────────────┘
```

### bpq32.cfg Modifications

The installer automatically patches your bpq32.cfg to:

1. Add port 63005 to CMDPORT line (as HOST 5)
2. Replace built-in CHAT application with CMDPORT-based version
3. Remove TARPN-HOME APPLICATION lines (HOME4, HOME5, HOME6)

Changes are marked with `;;; TARPN-CHAT PATCHED` comment.

A systemd path watcher (`tarpn-chat-config.path`) automatically re-patches the config if TARPN regenerates it.

## Manual Configuration

### tarpn-mon

Edit `/opt/tarpn-mon/tarpn-mon.env`:

```bash
TARPN_MON_CALL=N0CALL
TARPN_MON_PORT=8212
```

### tarpn-chat

Edit `/opt/tarpn-chat/config.toml`:

```toml
[node]
call = "N0CALL-9"
alias = "N0CHAT"

[listener]
port = 63005
bind = "127.0.0.1"

[client]
port = 8513
bind = "127.0.0.1"
```

## Troubleshooting

### Check service status
```bash
sudo systemctl status tarpn-mon
sudo systemctl status tarpn-chat
```

### View logs
```bash
tail -f /var/log/tarpn-mon.log
tail -f /var/log/tarpn-chat.log
tail -f /var/log/tarpn-chat-patch.log
```

### Restart services
```bash
sudo systemctl restart tarpn-mon
sudo systemctl restart tarpn-chat
```

### Restart LinBPQ to pick up config changes
```bash
tarpn stop && tarpn test
```

## Files

```
deploy/
├── install.sh              # Main installer script
├── README.md               # This file
├── config/
│   ├── tarpn-chat.toml.example
│   └── tarpn-mon.env.example
└── scripts/
    └── patch-bpq32-config.sh
```

## Requirements

- Standard TARPN installation with LinBPQ
- Raspberry Pi (ARM32/ARM64) or x86_64 Linux
- Internet connection (for downloading binaries)
- sudo/root access

## Release channel layout

`build-release.sh` publishes one directory per version plus a `latest/`
mirror, and `../tarpn-node/` installs from `RELEASE_BASE_URL` / `RELEASE_VERSION`
in `/etc/tarpn/tarpn.conf` (defaulting to this bucket and `latest`).

```
s3://tarpn-terminal/<version>/
  tarpn-mon.linux-<arch>
  tarpn-chat.linux-<arch>          canonical
  tarpn-chat-<arch>                legacy alias, see below
  send-routes-via-cq.linux-<arch>
  linktest.linux-<arch>
  manifest.json
  scripts/
s3://tarpn-terminal/latest/        synced from the newest version
```

Every component follows `<name>.linux-<arch>`. `tarpn-chat` was originally
published as `tarpn-chat-<arch>`; releases now upload **both** names so the
older `install.sh` in this directory keeps working, and the tarpn-node
installer falls back to the legacy name when the canonical one is absent.
Drop the alias once nothing installs with the old script.

### Publishing a new architecture

Adding an architecture that has never been published is safe to send straight
to `latest/`: the sync no longer uses `--delete`, so it adds the new binaries
alongside the existing ones rather than replacing them. Nodes on other
architectures keep resolving exactly what they resolved before, and nodes on
the new one start working with no configuration at all.

The one thing it does overwrite is `latest/manifest.json`, which describes
whichever architecture was published last. The tarpn-node installer builds
URLs directly and never reads it, but the older `install.sh` in this directory
reads its `version` field to decide whether to update - so publishing a build
whose version string differs will make those nodes re-download a binary that
has not actually changed. Harmless, but it is why the manifest is worth
replacing with per-architecture ones eventually.

### Prerelease and branch builds

`--no-latest` uploads the version directory but leaves `latest/` alone, for a
build that should be installable by name without becoming the default:

```bash
./build-release.sh --arch arm64 --no-latest
```

On the node under test, point at that version in `/etc/tarpn/tarpn.conf`:

```
RELEASE_VERSION=v0.1.1-4-g515e7b3
```

then `sudo tarpnctl update`. Nodes on the default `latest` are unaffected.

### Publishing all architectures

`--arch` builds one architecture at a time, and the per-version directory
accumulates, so publishing all three means running it three times before the
`latest/` sync reflects the full set:

```bash
./build-release.sh --arch arm32
./build-release.sh --arch arm64
./build-release.sh --arch amd64
```

Note that `manifest.json` is rewritten per architecture and therefore
describes only the last one built. The tarpn-node installer constructs URLs
directly and does not read it.
