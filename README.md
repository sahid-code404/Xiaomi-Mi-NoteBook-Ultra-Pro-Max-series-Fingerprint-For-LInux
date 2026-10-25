# Xiaomi FPC1022 for Linux

[![Linux](https://img.shields.io/badge/platform-Linux-FCC624?logo=linux&logoColor=black)](#compatibility)
[![USB ID](https://img.shields.io/badge/sensor-10a5%3A9200-blue)](#compatibility)
[![License](https://img.shields.io/badge/license-LGPL--2.1--or--later-blueviolet)](LICENSE)
[![CI](https://github.com/sahid-code404/xiaomi-fprint-driver/actions/workflows/quality.yml/badge.svg)](https://github.com/sahid-code404/xiaomi-fprint-driver/actions/workflows/quality.yml)

Linux integration for the **FPC1022 / FPC DISUM match-on-host fingerprint sensor** found in some Xiaomi laptops.

> [!WARNING]
> **Experimental project.** Hardware compatibility and biometric security have not been independently validated. Keep password login available and review scripts before running them as root.

## At a glance

- FPC1022 driver integrated with `libfprint`
- Installer, source-build option, and rollback script
- Optional power-button integration
- No automatic PAM changes, broad `input` group access, or package holds

## Compatibility

The driver targets USB **`10a5:9200`**. Check your actual sensor first:

```bash
lsusb -d 10a5:9200
```

If it is not detected, do not assume your device is supported.

## Install

```bash
git clone https://github.com/sahid-code404/xiaomi-fprint-driver.git
cd xiaomi-fprint-driver
less install.sh
sudo ./install.sh
```

Useful options:

| Option | Purpose |
| --- | --- |
| `--build` | Build from the bundled source |
| `--power-button` | Opt in to power-button and resume integration |
| `--protect-enrollment` | Require administrator authorization for system-wide fingerprint enrollment/deletion |
| `--verbose` | Show command output |
| `--help` | Show all options |

Example: `sudo ./install.sh --build`

Power-button and enrollment-policy changes are **opt-in**. Review the related files in `configs/` before enabling them.

## Test before login

```bash
sudo systemctl restart fprintd.service
fprintd-enroll
fprintd-verify
```

Test several times, including after reboot and suspend/resume. Only then configure fingerprint login with your distribution's documented PAM tools. This installer does **not** enable PAM automatically.

For troubleshooting:

```bash
journalctl -u fprintd.service -b --no-pager
fprintd-list "$USER"
lsusb -d 10a5:9200
```

## Uninstall

```bash
sudo ./uninstall.sh
```

The default rollback does not remove unrelated packages. Orphan cleanup is separate and requires explicit opt-in:

```bash
sudo ./uninstall.sh --cleanup-orphans
```

Review the package manager's proposed removals before confirming.

## Development

```bash
make check
make build
make unit-test
```

See [docs/TESTING.md](docs/TESTING.md) for validation steps and [CONTRIBUTING.md](CONTRIBUTING.md) to contribute.

## Security & limitations

- No independently measured **FAR/FRR** or presentation-attack/liveness results are available.
- The public implementation and protocol compatibility are not proof of sensor authenticity or production-grade biometric security.
- An OS update may replace the manually installed `libfprint` library. Re-test after system or `libfprint` upgrades.
- Keep a tested password-based recovery path.

Report security concerns privately as described in [SECURITY.md](SECURITY.md).

## Credits & license

This project includes and modifies `libfprint` code licensed under **LGPL-2.1-or-later**. See [LICENSE](LICENSE) and source-file notices for details. Driver and matcher attribution is retained in the source.

Maintained by [Sahidul Haque](https://github.com/sahid-code404).
