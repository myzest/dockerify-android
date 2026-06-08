#!/bin/bash

ADB=(adb)
if [ -n "${ANDROID_SERIAL:-}" ]; then
  ADB+=(-s "$ANDROID_SERIAL")
fi

"${ADB[@]}" wait-for-device
"${ADB[@]}" shell settings put global development_settings_enabled 1 || true
"${ADB[@]}" shell settings put global adb_enabled 1 || true
