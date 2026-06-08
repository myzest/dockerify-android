#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/macos-env.sh"

macos_require_darwin
macos_load_profile
macos_configure_sdk_path || {
  macos_error "Android SDK not found"
  exit 1
}
macos_require_command adb

SERIAL="$(macos_android_serial)"
PID_FILE="$(macos_pid_file)"
LAUNCHD_JOB="$(macos_launchd_job)"
LAUNCHD_PLIST="$(macos_launchd_plist)"

if macos_serial_online "$SERIAL"; then
  macos_log "Stopping ${SERIAL}"
  adb -s "$SERIAL" emu kill >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do
    if ! macos_serial_online "$SERIAL"; then
      break
    fi
    sleep 1
  done
else
  macos_log "${SERIAL} is not listed by adb"
fi

if launchctl print "$LAUNCHD_JOB" >/dev/null 2>&1; then
  macos_log "Unloading ${LAUNCHD_JOB}"
  launchctl bootout "$LAUNCHD_JOB" >/dev/null 2>&1 || true
fi

if [ -f "$PID_FILE" ]; then
  pid="$(cat "$PID_FILE")"
  if [ -n "$pid" ] && kill -0 "$pid" >/dev/null 2>&1; then
    kill "$pid" >/dev/null 2>&1 || true
  fi
  rm -f "$PID_FILE"
fi

rm -f "$LAUNCHD_PLIST"
