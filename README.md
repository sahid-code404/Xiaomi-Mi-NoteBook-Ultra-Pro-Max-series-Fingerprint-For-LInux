# Xiaomi Mi NoteBook Ultra / Pro / Max — Unified Linux Fingerprint Driver & Power Button Fix

[![Linux Supported](https://img.shields.io/badge/Platform-Linux-FCC624?logo=linux&logoColor=black&style=for-the-badge)](#supported-hardware)
[![Device ID](https://img.shields.io/badge/Hardware-10a5%3A9200-blue?style=for-the-badge&logo=usb)](#supported-hardware)
[![Sensor](https://img.shields.io/badge/Sensor-FPC1022-brightgreen?style=for-the-badge)](#how-it-works)
[![Power Button](https://img.shields.io/badge/Power%20Button-Interactive%20%2F%20No%20Suspend-success?style=for-the-badge)](#power-button--fingerprint-coexistence)
[![Matcher](https://img.shields.io/badge/Matcher-SIGFM%20(OpenCV%20SIFT)-orange?style=for-the-badge)](#biometric-matching-algorithm-sigfm)
[![License](https://img.shields.io/badge/License-LGPL--2.1-blueviolet?style=for-the-badge)](#license)
[![Distros](https://img.shields.io/badge/Distros-Fedora%20%7C%20Ubuntu%20%7C%20Arch%20%7C%20Debian-informational?style=for-the-badge)](#quick-installation)

A unified, production-grade 1-click Linux solution for both the **Fingerprint Cards (FPC) FPC1022** USB fingerprint sensor (`10a5:9200`) and **proper power button handling** on **Xiaomi Mi NoteBook Ultra**, **Mi NoteBook Pro**, and **RedmiBook Pro / Max** laptops.

On these laptops, the fingerprint sensor is physically integrated directly into the power button. Under stock Linux desktop settings, resting a finger on the sensor or pressing it during authentication frequently triggers an accidental system suspend. This repository solves both issues seamlessly in a single unified installer:
1. **FPC1022 Fingerprint Driver**: Full match-on-host biometric support with TLS-PSK USB communication and OpenCV SIFT/FLANN matching (SIGFM).
2. **Power Button Coexistence Fix**: Prevents accidental sleep by setting GNOME's power button action to `'interactive'` (displaying the power off / restart dialog), delegating handling to desktop environment inhibitors, adding the user to the `input` group, and providing clean poweroff fallback in `systemd-logind` when uninhibited (lock screen, TTY, display manager).

---

## Table of Contents

- [Supported Hardware](#supported-hardware)
- [Key Features](#key-features)
- [Power Button & Fingerprint Coexistence](#power-button--fingerprint-coexistence)
- [How It Works](#how-it-works)
- [Quick Installation (1-Step)](#quick-installation)
- [Enrollment & Usage Guide](#enrollment--usage-guide)
  - [Terminal (CLI) Enrollment](#1-terminal-cli-enrollment)
  - [Testing & Verification](#2-testing--verification)
  - [Configuring PAM (sudo, login, lock screen)](#3-configuring-pam-sudo-login-lock-screen)
  - [Desktop GUI (GNOME & KDE)](#4-desktop-gui-integration)
- [Manual Compilation from Source](#manual-compilation-from-source)
- [Uninstallation & Rollback](#uninstallation--rollback)
- [Troubleshooting & FAQ](#troubleshooting--faq)
- [Repository Structure](#repository-structure)
- [Credits & Acknowledgements](#credits--acknowledgements)
- [License](#license)

---

## Supported Hardware

| Laptop Model | Display | USB ID | Sensor Controller | Architecture | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Xiaomi Mi NoteBook Ultra** | 15.6" 3.2K 90Hz | `10a5:9200` | FPC1022 (Match-on-Host) | x86_64 | **Fully Supported** |
| **Xiaomi Mi NoteBook Pro** | 14" / 15.6" 2.5K | `10a5:9200` | FPC1022 (Match-on-Host) | x86_64 | **Fully Supported** |
| **RedmiBook Pro / Max Series** | Various | `10a5:9200` | FPC1022 (Match-on-Host) | x86_64 | **Fully Supported** |

Verify your hardware in the terminal:

```bash
lsusb -d 10a5:9200
```

Expected output:
```text
Bus 003 Device 003: ID 10a5:9200 FPC FPC Sensor Controller
```

---

## Key Features

- **Unified 1-Click Installer**: Deploys the FPC1022 biometric driver, early-boot hardware power button wake service, and desktop coexistence policies in one automated step.
- **Cold-Boot & Resume Power Button Wake**: Fixes the dormant power button on fresh boots and after suspend by signaling USB S0 working state to the FPC microcontroller immediately upon boot and resume.
- **Accidental Suspend Prevention**: Reconfigures GNOME to `'interactive'` power button action, showing the power dialog instead of putting the laptop to sleep when touching the sensor.
- **Clean Logind Poweroff Fallback**: Configures `/etc/systemd/logind.conf.d/10-power-button.conf` (`PowerKeyIgnoreInhibited=no`, `HandlePowerKey=poweroff`) to honor desktop inhibitors while ensuring clean shutdown when uninhibited (lock screen, TTY, display manager).
- **Seamless Linux PAM Integration**: Works natively with `fprintd` and standard Linux PAM (`sudo`, GDM, SDDM, LightDM, Polkit, lock screens).
- **Desktop Settings Integration**: Direct GUI support in GNOME Settings (`Settings -> Users -> Fingerprint Login`) and KDE System Settings.
- **Encrypted USB Channel**: Implements host-driven **TLS-PSK tunneling** over USB bulk endpoints (host as TLS server, sensor as TLS client).
- **SIGFM SIFT Biometric Matcher**: Overcomes the physical limitations of small 112×88 pixel sensors where traditional NIST NBIS Bozorth3 minutiae matching fails, using OpenCV SIFT keypoint descriptors with geometric consistency checks.
- **Package Manager Shielding**: Automatically guards against package updates (`dnf upgrade`, `apt upgrade`, `pacman -Syu`) overwriting the driver with unpatched stock packages.
- **SELinux Compatible**: Automatically configures the appropriate `lib_t` SELinux file contexts so enforcement remains enabled with zero AVC denials.
- **1-Click Rollback**: Fully reversible using `./uninstall.sh` to restore your pristine factory distribution packages and clean power settings anytime.

---

## Power Button & Fingerprint Coexistence

### The Problem

On the Xiaomi Mi NoteBook Ultra / Pro / Max series, the biometric sensor and the physical power button are mechanically integrated into a single button module on the FPC1022 flexible circuit:

1. **Cold Boot Dormancy**:
   - The physical power button switch line connects through the FPC1022 microcontroller to the motherboard ACPI/Intel PCH `PWRBTN#` line.
   - On cold boot (power on from complete off), the FPC microcontroller powers up in a cold uninitialized / sleep state, gating the power switch pass-through line.
   - On Linux, `fprintd.service` is D-Bus activated on demand and never touches the USB device at boot.
   - Consequently, pressing the power button produces **zero ACPI or input events** until an application triggers fingerprint authentication (e.g. `sudo` or `fprintd-verify`), which causes `libfprint` to send `CMD_INDICATE_S_STATE` (S0) and wakes the MCU.
2. **Accidental Suspend**:
   - Resting a finger on the sensor or pressing slightly during fingerprint enrollment/verification can register a mechanical `KEY_POWER` keypress event.
   - By default, modern Linux desktop environments (such as GNOME) configure the power button action to `suspend`.
   - Consequently, users trying to authenticate or enroll prints often suffered abrupt, unwanted system suspends.

### The Unified Fix

This repository addresses both the hardware microcontroller state and the desktop session policies:

1. **Early Hardware Initializer (`tools/fpc1022-wake.c` & `configs/fpc1022-wake.service`)**:
   - A fast, lightweight C utility (`fpc1022-wake`) sends `CMD_INDICATE_S_STATE` (`0x08`, value `0x0010` = S0) via a standalone USB control transfer directly to `10a5:9200`.
   - A dedicated systemd boot unit (`/etc/systemd/system/fpc1022-wake.service`) ensures S0 initialization completes cleanly at boot before user login.
   - A systemd-sleep hook (`/usr/lib/systemd/system-sleep/fpc1022-wake`) re-asserts S0 state instantly when waking from suspend/hibernate.
   - An access udev rule (`/etc/udev/rules.d/99-fpc1022-wake.rules`) ensures proper active user session tagging without triggering re-enumeration feedback loops.
   - **Result**: The physical power button works immediately from the second the laptop boots up or wakes from sleep, while biometric scanning remains fully responsive with zero USB reset cycles.
2. **`systemd-logind` Configuration (`configs/10-power-button.conf`)**:
   ```ini
   [Login]
   HandlePowerKey=poweroff
   HandlePowerKeyLongPress=poweroff
   PowerKeyIgnoreInhibited=no
   HoldoffTimeoutSec=0
   ```
   - Setting `PowerKeyIgnoreInhibited=no` ensures that while a desktop session (like GNOME) is running with an active inhibitor, `logind` defers power key events to the desktop environment. When no desktop inhibitor is present (such as at the login screen, lock screen, or a TTY), pressing the power button safely performs a clean system `poweroff` instead of an unstable sleep state.
   - Setting `HoldoffTimeoutSec=0` disables systemd's default 30-second post-resume / post-boot ignore period, ensuring instant response to every power key press without dropped clicks or lag after waking.
3. **GNOME Dconf Configuration & Lock (`/etc/dconf/db/local.d/01-power-button`)**:
   Sets `org.gnome.settings-daemon.plugins.power power-button-action` to `'interactive'` and locks it system-wide. Instead of suspending the machine, a short press prompts the user with the interactive power dialog (Power Off / Restart / Cancel), avoiding unwanted sleep cycles.
4. **User Input Group**:
   Adds the target user to the `input` group (`usermod -a -G input "$TARGET_USER"`) for direct event device access.

---

## How It Works

### 1. Hardware Communication & TLS-PSK Tunneling

The FPC1022 controller is a **match-on-host** biometric device. Unlike match-on-chip sensors that store prints inside internal secure hardware, the FPC1022 streams raw captured frames to the host operating system. To protect biometric data traversing the external USB bus, the device establishes a hardware-accelerated **TLS-PSK (Pre-Shared Key)** encrypted channel:

1. The host `libfprint` driver acts as a **TLS server**.
2. The fingerprint controller acts as a **TLS client**.
3. Cryptographic handshake generates session keys for USB bulk transfers.
4. Plaintext sensor control frames and raw pixel buffers are transmitted through the encrypted tunnel.

### 2. Biometric Matching Algorithm (SIGFM)

Standard `libfprint` uses **NIST NBIS (Bozorth3)**, which requires at least 15–20 clear minutiae points (ridge endings and bifurcations). Because the FPC1022 sensor has an ultra-compact surface area capturing only **112×88 pixels**, the number of detectable minutiae points is insufficient, leading to false rejection rates (FRR) nearing 100% on stock drivers.

To solve this:
- Images are upscaled 2× via nearest-neighbor interpolation.
- The **SIGFM (SIFT-based)** algorithm extracts scale-invariant keypoint features and descriptors via OpenCV.
- During verification, descriptors undergo nearest-neighbor distance ratio matching combined with geometric consistency pruning to confirm genuine user identity securely and reliably.

---

## Quick Installation

Clone this repository and run the automated installer:

```bash
git clone https://github.com/sahid-code404/Xiaomi-Notebook-Ultra-Max-Series-Fingerprint-For-Linux.git
cd Xiaomi-Notebook-Ultra-Max-Series-Fingerprint-For-Linux
sudo ./install.sh
```

### What `install.sh` Does Automatically:
1. Detects your Linux distribution (Fedora / Ubuntu / Debian / Arch / etc.).
2. Checks for sensor `10a5:9200` via `lsusb`.
3. Installs `fprintd` and required system libraries.
4. Deploys the patched `libfprint` and SIGFM OpenCV runtime dependencies (`/usr/local/lib64/fprint-deps`).
5. Sets required SELinux permissions (`lib_t`).
6. Configures package manager protection (`excludepkgs=libfprint*` in `/etc/dnf/dnf.conf`, `apt-mark hold`, or `IgnorePkg` in pacman).
7. Compiles and installs the early hardware wake utility `/usr/local/bin/fpc1022-wake`.
8. Deploys `/etc/udev/rules.d/99-fpc1022-wake.rules` to configure session access tags.
9. Deploys and enables `/etc/systemd/system/fpc1022-wake.service` for system boot initialization.
10. Installs `/usr/lib/systemd/system-sleep/fpc1022-wake` to restore power button state upon waking from suspend/hibernate.
11. Installs `/etc/systemd/logind.conf.d/10-power-button.conf` (`HandlePowerKey=poweroff`, `PowerKeyIgnoreInhibited=no`) and reloads `systemd-logind`.
12. Configures GNOME power button action to `'interactive'` via `/etc/dconf/db/local.d/01-power-button` and updates `dconf`.
13. Adds target user to the `input` group for direct event handling.
14. Restarts `fprintd.service` and executes immediate hardware initialization.

---

## Enrollment & Usage Guide

### 1. Terminal (CLI) Enrollment

To enroll your fingerprint for the current user:

```bash
fprintd-enroll
```

To enroll a specific finger (e.g. right index finger):

```bash
fprintd-enroll -f right-index-finger $USER
```

Available finger identifiers:
- `right-thumb`, `right-index-finger`, `right-middle-finger`, `right-ring-finger`, `right-little-finger`
- `left-thumb`, `left-index-finger`, `left-middle-finger`, `left-ring-finger`, `left-little-finger`

> **Tips for 5-Stage Enrollment on Small Sensors:**
> - The sensor will prompt you **5 times** (`Enroll result: enroll-stage-passed`).
> - For stage 1 and 2, place the center of your finger pad directly on the sensor.
> - For stages 3 to 5, gently tilt your finger slightly to capture edge areas.
> - Press firmly and steadily until you see `Enroll result: enroll-completed`.

### 2. Testing & Verification

Once enrolled, verify that recognition works:

```bash
fprintd-verify
```

When prompted, place your finger on the sensor. You should see:
```text
Using device /net/reactivated/Fprint/Device/0
Listing enrolled fingers:
 - #0: right-index-finger
Verify result: verify-match (done)
```

To check all enrolled fingerprints:
```bash
fprintd-list $USER
```

### 3. Configuring PAM (sudo, login, lock screen)

#### Fedora Linux:
```bash
sudo authselect enable-feature with-fingerprint
sudo authselect apply-changes
```

#### Ubuntu / Debian / Pop!_OS:
```bash
sudo pam-auth-update
```
*(Ensure "Fingerprint authentication" is checked using the spacebar, then press Tab and Enter).*

#### Arch Linux:
Add the following line to the top of `/etc/pam.d/system-auth` and `/etc/pam.d/sudo`:
```text
auth      sufficient pam_fprintd.so
```

Now try running `sudo ls` in a new terminal — you will be prompted to touch the fingerprint reader!

### 4. Desktop GUI Integration

- **GNOME (Fedora Workstation / Ubuntu Desktop)**:
  Open **Settings** &rarr; **Users** &rarr; Select your account &rarr; Enable **Fingerprint Login** &rarr; Follow the on-screen prompts.
- **KDE Plasma**:
  Open **System Settings** &rarr; **Users** &rarr; **Fingerprint Authentication**.

---

## Manual Compilation from Source

If you prefer building from source code rather than using pre-compiled binaries:

```bash
sudo ./install.sh --build
```

Or execute the build steps manually:

### 1. Install Prerequisites

**Fedora:**
```bash
sudo dnf install -y meson ninja-build gcc gcc-c++ glib2-devel libgusb-devel \
    pixman-devel openssl-devel libgudev-devel polkit-devel systemd-devel \
    doctest-devel opencv-devel fprintd fprintd-pam
```

**Ubuntu / Debian:**
```bash
sudo apt update
sudo apt install -y meson ninja-build build-essential libglib2.0-dev libgusb-dev \
    libpixman-1-dev libssl-dev libgudev-1.0-dev libpolkit-gobject-1-dev \
    doctest-dev libopencv-dev fprintd
```

**Arch Linux:**
```bash
sudo pacman -S --needed meson ninja gcc glib2 libgusb pixman openssl libgudev \
    polkit doctest opencv fprintd
```

### 2. Configure and Compile

**Fedora / RHEL:**
```bash
cd src/libfprint
meson setup build --prefix=/usr --libdir=/usr/lib64 -Ddrivers=all -Ddoc=false -Dintrospection=false -Dinstalled-tests=false -Dudev_hwdb=enabled
ninja -C build
sudo ninja -C build install
sudo chcon -t lib_t /usr/lib64/libfprint-2.so* 2>/dev/null || true
sudo restorecon -v /usr/lib64/libfprint-2.so* 2>/dev/null || true
sudo ldconfig
sudo systemctl restart fprintd.service
```

**Ubuntu / Debian:**
```bash
cd src/libfprint
meson setup build --prefix=/usr -Ddrivers=all -Ddoc=false -Dintrospection=false -Dinstalled-tests=false -Dudev_hwdb=enabled
ninja -C build
sudo ninja -C build install
sudo ldconfig
sudo systemctl restart fprintd.service
```

**Arch Linux:**
```bash
cd src/libfprint
meson setup build --prefix=/usr --libdir=/usr/lib -Ddrivers=all -Ddoc=false -Dintrospection=false -Dinstalled-tests=false -Dudev_hwdb=enabled
ninja -C build
sudo ninja -C build install
sudo ldconfig
sudo systemctl restart fprintd.service
```

---

## Uninstallation & Rollback

To completely remove the driver, reset power button handling, and restore your clean distribution stock `libfprint`:

```bash
sudo ./uninstall.sh
```

The rollback script:
1. Re-enables distribution updates by clearing package manager exclusions.
2. Reinstalls the official stock `libfprint` package from distribution repositories.
3. Cleans up custom runtime libraries and linker configurations.
4. Stops, disables, and deletes `/etc/systemd/system/fpc1022-wake.service`.
5. Removes `/etc/udev/rules.d/99-fpc1022-wake.rules` and reloads udev.
6. Removes `/usr/lib/systemd/system-sleep/fpc1022-wake` and `/usr/local/bin/fpc1022-wake`.
7. Removes `/etc/systemd/logind.conf.d/10-power-button.conf` and reloads `systemd-logind`.
8. Removes `/etc/dconf/db/local.d/01-power-button` and updates `dconf`.
9. Restarts `fprintd.service`.

---

## Troubleshooting & FAQ

### 1. `lsusb` does not show `10a5:9200`
- Ensure the fingerprint reader is enabled in your laptop BIOS/UEFI settings.
- Check power management or reboot with the laptop connected to AC power.

### 2. `fprintd.service: Failed to claim device`
- Ensure no other service is monopolizing the sensor:
  ```bash
  sudo systemctl restart fprintd.service
  ```
- Check service logs:
  ```bash
  journalctl -u fprintd.service -e -n 50
  ```

### 3. SELinux AVC Denial on Fedora
If SELinux blocks `fprintd` from loading libraries, re-apply the context:
```bash
sudo chcon -t lib_t /usr/lib64/libfprint-2.so*
sudo chcon -R -t lib_t /usr/local/lib64/fprint-deps
sudo restorecon -Rv /usr/lib64/libfprint* /usr/local/lib64/fprint-deps
```

### 4. System updates broke fingerprint authentication
If a major distribution upgrade replaced the library, re-run:
```bash
cd Xiaomi-Notebook-Ultra-Max-Series-Fingerprint-For-Linux
sudo ./install.sh
```
Ensure `/etc/dnf/dnf.conf` retains `excludepkgs=libfprint*`.

---

## Repository Structure

```text
├── README.md             # Complete documentation and usage guide
├── LICENSE               # LGPL-2.1 Open-Source License
├── install.sh            # Automated unified installer (driver + power button fix)
├── uninstall.sh          # Safe rollback script (stock libfprint + clean power state)
├── .gitignore            # Git ignore rules for build and cache artifacts
├── configs/              # Managed system configuration drop-ins
│   ├── 10-power-button.conf     # systemd-logind power button override
│   ├── 99-fpc1022-wake.rules    # udev boot wake rule for 10a5:9200
│   ├── fpc1022-wake.service     # early boot systemd initialization service
│   └── fpc1022-sleep-wake       # systemd-sleep resume wake hook
├── tools/                # Hardware utility source code
│   └── fpc1022-wake.c           # Lightweight C utility for FPC1022 S0 state wake
├── packages/             # Pre-built distribution packages and runtime libraries
│   ├── fedora/           # Tested Fedora binaries and OpenCV runtime libraries
│   │   ├── libfprint-2.so.2.0.0
│   │   └── fprint-deps/  # Runtime OpenCV, BLAS, LAPACK, and TBB libraries
│   ├── deb/              # Ubuntu / Debian binary package (.deb)
│   └── arch/             # Arch Linux binary package (.pkg.tar.zst)
├── patches/              # Clean standalone git patches for upstream libfprint
│   ├── 0001-Add-SIGFM-SIFT-based-matching-algorithm-for-small-ar.patch
│   ├── 0002-Add-fpc1022-driver-for-FPC-Disum-match-on-host-senso.patch
│   ├── 0003-device-Validate-gallery-equality-only-for-raw-prints.patch
│   ├── 0004-sigfm-Harden-matching-and-template-handling.patch
│   ├── 0005-fpc1022-Harden-TLS-framing-and-capture-lifecycle.patch
│   └── 0006-packaging-Add-native-packages-and-Ubuntu-CI.patch
└── src/
    └── libfprint/        # Full pristine libfprint source tree with driver & matcher
```

---

## Credits & Acknowledgements

- **Sergey Subbotin (`ssubbotin`)**: Core FPC1022 driver implementation and SIGFM matcher architecture.
- **Omkar Chandorkar (`gotenksIN`)**: TLS framing hardening, template handling, and packaging CI.
- **Jason Huang**: Original reverse engineering and initial libfprint merge request.
- **Natalie Klestrup Röijezon & Tooniis**: Foundational work on small-area SIFT biometric matching.
- **Sahidul Haque ([@sahid-code404](https://github.com/sahid-code404))**: Fedora integration, runtime bundling, packaging, automated installation tooling, and maintenance for the Xiaomi Notebook community.

---

## License

This project is licensed under the **GNU Lesser General Public License version 2.1 (LGPL-2.1)** in accordance with the upstream `libfprint` project. See [LICENSE](LICENSE) for the full text.
