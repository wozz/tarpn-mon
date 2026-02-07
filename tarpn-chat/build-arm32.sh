#!/bin/bash
#
# build-arm32.sh - Cross-compile tarpn-chat for Raspberry Pi (32-bit ARM)
#
# Uses musl libc for a fully static binary that works on any glibc version.
#
# Prerequisites:
#   - Rust toolchain (rustup)
#   - musl cross-compiler: sudo apt install musl-tools
#   - For ARM: Install musl-cross-make or use cross
#
# Usage:
#   ./build-arm32.sh           # Build release binary
#   ./build-arm32.sh --debug   # Build debug binary
#   ./build-arm32.sh --cross   # Use 'cross' tool (recommended)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TARGET="armv7-unknown-linux-musleabihf"
PROFILE="release"
USE_CROSS=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --debug)
            PROFILE="debug"
            shift
            ;;
        --cross)
            USE_CROSS=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [ "$USE_CROSS" = true ]; then
    # Use 'cross' tool - easiest method, uses Docker
    if ! command -v cross &> /dev/null; then
        log_info "Installing 'cross' tool..."
        cargo install cross --git https://github.com/cross-rs/cross
    fi

    # Clean any cached build artifacts that might be incompatible
    # This prevents glibc version mismatches between host and container
    log_info "Cleaning cached build artifacts..."
    rm -rf "target/$TARGET" "target/release/build" "target/debug/build" 2>/dev/null || true

    log_info "Building tarpn-chat for $TARGET using cross ($PROFILE)..."

    if [ "$PROFILE" = "release" ]; then
        cross build --target "$TARGET" --release
        BINARY_PATH="target/$TARGET/release/tarpn-chat"
    else
        cross build --target "$TARGET"
        BINARY_PATH="target/$TARGET/debug/tarpn-chat"
    fi
else
    # Direct compilation - requires musl cross toolchain

    # Check for Rust target
    if ! rustup target list --installed | grep -q "$TARGET"; then
        log_info "Installing Rust target: $TARGET"
        rustup target add "$TARGET"
    fi

    # Check for musl cross-compiler
    MUSL_GCC="arm-linux-musleabihf-gcc"
    if ! command -v "$MUSL_GCC" &> /dev/null; then
        log_warn "musl cross-compiler ($MUSL_GCC) not found."
        log_info "Trying with 'cross' tool instead (requires Docker)..."
        echo ""
        exec "$0" --cross ${PROFILE:+--$PROFILE}
    fi

    # Create/update .cargo/config.toml for cross-compilation
    mkdir -p .cargo
    cat > .cargo/config.toml << EOF
[target.armv7-unknown-linux-musleabihf]
linker = "$MUSL_GCC"
EOF

    log_info "Building tarpn-chat for $TARGET ($PROFILE)..."

    if [ "$PROFILE" = "release" ]; then
        cargo build --target "$TARGET" --release
        BINARY_PATH="target/$TARGET/release/tarpn-chat"
    else
        cargo build --target "$TARGET"
        BINARY_PATH="target/$TARGET/debug/tarpn-chat"
    fi
fi

# Copy to dist directory for easy access
mkdir -p dist
cp "$BINARY_PATH" "dist/tarpn-chat-arm32"

# Show result
BINARY_SIZE=$(du -h "dist/tarpn-chat-arm32" | cut -f1)
log_info "Build complete!"
echo ""
echo "Binary: dist/tarpn-chat-arm32 ($BINARY_SIZE)"
echo ""

# Verify it's statically linked
if command -v file &> /dev/null; then
    FILE_INFO=$(file "dist/tarpn-chat-arm32")
    if echo "$FILE_INFO" | grep -q "statically linked"; then
        log_info "Binary is statically linked (no glibc dependency)"
    else
        log_warn "Binary may have dynamic dependencies"
        echo "$FILE_INFO"
    fi
fi

echo ""
echo "To deploy with Ansible:"
echo "  cd ansible && ansible-playbook -i inventory.yml deploy.yml"
echo ""
