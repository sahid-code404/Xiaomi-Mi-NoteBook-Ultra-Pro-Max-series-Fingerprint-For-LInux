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

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    local status=0
    "$@" >/dev/null 2>&1 || status=$?
    if (( status != 0 )); then
        print_warn "Best-effort command failed (exit $status): $*"
    fi
    return 0
}

CLEANUP_ORPHANS=false
case "${1:-}" in
    "")
        ;;
    --cleanup-orphans)
        CLEANUP_ORPHANS=true
        ;;
    --help|-h)
        cat <<'EOF'
Usage: sudo ./uninstall.sh [--cleanup-orphans]

Restores the distribution driver and removes files managed by this project.
Optional orphan-package cleanup is opt-in because it may remove unrelated packages.
EOF
        exit 0
        ;;
    *)
        print_err "Unknown option: $1"
        echo "Usage: sudo ./uninstall.sh [--cleanup-orphans]" >&2
        exit 2
        ;;
esac

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

manifest_has_path() {
    local target="$1"
    local manifest="/usr/local/share/fpc1022-backup/managed-paths.txt"
    [[ -f "$manifest" ]] && grep -Fqx -- "$target" "$manifest"
}

is_managed_or_matching() {
    local target="$1"
    local template="${2:-}"
    local backup_root="/usr/local/share/fpc1022-backup"
    local backup="$backup_root/config-backups/${target#/}"

    if manifest_has_path "$target"; then
        # If an originally existing file has lost its backup, leave it in
        # place. The later restoration pass must not interpret a missing
        # backup as permission to delete the current configuration.
        if grep -Fqx -- "$target" "$backup_root/preexisting-paths.txt" 2>/dev/null &&
           [[ ! -e "$backup" && ! -L "$backup" ]]; then
            return 1
        fi
        return 0
    fi
    if [[ -n "$template" && -f "$SCRIPT_DIR/$template" && -f "$target" ]] &&
       cmp -s -- "$SCRIPT_DIR/$template" "$target"; then
        return 0
    fi
    return 1
}

restore_file_atomically() {
    local source="$1"
    local target="$2"
    local temp

    if [[ ! -f "$source" ]]; then
        print_err "Backup file does not exist: $source"
        return 1
    fi
    temp="$(mktemp "${target}.restore.XXXXXX")" || {
        print_err "Could not create a temporary restore file beside $target."
        return 1
    }
    if ! cp -p -- "$source" "$temp" || ! mv -f -- "$temp" "$target"; then
        rm -f -- "$temp"
        print_err "Could not atomically restore $target; backup remains at $source."
        return 1
    fi
}

revert_fedora() {
    # Do not rewrite existing DNF configuration automatically: older
    # installer versions did not record whether exclusions predated installation.
    # Inspect /etc/dnf/dnf.conf manually if a legacy exclusion remains.

    # Remove only the exact global loader path written by older project releases.
    # Preserve this file if it contains any other settings.
    local loader_conf="/etc/ld.so.conf.d/fprint.conf"
    local legacy_driver_backup="/usr/local/share/fpc1022-backup/libfprint-2.so.2.0.0.stock-backup"
    if ! manifest_has_path "$loader_conf" &&
       [[ -f "$loader_conf" ]] &&
       [[ "$(cat "$loader_conf")" == "/usr/local/lib64/fprint-deps" ]] &&
       { [[ -f "$legacy_driver_backup" ]] || [[ -f /usr/lib64/libfprint-2.so.2.0.0.stock-backup ]]; }; then
        rm -f -- "$loader_conf"
        print_ok "Removed the exact legacy loader path created by an older installation"
    fi

    # Restore stock libfprint (do NOT delete system packages)
    local backup_lib="/usr/local/share/fpc1022-backup/libfprint-2.so.2.0.0.stock-backup"
    if [[ -f "$backup_lib" ]]; then
        restore_file_atomically "$backup_lib" /usr/lib64/libfprint-2.so.2.0.0
        ln -sf libfprint-2.so.2.0.0 /usr/lib64/libfprint-2.so.2
        print_ok "Restored stock libfprint from backup"
    elif [[ -f /usr/lib64/libfprint-2.so.2.0.0.stock-backup ]]; then
        restore_file_atomically /usr/lib64/libfprint-2.so.2.0.0.stock-backup /usr/lib64/libfprint-2.so.2.0.0
        ln -sf libfprint-2.so.2.0.0 /usr/lib64/libfprint-2.so.2
        print_ok "Restored stock libfprint from legacy backup"
    else
        if dnf reinstall -y libfprint; then
            print_ok "Reinstalled stock libfprint package"
        else
            print_err "Could not reinstall stock libfprint. Restore it with the Fedora package manager before using fingerprint authentication."
            return 1
        fi
    fi

    # Restore a pre-existing dependency directory if one was present. New
    # installs have no backup here, so their bundled files are simply removed.
    local deps_dir="/usr/local/lib64/fprint-deps"
    local deps_backup="/usr/local/share/fpc1022-backup/previous-fprint-deps"
    rm -rf -- "$deps_dir"
    if [[ -d "$deps_backup" ]]; then
        cp -a -- "$deps_backup" "$deps_dir"
        print_ok "Restored previous runtime dependency directory"
    fi
    rm -f /usr/lib64/libfprint-2.so.2.0.0.stock-backup

    if command -v restorecon >/dev/null 2>&1; then
        run_cmd restorecon -v /usr/lib64/libfprint*
    fi
    run_cmd ldconfig
    print_warn "Inspect /etc/dnf/dnf.conf for legacy libfprint exclusions; this version preserves existing configuration."
}

revert_debian() {
    # Remove our native package first if it was installed as a Debian package.
    # This avoids a Conflicts/Replaces collision with the distribution package.
    if dpkg-query -W -f='${Status}' libfprint-fpc1022 2>/dev/null | grep -q 'install ok installed'; then
        if ! apt-get remove -y libfprint-fpc1022; then
            print_err "Could not remove libfprint-fpc1022 before restoring the distribution package."
            return 1
        fi
    fi

    # Older releases may have held these packages, but there is no state file
    # that proves those holds were added by this project. Preserve user policy.
    if apt-get install --reinstall -y libfprint-2-2 fprintd; then
        print_ok "Restored stock Debian/Ubuntu libfprint packages"
    else
        print_err "Could not restore stock packages. Resolve the package conflict before using fingerprint authentication."
        return 1
    fi
    run_cmd ldconfig
    print_warn "Check 'apt-mark showhold' and remove only any hold created for this driver."
}

revert_arch() {
    # Restore packages even after a source build replaced files belonging to
    # an installed package. Remove our named package if the binary package path
    # was used, then reinstall the distribution's package.
    if pacman -Q libfprint-fpc1022 >/dev/null 2>&1; then
        if ! pacman -R libfprint-fpc1022; then
            print_err "Could not remove libfprint-fpc1022 before restoring the distribution package."
            return 1
        fi
    fi
    if pacman -S --overwrite 'usr/lib/libfprint-2.so.*' libfprint fprintd; then
        print_ok "Restored stock Arch libfprint packages"
    else
        print_err "Could not restore stock packages. Resolve the package conflict before using fingerprint authentication."
        return 1
    fi
    run_cmd ldconfig
    print_warn "Inspect /etc/pacman.conf for any legacy IgnorePkg entry for libfprint."
}

restore_managed_paths() {
    local backup_root="/usr/local/share/fpc1022-backup"
    local manifest="$backup_root/managed-paths.txt"
    local preexisting="$backup_root/preexisting-paths.txt"
    local created="$backup_root/created-paths.txt"
    local target backup relative
    [[ -f "$manifest" ]] || return 0

    while IFS= read -r target; do
        [[ -n "$target" && "$target" == /* ]] || continue
        relative="${target#/}"
        backup="$backup_root/config-backups/$relative"
        if [[ -e "$backup" || -L "$backup" ]]; then
            mkdir -p "$(dirname "$target")"
            rm -f -- "$target"
            cp -a -- "$backup" "$target"
            print_ok "Restored previous file: $target"
        elif grep -Fqx -- "$target" "$created" 2>/dev/null; then
            rm -f -- "$target"
            print_ok "Removed file created by this installer: $target"
        elif grep -Fqx -- "$target" "$preexisting" 2>/dev/null; then
            # The backup may have been removed or damaged. Preserve the current
            # file rather than deleting a user's pre-existing configuration.
            print_warn "Original backup is missing; preserved current file: $target"
        else
            # Compatibility fallback for manifests created by earlier versions.
            rm -f -- "$target"
            print_warn "Removed legacy managed file without an original-state ledger: $target"
        fi
    done < "$manifest"

    if command -v dconf >/dev/null 2>&1 &&
       grep -Eq '^/etc/dconf/' "$manifest"; then
        run_cmd dconf update
    fi
}

revert_generic_source() {
    local lib_dir="/usr/lib"
    if [[ "$DISTRO_ID" == "debian" || "$DISTRO_ID" == "ubuntu" ||
          "$DISTRO_ID" == "linuxmint" || "$DISTRO_ID" == "pop" ]]; then
        local multiarch=""
        if command -v dpkg-architecture >/dev/null 2>&1; then
            multiarch="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || true)"
        fi
        if [[ -z "$multiarch" ]] && command -v gcc >/dev/null 2>&1; then
            multiarch="$(gcc -print-multiarch 2>/dev/null || true)"
        fi
        # The compiler or dpkg-dev may have been removed since installation.
        # Prefer the multiarch directory containing the installed libfprint.
        if [[ -z "$multiarch" ]]; then
            local candidate
            for candidate in /usr/lib/*-linux-gnu; do
                [[ -d "$candidate" ]] || continue
                if [[ -f "$candidate/libfprint-2.so.2.0.0" ||
                      -e "$candidate/libfprint-2.so.2" ]]; then
                    multiarch="${candidate#/usr/lib/}"
                    break
                fi
            done
        fi
        [[ -z "$multiarch" || ! -d "/usr/lib/$multiarch" ]] || lib_dir="/usr/lib/$multiarch"
    elif [[ -d /usr/lib64 ]]; then
        lib_dir="/usr/lib64"
    fi

    local backup="/usr/local/share/fpc1022-backup/libfprint-2.so.2.0.0.stock-backup"
    local target="$lib_dir/libfprint-2.so.2.0.0"
    if [[ -f "$backup" ]]; then
        local restore_tmp
        restore_tmp="$(mktemp "${target}.restore.XXXXXX")" || {
            print_err "Could not create a temporary file beside $target; backup was preserved at $backup."
            return 1
        }
        if ! cp -p -- "$backup" "$restore_tmp" || ! mv -f -- "$restore_tmp" "$target"; then
            rm -f -- "$restore_tmp"
            print_err "Could not restore $target; backup was preserved at $backup."
            return 1
        fi
        ln -sf libfprint-2.so.2.0.0 "$lib_dir/libfprint-2.so.2"
        print_ok "Restored saved libfprint library at $target"
    else
        print_err "No original libfprint backup was found for $lib_dir. Refusing to report successful rollback; reinstall the distribution's libfprint package manually."
        return 1
    fi
    run_cmd ldconfig
}

revert_power_button() {
    local logind_conf="/etc/systemd/logind.conf.d/10-power-button.conf"
    local dconf_override="/etc/dconf/db/local.d/01-power-button"
    local dconf_lock="/etc/dconf/db/local.d/locks/01-power-button"
    local wake_service="/etc/systemd/system/fpc1022-wake.service"
    local udev_rule="/etc/udev/rules.d/99-fpc1022-wake.rules"
    local sleep_hook="/usr/lib/systemd/system-sleep/fpc1022-wake"
    local wake_bin="/usr/local/bin/fpc1022-wake"

    if [[ -f "$logind_conf" ]]; then
        if is_managed_or_matching "$logind_conf" "configs/10-power-button.conf"; then
            rm -f -- "$logind_conf"
            run_cmd systemctl reload systemd-logind
            print_ok "Removed installer power-button policy"
        else
            print_warn "Preserved unrecognized logind config: $logind_conf"
        fi
    fi

    # These legacy dconf paths were removed by older installers. Only remove
    # them automatically when a current manifest proves this installer touched them.
    if manifest_has_path "$dconf_override"; then
        rm -f -- "$dconf_override"
    fi
    if manifest_has_path "$dconf_lock"; then
        rm -f -- "$dconf_lock"
    fi

    if [[ -f "$wake_service" ]]; then
        if is_managed_or_matching "$wake_service" "configs/fpc1022-wake.service"; then
            run_cmd systemctl stop fpc1022-wake.service
            run_cmd systemctl disable fpc1022-wake.service
            rm -f -- "$wake_service"
            run_cmd systemctl daemon-reload
            print_ok "Removed installer wake service"
        else
            print_warn "Preserved unrecognized systemd unit: $wake_service"
        fi
    fi

    if [[ -f "$udev_rule" ]]; then
        if is_managed_or_matching "$udev_rule" "configs/99-fpc1022-wake.rules"; then
            rm -f -- "$udev_rule"
            print_ok "Removed installer udev rule"
        else
            print_warn "Preserved unrecognized udev rule: $udev_rule"
        fi
    fi

    if [[ -f "$sleep_hook" ]]; then
        if is_managed_or_matching "$sleep_hook" "configs/fpc1022-sleep-wake"; then
            rm -f -- "$sleep_hook"
            print_ok "Removed installer resume hook"
        else
            print_warn "Preserved unrecognized sleep hook: $sleep_hook"
        fi
    fi

    if [[ -f "$wake_bin" ]]; then
        if manifest_has_path "$wake_bin" ||
           (command -v strings >/dev/null 2>&1 && strings "$wake_bin" | grep -q 'fpc1022-wake:'); then
            rm -f -- "$wake_bin"
            print_ok "Removed installer wake helper"
        else
            print_warn "Preserved unrecognized binary: $wake_bin"
        fi
    fi
}

revert_security() {
    local rule="/etc/polkit-1/rules.d/50-fprintd-auth.rules"
    if [[ -f "$rule" ]]; then
        if is_managed_or_matching "$rule" "configs/50-fprintd-auth.rules"; then
            rm -f -- "$rule"
            print_ok "Removed installer Polkit rule"
        else
            print_warn "Preserved unrecognized Polkit rule: $rule"
        fi
    fi
}

cleanup_orphans() {
    print_warn "Optional package cleanup requested; review the package manager's plan before confirming."
    case "$DISTRO_ID" in
        fedora|rhel|centos)
            command -v dnf >/dev/null 2>&1 && dnf autoremove
            ;;
        ubuntu|debian|linuxmint|pop)
            command -v apt-get >/dev/null 2>&1 && apt-get autoremove
            ;;
        arch|manjaro|endeavouros)
            if command -v pacman >/dev/null 2>&1; then
                local -a orphans=()
                mapfile -t orphans < <(pacman -Qtdq 2>/dev/null || true)
                if (("${#orphans[@]}" > 0)); then
                    printf 'Orphan packages eligible for removal:\n'
                    printf '  %s\n' "${orphans[@]}"
                    read -r -p "Remove these packages? [y/N]: " answer
                    if [[ "$answer" =~ ^[yY]([eE][sS])?$ ]]; then
                        pacman -Rns -- "${orphans[@]}"
                    else
                        print_warn "Orphan cleanup skipped."
                    fi
                else
                    print_ok "No orphan packages found."
                fi
            fi
            ;;
        *)
            print_warn "Run your distribution's orphan cleanup manually if required."
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Main Flow
# ------------------------------------------------------------------------------
main() {
    print_banner

    print_step "1/5" "Restoring stock system driver..."
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
        opensuse*|sles)
            revert_generic_source
            ;;
        *)
            if [[ "$DISTRO_LIKE" =~ (fedora|rhel) ]]; then
                revert_fedora
            elif [[ "$DISTRO_LIKE" =~ (ubuntu|debian) ]]; then
                revert_debian
            elif [[ "$DISTRO_LIKE" =~ (arch) ]]; then
                revert_arch
            elif [[ "$DISTRO_LIKE" =~ (suse) ]]; then
                revert_generic_source
            else
                revert_generic_source
            fi
            ;;
    esac

    print_step "2/5" "Reverting power button configuration..."
    revert_power_button

    print_step "3/5" "Reverting security policies..."
    revert_security

    print_step "4/5" "Restoring previous configuration files..."
    restore_managed_paths
    if command -v systemctl >/dev/null 2>&1; then
        run_cmd systemctl daemon-reload
        run_cmd systemctl reload systemd-logind
        local service_state="/usr/local/share/fpc1022-backup/fpc1022-wake-service.state"
        if [[ -f "$service_state" ]] && grep -qx 'enabled' "$service_state"; then
            run_cmd systemctl enable fpc1022-wake.service
        fi
        if [[ -f "$service_state" ]] && grep -qx 'active' "$service_state"; then
            run_cmd systemctl start fpc1022-wake.service
        fi
    fi
    if command -v udevadm >/dev/null 2>&1; then
        run_cmd udevadm control --reload
        run_cmd udevadm trigger
    else
        print_warn "udevadm unavailable; reload udev rules manually if hardware permissions do not update."
    fi
    run_cmd ldconfig

    # Older installer versions changed authentication configuration without
    # recording its prior state, so never overwrite PAM/authselect blindly.
    print_warn "Review PAM/authselect settings manually if an older installer enabled fingerprint login."

    # Restart fprintd after library restoration, when systemd and the unit exist.
    if command -v systemctl >/dev/null 2>&1 &&
       systemctl is-active --quiet fprintd.service; then
        run_cmd systemctl restart fprintd.service
    fi

    print_step "5/5" "Optional orphan-package cleanup..."
    if [[ "$CLEANUP_ORPHANS" == "true" ]]; then
        cleanup_orphans
    else
        print_ok "Skipped orphan-package cleanup (safe default)."
    fi

    rm -rf /usr/local/share/fpc1022-backup

    echo ""
    echo -e "${GREEN}====================================================================${NC}"
    echo -e "${GREEN}${BOLD}  ✔ Driver rollback steps completed.${NC}"
    echo -e "${GREEN}====================================================================${NC}"
    echo ""
}

main "$@"
