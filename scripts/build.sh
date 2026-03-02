#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$SCRIPT_DIR/../core"
BUILD_DIR="$CORE_DIR/build"
LOCAL_LIBSSH_ROOT=""

if [[ -d "$SCRIPT_DIR/../vendor/libssh" ]]; then
    LOCAL_LIBSSH_ROOT="$SCRIPT_DIR/../vendor/libssh"
fi

CMAKE_BIN="$(command -v cmake)"

if command -v getconf >/dev/null 2>&1; then
    BUILD_JOBS="$(getconf NPROCESSORS_ONLN)"
elif command -v nproc >/dev/null 2>&1; then
    BUILD_JOBS="$(nproc)"
else
    BUILD_JOBS=4
fi

CMAKE_ARGS=(
    ..
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_INSTALL_PREFIX="$SCRIPT_DIR/../dist"
    -DBUILD_SHARED_LIBS=OFF
    -DBUILD_EXAMPLE=ON
)

if [[ -d "$LOCAL_LIBSSH_ROOT" ]]; then
    CMAKE_ARGS+=("-DOPENTERM_LIBSSH_ROOT=$LOCAL_LIBSSH_ROOT")
fi

echo "🔨 Building OpenTerm SSH core with managed libssh/OpenSSL dependencies..."
echo ""
echo "🛠️  Using CMake: $CMAKE_BIN"
echo "🧵 Parallel jobs: $BUILD_JOBS"
echo ""

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo "📋 Configuring with CMake..."
"$CMAKE_BIN" "${CMAKE_ARGS[@]}" "$@"

echo ""
echo "⚙️  Compiling (this may take a few minutes on first build)..."
make -j"$BUILD_JOBS"

echo ""
echo "✅ Build completed!"
echo ""
echo "📦 Output:"
echo "   - Library: $BUILD_DIR/libopenterm_core.a"
echo "   - CLI: $BUILD_DIR/openterm_cli"
echo ""
echo "📚 libssh is resolved from the vendored copy configured for this repo."
echo "   Review THIRD_PARTY_NOTICES.md before redistributing binaries."
echo "   Source of truth for libssh: $LOCAL_LIBSSH_ROOT"
