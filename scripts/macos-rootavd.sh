#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/macos-env.sh"

ROOTAVD_REPO="${ROOTAVD_REPO:-newbit/rootAVD}"
ROOTAVD_REF="${ROOTAVD_REF:-master}"
ROOTAVD_CACHE_DIR="${ROOTAVD_CACHE_DIR:-${HOME}/.dockerify-android/rootavd}"
ROOTAVD_TARBALL="${ROOTAVD_CACHE_DIR}/rootAVD-${ROOTAVD_REF}.tar.gz"
ROOTAVD_WORK_DIR="${ROOTAVD_CACHE_DIR}/rootAVD-${ROOTAVD_REF}"
ACTION="${1:-patch}"

require_host_command() {
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    macos_error "Missing '${command_name}'. Install it on macOS and try again."
    exit 1
  fi
}

macos_require_darwin
macos_load_profile
macos_configure_sdk_path || {
  macos_error "Android SDK not found. Run ./scripts/macos-bootstrap-sdk.sh first."
  exit 1
}
macos_require_command adb
require_host_command curl
require_host_command tar
require_host_command sed
require_host_command unzip

AVD_NAME="$(macos_avd_name)"
SYSTEM_IMAGE="$(macos_system_image_package)"
SYSTEM_IMAGE_RELPATH="$(macos_package_relpath "$SYSTEM_IMAGE")"
RAMDISK_PATH="${ANDROID_HOME}/${SYSTEM_IMAGE_RELPATH}/ramdisk.img"
SERIAL="$(macos_android_serial)"

download_rootavd_if_needed() {
  local url

  mkdir -p "$ROOTAVD_CACHE_DIR"
  if [ -f "$ROOTAVD_WORK_DIR/rootAVD.sh" ] && [ -f "$ROOTAVD_WORK_DIR/Magisk.zip" ]; then
    return 0
  fi

  url="https://gitlab.com/${ROOTAVD_REPO}/-/archive/${ROOTAVD_REF}/$(basename "$ROOTAVD_REPO")-${ROOTAVD_REF}.tar.gz"
  macos_log "Downloading rootAVD from ${url}"
  rm -rf "$ROOTAVD_WORK_DIR"
  curl -fL --retry 3 --retry-delay 2 "$url" -o "$ROOTAVD_TARBALL"
  mkdir -p "$ROOTAVD_WORK_DIR"
  tar -xzf "$ROOTAVD_TARBALL" --strip-components=1 -C "$ROOTAVD_WORK_DIR"
}

require_running_avd() {
  if ! macos_serial_online "$SERIAL"; then
    macos_error "${SERIAL} is not online."
    macos_error "Start the native AVD first, for example:"
    macos_error "  MACOS_NO_WINDOW=0 DEVICE_PROFILE=${DEVICE_PROFILE} ./scripts/macos-run-avd.sh"
    exit 1
  fi
}

require_ramdisk() {
  if [ ! -f "$RAMDISK_PATH" ]; then
    macos_error "ramdisk.img not found: ${RAMDISK_PATH}"
    macos_error "Run ./scripts/macos-bootstrap-sdk.sh or check MACOS_SYSTEM_IMAGE."
    exit 1
  fi
}

backup_ramdisk() {
  local backup_path

  backup_path="${RAMDISK_PATH}.dockerify-native-rootavd-$(date +%Y%m%d-%H%M%S).backup"
  cp "$RAMDISK_PATH" "$backup_path"
  macos_log "Backed up ramdisk.img to ${backup_path}"
}

restore_latest_backup() {
  local latest_backup

  latest_backup="$(find "$(dirname "$RAMDISK_PATH")" -maxdepth 1 -type f \
    -name 'ramdisk.img.dockerify-native-rootavd-*.backup' \
    -print | sort | tail -1)"
  if [ -z "$latest_backup" ]; then
    macos_error "No native rootAVD backup found next to ${RAMDISK_PATH}"
    exit 1
  fi

  cp "$latest_backup" "$RAMDISK_PATH"
  copy_patched_ramdisk_to_avd
  macos_log "Restored ${RAMDISK_PATH} from ${latest_backup}"
}

patch_rootavd_noninteractive() {
  local script_path="${ROOTAVD_WORK_DIR}/rootAVD.sh"

  chmod +x "$script_path"
  # Keep rootAVD's Magisk download chooser non-interactive when Magisk.zip
  # needs to be refreshed by the upstream script.
  sed -i.bak 's/read -t 10 choice/choice=1/' "$script_path"

  macos_log "Patching ${RAMDISK_PATH}"
  (
    cd "$ROOTAVD_WORK_DIR"
    ADB="$ANDROID_HOME/platform-tools/adb" ./rootAVD.sh "$SYSTEM_IMAGE_RELPATH/ramdisk.img"
  )
}

copy_patched_ramdisk_to_avd() {
  local avd_ramdisk

  avd_ramdisk="$(macos_avd_dir "$AVD_NAME")/ramdisk.img"
  if [ -d "$(dirname "$avd_ramdisk")" ]; then
    cp "$RAMDISK_PATH" "$avd_ramdisk"
    macos_log "Copied patched ramdisk into ${avd_ramdisk}"
  fi
}

macos_log "Native rootAVD target: ${AVD_NAME} (${SERIAL})"
macos_log "System image: ${SYSTEM_IMAGE}"
macos_log "This patches the SDK system image ramdisk used by this profile."

require_ramdisk
if [ "$ACTION" = "restore" ]; then
  restore_latest_backup
  exit 0
fi

if [ "$ACTION" != "patch" ]; then
  macos_error "Unknown action: ${ACTION}"
  macos_error "Usage: DEVICE_PROFILE=${DEVICE_PROFILE} ./scripts/macos-rootavd.sh [patch|restore]"
  exit 1
fi

require_running_avd
download_rootavd_if_needed
backup_ramdisk
patch_rootavd_noninteractive
copy_patched_ramdisk_to_avd

macos_log "rootAVD patch complete."
macos_log "Cold boot the AVD to load Magisk:"
macos_log "  adb -s ${SERIAL} emu kill"
macos_log "  MACOS_NO_WINDOW=0 DEVICE_PROFILE=${DEVICE_PROFILE} ./scripts/macos-run-avd.sh"
