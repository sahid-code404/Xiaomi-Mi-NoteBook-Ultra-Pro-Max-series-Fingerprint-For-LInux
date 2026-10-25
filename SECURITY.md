# Security policy

## Reporting a vulnerability

Please do not publish exploitable details in a public issue before the maintainer has had an opportunity to investigate. Contact the repository maintainer through the private contact options available on the GitHub profile. Include the affected commit, distribution, package/source-build mode, hardware USB ID, and a minimal reproduction. Do not attach real fingerprint images or biometric templates.

This is a community-maintained project and response times are not guaranteed. Do not include passwords, private keys, or other unrelated sensitive information in a report.

## Scope and limitations

This project installs privileged system files and integrates with the Linux fingerprint stack. Treat installer and uninstaller changes as security-sensitive.

The sensor protocol uses TLS-PSK and the host performs matching with SIGFM/SIFT. The source contains fixed key-derivation/sealing constants required by the current implementation. Because the implementation is public, these constants are not equivalent to a device-specific secret and should not be treated as strong proof of sensor identity.

The project does not currently publish independently verified false-acceptance/false-rejection results or a presentation-attack/liveness evaluation. Do not claim resistance to printed, replayed, molded, or otherwise spoofed fingerprints without dedicated testing.

## Maintainer release checklist

- Review changes to root-level scripts, PAM, Polkit, udev, systemd, and dynamic-loader configuration.
- Confirm every modified system file has an explicit backup/restore strategy.
- Do not add users to broad device-access groups or disable package security updates.
- Build from pinned source and verify published checksums/signatures for prebuilt artifacts.
- Run shell checks and the libfprint build/test workflow.
- Test enrollment, repeated verification, suspend/resume, password fallback, update behavior, and uninstall on actual hardware before declaring a release stable.
