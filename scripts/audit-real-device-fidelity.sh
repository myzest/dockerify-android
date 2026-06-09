#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/profile-lib.sh"

load_device_profile

ADB=(adb)
if [ -n "${ANDROID_SERIAL:-}" ]; then
  ADB+=(-s "$ANDROID_SERIAL")
fi

AUDIT_SCOPE="${AUDIT_SCOPE:-}"
if [ -z "$AUDIT_SCOPE" ]; then
  AUDIT_SCOPE="docker"
  case "${ANDROID_SERIAL:-}" in
    emulator-*) AUDIT_SCOPE="macos-native" ;;
  esac
  if [ "${SCRIPT_DIR#/opt/dockerify-android/}" = "$SCRIPT_DIR" ] && [ "${ANDROID_SERIAL:-}" != "" ]; then
    AUDIT_SCOPE="macos-native"
  fi
fi

"${ADB[@]}" wait-for-device >/dev/null 2>&1 || true

pass_count=0
warn_count=0
info_count=0

emit_pass() {
  pass_count=$((pass_count + 1))
  printf '[pass] %s\n' "$*"
}

emit_warn() {
  warn_count=$((warn_count + 1))
  printf '[warn] %s\n' "$*"
}

emit_info() {
  info_count=$((info_count + 1))
  printf '[info] %s\n' "$*"
}

prop() {
  "${ADB[@]}" shell getprop "$1" </dev/null 2>/dev/null | tr -d '\r' | tail -n 1
}

setting() {
  "${ADB[@]}" shell settings get "$1" "$2" </dev/null 2>/dev/null | tr -d '\r' | tail -n 1
}

shell_out() {
  "${ADB[@]}" shell "$@" </dev/null 2>/dev/null | tr -d '\r'
}

check_expected_prop() {
  local key="$1"
  local expected="$2"
  local severity="${3:-warn}"
  local actual

  actual="$(prop "$key")"
  if [ "$actual" = "$expected" ]; then
    emit_pass "${key}=${actual}"
  else
    if [ "$severity" = "info" ]; then
      emit_info "${key}: expected '${expected}', got '${actual}'"
    else
      emit_warn "${key}: expected '${expected}', got '${actual}'"
    fi
  fi
}

check_expected_setting() {
  local namespace="$1"
  local key="$2"
  local expected="$3"
  local actual

  [ -n "$expected" ] || return 0
  actual="$(setting "$namespace" "$key")"
  if [ "$actual" = "$expected" ]; then
    emit_pass "settings ${namespace}.${key}=${actual}"
  else
    emit_warn "settings ${namespace}.${key}: expected '${expected}', got '${actual}'"
  fi
}

check_expected_runtime_prop() {
  local key="$1"
  local expected="$2"
  local severity="${3:-warn}"

  [ -n "$expected" ] || return 0
  check_expected_prop "$key" "$expected" "$severity"
}

check_expected_command_contains() {
  local label="$1"
  local expected="$2"
  shift 2
  local actual

  [ -n "$expected" ] || return 0
  actual="$("${ADB[@]}" shell "$@" </dev/null 2>/dev/null | tr -d '\r')"
  if printf '%s\n' "$actual" | grep -Fq "$expected"; then
    emit_pass "${label} contains ${expected}"
  else
    emit_warn "${label}: expected to contain '${expected}', got '${actual}'"
  fi
}

check_marker_prop() {
  local key="$1"
  local bad_pattern="$2"
  local label="$3"
  local actual

  actual="$(prop "$key")"
  if [ -z "$actual" ]; then
    emit_pass "${label}: ${key} is empty"
  elif printf '%s\n' "$actual" | grep -Eiq "$bad_pattern"; then
    emit_warn "${label}: ${key}=${actual}"
  else
    emit_pass "${label}: ${key}=${actual}"
  fi
}

check_marker_path() {
  local path="$1"
  local label="$2"

  if shell_out sh -c "test -e '$path' && echo present || echo missing" | grep -qx present; then
    emit_warn "${label}: ${path} exists"
  else
    emit_pass "${label}: ${path} missing"
  fi
}

profile_prop_parity() {
  local props_file="${1:-$PROFILE_PROPS}"
  local label="${2:-profile system props}"
  local severity="${3:-warn}"
  local total=0
  local matched=0
  local mismatched=0
  local key
  local expected
  local actual

  [ -s "$props_file" ] || {
    emit_info "No ${label} file: ${props_file}"
    return 0
  }

  while IFS='=' read -r key expected || [ -n "$key" ]; do
    key="$(printf '%s' "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    case "$key" in
      ""|\#*) continue ;;
    esac
    expected="${expected%%#*}"
    expected="$(printf '%s' "$expected" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    total=$((total + 1))
    actual="$(prop "$key")"
    if [ "$actual" = "$expected" ]; then
      matched=$((matched + 1))
    else
      mismatched=$((mismatched + 1))
      if [ "$severity" = "info" ]; then
        emit_info "${label} mismatch: ${key}: expected '${expected}', got '${actual}'"
      else
        emit_warn "${label} mismatch: ${key}: expected '${expected}', got '${actual}'"
      fi
    fi
  done < "$props_file"

  if [ "$mismatched" -eq 0 ]; then
    emit_pass "${label} parity: ${matched}/${total} matched"
  else
    if [ "$severity" = "info" ]; then
      emit_info "${label} parity: ${matched}/${total} matched, ${mismatched} best-effort mismatched"
    else
      emit_warn "${label} parity: ${matched}/${total} matched, ${mismatched} mismatched"
    fi
  fi
}

check_runtime_identity() {
  local identity_severity="warn"

  if [ "$AUDIT_SCOPE" = "macos-native" ]; then
    identity_severity="info"
  fi

  echo "--- Runtime identity ---"
  emit_info "reference mapping: brand=${PROFILE_REFERENCE_BRAND:-${PROFILE_MANUFACTURER:-}} device=${PROFILE_REFERENCE_DEVICE:-${PROFILE_DEVICE:-}} model=${PROFILE_REFERENCE_MODEL:-${PROFILE_MODEL:-}} name=${PROFILE_REFERENCE_NAME:-${DEVICE_PROFILE_LABEL:-}}"
  check_expected_prop ro.product.brand "${PROFILE_BRAND:-google}" "$identity_severity"
  check_expected_prop ro.product.manufacturer "${PROFILE_MANUFACTURER:-Google}" "$identity_severity"
  check_expected_prop ro.product.model "${PROFILE_MODEL:-Pixel 5}" "$identity_severity"
  check_expected_prop ro.product.device "${PROFILE_DEVICE:-redfin}" "$identity_severity"
  check_expected_prop ro.product.name "${PROFILE_PRODUCT:-redfin}" "$identity_severity"
  check_expected_prop ro.build.version.release "${PROFILE_ANDROID_RELEASE:-11}" "$identity_severity"
  check_expected_prop ro.build.version.sdk "${PROFILE_ANDROID_API_LEVEL:-30}" "$identity_severity"
  if [ "$AUDIT_SCOPE" = "macos-native" ]; then
    emit_info "macOS native scope: system build props are unchanged by default; run scripts/macos-apply-system-props.sh for explicit Build.* parity. Prop parity is informational in this scope."
    profile_prop_parity "$PROFILE_PROPS" "strict profile props" "info"
  else
    profile_prop_parity "$PROFILE_PROPS" "strict profile props" "warn"
  fi
  profile_prop_parity "${PROFILE_OPTIONAL_PROPS:-${PROFILE_DIR}/props.optional}" "optional profile props" "info"
  echo
}

check_runtime_state() {
  local width
  local density
  local locale_actual

  echo "--- Runtime state ---"
  if [ -n "${SCREEN_RESOLUTION:-${PROFILE_SCREEN_RESOLUTION:-}}" ]; then
    width="${SCREEN_RESOLUTION:-${PROFILE_SCREEN_RESOLUTION}}"
    check_expected_command_contains "wm size" "$width" wm size
  fi
  if [ -n "${SCREEN_DENSITY:-${PROFILE_SCREEN_DENSITY:-}}" ]; then
    density="${SCREEN_DENSITY:-${PROFILE_SCREEN_DENSITY}}"
    check_expected_command_contains "wm density" "$density" wm density
  fi
  if [ -n "${PROFILE_LOCALE:-}" ]; then
    locale_actual="$(prop persist.sys.locale)"
    if [ -z "$locale_actual" ]; then
      locale_actual="$(prop ro.product.locale)"
    fi
    if [ "$locale_actual" = "$PROFILE_LOCALE" ]; then
      emit_pass "locale=${locale_actual}"
    else
      emit_warn "locale: expected '${PROFILE_LOCALE}', got persist.sys.locale='$(prop persist.sys.locale)' ro.product.locale='$(prop ro.product.locale)'"
    fi
  fi
  check_expected_prop persist.sys.timezone "${PROFILE_TIMEZONE:-}"
  check_expected_setting global device_name "${PROFILE_DEVICE_NAME:-}"
  check_expected_setting system accelerometer_rotation "${PROFILE_ACCELEROMETER_ROTATION:-}"
  check_expected_setting secure location_mode "${PROFILE_LOCATION_MODE:-}"
  check_expected_setting global window_animation_scale "${PROFILE_WINDOW_ANIMATION_SCALE:-}"
  check_expected_setting global transition_animation_scale "${PROFILE_TRANSITION_ANIMATION_SCALE:-}"
  check_expected_setting global animator_duration_scale "${PROFILE_ANIMATOR_DURATION_SCALE:-}"
  check_expected_setting system screen_off_timeout "${PROFILE_SCREEN_OFF_TIMEOUT_MS:-}"
  check_expected_setting global stay_on_while_plugged_in "${PROFILE_STAY_ON_WHILE_PLUGGED_IN:-}"
  check_expected_setting global airplane_mode_on "${PROFILE_AIRPLANE_MODE:-}"
  check_expected_runtime_prop gsm.version.baseband "${PROFILE_BASEBAND_VERSION:-}" info
  check_expected_runtime_prop gsm.current.phone-type "${PROFILE_GSM_CURRENT_PHONE_TYPE:-}" info
  check_expected_runtime_prop gsm.network.type "${PROFILE_GSM_NETWORK_TYPE:-}" info
  check_expected_runtime_prop gsm.operator.alpha "${PROFILE_GSM_OPERATOR_ALPHA:-}" info
  check_expected_runtime_prop gsm.operator.numeric "${PROFILE_GSM_OPERATOR_NUMERIC:-}" info
  check_expected_runtime_prop gsm.operator.iso-country "${PROFILE_GSM_OPERATOR_ISO_COUNTRY:-}" info
  check_expected_runtime_prop gsm.operator.isroaming "${PROFILE_GSM_OPERATOR_ISROAMING:-}" info
  check_expected_runtime_prop gsm.sim.operator.alpha "${PROFILE_GSM_SIM_OPERATOR_ALPHA:-}" info
  check_expected_runtime_prop gsm.sim.operator.numeric "${PROFILE_GSM_SIM_OPERATOR_NUMERIC:-}" info
  check_expected_runtime_prop gsm.sim.operator.iso-country "${PROFILE_GSM_SIM_OPERATOR_ISO_COUNTRY:-}" info
  check_expected_runtime_prop gsm.sim.state "${PROFILE_GSM_SIM_STATE:-}" info
  echo
}

check_emulator_exposure() {
  local abilist
  local dev_settings
  local adb_enabled
  local selinux
  local magisk

  echo "--- Emulator / instrumentation exposure ---"
  check_marker_prop ro.kernel.qemu '^1$|true|yes' "kernel QEMU flag"
  check_marker_prop ro.boot.qemu '^1$|true|yes' "boot QEMU flag"
  check_marker_prop ro.hardware 'ranchu|goldfish|qemu' "hardware name"
  check_marker_prop ro.boot.hardware 'ranchu|goldfish|qemu' "boot hardware name"
  check_marker_prop ro.bootloader '^unknown$|ranchu|goldfish' "bootloader"
  check_marker_path /dev/qemu_pipe "QEMU pipe"
  check_marker_path /dev/qemu_trace "QEMU trace"
  check_marker_path /system/bin/qemu-props "qemu-props binary"

  abilist="$(prop ro.product.cpu.abilist)"
  if printf '%s\n' "$abilist" | grep -Eq '(^|,)x86(_64)?(,|$)'; then
    emit_warn "ABI list exposes emulator CPU architecture: ro.product.cpu.abilist=${abilist}"
  else
    emit_pass "ABI list does not expose x86: ro.product.cpu.abilist=${abilist}"
  fi

  dev_settings="$(setting global development_settings_enabled)"
  adb_enabled="$(setting global adb_enabled)"
  if [ "$dev_settings" = "1" ]; then
    emit_warn "Developer settings are enabled for manageability"
  else
    emit_pass "Developer settings are not enabled"
  fi
  if [ "$adb_enabled" = "1" ]; then
    emit_warn "ADB is enabled for container/web control"
  else
    emit_pass "ADB setting is not enabled"
  fi

  selinux="$(shell_out getenforce | tail -n 1)"
  if [ "$selinux" = "Enforcing" ]; then
    emit_pass "SELinux=${selinux}"
  else
    emit_warn "SELinux=${selinux:-unknown}"
  fi

  magisk="$(shell_out 'test -x /data/adb/magisk/magiskinit && echo present || echo missing' | tail -n 1)"
  if [ "$magisk" = "present" ]; then
    emit_warn "Magisk/root artifacts are present; stock-device fidelity is reduced"
  else
    emit_pass "Magisk/root artifacts are not present"
  fi
  echo
}

check_integrity_boundaries() {
  echo "--- Hardware-backed integrity boundaries ---"
  emit_info "This is still an Android Emulator image; TEE/StrongBox/baseband/SIM/real sensor noise cannot be made hardware-backed here."
  emit_info "ro.boot.verifiedbootstate=$(prop ro.boot.verifiedbootstate)"
  emit_info "ro.boot.flash.locked=$(prop ro.boot.flash.locked)"
  emit_info "ro.boot.vbmeta.device_state=$(prop ro.boot.vbmeta.device_state)"
  emit_info "ro.dalvik.vm.native.bridge=$(prop ro.dalvik.vm.native.bridge)"
  emit_info "ro.ndk_translation.version=$(prop ro.ndk_translation.version)"
  echo
}

echo "=== Dockerify Android Real-device Fidelity Audit ==="
echo "profile=${DEVICE_PROFILE}"
echo "label=${DEVICE_PROFILE_LABEL}"
echo "serial=${ANDROID_SERIAL:-default-adb-target}"
echo "scope=${AUDIT_SCOPE}"
echo

check_runtime_identity
check_runtime_state
check_emulator_exposure
check_integrity_boundaries

printf 'Summary: pass=%s warn=%s info=%s\n' "$pass_count" "$warn_count" "$info_count"
if [ "$warn_count" -gt 0 ]; then
  echo "Result: high-fidelity profile applied, but emulator/instrumentation boundaries remain visible."
elif [ "$info_count" -gt 0 ]; then
  echo "Result: no warning-level mismatch found; informational best-effort or hardware-boundary notes were reported."
else
  echo "Result: no visible issues found by this audit."
fi

exit 0
