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
- `props.system`: Android system properties applied on boot.
- `avd.ini`: AVD `config.ini` overrides applied before emulator startup.
- `settings.sh`: optional custom ADB settings applied after Android boots.

Useful macOS-specific `profile.env` fields:

- `PROFILE_MACOS_AVD_NAME`: stable AVD name for this profile.
- `PROFILE_MACOS_DEVICE_ID`: `avdmanager -d` device id such as `pixel_5`.
- `PROFILE_MACOS_SYSTEM_IMAGE_ARM64`: system image for Apple Silicon Macs.
- `PROFILE_MACOS_SYSTEM_IMAGE_X86_64`: system image for Intel Macs.

To add a device, copy `templates/android_11_device` to a new directory and edit
the values. Prefer matching the profile's Android version with the emulator
system image in the Dockerfile or the profile's macOS system image fields.
