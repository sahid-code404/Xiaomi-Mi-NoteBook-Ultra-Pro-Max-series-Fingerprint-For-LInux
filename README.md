# Xiaomi Mi NoteBook Ultra / Pro / Max — Linux Fingerprint Driver

[![Linux Supported](https://img.shields.io/badge/Platform-Linux-FCC624?logo=linux&logoColor=black&style=for-the-badge)](#supported-hardware)
[![Device ID](https://img.shields.io/badge/Hardware-10a5%3A9200-blue?style=for-the-badge&logo=usb)](#supported-hardware)
[![Sensor](https://img.shields.io/badge/Sensor-FPC1022-brightgreen?style=for-the-badge)](#how-it-works)
[![Matcher](https://img.shields.io/badge/Matcher-SIGFM%20(OpenCV%20SIFT)-orange?style=for-the-badge)](#biometric-matching-algorithm-sigfm)
[![License](https://img.shields.io/badge/License-LGPL--2.1-blueviolet?style=for-the-badge)](#license)
[![Distros](https://img.shields.io/badge/Distros-Fedora%20%7C%20Ubuntu%20%7C%20Arch%20%7C%20Debian-informational?style=for-the-badge)](#quick-installation)

A production-grade Linux driver and user-space integration for the **Fingerprint Cards (FPC) FPC1022** USB fingerprint sensor (`10a5:9200`) found on **Xiaomi Mi NoteBook Ultra**, **Mi NoteBook Pro**, and **RedmiBook Pro / Max** laptops.

This repository provides ready-to-run installation scripts, pre-built distribution packages (Fedora, Ubuntu/Debian, Arch Linux), standalone upstream patches, and the complete source code tree.

---

## Table of Contents

- [Supported Hardware](#supported-hardware)
- [Key Features](#key-features)
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

- **Seamless Linux Integration**: Works natively with `fprintd` and standard Linux PAM (`sudo`, GDM, SDDM, LightDM, Polkit, lock screens).
- **Desktop Settings Integration**: Direct GUI support in GNOME Settings (`Settings -> Users -> Fingerprint Login`) and KDE System Settings.
- **Encrypted USB Channel**: Implements host-driven **TLS-PSK tunneling** over USB bulk endpoints (host as TLS server, sensor as TLS client).
- **SIGFM SIFT Biometric Matcher**: Overcomes the physical limitations of small 112×88 pixel sensors where traditional NIST NBIS Bozorth3 minutiae matching fails, using OpenCV SIFT keypoint descriptors with geometric consistency checks.
- **Package Manager Shielding**: Automatically guards against package updates (`dnf upgrade`, `apt upgrade`, `pacman -Syu`) overwriting the driver with unpatched stock packages.
- **SELinux Compatible**: Automatically configures the appropriate `lib_t` SELinux file contexts so enforcement remains enabled with zero AVC denials.
- **1-Click Rollback**: Fully reversible using `./uninstall.sh` to restore your pristine factory distribution packages anytime.

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
7. Restarts `fprintd.service` and validates sensor readiness.

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

To completely remove the driver and restore your clean distribution stock `libfprint`:

```bash
sudo ./uninstall.sh
```

The rollback script:
1. Re-enables distribution updates by clearing package manager exclusions.
2. Reinstalls the official stock `libfprint` package from distribution repositories.
3. Cleans up custom runtime libraries and linker configurations.
4. Restarts `fprintd.service`.

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
├── install.sh            # Automated distribution-agnostic installer
├── uninstall.sh          # Safe rollback script to stock libfprint
├── .gitignore            # Git ignore rules for build and cache artifacts
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
