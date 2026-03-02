#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."

echo "🧹 Cleaning build artifacts..."

rm -rf \
    "$REPO_DIR/core/build" \
    "$REPO_DIR/core/build-tests" \
    "$REPO_DIR/core/build_xcframework" \
    "$REPO_DIR/dist/OpenTermCore.xcframework" \
    "$REPO_DIR/platforms/macos/.build" \
    "$REPO_DIR/platforms/macos/.cache" \
    "$REPO_DIR/platforms/macos/.spm-home" \
    "$REPO_DIR/vendor/apple/build"

echo "✅ Clean complete!"
echo ""
echo "📝 Removed local build outputs and caches."
echo "   Prepared Apple artifacts under vendor/apple/openssl and vendor/apple/libssh were kept."
