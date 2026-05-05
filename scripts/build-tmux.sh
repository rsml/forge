#!/usr/bin/env bash
set -euo pipefail

# Versions
LIBEVENT_VERSION="2.1.12-stable"
NCURSES_VERSION="6.5"
UTF8PROC_VERSION="2.9.0"
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

echo "==> Building utf8proc $UTF8PROC_VERSION"
if [[ ! -d "utf8proc-${UTF8PROC_VERSION}" ]]; then
    curl -LO "https://github.com/JuliaStrings/utf8proc/archive/refs/tags/v${UTF8PROC_VERSION}.tar.gz"
    tar xzf "v${UTF8PROC_VERSION}.tar.gz"
fi
cd "utf8proc-${UTF8PROC_VERSION}"
make clean 2>/dev/null || true
make -j"$(sysctl -n hw.ncpu)" libutf8proc.a
mkdir -p "$PREFIX/lib" "$PREFIX/include"
cp libutf8proc.a "$PREFIX/lib/"
cp utf8proc.h "$PREFIX/include/"
# Create pkg-config file so tmux's configure can find it
mkdir -p "$PREFIX/lib/pkgconfig"
cat > "$PREFIX/lib/pkgconfig/libutf8proc.pc" <<PKGEOF
prefix=$PREFIX
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: libutf8proc
Description: UTF-8 processing library
Version: $UTF8PROC_VERSION
Libs: -L\${libdir} -lutf8proc
Cflags: -I\${includedir}
PKGEOF
cd "$BUILD_DIR"

echo "==> Building tmux $TMUX_VERSION"
if [[ ! -d "tmux-${TMUX_VERSION}" ]]; then
    curl -LO "https://github.com/tmux/tmux/releases/download/${TMUX_VERSION}/tmux-${TMUX_VERSION}.tar.gz"
    tar xzf "tmux-${TMUX_VERSION}.tar.gz"
fi
cd "tmux-${TMUX_VERSION}"
# Force static linking by passing .a files directly via LIBS
PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" \
CFLAGS="-I$PREFIX/include -I$PREFIX/include/ncursesw" \
LDFLAGS="-L$PREFIX/lib" \
LIBS="$PREFIX/lib/libncursesw.a $PREFIX/lib/libevent.a $PREFIX/lib/libevent_pthreads.a $PREFIX/lib/libutf8proc.a" \
./configure --prefix="$PREFIX" --enable-utf8proc
make -j"$(sysctl -n hw.ncpu)"

cp tmux "$OUTPUT"
echo "==> tmux binary built at $OUTPUT"
