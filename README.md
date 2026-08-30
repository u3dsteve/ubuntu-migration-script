# Ubuntu GNOME Migration Tool

**Modular backup & restore toolkit for Ubuntu GNOME desktop environments — built for engineers who actually migrate machines for a living.**

---

## One Sentence

> A modular, pipeline-driven backup and restore toolkit for Ubuntu GNOME desktop environments — captures APT packages, Snap packages, dconf settings, dotfiles, systemd user units, and environment state into a portable, restorable snapshot.

---

## Why This Exists

If you've ever migrated a Linux workstation and spent three days remembering what packages you installed, which PPAs you added, and where that one custom GNOME shortcut went — this is for you.

It doesn't do everything. But it does the things that actually take time to re-create.

---

## What It Backs Up

| Category | What's Captured |
| :--- | :--- |
| **APT** | Manual packages, sources.list.d, keyrings, trusted GPG |
| **Snap** | Installed snap packages (with classic flag preserved) |
| **GNOME/dconf** | Full shell, desktop, and window manager settings |
| **Dotfiles** | Bash, Zsh, Git, SSH config, Neovim, tmux, Alacritty, Kitty, GTK, fonts, autostart |
| **Systemd** | User unit files |
| **Environment** | OS release, kernel, locale, pip user packages, npm global packages |
| **GNOME Extensions** | Shell extensions (optional module) |
| **GTK Config** | GTK-3.0 and GTK-4.0 settings (optional module) |

---

## Quick Start

### Full System Migration (Main Script)

```bash
# Backup
./ubuntu-gnome-migration.sh backup ./my-backup-dir

# Restore
./ubuntu-gnome-migration.sh restore ./my-backup-dir
```

### GNOME-Only Config (Lightweight Script)

```bash
# Backup GNOME settings only
./ubuntu-gnome-config-backup-and-restore.sh --backup

# Restore GNOME settings only
./ubuntu-gnome-config-backup-and-restore.sh --restore

# Force non-interactive mode
./ubuntu-gnome-config-backup-and-restore.sh --restore --force
```

---

## Installation

No installation required. Just clone and run.

```bash
git clone https://github.com/yourusername/ubuntu-gnome-migration-tool
cd ubuntu-gnome-migration-tool
chmod +x *.sh
```

### Dependencies

**Required:**
- Bash 4+
- `dconf-cli` (for GNOME settings backup/restore)

**Optional but recommended:**
- `rsync` (for faster directory syncing)
- `snap` (if you use Snap packages)
- `sudo` (for APT/Snap restore, automatically prompted)

```bash
sudo apt install dconf-cli rsync
```

---

## Usage Guide

### Main Migration Script (`ubuntu-gnome-migration.sh`)

```bash
./ubuntu-gnome-migration.sh backup [output-dir]   # Backup to specified directory
./ubuntu-gnome-migration.sh restore <backup-dir>  # Restore from backup directory
./ubuntu-gnome-migration.sh --help                # Show help
```

**Backup output structure:**

```
ubuntu-backup_20240831_120000/
├── apt/
│   ├── manual-packages.txt
│   ├── sources.list.d/
│   ├── keyrings/
│   └── trusted.gpg.d/
├── snap/
│   ├── snap-list.txt
│   └── snap-classic.txt
├── gnome/
│   ├── dconf-full.ini
│   ├── shell.ini
│   ├── desktop.ini
│   └── wm.ini
├── dotfiles/
│   ├── .bashrc
│   ├── .gitconfig
│   ├── .ssh/config
│   └── ... (full dotfile tree)
├── env/
│   ├── os-release.txt
│   ├── uname.txt
│   ├── locale.txt
│   └── systemd-user/
├── pip/
│   └── pip-user-packages.txt
├── npm/
│   └── npm-global-packages.txt
└── BACKUP_INFO.txt
```

### GNOME-Only Script (`ubuntu-gnome-config-backup-and-restore.sh`)

```bash
# Interactive mode
./ubuntu-gnome-config-backup-and-restore.sh

# Non-interactive backup
./ubuntu-gnome-config-backup-and-restore.sh --backup --force

# Non-interactive restore
./ubuntu-gnome-config-backup-and-restore.sh --restore --force
```

**GNOME backup structure:**

```
gnome-config/
├── dconf/
│   ├── shell.ini
│   ├── desktop.ini
│   └── wm.ini
└── files/
    ├── extensions/       # GNOME Shell extensions
    ├── gtk-3.0/          # GTK3 configs
    └── gtk-4.0/          # GTK4 configs
```

---

## Architecture

Both scripts use a **modular pipeline engine** with atomic step execution:

```bash
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
```

Each step is an independent function. Steps can be reordered, skipped, or extended without breaking the pipeline. This makes the script:

- **Testable** — each step runs independently
- **Extensible** — add new steps without touching existing ones
- **Debuggable** — if a step fails, error handling shows exactly which step and line failed

---

## Safety Features

| Feature | How It Works |
| :--- | :--- |
| **Non-root by default** | The scripts warn if run as root (which changes `$HOME` to `/root`) and require confirmation |
| **Interactive confirmation** | Restore operations prompt for confirmation before overwriting |
| **Signal handling** | `SIGINT` allows graceful exit mid-step with recovery instructions |
| **Backup preservation** | Existing dotfiles are backed up as `*.bak_TIMESTAMP` before overwrite |
| **Atomic steps** | Each step is independent; failure in one doesn't break others |
| **Graceful degradation** | Missing files or commands produce warnings, not fatal errors |
| **sudo session keepalive** | Restore keeps `sudo` alive for the duration of APT/Snap installation |
| **Error trace** | On error, scripts print the exact line number and exit code |

---

## What's NOT Backed Up (By Design)

- **SSH private keys** (`~/.ssh/id_*`) — intentionally excluded for security reasons. Back these up separately and securely.
- **Large media files** — dotfiles only, not `~/Downloads`, `~/Documents`, `~/Videos`, etc.
- **Application data** — only configuration, not user data (browser profiles, mail caches, etc.)
- **System-wide files** — `/etc/` modifications are not captured (use a separate system backup strategy)

---

## Use Cases

1. **Machine migration** — moving from one Ubuntu machine to another
2. **Clean install recovery** — reinstall Ubuntu and restore your exact environment
3. **Team onboarding** — standardize developer environments across a team
4. **Configuration backup** — before experimenting with major desktop changes
5. **Disaster recovery** — if your system breaks, get back to a known-good configuration

---

## Example: Full Migration Workflow

**On the old machine:**

```bash
./ubuntu-gnome-migration.sh backup /media/usb/
```

This creates `/media/usb/ubuntu-backup_20240831_120000/`.

**On the new machine (fresh Ubuntu install):**

```bash
./ubuntu-gnome-migration.sh restore /media/usb/ubuntu-backup_20240831_120000/
```

Follow the on-screen prompts. After restore, log out and back in to apply all settings.

---

## Advanced Usage: Adding Custom Steps

To add your own backup/restore steps:

```bash
# Define a new step
step_backup_custom() {
    mkdir -p "${BACKUP_DIR}/custom"
    cp -a "${HOME}/my-config" "${BACKUP_DIR}/custom/"
}

# Add to pipeline
PIPELINE_BACKUP+=("step_backup_custom")
```

No need to touch existing code.

---

## License

MIT — use it, fork it, send PRs, or just steal the ideas. No attribution required, though appreciated.

---

## Contributing

Issue reports and pull requests are welcome. The codebase is intentionally simple — no frameworks, no dependencies beyond standard Linux utilities. If you find a bug or have an idea for a new step, open an issue or submit a PR.

---

## Why Open Source?

These scripts were written out of real pain — migrating machines, rebuilding environments, and losing configuration. They've been battle-tested through dozens of migrations. We're open-sourcing them because we believe the tools that make our lives easier should be available to everyone.

If you've ever spent three days re-creating your workstation from scratch, these scripts are for you.

---

## Topics

```
ubuntu gnome backup restore dotfiles dconf apt snap systemd migration desktop-configuration bash
```

---

*Built by engineers who migrate machines. Shared for everyone who does the same.*
