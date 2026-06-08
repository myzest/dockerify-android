#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/profile-lib.sh"

load_device_profile

adb wait-for-device

prop() {
  adb shell getprop "$1" 2>/dev/null | tr -d '\r'
}

setting() {
  adb shell settings get "$1" "$2" 2>/dev/null | tr -d '\r'
}

echo "=== Dockerify Android Profile Verification ==="
echo "profile=${DEVICE_PROFILE}"
echo "label=${DEVICE_PROFILE_LABEL}"
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

echo "--- ABI ---"
for key in \
  ro.product.cpu.abilist \
  ro.product.cpu.abilist32 \
  ro.product.cpu.abilist64 \
  ro.dalvik.vm.native.bridge \
  ro.ndk_translation.version; do
  printf '%s=%s\n' "$key" "$(prop "$key")"
done
echo

echo "--- Display ---"
adb shell wm size 2>/dev/null | tr -d '\r' || true
adb shell wm density 2>/dev/null | tr -d '\r' || true
echo

echo "--- Locale and time ---"
printf 'persist.sys.locale=%s\n' "$(prop persist.sys.locale)"
printf 'persist.sys.timezone=%s\n' "$(prop persist.sys.timezone)"
printf 'device_name=%s\n' "$(setting global device_name)"
echo

echo "--- Runtime state ---"
printf 'sys.boot_completed=%s\n' "$(prop sys.boot_completed)"
printf 'gapps_marker=%s\n' "$(adb shell 'test -d /system/priv-app/PrebuiltGmsCore || test -d /data/adb/modules/gapps && echo present || echo missing' 2>/dev/null | tr -d '\r')"
printf 'magisk=%s\n' "$(adb shell 'test -x /data/adb/magisk/magiskinit && echo present || echo missing' 2>/dev/null | tr -d '\r')"
printf 'arm_translation_marker=%s\n' "$(adb shell 'test -d /data/adb/modules/ndk_translation || test -f /system/lib64/libndk_translation.so && echo present || echo missing' 2>/dev/null | tr -d '\r')"
echo

echo "--- Sensors snapshot ---"
adb shell dumpsys sensorservice 2>/dev/null | sed -n '1,80p' | tr -d '\r' || true
