#!/bin/bash
#
# patch-bpq32-config.sh - Inject tarpn-chat configuration into bpq32.cfg
#
# This script is triggered by systemd when bpq32.cfg is modified.
# It configures LinBPQ to accept tarpn-chat as a NetROM node via NETROMPORT.
#
# Changes made:
#   1. Adds NETROMPORT to the TELNET CONFIG section
#   2. Adds a ROUTES entry for our chat node callsign
#   3. Creates/updates BPQNODES.dat with NODE ADD entry (for NODES broadcast)
#   4. Comments out built-in CHAT application (to avoid confusion)
#   5. Removes TARPN-HOME APPLICATION lines (HOME4, HOME5, HOME6)
#
# Users connect to tarpn-chat by: C CALL-9 (e.g., C WA2M-9)
#
# The script is idempotent - it won't modify an already-patched config.
#

set -e

CONFIG="/home/pi/bpq/bpq32.cfg"
MARKER=";;; TARPN-CHAT PATCHED"
LOGFILE="/var/log/tarpn-chat-patch.log"
LOCKFILE="/tmp/tarpn-chat-patch.lock"

# NetROM port that LinBPQ listens on (tarpn-chat connects to this)
NETROM_PORT=63119

# Chat node callsign (read from tarpn-chat config if available)
TARPN_CHAT_CALL=""
TARPN_CHAT_ALIAS=""
TARPN_CHAT_CONFIG="/opt/tarpn-chat/config.toml"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOGFILE"
}

# Prevent loop: if we're already running, exit
if [ -f "$LOCKFILE" ]; then
    # Check if lock is stale (older than 60 seconds)
    if [ $(($(date +%s) - $(stat -c %Y "$LOCKFILE"))) -lt 60 ]; then
        log "Lock file exists, skipping (probably triggered by our own edit)"
        exit 0
    fi
    rm -f "$LOCKFILE"
fi

# Create lock file
touch "$LOCKFILE"
trap "rm -f $LOCKFILE" EXIT

# Check if config exists
if [ ! -f "$CONFIG" ]; then
    log "ERROR: $CONFIG does not exist"
    exit 1
fi

# =============================================================================
# OARC API configuration (runs every time, independent of TARPN-CHAT marker)
# =============================================================================
# LinBPQ's OARC API sends structured JSON events via UDP to
# node-api.packet.oarc.uk:13579. We redirect that hostname to localhost
# via /etc/hosts so tarpn-mon receives them locally for session tracking.
# This must be re-checked on every bpq32.cfg change because TARPN's
# update scripts may regenerate the config and strip ENABLEOARCAPI.

OARC_HOST="node-api.packet.oarc.uk"
HOSTS_FILE="/etc/hosts"

# Ensure /etc/hosts redirect is in place
if ! grep -q "$OARC_HOST" "$HOSTS_FILE" 2>/dev/null; then
    echo "127.0.0.1 $OARC_HOST" >> "$HOSTS_FILE"
    log "Added '127.0.0.1 $OARC_HOST' to $HOSTS_FILE"
fi

# Ensure ENABLEOARCAPI=1 is in bpq32.cfg
if ! grep -qi "ENABLEOARCAPI" "$CONFIG"; then
    if grep -qi "^NODECALL=" "$CONFIG"; then
        sed -i '/^NODECALL=/a ENABLEOARCAPI=1' "$CONFIG"
    else
        sed -i '1i ENABLEOARCAPI=1' "$CONFIG"
    fi
    log "Added ENABLEOARCAPI=1 to $CONFIG"
fi

# Check if already patched (tarpn-chat specific changes below)
if grep -q "$MARKER" "$CONFIG"; then
    log "Config already patched, skipping"
    exit 0
fi

# Read chat node info from tarpn-chat config
if [ -f "$TARPN_CHAT_CONFIG" ]; then
    TARPN_CHAT_CALL=$(grep "^call" "$TARPN_CHAT_CONFIG" 2>/dev/null | head -1 | cut -d'"' -f2)
    TARPN_CHAT_ALIAS=$(grep "^alias" "$TARPN_CHAT_CONFIG" 2>/dev/null | head -1 | cut -d'"' -f2)
    log "Read chat config: call=$TARPN_CHAT_CALL, alias=$TARPN_CHAT_ALIAS"
fi

# Fallback: derive from NODECALL in bpq32.cfg
if [ -z "$TARPN_CHAT_CALL" ]; then
    NODECALL=$(grep -i "^NODECALL=" "$CONFIG" 2>/dev/null | head -1 | sed -E 's/^[Nn][Oo][Dd][Ee][Cc][Aa][Ll][Ll]=([A-Za-z]{1,2}[0-9]{1,2}[A-Za-z]{1,3}(-[0-9]{1,2})?).*/\1/')
    if [ -n "$NODECALL" ]; then
        BASE_CALL=$(echo "$NODECALL" | cut -d'-' -f1 | tr '[:lower:]' '[:upper:]')
        TARPN_CHAT_CALL="${BASE_CALL}-9"
        # Generate alias: Y + chars 2,3,4 + 09
        MIDDLE=$(echo "$BASE_CALL" | cut -c2-4)
        TARPN_CHAT_ALIAS="Y${MIDDLE}09"
        log "Derived chat config from NODECALL: call=$TARPN_CHAT_CALL, alias=$TARPN_CHAT_ALIAS"
    else
        log "ERROR: Could not determine chat callsign"
        exit 1
    fi
fi

log "Patching $CONFIG for tarpn-chat (NetROM mode)..."
log "Chat node: $TARPN_CHAT_CALL ($TARPN_CHAT_ALIAS)"

# Create backup
cp "$CONFIG" "${CONFIG}.pre-tarpn-chat.bak"

# =============================================================================
# Step 1: Add NETROMPORT to TELNET CONFIG section
# =============================================================================
# The TELNET port CONFIG section needs NETROMPORT=63119 so tarpn-chat can connect
#
# We look for the TELNET port section and add NETROMPORT after HTTPPORT or FBBPORT

if grep -q "^NETROMPORT=" "$CONFIG"; then
    log "NETROMPORT already configured"
else
    # Find a good place to insert NETROMPORT in the TELNET CONFIG
    # Look for HTTPPORT or FBBPORT lines and insert after
    if grep -q "^HTTPPORT=" "$CONFIG"; then
        sed -i "/^HTTPPORT=/a NETROMPORT=${NETROM_PORT}" "$CONFIG"
        log "Added NETROMPORT=${NETROM_PORT} after HTTPPORT"
    elif grep -q "^FBBPORT=" "$CONFIG"; then
        sed -i "/^FBBPORT=/a NETROMPORT=${NETROM_PORT}" "$CONFIG"
        log "Added NETROMPORT=${NETROM_PORT} after FBBPORT"
    elif grep -q "^TCPPORT=" "$CONFIG"; then
        sed -i "/^TCPPORT=/a NETROMPORT=${NETROM_PORT}" "$CONFIG"
        log "Added NETROMPORT=${NETROM_PORT} after TCPPORT"
    else
        log "WARNING: Could not find TELNET CONFIG section to add NETROMPORT"
        log "         You may need to manually add NETROMPORT=${NETROM_PORT} to the TELNET CONFIG"
    fi
fi

# =============================================================================
# Step 2: Add ROUTES entry for our chat node
# =============================================================================
# Format: CALL=callsign,QUALITY=n,PORT=32,TCP=0.0.0.0:port
# This advertises our chat callsign as routable via the NETROMPORT

ROUTES_ENTRY="CALL=${TARPN_CHAT_CALL},QUALITY=200,PORT=32,TCP=0.0.0.0:${NETROM_PORT}"

# Check if ROUTES section exists
if grep -q "^ROUTES:" "$CONFIG"; then
    # Check if our entry already exists
    if ! grep -q "CALL=${TARPN_CHAT_CALL}" "$CONFIG"; then
        # Add our entry after ROUTES: line
        sed -i "/^ROUTES:/a ${ROUTES_ENTRY}  ;;; tarpn-chat" "$CONFIG"
        log "Added ROUTES entry: $ROUTES_ENTRY"
    else
        log "ROUTES entry already exists for $TARPN_CHAT_CALL"
    fi
else
    # No ROUTES section - add one at end of file
    log "WARNING: No ROUTES: section found, adding one"
    echo "" >> "$CONFIG"
    echo "ROUTES:" >> "$CONFIG"
    echo "${ROUTES_ENTRY}  ;;; tarpn-chat" >> "$CONFIG"
fi

# =============================================================================
# Step 3: Add NODE entry to BPQNODES.dat (for NODES broadcast advertisement)
# =============================================================================
# The ROUTES entry allows connections, but BPQNODES.dat creates the DEST entry
# that gets advertised in NODES broadcasts so other nodes can route to us.
# Format: NODE ADD ALIAS:CALL NEIGHBOUR PORT QUAL !
#   - ALIAS:CALL = how we appear in NODES table
#   - NEIGHBOUR = the neighbor call to route through (ourselves via NETROMPORT)
#   - PORT = telnet port number (32)
#   - QUAL = quality (200 = direct)
#   - ! = locked (persistent)

BPQ_DIR=$(dirname "$CONFIG")
BPQNODES_FILE="${BPQ_DIR}/BPQNODES.dat"
NODE_ENTRY="NODE ADD ${TARPN_CHAT_ALIAS}:${TARPN_CHAT_CALL} ${TARPN_CHAT_CALL} 32 200 !"

# Create or update BPQNODES.dat
if [ -f "$BPQNODES_FILE" ]; then
    # Check if our entry already exists
    if grep -q "NODE ADD.*${TARPN_CHAT_CALL}" "$BPQNODES_FILE"; then
        log "NODE ADD entry already exists in BPQNODES.dat"
    else
        # Append our entry
        echo "" >> "$BPQNODES_FILE"
        echo "; tarpn-chat node entry (added by patch script)" >> "$BPQNODES_FILE"
        echo "$NODE_ENTRY" >> "$BPQNODES_FILE"
        log "Added NODE entry to BPQNODES.dat: $NODE_ENTRY"
    fi
else
    # Create new BPQNODES.dat
    log "Creating new BPQNODES.dat"
    cat > "$BPQNODES_FILE" << EOF
; BPQNODES.dat - Saved/locked node entries
; Format: NODE ADD ALIAS:CALL NEIGHBOUR PORT QUAL [!]

; tarpn-chat node entry (added by patch script)
$NODE_ENTRY
EOF
    log "Created BPQNODES.dat with NODE entry: $NODE_ENTRY"
fi

# =============================================================================
# Step 4: Comment out built-in CHAT application (if present)
# =============================================================================
# The built-in CHAT is no longer needed since users connect directly to our
# chat node callsign. We comment it out to avoid confusion.

OLD_CHAT_LINE=$(grep -i "^APPLICATION [0-9]*,CHAT,," "$CONFIG" || echo "")
if [ -n "$OLD_CHAT_LINE" ]; then
    APP_NUM=$(echo "$OLD_CHAT_LINE" | grep -oP '^APPLICATION \K[0-9]+')
    sed -i "s|^APPLICATION ${APP_NUM},CHAT,,|; DISABLED by tarpn-chat: APPLICATION ${APP_NUM},CHAT,,|" "$CONFIG"
    log "Commented out built-in CHAT application"
    log "  Users should connect with: C $TARPN_CHAT_CALL"
fi

# Also handle any CMDPORT-based CHAT from previous versions
CMDPORT_CHAT=$(grep -i "^APPLICATION [0-9]*,CHAT,C [0-9]* HOST" "$CONFIG" || echo "")
if [ -n "$CMDPORT_CHAT" ]; then
    APP_NUM=$(echo "$CMDPORT_CHAT" | grep -oP '^APPLICATION \K[0-9]+')
    sed -i "s|^APPLICATION ${APP_NUM},CHAT,C [0-9]* HOST|; DISABLED by tarpn-chat: APPLICATION ${APP_NUM},CHAT,C HOST|" "$CONFIG"
    log "Commented out CMDPORT-based CHAT application"
fi

# =============================================================================
# Step 5: Remove TARPN-HOME APPLICATION lines (HOME4, HOME5, HOME6)
# =============================================================================

for HOMENUM in 4 5 6; do
    if grep -q "^APPLICATION.*HOME${HOMENUM}" "$CONFIG"; then
        sed -i "/^APPLICATION.*HOME${HOMENUM}/d" "$CONFIG"
        log "Removed HOME${HOMENUM} APPLICATION line"
    fi
done

# =============================================================================
# Step 6: Add our marker comment
# =============================================================================
echo "" >> "$CONFIG"
echo "$MARKER $(date '+%Y-%m-%d %H:%M:%S')" >> "$CONFIG"
echo "; tarpn-chat ($TARPN_CHAT_CALL) connects via NETROMPORT=${NETROM_PORT}" >> "$CONFIG"
echo "; Users connect with: C $TARPN_CHAT_CALL" >> "$CONFIG"

log "Patch complete"

# =============================================================================
# Step 7: Handle LinBPQ restart
# =============================================================================
if pgrep -x "linbpq" > /dev/null; then
    log "LinBPQ is running - restart required to apply changes"

    if [ "${TARPN_CHAT_AUTO_RESTART:-1}" = "1" ]; then
        log "Auto-restart enabled, killing LinBPQ..."
        pkill -x linbpq || true
        sleep 2
        log "LinBPQ killed, TARPN monitoring should restart it with new config"
    else
        log "Auto-restart disabled. Kill linbpq manually to apply changes:"
        log "  sudo pkill linbpq  # TARPN will restart it automatically"
        echo "tarpn-chat: Config patched. Run 'sudo pkill linbpq' to apply (TARPN will restart it)"
    fi
else
    log "LinBPQ not running - changes will take effect on next start"
fi

# =============================================================================
# Summary
# =============================================================================
log "NOTE: tarpn-chat connects TO LinBPQ via NETROMPORT=${NETROM_PORT}"
log "      Users connect with: C $TARPN_CHAT_CALL"
