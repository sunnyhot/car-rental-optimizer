#!/usr/bin/env bash
# Verify that the packaged macOS app can resolve its embedded frameworks.
set -euo pipefail

APP_BUNDLE="${1:-build/租车比价助手.app}"
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

PLIST_PACKAGE_TYPE=$(/usr/libexec/PlistBuddy -c "Print :CFBundlePackageType" "${APP_BUNDLE}/Contents/Info.plist")
if [ "${PLIST_PACKAGE_TYPE}" != "APPL" ]; then
    echo "ERROR: CFBundlePackageType is ${PLIST_PACKAGE_TYPE}, expected APPL" >&2
    exit 1
fi

PLIST_INFO_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleInfoDictionaryVersion" "${APP_BUNDLE}/Contents/Info.plist")
if [ "${PLIST_INFO_VERSION}" != "6.0" ]; then
    echo "ERROR: CFBundleInfoDictionaryVersion is ${PLIST_INFO_VERSION}, expected 6.0" >&2
    exit 1
fi

if ! otool -l "${EXECUTABLE_PATH}" | grep -q "${FRAMEWORK_RPATH}"; then
    echo "ERROR: Missing framework rpath ${FRAMEWORK_RPATH}" >&2
    exit 1
fi

SIGNATURE_KIND=$(codesign -dv --verbose=4 "${APP_BUNDLE}" 2>&1 | awk -F= '/^Signature=/{print $2}')
if [ "${SIGNATURE_KIND}" = "adhoc" ] && otool -L "${EXECUTABLE_PATH}" | grep -q "@rpath/Sparkle.framework"; then
    echo "ERROR: Ad-hoc release app must not link Sparkle.framework; Gatekeeper blocks the nested framework" >&2
    exit 1
fi

codesign --verify --deep --strict "${APP_BUNDLE}"
echo "App bundle verification OK: ${APP_BUNDLE}"
