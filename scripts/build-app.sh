#!/usr/bin/env bash
# Build a proper macOS .app bundle with Sparkle framework embedded.
# This script creates the bundle structure that swift build alone does not produce.
set -euo pipefail

APP_NAME="租车总成本比较"
BUNDLE_ID="com.carrental.optimizer"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"

echo "==> Building CarRentalOptimizer in Release mode..."
swift build -c release

echo "==> Creating .app bundle structure..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Frameworks"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy executable
cp ".build/release/CarRentalOptimizer" "${APP_BUNDLE}/Contents/MacOS/"

# Copy Info.plist
if [ -f "native/Info.plist" ]; then
    cp "native/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
    echo "    Copied native/Info.plist"
else
    echo "    WARNING: native/Info.plist not found"
fi

# Copy Sparkle framework (find it in the build artifacts)
SPARKLE_FW=$(find .build -name "Sparkle.framework" -type d -maxdepth 5 | head -1)
if [ -n "${SPARKLE_FW}" ]; then
    cp -R "${SPARKLE_FW}" "${APP_BUNDLE}/Contents/Frameworks/"
    echo "    Copied Sparkle.framework"
else
    echo "    WARNING: Sparkle.framework not found in .build"
fi

# Create PkgInfo
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

# Ad-hoc sign (sign frameworks first, then the whole bundle)
echo "==> Signing app bundle..."
if [ -d "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework" ]; then
    codesign --force --sign - "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework"
    echo "    Signed Sparkle.framework"
fi
codesign --deep --force --sign - "${APP_BUNDLE}"
echo "    Ad-hoc signed ${APP_NAME}.app"

# Verify signature
echo "==> Verifying signature..."
codesign --verify --deep --strict "${APP_BUNDLE}"
echo "    Signature OK"

# Clear quarantine attributes
xattr -cr "${APP_BUNDLE}"
echo "    Cleared quarantine attributes"

echo "==> App bundle created at ${APP_BUNDLE}"
echo ""
echo "To test: open \"${APP_BUNDLE}\""
echo "To distribute: codesign, notarize, and create a DMG (see docs/release-guide.md)"
