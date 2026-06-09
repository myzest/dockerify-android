#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

export PROFILE_ROOT="${PROFILE_ROOT:-${REPO_ROOT}/profiles}"
export DEVICE_PROFILE="${DEVICE_PROFILE:-pixel_5_android_11}"

. "${SCRIPT_DIR}/profile-lib.sh"

macos_log() {
  echo "[macos] $*"
}

macos_error() {
  echo "[macos] $*" >&2
}

macos_require_darwin() {
  if [ "$(uname -s)" != "Darwin" ]; then
    macos_error "This runner is for macOS. Use docker compose on Linux/KVM hosts."
    return 1
  fi
}

macos_default_sdk_root() {
  printf '%s\n' "${HOME}/.dockerify-android/android-sdk"
}

macos_find_sdk_root() {
  local candidate

  for candidate in \
    "${ANDROID_HOME:-}" \
    "${ANDROID_SDK_ROOT:-}" \
    "${HOME}/Library/Android/sdk" \
    "$(macos_default_sdk_root)"; do
    [ -n "$candidate" ] || continue
    if [ -d "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

macos_configure_sdk_path() {
  local sdk_root

  sdk_root="$(macos_find_sdk_root)" || return 1
  export ANDROID_HOME="$sdk_root"
  export ANDROID_SDK_ROOT="$sdk_root"
  export PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/emulator:${ANDROID_HOME}/platform-tools:${PATH}"
}

macos_require_command() {
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    macos_error "Missing '${command_name}'. Run ./scripts/macos-bootstrap-sdk.sh or install Android SDK command-line tools."
    return 1
  fi
}

macos_host_abi() {
  case "$(uname -m)" in
    arm64) printf '%s\n' "arm64-v8a" ;;
    x86_64) printf '%s\n' "x86_64" ;;
    *)
      macos_error "Unsupported macOS CPU architecture: $(uname -m)"
      return 1
      ;;
  esac
}

macos_android_api_level() {
  printf '%s\n' "${PROFILE_ANDROID_API_LEVEL:-30}"
}

macos_system_image_api_level() {
  printf '%s\n' "$(macos_system_image_package)" | awk -F';' '{print $2}' | sed 's/^android-//'
}

macos_system_image_package() {
  local abi
  local api
  local profile_package

  abi="$(macos_host_abi)" || return 1
  api="$(macos_android_api_level)"
  case "$abi" in
    arm64-v8a) profile_package="${PROFILE_MACOS_SYSTEM_IMAGE_ARM64:-}" ;;
    x86_64) profile_package="${PROFILE_MACOS_SYSTEM_IMAGE_X86_64:-}" ;;
    *) profile_package="" ;;
  esac

  printf '%s\n' "${MACOS_SYSTEM_IMAGE:-${PROFILE_MACOS_SYSTEM_IMAGE:-${profile_package:-system-images;android-${api};google_apis;${abi}}}}"
}

macos_package_relpath() {
  printf '%s\n' "$1" | tr ';' '/'
}

macos_package_installed() {
  local package="$1"
  [ -d "${ANDROID_HOME}/$(macos_package_relpath "$package")" ]
}

macos_avd_name() {
  local name

  name="${MACOS_AVD_NAME:-${PROFILE_MACOS_AVD_NAME:-dockerify_${DEVICE_PROFILE}_$(macos_host_abi)}}"
  printf '%s\n' "$name" | sed 's/[^A-Za-z0-9_.-]/_/g'
}

macos_avd_home() {
  printf '%s\n' "${ANDROID_AVD_HOME:-${MACOS_AVD_HOME:-${HOME}/.android/avd}}"
}

macos_avd_dir() {
  printf '%s/%s.avd\n' "$(macos_avd_home)" "$1"
}

macos_boot_props_file() {
  printf '%s\n' "${MACOS_BOOT_PROPS_FILE:-${PROFILE_DIR}/props.macos-boot}"
}

macos_device_id() {
  local device_id

  device_id="${MACOS_DEVICE_ID:-${PROFILE_MACOS_DEVICE_ID:-}}"
  if [ -z "$device_id" ] && [ -f "$PROFILE_AVD" ]; then
    device_id="$(sed -n 's/^hw.device.name=//p' "$PROFILE_AVD" | head -1)"
  fi
  printf '%s\n' "${device_id:-pixel_5}"
}

macos_emulator_port() {
  printf '%s\n' "${MACOS_EMULATOR_PORT:-5584}"
}

macos_android_serial() {
  printf 'emulator-%s\n' "$(macos_emulator_port)"
}

macos_logs_dir() {
  printf '%s\n' "${MACOS_LOGS_DIR:-${HOME}/.dockerify-android/logs}"
}

macos_pid_file() {
  printf '%s/%s.pid\n' "$(macos_logs_dir)" "$(macos_avd_name)"
}

macos_launchd_dir() {
  printf '%s\n' "${MACOS_LAUNCHD_DIR:-${HOME}/.dockerify-android/launchd}"
}

macos_launchd_label() {
  local name

  name="$(macos_avd_name)"
  printf 'com.dockerify-android.%s\n' "$(printf '%s\n' "$name" | sed 's/[^A-Za-z0-9_.-]/_/g')"
}

macos_launchd_domain() {
  printf 'gui/%s\n' "$(id -u)"
}

macos_launchd_plist() {
  printf '%s/%s.plist\n' "$(macos_launchd_dir)" "$(macos_launchd_label)"
}

macos_launchd_job() {
  printf '%s/%s\n' "$(macos_launchd_domain)" "$(macos_launchd_label)"
}

macos_serial_online() {
  local serial="$1"

  adb devices | awk -v serial="$serial" '$1 == serial && $2 == "device" { found = 1 } END { exit found ? 0 : 1 }'
}

macos_wait_for_serial() {
  local serial="$1"
  local timeout="${MACOS_ADB_TIMEOUT:-120}"
  local waited=0
  local pid_file="${2:-}"
  local pid=""

  if [ -n "$pid_file" ] && [ -f "$pid_file" ]; then
    pid="$(cat "$pid_file")"
  fi

  while ! macos_serial_online "$serial"; do
    if [ -n "$pid" ] && ! kill -0 "$pid" >/dev/null 2>&1; then
      macos_error "Emulator process ${pid} exited before ${serial} registered with adb"
      adb devices -l >&2 || true
      return 1
    fi
    sleep 2
    waited=$((waited + 2))
    if [ "$waited" -ge "$timeout" ]; then
      macos_error "Timed out waiting for ${serial} to register with adb"
      adb devices -l >&2 || true
      return 1
    fi
  done
}

macos_wait_for_boot() {
  local serial="$1"
  local timeout="${MACOS_BOOT_TIMEOUT:-300}"
  local waited=0
  local completed

  macos_wait_for_serial "$serial" "${2:-}"
  completed="$(adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
  while [ "$completed" != "1" ]; do
    sleep 5
    waited=$((waited + 5))
    if [ "$waited" -ge "$timeout" ]; then
      macos_error "Timed out waiting for ${serial} to finish booting"
      return 1
    fi
    completed="$(adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
  done
}

macos_load_profile() {
  load_device_profile
  export ANDROID_API_LEVEL="${ANDROID_API_LEVEL:-$(macos_system_image_api_level)}"
  export ANDROID_RELEASE="${ANDROID_RELEASE:-${PROFILE_ANDROID_RELEASE:-}}"
  profile_validate_android_version || return 1
}
