#!/bin/bash
set -euo pipefail

echo "🔧 Checking build requirements..."
echo ""

if command -v cmake >/dev/null 2>&1; then
    CMAKE_VERSION=$(cmake --version | head -n 1)
    echo "✅ CMake: $CMAKE_VERSION"
else
    echo "❌ CMake: NOT FOUND"
    echo "   Install CMake and make sure it is available in PATH."
    exit 1
fi

if command -v git >/dev/null 2>&1; then
    GIT_VERSION=$(git --version)
    echo "✅ Git: $GIT_VERSION"
else
    echo "❌ Git: NOT FOUND"
    echo "   Install Git and make sure it is available in PATH."
    exit 1
fi

if [[ "$OSTYPE" == "darwin"* ]]; then
    if xcode-select -p >/dev/null 2>&1; then
        echo "✅ Xcode Command Line Tools: Installed"
    else
        echo "❌ Xcode Command Line Tools: NOT FOUND"
        echo "   Install Xcode Command Line Tools and try again."
        exit 1
    fi

    for cmd in xcrun xcodebuild swift make perl; do
        if command -v "$cmd" >/dev/null 2>&1; then
            echo "✅ $cmd: Available"
        else
            echo "❌ $cmd: NOT FOUND"
            echo "   Install the required Apple developer tools and ensure $cmd is in PATH."
            exit 1
        fi
    done
else
    if command -v gcc >/dev/null 2>&1; then
        GCC_VERSION=$(gcc --version | head -n 1)
        echo "✅ GCC: $GCC_VERSION"
    elif command -v clang >/dev/null 2>&1; then
        CLANG_VERSION=$(clang --version | head -n 1)
        echo "✅ Clang: $CLANG_VERSION"
    else
        echo "❌ C Compiler: NOT FOUND"
        echo "   Install a working C compiler and make sure it is available in PATH."
        exit 1
    fi
fi

echo ""
echo "✅ All requirements met!"
echo ""
echo "📝 Notes:"
echo "   - The general core build uses vendor/libssh already present in the repo."
echo "   - The macOS app build uses Apple-native OpenSSL/libssh artifacts generated from vendor/sources/."
echo "   - Builds do not install libssh for you via Homebrew or apt."
echo "   Review THIRD_PARTY_NOTICES.md before redistributing binaries."
echo ""
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "🚀 Run './scripts/build_macos_app.sh' for the supported macOS app path."
    echo "   Run './scripts/build.sh' for the shared core only."
else
    echo "🚀 Run './scripts/build.sh' to compile the shared core."
fi
