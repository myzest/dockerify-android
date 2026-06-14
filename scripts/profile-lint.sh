#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROFILE_ROOT="${PROFILE_ROOT:-${REPO_ROOT}/profiles}"

usage() {
  cat <<'USAGE'
Usage: profile-lint.sh [PROFILE_NAME ...]

Lint Dockerify Android device profiles before runtime.
If no profile names are provided, all non-template profiles under profiles/ are checked.
Set PROFILE_LINT_INCLUDE_TEMPLATES=1 to include profiles/templates/*.
USAGE
}

profiles=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      profiles+=("$1")
      ;;
  esac
  shift
done

if [ "${#profiles[@]}" -eq 0 ]; then
  while IFS= read -r dir; do
    profiles+=("$(basename "$dir")")
  done < <(find "$PROFILE_ROOT" -mindepth 1 -maxdepth 1 -type d ! -name templates | sort)

  if [ "${PROFILE_LINT_INCLUDE_TEMPLATES:-0}" = "1" ] && [ -d "$PROFILE_ROOT/templates" ]; then
    while IFS= read -r dir; do
      profiles+=("templates/$(basename "$dir")")
    done < <(find "$PROFILE_ROOT/templates" -mindepth 1 -maxdepth 1 -type d | sort)
  fi
fi

python3 - "$PROFILE_ROOT" "${profiles[@]}" <<'PY'
import json
import re
import sys
from pathlib import Path

profile_root = Path(sys.argv[1])
profile_names = sys.argv[2:]
failed = False
failed_profiles = set()

REQUIRED_ENV = [
    "DEVICE_PROFILE_LABEL",
    "PROFILE_ANDROID_API_LEVEL",
    "PROFILE_ANDROID_RELEASE",
    "PROFILE_DEVICE_NAME",
    "PROFILE_MANUFACTURER",
    "PROFILE_BRAND",
    "PROFILE_MODEL",
    "PROFILE_PRODUCT",
    "PROFILE_DEVICE",
    "PROFILE_SCREEN_RESOLUTION",
    "PROFILE_SCREEN_DENSITY",
    "PROFILE_RAM_SIZE",
    "PROFILE_DNS",
    "PROFILE_LOCALE",
    "PROFILE_TIMEZONE",
    "PROFILE_MACOS_AVD_NAME",
    "PROFILE_MACOS_DEVICE_ID",
    "PROFILE_MACOS_SYSTEM_IMAGE_ARM64",
    "PROFILE_MACOS_SYSTEM_IMAGE_X86_64",
]

BOOL_KEYS = {"docker", "macos_native", "rootavd", "gapps", "arm_translation", "audit_json"}
STATUS_VALUES = {"supported", "experimental", "template", "deprecated"}
ENV_LINE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
RESOLUTION = re.compile(r"^[1-9][0-9]*x[1-9][0-9]*$")
LOCALE = re.compile(r"^[a-z]{2}(-[A-Z]{2})?$")
TIMEZONE = re.compile(r"^[A-Za-z_]+/[A-Za-z0-9_+.-]+(?:/[A-Za-z0-9_+.-]+)?$")


def emit(level, profile, message):
    print(f"[{level}] {profile}: {message}")


def fail(profile, message):
    global failed
    failed = True
    failed_profiles.add(profile)
    emit("fail", profile, message)


def ok(profile, message):
    emit("ok", profile, message)


def parse_env(path, profile):
    values = {}
    duplicates = []
    malformed = []
    if not path.exists():
        fail(profile, f"missing {path.name}")
        return values
    for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if not ENV_LINE.match(line):
            malformed.append((lineno, raw))
            continue
        key, value = line.split("=", 1)
        if key in values:
            duplicates.append(key)
        values[key] = value.strip().strip('"').strip("'")
    for key in sorted(set(duplicates)):
        fail(profile, f"duplicate profile.env key: {key}")
    for lineno, raw in malformed:
        fail(profile, f"malformed profile.env line {lineno}: {raw}")
    return values


def parse_kv_file(path, profile, required=False):
    values = {}
    duplicates = []
    malformed = []
    if not path.exists():
        if required:
            fail(profile, f"missing {path.name}")
        return values
    for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            malformed.append((lineno, raw))
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if not key:
            malformed.append((lineno, raw))
            continue
        if key in values:
            duplicates.append(key)
        values[key] = value.split("#", 1)[0].strip()
    for key in sorted(set(duplicates)):
        fail(profile, f"duplicate {path.name} key: {key}")
    for lineno, raw in malformed:
        fail(profile, f"malformed {path.name} line {lineno}: {raw}")
    return values


def load_meta(path, profile):
    if not path.exists():
        fail(profile, "missing profile.meta.json")
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(profile, f"invalid profile.meta.json: {exc}")
        return {}


def expect_equal(profile, label, expected, actual):
    if str(expected) != str(actual):
        fail(profile, f"{label} mismatch: meta={expected!r} env={actual!r}")


def lint_profile(profile_name):
    before_fail_count = len(failed_profiles)
    profile_dir = profile_root / profile_name
    if not profile_dir.is_dir():
        fail(profile_name, f"profile directory not found: {profile_dir}")
        return

    env = parse_env(profile_dir / "profile.env", profile_name)
    meta = load_meta(profile_dir / "profile.meta.json", profile_name)
    props_system = parse_kv_file(profile_dir / "props.system", profile_name, required=True)
    props_optional = parse_kv_file(profile_dir / "props.optional", profile_name, required=False)
    avd = parse_kv_file(profile_dir / "avd.ini", profile_name, required=True)

    settings = profile_dir / "settings.sh"
    if not settings.exists():
        fail(profile_name, "missing settings.sh")
    elif not settings.read_text(encoding="utf-8", errors="ignore").startswith("#!/"):
        fail(profile_name, "settings.sh should start with a shebang")

    for key in REQUIRED_ENV:
        if not env.get(key):
            fail(profile_name, f"missing required profile.env key: {key}")

    if env.get("PROFILE_SCREEN_RESOLUTION") and not RESOLUTION.match(env["PROFILE_SCREEN_RESOLUTION"]):
        fail(profile_name, "PROFILE_SCREEN_RESOLUTION must be WIDTHxHEIGHT")
    for numeric_key in ["PROFILE_ANDROID_API_LEVEL", "PROFILE_SCREEN_DENSITY", "PROFILE_RAM_SIZE"]:
        if env.get(numeric_key) and not env[numeric_key].isdigit():
            fail(profile_name, f"{numeric_key} must be numeric")
    if env.get("PROFILE_LOCALE") and not LOCALE.match(env["PROFILE_LOCALE"]):
        fail(profile_name, "PROFILE_LOCALE should look like en-US")
    if env.get("PROFILE_TIMEZONE") and not TIMEZONE.match(env["PROFILE_TIMEZONE"]):
        fail(profile_name, "PROFILE_TIMEZONE should look like Region/City")

    if meta:
        for key in ["schema_version", "id", "label", "status", "android", "device", "capabilities", "known_boundaries", "audit"]:
            if key not in meta:
                fail(profile_name, f"profile.meta.json missing key: {key}")
        if meta.get("schema_version") != "1.0":
            fail(profile_name, "profile.meta.json schema_version must be 1.0")
        expected_id = profile_name.split("/", 1)[-1]
        if meta.get("id") != expected_id:
            fail(profile_name, f"profile.meta.json id must be {expected_id}")
        if meta.get("status") not in STATUS_VALUES:
            fail(profile_name, f"profile.meta.json status must be one of {sorted(STATUS_VALUES)}")
        if not isinstance(meta.get("known_boundaries"), list) or not meta.get("known_boundaries"):
            fail(profile_name, "profile.meta.json known_boundaries must be a non-empty array")

        android = meta.get("android") if isinstance(meta.get("android"), dict) else {}
        device = meta.get("device") if isinstance(meta.get("device"), dict) else {}
        caps = meta.get("capabilities") if isinstance(meta.get("capabilities"), dict) else {}
        audit = meta.get("audit") if isinstance(meta.get("audit"), dict) else {}

        if android:
            expect_equal(profile_name, "android.api_level", android.get("api_level"), env.get("PROFILE_ANDROID_API_LEVEL"))
            expect_equal(profile_name, "android.release", android.get("release"), env.get("PROFILE_ANDROID_RELEASE"))
            if not android.get("system_image"):
                fail(profile_name, "profile.meta.json android.system_image is required")
        else:
            fail(profile_name, "profile.meta.json android must be an object")

        if device:
            mapping = {
                "manufacturer": "PROFILE_MANUFACTURER",
                "brand": "PROFILE_BRAND",
                "model": "PROFILE_MODEL",
                "product": "PROFILE_PRODUCT",
                "device": "PROFILE_DEVICE",
            }
            for meta_key, env_key in mapping.items():
                expect_equal(profile_name, f"device.{meta_key}", device.get(meta_key), env.get(env_key))
        else:
            fail(profile_name, "profile.meta.json device must be an object")

        if caps:
            for key in BOOL_KEYS:
                if key not in caps:
                    fail(profile_name, f"profile.meta.json capabilities missing {key}")
                elif not isinstance(caps[key], bool):
                    fail(profile_name, f"profile.meta.json capabilities.{key} must be boolean")
        else:
            fail(profile_name, "profile.meta.json capabilities must be an object")

        if audit:
            if not isinstance(audit.get("minimum_score"), int) or not (0 <= audit.get("minimum_score", -1) <= 100):
                fail(profile_name, "profile.meta.json audit.minimum_score must be an integer 0-100")
            for file_key in ["strict_props", "optional_props"]:
                value = audit.get(file_key)
                if value and not (profile_dir / value).exists():
                    fail(profile_name, f"profile.meta.json audit.{file_key} references missing file: {value}")
        else:
            fail(profile_name, "profile.meta.json audit must be an object")

    # Cross-file sanity checks for profile identity.
    prop_expectations = {
        "ro.product.manufacturer": env.get("PROFILE_MANUFACTURER"),
        "ro.product.brand": env.get("PROFILE_BRAND"),
        "ro.product.model": env.get("PROFILE_MODEL"),
        "ro.product.name": env.get("PROFILE_PRODUCT"),
        "ro.product.device": env.get("PROFILE_DEVICE"),
        "ro.build.version.release": env.get("PROFILE_ANDROID_RELEASE"),
        "ro.build.version.sdk": env.get("PROFILE_ANDROID_API_LEVEL"),
    }
    for key, expected in prop_expectations.items():
        if expected and props_system.get(key) != expected:
            fail(profile_name, f"props.system {key} should match profile.env value {expected!r}")

    if "hw.lcd.width" in avd and "hw.lcd.height" in avd and env.get("PROFILE_SCREEN_RESOLUTION"):
        expected = f"{avd['hw.lcd.width']}x{avd['hw.lcd.height']}"
        if expected != env["PROFILE_SCREEN_RESOLUTION"]:
            fail(profile_name, f"avd.ini display {expected} does not match PROFILE_SCREEN_RESOLUTION={env['PROFILE_SCREEN_RESOLUTION']}")
    if "hw.lcd.density" in avd and env.get("PROFILE_SCREEN_DENSITY") and avd["hw.lcd.density"] != env["PROFILE_SCREEN_DENSITY"]:
        fail(profile_name, "avd.ini hw.lcd.density does not match PROFILE_SCREEN_DENSITY")
    if "hw.ramSize" in avd and env.get("PROFILE_RAM_SIZE") and avd["hw.ramSize"] != env["PROFILE_RAM_SIZE"]:
        fail(profile_name, "avd.ini hw.ramSize does not match PROFILE_RAM_SIZE")

    if len(failed_profiles) == before_fail_count:
        ok(profile_name, "profile lint passed")


if not profile_names:
    print("[fail] no profiles selected", file=sys.stderr)
    sys.exit(1)

for profile_name in profile_names:
    lint_profile(profile_name)

sys.exit(1 if failed else 0)
PY
