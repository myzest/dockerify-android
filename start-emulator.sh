#!/bin/bash

PROFILE_LIB="/opt/dockerify-android/scripts/profile-lib.sh"
if [ -f "$PROFILE_LIB" ]; then
  . "$PROFILE_LIB"
  load_device_profile
fi

require_kvm() {
  if [ "${ALLOW_NO_KVM:-0}" = "1" ]; then
    return 0
  fi
  if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    return 0
  fi

  cat >&2 <<'EOF'
KVM is required to boot the default x86_64 Android emulator image.
/dev/kvm is not available inside this container. On Docker Desktop for macOS,
the Docker Linux VM usually does not expose KVM to containers, so the emulator
cannot complete first boot with the default profile.

Run this image on a Linux host with KVM exposed, or set ALLOW_NO_KVM=1 only when
using a system image that can boot without KVM.
EOF
  exit 78
}

# Kill any running emulator instances before starting a new one
pkill -f "/opt/android-sdk/emulator/emulator"

# Removes .lock files before emulator starts to prevent crashes
rm -rf /data/android.avd/*.lock

# Use custom ramdisk if present
if [ -f /data/android.avd/ramdisk.img ]; then
  RAMDISK="-ramdisk /data/android.avd/ramdisk.img"
fi

# Path to the AVD config
CONFIG_FILE="/data/android.avd/config.ini"

update_config() {
  local key="$1"
  local value="$2"
  if grep -q "^$key=" "$CONFIG_FILE"; then
    sed -i "s/^$key=.*/$key=$value/" "$CONFIG_FILE"
  else
    echo "$key=$value" >> "$CONFIG_FILE"
  fi
}

# Configure optional profile and environment values directly via config.ini
if [ -f "$CONFIG_FILE" ]; then
  if type profile_apply_avd_config >/dev/null 2>&1; then
    profile_apply_avd_config "$CONFIG_FILE"
  else
    if [ -n "$SCREEN_RESOLUTION" ]; then
      WIDTH=${SCREEN_RESOLUTION%x*}
      HEIGHT=${SCREEN_RESOLUTION#*x}
      update_config "hw.lcd.width" "$WIDTH"
      update_config "hw.lcd.height" "$HEIGHT"
    fi
    if [ -n "$SCREEN_DENSITY" ]; then
      update_config "hw.lcd.density" "$SCREEN_DENSITY"
    fi
  fi
fi

require_kvm

# Start the emulator with the appropriate ramdisk.img
/opt/android-sdk/emulator/emulator -avd android -nojni -netfast -writable-system -no-window -no-audio -no-boot-anim -skip-adb-auth -gpu swiftshader_indirect -no-snapshot -no-metrics $RAMDISK -qemu -m ${RAM_SIZE:-4096}
