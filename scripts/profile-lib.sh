#!/bin/bash

PROFILE_ROOT="${PROFILE_ROOT:-/opt/dockerify-android/profiles}"
DEVICE_PROFILE="${DEVICE_PROFILE:-pixel_5_android_11}"
PROFILE_DIR="${PROFILE_ROOT}/${DEVICE_PROFILE}"
PROFILE_ENV="${PROFILE_DIR}/profile.env"
PROFILE_PROPS="${PROFILE_DIR}/props.system"
PROFILE_OPTIONAL_PROPS="${PROFILE_DIR}/props.optional"
PROFILE_AVD="${PROFILE_DIR}/avd.ini"
PROFILE_SETTINGS="${PROFILE_DIR}/settings.sh"
PROFILE_STATE_FILE="${PROFILE_STATE_FILE:-/data/.device-profile-state}"
PROFILE_LOADED=false

profile_log() {
  echo "[profile] $*"
}

profile_shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

profile_adb_setprop_if_set() {
  local key="$1"
  local value="$2"

  [ -n "$value" ] || return 0
  adb shell "setprop ${key} $(profile_shell_quote "$value")" || true
}

profile_require() {
  if [ ! -d "$PROFILE_DIR" ]; then
    echo "[profile] Unknown DEVICE_PROFILE=${DEVICE_PROFILE}" >&2
    echo "[profile] Expected a directory at ${PROFILE_DIR}" >&2
    exit 1
  fi
}

load_device_profile() {
  if [ "$PROFILE_LOADED" = true ]; then
    return 0
  fi

  profile_require
  if [ -f "$PROFILE_ENV" ]; then
    set -a
    . "$PROFILE_ENV"
    set +a
  fi

  DEVICE_PROFILE_LABEL="${DEVICE_PROFILE_LABEL:-$DEVICE_PROFILE}"
  if [ -z "${RAM_SIZE:-}" ] && [ -n "${PROFILE_RAM_SIZE:-}" ]; then
    export RAM_SIZE="$PROFILE_RAM_SIZE"
  fi
  if [ -z "${SCREEN_RESOLUTION:-}" ] && [ -n "${PROFILE_SCREEN_RESOLUTION:-}" ]; then
    export SCREEN_RESOLUTION="$PROFILE_SCREEN_RESOLUTION"
  fi
  if [ -z "${SCREEN_DENSITY:-}" ] && [ -n "${PROFILE_SCREEN_DENSITY:-}" ]; then
    export SCREEN_DENSITY="$PROFILE_SCREEN_DENSITY"
  fi
  if [ -z "${DNS:-}" ] && [ -n "${PROFILE_DNS:-}" ]; then
    export DNS="$PROFILE_DNS"
  fi

  PROFILE_LOADED=true
  profile_log "Loaded ${DEVICE_PROFILE_LABEL} (${DEVICE_PROFILE})"
}

profile_validate_android_version() {
  load_device_profile

  if [ -n "${PROFILE_ANDROID_API_LEVEL:-}" ] &&
     [ -n "${ANDROID_API_LEVEL:-}" ] &&
     [ "$PROFILE_ANDROID_API_LEVEL" != "$ANDROID_API_LEVEL" ]; then
    echo "[profile] ${DEVICE_PROFILE} expects Android API ${PROFILE_ANDROID_API_LEVEL}, but image API is ${ANDROID_API_LEVEL}" >&2
    return 1
  fi

  if [ -n "${PROFILE_ANDROID_RELEASE:-}" ] &&
     [ -n "${ANDROID_RELEASE:-}" ] &&
     [ "$PROFILE_ANDROID_RELEASE" != "$ANDROID_RELEASE" ]; then
    echo "[profile] ${DEVICE_PROFILE} expects Android ${PROFILE_ANDROID_RELEASE}, but image release is ${ANDROID_RELEASE}" >&2
    return 1
  fi
}

profile_update_ini() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp

  mkdir -p "$(dirname "$file")"
  touch "$file"
  tmp="$(mktemp)"
  awk -F= -v key="$key" -v value="$value" '
    BEGIN { done = 0 }
    $1 == key {
      print key "=" value
      done = 1
      next
    }
    { print }
    END {
      if (!done) {
        print key "=" value
      }
    }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

profile_apply_avd_config() {
  local config_file="${1:-/data/android.avd/config.ini}"
  local resolution
  local width
  local height

  load_device_profile
  if [ ! -f "$config_file" ]; then
    profile_log "AVD config not found yet: ${config_file}"
    return 0
  fi

  resolution="${SCREEN_RESOLUTION:-${PROFILE_SCREEN_RESOLUTION:-}}"
  if [ -n "$resolution" ]; then
    width="${resolution%x*}"
    height="${resolution#*x}"
    if [ -n "$width" ] && [ -n "$height" ] && [ "$width" != "$resolution" ]; then
      profile_update_ini "$config_file" "hw.lcd.width" "$width"
      profile_update_ini "$config_file" "hw.lcd.height" "$height"
    fi
  fi

  if [ -n "${SCREEN_DENSITY:-${PROFILE_SCREEN_DENSITY:-}}" ]; then
    profile_update_ini "$config_file" "hw.lcd.density" "${SCREEN_DENSITY:-${PROFILE_SCREEN_DENSITY:-}}"
  fi

  if [ -n "${RAM_SIZE:-${PROFILE_RAM_SIZE:-}}" ]; then
    profile_update_ini "$config_file" "hw.ramSize" "${RAM_SIZE:-${PROFILE_RAM_SIZE:-}}"
  fi

  if [ -f "$PROFILE_AVD" ]; then
    while IFS='=' read -r key value || [ -n "$key" ]; do
      key="$(printf '%s' "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      value="$(printf '%s' "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      case "$key" in
        ""|\#*) continue ;;
      esac
      profile_update_ini "$config_file" "$key" "$value"
    done < "$PROFILE_AVD"
  fi

  profile_log "Applied AVD config to ${config_file}"
}

profile_has_system_props() {
  [ -s "$PROFILE_PROPS" ] || [ -s "$PROFILE_OPTIONAL_PROPS" ]
}

profile_props_files() {
  [ -s "$PROFILE_PROPS" ] && printf '%s\n' "$PROFILE_PROPS"
  [ -s "$PROFILE_OPTIONAL_PROPS" ] && printf '%s\n' "$PROFILE_OPTIONAL_PROPS"
}

profile_write_combined_props() {
  local output_file="$1"
  local props_file

  : > "$output_file"
  while IFS= read -r props_file; do
    {
      echo ""
      echo "# Dockerify Android profile source: $(basename "$props_file")"
      cat "$props_file"
    } >> "$output_file"
  done < <(profile_props_files)
}

profile_props_signature() {
  local props_file

  profile_has_system_props || return 1
  {
    printf '%s\n' "$DEVICE_PROFILE"
    [ -f "$PROFILE_ENV" ] && sha256sum "$PROFILE_ENV"
    while IFS= read -r props_file; do
      sha256sum "$props_file"
    done < <(profile_props_files)
  } | sha256sum | awk '{print $1}'
}

profile_needs_system_props() {
  local signature

  load_device_profile
  profile_has_system_props || return 1
  signature="$(profile_props_signature)"
  [ -n "$signature" ] || return 1

  if [ -f "$PROFILE_STATE_FILE" ] &&
     grep -qx "DEVICE_PROFILE=${DEVICE_PROFILE}" "$PROFILE_STATE_FILE" &&
     grep -qx "PROPS_SIGNATURE=${signature}" "$PROFILE_STATE_FILE"; then
    return 1
  fi

  return 0
}

profile_mark_system_props_applied() {
  local signature
  local keys

  load_device_profile
  signature="$(profile_props_signature || true)"
  keys="$(profile_property_keys || true)"
  {
    echo "DEVICE_PROFILE=${DEVICE_PROFILE}"
    echo "DEVICE_PROFILE_LABEL=${DEVICE_PROFILE_LABEL}"
    echo "PROPS_SIGNATURE=${signature}"
    echo "PROPS_KEYS=${keys}"
  } > "$PROFILE_STATE_FILE"
}

profile_property_keys() {
  local props_file

  while IFS= read -r props_file; do
    grep -vE '^[[:space:]]*($|#)' "$props_file" | awk -F= '{print $1}'
  done < <(profile_props_files) | tr '\n' ' '
}

profile_previous_property_keys() {
  if [ -f "$PROFILE_STATE_FILE" ]; then
    sed -n 's/^PROPS_KEYS=//p' "$PROFILE_STATE_FILE"
  fi
}

profile_combined_property_keys() {
  {
    profile_previous_property_keys
    profile_property_keys
  } | tr ' ' '\n' | sed '/^$/d' | sort -u | tr '\n' ' '
}

profile_write_property_keys_file() {
  local output_file="$1"

  profile_combined_property_keys | tr ' ' '\n' | sed '/^$/d' > "$output_file"
}

profile_prepare_system() {
  adb wait-for-device || return 1
  adb root || return 1
  adb shell avbctl disable-verification || true
  adb disable-verity || return 1
  adb reboot || return 1
  adb wait-for-device || return 1
  adb root || return 1
  adb remount || return 1
}

profile_install_props_magisk() {
  local mod="/data/adb/modules/device_profile"
  local props_tmp

  profile_log "Installing device profile as a Magisk module"
  props_tmp="$(mktemp)"
  profile_write_combined_props "$props_tmp"
  adb push "$props_tmp" /data/local/tmp/device-profile-system.prop || {
    rm -f "$props_tmp"
    return 1
  }
  rm -f "$props_tmp"
  adb shell "
    set -e
    rm -rf ${mod}
    mkdir -p ${mod}
    cp /data/local/tmp/device-profile-system.prop ${mod}/system.prop
    cat > ${mod}/module.prop <<'PROP'
id=device_profile
name=Dockerify Android Device Profile
version=1
versionCode=1
author=dockerify-android
description=Applies the selected Dockerify Android test device profile
PROP
    chmod 0644 ${mod}/system.prop ${mod}/module.prop
    rm -f /data/local/tmp/device-profile-system.prop
  " || return 1
}

profile_install_props_system() {
  local safe_profile
  local props_tmp
  local keys_tmp

  profile_log "Installing device profile into system build properties"
  profile_prepare_system || return 1
  safe_profile="$(printf '%s' "$DEVICE_PROFILE" | sed 's/[^A-Za-z0-9_.-]/_/g')"
  props_tmp="$(mktemp)"
  keys_tmp="$(mktemp)"
  profile_write_combined_props "$props_tmp"
  profile_write_property_keys_file "$keys_tmp"
  adb push "$props_tmp" /data/local/tmp/device-profile.props || {
    rm -f "$props_tmp" "$keys_tmp"
    return 1
  }
  adb push "$keys_tmp" /data/local/tmp/device-profile.keys || {
    rm -f "$props_tmp" "$keys_tmp"
    adb shell rm -f /data/local/tmp/device-profile.props >/dev/null 2>&1 || true
    return 1
  }
  rm -f "$props_tmp" "$keys_tmp"
  adb shell "DEVICE_PROFILE='${safe_profile}' sh -s" <<'ANDROID_SH'
set -e

PROPS=/data/local/tmp/device-profile.props
KEYS=/data/local/tmp/device-profile.keys
TARGET=/system/build.prop
TMP=/data/local/tmp/device-profile.filtered

[ -s "$PROPS" ]
[ -s "$KEYS" ]
[ -w "$TARGET" ]

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
  filter_prop_file "$f" 2>/dev/null || true
done

{
  echo ""
  echo "# Dockerify Android device profile: ${DEVICE_PROFILE}"
  cat "$PROPS"
} >> "$TARGET"

rm -f "$PROPS" "$KEYS" "$TMP"
ANDROID_SH
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    adb shell rm -f /data/local/tmp/device-profile.props /data/local/tmp/device-profile.keys /data/local/tmp/device-profile.filtered >/dev/null 2>&1 || true
    return "$rc"
  fi

  return 0
}

profile_install_system_props() {
  local installed=false

  load_device_profile
  profile_has_system_props || return 0

  if [ "${PROFILE_FORCE_SYSTEM_PROPS:-0}" = "1" ]; then
    profile_install_props_system && installed=true
  elif type magisk_active >/dev/null 2>&1 && magisk_active; then
    profile_install_props_magisk && installed=true
  else
    profile_install_props_system && installed=true
  fi

  [ "$installed" = true ]
}

profile_verify_system_props() {
  local failed=false
  local key
  local expected
  local actual

  load_device_profile
  [ -s "$PROFILE_PROPS" ] || return 0
  profile_wait_for_boot
  adb root >/dev/null 2>&1 || true

  while IFS='=' read -r key expected || [ -n "$key" ]; do
    key="$(printf '%s' "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    case "$key" in
      ""|\#*) continue ;;
    esac
    expected="${expected%%#*}"
    expected="$(printf '%s' "$expected" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    actual="$(adb shell getprop "$key" </dev/null 2>/dev/null | tr -d '\r')"
    if [ "$actual" != "$expected" ]; then
      echo "[profile] property mismatch: ${key}: expected '${expected}', got '${actual}'" >&2
      failed=true
    fi
  done < "$PROFILE_PROPS"

  [ "$failed" = false ]
}

profile_wait_for_boot() {
  local completed
  local waited=0
  local timeout="${PROFILE_BOOT_TIMEOUT:-300}"

  adb wait-for-device
  completed="$(adb shell getprop sys.boot_completed | tr -d '\r')"
  while [ "$completed" != "1" ]; do
    sleep 5
    waited=$((waited + 5))
    if [ "$waited" -ge "$timeout" ]; then
      echo "[profile] Timed out waiting for Android boot completion" >&2
      return 1
    fi
    completed="$(adb shell getprop sys.boot_completed | tr -d '\r')"
  done
}

profile_apply_runtime_settings() {
  local completed

  load_device_profile
  profile_wait_for_boot
  adb root >/dev/null 2>&1 || true
  adb wait-for-device >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do
    completed="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
    [ "$completed" = "1" ] && break
    sleep 1
  done

  if [ -n "${PROFILE_TIMEZONE:-}" ]; then
    adb shell setprop persist.sys.timezone "$PROFILE_TIMEZONE" || true
    adb shell settings put global auto_time_zone 0 || true
  fi

  if [ -n "${PROFILE_LOCALE:-}" ]; then
    adb shell setprop persist.sys.locale "$PROFILE_LOCALE" || true
  fi

  if [ -n "${PROFILE_DEVICE_NAME:-}" ]; then
    adb shell "settings put global device_name $(profile_shell_quote "$PROFILE_DEVICE_NAME")" || true
    adb shell "settings put secure bluetooth_name $(profile_shell_quote "$PROFILE_DEVICE_NAME")" || true
  fi

  if [ -n "${PROFILE_AUTO_TIME:-}" ]; then
    adb shell settings put global auto_time "$PROFILE_AUTO_TIME" || true
  fi

  if [ -n "${PROFILE_AUTO_TIME_ZONE:-}" ]; then
    adb shell settings put global auto_time_zone "$PROFILE_AUTO_TIME_ZONE" || true
  fi

  if [ -n "${PROFILE_ACCELEROMETER_ROTATION:-}" ]; then
    adb shell settings put system accelerometer_rotation "$PROFILE_ACCELEROMETER_ROTATION" || true
  fi

  if [ -n "${PROFILE_WINDOW_ANIMATION_SCALE:-}" ]; then
    adb shell settings put global window_animation_scale "$PROFILE_WINDOW_ANIMATION_SCALE" || true
  fi

  if [ -n "${PROFILE_TRANSITION_ANIMATION_SCALE:-}" ]; then
    adb shell settings put global transition_animation_scale "$PROFILE_TRANSITION_ANIMATION_SCALE" || true
  fi

  if [ -n "${PROFILE_ANIMATOR_DURATION_SCALE:-}" ]; then
    adb shell settings put global animator_duration_scale "$PROFILE_ANIMATOR_DURATION_SCALE" || true
  fi

  if [ -n "${PROFILE_STAY_ON_WHILE_PLUGGED_IN:-}" ]; then
    adb shell settings put global stay_on_while_plugged_in "$PROFILE_STAY_ON_WHILE_PLUGGED_IN" || true
  fi

  if [ -n "${PROFILE_SCREEN_OFF_TIMEOUT_MS:-}" ]; then
    adb shell settings put system screen_off_timeout "$PROFILE_SCREEN_OFF_TIMEOUT_MS" || true
  fi

  if [ -n "${PROFILE_AIRPLANE_MODE:-}" ]; then
    adb shell settings put global airplane_mode_on "$PROFILE_AIRPLANE_MODE" || true
    if [ "$PROFILE_AIRPLANE_MODE" = "1" ]; then
      adb shell am broadcast -a android.intent.action.AIRPLANE_MODE --ez state true >/dev/null 2>&1 || true
    else
      adb shell am broadcast -a android.intent.action.AIRPLANE_MODE --ez state false >/dev/null 2>&1 || true
    fi
  fi

  if [ -n "${PROFILE_WIFI_ENABLED:-}" ]; then
    if [ "$PROFILE_WIFI_ENABLED" = "1" ]; then
      adb shell svc wifi enable || true
    else
      adb shell svc wifi disable || true
    fi
  fi

  if [ -n "${PROFILE_MOBILE_DATA_ENABLED:-}" ]; then
    if [ "$PROFILE_MOBILE_DATA_ENABLED" = "1" ]; then
      adb shell svc data enable || true
    else
      adb shell svc data disable || true
    fi
  fi

  if [ -n "${PROFILE_LOCATION_MODE:-}" ]; then
    adb shell settings put secure location_mode "$PROFILE_LOCATION_MODE" || true
  fi

  profile_adb_setprop_if_set "gsm.version.baseband" "${PROFILE_BASEBAND_VERSION:-}"
  profile_adb_setprop_if_set "gsm.current.phone-type" "${PROFILE_GSM_CURRENT_PHONE_TYPE:-}"
  profile_adb_setprop_if_set "gsm.network.type" "${PROFILE_GSM_NETWORK_TYPE:-}"
  profile_adb_setprop_if_set "gsm.operator.alpha" "${PROFILE_GSM_OPERATOR_ALPHA:-}"
  profile_adb_setprop_if_set "gsm.operator.numeric" "${PROFILE_GSM_OPERATOR_NUMERIC:-}"
  profile_adb_setprop_if_set "gsm.operator.iso-country" "${PROFILE_GSM_OPERATOR_ISO_COUNTRY:-}"
  profile_adb_setprop_if_set "gsm.operator.isroaming" "${PROFILE_GSM_OPERATOR_ISROAMING:-}"
  profile_adb_setprop_if_set "gsm.sim.operator.alpha" "${PROFILE_GSM_SIM_OPERATOR_ALPHA:-}"
  profile_adb_setprop_if_set "gsm.sim.operator.numeric" "${PROFILE_GSM_SIM_OPERATOR_NUMERIC:-}"
  profile_adb_setprop_if_set "gsm.sim.operator.iso-country" "${PROFILE_GSM_SIM_OPERATOR_ISO_COUNTRY:-}"
  profile_adb_setprop_if_set "gsm.sim.state" "${PROFILE_GSM_SIM_STATE:-}"

  if [ -n "${PROFILE_BATTERY_LEVEL:-}" ]; then
    adb shell dumpsys battery set level "$PROFILE_BATTERY_LEVEL" || true
  fi

  if [ -n "${PROFILE_BATTERY_STATUS:-}" ]; then
    adb shell dumpsys battery set status "$PROFILE_BATTERY_STATUS" || true
  fi

  if [ -n "${PROFILE_BATTERY_AC:-}" ]; then
    adb shell dumpsys battery set ac "$PROFILE_BATTERY_AC" || true
  fi

  profile_log "Applied runtime settings"
}

profile_run_custom_settings() {
  load_device_profile
  if [ -f "$PROFILE_SETTINGS" ]; then
    profile_log "Running custom settings script: ${PROFILE_SETTINGS}"
    DEVICE_PROFILE="$DEVICE_PROFILE" PROFILE_DIR="$PROFILE_DIR" bash "$PROFILE_SETTINGS"
  fi
}
