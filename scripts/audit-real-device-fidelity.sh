#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
if [ -z "${PROFILE_ROOT:-}" ] && [ -d "${REPO_ROOT}/profiles" ]; then
  export PROFILE_ROOT="${REPO_ROOT}/profiles"
fi
. "${SCRIPT_DIR}/profile-lib.sh"

AUDIT_OUTPUT="text"
AUDIT_USE_FAKE_ADB="${AUDIT_USE_FAKE_ADB:-0}"
AUDIT_FAKE_ROOT="${AUDIT_FAKE_ROOT:-}"

usage() {
  cat <<'USAGE'
Usage: audit-real-device-fidelity.sh [--json] [--text]

Audit the active Dockerify Android device profile.

Options:
  --json    Emit a machine-readable JSON report.
  --text    Emit the human-readable report (default).
  -h,--help Show this help.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --json)
      AUDIT_OUTPUT="json"
      ;;
    --text)
      AUDIT_OUTPUT="text"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [ "$AUDIT_OUTPUT" = "json" ]; then
  load_device_profile >/dev/null
else
  load_device_profile
fi
export DEVICE_PROFILE DEVICE_PROFILE_LABEL

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

if [ "$AUDIT_USE_FAKE_ADB" != "1" ]; then
  "${ADB[@]}" wait-for-device >/dev/null 2>&1 || true
fi

CHECKS_FILE="$(mktemp)"
trap 'rm -f "$CHECKS_FILE"' EXIT

pass_count=0
warn_count=0
info_count=0
fail_count=0
check_count=0
current_category="general"
field_sep=$'\037'
record_sep=$'\036'

text_line() {
  if [ "$AUDIT_OUTPUT" = "text" ]; then
    printf '%s\n' "$*"
  fi
}

set_category() {
  current_category="$1"
  text_line "--- $2 ---"
}

append_check() {
  local status="$1"
  local severity="$2"
  local category="$3"
  local id="$4"
  local label="$5"
  local expected="$6"
  local actual="$7"
  local message="$8"
  local recommendation="$9"

  check_count=$((check_count + 1))
  case "$status" in
    pass) pass_count=$((pass_count + 1)) ;;
    warn) warn_count=$((warn_count + 1)) ;;
    info) info_count=$((info_count + 1)) ;;
    fail) fail_count=$((fail_count + 1)) ;;
  esac

  case "$status" in
    pass) text_line "[pass] ${message}" ;;
    warn) text_line "[warn] ${message}" ;;
    info) text_line "[info] ${message}" ;;
    fail) text_line "[fail] ${message}" ;;
  esac

  printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s' \
    "$status" "$field_sep" \
    "$severity" "$field_sep" \
    "$category" "$field_sep" \
    "$id" "$field_sep" \
    "$label" "$field_sep" \
    "$expected" "$field_sep" \
    "$actual" "$field_sep" \
    "$message" "$field_sep" \
    "$recommendation" "$record_sep" >> "$CHECKS_FILE"
}

fake_file_value() {
  local rel="$1"
  local file

  [ -n "$AUDIT_FAKE_ROOT" ] || return 1
  file="${AUDIT_FAKE_ROOT}/${rel}"
  [ -f "$file" ] || return 1
  cat "$file"
}

prop() {
  local key="$1"
  local safe_key

  if [ "$AUDIT_USE_FAKE_ADB" = "1" ]; then
    safe_key="$(printf '%s' "$key" | tr '/:' '__')"
    fake_file_value "props/${safe_key}" | tr -d '\r' | tail -n 1
    return 0
  fi

  "${ADB[@]}" shell getprop "$key" </dev/null 2>/dev/null | tr -d '\r' | tail -n 1
}

setting() {
  local namespace="$1"
  local key="$2"

  if [ "$AUDIT_USE_FAKE_ADB" = "1" ]; then
    fake_file_value "settings/${namespace}.${key}" | tr -d '\r' | tail -n 1
    return 0
  fi

  "${ADB[@]}" shell settings get "$namespace" "$key" </dev/null 2>/dev/null | tr -d '\r' | tail -n 1
}

shell_out() {
  local key
  local path

  if [ "$AUDIT_USE_FAKE_ADB" = "1" ]; then
    case "$*" in
      "wm size") fake_file_value "commands/wm_size" | tr -d '\r'; return 0 ;;
      "wm density") fake_file_value "commands/wm_density" | tr -d '\r'; return 0 ;;
      getenforce) fake_file_value "commands/getenforce" | tr -d '\r'; return 0 ;;
      "test -x /data/adb/magisk/magiskinit && echo present || echo missing")
        fake_file_value "commands/magisk_present" | tr -d '\r'
        return 0
        ;;
      sh\ -c\ test\ -e*)
        path="$(printf '%s' "$*" | sed -n "s/^sh -c test -e '\([^']*\)'.*/\1/p")"
        key="$(printf '%s' "$path" | sed 's#^/##;s#[^A-Za-z0-9_.-]#_#g')"
        fake_file_value "paths/${key}" | tr -d '\r'
        return 0
        ;;
    esac
    return 0
  fi

  "${ADB[@]}" shell "$@" </dev/null 2>/dev/null | tr -d '\r'
}

check_expected_prop() {
  local key="$1"
  local expected="$2"
  local severity="${3:-warn}"
  local category="${4:-$current_category}"
  local recommendation="${5:-Check profile system-property installation and reboot the emulator.}"
  local actual

  [ -n "$expected" ] || return 0
  actual="$(prop "$key")"
  if [ "$actual" = "$expected" ]; then
    append_check "pass" "pass" "$category" "prop.${key}" "$key" "$expected" "$actual" "${key}=${actual}" ""
  elif [ "$severity" = "info" ]; then
    append_check "info" "info" "$category" "prop.${key}" "$key" "$expected" "$actual" "${key}: expected '${expected}', got '${actual}'" "$recommendation"
  else
    append_check "warn" "warn" "$category" "prop.${key}" "$key" "$expected" "$actual" "${key}: expected '${expected}', got '${actual}'" "$recommendation"
  fi
}

check_expected_setting() {
  local namespace="$1"
  local key="$2"
  local expected="$3"
  local category="${4:-$current_category}"
  local actual

  [ -n "$expected" ] || return 0
  actual="$(setting "$namespace" "$key")"
  if [ "$actual" = "$expected" ]; then
    append_check "pass" "pass" "$category" "setting.${namespace}.${key}" "settings ${namespace}.${key}" "$expected" "$actual" "settings ${namespace}.${key}=${actual}" ""
  else
    append_check "warn" "warn" "$category" "setting.${namespace}.${key}" "settings ${namespace}.${key}" "$expected" "$actual" "settings ${namespace}.${key}: expected '${expected}', got '${actual}'" "Run profile runtime settings again or inspect why Android rejected the setting."
  fi
}

check_expected_runtime_prop() {
  local key="$1"
  local expected="$2"
  local severity="${3:-warn}"

  [ -n "$expected" ] || return 0
  check_expected_prop "$key" "$expected" "$severity" "$current_category" "Runtime radio/baseband properties are best-effort; verify profile_apply_runtime_settings and emulator telephony support."
}

check_expected_command_contains() {
  local label="$1"
  local expected="$2"
  shift 2
  local actual
  local id

  [ -n "$expected" ] || return 0
  actual="$(shell_out "$@")"
  id="command.$(printf '%s' "$label" | tr ' /' '__')"
  if printf '%s\n' "$actual" | grep -Fq "$expected"; then
    append_check "pass" "pass" "$current_category" "$id" "$label" "$expected" "$actual" "${label} contains ${expected}" ""
  else
    append_check "warn" "warn" "$current_category" "$id" "$label" "$expected" "$actual" "${label}: expected to contain '${expected}', got '${actual}'" "Check profile AVD config, runtime overrides, and emulator restart state."
  fi
}

check_marker_prop() {
  local key="$1"
  local bad_pattern="$2"
  local label="$3"
  local actual

  actual="$(prop "$key")"
  if [ -z "$actual" ]; then
    append_check "pass" "pass" "$current_category" "marker.prop.${key}" "$label" "not matching ${bad_pattern}" "$actual" "${label}: ${key} is empty" ""
  elif printf '%s\n' "$actual" | grep -Eiq "$bad_pattern"; then
    append_check "warn" "boundary" "$current_category" "marker.prop.${key}" "$label" "not matching ${bad_pattern}" "$actual" "${label}: ${key}=${actual}" "This is usually an emulator-owned boundary; document it rather than treating it as profile drift."
  else
    append_check "pass" "pass" "$current_category" "marker.prop.${key}" "$label" "not matching ${bad_pattern}" "$actual" "${label}: ${key}=${actual}" ""
  fi
}

check_marker_path() {
  local path="$1"
  local label="$2"
  local actual

  actual="$(shell_out sh -c "test -e '$path' && echo present || echo missing" | tail -n 1)"
  if [ "$actual" = "present" ]; then
    append_check "warn" "boundary" "$current_category" "marker.path.$(printf '%s' "$path" | sed 's#^/##;s#[^A-Za-z0-9_.-]#_#g')" "$label" "missing" "$actual" "${label}: ${path} exists" "This path is an emulator marker. Keep it in the audit report as a known boundary."
  else
    append_check "pass" "pass" "$current_category" "marker.path.$(printf '%s' "$path" | sed 's#^/##;s#[^A-Za-z0-9_.-]#_#g')" "$label" "missing" "$actual" "${label}: ${path} missing" ""
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
  local category="build-properties"

  [ -s "$props_file" ] || {
    append_check "info" "info" "$category" "profile.props.$(basename "$props_file").missing" "$label" "present" "missing" "No ${label} file: ${props_file}" "Add the profile property file if this profile is expected to declare Build.* parity."
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
        append_check "info" "info" "$category" "profile.prop.${key}" "$key" "$expected" "$actual" "${label} mismatch: ${key}: expected '${expected}', got '${actual}'" "For macOS native scope this is expected unless scripts/macos-apply-system-props.sh was run."
      else
        append_check "warn" "warn" "$category" "profile.prop.${key}" "$key" "$expected" "$actual" "${label} mismatch: ${key}: expected '${expected}', got '${actual}'" "Check profile property installation, duplicate build.prop sources, and reboot state."
      fi
    fi
  done < "$props_file"

  if [ "$mismatched" -eq 0 ]; then
    append_check "pass" "pass" "$category" "profile.props.$(basename "$props_file").parity" "$label parity" "${total}/${total}" "${matched}/${total}" "${label} parity: ${matched}/${total} matched" ""
  else
    if [ "$severity" = "info" ]; then
      append_check "info" "info" "$category" "profile.props.$(basename "$props_file").parity" "$label parity" "${total}/${total}" "${matched}/${total}" "${label} parity: ${matched}/${total} matched, ${mismatched} best-effort mismatched" "Review informational mismatches before using this profile for app-visible Build.* parity."
    else
      append_check "warn" "warn" "$category" "profile.props.$(basename "$props_file").parity" "$label parity" "${total}/${total}" "${matched}/${total}" "${label} parity: ${matched}/${total} matched, ${mismatched} mismatched" "Fix warning-level property mismatches before treating this profile as applied."
    fi
  fi
}

check_runtime_identity() {
  local identity_severity="warn"

  if [ "$AUDIT_SCOPE" = "macos-native" ]; then
    identity_severity="info"
  fi

  set_category "runtime-identity" "Runtime identity"
  append_check "info" "info" "$current_category" "profile.reference.mapping" "reference mapping" "profile reference" "brand=${PROFILE_REFERENCE_BRAND:-${PROFILE_MANUFACTURER:-}} device=${PROFILE_REFERENCE_DEVICE:-${PROFILE_DEVICE:-}} model=${PROFILE_REFERENCE_MODEL:-${PROFILE_MODEL:-}} name=${PROFILE_REFERENCE_NAME:-${DEVICE_PROFILE_LABEL:-}}" "reference mapping: brand=${PROFILE_REFERENCE_BRAND:-${PROFILE_MANUFACTURER:-}} device=${PROFILE_REFERENCE_DEVICE:-${PROFILE_DEVICE:-}} model=${PROFILE_REFERENCE_MODEL:-${PROFILE_MODEL:-}} name=${PROFILE_REFERENCE_NAME:-${DEVICE_PROFILE_LABEL:-}}" "Keep profile references current when adding or changing device identities."
  check_expected_prop ro.product.brand "${PROFILE_BRAND:-google}" "$identity_severity" "$current_category"
  check_expected_prop ro.product.manufacturer "${PROFILE_MANUFACTURER:-Google}" "$identity_severity" "$current_category"
  check_expected_prop ro.product.model "${PROFILE_MODEL:-Pixel 5}" "$identity_severity" "$current_category"
  check_expected_prop ro.product.device "${PROFILE_DEVICE:-redfin}" "$identity_severity" "$current_category"
  check_expected_prop ro.product.name "${PROFILE_PRODUCT:-redfin}" "$identity_severity" "$current_category"
  check_expected_prop ro.build.version.release "${PROFILE_ANDROID_RELEASE:-11}" "$identity_severity" "$current_category"
  check_expected_prop ro.build.version.sdk "${PROFILE_ANDROID_API_LEVEL:-30}" "$identity_severity" "$current_category"
  if [ "$AUDIT_SCOPE" = "macos-native" ]; then
    append_check "info" "info" "$current_category" "scope.macos-native.build-props" "macOS native Build.* parity" "explicit overlay" "not applied by default" "macOS native scope: system build props are unchanged by default; run scripts/macos-apply-system-props.sh for explicit Build.* parity. Prop parity is informational in this scope." "Run scripts/macos-apply-system-props.sh after starting with -writable-system if Build.* parity is required."
    profile_prop_parity "$PROFILE_PROPS" "strict profile props" "info"
  else
    profile_prop_parity "$PROFILE_PROPS" "strict profile props" "warn"
  fi
  profile_prop_parity "${PROFILE_OPTIONAL_PROPS:-${PROFILE_DIR}/props.optional}" "optional profile props" "info"
  text_line ""
}

check_runtime_state() {
  local width
  local density
  local locale_actual
  local persist_locale
  local product_locale

  set_category "runtime-state" "Runtime state"
  if [ -n "${SCREEN_RESOLUTION:-${PROFILE_SCREEN_RESOLUTION:-}}" ]; then
    width="${SCREEN_RESOLUTION:-${PROFILE_SCREEN_RESOLUTION}}"
    check_expected_command_contains "wm size" "$width" wm size
  fi
  if [ -n "${SCREEN_DENSITY:-${PROFILE_SCREEN_DENSITY:-}}" ]; then
    density="${SCREEN_DENSITY:-${PROFILE_SCREEN_DENSITY}}"
    check_expected_command_contains "wm density" "$density" wm density
  fi
  if [ -n "${PROFILE_LOCALE:-}" ]; then
    persist_locale="$(prop persist.sys.locale)"
    product_locale="$(prop ro.product.locale)"
    locale_actual="$persist_locale"
    if [ -z "$locale_actual" ]; then
      locale_actual="$product_locale"
    fi
    if [ "$locale_actual" = "$PROFILE_LOCALE" ]; then
      append_check "pass" "pass" "$current_category" "locale" "locale" "$PROFILE_LOCALE" "$locale_actual" "locale=${locale_actual}" ""
    else
      append_check "warn" "warn" "$current_category" "locale" "locale" "$PROFILE_LOCALE" "persist.sys.locale=${persist_locale}; ro.product.locale=${product_locale}" "locale: expected '${PROFILE_LOCALE}', got persist.sys.locale='${persist_locale}' ro.product.locale='${product_locale}'" "Reapply runtime settings and reboot if the framework locale cache is stale."
    fi
  fi
  check_expected_prop persist.sys.timezone "${PROFILE_TIMEZONE:-}" "warn" "$current_category" "Reapply runtime settings or verify timezone support in this system image."
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
  text_line ""
}

check_emulator_exposure() {
  local abilist
  local dev_settings
  local adb_enabled
  local selinux
  local magisk

  set_category "emulator-exposure" "Emulator / instrumentation exposure"
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
    append_check "warn" "boundary" "$current_category" "abi.x86.exposed" "ABI list exposes emulator CPU architecture" "no x86 ABI" "$abilist" "ABI list exposes emulator CPU architecture: ro.product.cpu.abilist=${abilist}" "Expected for x86_64 emulator and ndk_translation setups; track separately from profile drift."
  else
    append_check "pass" "pass" "$current_category" "abi.x86.exposed" "ABI list does not expose x86" "no x86 ABI" "$abilist" "ABI list does not expose x86: ro.product.cpu.abilist=${abilist}" ""
  fi

  dev_settings="$(setting global development_settings_enabled)"
  adb_enabled="$(setting global adb_enabled)"
  if [ "$dev_settings" = "1" ]; then
    append_check "warn" "manageability" "$current_category" "setting.global.development_settings_enabled.exposed" "Developer settings" "not enabled" "$dev_settings" "Developer settings are enabled for manageability" "This is useful for automation; disable only if your test profile requires stock-like UI settings."
  else
    append_check "pass" "pass" "$current_category" "setting.global.development_settings_enabled.exposed" "Developer settings" "not enabled" "$dev_settings" "Developer settings are not enabled" ""
  fi
  if [ "$adb_enabled" = "1" ]; then
    append_check "warn" "manageability" "$current_category" "setting.global.adb_enabled.exposed" "ADB setting" "not enabled" "$adb_enabled" "ADB is enabled for container/web control" "Expected for Dockerify control paths; expose this as a known manageability tradeoff."
  else
    append_check "pass" "pass" "$current_category" "setting.global.adb_enabled.exposed" "ADB setting" "not enabled" "$adb_enabled" "ADB setting is not enabled" ""
  fi

  selinux="$(shell_out getenforce | tail -n 1)"
  if [ "$selinux" = "Enforcing" ]; then
    append_check "pass" "pass" "$current_category" "selinux.mode" "SELinux" "Enforcing" "$selinux" "SELinux=${selinux}" ""
  else
    append_check "warn" "warn" "$current_category" "selinux.mode" "SELinux" "Enforcing" "${selinux:-unknown}" "SELinux=${selinux:-unknown}" "Investigate root/custom image changes if stock-like SELinux enforcing mode is required."
  fi

  magisk="$(shell_out 'test -x /data/adb/magisk/magiskinit && echo present || echo missing' | tail -n 1)"
  if [ "$magisk" = "present" ]; then
    append_check "warn" "root" "$current_category" "magisk.artifacts" "Magisk/root artifacts" "missing" "$magisk" "Magisk/root artifacts are present; stock-device fidelity is reduced" "Use ROOT_SETUP=0 and a clean data directory for stock-device fidelity tests."
  else
    append_check "pass" "pass" "$current_category" "magisk.artifacts" "Magisk/root artifacts" "missing" "$magisk" "Magisk/root artifacts are not present" ""
  fi
  text_line ""
}

check_integrity_boundaries() {
  set_category "integrity-boundaries" "Hardware-backed integrity boundaries"
  append_check "info" "boundary" "$current_category" "hardware.backed.boundaries" "hardware-backed boundaries" "hardware-backed Pixel hardware" "Android Emulator" "This is still an Android Emulator image; TEE/StrongBox/baseband/SIM/real sensor noise cannot be made hardware-backed here." "Document these boundaries in profile metadata and avoid promising hardware-backed parity."
  append_check "info" "info" "$current_category" "prop.ro.boot.verifiedbootstate" "ro.boot.verifiedbootstate" "reported" "$(prop ro.boot.verifiedbootstate)" "ro.boot.verifiedbootstate=$(prop ro.boot.verifiedbootstate)" ""
  append_check "info" "info" "$current_category" "prop.ro.boot.flash.locked" "ro.boot.flash.locked" "reported" "$(prop ro.boot.flash.locked)" "ro.boot.flash.locked=$(prop ro.boot.flash.locked)" ""
  append_check "info" "info" "$current_category" "prop.ro.boot.vbmeta.device_state" "ro.boot.vbmeta.device_state" "reported" "$(prop ro.boot.vbmeta.device_state)" "ro.boot.vbmeta.device_state=$(prop ro.boot.vbmeta.device_state)" ""
  append_check "info" "info" "$current_category" "prop.ro.dalvik.vm.native.bridge" "ro.dalvik.vm.native.bridge" "reported" "$(prop ro.dalvik.vm.native.bridge)" "ro.dalvik.vm.native.bridge=$(prop ro.dalvik.vm.native.bridge)" ""
  append_check "info" "info" "$current_category" "prop.ro.ndk_translation.version" "ro.ndk_translation.version" "reported" "$(prop ro.ndk_translation.version)" "ro.ndk_translation.version=$(prop ro.ndk_translation.version)" ""
  text_line ""
}

score_value() {
  local denominator
  local score

  denominator=$((pass_count + warn_count + fail_count))
  if [ "$denominator" -le 0 ]; then
    printf '100'
    return 0
  fi
  score=$(( (pass_count * 100) / denominator ))
  printf '%s' "$score"
}

result_text() {
  if [ "$fail_count" -gt 0 ]; then
    printf '%s' "audit failed: command or fixture failures were reported."
  elif [ "$warn_count" -gt 0 ]; then
    printf '%s' "high-fidelity profile applied, but emulator/instrumentation boundaries or mismatches remain visible."
  elif [ "$info_count" -gt 0 ]; then
    printf '%s' "no warning-level mismatch found; informational best-effort or hardware-boundary notes were reported."
  else
    printf '%s' "no visible issues found by this audit."
  fi
}

emit_json() {
  python3 - "$CHECKS_FILE" <<'PY'
import json
import os
import sys

checks_path = sys.argv[1]
field_sep = "\x1f"
record_sep = "\x1e"
checks = []
raw = open(checks_path, encoding="utf-8").read()
for record in raw.split(record_sep):
    if not record:
        continue
    fields = record.split(field_sep)
    fields += [""] * (9 - len(fields))
    status, severity, category, check_id, label, expected, actual, message, recommendation = fields[:9]
    item = {
        "id": check_id,
        "category": category,
        "status": status,
        "severity": severity,
        "label": label,
        "expected": expected,
        "actual": actual,
        "message": message,
    }
    if recommendation:
        item["recommendation"] = recommendation
    checks.append(item)

summary = {
    "pass": int(os.environ["AUDIT_PASS_COUNT"]),
    "warn": int(os.environ["AUDIT_WARN_COUNT"]),
    "info": int(os.environ["AUDIT_INFO_COUNT"]),
    "fail": int(os.environ["AUDIT_FAIL_COUNT"]),
    "total": int(os.environ["AUDIT_CHECK_COUNT"]),
}
report = {
    "schema_version": "1.0",
    "generated_at": os.environ["AUDIT_GENERATED_AT"],
    "profile": os.environ["DEVICE_PROFILE"],
    "label": os.environ.get("DEVICE_PROFILE_LABEL", os.environ["DEVICE_PROFILE"]),
    "serial": os.environ.get("ANDROID_SERIAL") or "default-adb-target",
    "scope": os.environ["AUDIT_SCOPE"],
    "summary": summary,
    "score": int(os.environ["AUDIT_SCORE"]),
    "result": os.environ["AUDIT_RESULT"],
    "checks": checks,
}
print(json.dumps(report, ensure_ascii=False, indent=2))
PY
}

text_line "=== Dockerify Android Real-device Fidelity Audit ==="
text_line "profile=${DEVICE_PROFILE}"
text_line "label=${DEVICE_PROFILE_LABEL}"
text_line "serial=${ANDROID_SERIAL:-default-adb-target}"
text_line "scope=${AUDIT_SCOPE}"
text_line ""

check_runtime_identity
check_runtime_state
check_emulator_exposure
check_integrity_boundaries

if [ "$AUDIT_OUTPUT" = "text" ]; then
  printf 'Summary: pass=%s warn=%s info=%s\n' "$pass_count" "$warn_count" "$info_count"
  printf 'Score: %s\n' "$(score_value)"
  printf 'Result: %s\n' "$(result_text)"
else
  export AUDIT_PASS_COUNT="$pass_count"
  export AUDIT_WARN_COUNT="$warn_count"
  export AUDIT_INFO_COUNT="$info_count"
  export AUDIT_FAIL_COUNT="$fail_count"
  export AUDIT_CHECK_COUNT="$check_count"
  export AUDIT_SCORE="$(score_value)"
  export AUDIT_RESULT="$(result_text)"
  export AUDIT_GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  export AUDIT_SCOPE
  emit_json
fi

exit 0
