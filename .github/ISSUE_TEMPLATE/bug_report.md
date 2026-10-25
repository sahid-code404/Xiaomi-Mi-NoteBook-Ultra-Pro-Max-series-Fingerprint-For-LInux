---
name: Bug report
about: Report a reproducible driver, build, installer, or rollback issue
title: "[Bug]: "
labels: bug
assignees: ""
---

## Summary

Describe the problem and what you expected to happen.

## Hardware and software

- Laptop model:
- USB ID (`lsusb -d 10a5:9200`):
- Linux distribution and version:
- Kernel:
- Desktop environment:
- Installation method (prebuilt/source):
- Project commit or release:

## Reproduction steps

1.
2.
3.

## Relevant logs

Include only the relevant, redacted output from:

```bash
journalctl -u fprintd.service -b --no-pager
```

Do not attach fingerprint images, biometric templates, passwords, access tokens, or unrelated personal data.

## Recovery status

- [ ] Password login still works.
- [ ] I reviewed the installer/uninstaller before running it.
- [ ] I can reproduce the issue after a reboot.
