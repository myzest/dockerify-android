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

SERIAL="${ANDROID_SERIAL:-$(macos_android_serial)}"

prop() {
  adb -s "$SERIAL" shell getprop "$1" 2>/dev/null | tr -d '\r'
}

setting() {
  adb -s "$SERIAL" shell settings get "$1" "$2" 2>/dev/null | tr -d '\r'
}

expect_text() {
  local label="$1"
  local expected="$2"
  local actual="$3"

  if [ -z "$expected" ]; then
    return 0
  fi
  if [ "$actual" = "$expected" ]; then
    printf '[ok] %s=%s\n' "$label" "$actual"
  else
    printf '[warn] %s expected %s, got %s\n' "$label" "$expected" "$actual"
  fi
}

macos_wait_for_boot "$SERIAL" "$(macos_pid_file)"

echo "=== Dockerify Android macOS Profile Verification ==="
echo "profile=${DEVICE_PROFILE}"
echo "label=${DEVICE_PROFILE_LABEL}"
echo "serial=${SERIAL}"
echo

echo "--- Build identity ---"
for key in \
  ro.product.brand \
  ro.product.manufacturer \
  ro.product.model \
  ro.product.name \
  ro.product.device \
  ro.build.version.release \
  ro.build.version.sdk \
  ro.build.id \
  ro.build.tags \
  ro.build.type \
  ro.build.fingerprint; do
  printf '%s=%s\n' "$key" "$(prop "$key")"
done
echo

echo "--- Runtime profile checks ---"
expect_text "sys.boot_completed" "1" "$(prop sys.boot_completed)"
expect_text "persist.sys.timezone" "${PROFILE_TIMEZONE:-}" "$(prop persist.sys.timezone)"
expect_text "device_name" "${PROFILE_DEVICE_NAME:-}" "$(setting global device_name)"
echo

echo "--- Display ---"
adb -s "$SERIAL" shell wm size 2>/dev/null | tr -d '\r' || true
adb -s "$SERIAL" shell wm density 2>/dev/null | tr -d '\r' || true
echo

echo "--- ABI ---"
for key in \
  ro.product.cpu.abilist \
  ro.product.cpu.abilist32 \
  ro.product.cpu.abilist64 \
  ro.dalvik.vm.native.bridge; do
  printf '%s=%s\n' "$key" "$(prop "$key")"
done
echo

echo "--- macOS runner scope ---"
echo "root_magisk=not managed by macOS native runner"
echo "system_build_prop=not managed by macOS native runner"
