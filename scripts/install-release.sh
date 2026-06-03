#!/usr/bin/env bash
# Standalone installer for a GitHub Release ZIP.
#
# Usage:
#   scripts/install-release.sh
#   scripts/install-release.sh ~/Downloads/CarRentalOptimizer-v0.4.0.zip
#
# Without Developer ID signing and notarization, a browser-downloaded app is
# blocked by Gatekeeper. This script is an explicit local-install workaround for
# trusted test builds: it installs the app, clears quarantine, and verifies that
# the app launches.
set -euo pipefail

REPO="${REPO:-sunnyhot/car-rental-optimizer}"
RELEASE_VERSION="${RELEASE_VERSION:-v0.4.0}"
ZIP_NAME="CarRentalOptimizer-${RELEASE_VERSION}.zip"
ZIP_URL="https://github.com/${REPO}/releases/download/${RELEASE_VERSION}/${ZIP_NAME}"
APP_NAME="租车比价助手.app"
DESTINATION="/Applications/${APP_NAME}"
TMP_DIR=$(mktemp -d)

cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

if [ "${1:-}" != "" ]; then
    ZIP_PATH="$1"
else
    ZIP_PATH="${TMP_DIR}/${ZIP_NAME}"
    echo "==> Downloading ${ZIP_URL}"
    curl -fL "${ZIP_URL}" -o "${ZIP_PATH}"
fi

if [ ! -f "${ZIP_PATH}" ]; then
    echo "ERROR: ZIP not found: ${ZIP_PATH}" >&2
    exit 1
fi

echo "==> Extracting ${ZIP_PATH}"
ditto -x -k "${ZIP_PATH}" "${TMP_DIR}"

SOURCE_APP="${TMP_DIR}/${APP_NAME}"
if [ ! -d "${SOURCE_APP}" ]; then
    echo "ERROR: ${APP_NAME} not found in ZIP" >&2
    find "${TMP_DIR}" -maxdepth 2 -print >&2
    exit 1
fi

echo "==> Installing ${APP_NAME} to /Applications"
rm -rf "${DESTINATION}"
ditto "${SOURCE_APP}" "${DESTINATION}"

echo "==> Clearing quarantine attributes"
xattr -cr "${DESTINATION}"

echo "==> Verifying code signature structure"
codesign --verify --deep --strict "${DESTINATION}"

echo "==> Launch smoke test"
open -n "${DESTINATION}"
sleep 3

EXECUTABLE_PATH="${DESTINATION}/Contents/MacOS/CarRentalOptimizer"
PID=$(pgrep -f "${EXECUTABLE_PATH}" | head -1 || true)
if [ -z "${PID}" ]; then
    echo "ERROR: App did not stay running after launch" >&2
    exit 1
fi

echo "Launch verification OK: ${DESTINATION} (pid ${PID})"
osascript -e 'tell application "租车比价助手" to quit' >/dev/null 2>&1 || true
sleep 1
if kill -0 "${PID}" 2>/dev/null; then
    kill "${PID}" 2>/dev/null || true
fi

echo "Installed: ${DESTINATION}"
