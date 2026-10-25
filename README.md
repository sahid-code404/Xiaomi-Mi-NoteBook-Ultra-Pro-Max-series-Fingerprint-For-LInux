# Xiaomi FPC1022 for Linux

[![Linux](https://img.shields.io/badge/platform-Linux-FCC624?logo=linux&logoColor=black)](#compatibility)
[![Sensor](https://img.shields.io/badge/FPC1022-10a5%3A9200-blue)](#compatibility)
[![License](https://img.shields.io/badge/license-LGPL--2.1--or--later-blueviolet)](LICENSE)
[![CI](https://github.com/sahid-code404/xiaomi-fprint-driver/actions/workflows/quality.yml/badge.svg)](https://github.com/sahid-code404/xiaomi-fprint-driver/actions/workflows/quality.yml)

Linux support for the **FPC1022 / FPC DISUM match-on-host fingerprint sensor** found in some Xiaomi and Redmi laptops.

> [!WARNING]
> **Experimental.** Hardware compatibility and biometric security are not independently validated. Keep password login available and review scripts before running them as root.

## Features

- FPC1022 support integrated with `libfprint`
- Native-package path where a supported package is available
- Update diagnostic: `fpc1022-doctor`
- Optional power-button and enrollment-policy integration
- Backup-aware rollback and automated quality checks

## Compatibility

The driver targets USB ID **`10a5:9200`**. Check your actual sensor:

```bash
lsusb -d 10a5:9200
```

A laptop model name alone does not guarantee the sensor is supported.

## Install

```bash
git clone https://github.com/sahid-code404/xiaomi-fprint-driver.git
cd xiaomi-fprint-driver
less install.sh
sudo ./install.sh
```

Optional integrations are off by default:

| Option | What it does |
| --- | --- |
| `--power-button` | Configure power-button handling and resume initialization |
| `--protect-enrollment` | Require administrator authorization for system-wide fingerprint enrollment/deletion |
| `--build` | Build a native package from the included source |
| `--verbose` | Show command output |

## Test before login

```bash
sudo systemctl restart fprintd.service
fprintd-enroll
fprintd-verify
```

Test several enrollments and verifications, including after reboot and suspend/resume. Configure fingerprint login manually with your distribution's documented PAM tool **only after those tests pass**. The installer does not enable PAM automatically.

## Kernel and system updates

This driver runs in **userspace through libfprint and USB**; it is not a custom kernel module and does not use DKMS. Ordinary kernel updates therefore generally do not require rebuilding a kernel module, but they are not a guarantee against changes to USB behavior, firmware, suspend/resume, systemd, OpenSSL, fprintd, or libfprint.

After a system update and reboot:

```bash
fpc1022-doctor
fprintd-verify
```

The diagnostic can check basic installation and device state; it cannot prove recognition accuracy or reliable suspend/resume on your laptop. The installer does not freeze system package updates. Prefer native packages where provided, and re-test after libfprint or operating-system updates.

## Uninstall

```bash
sudo ./uninstall.sh
```

This restores distribution packages and tracked configuration files. Orphan-package cleanup is disabled by default; explicitly request it with `sudo ./uninstall.sh --cleanup-orphans` and review the package manager's proposed removals.

## Development

```bash
make check
make build
make unit-test
```

See [CONTRIBUTING.md](CONTRIBUTING.md), [docs/TESTING.md](docs/TESTING.md), and [SECURITY.md](SECURITY.md).

## Security limits

- No independently measured false-acceptance/false-rejection rates or presentation-attack/liveness results are published.
- Encrypted transport and protocol compatibility do not prove that the physical sensor is authentic.
- Do not rely on this project as the sole control for high-assurance systems without independent evaluation.

## Credits and license

Driver and matcher contributors are credited in the source files and project history. The project includes and modifies `libfprint` code licensed under **LGPL-2.1-or-later**; see [LICENSE](LICENSE).

Maintained by [Sahidul Haque](https://github.com/sahid-code404).
