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
TARGET_USER="${SUDO_USER:-$USER}"
if [[ "$TARGET_USER" == "root" ]]; then
    TARGET_USER="$(logname 2>/dev/null || id -nu 1000 2>/dev/null || echo "root")"
fi

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
  -b, --build       Compile driver from source instead of using pre-built binaries
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
install_fedora() {
    local fedora_pkg="$SCRIPT_DIR/packages/fedora"
    local deps_dir="/usr/local/lib64/fprint-deps"
    local target_lib="/usr/lib64/libfprint-2.so.2.0.0"
    local backup_dir="/usr/local/share/fpc1022-backup"
    local backup_lib="$backup_dir/libfprint-2.so.2.0.0.stock-backup"

    # Install fprintd daemon if missing
    if ! rpm -q fprintd >/dev/null 2>&1 || ! rpm -q fprintd-pam >/dev/null 2>&1; then
        run_cmd dnf install -y fprintd fprintd-pam
    fi

    if [[ "$BUILD_MODE" == "true" ]] || [[ ! -f "$fedora_pkg/libfprint-2.so.2.0.0" ]]; then
        install_from_source "fedora"
        return
    fi

    mkdir -p "$backup_dir"

    # Clean up legacy backup in /usr/lib64 to prevent ldconfig symlink hijacking
    if [[ -f "/usr/lib64/libfprint-2.so.2.0.0.stock-backup" ]]; then
        mv -f "/usr/lib64/libfprint-2.so.2.0.0.stock-backup" "$backup_lib"
    fi

    # Backup stock Fedora library once
    if [[ -f "$target_lib" && ! -f "$backup_lib" ]]; then
        cp -p "$target_lib" "$backup_lib"
    fi

    # Clean up any leftover stock backup file in /usr/lib64
    rm -f /usr/lib64/*stock-backup*

    # Deploy bundled runtime dependencies
    mkdir -p "$deps_dir"
    cp -p "$fedora_pkg/fprint-deps/"*.so.* "$deps_dir/"
    (
        cd "$deps_dir"
        ln -sf libblas.so.3.12.1 libblas.so.3; ln -sf libblas.so.3 libblas.so
        ln -sf libgfortran.so.5.0.0 libgfortran.so.5; ln -sf libgfortran.so.5 libgfortran.so
        ln -sf liblapack.so.3.12.1 liblapack.so.3; ln -sf liblapack.so.3 liblapack.so
        ln -sf libopencv_core.so.4.10.0 libopencv_core.so.410; ln -sf libopencv_core.so.410 libopencv_core.so
        ln -sf libopencv_features2d.so.4.10.0 libopencv_features2d.so.410; ln -sf libopencv_features2d.so.410 libopencv_features2d.so
        ln -sf libopencv_flann.so.4.10.0 libopencv_flann.so.410; ln -sf libopencv_flann.so.410 libopencv_flann.so
        ln -sf libopencv_imgproc.so.4.10.0 libopencv_imgproc.so.410; ln -sf libopencv_imgproc.so.410 libopencv_imgproc.so
        ln -sf libtbb.so.12.17 libtbb.so.12; ln -sf libtbb.so.12 libtbb.so
        [[ -f /usr/lib64/libcrypto.so.3 ]] && ln -sf /usr/lib64/libcrypto.so.3 libcrypto.so
        [[ -f /usr/lib64/libssl.so.3 ]] && ln -sf /usr/lib64/libssl.so.3 libssl.so
    )
    echo "$deps_dir" > /etc/ld.so.conf.d/fprint.conf

    # Deploy patched driver and enforce symlink
    cp -p "$fedora_pkg/libfprint-2.so.2.0.0" "$target_lib"
    ln -sf libfprint-2.so.2.0.0 /usr/lib64/libfprint-2.so.2

    # SELinux contexts
    if command -v chcon >/dev/null 2>&1; then
        run_cmd chcon -t lib_t /usr/lib64/libfprint-2.so*
        run_cmd chcon -R -t lib_t "$deps_dir"
    fi
    if command -v restorecon >/dev/null 2>&1; then
        run_cmd restorecon -v /usr/lib64/libfprint-2.so*
        run_cmd restorecon -Rv "$deps_dir"
    fi

    run_cmd ldconfig

    # Shield libfprint from DNF upgrades
    local dnf_conf="/etc/dnf/dnf.conf"
    if [[ -f "$dnf_conf" ]]; then
        if grep -E -q "^[ \t]*excludepkgs[ \t]*=" "$dnf_conf"; then
            if ! grep -q "libfprint\*" "$dnf_conf"; then
                sed -i -E 's/^[ \t]*excludepkgs[ \t]*=(.*)/excludepkgs=\1 libfprint*/' "$dnf_conf"
            fi
        else
            if grep -q "^\[main\]" "$dnf_conf"; then
                sed -i '/^\[main\]/a excludepkgs=libfprint*' "$dnf_conf"
            else
                echo -e "\n[main]\nexcludepkgs=libfprint*" >> "$dnf_conf"
            fi
        fi
    fi

    print_ok "Installed FPC1022 driver and runtime libraries"
    print_ok "Protected driver from DNF system upgrades"
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

    # Pin in apt
    run_cmd apt-mark hold libfprint-2-2 libfprint-fpc1022

    # Enable PAM auth
    if command -v pam-auth-update >/dev/null 2>&1; then
        run_cmd pam-auth-update --enable fingerprint
    fi

    print_ok "Installed FPC1022 driver"
    print_ok "Protected driver from APT package updates"
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

    # Pin in pacman.conf
    if [[ -f /etc/pacman.conf ]]; then
        if grep -E -q "^[ \t]*IgnorePkg" /etc/pacman.conf; then
            if ! grep -q "\blibfprint\b" /etc/pacman.conf; then
                sed -i -E 's/^[ \t]*IgnorePkg[ \t]*=[ \t]*(.*)/IgnorePkg = \1 libfprint/' /etc/pacman.conf
            fi
        else
            if grep -q "^\[options\]" /etc/pacman.conf; then
                sed -i '/^\[options\]/a IgnorePkg = libfprint' /etc/pacman.conf
            else
                echo -e "\n[options]\nIgnorePkg = libfprint" >> /etc/pacman.conf
            fi
        fi
    fi

    print_ok "Installed FPC1022 driver"
    print_ok "Protected driver from Pacman system updates"
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
            run_cmd dnf install -y meson ninja-build gcc gcc-c++ glib2-devel libgusb-devel \
                pixman-devel openssl-devel libgudev-devel polkit-devel systemd-devel \
                doctest-devel opencv-devel fprintd fprintd-pam
            ;;
        debian)
            run_cmd apt-get update -y
            run_cmd apt-get install -y meson ninja-build build-essential libglib2.0-dev libgusb-dev \
                libpixman-1-dev libssl-dev libgudev-1.0-dev libpolkit-gobject-1-dev doctest-dev \
                libopencv-dev fprintd
            ;;
        arch)
            run_cmd pacman -S --needed --noconfirm meson ninja gcc glib2 libgusb pixman openssl \
                libgudev polkit doctest opencv fprintd
            ;;
        suse)
            run_cmd zypper --non-interactive install meson ninja gcc gcc-c++ glib2-devel \
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
    print_ok "Built and installed driver from source"
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

    # 2. Add user to input group if group exists
    if getent group input >/dev/null 2>&1 && [[ -n "$TARGET_USER" && "$TARGET_USER" != "root" ]]; then
        run_cmd usermod -a -G input "$TARGET_USER"
        print_ok "Added user '${TARGET_USER}' to 'input' group"
    fi

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
    local wake_prebuilt="$SCRIPT_DIR/tools/fpc1022-wake"
    local wake_ok=false

    if command -v gcc >/dev/null 2>&1 && [[ -f "$wake_c" ]]; then
        local libusb_flags
        libusb_flags="$(pkg-config --cflags --libs libusb-1.0 2>/dev/null || echo "-I/usr/include/libusb-1.0 -lusb-1.0")"
        if gcc -O2 -Wall "$wake_c" $libusb_flags -o "$wake_bin" 2>/dev/null; then
            chmod 755 "$wake_bin"
            wake_ok=true
        fi
    fi

    if [[ "$wake_ok" != "true" && -f "$wake_prebuilt" ]]; then
        cp -p "$wake_prebuilt" "$wake_bin"
        chmod 755 "$wake_bin"
        wake_ok=true
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
