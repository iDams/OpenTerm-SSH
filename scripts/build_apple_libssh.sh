#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."

LIBSSH_VERSION="${OPENTERM_LIBSSH_VERSION:-0.11.3}"
LIBSSH_ARCHIVE="${OPENTERM_LIBSSH_ARCHIVE:-$REPO_DIR/vendor/sources/libssh/libssh-$LIBSSH_VERSION.tar.xz}"
LIBSSH_ARCHIVE_ALT="${OPENTERM_LIBSSH_ARCHIVE_ALT:-$REPO_DIR/vendor/sources/libssh/libssh-$LIBSSH_VERSION.tar.gz}"
LIBSSH_SOURCE_DIR="${OPENTERM_LIBSSH_SOURCE_DIR:-$REPO_DIR/vendor/sources/libssh/libssh-$LIBSSH_VERSION}"
OPENSSL_VERSION="${OPENTERM_OPENSSL_VERSION:-3.6.1}"
APPLE_OPENSSL_DIR="${OPENTERM_APPLE_OPENSSL_DIR:-$REPO_DIR/vendor/apple/openssl/$OPENSSL_VERSION}"
APPLE_LIBSSH_DIR="$REPO_DIR/vendor/apple/libssh/$LIBSSH_VERSION"
BUILD_ROOT="$REPO_DIR/vendor/apple/build/libssh-$LIBSSH_VERSION"

ARCHS=("arm64")
CMAKE_BIN="$(command -v cmake)"

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "❌ Missing required command: $1" >&2
        exit 1
    fi
}

extract_source_if_needed() {
    if [[ -d "$LIBSSH_SOURCE_DIR" ]]; then
        return
    fi

    local archive=""
    if [[ -f "$LIBSSH_ARCHIVE" ]]; then
        archive="$LIBSSH_ARCHIVE"
    elif [[ -f "$LIBSSH_ARCHIVE_ALT" ]]; then
        archive="$LIBSSH_ARCHIVE_ALT"
    fi

    if [[ -z "$archive" ]]; then
        echo "❌ libssh source not found." >&2
        echo "   Expected either:" >&2
        echo "   - source directory: $LIBSSH_SOURCE_DIR" >&2
        echo "   - source archive:   $LIBSSH_ARCHIVE" >&2
        echo "   - source archive:   $LIBSSH_ARCHIVE_ALT" >&2
        echo "   Set OPENTERM_LIBSSH_SOURCE_DIR or OPENTERM_LIBSSH_ARCHIVE to override." >&2
        exit 1
    fi

    mkdir -p "$(dirname "$LIBSSH_SOURCE_DIR")"
    case "$archive" in
        *.tar.xz) tar -xJf "$archive" -C "$(dirname "$LIBSSH_SOURCE_DIR")" ;;
        *.tar.gz) tar -xzf "$archive" -C "$(dirname "$LIBSSH_SOURCE_DIR")" ;;
        *)
            echo "❌ Unsupported libssh archive format: $archive" >&2
            exit 1
            ;;
    esac
}

build_arch() {
    local arch="$1"
    local openssl_root="$APPLE_OPENSSL_DIR/macos-$arch"
    local build_dir="$BUILD_ROOT/$arch"
    local install_dir="$APPLE_LIBSSH_DIR/macos-$arch"
    local sdkroot

    if [[ ! -d "$openssl_root" ]]; then
        echo "❌ Missing Apple OpenSSL artifact for $arch at $openssl_root" >&2
        echo "   Run ./scripts/build_apple_openssl.sh first." >&2
        exit 1
    fi

    sdkroot="$(xcrun --sdk macosx --show-sdk-path)"

    rm -rf "$build_dir" "$install_dir"
    mkdir -p "$build_dir" "$install_dir"

    "$CMAKE_BIN" -S "$LIBSSH_SOURCE_DIR" -B "$build_dir" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$install_dir" \
        -DCMAKE_OSX_SYSROOT="$sdkroot" \
        -DCMAKE_OSX_ARCHITECTURES="$arch" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
        -DBUILD_SHARED_LIBS=OFF \
        -DWITH_EXAMPLES=OFF \
        -DWITH_TESTING=OFF \
        -DWITH_GSSAPI=OFF \
        -DOPENSSL_ROOT_DIR="$openssl_root" \
        -DZLIB_LIBRARY=/usr/lib/libz.tbd \
        -DZLIB_INCLUDE_DIR="$sdkroot/usr/include"

    "$CMAKE_BIN" --build "$build_dir" --config Release
    "$CMAKE_BIN" --install "$build_dir"
}

require_command tar
require_command xcrun

if [[ ! -x "$CMAKE_BIN" ]]; then
    echo "❌ CMake binary not executable: $CMAKE_BIN" >&2
    exit 1
fi

extract_source_if_needed

echo "🔨 Building Apple libssh $LIBSSH_VERSION..."
echo "📦 Source: $LIBSSH_SOURCE_DIR"
echo "🔐 OpenSSL root: $APPLE_OPENSSL_DIR"
echo "📁 Output: $APPLE_LIBSSH_DIR"

rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT" "$APPLE_LIBSSH_DIR"

for arch in "${ARCHS[@]}"; do
    echo "⚙️  Building macOS libssh for $arch..."
    build_arch "$arch"
done

echo "✅ Apple libssh build completed."
echo "   - $APPLE_LIBSSH_DIR/macos-arm64"
