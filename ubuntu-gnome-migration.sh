#!/bin/bash
# ==============================================================================
# Ubuntu GNOME Backup & Restore Tool (Modular Pipeline Edition)
#
# Usage:
#   ./ubuntu-gnome-migration.sh backup  [output-dir]
#   ./ubuntu-gnome-migration.sh restore <backup-dir>
#   ./ubuntu-gnome-migration.sh --help
#
# Description:
#   Comprehensive backup and restore tool for Ubuntu desktop environments.
#   Uses atomic step execution managed by a pipeline engine while preserving
#   the standard CLI argument interface.
#
# Requirements:
#   - Does not require root (restore uses sudo for apt/snap)
#   - Must be run from an active desktop session for dconf restore
# ==============================================================================
set -euo pipefail

# ==============================================================================
# Pipeline Configuration Area
# ==============================================================================
PIPELINE_BACKUP=(
    step_backup_init
    step_backup_apt
    step_backup_snap
    step_backup_dconf
    step_backup_dotfiles
    step_backup_env
    step_backup_metadata
    step_backup_summary
)

PIPELINE_RESTORE=(
    step_restore_init
    step_restore_apt
    step_restore_snap
    step_restore_dotfiles
    step_restore_dconf
    step_restore_systemd
    step_restore_summary
)

# ==============================================================================
# Global Flags & State Variables
# ==============================================================================
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEFAULT_BACKUP_NAME="ubuntu-backup_${TIMESTAMP}"
HOME_DIR="${HOME}"
CURRENT_STEP=""

DEST_BASE="."
BACKUP_DIR=""

DOTFILES=(
    ".bashrc"
    ".bash_profile"
    ".bash_aliases"
    ".profile"
    ".zshrc"
    ".zprofile"
    ".zsh_history"
    ".gitconfig"
    ".gitignore_global"
    ".ssh/config"
    ".ssh/known_hosts"
    ".npmrc"
    ".yarnrc"
    ".cargo/config.toml"
    ".config/nvim"
    ".config/vim"
    ".vimrc"
    ".tmux.conf"
    ".config/htop"
    ".config/alacritty"
    ".config/kitty"
    ".config/fish"
    ".config/starship.toml"
    ".config/gtk-3.0"
    ".config/gtk-4.0"
    ".local/share/fonts"
    ".config/autostart"
)

# ==============================================================================
# Colored Output Helpers
# ==============================================================================
info()    { echo -e "\e[32m>>> $* \e[0m"; }
warning() { echo -e "\e[33m!!! $* \e[0m"; }
error()   { echo -e "\e[31m[ERROR] $* \e[0m" >&2; }
header()  { echo -e "\n\e[1m── $* ──\e[0m"; }

# ==============================================================================
# Signal & Error Handling
# ==============================================================================
on_error() {
    local exit_code=$?
    local line=$1
    echo -e "\e[31m\n[FAILED] Script exited unexpectedly at line ${line} (exit code: ${exit_code}).\e[0m"
    echo -e "\e[33mPlease review the output above and resolve the issue manually.\e[0m"
    exit $exit_code
}
trap 'on_error $LINENO' ERR

handle_sigint() {
    echo ""
    if [[ -n "${CURRENT_STEP}" ]]; then
        warning "Interrupted during step: ${CURRENT_STEP}"
        read -rp "Step not complete. Exit anyway? [y/N] " choice || true
        if [[ "${choice}" =~ ^[Yy]$ ]]; then
            error "Aborted by user."
            exit 130
        else
            info "Resuming..."
            trap handle_sigint INT
        fi
    else
        warning "Interrupted. Exiting."
        exit 130
    fi
}
trap handle_sigint INT

graceful_exit() {
    local code="${1:-0}"
    CURRENT_STEP=""
    trap - INT
    exit "${code}"
}

# ==============================================================================
# Helper Checks & Usage
# ==============================================================================
check_environment() {
    if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -d "/run/user/$(id -u)" ]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
    fi

    if [[ "${EUID}" -eq 0 ]]; then
        warning "Running this script directly with sudo/root changes \$HOME to /root."
        warning "This may restore dotfiles to /root and fail to load GNOME dconf settings."
        read -rp "Are you sure you want to continue as root? [y/N] " root_choice || true
        if [[ ! "${root_choice}" =~ ^[Yy]$ ]]; then
            error "Aborted. Please run as normal user (it will prompt for sudo when needed)."
            exit 1
        fi
    fi
}

usage() {
    local script
    script="$(basename "$0")"
    echo -e "\e[1mUsage:\e[0m"
    echo "  ${script} backup  [output-dir]   # Backup to specified directory (default: current dir)"
    echo "  ${script} restore <backup-dir>   # Restore from backup directory"
    echo "  ${script} --help                 # Show this help message"
    [[ "${1:-}" == "err" ]] && graceful_exit 1 || graceful_exit 0
}

# ==============================================================================
# Atomic Step Functions — Backup
# ==============================================================================
step_backup_init() {
    if [[ ! -d "${DEST_BASE}" ]]; then
        error "Output directory does not exist: ${DEST_BASE}"
        graceful_exit 1
    fi
    BACKUP_DIR="${DEST_BASE}/${DEFAULT_BACKUP_NAME}"
    header "Starting Backup"
    info "Backup destination: ${BACKUP_DIR}"
    mkdir -p "${BACKUP_DIR}"
}

step_backup_apt() {
    header "APT Package List & Sources"
    local apt_dir="${BACKUP_DIR}/apt"
    mkdir -p "${apt_dir}"

    comm -23 \
        <(apt-mark showmanual | sort) \
        <(gzip -dc /var/log/installer/initial-status.gz 2>/dev/null \
            | grep '^Package:' | awk '{print $2}' | sort \
          || dpkg --get-selections | awk '/\tinstall/{print $1}' \
            | grep -E '^(ubuntu-|linux-)' | sort) \
        > "${apt_dir}/manual-packages.txt" 2>/dev/null || true

    if [[ ! -s "${apt_dir}/manual-packages.txt" ]]; then
        apt-mark showmanual | sort > "${apt_dir}/manual-packages.txt"
    fi

    local pkg_count
    pkg_count=$(wc -l < "${apt_dir}/manual-packages.txt")
    info "Recorded ${pkg_count} apt packages"

    if [[ -d "/etc/apt/sources.list.d" ]]; then
        mkdir -p "${apt_dir}/sources.list.d"
        cp -a /etc/apt/sources.list.d/. "${apt_dir}/sources.list.d/" 2>/dev/null || true
    fi
    if [[ -d "/etc/apt/keyrings" ]]; then
        mkdir -p "${apt_dir}/keyrings"
        cp -a /etc/apt/keyrings/. "${apt_dir}/keyrings/" 2>/dev/null || true
    fi
    if [[ -d "/etc/apt/trusted.gpg.d" ]]; then
        mkdir -p "${apt_dir}/trusted.gpg.d"
        cp -a /etc/apt/trusted.gpg.d/. "${apt_dir}/trusted.gpg.d/" 2>/dev/null || true
    fi
    info "Third-party APT sources and GPG keyrings backed up"
}

step_backup_snap() {
    header "Snap Package List"
    local snap_dir="${BACKUP_DIR}/snap"
    mkdir -p "${snap_dir}"

    if command -v snap &>/dev/null; then
        snap list --unicode=never 2>/dev/null \
            | awk 'NR>1 && $1!~/^(core|snapd|bare|gtk-common-themes|gnome-[0-9])/{print $1}' \
            > "${snap_dir}/snap-list.txt" || true

        snap list --unicode=never 2>/dev/null \
            | awk 'NR>1 && $NF ~ /classic/ && $1!~/^(core|snapd|bare)/{print $1}' \
            > "${snap_dir}/snap-classic.txt" || true

        local snap_count
        snap_count=$(wc -l < "${snap_dir}/snap-list.txt")
        info "Recorded ${snap_count} snap packages"
    else
        warning "snap not installed, skipping"
    fi
}

step_backup_dconf() {
    header "GNOME dconf Settings"
    local gnome_dir="${BACKUP_DIR}/gnome"
    mkdir -p "${gnome_dir}"

    if command -v dconf &>/dev/null; then
        dconf dump / > "${gnome_dir}/dconf-full.ini" 2>/dev/null || true
        [[ -s "${gnome_dir}/dconf-full.ini" ]] || rm -f "${gnome_dir}/dconf-full.ini"

        for ns in \
            "/org/gnome/desktop/" \
            "/org/gnome/shell/" \
            "/org/gnome/terminal/" \
            "/org/gtk/settings/"; do
            local fname
            fname=$(echo "${ns}" | tr '/' '_' | sed 's/^_//;s/_$//')
            dconf dump "${ns}" > "${gnome_dir}/${fname}.ini" 2>/dev/null || true
            [[ -s "${gnome_dir}/${fname}.ini" ]] || rm -f "${gnome_dir}/${fname}.ini"
        done
        info "dconf settings exported"
    else
        warning "dconf not installed, skipping GNOME settings"
    fi
}

step_backup_dotfiles() {
    header "Dotfiles"
    local dots_dir="${BACKUP_DIR}/dotfiles"
    mkdir -p "${dots_dir}"

    local copied=0 skipped=0
    for item in "${DOTFILES[@]}"; do
        local src="${HOME_DIR}/${item}"
        if [[ -e "${src}" ]]; then
            local dest_path="${dots_dir}/${item}"
            mkdir -p "$(dirname "${dest_path}")"
            cp -a "${src}" "${dest_path}"
            ((copied++)) || true
        else
            ((skipped++)) || true
        fi
    done
    info "Copied ${copied} items (${skipped} not found, skipped)"
}

step_backup_env() {
    header "System Environment"
    local env_dir="${BACKUP_DIR}/env"
    mkdir -p "${env_dir}"

    cat /etc/os-release > "${env_dir}/os-release.txt" 2>/dev/null || true
    uname -a            > "${env_dir}/uname.txt"      2>/dev/null || true
    locale              > "${env_dir}/locale.txt"     2>/dev/null || true

    local systemd_user_dir="${HOME_DIR}/.config/systemd/user"
    if [[ -d "${systemd_user_dir}" ]]; then
        cp -a "${systemd_user_dir}" "${env_dir}/systemd-user" 2>/dev/null || true
        info "systemd user units backed up"
    fi

    local pip_dir="${BACKUP_DIR}/pip"
    if command -v pip3 &>/dev/null; then
        mkdir -p "${pip_dir}"
        pip3 list --user --format=freeze > "${pip_dir}/pip-user-packages.txt" 2>/dev/null || true
        info "pip user package list recorded"
    fi

    local npm_dir="${BACKUP_DIR}/npm"
    if command -v npm &>/dev/null; then
        mkdir -p "${npm_dir}"
        npm list -g --depth=0 2>/dev/null \
            | tail -n +2 | sed -E 's/^[├└─ ]+//' | sed -E 's/(.+)@([^@]+)$/\1@\2/' \
            > "${npm_dir}/npm-global-packages.txt" || true
        info "npm global package list recorded"
    fi
}

step_backup_metadata() {
    cat > "${BACKUP_DIR}/BACKUP_INFO.txt" <<EOF
Backup time  : $(date)
Hostname     : $(hostname)
User         : $(whoami)
Ubuntu ver   : $(lsb_release -ds 2>/dev/null || echo "N/A")
EOF
}

step_backup_summary() {
    echo ""
    info "Backup complete → ${BACKUP_DIR}"
    echo "  apt/manual-packages.txt     — apt package list"
    echo "  apt/sources.list.d/         — third-party apt repositories"
    echo "  apt/keyrings/               — GPG keyrings for third-party apt repos"
    echo "  snap/snap-list.txt          — snap package list"
    echo "  gnome/dconf-full.ini        — full GNOME settings"
    echo "  dotfiles/                   — home directory configs"
    echo "  pip/pip-user-packages.txt   — pip user package list"
    echo "  npm/npm-global-packages.txt — npm global package list"
    echo "  env/                        — environment info & systemd units"
    echo ""
    warning "SSH private keys are NOT backed up (only config & known_hosts)."
    warning "Back up ~/.ssh/id_* separately and store it somewhere secure."
}

# ==============================================================================
# Atomic Step Functions — Restore
# ==============================================================================
step_restore_init() {
    if [[ ! -d "${BACKUP_DIR}" ]]; then
        error "Backup directory does not exist: ${BACKUP_DIR}"
        graceful_exit 1
    fi
    if [[ ! -f "${BACKUP_DIR}/BACKUP_INFO.txt" ]]; then
        warning "BACKUP_INFO.txt not found — this may not be a valid backup directory."
        read -rp "Continue anyway? [y/N] " check || true
        [[ "${check}" =~ ^[Yy]$ ]] || { info "Aborted."; graceful_exit 0; }
    fi

    header "Starting Restore"
    info "Backup source: ${BACKUP_DIR}"

    if [[ -f "${BACKUP_DIR}/BACKUP_INFO.txt" ]]; then
        echo ""
        cat "${BACKUP_DIR}/BACKUP_INFO.txt"
        echo ""
    fi

    read -rp "Confirm restore from this backup? [y/N] " confirm || true
    [[ "${confirm}" =~ ^[Yy]$ ]] || { info "Aborted."; graceful_exit 0; }
}

step_restore_apt() {
    header "Restoring APT Sources & Packages"
    local apt_src_dir="${BACKUP_DIR}/apt/sources.list.d"
    local apt_key_dir="${BACKUP_DIR}/apt/keyrings"
    local apt_trusted_dir="${BACKUP_DIR}/apt/trusted.gpg.d"

    if [[ -d "${apt_key_dir}" ]]; then
        sudo mkdir -p /etc/apt/keyrings
        sudo cp -a "${apt_key_dir}/." /etc/apt/keyrings/ 2>/dev/null || true
    fi
    if [[ -d "${apt_trusted_dir}" ]]; then
        sudo mkdir -p /etc/apt/trusted.gpg.d
        sudo cp -a "${apt_trusted_dir}/." /etc/apt/trusted.gpg.d/ 2>/dev/null || true
    fi
    if [[ -d "${apt_src_dir}" ]]; then
        sudo mkdir -p /etc/apt/sources.list.d
        sudo cp -a "${apt_src_dir}/." /etc/apt/sources.list.d/ 2>/dev/null || true
        info "Third-party APT sources and keyrings restored"
    fi

    local pkg_list="${BACKUP_DIR}/apt/manual-packages.txt"
    if [[ -f "${pkg_list}" && -s "${pkg_list}" ]]; then
        info "Updating package index..."
        sudo apt-get update -qq
        info "Installing packages (failures will be skipped)..."
        < "${pkg_list}" xargs -r sudo apt-get install -y --ignore-missing 2>&1 \
            | grep -E "^(Inst|Setting up|E:)" || true
        info "apt packages installed"
    else
        warning "apt package list not found or empty, skipping"
    fi
}

step_restore_snap() {
    header "Restoring Snap Packages"
    local snap_list="${BACKUP_DIR}/snap/snap-list.txt"
    local snap_classic="${BACKUP_DIR}/snap/snap-classic.txt"

    if [[ -f "${snap_list}" && -s "${snap_list}" ]] && command -v snap &>/dev/null; then
        declare -A is_classic=()
        if [[ -f "${snap_classic}" ]]; then
            while IFS= read -r cpkg; do
                [[ -n "${cpkg}" ]] && is_classic["${cpkg}"]=1
            done < "${snap_classic}"
        fi

        while IFS= read -r pkg; do
            [[ -z "${pkg}" ]] && continue
            local -a snap_flags=()
            if [[ -n "${is_classic[${pkg}]:-}" ]]; then
                snap_flags+=("--classic")
            fi
            info "Installing snap: ${pkg}${snap_flags[*]:+ ${snap_flags[*]}}"
            sudo snap install "${pkg}" "${snap_flags[@]}" < /dev/null 2>/dev/null \
                || warning "snap install ${pkg} failed, skipping"
        done < "${snap_list}"
        info "snap packages installed"
    else
        warning "snap list not found or snap not installed, skipping"
    fi
}

step_restore_dotfiles() {
    header "Restoring Dotfiles"
    local dots_dir="${BACKUP_DIR}/dotfiles"
    if [[ -d "${dots_dir}" ]]; then
        for item in "${DOTFILES[@]}"; do
            local src="${dots_dir}/${item}"
            local dest="${HOME_DIR}/${item}"

            [[ -e "${src}" ]] || continue

            if [[ -e "${dest}" ]]; then
                cp -a "${dest}" "${dest}.bak_${TIMESTAMP}" 2>/dev/null || true
                warning "Original backed up: ${dest} → ${dest}.bak_${TIMESTAMP}"
                rm -rf "${dest}"
            fi
            mkdir -p "$(dirname "${dest}")"
            cp -a "${src}" "${dest}"
        done
        info "Dotfiles restored"
    else
        warning "dotfiles directory not found, skipping"
    fi
}

step_restore_dconf() {
    header "Restoring GNOME Settings"
    local dconf_full="${BACKUP_DIR}/gnome/dconf-full.ini"
    if [[ -f "${dconf_full}" ]] && command -v dconf &>/dev/null; then
        if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
            dconf load / < "${dconf_full}"
            info "dconf settings restored"
        else
            warning "No active GNOME session detected (DBUS_SESSION_BUS_ADDRESS not set)"
            warning "Run manually after login: dconf load / < ${dconf_full}"
        fi
    else
        warning "dconf backup not found or dconf not installed, skipping"
    fi
}

step_restore_systemd() {
    header "Restoring systemd User Units"
    local systemd_backup="${BACKUP_DIR}/env/systemd-user"
    if [[ -d "${systemd_backup}" ]]; then
        local systemd_dest="${HOME_DIR}/.config/systemd/user"
        mkdir -p "${systemd_dest}"
        cp -a "${systemd_backup}/." "${systemd_dest}/"
        systemctl --user daemon-reload 2>/dev/null || true
        info "systemd user units restored"
    else
        warning "No systemd user units backup found, skipping"
    fi
}

step_restore_summary() {
    echo ""
    echo -e "\e[1mRestore complete. The following require manual action:\e[0m"

    local pip_list="${BACKUP_DIR}/pip/pip-user-packages.txt"
    if [[ -f "${pip_list}" && -s "${pip_list}" ]]; then
        echo -e "  \e[33mpip user packages:\e[0m"
        echo "    pip3 install --user -r ${pip_list}"
    fi

    local npm_list="${BACKUP_DIR}/npm/npm-global-packages.txt"
    if [[ -f "${npm_list}" && -s "${npm_list}" ]]; then
        echo -e "  \e[33mnpm global packages:\e[0m see ${npm_list}, install with npm install -g"
    fi

    echo -e "  \e[33mSSH private keys:\e[0m only config & known_hosts were backed up"
    echo "    chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_*"
    echo ""
    info "All done. A reboot or re-login is recommended to apply all settings."
}

# ==============================================================================
# Pipeline Engine
# ==============================================================================
run_pipeline() {
    local pipeline=("$@")
    info "Executing pipeline with ${#pipeline[@]} steps..."

    for step in "${pipeline[@]}"; do
        if declare -f "$step" >/dev/null; then
            CURRENT_STEP="${step#step_}"
            "$step"
        else
            error "Pipeline error: step function '$step' is not defined."
        fi
    done
    CURRENT_STEP=""
}

# ==============================================================================
# Entry Point & CLI Dispatcher
# ==============================================================================
check_environment

case "${1:-}" in
    backup)
        DEST_BASE="${2:-.}"
        run_pipeline "${PIPELINE_BACKUP[@]}"
        graceful_exit 0
        ;;
    restore)
        BACKUP_DIR="${2:-}"
        if [[ -z "${BACKUP_DIR}" ]]; then
            error "No backup directory specified."
            usage err
        fi

        info "Restore requires sudo for apt and snap. Authenticating..."
        sudo -v || { error "sudo authentication failed."; exit 1; }

        ( while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done ) 2>/dev/null &
        SUDO_KP_PID=$!
        trap 'kill "${SUDO_KP_PID}" 2>/dev/null || true' EXIT

        run_pipeline "${PIPELINE_RESTORE[@]}"
        graceful_exit 0
        ;;
    -h|--help)
        usage
        ;;
    *)
        error "Unknown command: ${1:-}"
        usage err
        ;;
esac