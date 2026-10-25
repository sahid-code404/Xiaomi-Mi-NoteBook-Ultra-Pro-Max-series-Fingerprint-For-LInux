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

uninstall_help="$(bash uninstall.sh --help)"
grep -q -- '--cleanup-orphans' <<< "$uninstall_help" || fail "uninstaller help is missing opt-in cleanup option"

grep -q 'backup_managed_file' install.sh || fail "installer no longer records managed files"
grep -q 'restore_managed_paths' uninstall.sh || fail "uninstaller no longer restores managed files"
grep -q 'SENSOR_DETECTED=true' install.sh || fail "sensor detection does not set the safety gate"

if grep -q 'usermod -a -G input' install.sh; then
    fail "installer must not add a user to the broad input group"
fi
if grep -Eq 'apt-mark hold|excludepkgs=libfprint|IgnorePkg = libfprint' install.sh; then
    fail "installer must not silently block package updates"
fi
if grep -Eq 'autoremove -y|pacman -Rns --noconfirm' uninstall.sh; then
    fail "uninstaller must not automatically remove orphan packages"
fi
if grep -q 'pam-auth-update --enable fingerprint' install.sh ||
   grep -q 'authselect enable-feature with-fingerprint' install.sh; then
    fail "installer must not enable fingerprint PAM automatically"
fi

printf 'PASS: shell syntax and safety smoke checks\n'
