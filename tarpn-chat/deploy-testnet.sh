#!/bin/bash
# Deploy tarpn-chat to the docker-testnet
#
# This script:
# 1. Builds the musl binary for x86_64
# 2. STOPS the containers that use tarpn-chat (file is mounted as volume)
# 3. Copies the binary to dist/ directory
# 4. STARTS the containers back up
#
# Usage: ./deploy-testnet.sh [--no-build] [--restart-all]

set -e

# Source cargo environment if available
if [ -f "$HOME/.cargo/env" ]; then
    source "$HOME/.cargo/env"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$SCRIPT_DIR/dist"
BINARY_NAME="tarpn-chat-x86_64-musl"
TARGET="x86_64-unknown-linux-musl"

# Containers that mount the tarpn-chat binary
CHAT_CONTAINERS="tarpn-node4 tarpn-node5"

# Parse arguments
NO_BUILD=false
RESTART_ALL=false
for arg in "$@"; do
    case $arg in
        --no-build)
            NO_BUILD=true
            ;;
        --restart-all)
            RESTART_ALL=true
            ;;
    esac
done

echo "=== tarpn-chat Testnet Deployment ==="
echo "Script dir: $SCRIPT_DIR"
echo "Dist dir: $DIST_DIR"
echo ""

# Step 1: Build the binary (unless --no-build)
if [ "$NO_BUILD" = false ]; then
    echo "Building $TARGET..."
    cd "$SCRIPT_DIR"
    cargo build --release --target "$TARGET"
    echo "Build complete."
else
    echo "Skipping build (--no-build)"
fi

# Step 2: STOP containers that use tarpn-chat (binary is volume-mounted)
echo ""
echo "Stopping containers that use tarpn-chat..."
for container in $CHAT_CONTAINERS; do
    if podman ps --format '{{.Names}}' | grep -q "^${container}$"; then
        echo "  Stopping $container..."
        podman stop "$container" >/dev/null 2>&1 || echo "    Warning: failed to stop $container"
    else
        echo "  Container $container not running, skipping stop"
    fi
done

# Step 3: Copy binary to dist/
echo ""
echo "Copying binary to dist/..."
mkdir -p "$DIST_DIR"
cp "$SCRIPT_DIR/target/$TARGET/release/tarpn-chat" "$DIST_DIR/$BINARY_NAME"
chmod +x "$DIST_DIR/$BINARY_NAME"
ls -la "$DIST_DIR/$BINARY_NAME"

# Step 4: START containers back up
echo ""
if [ "$RESTART_ALL" = true ]; then
    echo "Starting all tarpn containers..."
    CONTAINERS="tarpn-node1 tarpn-node2 tarpn-node3 tarpn-node4 tarpn-node5 tarpn-node6 tarpn-node7"
else
    echo "Starting tarpn-chat containers..."
    CONTAINERS="$CHAT_CONTAINERS"
fi

for container in $CONTAINERS; do
    if podman ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
        echo "  Starting $container..."
        podman start "$container" >/dev/null 2>&1 || echo "    Warning: failed to start $container"
    else
        echo "  Container $container not found, skipping"
    fi
done

echo ""
echo "=== Deployment complete ==="
echo ""
echo "Check logs with:"
echo "  podman logs -f tarpn-node4"
echo "  podman logs -f tarpn-node5"
