#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$SCRIPT_DIR/../core"
BUILD_DIR="$CORE_DIR/build_xcframework"
XCFRAMEWORK_DIR="$SCRIPT_DIR/../dist/OpenTermCore.xcframework"
APPLE_OPENSSL_VERSION="${OPENTERM_OPENSSL_VERSION:-3.6.1}"
APPLE_LIBSSH_VERSION="${OPENTERM_LIBSSH_VERSION:-0.11.3}"
APPLE_OPENSSL_DIR="$SCRIPT_DIR/../vendor/apple/openssl/$APPLE_OPENSSL_VERSION"
APPLE_LIBSSH_DIR="$SCRIPT_DIR/../vendor/apple/libssh/$APPLE_LIBSSH_VERSION"

if [[ -x /opt/homebrew/bin/cmake ]]; then
    CMAKE_BIN="/opt/homebrew/bin/cmake"
else
    CMAKE_BIN="$(command -v cmake)"
fi

apple_deps_ready() {
    [[ -d "$APPLE_OPENSSL_DIR/macos-arm64" ]] &&
    [[ -d "$APPLE_LIBSSH_DIR/macos-arm64" ]]
}

echo "🔨 Building openterm_core as a macOS XCFramework..."

if ! apple_deps_ready; then
    echo "❌ Apple-native dependency artifacts are required for the Apple build path." >&2
    echo "   Expected prepared artifacts at:" >&2
    echo "   - $APPLE_OPENSSL_DIR/macos-arm64" >&2
    echo "   - $APPLE_LIBSSH_DIR/macos-arm64" >&2
    echo "   Generate them first with:" >&2
    echo "   ./scripts/build_apple_openssl.sh" >&2
    echo "   ./scripts/build_apple_libssh.sh" >&2
    exit 1
fi

# Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

build_arch() {
    local platform=$1
    local arch=$2
    local sysroot=$3
    local out_dir="$BUILD_DIR/$platform-$arch"

    echo "📋 Configuring $platform ($arch)..."

    local cmake_args=(
        -S "$CORE_DIR"
        -B "$out_dir"
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_EXAMPLE=OFF \
        -DBUILD_TESTS=OFF \
        -DCMAKE_OSX_SYSROOT="$sysroot" \
        -DCMAKE_OSX_ARCHITECTURES="$arch" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
    )

    cmake_args+=(
        -DOPENTERM_LIBSSH_ROOT="$APPLE_LIBSSH_DIR/$platform-$arch"
        -DOPENTERM_APPLE_OPENSSL_ROOT="$APPLE_OPENSSL_DIR/$platform-$arch"
    )

    "$CMAKE_BIN" "${cmake_args[@]}"

    echo "⚙️  Compiling $platform ($arch)..."
    "$CMAKE_BIN" --build "$out_dir" --config Release
}

# 1. Build macOS (arm64 only)
build_arch "macOS" "arm64" "macosx"

# 2. Create XCFramework
echo "📦 Combining static libraries into XCFramework..."
rm -rf "$XCFRAMEWORK_DIR"
mkdir -p "$SCRIPT_DIR/../dist"

xcodebuild -create-xcframework \
    -library "$BUILD_DIR/macOS-arm64/libopenterm_core.a" -headers "$CORE_DIR/include" \
    -output "$XCFRAMEWORK_DIR"

echo "✅ Success! XCFramework created at: $XCFRAMEWORK_DIR"
echo "ℹ️  This repo currently supports the macOS XCFramework path only."
echo "ℹ️  Built against prepared Apple OpenSSL/libssh artifacts."
