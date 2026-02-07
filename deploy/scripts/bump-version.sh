#!/bin/bash
#
# bump-version.sh - Update version strings, commit, and tag
#
# Updates these files:
#   - tarpn-terminal/package.json  ("version": "X.Y.Z")
#   - tarpn-chat/Cargo.toml        (version = "X.Y.Z")
#
# Then commits the changes and creates a git tag.
#
# tarpn-mon and sendroutesviacq get their version from the git tag
# at build time via -ldflags, so no file edits are needed for those.
# tarpn-chat reads CARGO_PKG_VERSION at compile time for CLI and protocol.
#
# Usage:
#   ./bump-version.sh v1.3.5
#   ./bump-version.sh v1.3.5 --no-tag    # Update files and commit, skip tag
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ -z "$1" ]; then
    echo -e "${RED}Usage: $0 <version> [--no-tag]${NC}"
    echo ""
    echo "  version   Version string (e.g., v1.3.5)"
    echo "  --no-tag  Update files and commit, but don't create git tag"
    echo ""
    echo "Current versions:"
    echo "  git tag:      $(git -C "$PROJECT_ROOT" describe --tags --abbrev=0 2>/dev/null || echo 'none')"
    grep -m1 '"version"' "$PROJECT_ROOT/tarpn-terminal/package.json" | sed 's/.*: *"//;s/".*//' | xargs -I{} echo "  package.json: {}"
    grep -m1 '^version' "$PROJECT_ROOT/tarpn-chat/Cargo.toml" | sed 's/.*= *"//;s/".*//' | xargs -I{} echo "  Cargo.toml:   {}"
    exit 1
fi

VERSION="$1"
NO_TAG=false
if [ "$2" = "--no-tag" ]; then
    NO_TAG=true
fi

# Strip leading 'v' for file versions (files use X.Y.Z, git tag uses vX.Y.Z)
if [[ "$VERSION" == v* ]]; then
    TAG_VERSION="$VERSION"
    FILE_VERSION="${VERSION#v}"
else
    TAG_VERSION="v$VERSION"
    FILE_VERSION="$VERSION"
fi

# Validate version format
if ! [[ "$FILE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}Error: Invalid version format '$FILE_VERSION'. Expected X.Y.Z${NC}"
    exit 1
fi

# Check for uncommitted changes (other than what we're about to modify)
cd "$PROJECT_ROOT"
if ! git diff --quiet HEAD -- ':!tarpn-terminal/package.json' ':!tarpn-chat/Cargo.toml'; then
    echo -e "${RED}Error: You have uncommitted changes. Commit or stash them first.${NC}"
    git status --short
    exit 1
fi

echo "Bumping version to $TAG_VERSION ($FILE_VERSION in files)"
echo ""

# Step 1: Update files
PACKAGE_JSON="$PROJECT_ROOT/tarpn-terminal/package.json"
if [ -f "$PACKAGE_JSON" ]; then
    sed -i "s/\"version\": \"[^\"]*\"/\"version\": \"$FILE_VERSION\"/" "$PACKAGE_JSON"
    echo -e "${GREEN}Updated${NC} tarpn-terminal/package.json -> $FILE_VERSION"
else
    echo -e "${YELLOW}Skipped${NC} tarpn-terminal/package.json (not found)"
fi

CARGO_TOML="$PROJECT_ROOT/tarpn-chat/Cargo.toml"
if [ -f "$CARGO_TOML" ]; then
    sed -i "s/^version = \"[^\"]*\"/version = \"$FILE_VERSION\"/" "$CARGO_TOML"
    echo -e "${GREEN}Updated${NC} tarpn-chat/Cargo.toml -> $FILE_VERSION"
else
    echo -e "${YELLOW}Skipped${NC} tarpn-chat/Cargo.toml (not found)"
fi

# Step 2: Commit
echo ""
git add tarpn-terminal/package.json tarpn-chat/Cargo.toml 2>/dev/null
git commit -m "Bump version to $TAG_VERSION"
echo -e "${GREEN}Committed${NC} version bump"

# Step 3: Tag
if [ "$NO_TAG" = false ]; then
    git tag "$TAG_VERSION"
    echo -e "${GREEN}Tagged${NC} $TAG_VERSION"
fi

echo ""
echo -e "${GREEN}Done!${NC} Version is now $TAG_VERSION"
echo ""
echo "Next steps:"
echo "  deploy/build-release.sh --version $TAG_VERSION"
