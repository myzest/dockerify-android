#!/bin/bash

adb wait-for-device
adb shell settings put secure install_non_market_apps 1 || true
adb shell settings put global development_settings_enabled 1 || true
adb shell settings put global adb_enabled 1 || true
