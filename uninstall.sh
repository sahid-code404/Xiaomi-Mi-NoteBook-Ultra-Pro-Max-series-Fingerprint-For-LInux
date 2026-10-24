#!/usr/bin/env bash
# ==============================================================================
# Xiaomi Mi NoteBook Ultra / Pro / Max - Linux Fingerprint Driver Uninstaller
# Safely reverts system back to stock distribution libfprint
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

if [[ "$(id -u)" -ne 0 ]]; then
    echo -e "${RED}[ERROR] This uninstaller must be run as root.${NC}" >&2
    echo -e "Please run: ${GREEN}sudo $0${NC}" >&2
    exit 1
fi

echo -e "${YELLOW}==============================================================================${NC}"
echo -e "${YELLOW}${BOLD}     FPC1022 FINGERPRINT DRIVER UNINSTALLER / ROLLBACK${NC}"
echo -e "${YELLOW}==============================================================================${NC}"
echo ""

if [[ ! -f /etc/os-release ]]; then
    echo -e "${RED}[ERROR] /etc/os-release not found. Cannot determine package manager.${NC}" >&2
    exit 1
fi

. /etc/os-release
DISTRO_ID="${ID:-unknown}"
DISTRO_LIKE="${ID_LIKE:-}"

revert_fedora() {
    echo -e "${BLUE}[*] Reverting Fedora/RHEL system packages...${NC}"

    # Remove libfprint from dnf.conf excludepkgs
    local dnf_conf="/etc/dnf/dnf.conf"
    if [[ -f "$dnf_conf" ]]; then
        echo -e "${BLUE}[*] Removing libfprint exclusion from $dnf_conf...${NC}"
        sed -i 's/libfprint\*//g' "$dnf_conf"
        # Clean up dangling empty excludepkgs=
        sed -i '/^[ \t]*excludepkgs=[ \t]*$/d' "$dnf_conf"
    fi

    # Reinstall stock Fedora libfprint package
    echo -e "${BLUE}[*] Reinstalling stock libfprint via DNF...${NC}"
    dnf reinstall -y libfprint || {
        echo -e "${YELLOW}[!] DNF reinstall failed, checking backup binary...${NC}"
        if [[ -f /usr/lib64/libfprint-2.so.2.0.0.stock-backup ]]; then
            cp -p /usr/lib64/libfprint-2.so.2.0.0.stock-backup /usr/lib64/libfprint-2.so.2.0.0
            echo -e "${GREEN}[✔] Restored from /usr/lib64/libfprint-2.so.2.0.0.stock-backup${NC}"
        fi
    }

    # Clean up fprint-deps directory and ld.so config
    echo -e "${BLUE}[*] Cleaning up /usr/local/lib64/fprint-deps and /etc/ld.so.conf.d/fprint.conf...${NC}"
    rm -f /etc/ld.so.conf.d/fprint.conf
    rm -rf /usr/local/lib64/fprint-deps
    rm -f /usr/lib64/libfprint-2.so.2.0.0.stock-backup

    ldconfig
}

revert_debian() {
    echo -e "${BLUE}[*] Reverting Debian/Ubuntu packages...${NC}"
    apt-mark unhold libfprint-2-2 libfprint-fpc1022 2>/dev/null || true
    apt-get remove -y libfprint-fpc1022 2>/dev/null || true
    apt-get install --reinstall -y libfprint-2-2 fprintd
}

revert_arch() {
    echo -e "${BLUE}[*] Reverting Arch Linux packages...${NC}"
    if [[ -f /etc/pacman.conf ]]; then
        sed -i 's/libfprint//g' /etc/pacman.conf
        sed -i '/^[ \t]*IgnorePkg[ \t]*=[ \t]*$/d' /etc/pacman.conf
    fi
    pacman -S --noconfirm libfprint fprintd
}

case "$DISTRO_ID" in
    fedora|rhel|centos)
        revert_fedora
        ;;
    ubuntu|debian|linuxmint|pop)
        revert_debian
        ;;
    arch|manjaro|endeavouros)
        revert_arch
        ;;
    *)
        if [[ "$DISTRO_LIKE" =~ (fedora|rhel) ]]; then
            revert_fedora
        elif [[ "$DISTRO_LIKE" =~ (ubuntu|debian) ]]; then
            revert_debian
        elif [[ "$DISTRO_LIKE" =~ (arch) ]]; then
            revert_arch
        else
            echo -e "${RED}[ERROR] Unsupported distribution: $DISTRO_ID${NC}" >&2
            exit 1
        fi
        ;;
esac

echo -e "${BLUE}[*] Reloading udev rules and restarting fprintd.service...${NC}"
udevadm control --reload 2>/dev/null || true
udevadm trigger 2>/dev/null || true
systemctl restart fprintd.service || true

echo ""
echo -e "${GREEN}==============================================================================${NC}"
echo -e "${GREEN}${BOLD}     [✔] UNINSTALLATION COMPLETE - STOCK DRIVER RESTORED${NC}"
echo -e "${GREEN}==============================================================================${NC}"
echo ""
