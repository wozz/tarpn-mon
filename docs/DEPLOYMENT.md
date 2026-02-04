# Deployment Guide

This guide covers deploying tarpn-terminal for testing and production use.

---

## Parallel Deployment (Testing)

If you're already running an older version of tarpn-mon, you can run the new tarpn-terminal in parallel on a different port for testing.

### Prerequisites

- Go 1.22+ (for building from source)
- Existing LinBPQ/TARPN node installation
- Access to the BPQ telnet ports (typically 8010, 8011)

### Building the Binary

Build for your target architecture:

```bash
# For Raspberry Pi 3/4 (32-bit OS)
GOOS=linux GOARCH=arm GOARM=7 go build -o tarpn-terminal-arm

# For Raspberry Pi 3/4 (64-bit OS)
GOOS=linux GOARCH=arm64 go build -o tarpn-terminal-arm64

# For standard Linux x86_64
GOOS=linux GOARCH=amd64 go build -o tarpn-terminal-amd64
```

### Running in Parallel

The default HTTP port is 8212. To run alongside an existing tarpn-mon instance, you have options:

**Option 1: Same port, stop old version first**
```bash
# Stop existing tarpn-mon
systemctl stop tarpn-mon  # or kill the process

# Start new version
./tarpn-terminal-arm -call YOURCALL -host localhost
```

**Option 2: Different port (requires frontend configuration)**
You can modify the Go source (`main.go:461`) to use a different port, or add a `-http-port` flag.

### Configuration

Basic monitor-only mode:
```bash
./tarpn-terminal -call N0CALL -host localhost -target-port 8011
```

Full feature mode (CLI auto-connect):
```bash
./tarpn-terminal \
  -call N0CALL \
  -host localhost \
  -chat -chat-port 8010 \
  -bbs -bbs-port 8010 \
  -node -node-port 8010
```

### Feature-Specific Notes

**Monitor** - Works immediately, connects to BPQ monitor port (default 8011)

**Node Console** - Works with your regular callsign, connects to BPQ telnet port (default 8010)

**BBS** - Works with your regular callsign, connects to BPQ telnet port (default 8010)

**Chat** - BPQ chat requires a unique callsign on the network. For testing, you can:
- Use a different SSID: `N0CALL-7` instead of `N0CALL`
- Use a test callsign if available

### Client-Initiated Connections

With the new dynamic connection feature, you don't need to specify `-chat`, `-bbs`, `-node` flags. Instead:

1. Start the server in monitor-only mode: `./tarpn-terminal -call N0CALL`
2. Open the web UI
3. Navigate to Settings tab
4. Click "Connect" on Chat, BBS, or Node cards
5. Enter connection details (host, port, callsign, password)

This allows connecting/disconnecting features without restarting the server.

---

## Mobile App Deployment

### Web (Expo Web)

The React Native app runs as a web app for development and testing:

```bash
cd tarpn-terminal
npm install
npm run web
```

Access at http://localhost:8081 (or the port Expo assigns).

### iOS Native Build

For a native iOS app, you'll need to set up Expo Application Services (EAS):

1. Install EAS CLI:
   ```bash
   npm install -g eas-cli
   ```

2. Log in to Expo:
   ```bash
   eas login
   ```

3. Configure the project:
   ```bash
   cd tarpn-terminal
   eas build:configure
   ```

4. Build for iOS:
   ```bash
   # Development build (requires Apple Developer account)
   eas build --platform ios --profile development

   # Preview build (AdHoc distribution)
   eas build --platform ios --profile preview

   # Production build (App Store)
   eas build --platform ios --profile production
   ```

**Requirements:**
- Apple Developer account ($99/year) for device builds
- Xcode on macOS for local development builds
- iOS device registered for development/AdHoc builds

### Android Native Build

1. Configure EAS (if not done):
   ```bash
   cd tarpn-terminal
   eas build:configure
   ```

2. Build for Android:
   ```bash
   # Development APK (sideload)
   eas build --platform android --profile development

   # Preview APK
   eas build --platform android --profile preview

   # Production AAB (Play Store)
   eas build --platform android --profile production
   ```

**Requirements:**
- Google Play Developer account ($25 one-time) for Play Store publishing
- Android device or emulator for testing

### Local Development Builds

For development without EAS:

**iOS (requires macOS with Xcode):**
```bash
cd tarpn-terminal
npx expo run:ios
```

**Android (requires Android Studio/SDK):**
```bash
cd tarpn-terminal
npx expo run:android
```

---

## WebSocket URL Configuration

The mobile/web app needs to know where to connect. By default, it connects to `ws://localhost:8212/ws`.

For production deployment, update the WebSocket URL in:
`tarpn-terminal/src/context/AppContext.js`

Or implement a settings screen for configurable server URL (recommended for mobile apps where the server isn't on localhost).

---

## Systemd Service (Production)

For production deployment on a Raspberry Pi:

```ini
# /etc/systemd/system/tarpn-terminal.service
[Unit]
Description=TARPN Terminal
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi
ExecStart=/home/pi/tarpn-terminal -call N0CALL -host localhost
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl enable tarpn-terminal
sudo systemctl start tarpn-terminal
```

---

## TARPN System Architecture

Understanding the existing TARPN installation helps when deploying tarpn-terminal alongside it.

### Installation Script Chain

TARPN uses a chain of installation scripts from `https://tarpn.net/bullseye2021/`:

1. **`w`** - Initial bootstrap (user downloads this)
   - Validates Raspberry Pi hardware and OS (Bullseye 32-bit)
   - Requires user `pi`
   - Downloads and runs `tarpn_start1.sh`

2. **`tarpn_start1.sh`** - Environment validation
   - Checks Pi revision codes for supported hardware
   - Validates OS version (Bullseye 11)
   - Saves source URL to `/usr/local/sbin/source_url.txt`
   - Downloads `tarpn_start1dl.sh`

3. **`tarpn_start1dl.sh`** - Main installer (~2000 lines)
   - Installs dependencies (zip, ftp, telnet, python packages)
   - Downloads LinBPQ (`bpq_6_0_21_40_mar_2021.zip`)
   - Installs tarpn-mon service
   - Sets up TARPN Home web interface
   - Configures systemd services
   - Reboots system

### Key Directories

| Path | Purpose |
|------|---------|
| `/home/pi/bpq/` | LinBPQ installation, bpq32.cfg, Files/ |
| `/home/pi/node.ini` | Node configuration file |
| `/usr/local/sbin/` | TARPN scripts and binaries |
| `/usr/local/etc/` | Configuration state files |
| `/var/log/` | TARPN log files |

### Key Files

| File | Purpose |
|------|---------|
| `/usr/local/sbin/tarpn-mon` | Existing tarpn-mon binary |
| `/usr/local/sbin/tarpnmon-runner.sh` | Service runner script |
| `/usr/local/sbin/runbpq.sh` | LinBPQ launcher script |
| `/usr/local/sbin/source_url.txt` | TARPN update URL |
| `/usr/local/etc/background.ini` | Background service state (`BACKGROUND:ON`) |
| `/etc/systemd/system/tarpn_mon.service` | tarpn-mon systemd service |

### tarpn-mon Service

The existing tarpn-mon is managed by `tarpnmon-runner.sh`:

```bash
# Service file: /etc/systemd/system/tarpn_mon.service
ExecStart=/usr/local/sbin/tarpnmon-runner.sh
Restart=always
RestartSec=2
```

The runner script:
- Only starts tarpn-mon if LinBPQ is running (`pgrep -nf linbpq`)
- Only runs if background mode is enabled (`BACKGROUND:ON` in `/usr/local/etc/background.ini`)
- Logs to `/var/log/tarpn_mon.log`
- Kills tarpn-mon if LinBPQ stops

### Parallel Testing Strategy

To test the new tarpn-terminal without affecting the production system:

1. **From a separate machine** (recommended):
   ```bash
   # Build for ARM on your dev machine
   GOOS=linux GOARCH=arm GOARM=7 go build -o tarpn-terminal-arm

   # Copy to Raspberry Pi
   scp tarpn-terminal-arm pi@raspberrypi:/home/pi/

   # SSH and run manually
   ssh pi@raspberrypi
   ./tarpn-terminal-arm -call N0CALL -host localhost
   ```

2. **Accessing from mobile/browser**:
   - Connect to `http://raspberrypi:8212` from your device
   - Or use the IP address directly

3. **Testing features**:
   - **Monitor**: Should work immediately (port 8011)
   - **Node Console**: Same callsign as production (port 8010)
   - **BBS**: Same callsign as production (port 8010)
   - **Chat**: Requires a completely different base callsign (see below)

### Chat Callsign Requirement

**Important**: BPQ Chat strips the SSID before checking for duplicate users. The code in LinBPQ (`ChatUtils.c:98-102`) explicitly does:

```c
strlop(callsign, '-');		// Remove any SSID
strcpy(user->Call, callsign);
```

This means `N0CALL-1` and `N0CALL-7` are treated as the same user. If you try to connect with any SSID variant of a callsign that's already connected, you'll get:
- "Already connected at this node" (closes old session)
- "Already connected at another node" (rejects new connection)

**For testing chat**, you must use a completely different callsign, such as:
- A different amateur callsign you hold
- A test/club callsign
- For development only: a temporary callsign (ensure compliance with regulations)

Source: [LinBPQ GitHub - ChatUtils.c](https://github.com/g8bpq/linbpq/blob/master/ChatUtils.c)

### Log Files

Monitor these for troubleshooting:

```bash
# Existing tarpn-mon logs
tail -f /var/log/tarpn_mon.log

# LinBPQ runner logs
tail -f /var/log/tarpn_runbpq.log

# System service logs
journalctl -u tarpn_mon.service -f
```

### Replacing Production tarpn-mon

When ready to replace the existing tarpn-mon:

```bash
# Stop existing service
sudo systemctl stop tarpn_mon.service

# Backup old binary
sudo mv /usr/local/sbin/tarpn-mon /usr/local/sbin/tarpn-mon.bak

# Install new binary
sudo cp tarpn-terminal-arm /usr/local/sbin/tarpn-mon
sudo chmod +x /usr/local/sbin/tarpn-mon

# Restart service
sudo systemctl start tarpn_mon.service
```

---

*Last updated: January 2026*
