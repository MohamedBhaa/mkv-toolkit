#!/bin/zsh
# config.sh — User-editable defaults for MKV Toolkit.
# All values here can be overridden at runtime via the Settings menu.
# This file is sourced first by the runner before any modules load.

# ── Subtitle language ────────────────────────────────────────
SUB_LANG="ara"
SUB_LANG_NAME="Arabic"

# ── Backup settings ──────────────────────────────────────────
# BACKUP_ENABLED: if true, originals are moved to BACKUP_BASE_DIR
#                 before processing and kept there afterwards.
#                 if false, originals are overwritten in-place.
BACKUP_ENABLED=true
BACKUP_BASE_DIR="${HOME}/tmp"

# ── Notification settings ────────────────────────────────────
# SILENT_MODE: if true, no notify-send calls are made.
#              Terminal output is always shown regardless.
SILENT_MODE=false

# ── fzf shared options ───────────────────────────────────────
FZF_OPTS=(
    --height=50%
    --border=rounded
    --cycle
    --layout=reverse
    --color=header:italic
)

# ── Internal runtime state ────────────────────────────────────
# Set dynamically per-operation. Do not edit these manually.
BACKUP_DIR=""    # Computed as: ${BACKUP_BASE_DIR}/<vid_dir_name>
SUB_ARGS=()      # Populated by build_sub_args() before each mkvmerge call
