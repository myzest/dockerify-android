#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"
. ./scripts/macos-env.sh >/dev/null 2>&1
macos_load_profile >/dev/null
macos_configure_sdk_path
SERIAL="${ANDROID_SERIAL:-$(macos_android_serial)}"
OUT_DIR="${1:-${TMPDIR:-/tmp}/dockerify-devinfo}"
mkdir -p "$OUT_DIR"

adb -s "$SERIAL" shell input keyevent WAKEUP >/dev/null 2>&1 || true
adb -s "$SERIAL" shell monkey -p com.liuzh.deviceinfo -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
sleep "${DEVINFO_CAPTURE_DELAY:-6}"
adb -s "$SERIAL" shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1 || true
adb -s "$SERIAL" shell cat /sdcard/window.xml > "$OUT_DIR/window.xml" 2>/dev/null || true
adb -s "$SERIAL" exec-out screencap -p > "$OUT_DIR/screen.png" 2>/dev/null || true
python3 - "$OUT_DIR/window.xml" > "$OUT_DIR/texts.txt" <<'PY'
import html
import os
import re
import sys
path = sys.argv[1]
text = open(path, errors="ignore").read() if os.path.exists(path) else ""
for value in re.findall(r'text="([^"]*)"', text):
    value = html.unescape(value)
    if value:
        print(value)
PY
cat "$OUT_DIR/texts.txt"
echo "\nSaved: $OUT_DIR/window.xml"
echo "Saved: $OUT_DIR/screen.png"
echo "Saved: $OUT_DIR/texts.txt"
