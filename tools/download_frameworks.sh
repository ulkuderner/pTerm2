#!/bin/sh
# Fetches optional native frameworks used by iTerm2 Pad:
#   * ios_system (Blink/a-Shell command runtime, BSD-3)
#   * libssh2 (SSH / scp)
#   * CPython 3.13 iOS XCFramework
#   * libgit2
#
# After a successful download, regenerate the Xcode project and rebuild with
# IT2PAD_HAS_IOS_SYSTEM / IT2PAD_HAS_LIBSSH2 / IT2PAD_HAS_PYTHON defined.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
VENDOR="$ROOT/Vendor"
mkdir -p "$VENDOR"

IOS_SYSTEM_URL="https://github.com/holzschu/ios_system/releases/latest/download/release.tar.gz"
echo "Downloading ios_system into $VENDOR/ios_system"
mkdir -p "$VENDOR/ios_system"
if command -v curl >/dev/null 2>&1; then
    curl -L "$IOS_SYSTEM_URL" -o "$VENDOR/ios_system/release.tar.gz" || {
        echo "ios_system download failed; Swift fallback commands remain available."
    }
    if [ -f "$VENDOR/ios_system/release.tar.gz" ]; then
        tar -xzf "$VENDOR/ios_system/release.tar.gz" -C "$VENDOR/ios_system" || true
    fi
else
    echo "curl is required to download frameworks."
    exit 1
fi

echo "Place a CPython 3.13 iOS XCFramework (--enable-framework, arm64-apple-ios) in:"
echo "  $VENDOR/Python.xcframework"
echo "Place libssh2.xcframework in:"
echo "  $VENDOR/libssh2.xcframework"
echo "Place libgit2.xcframework in:"
echo "  $VENDOR/libgit2.xcframework"
echo "Then re-run tools/generate_project.rb and build."
