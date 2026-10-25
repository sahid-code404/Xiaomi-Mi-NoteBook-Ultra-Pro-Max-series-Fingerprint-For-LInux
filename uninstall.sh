#!/usr/bin/env bash
# ==============================================================================
# Xiaomi Mi NoteBook Ultra / Pro / Max - Fingerprint & Power Button Uninstaller
# Restores original distribution driver and cleanly removes all custom configs
# Author: Sahidul Haque (sahid-code404) & Contributors
# License: LGPL-2.1-or-later
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

print_banner() {
    cat << "EOF"
====================================================================
 Xiaomi Mi NoteBook Fingerprint & Power Button Uninstaller
====================================================================
EOF
}

print_step() { echo -e "\n${BOLD}${BLUE}[$1]${NC} ${BOLD}$2${NC}"; }
print_ok()   { echo -e "    ${GREEN}✔${NC} $*"; }
print_warn() { echo -e "    ${YELLOW}!${NC} $*"; }
print_err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }

run_cmd() {
    "$@" >/dev/null 2>&1 || true
}

if [[ "$(id -u)" -ne 0 ]]; then
    print_err "This uninstaller must be run as root. Please run: sudo $0"
    exit 1
fi

if [[ ! -f /etc/os-release ]]; then
    print_err "Cannot detect Linux distribution (/etc/os-release missing)."
    exit 1
fi

. /etc/os-release
DISTRO_ID="${ID:-unknown}"
DISTRO_LIKE="${ID_LIKE:-}"

revert_fedora() {
    # 1. Remove libfprint exclusion from dnf.conf
    local dnf_conf="/etc/dnf/dnf.conf"
    if [[ -f "$dnf_conf" ]]; then
        sed -i -E 's/\blibfprint\*[ \t]*//g' "$dnf_conf"
        sed -i -E '/^[ \t]*excludepkgs[ \t]*=[ \t]*$/d' "$dnf_conf"
    fi

    # 2. Restore stock libfprint (do NOT delete system packages)
    local backup_lib="/usr/local/share/fpc1022-backup/libfprint-2.so.2.0.0.stock-backup"
    if [[ -f "$backup_lib" ]]; then
        cp -p "$backup_lib" /usr/lib64/libfprint-2.so.2.0.0
        ln -sf libfprint-2.so.2.0.0 /usr/lib64/libfprint-2.so.2
        print_ok "Restored stock libfprint from backup"
    elif [[ -f /usr/lib64/libfprint-2.so.2.0.0.stock-backup ]]; then
        cp -p /usr/lib64/libfprint-2.so.2.0.0.stock-backup /usr/lib64/libfprint-2.so.2.0.0
        ln -sf libfprint-2.so.2.0.0 /usr/lib64/libfprint-2.so.2
        print_ok "Restored stock libfprint from legacy backup"
    else
        run_cmd dnf reinstall -y libfprint
        print_ok "Reinstalled stock libfprint package"
    fi

    # Clean up custom dependency files and backup directory
    rm -f /etc/ld.so.conf.d/fprint.conf
    rm -rf /usr/local/lib64/fprint-deps
    rm -rf /usr/local/share/fpc1022-backup
    rm -f /usr/lib64/*stock-backup*

    if command -v restorecon >/dev/null 2>&1; then
        run_cmd restorecon -v /usr/lib64/libfprint*
    fi
    run_cmd ldconfig
    print_ok "Cleared DNF package exclusion locks"
}

revert_debian() {
    run_cmd apt-mark unhold libfprint-2-2 libfprint-fpc1022
    run_cmd apt-get install --reinstall -y libfprint-2-2 fprintd
    run_cmd ldconfig
    print_ok "Restored stock Debian/Ubuntu libfprint"
    print_ok "Cleared APT package holds"
}

revert_arch() {
    if [[ -f /etc/pacman.conf ]]; then
        sed -i -E 's/\blibfprint\b[ \t]*//g' /etc/pacman.conf
        sed -i -E '/^[ \t]*IgnorePkg[ \t]*=[ \t]*$/d' /etc/pacman.conf
    fi
    run_cmd pacman -S --noconfirm --needed libfprint fprintd
    run_cmd ldconfig
    print_ok "Restored stock Arch libfprint"
    print_ok "Cleared Pacman package locks"
}

revert_power_button() {
    # 1. logind config
    if [[ -f /etc/systemd/logind.conf.d/10-power-button.conf ]]; then
        rm -f /etc/systemd/logind.conf.d/10-power-button.conf
        if command -v systemctl >/dev/null 2>&1; then
            systemctl reload systemd-logind 2>/dev/null || systemctl kill -s HUP systemd-logind 2>/dev/null || true
        fi
        print_ok "Removed logind power button policy"
    fi

    # 2. dconf overrides
    if [[ -f /etc/dconf/db/local.d/01-power-button ]]; then
        rm -f /etc/dconf/db/local.d/01-power-button
        rm -f /etc/dconf/db/local.d/locks/01-power-button
        if command -v dconf >/dev/null 2>&1; then
            run_cmd dconf update
        fi
        print_ok "Removed desktop power button overrides"
    fi

    # 3. fpc1022-wake systemd service
    if [[ -f /etc/systemd/system/fpc1022-wake.service ]]; then
        if command -v systemctl >/dev/null 2>&1; then
            run_cmd systemctl stop fpc1022-wake.service
            run_cmd systemctl disable fpc1022-wake.service
        fi
        rm -f /etc/systemd/system/fpc1022-wake.service
        if command -v systemctl >/dev/null 2>&1; then
            run_cmd systemctl daemon-reload
        fi
        print_ok "Disabled and removed fpc1022-wake service"
    fi

    # 4. udev rule
    if [[ -f /etc/udev/rules.d/99-fpc1022-wake.rules ]]; then
        rm -f /etc/udev/rules.d/99-fpc1022-wake.rules
        print_ok "Removed udev rule"
    fi

    # 5. sleep hook & binary
    rm -f /usr/lib/systemd/system-sleep/fpc1022-wake
    rm -f /usr/local/bin/fpc1022-wake
    print_ok "Removed hardware wake binary and sleep hooks"
}

revert_security() {
    if [[ -f /etc/polkit-1/rules.d/50-fprintd-auth.rules ]]; then
        rm -f /etc/polkit-1/rules.d/50-fprintd-auth.rules
        print_ok "Removed Polkit security rule"
    fi
}

cleanup_orphans() {
    case "$DISTRO_ID" in
        fedora|rhel|centos)
            if command -v dnf >/dev/null 2>&1; then
                run_cmd dnf autoremove -y
            fi
            ;;
        ubuntu|debian|linuxmint|pop)
            if command -v apt-get >/dev/null 2>&1; then
                run_cmd apt-get autoremove -y
            fi
            ;;
        arch|manjaro|endeavouros)
            if command -v pacman >/dev/null 2>&1; then
                local orphans
                orphans="$(pacman -Qtdq 2>/dev/null || true)"
                if [[ -n "$orphans" ]]; then
                    run_cmd pacman -Rns --noconfirm $orphans
                fi
            fi
            ;;
        *)
            if [[ "$DISTRO_LIKE" =~ (fedora|rhel) ]] && command -v dnf >/dev/null 2>&1; then
                run_cmd dnf autoremove -y
            elif [[ "$DISTRO_LIKE" =~ (ubuntu|debian) ]] && command -v apt-get >/dev/null 2>&1; then
                run_cmd apt-get autoremove -y
            fi
            ;;
    esac
    print_ok "Cleaned up unneeded orphan dependencies"
}

# ------------------------------------------------------------------------------
# Main Flow
# ------------------------------------------------------------------------------
main() {
    print_banner

    print_step "1/4" "Restoring stock system driver..."
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
                print_warn "Distribution '$DISTRO_ID': Please reinstall stock libfprint using your package manager."
            fi
            ;;
    esac

    print_step "2/4" "Reverting power button configuration..."
    revert_power_button

    print_step "3/4" "Reverting security policies..."
    revert_security

    # Reload system services
    run_cmd udevadm control --reload
    run_cmd udevadm trigger
    run_cmd systemctl restart fprintd.service

    print_step "4/4" "Cleaning up system packages..."
    cleanup_orphans

    echo ""
    echo -e "${GREEN}====================================================================${NC}"
    echo -e "${GREEN}${BOLD}  ✔ Uninstallation Complete! System restored to stock settings.${NC}"
    echo -e "${GREEN}====================================================================${NC}"
    echo ""
}

main "$@"
