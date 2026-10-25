# Testing and release checklist

This repository contains a low-level USB driver plus scripts that modify a Linux installation. A successful compile is necessary but does not establish that the sensor works correctly or that biometric matching is secure.

## Automated checks

Run from the repository root:

```bash
bash -n install.sh uninstall.sh tests/smoke.sh
sh -n configs/fpc1022-sleep-wake
./tests/smoke.sh
```

If ShellCheck is installed:

```bash
shellcheck --severity=error install.sh uninstall.sh tests/smoke.sh
```

Build the vendored libfprint source with its FPC1022 driver:

```bash
sudo apt-get install build-essential meson ninja-build pkg-config \
  libglib2.0-dev libgusb-dev libssl-dev libgudev-1.0-dev \
  libopencv-dev libpixman-1-dev libudev-dev libsystemd-dev \
  libpolkit-gobject-1-dev doctest-dev libcairo2-dev \
  libusb-1.0-0-dev gobject-introspection python3-cairo python3-gi

cd src/libfprint
meson setup build --prefix=/usr --libdir=lib/x86_64-linux-gnu \
  -Ddrivers=all -Ddoc=false -Dintrospection=false \
  -Dinstalled-tests=false -Dudev_hwdb=enabled
meson compile -C build
meson test -C build --print-errorlogs
```

Use the library directory appropriate for the test distribution. The command above is for x86-64 Debian/Ubuntu.

## Hardware test plan

For each release candidate, record the exact laptop model, USB ID, firmware revision if available, distribution/version, kernel, desktop environment, libfprint build, and the installed/uninstalled state.

- [ ] `lsusb -d 10a5:9200` detects the sensor.
- [ ] `fprintd-enroll` succeeds for each supported finger.
- [ ] Repeated `fprintd-verify` scans succeed with normal variation in finger placement.
- [ ] A wrong enrolled user/finger is rejected in repeated trials.
- [ ] Enrollment/deletion authorization behaves as documented.
- [ ] Password fallback remains usable before and after PAM is enabled.
- [ ] The sensor works after reboot, suspend/resume, and repeated fprintd restarts.
- [ ] The power button follows the selected desktop action; verify lock screen, TTY, and resume behavior separately.
- [ ] An OS/libfprint update does not silently leave a misleading success state.
- [ ] Uninstall restores the previous library and all pre-existing configuration files.
- [ ] The package-manager plan is inspected; no unrelated packages are removed.
- [ ] ShellCheck, smoke tests, compilation, and unit tests pass.

## Biometric metrics

Do not describe a matching threshold as an accuracy guarantee. To support security-related claims, run a controlled evaluation and publish the protocol, sample counts, population details, FAR, FRR, confidence intervals, and limitations. Keep raw fingerprint captures and enrolled templates private; do not publish biometric data in CI artifacts or bug reports.

A small number of successful local scans is useful functional evidence but is not a substitute for false-acceptance, false-rejection, and presentation-attack evaluations.
