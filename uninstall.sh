#!/usr/bin/env bash
# ==============================================================================
# Xiaomi Mi NoteBook Ultra / Pro / Max - Linux Driver & Power Button Uninstaller
# Safely reverts system back to stock distribution libfprint & clean power state
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
echo -e "${YELLOW}${BOLD}     FPC1022 DRIVER & POWER BUTTON FIX UNINSTALLER / ROLLBACK${NC}"
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
        sed -i -E 's/\blibfprint\*[ \t]*//g' "$dnf_conf"
        # Clean up dangling empty excludepkgs=
        sed -i -E '/^[ \t]*excludepkgs[ \t]*=[ \t]*$/d' "$dnf_conf"
    fi

    # Reinstall stock Fedora libfprint package
    echo -e "${BLUE}[*] Reinstalling stock libfprint via DNF...${NC}"
    dnf reinstall -y libfprint || {
        echo -e "${YELLOW}[!] DNF reinstall failed, checking backup binary...${NC}"
        if [[ -f /usr/lib64/libfprint-2.so.2.0.0.stock-backup ]]; then
            cp -p /usr/lib64/libfprint-2.so.2.0.0.stock-backup /usr/lib64/libfprint-2.so.2.0.0
            ln -sf libfprint-2.so.2.0.0 /usr/lib64/libfprint-2.so.2
            echo -e "${GREEN}[✔] Restored from /usr/lib64/libfprint-2.so.2.0.0.stock-backup${NC}"
        fi
    }

    # Clean up fprint-deps directory and ld.so config
    echo -e "${BLUE}[*] Cleaning up /usr/local/lib64/fprint-deps and /etc/ld.so.conf.d/fprint.conf...${NC}"
    rm -f /etc/ld.so.conf.d/fprint.conf
    rm -rf /usr/local/lib64/fprint-deps
    rm -f /usr/lib64/libfprint-2.so.2.0.0.stock-backup

    # Restore SELinux contexts
    if command -v restorecon >/dev/null 2>&1; then
        restorecon -v /usr/lib64/libfprint* 2>/dev/null || true
    fi

    ldconfig
}

revert_debian() {
    echo -e "${BLUE}[*] Reverting Debian/Ubuntu packages...${NC}"
    apt-mark unhold libfprint-2-2 libfprint-fpc1022 2>/dev/null || true
    apt-get remove -y libfprint-fpc1022 2>/dev/null || true
    apt-get install -y libfprint-2-2 fprintd
    ldconfig
}

revert_arch() {
    echo -e "${BLUE}[*] Reverting Arch Linux packages...${NC}"
    if [[ -f /etc/pacman.conf ]]; then
        sed -i -E 's/\blibfprint\b[ \t]*//g' /etc/pacman.conf
        sed -i -E '/^[ \t]*IgnorePkg[ \t]*=[ \t]*$/d' /etc/pacman.conf
    fi
    pacman -S --noconfirm libfprint fprintd
    ldconfig
}

revert_power_button() {
    echo -e "${BLUE}[*] Reverting power button handling configuration...${NC}"
    
    # 1. Remove systemd-logind config and reload
    if [[ -f /etc/systemd/logind.conf.d/10-power-button.conf ]]; then
        echo -e "${BLUE}[*] Removing /etc/systemd/logind.conf.d/10-power-button.conf...${NC}"
        rm -f /etc/systemd/logind.conf.d/10-power-button.conf
        if command -v systemctl >/dev/null 2>&1; then
            echo -e "${BLUE}[*] Reloading systemd-logind...${NC}"
            systemctl reload systemd-logind 2>/dev/null || systemctl kill -s HUP systemd-logind 2>/dev/null || systemctl restart systemd-logind 2>/dev/null || true
        fi
        echo -e "${GREEN}[✔] Removed logind power button override and reloaded systemd-logind.${NC}"
    fi

    # 2. Remove GNOME system-wide dconf override
    if [[ -f /etc/dconf/db/local.d/01-power-button ]]; then
        echo -e "${BLUE}[*] Removing /etc/dconf/db/local.d/01-power-button...${NC}"
        rm -f /etc/dconf/db/local.d/01-power-button
        rm -f /etc/dconf/db/local.d/locks/01-power-button
        if command -v dconf >/dev/null 2>&1; then
            echo -e "${BLUE}[*] Updating dconf database...${NC}"
            dconf update 2>/dev/null || true
            echo -e "${GREEN}[✔] dconf database updated.${NC}"
        fi
    fi

    # 3. Stop, disable and remove fpc1022-wake.service
    if [[ -f /etc/systemd/system/fpc1022-wake.service ]]; then
        echo -e "${BLUE}[*] Disabling and removing /etc/systemd/system/fpc1022-wake.service...${NC}"
        if command -v systemctl >/dev/null 2>&1; then
            systemctl stop fpc1022-wake.service 2>/dev/null || true
            systemctl disable fpc1022-wake.service 2>/dev/null || true
        fi
        rm -f /etc/systemd/system/fpc1022-wake.service
        if command -v systemctl >/dev/null 2>&1; then
            systemctl daemon-reload 2>/dev/null || true
        fi
        echo -e "${GREEN}[✔] Removed fpc1022-wake.service.${NC}"
    fi

    # 4. Remove udev wake rule
    if [[ -f /etc/udev/rules.d/99-fpc1022-wake.rules ]]; then
        echo -e "${BLUE}[*] Removing /etc/udev/rules.d/99-fpc1022-wake.rules...${NC}"
        rm -f /etc/udev/rules.d/99-fpc1022-wake.rules
        echo -e "${GREEN}[✔] Removed udev wake rule.${NC}"
    fi

    # 5. Remove system-sleep hook
    if [[ -f /usr/lib/systemd/system-sleep/fpc1022-wake ]]; then
        echo -e "${BLUE}[*] Removing /usr/lib/systemd/system-sleep/fpc1022-wake...${NC}"
        rm -f /usr/lib/systemd/system-sleep/fpc1022-wake
        echo -e "${GREEN}[✔] Removed sleep resume hook.${NC}"
    fi

    # 6. Remove fpc1022-wake binary
    if [[ -f /usr/local/bin/fpc1022-wake ]]; then
        echo -e "${BLUE}[*] Removing /usr/local/bin/fpc1022-wake...${NC}"
        rm -f /usr/local/bin/fpc1022-wake
        echo -e "${GREEN}[✔] Removed /usr/local/bin/fpc1022-wake binary.${NC}"
    fi

    # 7. Remove Polkit security policy
    if [[ -f /etc/polkit-1/rules.d/50-fprintd-auth.rules ]]; then
        echo -e "${BLUE}[*] Removing /etc/polkit-1/rules.d/50-fprintd-auth.rules...${NC}"
        rm -f /etc/polkit-1/rules.d/50-fprintd-auth.rules
        echo -e "${GREEN}[✔] Removed Polkit security policy.${NC}"
    fi
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

# Revert power button configurations
revert_power_button

echo -e "${BLUE}[*] Reloading udev rules and restarting fprintd.service...${NC}"
udevadm control --reload 2>/dev/null || true
udevadm trigger 2>/dev/null || true
systemctl restart fprintd.service || true

echo ""
echo -e "${GREEN}==============================================================================${NC}"
echo -e "${GREEN}${BOLD}     [✔] UNINSTALLATION COMPLETE${NC}"
echo -e "${GREEN}${BOLD}         - Stock Libfprint Restored${NC}"
echo -e "${GREEN}${BOLD}         - Power Button Customizations Removed${NC}"
echo -e "${GREEN}==============================================================================${NC}"
echo ""
