#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/macos-env.sh"

macos_require_darwin
macos_load_profile
macos_configure_sdk_path || {
  macos_error "Android SDK not found. Run ./scripts/macos-bootstrap-sdk.sh first."
  exit 1
}
macos_require_command sdkmanager
macos_require_command avdmanager
macos_require_command emulator
macos_require_command adb

AVD_NAME="$(macos_avd_name)"
AVD_DIR="$(macos_avd_dir "$AVD_NAME")"
SYSTEM_IMAGE="$(macos_system_image_package)"
DEVICE_ID="$(macos_device_id)"
PORT="$(macos_emulator_port)"
SERIAL="$(macos_android_serial)"
LOGS_DIR="$(macos_logs_dir)"
PID_FILE="$(macos_pid_file)"
LOG_FILE="${LOGS_DIR}/${AVD_NAME}.log"
LAUNCHD_LABEL="$(macos_launchd_label)"
LAUNCHD_PLIST="$(macos_launchd_plist)"
LAUNCHD_JOB="$(macos_launchd_job)"

create_avd_if_needed() {
  if [ -d "$AVD_DIR" ]; then
    macos_log "Using existing AVD ${AVD_NAME}"
    return 0
  fi

  if ! macos_package_installed "$SYSTEM_IMAGE"; then
    macos_error "System image is not installed: ${SYSTEM_IMAGE}"
    macos_error "Run ./scripts/macos-bootstrap-sdk.sh first."
    return 1
  fi

  macos_log "Creating AVD ${AVD_NAME} with ${SYSTEM_IMAGE}"
  mkdir -p "$(macos_avd_home)"
  echo "no" | avdmanager create avd \
    -n "$AVD_NAME" \
    -k "$SYSTEM_IMAGE" \
    -d "$DEVICE_ID" \
    --force
}

apply_avd_profile() {
  local config_file="${AVD_DIR}/config.ini"

  if [ ! -f "$config_file" ]; then
    macos_error "AVD config not found: ${config_file}"
    return 1
  fi

  profile_apply_avd_config "$config_file"
  profile_update_ini "$config_file" "fastboot.forceColdBoot" "yes"
  profile_update_ini "$config_file" "fastboot.forceFastBoot" "no"
  profile_update_ini "$config_file" "fastboot.forceChosenSnapshotBoot" "no"
  profile_update_ini "$config_file" "firstboot.bootFromDownloadableSnapshot" "no"
  profile_update_ini "$config_file" "firstboot.bootFromLocalSnapshot" "no"
  profile_update_ini "$config_file" "firstboot.saveToLocalSnapshot" "no"
}

emulator_running() {
  macos_serial_online "$SERIAL"
}

plist_escape() {
  printf '%s\n' "$1" \
    | sed \
      -e 's/&/\&amp;/g' \
      -e 's/</\&lt;/g' \
      -e 's/>/\&gt;/g' \
      -e "s/'/\&apos;/g" \
      -e 's/"/\&quot;/g'
}

append_plist_string() {
  printf '    <string>%s</string>\n' "$(plist_escape "$1")" >> "$LAUNCHD_PLIST"
}

append_macos_boot_props() {
  local props_file
  local key
  local value
  local line

  props_file="$(macos_boot_props_file)"
  [ -s "$props_file" ] || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    case "$line" in
      ""|\#*) continue ;;
    esac
    key="${line%%=*}"
    value="${line#*=}"
    key="$(printf '%s' "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    value="$(printf '%s' "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [ "${#key}" -gt 32 ] || [ "${#value}" -gt 92 ]; then
      macos_log "Skipping boot prop outside emulator -prop limits: ${key}"
      continue
    fi
    append_plist_string "-prop"
    append_plist_string "${key}=${value}"
  done < "$props_file"
}

adb_setprop_if_set() {
  local key="$1"
  local value="$2"

  [ -n "$value" ] || return 0
  adb -s "$SERIAL" shell "setprop ${key} $(profile_shell_quote "$value")" >/dev/null 2>&1 || true
}

launchd_job_loaded() {
  launchctl print "$LAUNCHD_JOB" >/dev/null 2>&1
}

unload_launchd_job() {
  if launchd_job_loaded; then
    launchctl bootout "$LAUNCHD_JOB" >/dev/null 2>&1 || true
  fi
}

write_launchd_plist() {
  local adb_path
  local emulator_path
  local sdk_tools_path
  local window_arg="-no-window"
  local wipe_arg=""

  adb_path="$(command -v adb)"
  emulator_path="$(command -v emulator)"
  sdk_tools_path="${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/emulator:${ANDROID_HOME}/platform-tools:/usr/bin:/bin:/usr/sbin:/sbin"

  if [ "${MACOS_WIPE_DATA:-0}" = "1" ]; then
    wipe_arg="-wipe-data"
  fi

  if [ "${MACOS_NO_WINDOW:-1}" != "1" ]; then
    window_arg=""
  fi

  mkdir -p "$(dirname "$LAUNCHD_PLIST")" "$LOGS_DIR"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0">'
    printf '%s\n' '<dict>'
    printf '  <key>Label</key><string>%s</string>\n' "$(plist_escape "$LAUNCHD_LABEL")"
    printf '%s\n' '  <key>RunAtLoad</key><true/>'
    printf '%s\n' '  <key>KeepAlive</key><false/>'
    printf '%s\n' '  <key>EnvironmentVariables</key>'
    printf '%s\n' '  <dict>'
    printf '    <key>ANDROID_HOME</key><string>%s</string>\n' "$(plist_escape "$ANDROID_HOME")"
    printf '    <key>ANDROID_SDK_ROOT</key><string>%s</string>\n' "$(plist_escape "$ANDROID_SDK_ROOT")"
    printf '    <key>ANDROID_AVD_HOME</key><string>%s</string>\n' "$(plist_escape "$(macos_avd_home)")"
    printf '    <key>PATH</key><string>%s</string>\n' "$(plist_escape "$sdk_tools_path")"
    printf '%s\n' '  </dict>'
    printf '%s\n' '  <key>ProgramArguments</key>'
    printf '%s\n' '  <array>'
  } > "$LAUNCHD_PLIST"

  append_plist_string "$emulator_path"
  append_plist_string "-avd"
  append_plist_string "$AVD_NAME"
  append_plist_string "-port"
  append_plist_string "$PORT"
  append_plist_string "-no-snapshot"
  if [ -n "$window_arg" ]; then
    append_plist_string "$window_arg"
  fi
  append_plist_string "-no-boot-anim"
  append_plist_string "-no-audio"
  append_plist_string "-gpu"
  append_plist_string "swiftshader_indirect"
  append_plist_string "-netfast"
  append_plist_string "-adb-path"
  append_plist_string "$adb_path"
  append_macos_boot_props
  if [ -n "$wipe_arg" ]; then
    append_plist_string "$wipe_arg"
  fi
  if [ -n "${MACOS_EMULATOR_EXTRA_ARGS:-}" ]; then
    # shellcheck disable=SC2206
    local extra_args=(${MACOS_EMULATOR_EXTRA_ARGS})
    local arg
    for arg in "${extra_args[@]}"; do
      append_plist_string "$arg"
    done
  fi

  {
    printf '%s\n' '  </array>'
    printf '  <key>StandardOutPath</key><string>%s</string>\n' "$(plist_escape "$LOG_FILE")"
    printf '  <key>StandardErrorPath</key><string>%s</string>\n' "$(plist_escape "$LOG_FILE")"
    printf '  <key>WorkingDirectory</key><string>%s</string>\n' "$(plist_escape "$REPO_ROOT")"
    printf '%s\n' '</dict>'
    printf '%s\n' '</plist>'
  } >> "$LAUNCHD_PLIST"
}

start_emulator() {
  mkdir -p "$LOGS_DIR"
  if [ "${MACOS_WIPE_DATA:-0}" = "1" ] && emulator_running; then
    macos_log "Stopping running ${SERIAL} before wipe-data start"
    adb -s "$SERIAL" emu kill >/dev/null 2>&1 || true
    for _ in $(seq 1 30); do
      if ! emulator_running; then
        break
      fi
      sleep 1
    done
  fi

  if emulator_running; then
    macos_log "${SERIAL} is already running"
    return 0
  fi

  macos_log "Starting ${AVD_NAME} on ${SERIAL}"
  unload_launchd_job
  write_launchd_plist
  launchctl bootstrap "$(macos_launchd_domain)" "$LAUNCHD_PLIST"
  sleep 1
  launchctl print "$LAUNCHD_JOB" 2>/dev/null | awk '/pid = / { print $3; exit }' > "$PID_FILE" || true
  macos_log "Emulator log: ${LOG_FILE}"
}

apply_runtime_profile() {
  local adb_base=(adb -s "$SERIAL")
  local quoted_value

  macos_log "Waiting for Android boot completion"
  macos_wait_for_boot "$SERIAL" "$PID_FILE"

  if [ -n "${SCREEN_RESOLUTION:-${PROFILE_SCREEN_RESOLUTION:-}}" ]; then
    "${adb_base[@]}" shell wm size "${SCREEN_RESOLUTION:-${PROFILE_SCREEN_RESOLUTION:-}}" >/dev/null 2>&1 || true
  fi

  if [ -n "${SCREEN_DENSITY:-${PROFILE_SCREEN_DENSITY:-}}" ]; then
    "${adb_base[@]}" shell wm density "${SCREEN_DENSITY:-${PROFILE_SCREEN_DENSITY:-}}" >/dev/null 2>&1 || true
  fi

  if [ -n "${PROFILE_TIMEZONE:-}" ]; then
    "${adb_base[@]}" shell setprop persist.sys.timezone "$PROFILE_TIMEZONE" >/dev/null 2>&1 || true
    "${adb_base[@]}" shell service call alarm 3 s16 "$PROFILE_TIMEZONE" >/dev/null 2>&1 || true
    "${adb_base[@]}" shell settings put global auto_time_zone 0 || true
  fi

  if [ -n "${PROFILE_LOCALE:-}" ]; then
    "${adb_base[@]}" shell setprop persist.sys.locale "$PROFILE_LOCALE" >/dev/null 2>&1 || true
  fi

  if [ -n "${PROFILE_DEVICE_NAME:-}" ]; then
    quoted_value="$(profile_shell_quote "$PROFILE_DEVICE_NAME")"
    "${adb_base[@]}" shell "settings put global device_name ${quoted_value}" || true
    "${adb_base[@]}" shell "settings put secure bluetooth_name ${quoted_value}" || true
  fi

  if [ -n "${PROFILE_AUTO_TIME:-}" ]; then
    "${adb_base[@]}" shell settings put global auto_time "$PROFILE_AUTO_TIME" || true
  fi

  if [ -n "${PROFILE_AUTO_TIME_ZONE:-}" ]; then
    "${adb_base[@]}" shell settings put global auto_time_zone "$PROFILE_AUTO_TIME_ZONE" || true
  fi

  if [ -n "${PROFILE_ACCELEROMETER_ROTATION:-}" ]; then
    "${adb_base[@]}" shell settings put system accelerometer_rotation "$PROFILE_ACCELEROMETER_ROTATION" || true
  fi

  if [ -n "${PROFILE_WINDOW_ANIMATION_SCALE:-}" ]; then
    "${adb_base[@]}" shell settings put global window_animation_scale "$PROFILE_WINDOW_ANIMATION_SCALE" || true
  fi

  if [ -n "${PROFILE_TRANSITION_ANIMATION_SCALE:-}" ]; then
    "${adb_base[@]}" shell settings put global transition_animation_scale "$PROFILE_TRANSITION_ANIMATION_SCALE" || true
  fi

  if [ -n "${PROFILE_ANIMATOR_DURATION_SCALE:-}" ]; then
    "${adb_base[@]}" shell settings put global animator_duration_scale "$PROFILE_ANIMATOR_DURATION_SCALE" || true
  fi

  if [ -n "${PROFILE_STAY_ON_WHILE_PLUGGED_IN:-}" ]; then
    "${adb_base[@]}" shell settings put global stay_on_while_plugged_in "$PROFILE_STAY_ON_WHILE_PLUGGED_IN" || true
  fi

  if [ -n "${PROFILE_SCREEN_OFF_TIMEOUT_MS:-}" ]; then
    "${adb_base[@]}" shell settings put system screen_off_timeout "$PROFILE_SCREEN_OFF_TIMEOUT_MS" || true
  fi

  if [ -n "${PROFILE_AIRPLANE_MODE:-}" ]; then
    "${adb_base[@]}" shell settings put global airplane_mode_on "$PROFILE_AIRPLANE_MODE" || true
    if [ "$PROFILE_AIRPLANE_MODE" = "1" ]; then
      "${adb_base[@]}" shell am broadcast -a android.intent.action.AIRPLANE_MODE --ez state true >/dev/null 2>&1 || true
    else
      "${adb_base[@]}" shell am broadcast -a android.intent.action.AIRPLANE_MODE --ez state false >/dev/null 2>&1 || true
    fi
  fi

  if [ -n "${PROFILE_WIFI_ENABLED:-}" ]; then
    if [ "$PROFILE_WIFI_ENABLED" = "1" ]; then
      "${adb_base[@]}" shell svc wifi enable || true
    else
      "${adb_base[@]}" shell svc wifi disable || true
    fi
  fi

  if [ -n "${PROFILE_MOBILE_DATA_ENABLED:-}" ]; then
    if [ "$PROFILE_MOBILE_DATA_ENABLED" = "1" ]; then
      "${adb_base[@]}" shell svc data enable || true
    else
      "${adb_base[@]}" shell svc data disable || true
    fi
  fi

  if [ -n "${PROFILE_LOCATION_MODE:-}" ]; then
    "${adb_base[@]}" shell settings put secure location_mode "$PROFILE_LOCATION_MODE" || true
  fi

  adb_setprop_if_set "gsm.version.baseband" "${PROFILE_BASEBAND_VERSION:-}"
  adb_setprop_if_set "gsm.current.phone-type" "${PROFILE_GSM_CURRENT_PHONE_TYPE:-}"
  adb_setprop_if_set "gsm.network.type" "${PROFILE_GSM_NETWORK_TYPE:-}"
  adb_setprop_if_set "gsm.operator.alpha" "${PROFILE_GSM_OPERATOR_ALPHA:-}"
  adb_setprop_if_set "gsm.operator.numeric" "${PROFILE_GSM_OPERATOR_NUMERIC:-}"
  adb_setprop_if_set "gsm.operator.iso-country" "${PROFILE_GSM_OPERATOR_ISO_COUNTRY:-}"
  adb_setprop_if_set "gsm.operator.isroaming" "${PROFILE_GSM_OPERATOR_ISROAMING:-}"
  adb_setprop_if_set "gsm.sim.operator.alpha" "${PROFILE_GSM_SIM_OPERATOR_ALPHA:-}"
  adb_setprop_if_set "gsm.sim.operator.numeric" "${PROFILE_GSM_SIM_OPERATOR_NUMERIC:-}"
  adb_setprop_if_set "gsm.sim.operator.iso-country" "${PROFILE_GSM_SIM_OPERATOR_ISO_COUNTRY:-}"
  adb_setprop_if_set "gsm.sim.state" "${PROFILE_GSM_SIM_STATE:-}"

  if [ -n "${PROFILE_BATTERY_LEVEL:-}" ]; then
    "${adb_base[@]}" shell dumpsys battery set level "$PROFILE_BATTERY_LEVEL" || true
  fi

  if [ -n "${PROFILE_BATTERY_STATUS:-}" ]; then
    "${adb_base[@]}" shell dumpsys battery set status "$PROFILE_BATTERY_STATUS" || true
  fi

  if [ -n "${PROFILE_BATTERY_AC:-}" ]; then
    "${adb_base[@]}" shell dumpsys battery set ac "$PROFILE_BATTERY_AC" || true
  fi

  if [ -f "$PROFILE_SETTINGS" ]; then
    macos_log "Running custom settings script: ${PROFILE_SETTINGS}"
    DEVICE_PROFILE="$DEVICE_PROFILE" PROFILE_DIR="$PROFILE_DIR" ANDROID_SERIAL="$SERIAL" bash "$PROFILE_SETTINGS"
  fi

  macos_log "macOS profile runtime settings applied"
}

create_avd_if_needed
apply_avd_profile
start_emulator
apply_runtime_profile

macos_log "Ready: ${SERIAL}"
