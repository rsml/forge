#!/usr/bin/env bash
set -euo pipefail

# Versions
LIBEVENT_VERSION="2.1.12-stable"
NCURSES_VERSION="6.4"
TMUX_VERSION="3.5"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.tmux-build"
PREFIX="$BUILD_DIR/install"
OUTPUT="$PROJECT_DIR/Resources/tmux"

# Skip if already built
if [[ -f "$OUTPUT" ]]; then
    echo "tmux binary already exists at $OUTPUT"
    exit 0
fi

mkdir -p "$BUILD_DIR" "$PREFIX" "$(dirname "$OUTPUT")"
cd "$BUILD_DIR"

echo "==> Building libevent $LIBEVENT_VERSION"
if [[ ! -d "libevent-${LIBEVENT_VERSION}" ]]; then
    curl -LO "https://github.com/libevent/libevent/releases/download/release-${LIBEVENT_VERSION}/libevent-${LIBEVENT_VERSION}.tar.gz"
    tar xzf "libevent-${LIBEVENT_VERSION}.tar.gz"
fi
cd "libevent-${LIBEVENT_VERSION}"
./configure --prefix="$PREFIX" --disable-shared --enable-static --disable-openssl
make -j"$(sysctl -n hw.ncpu)"
make install
cd "$BUILD_DIR"

echo "==> Building ncurses $NCURSES_VERSION"
if [[ ! -d "ncurses-${NCURSES_VERSION}" ]]; then
    curl -LO "https://ftp.gnu.org/gnu/ncurses/ncurses-${NCURSES_VERSION}.tar.gz"
    tar xzf "ncurses-${NCURSES_VERSION}.tar.gz"
fi
cd "ncurses-${NCURSES_VERSION}"
./configure --prefix="$PREFIX" --without-shared --with-normal --without-debug --without-cxx-binding --enable-widec
make -j"$(sysctl -n hw.ncpu)"
make install
cd "$BUILD_DIR"

echo "==> Building tmux $TMUX_VERSION"
if [[ ! -d "tmux-${TMUX_VERSION}" ]]; then
    curl -LO "https://github.com/tmux/tmux/releases/download/${TMUX_VERSION}/tmux-${TMUX_VERSION}.tar.gz"
    tar xzf "tmux-${TMUX_VERSION}.tar.gz"
fi
cd "tmux-${TMUX_VERSION}"
PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" \
CFLAGS="-I$PREFIX/include -I$PREFIX/include/ncursesw" \
LDFLAGS="-L$PREFIX/lib" \
LIBS="-lncursesw" \
./configure --prefix="$PREFIX" --enable-static
make -j"$(sysctl -n hw.ncpu)"

cp tmux "$OUTPUT"
echo "==> tmux binary built at $OUTPUT"
