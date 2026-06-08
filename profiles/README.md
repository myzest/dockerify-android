# Device profiles

Profiles make Dockerify Android start with a repeatable test-device identity.
Select one with `DEVICE_PROFILE`, for example:

```bash
DEVICE_PROFILE=pixel_5_android_11 docker compose up -d
```

Each profile can include:

- `profile.env`: exported profile defaults such as RAM, display, locale, timezone, and battery state.
- `props.system`: Android system properties applied on boot.
- `avd.ini`: AVD `config.ini` overrides applied before emulator startup.
- `settings.sh`: optional custom ADB settings applied after Android boots.

To add a device, copy `templates/android_11_device` to a new directory and edit
the values. Prefer matching the profile's Android version with the emulator
system image in the Dockerfile.
