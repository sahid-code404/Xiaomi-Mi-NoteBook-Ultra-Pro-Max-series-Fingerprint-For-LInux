#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

bash -n install.sh uninstall.sh
sh -n configs/fpc1022-sleep-wake

install_help="$(bash install.sh --help)"
grep -q -- '--build' <<< "$install_help" || fail "installer help is missing --build"
grep -q -- '--verbose' <<< "$install_help" || fail "installer help is missing --verbose"
grep -q -- '--power-button' <<< "$install_help" || fail "installer help is missing --power-button"
grep -q -- '--protect-enrollment' <<< "$install_help" || fail "installer help is missing --protect-enrollment"

uninstall_help="$(bash uninstall.sh --help)"
grep -q -- '--cleanup-orphans' <<< "$uninstall_help" || fail "uninstaller help is missing opt-in cleanup option"

grep -q 'backup_managed_file' install.sh || fail "installer no longer records managed files"
grep -q 'preexisting-paths.txt' install.sh || fail "installer does not distinguish pre-existing paths"
grep -q 'created-paths.txt' install.sh || fail "installer does not track newly created paths"
grep -q 'preexisting-paths.txt' uninstall.sh || fail "uninstaller does not preserve files with missing backups"
grep -q 'restore_managed_paths' uninstall.sh || fail "uninstaller no longer restores managed files"
grep -q 'restore_file_atomically' uninstall.sh || fail "uninstaller no longer restores the Fedora library atomically"
grep -q 'Run the DNF orphan cleanup shown above?' uninstall.sh || fail "optional orphan cleanup is missing an explicit confirmation"
grep -q 'Run the APT orphan cleanup shown above?' uninstall.sh || fail "optional APT cleanup is missing an explicit confirmation"
grep -q 'SENSOR_DETECTED=true' install.sh || fail "sensor detection does not set the safety gate"

if grep -q 'usermod -a -G input' install.sh; then
    fail "installer must not add a user to the broad input group"
fi
if grep -Eq 'apt-mark hold|excludepkgs=libfprint|IgnorePkg = libfprint' install.sh; then
    fail "installer must not silently block package updates"
fi
if grep -q ' > /etc/ld.so.conf.d/fprint.conf' install.sh; then
    fail "installer must not add its private dependency directory to the global loader path"
fi
grep -q "patchelf --set-rpath" install.sh || fail "Fedora prebuilt path must use a private runtime search path"
if grep -Eq "glib2-devel|'libgcc'|'libstdc[+][+]'" src/libfprint/packaging/arch/PKGBUILD; then
    fail "Arch PKGBUILD contains non-Arch package names"
fi
grep -Eq '#commit=[0-9a-f]{40}' src/libfprint/packaging/arch/PKGBUILD || fail "Arch PKGBUILD source must be pinned to an exact commit"
if grep -Eq 'autoremove -y|pacman -Rns --noconfirm' uninstall.sh; then
    fail "uninstaller must not automatically remove orphan packages"
fi
if grep -q 'pam-auth-update --enable fingerprint' install.sh ||
   grep -q 'authselect enable-feature with-fingerprint' install.sh; then
    fail "installer must not enable fingerprint PAM automatically"
fi

printf 'PASS: shell syntax and safety smoke checks\n'
