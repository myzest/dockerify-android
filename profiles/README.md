# Device profiles

Profiles make Dockerify Android start with a repeatable test-device identity.
Select one with `DEVICE_PROFILE`, for example:

```bash
DEVICE_PROFILE=pixel_5_android_11 docker compose up -d
```

On macOS, use the native runner instead of Dockerized emulator runtime:

```bash
DEVICE_PROFILE=pixel_5_android_11 ./scripts/macos-run-avd.sh
```

Each profile can include:

- `profile.env`: exported profile defaults such as RAM, display, locale, timezone, and battery state.
- `props.system`: strict Android system properties applied on boot and verified after reboot.
- `props.optional`: Docker-runner best-effort Android properties installed with the profile but reported as non-fatal audit findings if the emulator runtime does not expose them.
- `avd.ini`: AVD `config.ini` overrides applied before emulator startup.
- `settings.sh`: optional custom ADB settings applied after Android boots.

Runtime profile fields currently understood by the shared profile runner:

- Display and memory: `PROFILE_SCREEN_RESOLUTION`, `PROFILE_SCREEN_DENSITY`, `PROFILE_RAM_SIZE`.
- Identity and locale: `PROFILE_DEVICE_NAME`, `PROFILE_LOCALE`, `PROFILE_TIMEZONE`,
  `PROFILE_AUTO_TIME`, `PROFILE_AUTO_TIME_ZONE`.
- Interaction state: `PROFILE_ACCELEROMETER_ROTATION`, `PROFILE_LOCATION_MODE`,
  `PROFILE_WINDOW_ANIMATION_SCALE`, `PROFILE_TRANSITION_ANIMATION_SCALE`,
  `PROFILE_ANIMATOR_DURATION_SCALE`, `PROFILE_SCREEN_OFF_TIMEOUT_MS`,
  `PROFILE_STAY_ON_WHILE_PLUGGED_IN`.
- Network/power presentation: `PROFILE_DNS`, `PROFILE_AIRPLANE_MODE`,
  `PROFILE_WIFI_ENABLED`, `PROFILE_MOBILE_DATA_ENABLED`, `PROFILE_BATTERY_LEVEL`,
  `PROFILE_BATTERY_STATUS`, `PROFILE_BATTERY_AC`.

The default `pixel_5_android_11` profile is a high-fidelity compatibility
profile, not a hardware-backed clone. It aligns app-visible build properties,
display, locale, battery, network, and sensor presentation with a Pixel 5 /
Android 11 shape while the underlying runtime remains an Android Emulator.
The macOS native runner applies AVD and runtime settings from the same profile.
By default it does not modify system build properties. For app-visible `Build.*`
parity during local testing, start the AVD with `-writable-system` and apply the
profile overlay explicitly:

```bash
MACOS_NO_WINDOW=0 MACOS_EMULATOR_EXTRA_ARGS='-writable-system' ./scripts/macos-run-avd.sh
./scripts/macos-apply-system-props.sh
```

That script filters profile keys from observed build-property files, including
`/vendor/odm/etc/build.prop`, appends the selected profile values to
`/system/build.prop`, keeps backups under
`/data/local/tmp/dockerify-build-prop-backups/`, reboots, and reapplies runtime
settings.

After boot, run the audit helper to see which profile checks passed and which
emulator or instrumentation boundaries remain visible:

```bash
docker exec dockerify-android /opt/dockerify-android/scripts/audit-real-device-fidelity.sh
docker exec dockerify-android /opt/dockerify-android/scripts/audit-real-device-fidelity.sh --json > audit.json
```

For the macOS native runner:

```bash
./scripts/macos-verify-profile.sh
ANDROID_SERIAL=emulator-5584 ./scripts/audit-real-device-fidelity.sh
ANDROID_SERIAL=emulator-5584 ./scripts/audit-real-device-fidelity.sh --json > audit.json
./scripts/macos-integrity-test.sh
./scripts/audit-json-test.sh
```

Use `--json` when the audit result should feed CI, matrix runners, historical
comparison, or dashboards. The JSON report includes profile metadata, scope,
summary counts, a 0-100 score, and structured check records with category,
status, severity, expected/actual values, messages, and recommendations.

Useful macOS-specific `profile.env` fields:

- `PROFILE_MACOS_AVD_NAME`: stable AVD name for this profile.
- `PROFILE_MACOS_DEVICE_ID`: `avdmanager -d` device id such as `pixel_5`.
- `PROFILE_MACOS_SYSTEM_IMAGE_ARM64`: system image for Apple Silicon Macs.
- `PROFILE_MACOS_SYSTEM_IMAGE_X86_64`: system image for Intel Macs.

To add a device, copy `templates/android_11_device` to a new directory and edit
the values. Prefer matching the profile's Android version with the emulator
system image in the Dockerfile or the profile's macOS system image fields.
