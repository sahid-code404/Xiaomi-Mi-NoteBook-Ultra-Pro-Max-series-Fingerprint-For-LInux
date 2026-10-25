# Contributing

Thanks for helping improve the Xiaomi FPC1022 Linux integration. Because this project changes the fingerprint stack and may modify system libraries, contributions should prioritize recoverability, limited privileges, and clear reporting over clever shortcuts.

## Before opening a pull request

1. Explain the hardware, distribution, firmware, and reproducible failure or improvement.
2. Keep the change focused. Avoid unrelated package-manager, PAM, Polkit, udev, systemd, or dynamic-loader changes.
3. Preserve upstream copyright and license notices in vendored code. Identify the source commit or patch when changing imported code.
4. Add tests for changed behavior and document any change to installation, rollback, compatibility, or security expectations.
5. Never commit fingerprint images, biometric templates, personal logs, private keys, tokens, or other private system data.

## Local checks

Install the development prerequisites documented in [docs/TESTING.md](docs/TESTING.md), then run:

```bash
make check
make build
make unit-test
```

`make lint` requires ShellCheck. A successful build does not prove hardware functionality; report hardware tests separately.

## Installer and rollback rules

- Keep system-wide changes opt-in when they change power, authentication, or access policy.
- Do not add users to broad access groups such as `input`.
- Do not silently hold/exclude packages or change the user's package-manager configuration.
- Do not delete unrelated files or automatically remove unrelated packages.
- Back up files before replacing them and restore only state that this installer can identify.
- Use staged, atomic deployment for runtime libraries. Do not overwrite development headers or pkg-config metadata as part of a runtime install.
- Errors must explain what failed and how to recover. Avoid swallowing failures from critical operations.
- Keep password-based recovery available when testing PAM changes.

## Pull request checklist

- [ ] The change and its limitations are documented.
- [ ] Shell syntax, ShellCheck, smoke tests, build, and unit tests pass as applicable.
- [ ] Uninstall behavior is considered for clean and upgraded installations.
- [ ] Existing user configuration is preserved when ownership/state is unknown.
- [ ] No security claims exceed the evidence.
- [ ] Hardware-specific results are labeled with the exact hardware and software versions tested.

## Releases

Do not label a release stable based on compilation alone. Verify enrollment, repeated verification, wrong-finger rejection, reboot, suspend/resume, password fallback, package-upgrade behavior, and uninstall on actual supported hardware. Publish measured FAR/FRR methodology and results before making biometric-accuracy claims.
