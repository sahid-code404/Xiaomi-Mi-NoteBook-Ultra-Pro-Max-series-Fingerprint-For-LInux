# Xiaomi FPC1022 Fingerprint Driver for Linux

[![Linux](https://img.shields.io/badge/platform-Linux-FCC624?logo=linux&logoColor=black)](#supported-hardware)
[![USB ID](https://img.shields.io/badge/USB-10a5%3A9200-blue)](#supported-hardware)
[![License](https://img.shields.io/badge/license-LGPL--2.1--or--later-blueviolet)](LICENSE)
[![Quality checks](https://github.com/sahid-code404/xiaomi-fprint-driver/actions/workflows/quality.yml/badge.svg)](https://github.com/sahid-code404/xiaomi-fprint-driver/actions/workflows/quality.yml)

A community-maintained Linux integration for the FPC1022 / FPC DISUM match-on-host fingerprint sensor identified as USB **10a5:9200**, with an optional Xiaomi laptop power-button initialization helper.

> **Status: experimental.** Hardware support and installation have not been validated across every laptop, firmware revision, distribution, or desktop environment. Review scripts before running them as root. Do not enable fingerprint login until enrollment and repeated verification work reliably on your machine.

## Features

- Adds an FPC1022 driver to the vendored `libfprint` source tree.
- Uses the sensor's TLS-PSK transport and host-side SIGFM/SIFT image matching.
- Provides a distro-aware installer with a source-build option.
- Offers optional power-button initialization for machines where the sensor is detected.
- Includes an uninstaller and backups for files managed by this installer.
- Leaves PAM/fingerprint login configuration opt-in and does not add users to the broad `input` group.

## Supported hardware

The supported hardware identifier is:

| Property | Value |
| --- | --- |
| USB vendor:product | `10a5:9200` |
| Driver family | FPC1022 / FPC DISUM match-on-host |
| Image size reported by the driver | 112 × 88 pixels before scaling |
| Prebuilt package architecture | x86-64 where a matching package is provided |

Laptop marketing names alone are not enough to establish compatibility. Before installing, check the actual sensor:

```bash
lsusb -d 10a5:9200
```

If no device is returned, do not assume that another fingerprint sensor will work with this driver. The installer asks before continuing when the sensor is absent, and it skips the power-button modifications when the device has not been detected.

## Install

Read the installer before granting it root privileges:

```bash
less install.sh
less uninstall.sh
```

Then install from a local clone:

```bash
git clone https://github.com/sahid-code404/xiaomi-fprint-driver.git
cd xiaomi-fprint-driver
sudo ./install.sh
```

Available options:

| Option | Meaning |
| --- | --- |
| `--build` | Build the vendored source instead of using an available prebuilt package/library |
| `--power-button` | Opt in to the power-button/logind configuration and resume helper |
| `--protect-enrollment` | Opt in to a system-wide administrator-authorization rule for fingerprint enrollment/deletion |
| `--yes` | Continue if the sensor is not detected |
| `--verbose` | Show command output for troubleshooting |
| `--help` | Show options and exit |

For example, to build from source:

```bash
sudo ./install.sh --build
```

The power-button helper and logind policy are separate, opt-in changes. Enable them only if you need that integration:

```bash
sudo ./install.sh --power-button
```

These options can be combined, for example `sudo ./install.sh --build --power-button`.

The source build needs the development dependencies for GLib/GIO, libgusb, OpenSSL, OpenCV, Meson, Ninja, a C/C++ toolchain, and the distribution-specific integration libraries. The installer attempts to install known prerequisites on supported package-manager families.

### Updates and package management

This installer intentionally **does not lock or exclude system packages**. That avoids silently blocking security and bug-fix updates. However, a distribution update can replace a manually installed library or cause the patched driver to stop loading. Re-test the reader after a `libfprint` or distribution upgrade and rebuild/reinstall this project if necessary.

For Fedora's bundled-library path, dependencies are placed in a private directory and loaded through a per-library RUNPATH instead of adding that directory to the global dynamic-loader configuration. The main driver library is still installed over the distribution library, so an OS update may replace it.

The long-term preferred distribution model is a native, versioned package with explicit dependencies and a clean upgrade path rather than replacing a package-owned shared library in place.

## Test before enabling login

First test the driver without changing the login stack:

```bash
systemctl restart fprintd.service
fprintd-enroll
fprintd-verify
```

Use the same finger repeatedly and test after reboot and suspend/resume. If enrollment or verification is intermittent, keep password authentication available and collect logs:

```bash
journalctl -u fprintd.service -b --no-pager
lsusb -d 10a5:9200
fprintd-list "$USER"
```

Only after successful repeated testing should you choose to enable fingerprint authentication using your distribution's documented PAM tool. This project does not enable PAM automatically.

- **Fedora:** inspect `authselect current` and follow Fedora's documentation for the active profile before enabling `with-fingerprint`.
- **Ubuntu/Debian:** use `sudo pam-auth-update` and select the fingerprint option if it is available.
- **Arch Linux:** configure the distribution's PAM stack according to the Arch Wiki and verify password fallback before relying on fingerprint login.

PAM changes can affect login and privilege escalation. Keep a tested password-based recovery path and avoid editing PAM files by hand without a backup.

## Power-button integration

When the fingerprint sensor is detected, the installer can configure the FPC1022 S0 initialization helper, a udev rule, a systemd unit, and a resume hook. It also installs a logind drop-in for the power-key policy.

The drop-in changes power-button behavior, so review `configs/10-power-button.conf` before installing. This project backs up managed files that already exist, then restores those backups during uninstallation. Older releases did not record all pre-existing state; see the rollback notes below when removing an older installation.

No user is added to the `input` group by the installer. USB access is scoped to the sensor's vendor/product identifier by the supplied udev rule.

A separate optional policy can require administrator authorization for fprintd enrollment/deletion. Enable it explicitly with `sudo ./install.sh --protect-enrollment`; it affects the system's fprintd policy, not just this sensor. Review `configs/50-fprintd-auth.rules` before opting in.

## Uninstall and rollback

Run the default rollback:

```bash
sudo ./uninstall.sh
```

The normal path does not run package-manager orphan cleanup. If you explicitly want to review orphan cleanup, run:

```bash
sudo ./uninstall.sh --cleanup-orphans
```

The package manager will show its proposed removals; review the plan carefully. No packages are automatically removed by the default uninstall.

The uninstaller restores a saved stock library when the installer created a backup, reinstalls distribution packages where supported, and restores files listed in the installer's managed-file manifest. For older installations that predate the manifest, it cannot reliably know whether PAM options, DNF exclusions, Pacman ignores, or overwritten config files existed beforehand. Review these manually rather than blindly resetting the system:

```bash
# Fedora: inspect any legacy exclusion
grep -n 'libfprint' /etc/dnf/dnf.conf 2>/dev/null

# Arch: inspect package exclusions
grep -n 'libfprint' /etc/pacman.conf 2>/dev/null

# Debian/Ubuntu: inspect package holds and active authentication profile
apt-mark showhold
sudo pam-auth-update
```

Do not remove an entry if you added it yourself for another reason.

## Build and validate from source

The bundled source is built with Meson and Ninja. A typical source build is:

```bash
cd src/libfprint
meson setup build --prefix=/usr -Ddrivers=all -Ddoc=false -Dintrospection=false -Dinstalled-tests=false
ninja -C build
meson test -C build --print-errorlogs
```

The package and installer paths vary by distribution. On Debian/Ubuntu, the build uses the host multiarch library directory when it is available rather than assuming that every system stores shared libraries in `/usr/lib` or `/usr/lib64`.

For developer checks:

```bash
bash -n install.sh uninstall.sh
sh -n configs/fpc1022-sleep-wake
bash tests/smoke.sh
```

See [docs/TESTING.md](docs/TESTING.md) for the release checklist and test-report template.

## Security model and limitations

- The sensor communicates over a TLS-PSK channel and the driver performs host-side fingerprint matching. Protocol compatibility does not itself prove that a physical sensor is authentic.
- Some key-derivation and sealing constants are present in the public driver source. Do not treat the HMAC check or encrypted transport as a guarantee against a determined attacker with physical access or the ability to inspect the implementation.
- The project currently does not publish independently measured false-acceptance rate (FAR), false-rejection rate (FRR), presentation-attack/liveness performance, or a broad hardware compatibility matrix.
- SIFT-based matching is a matching implementation, not proof of production-grade biometric security. Do not use this project as the sole protection for high-assurance systems without independent evaluation.
- Root-level installers can affect the operating system. Review changes, keep backups, and have a recovery route before installing.

Please report security issues privately to the repository maintainer rather than publishing details that could put users at risk. See [SECURITY.md](SECURITY.md).

## Credits and license

The driver and matcher incorporate work from Sergey Subbotin, Omkar Chandorkar, Jason Huang, and the SIGFM research contributors including Matthieu Charette, Natasha England-Elbro, and Timur Mangliev. See the source files and history for original copyright notices and attribution.

The project integrates and modifies `libfprint` source licensed under **LGPL-2.1-or-later**. See [LICENSE](LICENSE) and retain applicable notices when redistributing modified source or binaries.

Maintainer and integration work: [Sahidul Haque (@sahid-code404)](https://github.com/sahid-code404).
