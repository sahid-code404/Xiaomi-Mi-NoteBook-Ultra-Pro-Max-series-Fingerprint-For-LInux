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
BACKUP_ROOT="/usr/local/share/fpc1022-backup"

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

Restores native packages and files managed by this installer.
Orphan cleanup is opt-in because it may remove packages unrelated to this driver.
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
    local manifest="$BACKUP_ROOT/managed-paths.txt"
    [[ -f "$manifest" ]] && grep -Fqx -- "$target" "$manifest"
}

is_managed_or_matching() {
    local target="$1" template="${2:-}"
    local backup="$BACKUP_ROOT/config-backups/${target#/}"
    if manifest_has_path "$target"; then
        if grep -Fqx -- "$target" "$BACKUP_ROOT/preexisting-paths.txt" 2>/dev/null &&
           [[ ! -e "$backup" && ! -L "$backup" ]]; then
            return 1
        fi
        return 0
    fi
    [[ -n "$template" && -f "$SCRIPT_DIR/$template" && -f "$target" ]] &&
        cmp -s -- "$SCRIPT_DIR/$template" "$target"
}

restore_file_atomically() {
    local source="$1" target="$2" temp
    [[ -f "$source" ]] || { print_err "Backup missing: $source"; return 1; }
    temp="$(mktemp "${target}.restore.XXXXXX")" || return 1
    if ! cp -p -- "$source" "$temp" || ! mv -f -- "$temp" "$target"; then
        rm -f -- "$temp"
        print_err "Could not restore $target; backup remains at $source."
        return 1
    fi
}

restore_managed_paths() {
    local manifest="$BACKUP_ROOT/managed-paths.txt"
    local preexisting="$BACKUP_ROOT/preexisting-paths.txt"
    local created="$BACKUP_ROOT/created-paths.txt"
    local target backup relative
    [[ -f "$manifest" ]] || return 0
    while IFS= read -r target; do
        [[ -n "$target" && "$target" == /* ]] || continue
        relative="${target#/}"
        backup="$BACKUP_ROOT/config-backups/$relative"
        if [[ -e "$backup" || -L "$backup" ]]; then
            mkdir -p "$(dirname "$target")"
            rm -f -- "$target"
            cp -a -- "$backup" "$target"
            print_ok "Restored previous file: $target"
        elif grep -Fqx -- "$target" "$created" 2>/dev/null; then
            rm -f -- "$target"
            print_ok "Removed file created by this installer: $target"
        elif grep -Fqx -- "$target" "$preexisting" 2>/dev/null; then
            print_warn "Original backup missing; preserved current file: $target"
        else
            rm -f -- "$target"
            print_warn "Removed legacy managed file: $target"
        fi
    done < "$manifest"
    if command -v dconf >/dev/null 2>&1 && grep -Eq '^/etc/dconf/' "$manifest"; then
        run_cmd dconf update
    fi
}

restore_wake_service_state() {
    local state="$BACKUP_ROOT/fpc1022-wake-service.state"
    [[ -f "$state" ]] || return 0
    if command -v systemctl >/dev/null 2>&1; then
        if grep -qx 'enabled' "$state"; then run_cmd systemctl enable fpc1022-wake.service; else run_cmd systemctl disable fpc1022-wake.service; fi
        if grep -qx 'active' "$state"; then run_cmd systemctl start fpc1022-wake.service; else run_cmd systemctl stop fpc1022-wake.service; fi
    fi
}


revert_fedora() {
    # Current releases are installed as an RPM. Let DNF perform the complete
    # replacement transaction instead of copying libraries behind its back.
    if rpm -q libfprint-fpc1022 >/dev/null 2>&1; then
        dnf remove -y libfprint-fpc1022
    fi
    dnf install -y libfprint fprintd fprintd-pam

    # Remove only the exact global loader path used by old project versions.
    # Preserve user-managed loader configuration and backups unless recognized.
    local loader_conf="/etc/ld.so.conf.d/fprint.conf"
    local legacy_backup="$BACKUP_ROOT/libfprint-2.so.2.0.0.stock-backup"
    if [[ -f "$loader_conf" ]] &&
       [[ "$(cat "$loader_conf")" == "/usr/local/lib64/fprint-deps" ]] &&
       { [[ -f "$legacy_backup" ]] || [[ -f /usr/lib64/libfprint-2.so.2.0.0.stock-backup ]]; }; then
        rm -f -- "$loader_conf"
        rm -rf -- /usr/local/lib64/fprint-deps
    elif [[ -e "$loader_conf" ]]; then
        print_warn "Preserved unrecognized loader configuration: $loader_conf"
    fi

    if command -v restorecon >/dev/null 2>&1; then
        run_cmd restorecon -v /usr/lib64/libfprint*
    fi
    run_cmd ldconfig
    print_ok "Restored the stock Fedora libfprint package"
}

revert_debian() {
    if dpkg-query -W -f='${Status}' libfprint-fpc1022 2>/dev/null | grep -q '^install ok installed$'; then
        apt-get remove -y libfprint-fpc1022
    fi
    apt-get install --reinstall -y libfprint-2-2 fprintd
    run_cmd ldconfig
    print_ok "Restored stock Debian/Ubuntu libfprint"
}

revert_arch() {
    if pacman -Q libfprint-fpc1022 >/dev/null 2>&1; then
        pacman -Rns --noconfirm libfprint-fpc1022
    fi
    pacman -S --noconfirm --needed libfprint fprintd
    run_cmd ldconfig
    print_ok "Restored stock Arch libfprint"
}

revert_power_button() {
    local wake_service="/etc/systemd/system/fpc1022-wake.service"
    # Stop only a service that this installer managed (or whose contents
    # exactly match the known project unit). File restoration happens later.
    if [[ -f "$wake_service" ]] && is_managed_or_matching "$wake_service" "configs/fpc1022-wake.service"; then
        run_cmd systemctl stop fpc1022-wake.service
        run_cmd systemctl disable fpc1022-wake.service
    fi
}

revert_security() {
    local rule="/etc/polkit-1/rules.d/50-fprintd-auth.rules"
    if [[ -f "$rule" ]] && ! is_managed_or_matching "$rule" "configs/50-fprintd-auth.rules"; then
        print_warn "Preserved unrecognized Polkit rule: $rule"
    fi
    # Managed rules are restored or removed by restore_managed_paths().
}

revert_generic_source() {
    local lib_dir="/usr/lib"
    case "$DISTRO_ID" in
        debian|ubuntu|linuxmint|pop)
            local multiarch=""
            if command -v dpkg-architecture >/dev/null 2>&1; then
                multiarch="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || true)"
            fi
            if [[ -z "$multiarch" ]] && command -v gcc >/dev/null 2>&1; then
                multiarch="$(gcc -print-multiarch 2>/dev/null || true)"
            fi
            if [[ -z "$multiarch" ]]; then
                local candidate
                for candidate in /usr/lib/*-linux-gnu; do
                    [[ -d "$candidate" ]] || continue
                    if [[ -f "$candidate/libfprint-2.so.2.0.0" || -e "$candidate/libfprint-2.so.2" ]]; then
                        multiarch="${candidate#/usr/lib/}"
                        break
                    fi
                done
            fi
            [[ -z "$multiarch" || ! -d "/usr/lib/$multiarch" ]] || lib_dir="/usr/lib/$multiarch"
            ;;
        *)
            [[ ! -d /usr/lib64 ]] || lib_dir="/usr/lib64"
            ;;
    esac
    local target="$lib_dir/libfprint-2.so.2.0.0"
    local backup="$BACKUP_ROOT/libfprint-2.so.2.0.0.stock-backup"
    if [[ -f "$backup" ]]; then
        restore_file_atomically "$backup" "$target"
        ln -sf libfprint-2.so.2.0.0 "$lib_dir/libfprint-2.so.2"
        run_cmd ldconfig
        print_ok "Restored original libfprint library"
    else
        print_warn "No source-build backup was found; reinstall the distribution's libfprint package if needed."
    fi
}

cleanup_orphans() {
    local answer=""
    print_warn "Optional orphan cleanup may remove packages unrelated to this driver."
    case "$DISTRO_ID" in
        fedora|rhel|centos)
            dnf autoremove --assumeno || print_warn "DNF preview returned non-zero."
            read -r -p "Run the DNF orphan cleanup shown above? [y/N]: " answer || answer=""
            [[ ! "$answer" =~ ^[yY]([eE][sS])?$ ]] || dnf autoremove
            ;;
        ubuntu|debian|linuxmint|pop)
            apt-get -s autoremove || print_warn "APT preview returned non-zero."
            read -r -p "Run the APT orphan cleanup shown above? [y/N]: " answer || answer=""
            [[ ! "$answer" =~ ^[yY]([eE][sS])?$ ]] || apt-get autoremove
            ;;
        arch|manjaro|endeavouros)
            local -a orphans=()
            mapfile -t orphans < <(pacman -Qtdq 2>/dev/null || true)
            if (("${#orphans[@]}" > 0)); then
                printf 'Orphan packages eligible for removal:\n'
                printf '  %s\n' "${orphans[@]}"
                read -r -p "Remove these packages? [y/N]: " answer || answer=""
                [[ ! "$answer" =~ ^[yY]([eE][sS])?$ ]] || pacman -Rns -- "${orphans[@]}"
            else
                print_ok "No orphan packages found."
            fi
            ;;
        *) print_warn "Run your distribution's orphan cleanup manually if needed." ;;
    esac
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
            else
                revert_generic_source
            fi
            ;;
    esac

    print_step "2/4" "Reverting power button configuration..."
    revert_power_button

    print_step "3/5" "Reverting security policies..."
    revert_security

    print_step "4/5" "Restoring configuration files and service state..."
    restore_managed_paths
    if command -v systemctl >/dev/null 2>&1; then
        run_cmd systemctl daemon-reload
        run_cmd systemctl reload systemd-logind
        restore_wake_service_state
    fi
    if command -v udevadm >/dev/null 2>&1; then
        run_cmd udevadm control --reload
        run_cmd udevadm trigger
    fi
    run_cmd ldconfig
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet fprintd.service; then
        run_cmd systemctl restart fprintd.service
    fi
    print_warn "Review PAM/authselect manually if an older installer enabled fingerprint login."

    print_step "5/5" "Optional orphan-package cleanup..."
    if [[ "$CLEANUP_ORPHANS" == "true" ]]; then
        cleanup_orphans
    else
        print_ok "Skipped orphan-package cleanup (safe default)."
    fi
    rm -rf -- "$BACKUP_ROOT"

    echo ""
    echo -e "${GREEN}====================================================================${NC}"
    echo -e "${GREEN}${BOLD}  ✔ Uninstallation Complete! System restored to stock settings.${NC}"
    echo -e "${GREEN}====================================================================${NC}"
    echo ""
}

main "$@"
