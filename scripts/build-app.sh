#!/usr/bin/env bash
# Build a proper macOS .app bundle.
# This script creates the bundle structure that swift build alone does not produce.
set -euo pipefail

APP_NAME="租车比价助手"
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

# Ensure embedded frameworks are resolvable only when the executable actually
# links an @rpath framework. install_name_tool mutates the Mach-O and can break
# SwiftPM's linker signature, which current macOS then kills at launch.
EXECUTABLE_PATH="${APP_BUNDLE}/Contents/MacOS/CarRentalOptimizer"
FRAMEWORK_RPATH="@executable_path/../Frameworks"
if otool -L "${EXECUTABLE_PATH}" | grep -q "@rpath/"; then
    if ! otool -l "${EXECUTABLE_PATH}" | grep -q "${FRAMEWORK_RPATH}"; then
        install_name_tool -add_rpath "${FRAMEWORK_RPATH}" "${EXECUTABLE_PATH}"
        echo "    Added framework rpath ${FRAMEWORK_RPATH}"
    fi
else
    echo "    No @rpath framework dependencies; leaving linker signature untouched"
fi

# Copy Info.plist
if [ -f "native/Info.plist" ]; then
    cp "native/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
    echo "    Copied native/Info.plist"
else
    echo "    WARNING: native/Info.plist not found"
fi

if [ -f "native/AppIcon.icns" ]; then
    cp "native/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
    echo "    Copied native/AppIcon.icns"
else
    echo "    WARNING: native/AppIcon.icns not found"
fi

# Copy Sparkle only when the executable links it. Stale .build caches may contain
# Sparkle.framework even when the current release target no longer uses it.
if otool -L "${EXECUTABLE_PATH}" | grep -q "@rpath/Sparkle.framework"; then
    SPARKLE_FW=$(find .build -name "Sparkle.framework" -type d -maxdepth 5 | head -1)
    if [ -n "${SPARKLE_FW}" ]; then
        cp -R "${SPARKLE_FW}" "${APP_BUNDLE}/Contents/Frameworks/"
        echo "    Copied Sparkle.framework"
    else
        echo "    WARNING: Sparkle.framework not found in .build"
    fi
else
    echo "    Sparkle.framework not linked; skipping embedded framework copy"
fi

# Create PkgInfo
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

# The GitHub ZIP is still ad-hoc signed so update/install code can verify bundle
# integrity. The local installer externalizes the runtime executable before
# launch because current macOS builds reject an ad-hoc app main executable.
if [ "${SKIP_CODESIGN_APP:-0}" != "1" ]; then
    echo "==> Signing app bundle..."
    if [ -d "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework" ]; then
        codesign --force --sign - "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework"
        echo "    Signed Sparkle.framework"
    fi
    codesign --deep --force --sign - "${APP_BUNDLE}"
    echo "    Ad-hoc signed ${APP_NAME}.app"
else
    echo "==> Skipping ad-hoc bundle signing"
fi

# Clear quarantine attributes
xattr -cr "${APP_BUNDLE}"
echo "    Cleared quarantine attributes"

echo "==> Verifying app bundle..."
REQUIRE_CODESIGN=1 bash "$(dirname "$0")/verify-app-bundle.sh" "${APP_BUNDLE}"

echo "==> App bundle created at ${APP_BUNDLE}"
echo ""
echo "To test after zipping: LAUNCH_AFTER_INSTALL=1 scripts/install-local-app.sh build/CarRentalOptimizer-vX.Y.Z.zip"
echo "To distribute: codesign, notarize, and create a DMG (see docs/release-guide.md)"
