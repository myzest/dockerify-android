# Dockerify Android

<img align="right" src="/doc/dockerify-android-web-preview.png" />

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker Pulls](https://img.shields.io/docker/pulls/shmayro/dockerify-android)](https://hub.docker.com/r/shmayro/dockerify-android)
[![GitHub Release](https://img.shields.io/github/v/release/shmayro/dockerify-android)](https://github.com/shmayro/dockerify-android/releases)
[![GitHub Issues](https://img.shields.io/github/issues/shmayro/dockerify-android)](https://github.com/shmayro/dockerify-android/issues)
[![GitHub Stars](https://img.shields.io/github/stars/shmayro/dockerify-android?style=social)](https://github.com/shmayro/dockerify-android/stargazers)

**Dockerify Android** is a Dockerized Android emulator supporting multiple CPU architectures (**x86** and **ARM/ARM64 apps** via ndk_translation) with native performance and seamless ADB & Web access. It allows developers to run Android virtual devices (AVDs) efficiently within Docker containers, facilitating scalable testing and development environments.

### 🔥 **Key Feature: Web Interface Access** 🌐

Access and control the Android emulator directly in your web browser with the integrated [scrcpy-web](https://github.com/Shmayro/ws-scrcpy-docker) interface! No additional software needed - just open your browser and start using Android.

> **Benefits of Web Interface:**
> - No extra software to install
> - Access from any computer with a web browser
> - Full touchscreen and keyboard support
> - Perfect for remote work or sharing the emulator with team members

<br clear="right"/>

## 🏠 **Homepage**

[![GitHub](https://img.shields.io/badge/GitHub-Repo-blue?logo=github)](https://github.com/shmayro/dockerify-android)
[![Docker Hub](https://img.shields.io/badge/Docker%20Hub-Repo-blue?logo=docker)](https://hub.docker.com/r/shmayro/dockerify-android)

## 📜 **Table of Contents**

- [Features](#-features)
- [Prerequisites](#-prerequisites)
- [Installation](#-installation)
- [Usage](#-usage)
  - [Using Web Interface](#use-the-web-interface-to-access-the-emulator)
  - [Using ADB](#connect-via-adb)
  - [Using Desktop scrcpy](#use-scrcpy-to-mirror-the-emulator-screen)
  - [Customizing Device Screen](#customizing-device-screen)
- [First Boot Process](#-first-boot-process)
- [Container Logs](#-container-logs)
- [Versioning and Releases](#-versioning-and-releases)
- [Roadmap](#-roadmap)
- [Troubleshooting](#-troubleshooting)
- [Contributing](#-contributing)
- [License](#-license)
- [Contact](#-contact)

## 🔧 **Features**

- **🌐 Web Interface:** Access the emulator directly from your browser with the integrated [scrcpy-web](https://github.com/Shmayro/ws-scrcpy-docker) interface.
- **🔄 ARM Translation Support:** Run ARM/ARM64 native applications on x86_64 emulator using ndk_translation layer. This allows installation of modern Android apps that ship only with ARM native libraries (arm64-v8a, armeabi-v7a).
- **Root and Magisk Preinstalled:** Comes with root access and Magisk preinstalled for advanced modifications.
- **PICO GAPPS Preinstalled:** Includes PICO GAPPS for essential Google services.
- **Seamless ADB Access:** Connect to the emulator via ADB from the host and other networked devices.
- **scrcpy Support:** Mirror the emulator screen using scrcpy for a seamless user experience.
- **Optimized Performance:** Utilizes native CPU capabilities for efficient emulation.
- **Multi-Architecture Support:** Runs natively on both **x86** and **arm64** CPU architectures.
- **Docker Integration:** Easily deploy the Android emulator within a Docker container.
- **Easy Setup:** Simple Docker commands to build and run the emulator.
- **Supervisor Management:** Manages emulator processes with Supervisor for reliability.
- **Unified Container Logs:** All emulator and boot logs are redirected to Docker's standard log system.

## 🛠️ **Prerequisites**

Before you begin, ensure you have met the following requirements:
- **Docker:** Installed on your system. [Installation Guide](https://docs.docker.com/get-docker/)
- **Docker Compose:** For managing multi-container setups. [Installation Guide](https://docs.docker.com/compose/install/)
- **KVM Support:** Ensure your system supports KVM (Kernel-based Virtual Machine) for hardware acceleration.
  - **Check KVM Support:**

    ```bash
    egrep -c '(vmx|svm)' /proc/cpuinfo
    ```

    A non-zero output indicates KVM support.

  - **Docker Desktop for macOS:** the default x86_64 emulator image requires
    `/dev/kvm` inside the Linux Docker VM. Recent Docker Desktop versions on
    Apple Silicon can build this image, but they usually do not expose KVM to
    containers, so the emulator cannot complete first boot there. Use a Linux
    host with KVM exposed for runtime validation.

## 🚀 **Installation**

To simplify the setup process, you can use the provided [docker-compose.yml](https://github.com/Shmayro/dockerify-android/blob/main/docker-compose.yml) file.

1. **Clone the Repository:**

    ```bash
    git clone https://github.com/shmayro/dockerify-android.git
    cd dockerify-android
    ```

2. **Run Docker Compose:**

    ```bash
    docker compose up -d
    ```

    > **Note:** This command launches the Android emulator and web interface. First boot takes some time to initialize. Once ready, the device will appear in the web interface at http://localhost:8000.


## 📡 **Usage**

### 🌐 Use the Web Interface to Access the Emulator

The **quickest and easiest way** to interact with the Android emulator is through your web browser:

1. Open your browser and go to `http://localhost:8000`
2. You should see the device listed as "dockerify-android:5555" automatically connected
3. Select one of the available streaming options:
   - **H264 Converter** (recommended for best overall experience)
   - Tiny H264 (good for low-bandwidth connections)
   - Broadway.js (fallback option)

![scrcpy-web interface](/doc/scrcpy-web-preview.png)

> **Note:** First boot may take some time as the Android emulator needs to fully initialize. When everything is ready, the device will appear in the web interface as shown in the screenshot above.

### Connect via ADB

If you need direct ADB access to the emulator:

```bash
adb connect localhost:5555
adb devices
```

**Expected Output:**

```
connected to localhost:5555
List of devices attached
localhost:5555	device
```

### Use scrcpy to Mirror the Emulator Screen

For a native desktop experience, you can use scrcpy:

```bash
scrcpy -s localhost:5555
```

> **Note:** Ensure `scrcpy` is installed on your host machine. [Installation Guide](https://github.com/Genymobile/scrcpy#installation)

## ⚙️ **Environment Variables**

| Variable | Description | Default |
| --- | --- | --- |
| `DEVICE_PROFILE` | Device profile loaded from `profiles/<name>` | `pixel_5_android_11` |
| `DOCKER_PLATFORM` | Docker platform used for emulator containers. Android Emulator Linux packages are x86_64-only. | `linux/amd64` |
| `DNS` | Private DNS server used inside the emulator | `one.one.one.one` |
| `RAM_SIZE` | RAM in megabytes allocated to the emulator | `4096` |
| `SCREEN_RESOLUTION` | Screen size in `WIDTHxHEIGHT` format (e.g. `1080x1920`) | device default |
| `SCREEN_DENSITY` | Screen pixel density in DPI | device default |
| `ROOT_SETUP` | Set to `1` to enable rooting and Magisk. Can be turned on after the first start but cannot be undone without recreating the data volume. | `0` |
| `GAPPS_SETUP` | Set to `1` to install PICO GAPPS. Can be turned on after the first start but cannot be undone without recreating the data volume. | `0` |
| `ARM_TRANSLATION` | Set to `1` to enable ARM translation (ndk_translation) for running ARM/ARM64 apps on x86_64. Can be turned on after the first start but cannot be undone without recreating the data volume. | `1` in Compose |
| `ALLOW_NO_KVM` | Bypass the KVM preflight. Use only with an experimental non-x86 image that can boot without KVM. | `0` |

Profile defaults are loaded before emulator startup. If `RAM_SIZE`,
`SCREEN_RESOLUTION`, `SCREEN_DENSITY`, or `DNS` is unset or empty, the selected
profile can provide the effective value; for example the default Pixel 5 profile
sets `RAM_SIZE=8192` unless you override it.

### Device Profiles

Dockerify Android supports repeatable test-device profiles. A profile can set
the AVD display/RAM configuration, Android system properties, locale, timezone,
device name, battery state, expected Android version, and custom post-boot
settings.

The default profile is `pixel_5_android_11`, which matches the current Android
30 / Android 11 emulator base:

```bash
DEVICE_PROFILE=pixel_5_android_11 docker compose up -d
```

To add another device, copy `profiles/templates/android_11_device` to a new
directory under `profiles/`, edit the values, and set `DEVICE_PROFILE` to that
directory name. Runtime overrides such as `SCREEN_RESOLUTION`, `SCREEN_DENSITY`,
`RAM_SIZE`, and `DNS` still take precedence over profile defaults.

Each profile declares `PROFILE_ANDROID_API_LEVEL` and `PROFILE_ANDROID_RELEASE`.
The boot script refuses to apply a profile that does not match the Android
system image baked into the Docker image. Add Android 12/13 profiles only after
the Docker image supports the matching system image.

The bundled `pixel_5_android_11` profile is tuned as a high-fidelity Pixel 5
compatibility profile. It applies strict Pixel-style build properties plus
best-effort release metadata, display metrics, locale/timezone, battery state,
network presentation, and AVD sensor/camera settings. This improves ordinary
app-visible device consistency, but it does not turn the emulator into
hardware-backed Pixel hardware: TEE, StrongBox, baseband/SIM/IMEI, real sensor
noise, hardware Play Integrity, and low-level QEMU/KVM artifacts remain
emulator boundaries.

Device name/model values are meant to be grounded in public device mapping
datasets such as `bsthen/device-models` and
`androidtrackers/certified-android-devices`. The default profile cross-checks
the certified Pixel 5 mapping `brand=Google`, `device=redfin`,
`model=Pixel 5`, `name=Pixel 5`.

To inspect the active device after boot:

```bash
docker exec dockerify-android /opt/dockerify-android/scripts/verify-profile.sh
docker exec dockerify-android /opt/dockerify-android/scripts/audit-real-device-fidelity.sh
docker exec dockerify-android /opt/dockerify-android/scripts/audit-real-device-fidelity.sh --json > audit.json
```

When using the macOS native runner, run the same audit against the emulator
serial. The audit automatically treats build-property mismatches as
informational because the macOS runner does not install `props.system` or
`props.optional` into the system image:

```bash
ANDROID_SERIAL=emulator-5584 ./scripts/audit-real-device-fidelity.sh
ANDROID_SERIAL=emulator-5584 ./scripts/audit-real-device-fidelity.sh --json > audit.json
```

The default audit output is optimized for humans. `--json` emits a structured
report with `profile`, `serial`, `scope`, `summary`, `score`, `result`, and a
`checks[]` array. Each check includes an id, category, status, severity,
expected/actual values, message, and optional recommendation, so CI, matrix
runners, and future web dashboards can consume the same fidelity data.

For a repeatable local Mac integrity check, run:

```bash
./scripts/macos-integrity-test.sh
./scripts/audit-json-test.sh
```

### DevInfo-driven fidelity checks

A local DevInfo APK (`com.liuzh.deviceinfo`, v2.6.9) was used as a concrete
app-visible oracle for the Pixel 5 profile. The APK was pulled from the running
AVD and inspected with jadx; the decisive UI cards read these sources:

| DevInfo field | App read source | Profile/control path | Current result |
| --- | --- | --- | --- |
| Device name | `Build.DEVICE` / `Build.MODEL` plus bundled device-name DB | `props.system` via `scripts/macos-apply-system-props.sh` or Docker first boot | `redfin` |
| Brand/model/manufacturer/device/board | `Build.BRAND`, `Build.MODEL`, `Build.MANUFACTURER`, `Build.DEVICE`, `Build.BOARD` | `props.system` | `google`, `Pixel 5`, `Google`, `redfin`, `redfin` |
| Hardware | `Build.HARDWARE` | boot/kernel-owned emulator property | still `ranchu` |
| Android ID | `Settings.Secure.getString(..., "android_id")` | generated per Android data image | stable per AVD data; not profile-forced |
| GSF / Advertising ID | Google services provider / advertising-id service | Google services state | stable per installed services; not profile-forced |
| Hardware serial | `Build.SERIAL` | Android/emulator serial policy | still `unknown` in DevInfo |
| Build fingerprint | `Build.FINGERPRINT` | `props.system` | `google/redfin/redfin:11/RQ3A.211001.001/7641976:user/release-keys` |
| Device type/operator/network | `TelephonyManager.getPhoneType()`, `getNetworkOperatorName()`, `getNetworkType()` | runtime `gsm.*` profile properties | `GSM`, `T-Mobile`, `LTE` |
| Build number / ID / patch | `Build.DISPLAY`, `Build.ID`, `Build.VERSION.SECURITY_PATCH` | `props.system` / `props.optional` | `RQ3A.211001.001`, `2021-10-05` |
| Baseband | `Build.getRadioVersion()` | runtime `gsm.version.baseband` | `g7250-00123-211001-B-7641976` |
| Root access | `Build.TAGS` contains `test-keys` or `which su` paths | `ro.build.tags=release-keys`; no Magisk in macOS AVD | `No` |
| CPU hardware/frequency | `/proc/cpuinfo`, `/sys/devices/system/cpu/*/cpufreq/*`, fallback `Build.HARDWARE` | kernel/emulator-owned | still `ranchu`, `0MHz - 0MHz` |
| GPU renderer/vendor/version | OpenGL/EGL runtime | emulator GPU stack | still ANGLE/SwiftShader |

The important implementation detail is that Android loads properties from more
than just `/system/build.prop`. The macOS overlay script filters existing keys
from all observed build-property files, including `/vendor/odm/etc/build.prop`,
then appends the selected profile values to `/system/build.prop`. A reboot is
required because `ro.*` / `Build.*` values are read-only after init.

Known emulator boundaries after these changes are expected and audited: low-level
`ro.hardware` / `ro.boot.hardware`, kernel QEMU flags, bootloader state,
ADB/developer settings, `/proc/cpuinfo`, cpufreq sysfs, and ANGLE/SwiftShader
GPU strings.

For multiple emulator instances, give each stack its own Compose project,
container names, ports, and data directory:

```bash
COMPOSE_PROJECT_NAME=pixel5 \
ANDROID_CONTAINER_NAME=dockerify-android-pixel5 \
SCRCPY_CONTAINER_NAME=scrcpy-web-pixel5 \
DEVICE_PROFILE=pixel_5_android_11 \
DATA_DIR=./data/pixel_5 \
ADB_PORT=5555 \
WEB_PORT=8000 \
docker compose up -d
```

The `scrcpy-web` container connects to the Android service by Compose service
name, `dockerify-android:5555`. Keep the service names in `docker-compose.yml`
unchanged; use `COMPOSE_PROJECT_NAME`, container-name variables, ports, and data
directories to separate instances.

### macOS Native Runner

Docker Desktop for macOS can build the Docker image, but it usually cannot expose
`/dev/kvm` to Linux containers. For local Mac usage, run the Android Emulator
natively on macOS and reuse the same device profiles:

```bash
./scripts/macos-doctor.sh
./scripts/macos-bootstrap-sdk.sh
DEVICE_PROFILE=pixel_5_android_11 ./scripts/macos-run-avd.sh
./scripts/macos-verify-profile.sh
```

If Android Studio or an Android SDK is already installed, the runner reuses it
from `ANDROID_HOME`, `ANDROID_SDK_ROOT`, or `~/Library/Android/sdk`. If not,
`macos-bootstrap-sdk.sh` installs Android command-line tools into
`~/.dockerify-android/android-sdk` and installs the emulator, platform-tools,
platform package, and the profile's macOS system image.

Useful macOS runner variables:

| Variable | Description | Default |
| --- | --- | --- |
| `MACOS_AVD_NAME` | Override the generated AVD name | profile default |
| `MACOS_EMULATOR_PORT` | Emulator console/ADB port pair base | `5584` |
| `MACOS_SYSTEM_IMAGE` | Override the selected SDK system image package | profile/host ABI default |
| `MACOS_BOOT_TIMEOUT` | Seconds to wait for Android boot completion | `300` |
| `MACOS_EMULATOR_EXTRA_ARGS` | Extra arguments appended to the emulator command. The runner starts headless with `-no-window` by default. | empty |

The macOS runner is a native, profile-driven test environment. It supports AVD
creation, display/RAM config, locale/timezone/device-name/battery/radio
presentation settings, and verification. By default it does not mutate the
system image. For local app-visible `Build.*` parity, restart/start the AVD with
a writable system image and apply the profile overlay explicitly:

```bash
MACOS_NO_WINDOW=0 MACOS_EMULATOR_EXTRA_ARGS='-writable-system' ./scripts/macos-run-avd.sh
./scripts/macos-apply-system-props.sh
```

The overlay script backs up observed build-property files under
`/data/local/tmp/dockerify-build-prop-backups/`, filters duplicate profile keys
from `/system`, `/vendor`, `/product`, `/system_ext`, `/odm`, and
`/vendor/odm/etc/build.prop`, appends the selected profile values to
`/system/build.prop`, reboots, and reapplies runtime settings. The overlay
script itself does not manage root/Magisk, OpenGApps injection, or
ndk_translation.

Experimental native rootAVD support is available without Docker. Start the
native AVD first, then patch the profile's SDK `ramdisk.img` with rootAVD:

```bash
MACOS_NO_WINDOW=0 DEVICE_PROFILE=pixel_5_android_11 ./scripts/macos-run-avd.sh
DEVICE_PROFILE=pixel_5_android_11 ./scripts/macos-rootavd.sh
adb -s emulator-5584 emu kill
MACOS_NO_WINDOW=0 DEVICE_PROFILE=pixel_5_android_11 ./scripts/macos-run-avd.sh
```

`macos-rootavd.sh` downloads rootAVD into `~/.dockerify-android/rootavd`, backs
up the selected SDK system image `ramdisk.img`, patches it, and copies the
patched ramdisk into the profile AVD directory. This mutates the local Android
SDK system image used by matching AVDs; run
`DEVICE_PROFILE=pixel_5_android_11 ./scripts/macos-rootavd.sh restore` to
restore the latest generated backup. Native rootAVD does not install OpenGApps
or ndk_translation.


## 🔄 **First Boot Process**

The first time you start the container, it will perform a comprehensive setup process that includes:

1. **AVD Creation:** Creates a new Android Virtual Device running Android 30 (Android 11)
2. **PICO GAPPS Installation** (when `GAPPS_SETUP=1`): Adds essential Google services.
3. **Rooting the Device** (when `ROOT_SETUP=1`): Performs multiple reboots to:
   - Disable AVB verification
   - Remount system as writable
   - Install Magisk for root access
   - Reboot to apply root
4. **ARM Translation Installation** (when `ARM_TRANSLATION=1`): Installs ndk_translation ARM translation layer to enable running ARM/ARM64 native apps on x86_64:
   - Installs ndk_translation for both ARM32 (armeabi-v7a) and ARM64 (arm64-v8a) support
   - Updates system properties to advertise ARM ABI support
   - Configures native bridge for transparent ARM-to-x86 translation
   - After installation, the device will report `ro.product.cpu.abilist = x86_64,x86,arm64-v8a,armeabi-v7a,armeabi`
5. **Extras Copied:** Pushes everything from the `extras` directory to `/sdcard/Download` so files like APKs or Magisk modules are ready for manual installation on the device.
6. **Configuring optimal device settings**

`ROOT_SETUP`, `GAPPS_SETUP`, and `ARM_TRANSLATION` are checked on every start. If you enable them after the first boot, the script installs the requested components once and marks them complete so they won't run again. Removing them later requires recreating the data volume.

> **Important:** The first boot can take 10-15 minutes to complete. You'll know the process is finished when you see the following log output:
> ```
> Broadcast completed: result=0
> Success !!
> 2025-04-22 13:45:18,724 INFO exited: first-boot (exit status 0; expected)
> ```

> **Note:** If the Android emulator has restarted for any reason, it's recommended to restart the Docker container to reapply optimizations:
> ```bash
> docker compose restart
> ```
> This reapplies the base runtime settings and any selected profile overrides.
> The base script disables animations, sets a short screen timeout, disables
> rotation, configures DNS, enables airplane mode with WiFi, and disables mobile
> data. A device profile can intentionally override these values; for example,
> the default Pixel 5 profile uses normal animation scale, a 60-second screen
> timeout, airplane mode off, WiFi on, and mobile data off to look more like a
> handset at the framework settings layer.

After the first boot completes, a file marker is created to prevent running the initialization again on subsequent starts.

## 📋 **Container Logs**

All logs from the emulator and boot processes are redirected to Docker's standard log system. To view all container logs:

```bash
docker logs -f dockerify-android
```

This includes:
- Supervisor logs
- Android emulator stdout/stderr
- First-boot process logs

## 🏷️ **Versioning and Releases**

Dockerify Android uses GitHub Releases as the source of truth for stable project versions. Publishing a release such as `v1.2.3` creates matching Docker image tags: `1.2.3`, `1.2`, `1`, and `latest`.

Builds from the `main` branch are published as development images using `edge` and `sha-<short-sha>` tags.

## 🚧 **Roadmap**

- [ ] Support for additional Android versions
- [x] Integration with CI/CD pipelines
- [x] ARM Translation support (ndk_translation) for running ARM64 apps on x86_64
- [x] PICO GAPPS installation
- [x] Support Magisk
- [x] Adding web interface of [scrcpy](https://github.com/Shmayro/ws-scrcpy-docker)
- [x] Redirect all logs to container stdout/stderr

## 🐞 **Troubleshooting**

- **`KVM is required to boot the configured x86/x86_64 Android emulator image`:**
  - The default Android 11 x86_64 emulator cannot boot unless `/dev/kvm` is
    available inside the container.
  - Verify it from the host/container:
    ```bash
    ls -l /dev/kvm
    docker run --rm --privileged --platform linux/amd64 ubuntu:20.04 ls -l /dev/kvm
    ```
  - On Docker Desktop for macOS this device is usually not exposed, even when
    image builds work. Run the stack on a Linux host with KVM, or use
    `ALLOW_NO_KVM=1` only after switching to a system image that supports
    software-only boot.

- **ADB Connection Refused:**
  - **Ensure ADB Server is Running:**
    ```bash
    adb start-server -a
    ```
  - **Verify Firewall Settings:** Ensure that port `5555` is open on your server.
  - **Check Emulator Status:** Ensure the emulator has fully booted by checking logs.

    ```bash
    docker logs dockerify-android
    ```

- **First Boot Taking Too Long:**
  - This is normal, as the first boot process needs to perform several operations including:
    - Installing GAPPS (if enabled)
    - Rooting the device (if enabled)
    - Installing ARM Translation (if enabled)
    - Configuring system settings
  - The process can take 10-15 minutes depending on your system performance
  - You can monitor progress with `docker logs -f dockerify-android`

- **ARM/ARM64 Apps Still Not Installing:**
  - Ensure `ARM_TRANSLATION=1` is set in your docker-compose.yml or environment variables
  - Check that the first boot completed successfully with `docker logs dockerify-android | grep -i "ARM translation"`
  - Verify ARM ABIs are available:
    ```bash
    adb shell getprop ro.product.cpu.abilist
    ```
    Should show: `x86_64,x86,arm64-v8a,armeabi-v7a,armeabi`
  - If you enabled `ARM_TRANSLATION` after the first boot, restart the container to run the install step

- **Emulator Not Starting:**
  - **Check Container Logs:**

    ```bash
    docker logs dockerify-android
    ```

- **KVM Not Accessible:**
  - **Verify KVM Installation:**

    ```bash
    lsmod | grep kvm
    ```
  - **Check Permissions:** Ensure your user has access to `/dev/kvm`.

## 🤝 **Contributing**

Contributions are welcome! To contribute:

1. **Fork the Repository**
2. **Create a Feature Branch:**

    ```bash
    git checkout -b feature/YourFeature
    ```

3. **Commit Your Changes:**

    ```bash
    git commit -m "Add Your Feature"
    ```

4. **Push to the Branch:**

    ```bash
    git push origin feature/YourFeature
    ```

5. **Open a Pull Request**

Please ensure your contributions adhere to the project's coding standards and include relevant tests.

## 📄 **License**

This project is licensed under the [MIT License](LICENSE).

## 📫 **Contact**

- **Haroun EL ALAMI**
- **Email:** haroun.dev@gmail.com
- **GitHub:** [shmayro](https://github.com/shmayro)
- **Twitter:** [@HarounDev](https://twitter.com/HarounDev)
