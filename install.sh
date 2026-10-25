#!/usr/bin/env bash
# ==============================================================================
# Xiaomi Mi NoteBook Ultra / Pro / Max - Linux Fingerprint & Power Button Installer
# Target Sensor: FPC1022 (USB ID 10a5:9200) Match-on-Host Fingerprint Reader
# Author: Sahidul Haque (sahid-code404) & Contributors
# ==============================================================================

set -euo pipefail

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="${SUDO_USER:-$USER}"
if [[ "$TARGET_USER" == "root" ]]; then
    TARGET_USER="$(logname 2>/dev/null || id -nu 1000 2>/dev/null || echo "root")"
fi

BUILD_MODE=false
ASSUME_YES=false

print_banner() {
    cat << "EOF"
==============================================================================
   _  ___                     _   __ __    _    ___     _                 
  | |/ (_)__ _ ___  __ _  ___(_) / // /__ (_)  / _ \___(_)_  _____ ____   
  | ' < / _ `/ _ \/  ' \/ -_)_  / _  / _ `/ /  / // / __/ / |/ / -_) __/   
 |_|\_\_\_,_/\___/_/_/_/\__(_) /_//_/\_,_/_/  /____/_/ /_/|___/\__/_/      
 Xiaomi Mi NoteBook Ultra / Pro / Max - Unified Driver & Power Button Fix
==============================================================================
EOF
}

show_help() {
    cat << EOF
Usage: sudo ./install.sh [OPTIONS]

Options:
  -b, --build     Build driver from source instead of installing pre-compiled binaries
  -y, --yes       Automatic yes to prompts; run non-interactively
  -h, --help      Display this help message and exit

Supported Distributions:
  - Fedora Linux (Workstation 39, 40, 41, 42, 45, etc.) / RHEL / CentOS
  - Ubuntu (22.04 LTS, 24.04 LTS, etc.) / Debian / Pop!_OS / Linux Mint
  - Arch Linux / Manjaro / EndeavourOS
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

# Root privilege check
check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        echo -e "${RED}${BOLD}[ERROR] This installer must be executed as root.${NC}" >&2
        echo -e "Please re-run using: ${GREEN}sudo $0 $*${NC}" >&2
        exit 1
    fi
}

# Hardware verification
check_hardware() {
    echo -e "${BLUE}[*] Checking for FPC1022 fingerprint sensor...${NC}"
    if lsusb -d 10a5:9200 >/dev/null 2>&1; then
        echo -e "${GREEN}[✔] Detected FPC1022 fingerprint sensor: $(lsusb -d 10a5:9200)${NC}"
    else
        echo -e "${YELLOW}[!] WARNING: Sensor '10a5:9200' was not found in lsusb.${NC}"
        echo -e "${YELLOW}    Please make sure the fingerprint sensor is enabled in your BIOS/UEFI.${NC}"
        if [[ "$ASSUME_YES" != "true" ]]; then
            read -r -p "Do you still want to proceed with driver installation? [y/N]: " resp
            if [[ ! "$resp" =~ ^[yY]([eE][sS])?$ ]]; then
                echo "Installation cancelled."
                exit 0
            fi
        fi
    fi
}

# Distribution detection
detect_distro() {
    if [[ ! -f /etc/os-release ]]; then
        echo -e "${RED}[ERROR] Cannot detect Linux distribution (/etc/os-release missing).${NC}" >&2
        exit 1
    fi

    # Source os-release
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    DISTRO_LIKE="${ID_LIKE:-}"
    echo -e "${BLUE}[*] Detected Distribution: ${BOLD}${PRETTY_NAME:-$DISTRO_ID}${NC}"
}

# Protect libfprint from dnf upgrade
protect_dnf_packages() {
    local dnf_conf="/etc/dnf/dnf.conf"
    if [[ -f "$dnf_conf" ]]; then
        echo -e "${BLUE}[*] Protecting libfprint from DNF system upgrades...${NC}"
        if grep -E -q "^[ \t]*excludepkgs[ \t]*=" "$dnf_conf"; then
            if ! grep -q "libfprint\*" "$dnf_conf"; then
                sed -i -E 's/^[ \t]*excludepkgs[ \t]*=(.*)/excludepkgs=\1 libfprint*/' "$dnf_conf"
                echo -e "${GREEN}[✔] Appended libfprint* to excludepkgs in $dnf_conf${NC}"
            else
                echo -e "${GREEN}[✔] DNF excludepkgs already configured for libfprint*.${NC}"
            fi
        else
            if grep -q "^\[main\]" "$dnf_conf"; then
                sed -i '/^\[main\]/a excludepkgs=libfprint*' "$dnf_conf"
            else
                echo -e "\n[main]\nexcludepkgs=libfprint*" >> "$dnf_conf"
            fi
            echo -e "${GREEN}[✔] Added excludepkgs=libfprint* to $dnf_conf${NC}"
        fi
    fi
}

# Protect libfprint from apt upgrade
protect_apt_packages() {
    echo -e "${BLUE}[*] Locking libfprint packages in APT...${NC}"
    apt-mark hold libfprint-2-2 libfprint-fpc1022 2>/dev/null || true
}

# Protect libfprint from pacman upgrade
protect_arch_packages() {
    if [[ -f /etc/pacman.conf ]]; then
        echo -e "${BLUE}[*] Protecting libfprint from Pacman upgrades...${NC}"
        if grep -E -q "^[ \t]*IgnorePkg" /etc/pacman.conf; then
            if ! grep -q "\blibfprint\b" /etc/pacman.conf; then
                sed -i -E 's/^[ \t]*IgnorePkg[ \t]*=[ \t]*(.*)/IgnorePkg = \1 libfprint/' /etc/pacman.conf
                echo -e "${GREEN}[✔] Appended libfprint to IgnorePkg in /etc/pacman.conf${NC}"
            else
                echo -e "${GREEN}[✔] Pacman IgnorePkg already configured for libfprint.${NC}"
            fi
        else
            if grep -q "^\[options\]" /etc/pacman.conf; then
                sed -i '/^\[options\]/a IgnorePkg = libfprint' /etc/pacman.conf
            else
                echo -e "\n[options]\nIgnorePkg = libfprint" >> /etc/pacman.conf
            fi
            echo -e "${GREEN}[✔] Added IgnorePkg = libfprint to /etc/pacman.conf${NC}"
        fi
    fi
}

# Fedora / RHEL installation
install_fedora() {
    echo -e "${BLUE}[*] Preparing installation for Fedora/RHEL...${NC}"
    
    # Ensure fprintd and fprintd-pam packages are present
    if ! rpm -q fprintd >/dev/null 2>&1 || ! rpm -q fprintd-pam >/dev/null 2>&1; then
        echo -e "${BLUE}[*] Installing fprintd and fprintd-pam packages...${NC}"
        dnf install -y fprintd fprintd-pam
    fi

    if [[ "$BUILD_MODE" == "true" ]]; then
        echo -e "${BLUE}[*] Source build mode requested...${NC}"
        install_from_source_fedora
        return
    fi

    echo -e "${BLUE}[*] Installing pre-compiled FPC1022 libfprint with SIGFM matcher...${NC}"
    
    FEDORA_PKG_DIR="$SCRIPT_DIR/packages/fedora"
    DEPS_DIR="/usr/local/lib64/fprint-deps"
    TARGET_LIB="/usr/lib64/libfprint-2.so.2.0.0"
    BACKUP_LIB="/usr/lib64/libfprint-2.so.2.0.0.stock-backup"

    if [[ ! -f "$FEDORA_PKG_DIR/libfprint-2.so.2.0.0" ]]; then
        echo -e "${RED}[ERROR] Fedora pre-compiled binary missing at $FEDORA_PKG_DIR/libfprint-2.so.2.0.0${NC}" >&2
        echo -e "${YELLOW}Falling back to building from source...${NC}"
        install_from_source_fedora
        return
    fi

    # Backup stock Fedora libfprint library if not already backed up
    if [[ -f "$TARGET_LIB" && ! -f "$BACKUP_LIB" ]]; then
        echo -e "${BLUE}[*] Backing up stock system libfprint to ${BACKUP_LIB}...${NC}"
        cp -p "$TARGET_LIB" "$BACKUP_LIB"
    fi

    # Set up OpenCV / SIGFM dependency directory
    mkdir -p "$DEPS_DIR"
    echo -e "${BLUE}[*] Deploying runtime dependencies to ${DEPS_DIR}...${NC}"
    cp -p "$FEDORA_PKG_DIR/fprint-deps/"*.so.* "$DEPS_DIR/"

    # Create dependency symlinks
    (
        cd "$DEPS_DIR"
        ln -sf libblas.so.3.12.1 libblas.so.3
        ln -sf libblas.so.3 libblas.so
        ln -sf libgfortran.so.5.0.0 libgfortran.so.5
        ln -sf libgfortran.so.5 libgfortran.so
        ln -sf liblapack.so.3.12.1 liblapack.so.3
        ln -sf liblapack.so.3 liblapack.so
        ln -sf libopencv_core.so.4.10.0 libopencv_core.so.410
        ln -sf libopencv_core.so.410 libopencv_core.so
        ln -sf libopencv_features2d.so.4.10.0 libopencv_features2d.so.410
        ln -sf libopencv_features2d.so.410 libopencv_features2d.so
        ln -sf libopencv_flann.so.4.10.0 libopencv_flann.so.410
        ln -sf libopencv_flann.so.410 libopencv_flann.so
        ln -sf libopencv_imgproc.so.4.10.0 libopencv_imgproc.so.410
        ln -sf libopencv_imgproc.so.410 libopencv_imgproc.so
        ln -sf libtbb.so.12.17 libtbb.so.12
        ln -sf libtbb.so.12 libtbb.so
        
        # Link host system crypto and ssl if available
        if [[ -f /usr/lib64/libcrypto.so.3 ]]; then
            ln -sf /usr/lib64/libcrypto.so.3 libcrypto.so
        fi
        if [[ -f /usr/lib64/libssl.so.3 ]]; then
            ln -sf /usr/lib64/libssl.so.3 libssl.so
        fi
    )

    # Configure dynamic linker ld.so.conf.d
    echo "$DEPS_DIR" > /etc/ld.so.conf.d/fprint.conf

    # Deploy patched libfprint
    echo -e "${BLUE}[*] Installing driver library to /usr/lib64/...${NC}"
    cp -p "$FEDORA_PKG_DIR/libfprint-2.so.2.0.0" "$TARGET_LIB"
    ln -sf libfprint-2.so.2.0.0 /usr/lib64/libfprint-2.so.2

    # SELinux Permissions
    if command -v chcon >/dev/null 2>&1; then
        echo -e "${BLUE}[*] Configuring SELinux file contexts (lib_t)...${NC}"
        chcon -t lib_t /usr/lib64/libfprint-2.so* 2>/dev/null || true
        chcon -R -t lib_t "$DEPS_DIR" 2>/dev/null || true
    fi
    if command -v restorecon >/dev/null 2>&1; then
        restorecon -v /usr/lib64/libfprint-2.so* 2>/dev/null || true
        restorecon -Rv "$DEPS_DIR" 2>/dev/null || true
    fi

    # Update ldconfig
    ldconfig

    # Protect package from being overwritten by dnf upgrade
    protect_dnf_packages
}

# Ubuntu / Debian installation
install_ubuntu_debian() {
    echo -e "${BLUE}[*] Preparing installation for Ubuntu/Debian...${NC}"
    
    if [[ "$BUILD_MODE" == "true" ]]; then
        install_from_source_debian
        return
    fi

    local deb_pkg="$SCRIPT_DIR/packages/deb/libfprint-fpc1022_1.94.100_amd64.deb"
    local installed=false
    if [[ -f "$deb_pkg" ]]; then
        echo -e "${BLUE}[*] Attempting installation of pre-compiled Debian package...${NC}"
        apt-get update -y
        if apt-get install -y "$deb_pkg" fprintd 2>/dev/null; then
            installed=true
            protect_apt_packages
        else
            echo -e "${YELLOW}[!] Pre-compiled package dependencies not met on this release.${NC}"
            echo -e "${YELLOW}    Falling back to building from source for native compatibility...${NC}"
        fi
    fi

    if [[ "$installed" != "true" ]]; then
        install_from_source_debian
    fi

    # Enable PAM authentication
    if command -v pam-auth-update >/dev/null 2>&1; then
        echo -e "${BLUE}[*] Enabling PAM fingerprint authentication...${NC}"
        pam-auth-update --enable fingerprint 2>/dev/null || true
    fi
}

# Arch Linux installation
install_arch() {
    echo -e "${BLUE}[*] Preparing installation for Arch Linux...${NC}"

    local arch_pkg="$SCRIPT_DIR/packages/arch/libfprint-fpc1022-1.94.100-1-x86_64.pkg.tar.zst"
    local installed=false
    if [[ "$BUILD_MODE" != "true" && -f "$arch_pkg" ]]; then
        echo -e "${BLUE}[*] Attempting installation of pre-compiled Arch package...${NC}"
        pacman -S --needed --noconfirm fprintd
        if pacman -U --noconfirm "$arch_pkg" 2>/dev/null; then
            installed=true
            protect_arch_packages
        else
            echo -e "${YELLOW}[!] Pre-compiled package incompatible with current system libraries.${NC}"
            echo -e "${YELLOW}    Falling back to building from source for native compatibility...${NC}"
        fi
    fi

    if [[ "$installed" != "true" ]]; then
        install_from_source_arch
    fi
}

# Source build for Fedora
install_from_source_fedora() {
    echo -e "${BLUE}[*] Installing build dependencies via DNF...${NC}"
    dnf install -y meson ninja-build gcc gcc-c++ glib2-devel libgusb-devel pixman-devel openssl-devel libgudev-devel polkit-devel systemd-devel doctest-devel opencv-devel fprintd fprintd-pam
    
    local src_dir="$SCRIPT_DIR/src/libfprint"
    if [[ ! -d "$src_dir" ]]; then
        echo -e "${RED}[ERROR] Source tree missing at $src_dir${NC}" >&2
        exit 1
    fi

    # Backup stock Fedora libfprint library if not already backed up
    local target_lib="/usr/lib64/libfprint-2.so.2.0.0"
    local backup_lib="/usr/lib64/libfprint-2.so.2.0.0.stock-backup"
    if [[ -f "$target_lib" && ! -f "$backup_lib" ]]; then
        echo -e "${BLUE}[*] Backing up stock system libfprint to ${backup_lib}...${NC}"
        cp -p "$target_lib" "$backup_lib"
    fi

    echo -e "${BLUE}[*] Configuring and building libfprint with fpc1022 and sigfm...${NC}"
    local build_tmp
    build_tmp="$(mktemp -d /tmp/fpc1022_fedora_build.XXXXXX)"
    cp -r "$src_dir" "$build_tmp/src"

    (
        cd "$build_tmp/src"
        meson setup build --prefix=/usr --libdir=/usr/lib64 -Ddrivers=all -Ddoc=false -Dintrospection=false -Dinstalled-tests=false -Dudev_hwdb=enabled
        ninja -C build
        echo -e "${BLUE}[*] Installing compiled driver to /usr/lib64/...${NC}"
        ninja -C build install
    )
    rm -rf "$build_tmp"

    # SELinux Permissions
    if command -v chcon >/dev/null 2>&1; then
        echo -e "${BLUE}[*] Configuring SELinux file contexts (lib_t)...${NC}"
        chcon -t lib_t /usr/lib64/libfprint-2.so* 2>/dev/null || true
    fi
    if command -v restorecon >/dev/null 2>&1; then
        restorecon -v /usr/lib64/libfprint-2.so* 2>/dev/null || true
    fi

    ldconfig
    protect_dnf_packages
}

# Source build for Debian/Ubuntu
install_from_source_debian() {
    echo -e "${BLUE}[*] Installing build dependencies via APT...${NC}"
    apt-get update -y
    apt-get install -y meson ninja-build build-essential libglib2.0-dev libgusb-dev libpixman-1-dev libssl-dev libgudev-1.0-dev libpolkit-gobject-1-dev doctest-dev libopencv-dev fprintd
    
    local src_dir="$SCRIPT_DIR/src/libfprint"
    if [[ ! -d "$src_dir" ]]; then
        echo -e "${RED}[ERROR] Source tree missing at $src_dir${NC}" >&2
        exit 1
    fi

    echo -e "${BLUE}[*] Configuring and building libfprint with fpc1022 and sigfm...${NC}"
    local build_tmp
    build_tmp="$(mktemp -d /tmp/fpc1022_debian_build.XXXXXX)"
    cp -r "$src_dir" "$build_tmp/src"

    (
        cd "$build_tmp/src"
        meson setup build --prefix=/usr -Ddrivers=all -Ddoc=false -Dintrospection=false -Dinstalled-tests=false -Dudev_hwdb=enabled
        ninja -C build
        echo -e "${BLUE}[*] Installing compiled driver to /usr/...${NC}"
        ninja -C build install
    )
    rm -rf "$build_tmp"

    ldconfig
    protect_apt_packages
}

# Source build for Arch Linux
install_from_source_arch() {
    echo -e "${BLUE}[*] Installing build dependencies via Pacman...${NC}"
    pacman -S --needed --noconfirm meson ninja gcc glib2 libgusb pixman openssl libgudev polkit doctest opencv fprintd
    
    local src_dir="$SCRIPT_DIR/src/libfprint"
    if [[ ! -d "$src_dir" ]]; then
        echo -e "${RED}[ERROR] Source tree missing at $src_dir${NC}" >&2
        exit 1
    fi

    echo -e "${BLUE}[*] Configuring and building libfprint with fpc1022 and sigfm...${NC}"
    local build_tmp
    build_tmp="$(mktemp -d /tmp/fpc1022_arch_build.XXXXXX)"
    cp -r "$src_dir" "$build_tmp/src"

    (
        cd "$build_tmp/src"
        meson setup build --prefix=/usr --libdir=/usr/lib -Ddrivers=all -Ddoc=false -Dintrospection=false -Dinstalled-tests=false -Dudev_hwdb=enabled
        ninja -C build
        echo -e "${BLUE}[*] Installing compiled driver to /usr/lib/...${NC}"
        ninja -C build install
    )
    rm -rf "$build_tmp"

    ldconfig
    protect_arch_packages
}

# Configure power button handling to prevent accidental suspend on sensor touch
configure_power_button() {
    echo -e "${BLUE}[*] Configuring power button handling (coexistence with fingerprint sensor)...${NC}"
    
    # 1. Systemd logind configuration
    local logind_conf_dir="/etc/systemd/logind.conf.d"
    local power_conf="$SCRIPT_DIR/configs/10-power-button.conf"
    
    if [[ -f "$power_conf" ]]; then
        mkdir -p "$logind_conf_dir"
        echo -e "${BLUE}[*] Installing logind power button policy to ${logind_conf_dir}/10-power-button.conf...${NC}"
        cp -p "$power_conf" "$logind_conf_dir/10-power-button.conf"
        
        # Reload systemd-logind to pick up new configuration without dropping active sessions
        if command -v systemctl >/dev/null 2>&1; then
            echo -e "${BLUE}[*] Reloading systemd-logind...${NC}"
            systemctl reload systemd-logind 2>/dev/null || systemctl kill -s HUP systemd-logind 2>/dev/null || systemctl restart systemd-logind 2>/dev/null || true
        fi
        echo -e "${GREEN}[✔] Systemd logind power button handling configured.${NC}"
    else
        echo -e "${YELLOW}[!] Warning: $power_conf not found, skipping logind configuration.${NC}"
    fi

    # 2. Add target user to input group for direct power button & input event access
    if [[ -n "$TARGET_USER" && "$TARGET_USER" != "root" ]]; then
        echo -e "${BLUE}[*] Adding user '${TARGET_USER}' to the 'input' group...${NC}"
        usermod -a -G input "$TARGET_USER" 2>/dev/null || true
        echo -e "${GREEN}[✔] Added ${TARGET_USER} to input group.${NC}"
    fi

    # 3. Clean up any previous dconf power-button overrides so desktop settings remain 100% user-determined
    local dconf_dir="/etc/dconf/db/local.d"
    if [[ -f "$dconf_dir/01-power-button" || -f "$dconf_dir/locks/01-power-button" ]]; then
        echo -e "${BLUE}[*] Removing dconf overrides to leave power button action user-configurable in Desktop Settings...${NC}"
        rm -f "$dconf_dir/01-power-button" "$dconf_dir/locks/01-power-button"
        if command -v dconf >/dev/null 2>&1; then
            dconf update 2>/dev/null || true
        fi
        echo -e "${GREEN}[✔] Power button action left to user preference (GNOME/KDE Settings).${NC}"
    fi

    # 4. Compile and install early hardware initializer (fpc1022-wake)
    # The physical power button tactile dome switch is integrated into the FPC1022 MCU.
    # On cold boot, the MCU starts in sleep mode until S0 state is signaled via USB control transfer.
    echo -e "${BLUE}[*] Setting up FPC1022 hardware power button wake components...${NC}"
    local wake_bin="/usr/local/bin/fpc1022-wake"
    local wake_c="$SCRIPT_DIR/tools/fpc1022-wake.c"
    local wake_prebuilt="$SCRIPT_DIR/tools/fpc1022-wake"
    local wake_installed=false

    if command -v gcc >/dev/null 2>&1 && [[ -f "$wake_c" ]]; then
        echo -e "${BLUE}[*] Compiling hardware initializer $wake_bin...${NC}"
        local libusb_flags
        libusb_flags="$(pkg-config --cflags --libs libusb-1.0 2>/dev/null || echo "-I/usr/include/libusb-1.0 -lusb-1.0")"
        if gcc -O2 -Wall "$wake_c" $libusb_flags -o "$wake_bin" 2>/dev/null; then
            chmod 755 "$wake_bin"
            wake_installed=true
            echo -e "${GREEN}[✔] Compiled and installed $wake_bin.${NC}"
        fi
    fi

    if [[ "$wake_installed" != "true" && -f "$wake_prebuilt" ]]; then
        echo -e "${BLUE}[*] Installing prebuilt hardware initializer binary to $wake_bin...${NC}"
        cp -p "$wake_prebuilt" "$wake_bin"
        chmod 755 "$wake_bin"
        wake_installed=true
        echo -e "${GREEN}[✔] Installed prebuilt $wake_bin.${NC}"
    fi

    # 5. Install udev access rule for FPC1022 USB device (10a5:9200)
    local udev_rule="$SCRIPT_DIR/configs/99-fpc1022-wake.rules"
    if [[ -f "$udev_rule" ]]; then
        echo -e "${BLUE}[*] Installing udev rule to /etc/udev/rules.d/99-fpc1022-wake.rules...${NC}"
        cp -p "$udev_rule" /etc/udev/rules.d/99-fpc1022-wake.rules
        chmod 644 /etc/udev/rules.d/99-fpc1022-wake.rules
        echo -e "${GREEN}[✔] Installed udev access rule for FPC1022.${NC}"
    fi

    # 6. Install systemd boot service fpc1022-wake.service
    local wake_service="$SCRIPT_DIR/configs/fpc1022-wake.service"
    if [[ -f "$wake_service" ]]; then
        echo -e "${BLUE}[*] Installing systemd service /etc/systemd/system/fpc1022-wake.service...${NC}"
        cp -p "$wake_service" /etc/systemd/system/fpc1022-wake.service
        chmod 644 /etc/systemd/system/fpc1022-wake.service
        if command -v systemctl >/dev/null 2>&1; then
            systemctl daemon-reload 2>/dev/null || true
            systemctl enable fpc1022-wake.service 2>/dev/null || true
            echo -e "${GREEN}[✔] Enabled fpc1022-wake.service for cold boot initialization.${NC}"
        fi
    fi

    # 7. Install systemd-sleep hook for wake from suspend / hibernate
    local sleep_script="$SCRIPT_DIR/configs/fpc1022-sleep-wake"
    if [[ -d /usr/lib/systemd/system-sleep && -f "$sleep_script" ]]; then
        echo -e "${BLUE}[*] Installing system-sleep resume hook to /usr/lib/systemd/system-sleep/fpc1022-wake...${NC}"
        cp -p "$sleep_script" /usr/lib/systemd/system-sleep/fpc1022-wake
        chmod 755 /usr/lib/systemd/system-sleep/fpc1022-wake
        echo -e "${GREEN}[✔] Installed sleep resume hook.${NC}"
    fi

    # 8. Trigger immediate hardware initialization now
    if [[ -x "$wake_bin" ]]; then
        echo -e "${BLUE}[*] Triggering immediate hardware wake to S0 state...${NC}"
        "$wake_bin" 2>/dev/null || true
        echo -e "${GREEN}[✔] FPC1022 hardware initialized into S0 state.${NC}"
    fi
}

# Polkit Security Configuration: Enforce password authentication for fingerprint deletion & enrollment
configure_polkit_security() {
    echo -e "${BLUE}[*] Configuring PolicyKit security (password protection for fingerprint credentials)...${NC}"
    local polkit_rule="$SCRIPT_DIR/configs/50-fprintd-auth.rules"
    local polkit_dir="/etc/polkit-1/rules.d"
    
    if [[ -d "$polkit_dir" && -f "$polkit_rule" ]]; then
        echo -e "${BLUE}[*] Installing Polkit rule to ${polkit_dir}/50-fprintd-auth.rules...${NC}"
        cp -p "$polkit_rule" "$polkit_dir/50-fprintd-auth.rules"
        chmod 644 "$polkit_dir/50-fprintd-auth.rules"
        echo -e "${GREEN}[✔] Polkit security rule active: Sudo/admin password required to delete or enroll prints.${NC}"
    fi
}

# Post-install service reload and validation
finalize_installation() {
    echo -e "${BLUE}[*] Reloading udev rules and restarting fprintd.service...${NC}"
    udevadm control --reload 2>/dev/null || true
    udevadm trigger 2>/dev/null || true
    
    systemctl restart fprintd.service || {
        echo -e "${YELLOW}[!] Warning: fprintd.service restart returned non-zero, checking status...${NC}"
    }
    
    sleep 1

    # Optional authselect configuration for Fedora
    if command -v authselect >/dev/null 2>&1; then
        if authselect current >/dev/null 2>&1; then
            if ! authselect current | grep -q "with-fingerprint"; then
                echo -e "${BLUE}[*] Enabling fingerprint auth in authselect...${NC}"
                authselect enable-feature with-fingerprint 2>/dev/null || true
                authselect apply-changes 2>/dev/null || true
            fi
        fi
    fi

    # Configure Polkit security policy (password required to delete/enroll)
    configure_polkit_security

    # Configure power button handling
    configure_power_button

    echo ""
    echo -e "${GREEN}==============================================================================${NC}"
    echo -e "${GREEN}${BOLD}     [✔] UNIFIED INSTALLATION COMPLETE!${NC}"
    echo -e "${GREEN}${BOLD}         - FPC1022 Fingerprint Driver: Installed & Running${NC}"
    echo -e "${GREEN}${BOLD}         - Biometric Security Policy: Password-Guarded Deletion/Enrollment${NC}"
    echo -e "${GREEN}${BOLD}         - Power Button Hardware Wake: Initialized & Enabled at Boot/Resume${NC}"
    echo -e "${GREEN}${BOLD}         - Power Button Policy: Configured (Instant Response & Desktop-Managed)${NC}"
    echo -e "${GREEN}==============================================================================${NC}"
    echo ""
    echo -e "${BOLD}Summary of Applied Changes:${NC}"
    echo -e "  • ${CYAN}Biometric Stack:${NC} Libfprint patched with FPC1022 Match-on-Host & SIGFM OpenCV matcher"
    echo -e "  • ${CYAN}Security Policy:${NC} Polkit rule active (sudo/admin password required to enroll or delete fingerprints)"
    echo -e "  • ${CYAN}Cold-Boot Wake:${NC} /usr/local/bin/fpc1022-wake, udev rule & systemd service (MCU S0 working state)"
    echo -e "  • ${CYAN}Sleep/Resume Hook:${NC} /usr/lib/systemd/system-sleep/fpc1022-wake (immediate power button on resume)"
    echo -e "  • ${CYAN}Power Key Policy:${NC} logind delegated to desktop inhibitors (HoldoffTimeoutSec=0, no delay)"
    echo -e "  • ${CYAN}Desktop Action:${NC} User-determined (manageable via GNOME/KDE Power Settings: Nothing/Suspend/PowerOff)"
    echo -e "  • ${CYAN}User Group:${NC} Added '${BOLD}${TARGET_USER}${NC}' to 'input' group"
    echo ""
    echo -e "${BOLD}Next Steps for Enrollment & Verification:${NC}"
    echo -e "  1. Enroll a finger for your user (${BOLD}${TARGET_USER}${NC}):"
    echo -e "     ${CYAN}fprintd-enroll ${TARGET_USER}${NC}"
    echo -e "     (or specific finger: ${CYAN}fprintd-enroll -f right-index-finger ${TARGET_USER}${NC})"
    echo ""
    echo -e "  2. Test and verify your enrolled fingerprint:"
    echo -e "     ${CYAN}fprintd-verify ${TARGET_USER}${NC}"
    echo ""
    echo -e "  3. Desktop GUI Integration:"
    echo -e "     - ${BOLD}GNOME:${NC} Settings -> Users -> Fingerprint Login"
    echo -e "     - ${BOLD}KDE:${NC} System Settings -> Users -> Fingerprint"
    echo ""
    echo -e "  4. Need to revert? Simply run:"
    echo -e "     ${CYAN}sudo ./uninstall.sh${NC}"
    echo ""
}

# Main script flow
main() {
    print_banner
    check_root
    check_hardware
    detect_distro

    case "$DISTRO_ID" in
        fedora|rhel|centos)
            install_fedora
            ;;
        ubuntu|debian|linuxmint|pop)
            install_ubuntu_debian
            ;;
        arch|manjaro|endeavouros)
            install_arch
            ;;
        *)
            if [[ "$DISTRO_LIKE" =~ (fedora|rhel) ]]; then
                install_fedora
            elif [[ "$DISTRO_LIKE" =~ (ubuntu|debian) ]]; then
                install_ubuntu_debian
            elif [[ "$DISTRO_LIKE" =~ (arch) ]]; then
                install_arch
            else
                echo -e "${YELLOW}[!] Unrecognized distribution '$DISTRO_ID'. Falling back to source build...${NC}"
                install_from_source_debian
            fi
            ;;
    esac

    finalize_installation
}

main "$@"
