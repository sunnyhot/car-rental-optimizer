#!/usr/bin/env bash
# Launch a macOS .app and verify that its executable process starts.
set -euo pipefail

APP_BUNDLE="${1:-build/租车比价助手.app}"
EXECUTABLE_NAME="CarRentalOptimizer"
EXECUTABLE_PATH="${APP_BUNDLE}/Contents/MacOS/${EXECUTABLE_NAME}"
PROCESS_PATH="${EXECUTABLE_PATH}"
KEEP_RUNNING="${KEEP_RUNNING:-0}"

if [ ! -d "${APP_BUNDLE}" ]; then
    echo "ERROR: App bundle not found: ${APP_BUNDLE}" >&2
    exit 1
fi

if [ ! -x "${EXECUTABLE_PATH}" ]; then
    echo "ERROR: Executable not found or not executable: ${EXECUTABLE_PATH}" >&2
    exit 1
fi

if [ -L "${EXECUTABLE_PATH}" ]; then
    LINK_TARGET=$(readlink "${EXECUTABLE_PATH}")
    case "${LINK_TARGET}" in
        /*)
            PROCESS_PATH="${LINK_TARGET}"
            ;;
        *)
            PROCESS_PATH="$(cd "$(dirname "${EXECUTABLE_PATH}")" && cd "$(dirname "${LINK_TARGET}")" && pwd)/$(basename "${LINK_TARGET}")"
            ;;
    esac
fi

open -n "${APP_BUNDLE}"
sleep 3

PID=$(pgrep -f "${PROCESS_PATH}" | head -1 || true)
if [ -z "${PID}" ]; then
    echo "ERROR: App did not stay running after launch: ${APP_BUNDLE}" >&2
    exit 1
fi

echo "Launch verification OK: ${APP_BUNDLE} (pid ${PID})"

if [ "${KEEP_RUNNING}" != "1" ]; then
    osascript -e 'tell application "租车比价助手" to quit' >/dev/null 2>&1 || true
    sleep 1
    if kill -0 "${PID}" 2>/dev/null; then
        kill "${PID}" 2>/dev/null || true
    fi
fi
