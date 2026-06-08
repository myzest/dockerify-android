#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/macos-env.sh"

status=0

check_ok() {
  printf '[ok] %s\n' "$1"
}

check_fail() {
  printf '[missing] %s\n' "$1"
  status=1
}

macos_require_darwin || exit 1
macos_load_profile || exit 1

echo "=== Dockerify Android macOS Doctor ==="
echo "profile=${DEVICE_PROFILE}"
echo "label=${DEVICE_PROFILE_LABEL}"
echo "host_arch=$(uname -m)"
echo "preferred_abi=$(macos_host_abi)"
echo "system_image=$(macos_system_image_package)"
echo

if macos_configure_sdk_path; then
  check_ok "Android SDK root: ${ANDROID_HOME}"
else
  check_fail "Android SDK root. Run ./scripts/macos-bootstrap-sdk.sh"
fi

for command_name in sdkmanager avdmanager emulator adb; do
  if command -v "$command_name" >/dev/null 2>&1; then
    check_ok "${command_name}: $(command -v "$command_name")"
  else
    check_fail "$command_name"
  fi
done

if [ -n "${ANDROID_HOME:-}" ]; then
  package="$(macos_system_image_package)"
  if macos_package_installed "$package"; then
    check_ok "system image installed: ${package}"
  else
    check_fail "system image not installed: ${package}"
  fi
fi

echo
if [ "$status" -eq 0 ]; then
  echo "macOS runner prerequisites look ready."
else
  echo "Some prerequisites are missing. Run ./scripts/macos-bootstrap-sdk.sh, then re-run this doctor."
fi

exit "$status"
