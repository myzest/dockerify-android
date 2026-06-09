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
REBOOT_AFTER="${MACOS_REBOOT_AFTER_SYSTEM_PROPS:-1}"

if ! profile_has_system_props; then
  macos_log "No system properties found for ${DEVICE_PROFILE}; nothing to apply."
  exit 0
fi

if ! macos_serial_online "$SERIAL"; then
  macos_error "${SERIAL} is not online. Start it first, for example:"
  macos_error "  MACOS_NO_WINDOW=0 MACOS_EMULATOR_EXTRA_ARGS='-writable-system' ./scripts/macos-run-avd.sh"
  exit 1
fi

macos_log "Waiting for Android boot completion on ${SERIAL}"
macos_wait_for_boot "$SERIAL" "$(macos_pid_file)"

props_tmp="$(mktemp)"
keys_tmp="$(mktemp)"
cleanup() {
  rm -f "$props_tmp" "$keys_tmp"
}
trap cleanup EXIT

profile_write_combined_props "$props_tmp"
profile_write_property_keys_file "$keys_tmp"

macos_log "Requesting root adbd"
adb -s "$SERIAL" root >/dev/null
adb -s "$SERIAL" wait-for-device

macos_log "Remounting system partitions writable"
if ! adb -s "$SERIAL" remount; then
  macos_error "adb remount failed. Restart this AVD with -writable-system, for example:"
  macos_error "  MACOS_NO_WINDOW=0 MACOS_EMULATOR_EXTRA_ARGS='-writable-system' ./scripts/macos-run-avd.sh"
  exit 1
fi

adb -s "$SERIAL" push "$props_tmp" /data/local/tmp/device-profile.props >/dev/null
adb -s "$SERIAL" push "$keys_tmp" /data/local/tmp/device-profile.keys >/dev/null

safe_profile="$(printf '%s' "$DEVICE_PROFILE" | sed 's/[^A-Za-z0-9_.-]/_/g')"
macos_log "Applying build-property overlay for ${DEVICE_PROFILE}"
adb -s "$SERIAL" shell "DEVICE_PROFILE='${safe_profile}' sh -s" <<'ANDROID_SH'
set -e

PROPS=/data/local/tmp/device-profile.props
KEYS=/data/local/tmp/device-profile.keys
TARGET=/system/build.prop
TMP=/data/local/tmp/device-profile.filtered
BACKUP_DIR=/data/local/tmp/dockerify-build-prop-backups
STAMP="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)"

[ -s "$PROPS" ]
[ -s "$KEYS" ]
[ -w "$TARGET" ]

mkdir -p "$BACKUP_DIR"

backup_prop_file() {
  local file="$1"
  local safe_name

  [ -f "$file" ] || return 0
  safe_name="$(printf '%s' "$file" | sed 's#^/##;s#[^A-Za-z0-9_.-]#.#g')"
  cp "$file" "$BACKUP_DIR/${safe_name}.${STAMP}"
  cp "$file" "$BACKUP_DIR/${safe_name}.latest"
}

filter_prop_file() {
  local file="$1"

  [ -f "$file" ] || return 0
  awk -F= '
    NR == FNR {
      if ($1 != "") {
        drop[$1] = 1
      }
      next
    }
    /^[[:space:]]*($|#)/ {
      print
      next
    }
    {
      key = $1
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      if (!(key in drop)) {
        print
      }
    }
  ' "$KEYS" "$file" > "$TMP"
  cat "$TMP" > "$file"
  rm -f "$TMP"
}

for f in /system/build.prop /vendor/build.prop /product/build.prop /system_ext/build.prop /odm/build.prop /vendor/odm/etc/build.prop; do
  backup_prop_file "$f" 2>/dev/null || true
  filter_prop_file "$f" 2>/dev/null || true
done

{
  echo ""
  echo "# Dockerify Android device profile: ${DEVICE_PROFILE}"
  echo "# Applied by scripts/macos-apply-system-props.sh"
  cat "$PROPS"
} >> "$TARGET"

rm -f "$PROPS" "$KEYS" "$TMP"
ANDROID_SH

macos_log "System property overlay installed. Backup path on device: /data/local/tmp/dockerify-build-prop-backups/"

if [ "$REBOOT_AFTER" = "1" ]; then
  macos_log "Rebooting ${SERIAL} so read-only Build properties are reloaded"
  adb -s "$SERIAL" reboot
  macos_wait_for_boot "$SERIAL" "$(macos_pid_file)"
  macos_log "Reapplying runtime profile settings after reboot"
  export ANDROID_SERIAL="$SERIAL"
  profile_apply_runtime_settings
  ANDROID_SERIAL="$SERIAL" profile_run_custom_settings
fi

macos_log "Done"
