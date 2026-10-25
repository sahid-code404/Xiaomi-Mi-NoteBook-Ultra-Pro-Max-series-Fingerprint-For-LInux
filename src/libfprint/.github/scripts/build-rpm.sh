#!/usr/bin/env bash
set -euo pipefail

source /etc/os-release
if [[ ${ID:-} != fedora ]]; then
  printf 'Container ID does not match fedora\n' >&2
  exit 2
fi

root=$(pwd -P)
spec="$root/packaging/fedora/libfprint-fpc1022.spec"
[[ -f $root/meson.build && -f $spec ]]
source_dir=$(basename "$root")

dnf -y install --setopt=install_weak_deps=False \
  rpm-build gcc gcc-c++ meson ninja-build pkgconf-pkg-config \
  glib2-devel libgusb-devel libusb1-devel pixman-devel openssl-devel libgudev-devel \
  systemd-devel doctest-devel opencv-devel

version=$(sed -n "s/^[[:space:]]*version:[[:space:]]*'\([^']*\)'.*/\1/p" \
  "$root/meson.build" | head -n 1)
[[ -n $version ]]

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
topdir="$work/rpmbuild"
mkdir -p "$topdir/SOURCES" "$topdir/SPECS"

tar --create --gzip --file "$topdir/SOURCES/libfprint-fpc1022-$version.tar.gz" \
  --directory="$(dirname "$root")" \
  --exclude="$source_dir/build" --exclude="$source_dir/build-*" --exclude="$source_dir/.git" \
  --transform "s,^$source_dir,libfprint-fpc1022-$version," "$source_dir"
cp "$spec" "$topdir/SPECS/"
rpmbuild -ba --define "_topdir $topdir" "$topdir/SPECS/$(basename "$spec")"

out="$root/artifacts/fedora"
mkdir -p "$out"
find "$topdir/RPMS" -type f -name 'libfprint-fpc1022-*.rpm' -exec cp {} "$out/" \;
test -n "$(find "$out" -maxdepth 1 -name 'libfprint-fpc1022-*.rpm' -print -quit)"
