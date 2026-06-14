#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROFILE_ROOT="${REPO_ROOT}/profiles"
DEVICE_PROFILE="${DEVICE_PROFILE:-pixel_5_android_11}"
PROFILE_DIR="${PROFILE_ROOT}/${DEVICE_PROFILE}"
FIXTURE_DIR="$(mktemp -d)"
JSON_OUT="$(mktemp)"
ERR_OUT="$(mktemp)"

cleanup() {
  rm -rf "$FIXTURE_DIR" "$JSON_OUT" "$ERR_OUT"
}
trap cleanup EXIT

if [ ! -d "$PROFILE_DIR" ]; then
  echo "Unknown DEVICE_PROFILE=${DEVICE_PROFILE}" >&2
  exit 1
fi

python3 - "$PROFILE_DIR" "$FIXTURE_DIR" <<'PY'
from pathlib import Path
import sys

profile_dir = Path(sys.argv[1])
fixture_dir = Path(sys.argv[2])

for name in ["props", "settings", "commands", "paths"]:
    (fixture_dir / name).mkdir(parents=True, exist_ok=True)

def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"{value}\n", encoding="utf-8")

def safe_prop(key):
    return key.replace("/", "_").replace(":", "_")

def parse_env(path):
    values = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key] = value.strip().strip('"')
    return values

def parse_props(path):
    values = {}
    if not path.exists():
        return values
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.split("#", 1)[0].strip()
    return values

values = parse_env(profile_dir / "profile.env")
props = {
    "ro.product.brand": values.get("PROFILE_BRAND", "google"),
    "ro.product.manufacturer": values.get("PROFILE_MANUFACTURER", "Google"),
    "ro.product.model": values.get("PROFILE_MODEL", "Pixel 5"),
    "ro.product.device": values.get("PROFILE_DEVICE", "redfin"),
    "ro.product.name": values.get("PROFILE_PRODUCT", "redfin"),
    "ro.build.version.release": values.get("PROFILE_ANDROID_RELEASE", "11"),
    "ro.build.version.sdk": values.get("PROFILE_ANDROID_API_LEVEL", "30"),
    "persist.sys.locale": values.get("PROFILE_LOCALE", "en-US"),
    "ro.product.locale": values.get("PROFILE_LOCALE", "en-US"),
    "persist.sys.timezone": values.get("PROFILE_TIMEZONE", "Asia/Shanghai"),
    "gsm.version.baseband": values.get("PROFILE_BASEBAND_VERSION", ""),
    "gsm.current.phone-type": values.get("PROFILE_GSM_CURRENT_PHONE_TYPE", ""),
    "gsm.network.type": values.get("PROFILE_GSM_NETWORK_TYPE", ""),
    "gsm.operator.alpha": values.get("PROFILE_GSM_OPERATOR_ALPHA", ""),
    "gsm.operator.numeric": values.get("PROFILE_GSM_OPERATOR_NUMERIC", ""),
    "gsm.operator.iso-country": values.get("PROFILE_GSM_OPERATOR_ISO_COUNTRY", ""),
    "gsm.operator.isroaming": values.get("PROFILE_GSM_OPERATOR_ISROAMING", ""),
    "gsm.sim.operator.alpha": values.get("PROFILE_GSM_SIM_OPERATOR_ALPHA", ""),
    "gsm.sim.operator.numeric": values.get("PROFILE_GSM_SIM_OPERATOR_NUMERIC", ""),
    "gsm.sim.operator.iso-country": values.get("PROFILE_GSM_SIM_OPERATOR_ISO_COUNTRY", ""),
    "gsm.sim.state": values.get("PROFILE_GSM_SIM_STATE", ""),
    "ro.kernel.qemu": "",
    "ro.boot.qemu": "",
    "ro.hardware": values.get("PROFILE_DEVICE", "redfin"),
    "ro.boot.hardware": values.get("PROFILE_DEVICE", "redfin"),
    "ro.bootloader": f"{values.get('PROFILE_DEVICE', 'redfin')}-fixture",
    "ro.product.cpu.abilist": "arm64-v8a,armeabi-v7a,armeabi",
    "ro.boot.verifiedbootstate": "green",
    "ro.boot.flash.locked": "1",
    "ro.boot.vbmeta.device_state": "locked",
    "ro.dalvik.vm.native.bridge": "libndk_translation.so",
    "ro.ndk_translation.version": "0.2.3",
}
props.update(parse_props(profile_dir / "props.system"))
props.update(parse_props(profile_dir / "props.optional"))

for key, value in props.items():
    write(fixture_dir / "props" / safe_prop(key), value)

settings = {
    "global.device_name": values.get("PROFILE_DEVICE_NAME", "Pixel 5"),
    "system.accelerometer_rotation": values.get("PROFILE_ACCELEROMETER_ROTATION", "0"),
    "secure.location_mode": values.get("PROFILE_LOCATION_MODE", "3"),
    "global.window_animation_scale": values.get("PROFILE_WINDOW_ANIMATION_SCALE", "1"),
    "global.transition_animation_scale": values.get("PROFILE_TRANSITION_ANIMATION_SCALE", "1"),
    "global.animator_duration_scale": values.get("PROFILE_ANIMATOR_DURATION_SCALE", "1"),
    "system.screen_off_timeout": values.get("PROFILE_SCREEN_OFF_TIMEOUT_MS", "60000"),
    "global.stay_on_while_plugged_in": values.get("PROFILE_STAY_ON_WHILE_PLUGGED_IN", "0"),
    "global.airplane_mode_on": values.get("PROFILE_AIRPLANE_MODE", "0"),
    "global.development_settings_enabled": "0",
    "global.adb_enabled": "0",
}
for key, value in settings.items():
    write(fixture_dir / "settings" / key, value)

write(fixture_dir / "commands" / "wm_size", f"Physical size: {values.get('PROFILE_SCREEN_RESOLUTION', '1080x2340')}")
write(fixture_dir / "commands" / "wm_density", f"Physical density: {values.get('PROFILE_SCREEN_DENSITY', '440')}")
write(fixture_dir / "commands" / "getenforce", "Enforcing")
write(fixture_dir / "commands" / "magisk_present", "missing")
for path in ["/dev/qemu_pipe", "/dev/qemu_trace", "/system/bin/qemu-props"]:
    write(fixture_dir / "paths" / path.lstrip("/").replace("/", "_"), "missing")
PY

PROFILE_ROOT="$PROFILE_ROOT" \
DEVICE_PROFILE="$DEVICE_PROFILE" \
AUDIT_USE_FAKE_ADB=1 \
AUDIT_FAKE_ROOT="$FIXTURE_DIR" \
"${SCRIPT_DIR}/audit-real-device-fidelity.sh" --json >"$JSON_OUT" 2>"$ERR_OUT"

if [ -s "$ERR_OUT" ]; then
  echo "audit JSON mode wrote unexpected stderr:" >&2
  cat "$ERR_OUT" >&2
  exit 1
fi

python3 - "$JSON_OUT" "$DEVICE_PROFILE" <<'PY'
import json
import sys

path, expected_profile = sys.argv[1:3]
report = json.load(open(path, encoding="utf-8"))
required_top = {
    "schema_version",
    "generated_at",
    "profile",
    "label",
    "serial",
    "scope",
    "summary",
    "score",
    "result",
    "checks",
}
missing = required_top - set(report)
if missing:
    raise SystemExit(f"missing top-level keys: {sorted(missing)}")
if report["schema_version"] != "1.0":
    raise SystemExit(f"unexpected schema_version={report['schema_version']!r}")
if report["profile"] != expected_profile:
    raise SystemExit(f"unexpected profile={report['profile']!r}")
if not isinstance(report["score"], int) or not (0 <= report["score"] <= 100):
    raise SystemExit(f"invalid score={report['score']!r}")
checks = report["checks"]
if not checks:
    raise SystemExit("checks must not be empty")
summary = report["summary"]
if summary["total"] != len(checks):
    raise SystemExit(f"summary total {summary['total']} != checks length {len(checks)}")
for key in ["pass", "warn", "info", "fail", "total"]:
    if key not in summary or not isinstance(summary[key], int):
        raise SystemExit(f"invalid summary.{key}")
required_check = {"id", "category", "status", "severity", "label", "expected", "actual", "message"}
for index, check in enumerate(checks):
    missing = required_check - set(check)
    if missing:
        raise SystemExit(f"check[{index}] missing keys: {sorted(missing)}")
    if check["status"] not in {"pass", "warn", "info", "fail"}:
        raise SystemExit(f"check[{index}] invalid status={check['status']!r}")
ids = {check["id"] for check in checks}
for required_id in ["prop.ro.product.model", "profile.props.props.system.parity", "command.wm_size", "hardware.backed.boundaries"]:
    if required_id not in ids:
        raise SystemExit(f"missing required check id: {required_id}")
print(f"ok audit json: checks={len(checks)} score={report['score']} warn={summary['warn']}")
PY
