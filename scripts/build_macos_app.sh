#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."
PACKAGE_DIR="$REPO_DIR/platforms/macos"
SCRATCH_DIR="$REPO_DIR/platforms/macos/.build"
MODULE_CACHE_DIR="$REPO_DIR/platforms/macos/.cache/clang-modules"
SPM_HOME="$REPO_DIR/platforms/macos/.spm-home"

mkdir -p "$MODULE_CACHE_DIR" "$SPM_HOME"

echo "🔨 Preparing Apple OpenSSL artifacts..."
"$SCRIPT_DIR/build_apple_openssl.sh"

echo "🔨 Preparing Apple libssh artifacts..."
"$SCRIPT_DIR/build_apple_libssh.sh"

"$SCRIPT_DIR/build_apple_xcframework.sh"

echo "🔨 Building macOS app from Swift Package..."

HOME="$SPM_HOME" \
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" \
swift build \
    --package-path "$PACKAGE_DIR" \
    --scratch-path "$SCRATCH_DIR"

echo "✅ macOS app build completed."
echo "📦 XCFramework: $REPO_DIR/dist/OpenTermCore.xcframework"
echo "📦 SwiftPM build: $SCRATCH_DIR"
