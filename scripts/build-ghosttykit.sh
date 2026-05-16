#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
GHOSTTY_DIR="$PROJECT_DIR/vendor/ghostty"
CACHE_ROOT="$HOME/.cache/forge/ghosttykit"

cd "$PROJECT_DIR"

# Check zig
if ! command -v zig &> /dev/null; then
    echo "Error: zig is not installed. Install via: brew install zig"
    exit 1
fi

# Check submodule
if [[ ! -f "$GHOSTTY_DIR/include/ghostty.h" ]]; then
    echo "Error: vendor/ghostty submodule not initialized."
    echo "Run: git submodule update --init vendor/ghostty"
    exit 1
fi

# Cache key from ghostty commit SHA
GHOSTTY_SHA="$(git -C "$GHOSTTY_DIR" rev-parse HEAD)"
CACHE_DIR="$CACHE_ROOT/$GHOSTTY_SHA"
CACHE_XCFW="$CACHE_DIR/GhosttyKit.xcframework"
LOCAL_XCFW="$PROJECT_DIR/GhosttyKit.xcframework"

if [[ -d "$CACHE_XCFW" ]]; then
    echo "==> Reusing cached GhosttyKit.xcframework (${GHOSTTY_SHA:0:8})"
else
    echo "==> Building GhosttyKit.xcframework (this takes a few minutes)..."
    (
        cd "$GHOSTTY_DIR"
        zig build -Demit-xcframework=true -Dxcframework-target=universal -Doptimize=ReleaseFast
    )

    BUILT="$GHOSTTY_DIR/macos/GhosttyKit.xcframework"
    if [[ ! -d "$BUILT" ]]; then
        echo "Error: GhosttyKit.xcframework not found at $BUILT"
        echo "Searching..."
        find "$GHOSTTY_DIR" -name "GhosttyKit.xcframework" -type d 2>/dev/null
        exit 1
    fi

    mkdir -p "$CACHE_DIR"
    cp -R "$BUILT" "$CACHE_XCFW"
    echo "==> Cached at $CACHE_XCFW"
fi

# Refresh ranlib index (required by Xcode 26+)
MACOS_ARCHIVE="$CACHE_XCFW/macos-arm64_x86_64/libghostty.a"
if [[ -f "$MACOS_ARCHIVE" ]]; then
    echo "==> Refreshing libghostty archive index..."
    xcrun ranlib "$MACOS_ARCHIVE" 2>/dev/null || true
fi

# Symlink into project root
ln -sfn "$CACHE_XCFW" "$LOCAL_XCFW"
echo "==> GhosttyKit.xcframework ready"
