#!/usr/bin/env bash
# ==============================================================================
# Xiaomi Mi NoteBook Ultra / Pro / Max - Fingerprint & Power Button Installer
# Supported Hardware: FPC1022 (USB ID 10a5:9200) Match-on-Host Fingerprint Reader
# Author: Sahidul Haque (sahid-code404) & Contributors
# License: LGPL-2.1-or-later
# ==============================================================================

set -euo pipefail

# Visual formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BUILD_MODE=false
ASSUME_YES=false
VERBOSE=false

print_banner() {
    cat << "EOF"
====================================================================
 Xiaomi Mi NoteBook Fingerprint & Power Button Installer
====================================================================
EOF
}

show_help() {
    cat << EOF
Usage: sudo ./install.sh [OPTIONS]

Options:
  -b, --build       Compile the driver from the included source tree
  -y, --yes         Automatic yes to prompts (non-interactive mode)
  -v, --verbose     Show detailed command outputs
  -h, --help        Show this help message and exit

Supported Distributions:
  - Fedora / RHEL / CentOS
  - Ubuntu / Debian / Linux Mint / Pop!_OS
  - Arch Linux / Manjaro / EndeavourOS
  - openSUSE / Generic Linux
EOF
}

# Parse command line flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        -b|--build)
            BUILD_MODE=true
            shift
            ;;
        -y|--yes)
            ASSUME_YES=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}[ERROR] Unknown option: $1${NC}" >&2
            show_help
            exit 1
            ;;
    esac
done

print_step() { echo -e "\n${BOLD}${BLUE}[$1]${NC} ${BOLD}$2${NC}"; }
print_ok()   { echo -e "    ${GREEN}✔${NC} $*"; }
print_warn() { echo -e "    ${YELLOW}!${NC} $*"; }
print_err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }

run_cmd() {
    if [[ "$VERBOSE" == "true" ]]; then
        "$@"
    else
        "$@" >/dev/null 2>&1
    fi
}

check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        print_err "This installer must be run as root. Please run: sudo $0"
        exit 1
    fi
}

detect_distro() {
    if [[ ! -f /etc/os-release ]]; then
        print_err "Cannot detect Linux distribution (/etc/os-release missing)."
        exit 1
    fi
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    DISTRO_LIKE="${ID_LIKE:-}"
    DISTRO_NAME="${PRETTY_NAME:-$DISTRO_ID}"
}

check_sensor() {
    if lsusb -d 10a5:9200 >/dev/null 2>&1; then
        print_ok "Detected FPC1022 fingerprint sensor (10a5:9200)"
    else
        print_warn "Sensor '10a5:9200' not found in lsusb. Ensure it is enabled in BIOS/UEFI."
        if [[ "$ASSUME_YES" != "true" ]]; then
            read -r -p "    Continue installation anyway? [y/N]: " resp
            if [[ ! "$resp" =~ ^[yY]([eE][sS])?$ ]]; then
                echo "Installation cancelled."
                exit 0
            fi
        fi
    fi
    print_ok "Detected system: ${DISTRO_NAME}"
}

# ------------------------------------------------------------------------------
# Driver Installation: Fedora / RHEL
# ------------------------------------------------------------------------------
source_version() {
    sed -n "s/^[[:space:]]*version:[[:space:]]*'\([^']*\)'.*/\1/p" \
        "$SCRIPT_DIR/src/libfprint/meson.build" | head -n 1
}

download_fedora_release_rpm() {
    local fedora_release="${VERSION_ID%%.*}"
    local release_json rpm_url sums_url rpm_file checksum_line
    local api_url="https://api.github.com/repos/sahid-code404/xiaomi-fprint-driver/releases/latest"

    require_cmd curl sha256sum
    release_json="$(curl --fail --silent --show-error --location "$api_url")" || return 1
    rpm_url="$(printf '%s' "$release_json" | sed -n \
        "s#.*\\\"browser_download_url\\\":\\\"\\([^\\\"]*libfprint-fpc1022-[^\\\"]*\\.fc${fedora_release}\\.x86_64\\.rpm\\)\\\".*#\\1#p" | head -n 1)"
    sums_url="$(printf '%s' "$release_json" | sed -n \
        's#.*"browser_download_url":"\([^"]*SHA256SUMS\)".*#\1#p' | head -n 1)"
    [[ -n "$rpm_url" && -n "$sums_url" ]] || return 1

    rpm_file="${rpm_url##*/}"
    curl --fail --silent --show-error --location --output "/tmp/$rpm_file" "$rpm_url" || return 1
    checksum_line="$(curl --fail --silent --show-error --location "$sums_url" | \
        awk -v name="$rpm_file" '$2 == name { print; exit }')" || return 1
    [[ -n "$checksum_line" ]] || return 1
    printf '%s\n' "$checksum_line" | (cd /tmp && sha256sum --check --status -) || return 1
    printf '%s\n' "/tmp/$rpm_file"
}

install_fedora_rpm() {
    local src_dir="$SCRIPT_DIR/src/libfprint"
    local spec_file="$src_dir/packaging/fedora/libfprint-fpc1022.spec"
    local version
    local build_dir
    local topdir
    local source_archive
    local rpm_package

    if [[ "$BUILD_MODE" != "true" ]]; then
        if ! rpm_package="$(download_fedora_release_rpm)"; then
            print_err "No verified Fedora ${VERSION_ID%%.*} RPM is available in the latest GitHub release."
            print_err "Use --build only when you explicitly accept local build dependencies."
            exit 1
        fi
        run_cmd dnf install -y --allowerasing --disableexcludes=all "$rpm_package" fprintd fprintd-pam
        rm -f "$rpm_package"
        print_ok "Installed verified native FPC1022 RPM"
        return
    fi

    [[ -d "$src_dir" && -f "$spec_file" ]] || {
        print_err "Fedora packaging sources are incomplete."
        exit 1
    }
    version="$(source_version)"
    [[ -n "$version" ]] || { print_err "Could not determine the libfprint version."; exit 1; }

    # Explicit development fallback. Do not deploy a bundled shared object into
    # /usr: RPM must own every installed library.
    run_cmd dnf install -y rpm-build meson ninja-build gcc gcc-c++ pkgconf-pkg-config \
        glib2-devel libgusb-devel pixman-devel openssl-devel libgudev-devel \
        systemd-devel doctest-devel opencv-devel libusb1-devel fprintd fprintd-pam

    build_dir="$(mktemp -d /tmp/fpc1022-rpm.XXXXXX)"
    topdir="$build_dir/rpmbuild"
    source_archive="$topdir/SOURCES/libfprint-fpc1022-$version.tar.gz"
    mkdir -p "$topdir/SOURCES" "$topdir/SPECS"

    # Package a clean copy of the checked-in source. Build directories and Git
    # metadata cannot influence the RPM payload or its build result.
    tar --create --gzip --file "$source_archive" \
        --directory="$(dirname "$src_dir")" \
        --exclude='libfprint/build' --exclude='libfprint/build-*' --exclude='libfprint/.git' \
        --transform "s,^libfprint,libfprint-fpc1022-$version," libfprint
    cp -p "$spec_file" "$topdir/SPECS/"

    if ! rpmbuild -ba --define "_topdir $topdir" \
        "$topdir/SPECS/$(basename "$spec_file")"; then
        rm -rf "$build_dir"
        print_err "Native RPM build failed; no driver was installed."
        exit 1
    fi

    rpm_package="$(find "$topdir/RPMS" -type f -name 'libfprint-fpc1022-*.rpm' -print -quit)"
    if [[ -z "$rpm_package" ]]; then
        rm -rf "$build_dir"
        print_err "RPM build completed without producing a package."
        exit 1
    fi

    # --allowerasing permits the custom package's declared libfprint conflict
    # to be resolved transactionally; DNF remains the owner of the replacement.
    # Older releases wrote a libfprint package-exclusion policy into dnf.conf.
    # Bypass that legacy policy for this one audited local transaction without
    # editing a user-managed DNF configuration file.
    run_cmd dnf install -y --allowerasing --disableexcludes=all "$rpm_package" fprintd fprintd-pam
    rm -rf "$build_dir"
    print_ok "Built and installed native FPC1022 RPM"
}

install_fedora() {
    install_fedora_rpm
}

# ------------------------------------------------------------------------------
# Driver Installation: Debian / Ubuntu
# ------------------------------------------------------------------------------
install_debian() {
    local deb_pkg="$SCRIPT_DIR/packages/deb/libfprint-fpc1022_1.94.100_amd64.deb"
    local installed=false

    if [[ "$BUILD_MODE" != "true" && -f "$deb_pkg" ]]; then
        run_cmd apt-get update -y
        if run_cmd apt-get install -y "$deb_pkg" fprintd; then
            installed=true
        fi
    fi

    if [[ "$installed" != "true" ]]; then
        install_from_source "debian"
    fi

    # Enable PAM auth
    if command -v pam-auth-update >/dev/null 2>&1; then
        run_cmd pam-auth-update --enable fingerprint
    fi

    print_ok "Installed FPC1022 driver"
    print_ok "Installed through APT; use fpc1022-doctor after system updates"
}

# ------------------------------------------------------------------------------
# Driver Installation: Arch Linux
# ------------------------------------------------------------------------------
install_arch() {
    local arch_pkg="$SCRIPT_DIR/packages/arch/libfprint-fpc1022-1.94.100-1-x86_64.pkg.tar.zst"
    local installed=false

    if [[ "$BUILD_MODE" != "true" && -f "$arch_pkg" ]]; then
        run_cmd pacman -S --needed --noconfirm fprintd
        if run_cmd pacman -U --noconfirm "$arch_pkg"; then
            installed=true
        fi
    fi

    if [[ "$installed" != "true" ]]; then
        install_from_source "arch"
    fi

    print_ok "Installed FPC1022 driver"
    print_ok "Installed through Pacman; use fpc1022-doctor after system updates"
}

# ------------------------------------------------------------------------------
# Universal Driver Source Build (Fedora, Debian, Arch, openSUSE, Generic)
# ------------------------------------------------------------------------------
install_from_source() {
    local family="$1"
    local src_dir="$SCRIPT_DIR/src/libfprint"
    local lib_dir="/usr/lib"
    [[ -d /usr/lib64 ]] && lib_dir="/usr/lib64"

    if [[ ! -d "$src_dir" ]]; then
        print_err "Source tree not found at $src_dir"
        exit 1
    fi

    print_ok "Installing build prerequisites for ${family}..."
    case "$family" in
        fedora)
            run_cmd dnf install -y meson ninja-build gcc gcc-c++ libusb1-devel glib2-devel libgusb-devel \
                pixman-devel openssl-devel libgudev-devel polkit-devel systemd-devel \
                doctest-devel opencv-devel fprintd fprintd-pam
            ;;
        debian)
            run_cmd apt-get update -y
            run_cmd apt-get install -y meson ninja-build build-essential libusb-1.0-0-dev libglib2.0-dev libgusb-dev \
                libpixman-1-dev libssl-dev libgudev-1.0-dev libpolkit-gobject-1-dev doctest-dev \
                libopencv-dev fprintd
            ;;
        arch)
            run_cmd pacman -S --needed --noconfirm meson ninja gcc libusb glib2 libgusb pixman openssl \
                libgudev polkit doctest opencv fprintd
            ;;
        suse)
            run_cmd zypper --non-interactive install meson ninja gcc gcc-c++ libusb-1_0-devel glib2-devel \
                libgusb-devel libpixman-1-0-devel libopenssl-devel libgudev-1_0-devel polkit-devel \
                systemd-devel doctest-devel opencv-devel fprintd fprintd-pam
            ;;
        generic)
            # Verify essentials are present
            for tool in meson ninja gcc; do
                if ! command -v "$tool" >/dev/null 2>&1; then
                    print_err "Required build tool '$tool' is missing. Please install build tools and OpenCV dev libraries."
                    exit 1
                fi
            done
            ;;
    esac

    # Isolate backup if stock lib exists
    local backup_dir="/usr/local/share/fpc1022-backup"
    local target_lib="${lib_dir}/libfprint-2.so.2.0.0"
    if [[ -f "$target_lib" && ! -f "$backup_dir/libfprint-2.so.2.0.0.stock-backup" ]]; then
        mkdir -p "$backup_dir"
        cp -p "$target_lib" "$backup_dir/libfprint-2.so.2.0.0.stock-backup"
    fi
    rm -f "${lib_dir}/"*stock-backup*

    local build_tmp
    build_tmp="$(mktemp -d /tmp/fpc1022_build.XXXXXX)"
    cp -r "$src_dir" "$build_tmp/src"

    (
        cd "$build_tmp/src"
        meson setup build --prefix=/usr --libdir="$lib_dir" -Ddrivers=all -Ddoc=false \
            -Dintrospection=false -Dinstalled-tests=false -Dudev_hwdb=enabled
        ninja -C build
        ninja -C build install
    )
    rm -rf "$build_tmp"

    if command -v chcon >/dev/null 2>&1; then
        run_cmd chcon -t lib_t "${lib_dir}/libfprint-2.so"*
    fi
    if command -v restorecon >/dev/null 2>&1; then
        run_cmd restorecon -v "${lib_dir}/libfprint-2.so"*
    fi

    run_cmd ldconfig
    print_warn "Installed an unmanaged source build; use a distribution package where available."
}

# ------------------------------------------------------------------------------
# Power Button Hardware Initializer & Policy Setup
# ------------------------------------------------------------------------------
configure_power_button() {
    # 1. logind policy: Instant response & honor desktop inhibitors
    local logind_dir="/etc/systemd/logind.conf.d"
    local power_conf="$SCRIPT_DIR/configs/10-power-button.conf"
    if [[ -f "$power_conf" ]]; then
        mkdir -p "$logind_dir"
        cp -p "$power_conf" "$logind_dir/10-power-button.conf"
        if command -v systemctl >/dev/null 2>&1; then
            systemctl reload systemd-logind 2>/dev/null || systemctl kill -s HUP systemd-logind 2>/dev/null || true
        fi
        print_ok "Configured instant power button response (logind)"
    fi

    # 2. Do not add users to the privileged input group. fprintd uses its own
    # D-Bus/Polkit authorization boundary and the udev rule grants uaccess.

    # 3. Clean up legacy dconf locks so desktop power action remains user-configurable
    local dconf_dir="/etc/dconf/db/local.d"
    if [[ -f "$dconf_dir/01-power-button" || -f "$dconf_dir/locks/01-power-button" ]]; then
        rm -f "$dconf_dir/01-power-button" "$dconf_dir/locks/01-power-button"
        if command -v dconf >/dev/null 2>&1; then
            run_cmd dconf update
        fi
        print_ok "Reset desktop power overrides (managed in GNOME/KDE Settings)"
    fi

    # 4. Hardware wake utility (fpc1022-wake)
    local wake_bin="/usr/local/bin/fpc1022-wake"
    local wake_c="$SCRIPT_DIR/tools/fpc1022-wake.c"
    local wake_ok=false

    if command -v gcc >/dev/null 2>&1 && command -v pkg-config >/dev/null 2>&1 && \
        pkg-config --exists libusb-1.0 && [[ -f "$wake_c" ]]; then
        if gcc -O2 -Wall -Wextra -Werror -fstack-protector-strong -D_FORTIFY_SOURCE=3 \
            -fPIE -pie -Wl,-z,relro,-z,now "$wake_c" \
            $(pkg-config --cflags --libs libusb-1.0) -o "$wake_bin"; then
            install -m 0755 "$SCRIPT_DIR/tools/fpc1022-doctor" /usr/local/bin/fpc1022-doctor
            wake_ok=true
        fi
    fi

    if [[ "$wake_ok" == "true" ]]; then
        # udev rule
        if [[ -f "$SCRIPT_DIR/configs/99-fpc1022-wake.rules" ]]; then
            cp -p "$SCRIPT_DIR/configs/99-fpc1022-wake.rules" /etc/udev/rules.d/99-fpc1022-wake.rules
            chmod 644 /etc/udev/rules.d/99-fpc1022-wake.rules
        fi

        # systemd boot service
        if [[ -f "$SCRIPT_DIR/configs/fpc1022-wake.service" ]]; then
            cp -p "$SCRIPT_DIR/configs/fpc1022-wake.service" /etc/systemd/system/fpc1022-wake.service
            chmod 644 /etc/systemd/system/fpc1022-wake.service
            if command -v systemctl >/dev/null 2>&1; then
                run_cmd systemctl daemon-reload
                run_cmd systemctl enable fpc1022-wake.service
            fi
        fi

        # resume sleep hook
        if [[ -d /usr/lib/systemd/system-sleep && -f "$SCRIPT_DIR/configs/fpc1022-sleep-wake" ]]; then
            cp -p "$SCRIPT_DIR/configs/fpc1022-sleep-wake" /usr/lib/systemd/system-sleep/fpc1022-wake
            chmod 755 /usr/lib/systemd/system-sleep/fpc1022-wake
        fi

        # Trigger immediate hardware wake
        "$wake_bin" 2>/dev/null || true
        print_ok "Installed hardware wake service (power button ready on boot & resume)"
    else
        print_err "Could not build fpc1022-wake from source (gcc, pkg-config, and libusb-1.0 development files are required)."
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# Security Policy (Polkit)
# ------------------------------------------------------------------------------
configure_security() {
    local polkit_rule="$SCRIPT_DIR/configs/50-fprintd-auth.rules"
    local polkit_dir="/etc/polkit-1/rules.d"
    if [[ -d "$polkit_dir" && -f "$polkit_rule" ]]; then
        cp -p "$polkit_rule" "$polkit_dir/50-fprintd-auth.rules"
        chmod 644 "$polkit_dir/50-fprintd-auth.rules"
        print_ok "Enabled PolicyKit rule (password required to delete/enroll prints)"
    fi
}

# ------------------------------------------------------------------------------
# Finalize & Service Reload
# ------------------------------------------------------------------------------
finalize_installation() {
    run_cmd udevadm control --reload
    run_cmd udevadm trigger
    run_cmd systemctl restart fprintd.service
    sleep 1

    # Fedora authselect fingerprint enable
    if command -v authselect >/dev/null 2>&1; then
        if authselect current >/dev/null 2>&1; then
            if ! authselect current | grep -q "with-fingerprint"; then
                run_cmd authselect enable-feature with-fingerprint
                run_cmd authselect apply-changes
                print_ok "Enabled fingerprint PAM feature in authselect"
            fi
        fi
    fi
    if [[ -x /usr/local/bin/fpc1022-doctor ]]; then
        /usr/local/bin/fpc1022-doctor --record-install
    fi
    print_ok "Reloaded system services and restarted fprintd"
}

# ------------------------------------------------------------------------------
# Main Flow
# ------------------------------------------------------------------------------
main() {
    print_banner
    check_root

    print_step "1/5" "Checking system & hardware..."
    detect_distro
    check_sensor

    print_step "2/5" "Installing fingerprint driver..."
    case "$DISTRO_ID" in
        fedora|rhel|centos)
            install_fedora
            ;;
        ubuntu|debian|linuxmint|pop)
            install_debian
            ;;
        arch|manjaro|endeavouros)
            install_arch
            ;;
        opensuse*|sles)
            install_from_source "suse"
            ;;
        *)
            if [[ "$DISTRO_LIKE" =~ (fedora|rhel) ]]; then
                install_fedora
            elif [[ "$DISTRO_LIKE" =~ (ubuntu|debian) ]]; then
                install_debian
            elif [[ "$DISTRO_LIKE" =~ (arch) ]]; then
                install_arch
            elif [[ "$DISTRO_LIKE" =~ (suse) ]]; then
                install_from_source "suse"
            else
                install_from_source "generic"
            fi
            ;;
    esac

    print_step "3/5" "Setting up power button handling..."
    configure_power_button

    print_step "4/5" "Applying security policies..."
    configure_security

    print_step "5/5" "Finalizing system services..."
    finalize_installation

    echo ""
    echo -e "${GREEN}====================================================================${NC}"
    echo -e "${GREEN}${BOLD}  ✔ Installation Complete!${NC}"
    echo -e "${GREEN}====================================================================${NC}"
    echo ""
    echo -e "${BOLD}Next Steps:${NC}"
    echo -e "  1. Enroll your fingerprint:"
    echo -e "     ${BLUE}fprintd-enroll${NC}"
    echo ""
    echo -e "  2. Verify your fingerprint:"
    echo -e "     ${BLUE}fprintd-verify${NC}"
    echo ""
    echo -e "  Or configure visually in ${BOLD}Settings → Users → Fingerprint Login${NC}."
    echo ""
}

main "$@"
