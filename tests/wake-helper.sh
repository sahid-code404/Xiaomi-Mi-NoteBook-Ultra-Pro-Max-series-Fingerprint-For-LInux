#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if ! command -v gcc >/dev/null || ! command -v pkg-config >/dev/null || \
    ! pkg-config --exists libusb-1.0; then
    printf 'wake helper test: SKIP (gcc, pkg-config, or libusb-1.0 development files missing)\n'
    exit 0
fi

build_dir=$(mktemp -d /tmp/fpc1022-wake-test.XXXXXX)
trap 'rm -rf "$build_dir"' EXIT

gcc -O2 -Wall -Wextra -Werror -fstack-protector-strong -D_FORTIFY_SOURCE=3 \
    -fPIE -pie -Wl,-z,relro,-z,now \
    "$repo_root/tools/fpc1022-wake.c" \
    $(pkg-config --cflags --libs libusb-1.0) \
    -o "$build_dir/fpc1022-wake"

"$build_dir/fpc1022-wake" --help >/dev/null
readelf -h "$build_dir/fpc1022-wake" | grep -q 'DYN (Position-Independent Executable file)'
readelf -lW "$build_dir/fpc1022-wake" | grep -q GNU_RELRO
# Verify a temporary unit that points to the temporary test binary. The real
# system unit intentionally points to /usr/local/bin after installation.
sed "s#^ExecStart=/usr/local/bin/fpc1022-wake#ExecStart=$build_dir/fpc1022-wake#" \
    "$repo_root/configs/fpc1022-wake.service" > "$build_dir/fpc1022-wake.service"
systemd-analyze verify "$build_dir/fpc1022-wake.service"

printf 'wake helper test: PASS\n'
