#!/bin/bash
#
# TARPN Enhanced Monitor & Chat Installer
#
# This script installs tarpn-mon (monitoring backend) and tarpn-chat (chat server)
# on a standard TARPN node. It is designed to be run via:
#
#   curl -sSL https://tarpn-terminal.s3.us-east-1.amazonaws.com/latest/scripts/install.sh | sudo bash
#
# Or with options:
#   curl -sSL ... | sudo bash -s -- --call N0CALL-9 --skip-chat
#
# The script is idempotent - safe to run multiple times. It will:
#   - Skip installation if already at latest version
#   - Update to latest version if outdated
#   - Preserve existing configuration
#
# Environment variables:
#   TARPN_S3_BUCKET       - S3 bucket name (default: tarpn-releases)
#   TARPN_S3_REGION       - S3 region (default: us-east-1)
#   TARPN_RELEASE_VERSION - Specific version to install (default: latest)
#
# Requirements:
#   - Standard TARPN installation (LinBPQ)
#   - Raspberry Pi (ARM32/ARM64) or x86_64 Linux
#   - Internet connection (for downloading binaries)
#   - sudo/root access
#

set -e

# =============================================================================
# Configuration
# =============================================================================

# S3 bucket for releases
S3_BUCKET="${TARPN_S3_BUCKET:-tarpn-terminal}"
S3_REGION="${TARPN_S3_REGION:-us-east-1}"
RELEASE_BASE_URL="https://${S3_BUCKET}.s3.${S3_REGION}.amazonaws.com"

# Use 'latest' by default, or specify version
RELEASE_VERSION="${TARPN_RELEASE_VERSION:-latest}"

# Installation directories
TARPN_MON_DIR="/opt/tarpn-mon"
TARPN_CHAT_DIR="/opt/tarpn-chat"
BPQ_CONFIG_DIR="/home/pi/bpq"

# Default ports
TARPN_MON_PORT="8212"
NETROM_PORT="63119"  # LinBPQ's NETROMPORT (tarpn-chat connects TO LinBPQ)
TARPN_CHAT_CLIENT_PORT="8513"

# Version file locations (for idempotency)
TARPN_MON_VERSION_FILE="${TARPN_MON_DIR}/.version"
TARPN_CHAT_VERSION_FILE="${TARPN_CHAT_DIR}/.version"

# Script source URL (for downloading supporting files)
SCRIPT_BASE_URL="${RELEASE_BASE_URL}/${RELEASE_VERSION}/scripts"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Logging functions
# =============================================================================

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

# =============================================================================
# Command line parsing
# =============================================================================

INSTALL_MON=true
INSTALL_CHAT=true
FORCE_REINSTALL=false
NODE_CALL=""
NODE_ALIAS=""
SKIP_BPQ_PATCH=false
SKIP_LINBPQ_UPGRADE=false
UNINSTALL=false
DRY_RUN=false

print_usage() {
    cat << EOF
TARPN Enhanced Monitor & Chat Installer

Usage: $0 [options]

Options:
  --call CALL           Node callsign for chat (e.g., N0CALL-9)
  --alias ALIAS         Node alias for chat (default: derived from callsign)
  --skip-mon            Skip tarpn-mon installation
  --skip-chat           Skip tarpn-chat installation
  --skip-bpq-patch      Don't modify bpq32.cfg
  --skip-linbpq-upgrade Don't upgrade LinBPQ binary
  --force               Force reinstall even if up to date
  --uninstall           Remove installed components
  --dry-run             Show what would be done without doing it
  --help                Show this help message

Examples:
  # Full installation with default settings
  curl -sSL <url> | sudo bash

  # Install with specific callsign
  curl -sSL <url> | sudo bash -s -- --call N0CALL-9

  # Install only tarpn-mon (no chat)
  curl -sSL <url> | sudo bash -s -- --skip-chat

  # Update to latest version
  curl -sSL <url> | sudo bash

EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --call)
            NODE_CALL="$2"
            shift 2
            ;;
        --alias)
            NODE_ALIAS="$2"
            shift 2
            ;;
        --skip-mon)
            INSTALL_MON=false
            shift
            ;;
        --skip-chat)
            INSTALL_CHAT=false
            shift
            ;;
        --skip-bpq-patch)
            SKIP_BPQ_PATCH=true
            shift
            ;;
        --skip-linbpq-upgrade)
            SKIP_LINBPQ_UPGRADE=true
            shift
            ;;
        --force)
            FORCE_REINSTALL=true
            shift
            ;;
        --uninstall)
            UNINSTALL=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# =============================================================================
# Utility functions
# =============================================================================

# Detect system architecture and return binary suffix
# Note: We check userland (getconf) not kernel (uname) because Pi can run
# 64-bit kernel with 32-bit userland
detect_arch() {
    local kernel_arch=$(uname -m)
    local bits=$(getconf LONG_BIT 2>/dev/null || echo "unknown")

    case "$kernel_arch" in
        armv7l|armv6l)
            echo "arm32"
            ;;
        aarch64)
            # 64-bit kernel - check if userland is 32 or 64 bit
            if [ "$bits" = "32" ]; then
                echo "arm32"
            else
                echo "arm64"
            fi
            ;;
        x86_64)
            echo "amd64"
            ;;
        *)
            log_error "Unsupported architecture: $kernel_arch"
            exit 1
            ;;
    esac
}

# Get the release version from S3 manifest
get_latest_version() {
    local manifest_url="${RELEASE_BASE_URL}/${RELEASE_VERSION}/manifest.json"
    local version=$(curl -sS "$manifest_url" 2>/dev/null | grep '"version"' | head -1 | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
    if [ -z "$version" ]; then
        # Fallback to release version if manifest not available
        echo "$RELEASE_VERSION"
    else
        echo "$version"
    fi
}

# Get currently installed version
get_installed_version() {
    local version_file="$1"
    if [ -f "$version_file" ]; then
        cat "$version_file"
    else
        echo "none"
    fi
}

# Compare versions (returns 0 if $1 >= $2)
version_gte() {
    [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}

# Download a file with progress
download_file() {
    local url="$1"
    local dest="$2"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would download: $url -> $dest"
        return 0
    fi

    # -f matters. Without it curl happily writes an HTTP error body to the
    # destination file and exits 0, so a missing object in the bucket becomes
    # a "binary" containing S3's AccessDenied XML, which then gets chmod +x
    # and fails at runtime with something unrecognisable. Download to a temp
    # file, and only accept it if it is really an executable.
    local tmp
    tmp="$(mktemp "${dest}.XXXXXX")" || return 1

    if ! curl -fsSL "$url" -o "$tmp"; then
        rm -f "$tmp"
        log_error "Download failed: $url"
        log_error "That architecture may not be published. Nothing was written."
        return 1
    fi

    mv "$tmp" "$dest"
}

# For the compiled programs. An object missing from the bucket is the common
# case - an architecture that has not been published - and without this the
# error body becomes the "binary".
download_binary() {
    local url="$1" dest="$2"

    download_file "$url" "$dest" || return 1
    [ "$DRY_RUN" = true ] && return 0

    if ! head -c4 "$dest" | grep -q $'\x7fELF'; then
        log_error "Downloaded file is not an executable: $url"
        log_error "First bytes: $(head -c 80 "$dest" | tr -d '\0' | tr '\n' ' ')"
        rm -f "$dest"
        return 1
    fi
}

# Check if a systemd service exists and is enabled
service_exists() {
    systemctl list-unit-files "$1" &>/dev/null
}

# Detect callsign from bpq32.cfg - robust parsing for various formats
# This handles formats like: NODECALL=WA2M-2 ;comment or NODECALL=WA2M-2;NodecallsignComment
detect_nodecall() {
    local cfg_file="$1"
    [ ! -f "$cfg_file" ] && return 1

    # Get line starting with NODECALL= (case-insensitive)
    local line=$(grep -i "^NODECALL=" "$cfg_file" 2>/dev/null | head -1)
    [ -z "$line" ] && return 1

    # Extract value after = and extract only the callsign pattern
    # Callsign format: 1-2 letters, 1-2 digits, 1-3 letters, optionally -SSID
    local value=$(echo "$line" | sed -E 's/^[Nn][Oo][Dd][Ee][Cc][Aa][Ll][Ll]=([A-Za-z]{1,2}[0-9]{1,2}[A-Za-z]{1,3}(-[0-9]{1,2})?).*/\1/')

    # Validate it looks like a callsign
    if echo "$value" | grep -qE '^[A-Za-z]{1,2}[0-9]{1,2}[A-Za-z]{1,3}(-[0-9]{1,2})?$'; then
        echo "$value" | tr '[:lower:]' '[:upper:]'
        return 0
    fi
    return 1
}

# Strip SSID from callsign (WA2M-2 -> WA2M)
strip_ssid() {
    echo "$1" | cut -d'-' -f1
}

# Parse OtherChatNodes from chatconfig.cfg
# Format: OtherChatNodes = "ALIAS:CALL\r\nALIAS2:CALL2";
# The \r\n are literal characters in the config file (not actual newlines)
# Returns lines of "ALIAS CALL" pairs
parse_other_chat_nodes() {
    local cfg_file="$1"
    [ ! -f "$cfg_file" ] && return 1

    # Extract OtherChatNodes value from between quotes
    local value=$(grep -i "OtherChatNodes" "$cfg_file" 2>/dev/null | \
        sed -E 's/.*OtherChatNodes\s*=\s*"([^"]+)".*/\1/' | head -1)
    [ -z "$value" ] && return 1

    # Replace literal \r\n with newlines, then parse ALIAS:CALL pairs
    # Also handle just \n in case some configs omit the \r
    echo "$value" | sed 's/\\r\\n/\n/g; s/\\n/\n/g' | \
        grep -i ':' | while IFS=':' read -r alias call; do
            # Trim whitespace and validate we have both parts
            alias=$(echo "$alias" | tr -d ' ')
            call=$(echo "$call" | tr -d ' ' | tr '[:lower:]' '[:upper:]')
            [ -n "$alias" ] && [ -n "$call" ] && echo "$alias $call"
        done
}

# Find chatconfig.cfg in standard locations
find_chatconfig() {
    local bpq_dir="$1"
    local locations=(
        "${bpq_dir}/chatconfig.cfg"
        "/home/pi/linbpq/chatconfig.cfg"
        "/home/pi/bpq/chatconfig.cfg"
    )
    for loc in "${locations[@]}"; do
        if [ -f "$loc" ]; then
            echo "$loc"
            return 0
        fi
    done
    return 1
}

# =============================================================================
# Pre-flight checks
# =============================================================================

preflight_checks() {
    log_step "Running pre-flight checks..."

    # Check root/sudo
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi

    # Check for required commands
    for cmd in curl systemctl grep sed; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Required command not found: $cmd"
            exit 1
        fi
    done

    # Check for pi user (standard TARPN)
    if ! id "pi" &>/dev/null; then
        log_warn "User 'pi' not found. This doesn't look like a standard TARPN installation."
        log_warn "Services will run as root instead."
    fi

    # Detect architecture
    ARCH=$(detect_arch)
    log_info "Detected architecture: $ARCH"

    # Get latest version
    log_info "Checking for latest release..."
    LATEST_VERSION=$(get_latest_version)
    if [ -z "$LATEST_VERSION" ]; then
        log_error "Could not determine latest version. Check your internet connection."
        exit 1
    fi
    log_info "Latest version: $LATEST_VERSION"

    # Check what needs updating
    MON_CURRENT=$(get_installed_version "$TARPN_MON_VERSION_FILE")
    CHAT_CURRENT=$(get_installed_version "$TARPN_CHAT_VERSION_FILE")

    log_info "tarpn-mon:  installed=$MON_CURRENT, latest=$LATEST_VERSION"
    log_info "tarpn-chat: installed=$CHAT_CURRENT, latest=$LATEST_VERSION"
}

# =============================================================================
# Uninstall function
# =============================================================================

do_uninstall() {
    log_step "Uninstalling TARPN Enhanced components..."

    # Stop and disable services
    for service in tarpn-mon tarpn-chat tarpn-chat-config.path send-routes-via-cq.timer send-routes-via-cq; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log_info "Stopping $service..."
            systemctl stop "$service" || true
        fi
        if systemctl is-enabled --quiet "$service" 2>/dev/null; then
            log_info "Disabling $service..."
            systemctl disable "$service" || true
        fi
    done

    # Remove systemd unit files
    rm -f /etc/systemd/system/tarpn-mon.service
    rm -f /etc/systemd/system/tarpn-chat.service
    rm -f /etc/systemd/system/tarpn-chat-config.service
    rm -f /etc/systemd/system/tarpn-chat-config.path
    rm -f /etc/systemd/system/send-routes-via-cq.service
    rm -f /etc/systemd/system/send-routes-via-cq.timer
    systemctl daemon-reload

    # Remove installation directories (but backup configs)
    if [ -d "$TARPN_MON_DIR" ]; then
        if [ -f "$TARPN_MON_DIR/config.toml" ]; then
            cp "$TARPN_MON_DIR/config.toml" "/tmp/tarpn-mon-config.toml.backup"
            log_info "Config backed up to /tmp/tarpn-mon-config.toml.backup"
        fi
        rm -rf "$TARPN_MON_DIR"
        log_info "Removed $TARPN_MON_DIR"
    fi

    if [ -d "$TARPN_CHAT_DIR" ]; then
        if [ -f "$TARPN_CHAT_DIR/config.toml" ]; then
            cp "$TARPN_CHAT_DIR/config.toml" "/tmp/tarpn-chat-config.toml.backup"
            log_info "Config backed up to /tmp/tarpn-chat-config.toml.backup"
        fi
        rm -rf "$TARPN_CHAT_DIR"
        log_info "Removed $TARPN_CHAT_DIR"
    fi

    # Remove log files
    rm -f /var/log/tarpn-mon.log
    rm -f /var/log/tarpn-chat.log
    rm -f /var/log/tarpn-chat-patch.log
    rm -f /var/log/send-routes-via-cq.log

    log_info "Uninstall complete"
    log_warn "Note: bpq32.cfg was not modified. You may need to restore the original CHAT configuration."

    exit 0
}

# =============================================================================
# Install tarpn-mon
# =============================================================================

install_tarpn_mon() {
    log_step "Installing tarpn-mon..."

    local current_version=$(get_installed_version "$TARPN_MON_VERSION_FILE")

    # Check if update needed
    if [ "$current_version" = "$LATEST_VERSION" ] && [ "$FORCE_REINSTALL" = false ]; then
        log_info "tarpn-mon is already at version $LATEST_VERSION - skipping"
        return 0
    fi

    if [ "$current_version" != "none" ]; then
        log_info "Updating tarpn-mon from $current_version to $LATEST_VERSION"
        # Stop service before replacing binary
        if systemctl is-active --quiet tarpn-mon 2>/dev/null; then
            log_info "Stopping tarpn-mon service for update..."
            systemctl stop tarpn-mon || true
        fi
    else
        log_info "Installing tarpn-mon $LATEST_VERSION"
    fi

    # Create installation directory
    mkdir -p "$TARPN_MON_DIR"

    # Download binary
    local binary_name="tarpn-mon.linux-${ARCH}"
    local download_url="${RELEASE_BASE_URL}/${RELEASE_VERSION}/${binary_name}"

    log_info "Downloading $binary_name..."
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would download: $download_url"
    else
        download_binary "$download_url" "${TARPN_MON_DIR}/tarpn-mon"
        chmod +x "${TARPN_MON_DIR}/tarpn-mon"
    fi

    # Download/create systemd service
    log_info "Installing systemd service..."
    if [ "$DRY_RUN" = false ]; then
        cat > /etc/systemd/system/tarpn-mon.service << EOF
[Unit]
Description=TARPN Enhanced Monitor
Documentation=https://github.com/wozz/tarpn-mon
After=network.target

[Service]
Type=simple
User=pi
Group=pi
WorkingDirectory=${TARPN_MON_DIR}
ExecStart=${TARPN_MON_DIR}/tarpn-mon -call \$TARPN_MON_CALL -stats
Restart=always
RestartSec=5

# Logging
StandardOutput=append:/var/log/tarpn-mon.log
StandardError=append:/var/log/tarpn-mon.log

# Environment file (optional)
EnvironmentFile=-${TARPN_MON_DIR}/tarpn-mon.env

[Install]
WantedBy=multi-user.target
EOF
    fi

    # Create or update environment file (uses global detect_nodecall function)
    local detected_call=""
    if [ -f "${BPQ_CONFIG_DIR}/bpq32.cfg" ]; then
        detected_call=$(detect_nodecall "${BPQ_CONFIG_DIR}/bpq32.cfg" || echo "")
    fi

    if [ "$DRY_RUN" = false ]; then
        # Check if env file exists and has bad callsign
        local needs_update=false
        if [ -f "${TARPN_MON_DIR}/tarpn-mon.env" ]; then
            local current_call=$(grep "^TARPN_MON_CALL=" "${TARPN_MON_DIR}/tarpn-mon.env" 2>/dev/null | cut -d'=' -f2)
            # Check if current value contains semicolon or other invalid chars
            if echo "$current_call" | grep -q '[;]'; then
                log_info "Detected malformed callsign in env file, updating..."
                needs_update=true
            fi
        else
            needs_update=true
        fi

        if [ "$needs_update" = true ]; then
            cat > "${TARPN_MON_DIR}/tarpn-mon.env" << EOF
# tarpn-mon configuration
# Edit this file and restart the service: sudo systemctl restart tarpn-mon

# Your callsign (used for display and chat features)
TARPN_MON_CALL=${detected_call:-N0CALL}

# LinBPQ connection settings (usually no changes needed)
# TARPN_MON_HOST=localhost
# TARPN_MON_BPQ_PORT=8010
# TARPN_MON_MONITOR_PORT=8011

# Web interface port
# TARPN_MON_PORT=${TARPN_MON_PORT}
EOF
            log_info "Created default config: ${TARPN_MON_DIR}/tarpn-mon.env"
        fi

        # Create log file
        touch /var/log/tarpn-mon.log
        chown pi:pi /var/log/tarpn-mon.log 2>/dev/null || true
        chown -R pi:pi "$TARPN_MON_DIR" 2>/dev/null || true
    fi

    # Save version
    if [ "$DRY_RUN" = false ]; then
        echo "$LATEST_VERSION" > "$TARPN_MON_VERSION_FILE"
    fi

    # Enable and start service
    if [ "$DRY_RUN" = false ]; then
        systemctl daemon-reload
        systemctl enable tarpn-mon.service

        # Only start if not already running with same version
        if systemctl is-active --quiet tarpn-mon; then
            log_info "Restarting tarpn-mon service..."
            systemctl restart tarpn-mon.service
        else
            log_info "Starting tarpn-mon service..."
            systemctl start tarpn-mon.service
        fi
    fi

    log_info "tarpn-mon installed successfully"
}

# =============================================================================
# Install tarpn-chat
# =============================================================================

install_tarpn_chat() {
    log_step "Installing tarpn-chat..."

    local current_version=$(get_installed_version "$TARPN_CHAT_VERSION_FILE")

    # Check if update needed
    if [ "$current_version" = "$LATEST_VERSION" ] && [ "$FORCE_REINSTALL" = false ]; then
        log_info "tarpn-chat is already at version $LATEST_VERSION - skipping"
        return 0
    fi

    if [ "$current_version" != "none" ]; then
        log_info "Updating tarpn-chat from $current_version to $LATEST_VERSION"
        # Stop service before replacing binary
        if systemctl is-active --quiet tarpn-chat 2>/dev/null; then
            log_info "Stopping tarpn-chat service for update..."
            systemctl stop tarpn-chat || true
        fi
    else
        log_info "Installing tarpn-chat $LATEST_VERSION"
    fi

    # Get callsign if not provided
    if [ -z "$NODE_CALL" ]; then
        # Try to detect from existing config
        if [ -f "${TARPN_CHAT_DIR}/config.toml" ]; then
            NODE_CALL=$(grep "^call" "${TARPN_CHAT_DIR}/config.toml" 2>/dev/null | head -1 | cut -d'"' -f2)
        fi

        # Try to detect from bpq32.cfg using robust parsing
        if [ -z "$NODE_CALL" ] && [ -f "${BPQ_CONFIG_DIR}/bpq32.cfg" ]; then
            local detected_call=$(detect_nodecall "${BPQ_CONFIG_DIR}/bpq32.cfg" || echo "")
            if [ -n "$detected_call" ]; then
                # Always use base call + -9 for chat (standard chat SSID)
                local base_call=$(strip_ssid "$detected_call")
                NODE_CALL="${base_call}-9"
            fi
        fi

        # Prompt if still not found
        if [ -z "$NODE_CALL" ]; then
            log_error "Chat node callsign not specified and could not be auto-detected."
            log_error "Please run with --call option, e.g.: --call N0CALL-9"
            exit 1
        fi
    fi

    # Generate alias if not provided
    if [ -z "$NODE_ALIAS" ]; then
        # Try to read from existing config first
        if [ -f "${TARPN_CHAT_DIR}/config.toml" ]; then
            NODE_ALIAS=$(grep "^alias" "${TARPN_CHAT_DIR}/config.toml" 2>/dev/null | head -1 | cut -d'"' -f2)
        fi

        # Generate from callsign: Y + chars 2,3,4 + 09 (e.g., WA2M -> YA2M09)
        if [ -z "$NODE_ALIAS" ]; then
            local base_call=$(echo "$NODE_CALL" | cut -d'-' -f1 | tr '[:lower:]' '[:upper:]')
            local middle=$(echo "$base_call" | cut -c2-4)
            NODE_ALIAS="Y${middle}09"
        fi
    fi

    log_info "Chat node: call=$NODE_CALL, alias=$NODE_ALIAS"

    # Create installation directory
    mkdir -p "$TARPN_CHAT_DIR"

    # Download binary
    local binary_name="tarpn-chat-${ARCH}"
    local download_url="${RELEASE_BASE_URL}/${RELEASE_VERSION}/${binary_name}"

    log_info "Downloading $binary_name..."
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would download: $download_url"
    else
        download_binary "$download_url" "${TARPN_CHAT_DIR}/tarpn-chat"
        chmod +x "${TARPN_CHAT_DIR}/tarpn-chat"
    fi

    # Create config file (preserve existing if present)
    if [ ! -f "${TARPN_CHAT_DIR}/config.toml" ] && [ "$DRY_RUN" = false ]; then
        # Parse OtherChatNodes from LinBPQ chatconfig.cfg if available
        local chatconfig=$(find_chatconfig "$BPQ_CONFIG_DIR")
        local other_nodes=""
        if [ -n "$chatconfig" ]; then
            log_info "Found chatconfig.cfg: $chatconfig"
            other_nodes=$(parse_other_chat_nodes "$chatconfig")
            if [ -n "$other_nodes" ]; then
                log_info "Found OtherChatNodes: $(echo "$other_nodes" | wc -l) peer(s)"
            fi
        fi

        # Generate config
        cat > "${TARPN_CHAT_DIR}/config.toml" << EOF
# tarpn-chat configuration
# Generated by installer on $(date)

[node]
call = "$NODE_CALL"
alias = "$NODE_ALIAS"

[netrom]
# LinBPQ's NETROMPORT address (tarpn-chat connects TO LinBPQ)
linbpq = "127.0.0.1:${NETROM_PORT}"

# Client API for local WebSocket clients (tarpn-mon backend)
[client]
port = ${TARPN_CHAT_CLIENT_PORT}
bind = "127.0.0.1"
max_clients = 10

EOF

        # Add known_nodes from OtherChatNodes (for identifying inbound connections)
        # These are other chat nodes in the network that will connect to us via
        # LinBPQ's NetROM routing.
        if [ -n "$other_nodes" ]; then
            echo "" >> "${TARPN_CHAT_DIR}/config.toml"
            echo "# Known chat nodes (from LinBPQ OtherChatNodes)" >> "${TARPN_CHAT_DIR}/config.toml"
            echo "# These nodes connect to us via LinBPQ NetROM routing" >> "${TARPN_CHAT_DIR}/config.toml"
            echo "$other_nodes" | while read alias call; do
                cat >> "${TARPN_CHAT_DIR}/config.toml" << EOF

[[known_nodes]]
call = "$call"
alias = "$alias"
EOF
            done
        else
            cat >> "${TARPN_CHAT_DIR}/config.toml" << EOF

# Peer chat nodes we connect to via L4 (outbound connections)
# [[peers]]
# call = "REMOTE-9"
# alias = "RMTCHT"
# auto_reconnect = true
# reconnect_delay = 30
EOF
        fi

        log_info "Created config: ${TARPN_CHAT_DIR}/config.toml"
    else
        log_info "Preserving existing config: ${TARPN_CHAT_DIR}/config.toml"
    fi

    # Download/install patch script
    if [ "$DRY_RUN" = false ]; then
        download_file "${SCRIPT_BASE_URL}/patch-bpq32-config.sh" "${TARPN_CHAT_DIR}/patch-bpq32-config.sh"
        chmod +x "${TARPN_CHAT_DIR}/patch-bpq32-config.sh"

        # Update port in patch script if non-default
        if [ "$NETROM_PORT" != "63119" ]; then
            sed -i "s/NETROM_PORT=63119/NETROM_PORT=${NETROM_PORT}/" "${TARPN_CHAT_DIR}/patch-bpq32-config.sh"
        fi
    fi

    # Install systemd services
    log_info "Installing systemd services..."
    if [ "$DRY_RUN" = false ]; then
        # Main chat service
        cat > /etc/systemd/system/tarpn-chat.service << EOF
[Unit]
Description=TARPN Chat Service
Documentation=https://github.com/wozz/tarpn-mon
After=network.target

[Service]
Type=simple
User=pi
Group=pi
WorkingDirectory=${TARPN_CHAT_DIR}
ExecStart=${TARPN_CHAT_DIR}/tarpn-chat --config ${TARPN_CHAT_DIR}/config.toml
Restart=always
RestartSec=5

StandardOutput=append:/var/log/tarpn-chat.log
StandardError=append:/var/log/tarpn-chat.log

Environment=RUST_LOG=info

[Install]
WantedBy=multi-user.target
EOF

        # Config patcher service (triggered by path unit)
        cat > /etc/systemd/system/tarpn-chat-config.service << EOF
[Unit]
Description=TARPN Chat Config Patcher
After=network.target

[Service]
Type=oneshot
ExecStart=${TARPN_CHAT_DIR}/patch-bpq32-config.sh

StandardOutput=append:/var/log/tarpn-chat-patch.log
StandardError=append:/var/log/tarpn-chat-patch.log
EOF

        # Path watcher (triggers config patcher when bpq32.cfg changes)
        cat > /etc/systemd/system/tarpn-chat-config.path << EOF
[Unit]
Description=Watch for bpq32.cfg changes

[Path]
PathModified=${BPQ_CONFIG_DIR}/bpq32.cfg

[Install]
WantedBy=multi-user.target
EOF
    fi

    # Create log files
    if [ "$DRY_RUN" = false ]; then
        touch /var/log/tarpn-chat.log
        touch /var/log/tarpn-chat-patch.log
        chown pi:pi /var/log/tarpn-chat.log 2>/dev/null || true
        chown pi:pi /var/log/tarpn-chat-patch.log 2>/dev/null || true
        chown -R pi:pi "$TARPN_CHAT_DIR" 2>/dev/null || true
    fi

    # Save version
    if [ "$DRY_RUN" = false ]; then
        echo "$LATEST_VERSION" > "$TARPN_CHAT_VERSION_FILE"
    fi

    # Enable and start services
    if [ "$DRY_RUN" = false ]; then
        systemctl daemon-reload
        systemctl enable tarpn-chat.service
        systemctl enable tarpn-chat-config.path

        if systemctl is-active --quiet tarpn-chat; then
            log_info "Restarting tarpn-chat service..."
            systemctl restart tarpn-chat.service
        else
            log_info "Starting tarpn-chat service..."
            systemctl start tarpn-chat.service
        fi

        systemctl start tarpn-chat-config.path
    fi

    log_info "tarpn-chat installed successfully"
}

# =============================================================================
# Patch bpq32.cfg
# =============================================================================

patch_bpq_config() {
    if [ "$SKIP_BPQ_PATCH" = true ]; then
        log_info "Skipping bpq32.cfg patch (--skip-bpq-patch)"
        return 0
    fi

    if [ ! -f "${BPQ_CONFIG_DIR}/bpq32.cfg" ]; then
        log_warn "bpq32.cfg not found at ${BPQ_CONFIG_DIR}/bpq32.cfg"
        log_warn "Config will be patched automatically when TARPN starts/restarts"
        return 0
    fi

    log_step "Patching bpq32.cfg..."

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would run: ${TARPN_CHAT_DIR}/patch-bpq32-config.sh"
        return 0
    fi

    if [ -x "${TARPN_CHAT_DIR}/patch-bpq32-config.sh" ]; then
        "${TARPN_CHAT_DIR}/patch-bpq32-config.sh"
    else
        log_warn "Patch script not found - skipping bpq32.cfg modification"
    fi
}

# =============================================================================
# Patch TARPN scripts to preserve BPQNODES.dat
# =============================================================================
# TARPN's tarpn_background.sh deletes BPQNODES.dat on every startup due to
# dynamic port assignment concerns. However, our chat node entry uses port 32
# (telnet), which never changes. We patch the script to preserve the file.

patch_tarpn_scripts() {
    if [ "$SKIP_BPQ_PATCH" = true ]; then
        log_info "Skipping TARPN script patch (--skip-bpq-patch)"
        return 0
    fi

    # Find tarpn_background.sh (location varies between TARPN versions)
    local TARPN_BG=""
    for path in "/usr/tarpn/sbin/tarpn_background.sh" "/usr/local/sbin/tarpn_background.sh" "/home/pi/tarpn2/bin/tarpn_background.sh"; do
        if [ -f "$path" ]; then
            TARPN_BG="$path"
            break
        fi
    done

    if [ -z "$TARPN_BG" ]; then
        log_warn "tarpn_background.sh not found - skipping TARPN script patch"
        return 0
    fi

    log_step "Checking TARPN scripts for BPQNODES.dat preservation..."

    # Check if the script deletes BPQNODES.dat
    if grep -q "rm -rf /home/pi/bpq/BPQNODES.dat" "$TARPN_BG" && \
       ! grep -q "# Disabled by tarpn-chat:" "$TARPN_BG"; then

        log_info "Found BPQNODES.dat deletion in $TARPN_BG"

        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY-RUN] Would patch $TARPN_BG to preserve BPQNODES.dat"
            return 0
        fi

        # Create backup
        cp "$TARPN_BG" "${TARPN_BG}.pre-tarpn-chat.bak"

        # Comment out the rm line
        sed -i 's|sudo rm -rf /home/pi/bpq/BPQNODES.dat|# Disabled by tarpn-chat: sudo rm -rf /home/pi/bpq/BPQNODES.dat|' "$TARPN_BG"

        log_info "Patched $TARPN_BG to preserve BPQNODES.dat"
    else
        log_info "TARPN script already patched or doesn't delete BPQNODES.dat"
    fi
}

# =============================================================================
# Install send-routes-via-cq (replaces legacy TARPN sendroutestocq)
# =============================================================================
# The legacy TARPN sendroutestocq binary is a 32-bit ARM binary that broadcasts
# TARPNstat link quality messages via CQ. Our Go rewrite is portable and supports
# newer LinBPQ route table formats (double-locked routes, high port numbers).

SENDROUTESVIACQ_DIR="/opt/tarpn-mon"  # Colocated with tarpn-mon

install_sendroutesviacq() {
    log_step "Installing send-routes-via-cq..."

    # Download binary
    local binary_name="send-routes-via-cq.linux-${ARCH}"
    local download_url="${RELEASE_BASE_URL}/${RELEASE_VERSION}/${binary_name}"

    log_info "Downloading $binary_name..."
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would download: $download_url"
    else
        mkdir -p "$SENDROUTESVIACQ_DIR"
        download_binary "$download_url" "${SENDROUTESVIACQ_DIR}/send-routes-via-cq"
        chmod +x "${SENDROUTESVIACQ_DIR}/send-routes-via-cq"
        chown pi:pi "${SENDROUTESVIACQ_DIR}/send-routes-via-cq" 2>/dev/null || true
    fi

    # Install systemd service and timer (runs every 15 minutes, matching legacy timing)
    log_info "Installing systemd timer..."
    if [ "$DRY_RUN" = false ]; then
        cat > /etc/systemd/system/send-routes-via-cq.service << EOF
[Unit]
Description=TARPN Link Status Broadcaster (send-routes-via-cq)
After=network.target

[Service]
Type=oneshot
User=pi
Group=pi
ExecStart=${SENDROUTESVIACQ_DIR}/send-routes-via-cq

StandardOutput=append:/var/log/send-routes-via-cq.log
StandardError=append:/var/log/send-routes-via-cq.log
EOF

        cat > /etc/systemd/system/send-routes-via-cq.timer << EOF
[Unit]
Description=Run send-routes-via-cq every 15 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=15min
RandomizedDelaySec=30

[Install]
WantedBy=timers.target
EOF

        # Create log file
        touch /var/log/send-routes-via-cq.log
        chown pi:pi /var/log/send-routes-via-cq.log 2>/dev/null || true

        systemctl daemon-reload
        systemctl enable send-routes-via-cq.timer
        systemctl start send-routes-via-cq.timer
    fi

    log_info "send-routes-via-cq installed successfully (runs every 15 min)"
}

# Patch statusmonitor.sh to disable legacy sendroutestocq
# Our send-routes-via-cq replaces it via systemd timer
patch_sendroutesviacq() {
    # Find statusmonitor.sh
    local STATUS_MON=""
    for path in "/usr/tarpn/sbin/statusmonitor.sh" "/usr/local/sbin/statusmonitor.sh" "/home/pi/tarpn2/bin/statusmonitor.sh"; do
        if [ -f "$path" ]; then
            STATUS_MON="$path"
            break
        fi
    done

    if [ -z "$STATUS_MON" ]; then
        log_info "statusmonitor.sh not found - no legacy sendroutestocq to disable"
        return 0
    fi

    log_step "Checking for legacy sendroutestocq in statusmonitor.sh..."

    # Check if it calls sendroutestocq and hasn't been patched yet
    # Path varies: /usr/tarpn/sbin/ (Bookworm) or /usr/local/sbin/ (Bullseye)
    if grep -q "sendroutestocq" "$STATUS_MON" && \
       ! grep -q "# Disabled by tarpn-mon:" "$STATUS_MON"; then

        log_info "Found legacy sendroutestocq calls in $STATUS_MON"

        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY-RUN] Would patch $STATUS_MON to disable sendroutestocq"
            return 0
        fi

        # Create backup
        cp "$STATUS_MON" "${STATUS_MON}.pre-sendroutesviacq.bak"

        # Comment out all sendroutestocq invocations (handles both Bullseye and Bookworm paths)
        # 1. The version check at startup
        sed -i 's|^\(\s*\)\(.*/sendroutestocq version\)|# Disabled by tarpn-mon: \2|' "$STATUS_MON"
        # 2. The main execution in the loop
        sed -i 's|^\(\s*\)\(.*/sendroutestocq\s*$\)|# Disabled by tarpn-mon: \2|' "$STATUS_MON"
        # 3. The check_process call (prevent false "redundantly running" errors)
        sed -i 's|check_process "sendroutestocq"|# Disabled by tarpn-mon: check_process "sendroutestocq"|' "$STATUS_MON"

        log_info "Patched $STATUS_MON - legacy sendroutestocq disabled"
        log_info "Replaced by send-routes-via-cq systemd timer"
    else
        log_info "statusmonitor.sh already patched or doesn't use sendroutestocq"
    fi
}

# =============================================================================
# Upgrade LinBPQ to latest version (required for NETROMPORT support)
# =============================================================================

upgrade_linbpq() {
    if [ "$SKIP_LINBPQ_UPGRADE" = true ]; then
        log_info "Skipping LinBPQ upgrade (--skip-linbpq-upgrade)"
        return 0
    fi

    local LINBPQ_BINARY="${BPQ_CONFIG_DIR}/linbpq"
    local LINBPQ_URL="https://www.cantab.net/users/john.wiseman/Downloads/Beta/pilinbpq"

    # Check if LinBPQ exists
    if [ ! -f "$LINBPQ_BINARY" ]; then
        log_warn "LinBPQ not found at $LINBPQ_BINARY"
        log_warn "Skipping LinBPQ upgrade - install TARPN first"
        return 0
    fi

    log_step "Checking LinBPQ version..."

    # Get current version (if possible)
    local current_version=""
    if [ -x "$LINBPQ_BINARY" ]; then
        current_version=$(strings "$LINBPQ_BINARY" 2>/dev/null | grep -oP '6\.0\.\d+\.\d+' | head -1 || echo "unknown")
    fi
    log_info "Current LinBPQ version: ${current_version:-unknown}"

    # Check if version supports NETROMPORT (need 6.0.25.x or higher)
    local needs_upgrade=false
    if [ -n "$current_version" ]; then
        local major_minor=$(echo "$current_version" | cut -d'.' -f1-3)
        if [ "$major_minor" = "6.0.24" ] || [ "$major_minor" = "6.0.23" ] || [ "$major_minor" = "6.0.22" ]; then
            needs_upgrade=true
            log_info "LinBPQ $current_version does not support NETROMPORT (requires 6.0.25+)"
        fi
    else
        # Can't determine version, offer to upgrade anyway
        needs_upgrade=true
        log_warn "Could not determine LinBPQ version"
    fi

    if [ "$needs_upgrade" = false ] && [ "$FORCE_REINSTALL" = false ]; then
        log_info "LinBPQ version appears to support NETROMPORT - skipping upgrade"
        return 0
    fi

    log_step "Upgrading LinBPQ to latest version..."

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would download: $LINBPQ_URL"
        log_info "[DRY-RUN] Would backup to: ${LINBPQ_BINARY}.backup.$(date +%Y%m%d-%H%M%S)"
        return 0
    fi

    # Backup with timestamp
    local backup_name="${LINBPQ_BINARY}.backup.$(date +%Y%m%d-%H%M%S)"
    cp "$LINBPQ_BINARY" "$backup_name"
    log_info "Backed up to: $backup_name"

    # Download latest
    log_info "Downloading latest LinBPQ from G8BPQ..."
    if curl -sSL "$LINBPQ_URL" -o "${LINBPQ_BINARY}.new"; then
        chmod +x "${LINBPQ_BINARY}.new"
        mv "${LINBPQ_BINARY}.new" "$LINBPQ_BINARY"
        chown pi:pi "$LINBPQ_BINARY" 2>/dev/null || true

        # Verify new version
        local new_version=$(strings "$LINBPQ_BINARY" 2>/dev/null | grep -oP '6\.0\.\d+\.\d+' | head -1 || echo "unknown")
        log_info "Upgraded LinBPQ to version: ${new_version:-unknown}"
    else
        log_error "Failed to download LinBPQ - restoring backup"
        cp "$backup_name" "$LINBPQ_BINARY"
        return 1
    fi
}

# =============================================================================
# Configure OARC API (session tracking)
# =============================================================================
# LinBPQ's OARC API provides structured JSON events for session tracking.
# It sends UDP datagrams to node-api.packet.oarc.uk:13579. We redirect
# that hostname to localhost via /etc/hosts so tarpn-mon receives them.

configure_oarc_api() {
    log_step "Configuring OARC API for session tracking..."

    local bpq_cfg="${BPQ_CONFIG_DIR}/bpq32.cfg"
    local hosts_file="/etc/hosts"
    local oarc_host="node-api.packet.oarc.uk"

    # 1. Redirect OARC hostname to localhost FIRST — must happen before enabling
    #    the API in bpq32.cfg to ensure no data is sent to the remote server.
    if grep -q "$oarc_host" "$hosts_file" 2>/dev/null; then
        log_info "/etc/hosts already has $oarc_host entry"
    else
        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY-RUN] Would add '127.0.0.1 $oarc_host' to $hosts_file"
        else
            echo "127.0.0.1 $oarc_host" >> "$hosts_file"
            log_info "Added '127.0.0.1 $oarc_host' to $hosts_file"
        fi
    fi

    # 2. Add ENABLEOARCAPI=1 to bpq32.cfg (safe now that hosts redirect is in place)
    if [ -f "$bpq_cfg" ]; then
        if grep -qi "ENABLEOARCAPI" "$bpq_cfg"; then
            log_info "ENABLEOARCAPI already present in bpq32.cfg"
        else
            if [ "$DRY_RUN" = true ]; then
                log_info "[DRY-RUN] Would add ENABLEOARCAPI=1 to $bpq_cfg"
            else
                # Insert after the NODECALL line (or at top of file if not found)
                if grep -qi "^NODECALL=" "$bpq_cfg"; then
                    sed -i '/^NODECALL=/a ENABLEOARCAPI=1' "$bpq_cfg"
                else
                    # Prepend to file
                    sed -i '1i ENABLEOARCAPI=1' "$bpq_cfg"
                fi
                log_info "Added ENABLEOARCAPI=1 to $bpq_cfg"
            fi
        fi
    else
        log_warn "bpq32.cfg not found at $bpq_cfg - OARC API will be configured on next TARPN restart"
    fi
}

# =============================================================================
# Post-install summary
# =============================================================================

print_summary() {
    echo ""
    echo "=============================================="
    echo "  TARPN Enhanced Installation Complete!"
    echo "=============================================="
    echo ""

    if [ "$INSTALL_MON" = true ]; then
        echo "tarpn-mon:"
        echo "  Status:    $(systemctl is-active tarpn-mon.service 2>/dev/null || echo 'not running')"
        echo "  Version:   $(cat $TARPN_MON_VERSION_FILE 2>/dev/null || echo 'unknown')"
        echo "  Web UI:    http://$(hostname -I | awk '{print $1}'):${TARPN_MON_PORT}"
        echo "  Config:    ${TARPN_MON_DIR}/tarpn-mon.env"
        echo "  Logs:      /var/log/tarpn-mon.log"
        echo ""
        echo "OARC API (session tracking):"
        echo "  bpq32.cfg: ENABLEOARCAPI=1"
        echo "  /etc/hosts: 127.0.0.1 node-api.packet.oarc.uk"
        echo "  UDP port:  13579 (tarpn-mon listens here)"
        echo ""
        echo "send-routes-via-cq:"
        echo "  Timer:     $(systemctl is-active send-routes-via-cq.timer 2>/dev/null || echo 'not running')"
        echo "  Schedule:  every 15 minutes"
        echo "  Logs:      /var/log/send-routes-via-cq.log"
        echo ""
    fi

    if [ "$INSTALL_CHAT" = true ]; then
        echo "tarpn-chat:"
        echo "  Status:    $(systemctl is-active tarpn-chat.service 2>/dev/null || echo 'not running')"
        echo "  Version:   $(cat $TARPN_CHAT_VERSION_FILE 2>/dev/null || echo 'unknown')"
        echo "  Callsign:  ${NODE_CALL}"
        echo "  Config:    ${TARPN_CHAT_DIR}/config.toml"
        echo "  Logs:      /var/log/tarpn-chat.log"
        echo ""
    fi

    echo "Next steps:"
    echo "  1. Edit config files if needed"
    echo "  2. Restart TARPN services to pick up changes:"
    echo "       tarpn service restart"
    echo "  3. Access the web interface"
    echo ""
    echo "To update in the future, just run this script again."
    echo "To uninstall: $0 --uninstall"
    echo ""
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo ""
    echo "=============================================="
    echo "  TARPN Enhanced Monitor & Chat Installer"
    echo "=============================================="
    echo ""

    # Handle uninstall
    if [ "$UNINSTALL" = true ]; then
        do_uninstall
        exit 0
    fi

    # Pre-flight checks
    preflight_checks

    # Install components
    if [ "$INSTALL_MON" = true ]; then
        install_tarpn_mon
        configure_oarc_api
        install_sendroutesviacq
        patch_sendroutesviacq
    fi

    if [ "$INSTALL_CHAT" = true ]; then
        install_tarpn_chat
        upgrade_linbpq
        patch_bpq_config
        patch_tarpn_scripts
    fi

    # Summary
    if [ "$DRY_RUN" = false ]; then
        print_summary
    else
        log_info ""
        log_info "[DRY-RUN] No changes were made"
    fi
}

# Run main
main "$@"
