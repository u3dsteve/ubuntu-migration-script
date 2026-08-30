#!/bin/bash
# ==============================================================================
# GNOME Configuration Backup & Restore Script (Modular Pipeline Edition)
#
# Description:
#   Modular deployment script for GNOME desktop environment backup & restore.
#   Uses atomic step execution with standard pipeline architecture.
# ==============================================================================
set -euo pipefail

# ==============================================================================
# Pipeline Configuration Area
# ==============================================================================
PIPELINE_BACKUP=(
    step_backup_init
    step_backup_dconf_shell
    step_backup_dconf_desktop
    step_backup_dconf_wm
    step_backup_files_extensions
    step_backup_files_gtk3
    step_backup_files_gtk4
)

PIPELINE_RESTORE=(
    step_restore_precheck
    step_restore_dconf_shell
    step_restore_dconf_desktop
    step_restore_dconf_wm
    step_restore_files_extensions
    step_restore_files_gtk3
    step_restore_files_gtk4
)

# ==============================================================================
# Global Flags & Paths
# ==============================================================================
FORCE=false
CURRENT_STEP=""
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/gnome-config"
DCONF_DIR="$BACKUP_DIR/dconf"
FILES_DIR="$BACKUP_DIR/files"

# ==============================================================================
# Helper Functions & Error Handling
# ==============================================================================
info()    { echo -e "\e[32m>>> $* \e[0m"; }
warning() { echo -e "\e[33m!!! $* \e[0m"; }
error()   { echo -e "\e[31m[ERROR] $* \e[0m"; exit 1; }

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
        if [ -t 0 ]; then
            read -rp "Step not confirmed complete. Exit anyway? [y/N] " choice || true
            if [[ "${choice}" =~ ^[Yy]$ ]]; then
                echo -e "\e[31m[ABORTED] Stopped mid '${CURRENT_STEP}'. Re-run to retry that step.\e[0m"
                exit 130
            else
                info "Resuming..."
                trap handle_sigint INT
            fi
        else
            exit 130
        fi
    else
        warning "Interrupted. Exiting."
        exit 130
    fi
}
trap handle_sigint INT

# Sync directories cleanly
sync_dir() {
    local src="$1"
    local dest="$2"
    mkdir -p "$dest"
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --delete "$src/" "$dest/"
    else
        rm -rf "$dest"
        mkdir -p "$dest"
        cp -a "$src/." "$dest/"
    fi
}

# Pre-flight environment check
check_environment() {
    if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -d "/run/user/$(id -u)" ]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
    fi
    command -v dconf >/dev/null 2>&1 || error "dconf not found. Install it with: sudo apt install dconf-cli"
}

# Check root safety
check_root_safety() {
    if [ "$EUID" -eq 0 ]; then
        warning "Running as root. Config paths will be under /root/.config/."
        warning "Do NOT restore this backup to a non-root user — paths will mismatch."
        if [ "$FORCE" = false ]; then
            [ -t 0 ] || error "Non-interactive shell detected. Please run with -f/--force."
            read -rp "Continue anyway? (y/N): " CONFIRM_ROOT || true
            [[ ! "$CONFIRM_ROOT" =~ ^[Yy]$ ]] && error "Aborted."
        fi
    fi
}

# ==============================================================================
# Atomic Step Functions — Backup
# ==============================================================================
step_backup_init() {
    info "Creating backup directory structure at $BACKUP_DIR"
    mkdir -p "$DCONF_DIR" "$FILES_DIR"
}

step_backup_dconf_shell() {
    info "Exporting dconf: /org/gnome/shell/ (includes extensions & dock)"
    dconf dump /org/gnome/shell/ > "$DCONF_DIR/shell.ini"
}

step_backup_dconf_desktop() {
    info "Exporting dconf: /org/gnome/desktop/"
    dconf dump /org/gnome/desktop/ > "$DCONF_DIR/desktop.ini"
}

step_backup_dconf_wm() {
    info "Exporting dconf: /org/gnome/desktop/wm/"
    dconf dump /org/gnome/desktop/wm/ > "$DCONF_DIR/wm.ini"
}

step_backup_files_extensions() {
    if [ -d "$HOME/.local/share/gnome-shell/extensions" ]; then
        info "Copying ~/.local/share/gnome-shell/extensions/"
        sync_dir "$HOME/.local/share/gnome-shell/extensions" "$FILES_DIR/extensions"
    else
        warning "~/.local/share/gnome-shell/extensions not found, skipping."
    fi
}

step_backup_files_gtk3() {
    if [ -d "$HOME/.config/gtk-3.0" ]; then
        info "Copying ~/.config/gtk-3.0/"
        sync_dir "$HOME/.config/gtk-3.0" "$FILES_DIR/gtk-3.0"
    else
        warning "~/.config/gtk-3.0 not found, skipping."
    fi
}

step_backup_files_gtk4() {
    if [ -d "$HOME/.config/gtk-4.0" ]; then
        info "Copying ~/.config/gtk-4.0/"
        sync_dir "$HOME/.config/gtk-4.0" "$FILES_DIR/gtk-4.0"
    else
        warning "~/.config/gtk-4.0 not found, skipping."
    fi
}

# ==============================================================================
# Atomic Step Functions — Restore
# ==============================================================================
step_restore_precheck() {
    [ -d "$BACKUP_DIR" ] || error "No backup found at $BACKUP_DIR. Run backup first."
    [ -d "$DCONF_DIR" ]  || error "dconf backup directory missing: $DCONF_DIR"

    if [ "$FORCE" = false ]; then
        [ -t 0 ] || error "Non-interactive shell detected. Please run with -f/--force."
        warning "This will overwrite your current GNOME settings with the backup."
        read -rp "Continue? (y/N): " CONFIRM || true
        [[ ! "$CONFIRM" =~ ^[Yy]$ ]] && error "Aborted."
    fi
}

step_restore_dconf_shell() {
    if [ -f "$DCONF_DIR/shell.ini" ]; then
        info "Restoring dconf: /org/gnome/shell/"
        dconf reset -f /org/gnome/shell/
        dconf load /org/gnome/shell/ < "$DCONF_DIR/shell.ini"
    else
        warning "shell.ini not found, skipping."
    fi
}

step_restore_dconf_desktop() {
    if [ -f "$DCONF_DIR/desktop.ini" ]; then
        info "Restoring dconf: /org/gnome/desktop/"
        dconf reset -f /org/gnome/desktop/
        dconf load /org/gnome/desktop/ < "$DCONF_DIR/desktop.ini"
    else
        warning "desktop.ini not found, skipping."
    fi
}

step_restore_dconf_wm() {
    if [ -f "$DCONF_DIR/wm.ini" ]; then
        info "Restoring dconf: /org/gnome/desktop/wm/"
        dconf reset -f /org/gnome/desktop/wm/
        dconf load /org/gnome/desktop/wm/ < "$DCONF_DIR/wm.ini"
    else
        warning "wm.ini not found, skipping."
    fi
}

step_restore_files_extensions() {
    if [ -d "$FILES_DIR/extensions" ]; then
        info "Restoring ~/.local/share/gnome-shell/extensions/"
        sync_dir "$FILES_DIR/extensions" "$HOME/.local/share/gnome-shell/extensions"
    else
        warning "extensions backup not found, skipping."
    fi
}

step_restore_files_gtk3() {
    if [ -d "$FILES_DIR/gtk-3.0" ]; then
        info "Restoring ~/.config/gtk-3.0/"
        sync_dir "$FILES_DIR/gtk-3.0" "$HOME/.config/gtk-3.0"
    else
        warning "gtk-3.0 backup not found, skipping."
    fi
}

step_restore_files_gtk4() {
    if [ -d "$FILES_DIR/gtk-4.0" ]; then
        info "Restoring ~/.config/gtk-4.0/"
        sync_dir "$FILES_DIR/gtk-4.0" "$HOME/.config/gtk-4.0"
    else
        warning "gtk-4.0 backup not found, skipping."
    fi
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
# CLI Argument Parsing
# ==============================================================================
ACTION=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--force)
            FORCE=true
            shift
            ;;
        -b|--backup)
            ACTION="backup"
            shift
            ;;
        -r|--restore)
            ACTION="restore"
            shift
            ;;
        *)
            error "Unknown option: $1. Supported flags: -b/--backup, -r/--restore, -f/--force"
            ;;
    esac
done

# ==============================================================================
# Main Orchestrator
# ==============================================================================
check_environment
check_root_safety

if [ -n "$ACTION" ]; then
    case "$ACTION" in
        backup)
            info "Starting backup via CLI"
            run_pipeline "${PIPELINE_BACKUP[@]}"
            info "Backup complete. Files saved to: $BACKUP_DIR"
            exit 0
            ;;
        restore)
            info "Starting restore via CLI"
            run_pipeline "${PIPELINE_RESTORE[@]}"
            info "Restore complete."
            warning "You may need to log out and back in for all changes to take effect."
            exit 0
            ;;
    esac
fi

[ -t 0 ] || error "Non-interactive shell detected. Please specify -b/--backup or -r/--restore with -f/--force."

echo ""
echo "=============================="
echo "  GNOME Config Script"
echo "=============================="
echo "  1) Backup current settings"
echo "  2) Restore from backup"
echo "=============================="
read -rp "Select an option (1/2): " CHOICE || true

case "$CHOICE" in
    1)
        info "Starting backup"
        run_pipeline "${PIPELINE_BACKUP[@]}"
        info "Backup complete. Files saved to: $BACKUP_DIR"
        ;;
    2)
        info "Starting restore"
        run_pipeline "${PIPELINE_RESTORE[@]}"
        info "Restore complete."
        warning "You may need to log out and back in for all changes to take effect."
        ;;
    *)
        error "Invalid option. Please enter 1 or 2."
        ;;
esac