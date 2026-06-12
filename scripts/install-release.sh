#!/usr/bin/env bash
# Standalone installer for a GitHub Release ZIP.
#
# Usage:
#   scripts/install-release.sh
#   scripts/install-release.sh ~/Downloads/CarRentalOptimizer-v0.7.0.zip
#
# Without Developer ID signing and notarization, a browser-downloaded app is
# blocked by Gatekeeper. This script is an explicit local-install workaround for
# trusted test builds: it installs the app, clears quarantine, and verifies that
# the app launches.
set -euo pipefail

REPO="${REPO:-sunnyhot/car-rental-optimizer}"
RELEASE_VERSION="${RELEASE_VERSION:-v0.7.0}"
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

echo "==> Installing launch runtime"
RUNTIME_DIR="${HOME}/Library/Application Support/CarRentalOptimizer/runtime"
RUNTIME_EXECUTABLE="${RUNTIME_DIR}/CarRentalOptimizer"
BUNDLED_EXECUTABLE="${DESTINATION}/Contents/MacOS/CarRentalOptimizer"
TMP_RUNTIME="${RUNTIME_EXECUTABLE}.$$"
mkdir -p "${RUNTIME_DIR}"
cp "${BUNDLED_EXECUTABLE}" "${TMP_RUNTIME}"
chmod +x "${TMP_RUNTIME}"
mv -f "${TMP_RUNTIME}" "${RUNTIME_EXECUTABLE}"
rm -f "${BUNDLED_EXECUTABLE}"
ln -s "${RUNTIME_EXECUTABLE}" "${BUNDLED_EXECUTABLE}"

echo "==> Clearing quarantine attributes"
xattr -cr "${DESTINATION}" "${RUNTIME_EXECUTABLE}"

echo "==> Clearing saved window state"
rm -rf "${HOME}/Library/Saved Application State/com.carrental.optimizer.savedState"

echo "==> Verifying installed bundle"
bash "$(dirname "$0")/verify-app-bundle.sh" "${DESTINATION}"

echo "==> Launch smoke test"
bash "$(dirname "$0")/verify-launch.sh" "${DESTINATION}"

echo "Installed: ${DESTINATION}"
