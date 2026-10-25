#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

require() {
    local pattern=$1 file=$2
    rg -q --fixed-strings -- "$pattern" "$file" || {
        printf 'missing required text %q in %s\n' "$pattern" "$file" >&2
        exit 1
    }
}

forbidden() {
    local pattern=$1 file=$2
    if rg -q --fixed-strings -- "$pattern" "$file"; then
        printf 'forbidden text %q remains in %s\n' "$pattern" "$file" >&2
        exit 1
    fi
}

bash -n "$repo_root/install.sh" "$repo_root/uninstall.sh" \
    "$repo_root/tools/fpc1022-doctor" "$repo_root/configs/fpc1022-sleep-wake"

require 'install_fedora_rpm' "$repo_root/install.sh"
require 'download_fedora_release_rpm' "$repo_root/install.sh"
require 'SHA256SUMS' "$repo_root/install.sh"
require '--disableexcludes=all' "$repo_root/install.sh"
require 'fpc1022-doctor --record-install' "$repo_root/install.sh"
require 'CapabilityBoundingSet=' "$repo_root/configs/fpc1022-wake.service"
require 'NoNewPrivileges=yes' "$repo_root/configs/fpc1022-wake.service"
require 'PrivateNetwork=yes' "$repo_root/configs/fpc1022-wake.service"
require 'native package installed' "$repo_root/tools/fpc1022-doctor"
require '[[ -n $path ]] || return 1' "$repo_root/tools/fpc1022-doctor"
require 'BuildRequires:  pkgconfig(opencv4)' "$repo_root/src/libfprint/packaging/fedora/libfprint-fpc1022.spec"
require 'BuildRequires:  pkgconfig(libusb-1.0)' "$repo_root/src/libfprint/packaging/fedora/libfprint-fpc1022.spec"
require 'build-rpm.sh' "$repo_root/src/libfprint/.github/workflows/release.yml"
require 'source_dir=$(basename "$root")' "$repo_root/src/libfprint/.github/scripts/build-rpm.sh"
require 'FPC1022_TLS_RX_MAX_SIZE' "$repo_root/src/libfprint/libfprint/drivers/fpc1022/fpc1022.c"
require 'TLS1_2_VERSION' "$repo_root/src/libfprint/libfprint/drivers/fpc1022/fpc1022.c"
require "cpp.find_library('opencv_features2d'" "$repo_root/src/libfprint/meson.build"
forbidden 'apt-mark hold' "$repo_root/install.sh"
forbidden 'IgnorePkg = libfprint' "$repo_root/install.sh"
forbidden 'excludepkgs=libfprint' "$repo_root/install.sh"
forbidden 'usermod -a -G input' "$repo_root/install.sh"
forbidden 'wake_prebuilt=' "$repo_root/install.sh"
forbidden 'packages/fedora' "$repo_root/install.sh"
forbidden 'autoremove -y' "$repo_root/uninstall.sh"

printf 'installer static checks: PASS\n'
