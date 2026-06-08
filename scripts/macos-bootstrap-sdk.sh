#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/macos-env.sh"

macos_require_darwin
macos_load_profile

SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$(macos_default_sdk_root)}}"
CMDLINE_TOOLS_VERSION="${CMDLINE_TOOLS_VERSION:-13114758}"
CMDLINE_TOOLS_URL="${CMDLINE_TOOLS_URL:-https://dl.google.com/android/repository/commandlinetools-mac-${CMDLINE_TOOLS_VERSION}_latest.zip}"
SYSTEM_IMAGE="$(macos_system_image_package)"
API_LEVEL="$(macos_system_image_api_level)"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

run_sdkmanager_with_yes() {
  local rc

  set +o pipefail
  yes | sdkmanager --sdk_root="$ANDROID_HOME" "$@"
  rc=$?
  set -o pipefail
  return "$rc"
}

macos_log "Installing Android SDK command-line tools into ${SDK_ROOT}"
mkdir -p "${SDK_ROOT}/cmdline-tools"

if [ ! -x "${SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager" ]; then
  macos_log "Downloading ${CMDLINE_TOOLS_URL}"
  curl -fL "$CMDLINE_TOOLS_URL" -o "${TMP_DIR}/cmdline-tools.zip"
  rm -rf "${SDK_ROOT}/cmdline-tools/latest"
  mkdir -p "${SDK_ROOT}/cmdline-tools/latest"
  unzip -q "${TMP_DIR}/cmdline-tools.zip" -d "$TMP_DIR"
  if [ -d "${TMP_DIR}/cmdline-tools" ]; then
    cp -R "${TMP_DIR}/cmdline-tools/." "${SDK_ROOT}/cmdline-tools/latest/"
  else
    macos_error "Unexpected command-line tools archive layout"
    exit 1
  fi
else
  macos_log "Command-line tools already installed"
fi

export ANDROID_HOME="$SDK_ROOT"
export ANDROID_SDK_ROOT="$SDK_ROOT"
export PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/emulator:${ANDROID_HOME}/platform-tools:${PATH}"

macos_log "Accepting Android SDK licenses"
run_sdkmanager_with_yes --licenses

macos_log "Installing emulator, platform-tools, platform android-${API_LEVEL}, and ${SYSTEM_IMAGE}"
run_sdkmanager_with_yes \
  "emulator" \
  "platform-tools" \
  "platforms;android-${API_LEVEL}" \
  "$SYSTEM_IMAGE"

macos_log "SDK bootstrap complete"
"${SCRIPT_DIR}/macos-doctor.sh"
