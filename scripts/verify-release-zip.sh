#!/usr/bin/env bash
# Verify that a release ZIP preserves the macOS app bundle after extraction.
set -euo pipefail

ZIP_PATH="${1:?Usage: $0 <release-zip>}"
EXPECTED_APP_NAME="${2:-租车比价助手.app}"

if [ ! -f "${ZIP_PATH}" ]; then
    echo "ERROR: Release ZIP not found: ${ZIP_PATH}" >&2
    exit 1
fi

TMP_DIR=$(mktemp -d)
cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

ditto -x -k "${ZIP_PATH}" "${TMP_DIR}"

APP_BUNDLE="${TMP_DIR}/${EXPECTED_APP_NAME}"
if [ ! -d "${APP_BUNDLE}" ]; then
    echo "ERROR: App bundle not found after extracting ZIP: ${EXPECTED_APP_NAME}" >&2
    find "${TMP_DIR}" -maxdepth 3 -print >&2
    exit 1
fi

SPARKLE_FRAMEWORK="${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework"
if [ -d "${SPARKLE_FRAMEWORK}" ]; then
    SYMLINK_COUNT=$(find "${SPARKLE_FRAMEWORK}" -maxdepth 3 -type l | wc -l | tr -d ' ')
    if [ "${SYMLINK_COUNT}" -eq 0 ]; then
        echo "ERROR: ZIP extraction did not preserve Sparkle.framework symlinks" >&2
        exit 1
    fi
fi

"$(dirname "$0")/verify-app-bundle.sh" "${APP_BUNDLE}"
echo "Release ZIP verification OK: ${ZIP_PATH}"
