#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."

OPENSSL_VERSION="${OPENTERM_OPENSSL_VERSION:-3.6.1}"
OPENSSL_ARCHIVE="${OPENTERM_OPENSSL_ARCHIVE:-$REPO_DIR/vendor/sources/openssl/openssl-$OPENSSL_VERSION.tar.gz}"
OPENSSL_SOURCE_DIR="${OPENTERM_OPENSSL_SOURCE_DIR:-$REPO_DIR/vendor/sources/openssl/openssl-$OPENSSL_VERSION}"
APPLE_VENDOR_DIR="$REPO_DIR/vendor/apple/openssl/$OPENSSL_VERSION"
BUILD_ROOT="$REPO_DIR/vendor/apple/build/openssl-$OPENSSL_VERSION"

ARCHS=("arm64")

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "❌ Missing required command: $1" >&2
        exit 1
    fi
}

extract_source_if_needed() {
    if [[ -d "$OPENSSL_SOURCE_DIR" ]]; then
        return
    fi

    if [[ ! -f "$OPENSSL_ARCHIVE" ]]; then
        echo "❌ OpenSSL source not found." >&2
        echo "   Expected either:" >&2
        echo "   - source directory: $OPENSSL_SOURCE_DIR" >&2
        echo "   - source archive:   $OPENSSL_ARCHIVE" >&2
        echo "   Set OPENTERM_OPENSSL_SOURCE_DIR or OPENTERM_OPENSSL_ARCHIVE to override." >&2
        exit 1
    fi

    mkdir -p "$(dirname "$OPENSSL_SOURCE_DIR")"
    tar -xzf "$OPENSSL_ARCHIVE" -C "$(dirname "$OPENSSL_SOURCE_DIR")"
}

configure_target() {
    local arch="$1"
    case "$arch" in
        arm64) echo "darwin64-arm64-cc" ;;
        *)
            echo "❌ Unsupported arch: $arch" >&2
            exit 1
            ;;
    esac
}

build_arch() {
    local arch="$1"
    local target
    local build_dir="$BUILD_ROOT/$arch"
    local install_dir="$APPLE_VENDOR_DIR/macos-$arch"
    local source_copy="$build_dir/src"

    target="$(configure_target "$arch")"

    rm -rf "$build_dir" "$install_dir"
    mkdir -p "$build_dir" "$install_dir"
    cp -R "$OPENSSL_SOURCE_DIR" "$source_copy"

    pushd "$source_copy" >/dev/null

    export CC="$(xcrun --sdk macosx --find clang)"
    export CXX="$(xcrun --sdk macosx --find clang++)"
    export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
    export CFLAGS="-arch $arch -isysroot $SDKROOT -mmacosx-version-min=14.0"
    export CXXFLAGS="$CFLAGS"
    export LDFLAGS="-arch $arch -isysroot $SDKROOT -mmacosx-version-min=14.0"

    ./Configure "$target" \
        no-shared \
        no-tests \
        --prefix="$install_dir"

    make clean >/dev/null 2>&1 || true
    make -j"$(sysctl -n hw.ncpu)"
    make install_sw

    popd >/dev/null
}

require_command tar
require_command make
require_command xcrun
require_command perl

extract_source_if_needed

echo "🔨 Building Apple OpenSSL $OPENSSL_VERSION..."
echo "📦 Source: $OPENSSL_SOURCE_DIR"
echo "📁 Output: $APPLE_VENDOR_DIR"

rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT" "$APPLE_VENDOR_DIR"

for arch in "${ARCHS[@]}"; do
    echo "⚙️  Building macOS OpenSSL for $arch..."
    build_arch "$arch"
done

echo "✅ Apple OpenSSL build completed."
echo "   - $APPLE_VENDOR_DIR/macos-arm64"
