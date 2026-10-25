#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

for script in install.sh uninstall.sh tests/smoke.sh tools/fpc1022-doctor; do bash -n "$script" || exit $?; done
sh -n configs/fpc1022-sleep-wake

install_help="$(bash install.sh --help)"
for option in --build --verbose --power-button --protect-enrollment; do
    grep -q -- "$option" <<< "$install_help" || fail "installer help is missing $option"
done
uninstall_help="$(bash uninstall.sh --help)"
grep -q -- '--cleanup-orphans' <<< "$uninstall_help" || fail "uninstaller help is missing opt-in cleanup"

grep -q 'backup_managed_file' install.sh || fail "installer does not track managed files"
grep -q 'preexisting-paths.txt' install.sh || fail "installer does not distinguish pre-existing paths"
grep -q 'created-paths.txt' install.sh || fail "installer does not track newly created paths"
grep -q 'restore_managed_paths' uninstall.sh || fail "uninstaller does not restore managed files"
grep -q 'restore_file_atomically' uninstall.sh || fail "source-build rollback is not atomic"
grep -q 'fpc1022-wake-service.state' install.sh || fail "installer does not track previous service state"
grep -q 'restore_wake_service_state' uninstall.sh || fail "uninstaller does not restore previous service state"
grep -q 'SENSOR_DETECTED=true' install.sh || fail "sensor detection does not set the safety gate"
grep -q 'DESTDIR="$build_tmp/stage" ninja -C build install' install.sh || fail "source build must stage before deployment"
grep -q 'mv -f -- "$deploy_tmp" "$target_lib"' install.sh || fail "source library deployment must be atomic"
grep -q 'install_fedora_rpm' install.sh || fail "native Fedora package path is missing"
grep -q 'download_fedora_release_rpm' install.sh || fail "verified Fedora release download is missing"
grep -q 'SHA256SUMS' install.sh || fail "prebuilt release checksum validation is missing"
grep -q -- '--disableexcludes=all' install.sh || fail "RPM installation should handle legacy user exclusions transactionally"

if grep -q 'usermod -a -G input' install.sh; then fail "installer must not add users to the broad input group"; fi
if grep -Eq 'apt-mark hold|excludepkgs=libfprint|IgnorePkg = libfprint' install.sh; then fail "installer must not silently block package updates"; fi
if grep -q ' > /etc/ld.so.conf.d/fprint.conf' install.sh; then fail "installer must not add a global loader path"; fi
if grep -q 'pam-auth-update --enable fingerprint' install.sh || grep -q 'authselect enable-feature with-fingerprint' install.sh; then
    fail "installer must not enable fingerprint PAM automatically"
fi
if grep -Eq 'dnf autoremove -y|apt-get autoremove -y' uninstall.sh; then fail "uninstaller must not automatically remove orphan packages"; fi
grep -q 'if [[ "$CLEANUP_ORPHANS" == "true" ]]; then' uninstall.sh || fail "orphan cleanup must stay opt-in"
if grep -Eq 'glib2-devel|libgcc|libstdc[+][+]' src/libfprint/packaging/arch/PKGBUILD; then
    fail "Arch PKGBUILD contains non-Arch package names"
fi
grep -Eq '#commit=[0-9a-f]{40}' src/libfprint/packaging/arch/PKGBUILD || fail "Arch source must be pinned to an exact commit"

printf 'PASS: shell syntax and installer safety smoke checks\n'
