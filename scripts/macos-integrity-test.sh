#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

section() {
  printf '\n===== %s =====\n' "$1"
}

section "shell syntax"
for f in \
  first-boot.sh \
  start-emulator.sh \
  scripts/*.sh \
  profiles/pixel_5_android_11/*.sh \
  profiles/templates/android_11_device/*.sh; do
  bash -n "$f"
  echo "ok $f"
done

section "profile duplicate keys"
awk -F= '!/^($|#)/{count[$1]++; if(count[$1]==2){print "strict duplicate",$1; bad=1}} END{exit bad?1:0}' profiles/pixel_5_android_11/props.system
awk -F= '!/^($|#)/{count[$1]++; if(count[$1]==2){print "optional duplicate",$1; bad=1}} END{exit bad?1:0}' profiles/pixel_5_android_11/props.optional
awk -F= '!/^($|#)/{count[$1]++; if(count[$1]==2){print "avd duplicate",$1; bad=1}} END{exit bad?1:0}' profiles/pixel_5_android_11/avd.ini
echo "no duplicate keys"

section "macos doctor"
./scripts/macos-doctor.sh

section "macos run avd"
MACOS_BOOT_TIMEOUT="${MACOS_BOOT_TIMEOUT:-180}" ./scripts/macos-run-avd.sh

section "macos verify"
VERIFY_OUT="${TMPDIR:-/tmp}/dockerify-macos-verify.out"
./scripts/macos-verify-profile.sh | tee "$VERIFY_OUT"
if grep -q '^\[warn\]' "$VERIFY_OUT"; then
  echo "macos verify emitted warnings" >&2
  exit 1
fi

section "audit"
AUDIT_OUT="${TMPDIR:-/tmp}/dockerify-macos-audit.out"
bash -lc '. ./scripts/macos-env.sh >/dev/null 2>&1; macos_load_profile >/dev/null; macos_configure_sdk_path; SERIAL=$(macos_android_serial); ANDROID_SERIAL="$SERIAL" ./scripts/audit-real-device-fidelity.sh' | tee "$AUDIT_OUT"
for expected in \
  '^scope=macos-native$' \
  '^\[pass\] settings global.device_name=Pixel 5$' \
  '^\[pass\] locale=en-US$' \
  '^\[pass\] wm size contains 1080x2340$' \
  '^\[pass\] wm density contains 440$'; do
  if ! grep -q "$expected" "$AUDIT_OUT"; then
    echo "audit missing expected line: $expected" >&2
    exit 1
  fi
done

section "emulator log scan"
LOG_FILE="${MACOS_LOGS_DIR:-${HOME}/.dockerify-android/logs}/dockerify_pixel_5_android_11.log"
if [ ! -f "$LOG_FILE" ]; then
  echo "missing emulator log: $LOG_FILE" >&2
  exit 1
fi
if tail -300 "$LOG_FILE" | grep -Ei 'FATAL EXCEPTION|PANIC|segmentation fault|AddressSanitizer|ERROR.*emulator'; then
  echo "fatal-looking emulator log lines found" >&2
  exit 1
fi
echo "log scan ok: $LOG_FILE"

section "summary"
echo "mac integrity test passed"
