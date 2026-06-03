#!/usr/bin/env bash
# Install the locally built or downloaded ad-hoc app on this Mac.
#
# Public GitHub ZIP downloads are quarantined by macOS. Without Developer ID
# signing and notarization, Gatekeeper rejects a browser-downloaded app on first
# double-click. This installer is for local/test installs: it copies the app to
# /Applications, clears quarantine attributes, verifies the bundle, and can run
# a launch smoke test.
set -euo pipefail

INPUT_PATH="${1:-build/租车比价助手.app}"
APP_NAME="租车比价助手.app"
DESTINATION="/Applications/${APP_NAME}"
TMP_DIR=""
LAUNCH_AFTER_INSTALL="${LAUNCH_AFTER_INSTALL:-1}"

cleanup() {
    if [ -n "${TMP_DIR}" ]; then
        rm -rf "${TMP_DIR}"
    fi
}
trap cleanup EXIT

if [ -d "${INPUT_PATH}" ]; then
    SOURCE_APP="${INPUT_PATH}"
elif [ -f "${INPUT_PATH}" ]; then
    TMP_DIR=$(mktemp -d)
    ditto -x -k "${INPUT_PATH}" "${TMP_DIR}"
    SOURCE_APP="${TMP_DIR}/${APP_NAME}"
else
    echo "ERROR: Input app or zip not found: ${INPUT_PATH}" >&2
    exit 1
fi

if [ ! -d "${SOURCE_APP}" ]; then
    echo "ERROR: ${APP_NAME} not found in input: ${INPUT_PATH}" >&2
    find "${TMP_DIR:-$(dirname "${INPUT_PATH}")}" -maxdepth 2 -print >&2
    exit 1
fi

echo "==> Installing ${APP_NAME} to /Applications"
rm -rf "${DESTINATION}"
ditto "${SOURCE_APP}" "${DESTINATION}"

echo "==> Clearing quarantine attributes"
xattr -cr "${DESTINATION}"

echo "==> Verifying installed bundle"
"$(dirname "$0")/verify-app-bundle.sh" "${DESTINATION}"

if [ "${LAUNCH_AFTER_INSTALL}" = "1" ]; then
    echo "==> Launch smoke test"
    "$(dirname "$0")/verify-launch.sh" "${DESTINATION}"
fi

echo "Installed: ${DESTINATION}"
