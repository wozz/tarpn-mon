#!/bin/bash
#
# build-release.sh - Build binaries and upload release to S3
#
# This script:
# 1. Builds tarpn-mon (Go) for target architecture
# 2. Builds tarpn-chat (Rust) for target architecture
# 3. Packages deploy scripts
# 4. Uploads everything to S3
#
# Prerequisites:
# - Go installed (for tarpn-mon)
# - Rust + cross installed (for tarpn-chat)
# - AWS CLI configured with credentials
#
# Usage:
#   ./build-release.sh                    # Build for arm32 (default)
#   ./build-release.sh --arch arm64       # Build for arm64
#   ./build-release.sh --version v1.0.0   # Specify version tag
#   ./build-release.sh --dry-run          # Don't upload, just build
#

set -e

# =============================================================================
# Configuration
# =============================================================================

# Default values
TARGET_ARCH="arm32"
VERSION=""
DRY_RUN=false

# Source AWS credentials if available
if [ -f ~/.aws_creds ]; then
    source ~/.aws_creds
    export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
fi

# Source Rust/Cargo environment if available
if [ -f ~/.cargo/env ]; then
    source ~/.cargo/env
fi

S3_BUCKET="${TARPN_S3_BUCKET:-${AWS_BUCKET:-tarpn-terminal}}"
S3_REGION="${AWS_DEFAULT_REGION:-${AWS_BUCKET_REGION:-us-east-1}}"

# Project directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TARPN_MON_DIR="$PROJECT_ROOT"
TARPN_CHAT_DIR="$PROJECT_ROOT/tarpn-chat"
TARPN_TERMINAL_DIR="$PROJECT_ROOT/tarpn-terminal"
SENDROUTESVIACQ_DIR="$PROJECT_ROOT/sendroutesviacq"

# Build output directory
BUILD_DIR="$PROJECT_ROOT/dist"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

# =============================================================================
# Parse arguments
# =============================================================================

print_usage() {
    cat << EOF
Build and deploy TARPN Enhanced releases

Usage: $0 [options]

Options:
  --arch ARCH       Target architecture: arm32, arm64, amd64 (default: arm32)
  --version VER     Version tag (default: git describe or 'dev')
  --bucket BUCKET   S3 bucket name (default: \$TARPN_S3_BUCKET or 'tarpn-releases')
  --no-latest       Upload the version directory but do not update latest/
                    (use for prerelease or branch builds - nothing installing
                    from latest/ is affected)
  --dry-run         Build only, don't upload to S3
  --skip-mon        Skip building tarpn-mon
  --skip-chat       Skip building tarpn-chat
  --help            Show this help

Environment variables:
  TARPN_S3_BUCKET   S3 bucket name
  AWS_ACCESS_KEY_ID AWS credentials
  AWS_SECRET_ACCESS_KEY AWS credentials
  AWS_DEFAULT_REGION AWS region (default: us-east-1)

Notes:
  Frontend is embedded in tarpn-mon binary via go:embed.
  Makefile handles incremental frontend builds automatically.

Examples:
  # Build for Raspberry Pi and upload
  ./build-release.sh --version v1.0.0

  # Build for testing without upload
  ./build-release.sh --dry-run

  # Build only tarpn-mon
  ./build-release.sh --skip-chat

EOF
}

BUILD_MON=true
BUILD_CHAT=true
UPDATE_LATEST=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --arch)
            TARGET_ARCH="$2"
            shift 2
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --bucket)
            S3_BUCKET="$2"
            shift 2
            ;;
        --no-latest)
            UPDATE_LATEST=false
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-mon)
            BUILD_MON=false
            shift
            ;;
        --skip-chat)
            BUILD_CHAT=false
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
# Determine build targets
# =============================================================================

case "$TARGET_ARCH" in
    arm32|armv7|armhf)
        TARGET_ARCH="arm32"
        GO_ARCH="arm"
        GO_ARM="7"
        RUST_TARGET="armv7-unknown-linux-musleabihf"
        ;;
    arm64|aarch64)
        TARGET_ARCH="arm64"
        GO_ARCH="arm64"
        GO_ARM=""
        RUST_TARGET="aarch64-unknown-linux-musl"
        ;;
    amd64|x86_64)
        TARGET_ARCH="amd64"
        GO_ARCH="amd64"
        GO_ARM=""
        RUST_TARGET="x86_64-unknown-linux-musl"
        ;;
    *)
        log_error "Unsupported architecture: $TARGET_ARCH"
        log_error "Supported: arm32, arm64, amd64"
        exit 1
        ;;
esac

# Determine version
if [ -z "$VERSION" ]; then
    if git describe --tags --exact-match 2>/dev/null; then
        VERSION=$(git describe --tags --exact-match)
    elif git describe --tags 2>/dev/null; then
        VERSION=$(git describe --tags)
    else
        VERSION="dev-$(date +%Y%m%d-%H%M%S)"
    fi
fi

log_info "Build configuration:"
log_info "  Target arch: $TARGET_ARCH"
log_info "  Version:     $VERSION"
log_info "  S3 bucket:   $S3_BUCKET"
log_info "  Dry run:     $DRY_RUN"
echo ""

# =============================================================================
# Pre-flight checks
# =============================================================================

log_step "Running pre-flight checks..."

# Check Go
if [ "$BUILD_MON" = true ]; then
    if ! command -v go &>/dev/null; then
        log_error "Go is not installed. Please install Go first."
        exit 1
    fi
    log_info "Go version: $(go version)"
fi

# Check Rust/cross for tarpn-chat
if [ "$BUILD_CHAT" = true ]; then
    if command -v cross &>/dev/null; then
        RUST_BUILD_CMD="cross"
        log_info "Using 'cross' for Rust cross-compilation"
    elif command -v cargo &>/dev/null; then
        RUST_BUILD_CMD="cargo"
        log_warn "Using 'cargo' directly - cross-compilation may fail without proper toolchain"
    else
        log_error "Neither 'cross' nor 'cargo' found. Please install Rust."
        exit 1
    fi
fi

# Check AWS CLI (unless dry run)
if [ "$DRY_RUN" = false ]; then
    if ! command -v aws &>/dev/null; then
        log_error "AWS CLI is not installed. Please install it or use --dry-run."
        exit 1
    fi

    # Check AWS credentials
    if [ -z "$AWS_ACCESS_KEY_ID" ] && [ ! -f ~/.aws/credentials ]; then
        log_error "AWS credentials not found. Set AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY or configure ~/.aws/credentials"
        exit 1
    fi
fi

# Check npm/npx for frontend (Makefile needs these)
if [ "$BUILD_MON" = true ]; then
    if ! command -v npm &>/dev/null; then
        log_error "npm not found. Please install Node.js."
        exit 1
    fi
    if ! command -v npx &>/dev/null; then
        log_error "npx not found. Please install Node.js."
        exit 1
    fi
    log_info "Node.js: $(node --version 2>/dev/null || echo 'unknown')"
fi

# Create build directory
mkdir -p "$BUILD_DIR"

# =============================================================================
# Build tarpn-mon (Go)
# =============================================================================

build_tarpn_mon() {
    log_step "Building tarpn-mon for $TARGET_ARCH..."

    cd "$TARPN_MON_DIR"

    # Use Makefile for incremental builds (handles frontend + Go compilation)
    local make_target="build-${TARGET_ARCH}"
    log_info "Running: make VERSION=$VERSION $make_target"

    make VERSION="$VERSION" "$make_target"

    local output_name="tarpn-mon.linux-${TARGET_ARCH}"

    # Check binary was created (Makefile puts it in dist/)
    if [ -f "$BUILD_DIR/$output_name" ]; then
        log_info "Built: $BUILD_DIR/$output_name ($(du -h "$BUILD_DIR/$output_name" | cut -f1))"
    else
        log_error "Build failed - binary not created"
        exit 1
    fi
}

# =============================================================================
# Build tarpn-chat (Rust)
# =============================================================================

build_tarpn_chat() {
    log_step "Building tarpn-chat for $TARGET_ARCH..."

    if [ ! -d "$TARPN_CHAT_DIR" ]; then
        log_error "tarpn-chat directory not found: $TARPN_CHAT_DIR"
        exit 1
    fi

    cd "$TARPN_CHAT_DIR"

    local output_name="tarpn-chat-${TARGET_ARCH}"

    log_info "Compiling Rust binary with $RUST_BUILD_CMD..."
    $RUST_BUILD_CMD build --release --target "$RUST_TARGET"

    # Copy to dist
    local rust_binary="target/${RUST_TARGET}/release/tarpn-chat"
    if [ -f "$rust_binary" ]; then
        cp "$rust_binary" "$BUILD_DIR/$output_name"
        log_info "Built: $BUILD_DIR/$output_name ($(du -h "$BUILD_DIR/$output_name" | cut -f1))"
    else
        log_error "Build failed - binary not created at $rust_binary"
        exit 1
    fi
}

# =============================================================================
# Build send-routes-via-cq (Go, separate module)
# =============================================================================

build_sendroutesviacq() {
    log_step "Building send-routes-via-cq for $TARGET_ARCH..."

    cd "$PROJECT_ROOT"

    # Run tests first
    log_info "Running send-routes-via-cq tests..."
    make test-sendroutesviacq

    # Build using Makefile (same cross-compile approach as tarpn-mon)
    local make_target="build-sendroutesviacq-${TARGET_ARCH}"
    log_info "Running: make $make_target"
    make "$make_target"

    local output_name="send-routes-via-cq.linux-${TARGET_ARCH}"
    if [ -f "$BUILD_DIR/$output_name" ]; then
        log_info "Built: $BUILD_DIR/$output_name ($(du -h "$BUILD_DIR/$output_name" | cut -f1))"
    else
        log_error "Build failed - binary not created"
        exit 1
    fi
}

build_linktest() {
    log_step "Building linktest for $TARGET_ARCH..."

    cd "$PROJECT_ROOT"

    local make_target="build-linktest-${TARGET_ARCH}"
    log_info "Running: make $make_target"
    make "$make_target"

    local output_name="linktest.linux-${TARGET_ARCH}"
    if [ -f "$BUILD_DIR/$output_name" ]; then
        log_info "Built: $BUILD_DIR/$output_name ($(du -h "$BUILD_DIR/$output_name" | cut -f1))"
    else
        log_error "Build failed - binary not created"
        exit 1
    fi
}

# =============================================================================
# Package deploy scripts
# =============================================================================

package_scripts() {
    log_step "Packaging deploy scripts..."

    local scripts_dir="$BUILD_DIR/scripts"
    mkdir -p "$scripts_dir"

    # Copy install script
    cp "$SCRIPT_DIR/install.sh" "$scripts_dir/"

    # Copy supporting scripts
    cp "$SCRIPT_DIR/scripts/patch-bpq32-config.sh" "$scripts_dir/"

    # Copy config examples
    mkdir -p "$scripts_dir/config"
    cp "$SCRIPT_DIR/config/"*.example "$scripts_dir/config/" 2>/dev/null || true

    # Copy README
    cp "$SCRIPT_DIR/README.md" "$scripts_dir/" 2>/dev/null || true

    log_info "Packaged scripts to: $scripts_dir/"
}

# =============================================================================
# Create version manifest
# =============================================================================

# sha256 of a file, or "n/a" if it is not there. Written as a function because
# `sha256sum f | cut ... || echo n/a` never fires the fallback - cut succeeds
# regardless - and silently emits an empty checksum.
file_checksum() {
    [ -f "$1" ] || { echo "n/a"; return 0; }
    sha256sum "$1" 2>/dev/null | cut -d' ' -f1
}

create_manifest() {
    log_step "Creating version manifest..."

    local manifest="$BUILD_DIR/manifest.json"

    cat > "$manifest" << EOF
{
    "version": "$VERSION",
    "build_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "architecture": "$TARGET_ARCH",
    "files": {
        "tarpn_mon": "tarpn-mon.linux-${TARGET_ARCH}",
        "tarpn_chat": "tarpn-chat.linux-${TARGET_ARCH}",
        "send_routes_via_cq": "send-routes-via-cq.linux-${TARGET_ARCH}",
        "linktest": "linktest.linux-${TARGET_ARCH}",
        "install_script": "scripts/install.sh"
    },
    "checksums": {
        "tarpn_mon": "$(file_checksum "$BUILD_DIR/tarpn-mon.linux-${TARGET_ARCH}")",
        "tarpn_chat": "$(file_checksum "$BUILD_DIR/tarpn-chat-${TARGET_ARCH}")",
        "send_routes_via_cq": "$(file_checksum "$BUILD_DIR/send-routes-via-cq.linux-${TARGET_ARCH}")",
        "linktest": "$(file_checksum "$BUILD_DIR/linktest.linux-${TARGET_ARCH}")"
    }
}
EOF

    log_info "Created manifest: $manifest"
    cat "$manifest"
}

# =============================================================================
# Upload to S3
# =============================================================================

upload_to_s3() {
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would upload to s3://$S3_BUCKET/$VERSION/"
        return 0
    fi

    log_step "Uploading to S3..."

    local s3_path="s3://$S3_BUCKET/$VERSION"

    # Upload binaries
    if [ -f "$BUILD_DIR/tarpn-mon.linux-${TARGET_ARCH}" ]; then
        log_info "Uploading tarpn-mon..."
        aws s3 cp "$BUILD_DIR/tarpn-mon.linux-${TARGET_ARCH}" "$s3_path/tarpn-mon.linux-${TARGET_ARCH}"
    fi

    if [ -f "$BUILD_DIR/tarpn-chat-${TARGET_ARCH}" ]; then
        log_info "Uploading tarpn-chat..."
        # Canonical name, matching every other component: <name>.linux-<arch>.
        aws s3 cp "$BUILD_DIR/tarpn-chat-${TARGET_ARCH}" "$s3_path/tarpn-chat.linux-${TARGET_ARCH}"
        # Legacy name, kept so the older deploy/install.sh keeps working
        # against this bucket. Drop once nothing installs with that script.
        aws s3 cp "$BUILD_DIR/tarpn-chat-${TARGET_ARCH}" "$s3_path/tarpn-chat-${TARGET_ARCH}"
    fi

    if [ -f "$BUILD_DIR/send-routes-via-cq.linux-${TARGET_ARCH}" ]; then
        log_info "Uploading send-routes-via-cq..."
        aws s3 cp "$BUILD_DIR/send-routes-via-cq.linux-${TARGET_ARCH}" "$s3_path/send-routes-via-cq.linux-${TARGET_ARCH}"
    fi

    if [ -f "$BUILD_DIR/linktest.linux-${TARGET_ARCH}" ]; then
        log_info "Uploading linktest..."
        aws s3 cp "$BUILD_DIR/linktest.linux-${TARGET_ARCH}" "$s3_path/linktest.linux-${TARGET_ARCH}"
    fi

    # Upload scripts
    log_info "Uploading scripts..."
    aws s3 cp "$BUILD_DIR/scripts/" "$s3_path/scripts/" --recursive

    # Upload manifest
    if [ -f "$BUILD_DIR/manifest.json" ]; then
        log_info "Uploading manifest..."
        aws s3 cp "$BUILD_DIR/manifest.json" "$s3_path/manifest.json" \
            --content-type "application/json"
    fi

    # Also upload to 'latest' path for easy access.
    #
    # NO --delete here. This script builds one architecture per run, so
    # $s3_path holds only that architecture's artifacts. Syncing it to latest/
    # with --delete removes every other architecture's binaries - which are
    # what already-deployed nodes install from. Publishing arm64 would have
    # silently deleted the arm32 binaries out from under every existing node.
    #
    # The cost of omitting it is that a renamed artifact lingers in latest/
    # until removed by hand. That is much cheaper than the alternative.
    if [ "$UPDATE_LATEST" = false ]; then
        log_warn "Skipping the 'latest' pointer (--no-latest)"
        log_info "Install from this build with, in /etc/tarpn/tarpn.conf:"
        log_info "  RELEASE_VERSION=$VERSION"
    else
        log_info "Updating 'latest' pointer..."
        aws s3 sync "$s3_path/" "s3://$S3_BUCKET/latest/"
    fi

    log_info "Upload complete!"
    log_info ""
    log_info "Release URLs:"
    log_info "  Versioned: https://$S3_BUCKET.s3.$S3_REGION.amazonaws.com/$VERSION/"
    log_info "  Latest:    https://$S3_BUCKET.s3.$S3_REGION.amazonaws.com/latest/"
    log_info ""
    log_info "Install command:"
    log_info "  curl -sSL https://$S3_BUCKET.s3.$S3_REGION.amazonaws.com/latest/scripts/install.sh | sudo bash"
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo ""
    echo "=============================================="
    echo "  TARPN Enhanced Build & Release"
    echo "=============================================="
    echo ""

    # Build components
    if [ "$BUILD_MON" = true ]; then
        build_tarpn_mon
        build_sendroutesviacq
        build_linktest
    fi

    if [ "$BUILD_CHAT" = true ]; then
        build_tarpn_chat
    fi

    # Package scripts
    package_scripts

    # Create manifest
    create_manifest

    # Upload
    upload_to_s3

    echo ""
    log_info "Build complete!"
    echo ""
    echo "Build artifacts in: $BUILD_DIR/"
    ls -la "$BUILD_DIR/"
}

main "$@"
