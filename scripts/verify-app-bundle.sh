#!/usr/bin/env bash
# Verify that the packaged macOS app can resolve its embedded frameworks.
set -euo pipefail

APP_BUNDLE="${1:-build/租车总成本比较.app}"
EXECUTABLE_NAME="CarRentalOptimizer"
EXECUTABLE_PATH="${APP_BUNDLE}/Contents/MacOS/${EXECUTABLE_NAME}"
FRAMEWORK_RPATH="@executable_path/../Frameworks"

if [ ! -d "${APP_BUNDLE}" ]; then
    echo "ERROR: App bundle not found: ${APP_BUNDLE}" >&2
    exit 1
fi

if [ ! -x "${EXECUTABLE_PATH}" ]; then
    echo "ERROR: Executable not found or not executable: ${EXECUTABLE_PATH}" >&2
    exit 1
fi

PLIST_EXECUTABLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "${APP_BUNDLE}/Contents/Info.plist")
if [ "${PLIST_EXECUTABLE}" != "${EXECUTABLE_NAME}" ]; then
    echo "ERROR: CFBundleExecutable is ${PLIST_EXECUTABLE}, expected ${EXECUTABLE_NAME}" >&2
    exit 1
fi

if ! otool -l "${EXECUTABLE_PATH}" | grep -q "${FRAMEWORK_RPATH}"; then
    echo "ERROR: Missing framework rpath ${FRAMEWORK_RPATH}" >&2
    exit 1
fi

codesign --verify --deep --strict "${APP_BUNDLE}"
echo "App bundle verification OK: ${APP_BUNDLE}"
