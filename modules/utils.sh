#!/bin/zsh
# modules/utils.sh — Shared utilities used across all modules.
#
# Provides:
#   Logging     : log_info, log_warn, log_error, log_success, log_step
#   Notify      : notify_info, notify_warn, notify_error  (respect SILENT_MODE)
#   Deps        : check_deps
#   fzf helpers : pick_file, pick_files, pick_dir
#   Sub helpers : find_sub, build_sub_args
#   mkvmerge    : run_mkvmerge
#   Backup      : set_backup_dir, setup_backup_workspace, _merge_in_place
#   Cleanup     : purge_backup_dir


# ════════════════════════════════════════════════════════════
#  LOGGING
# ════════════════════════════════════════════════════════════

log_info()    { print -P "  %F{blue}ℹ%f  $*" }
log_success() { print -P "  %F{green}✅%f $*" }
log_warn()    { print -P "  %F{yellow}⚠%f  $*" }
log_error()   { print -P "  %F{red}✗%f  $*" >&2 }
log_step()    { print -P "  %F{cyan}→%f  $*" }


# ════════════════════════════════════════════════════════════
#  DESKTOP NOTIFICATIONS
# ════════════════════════════════════════════════════════════
# Each function also logs to terminal. notify-send is only
# called when SILENT_MODE=false and the binary is available.

_notify() {
    local urgency="$1" icon="$2" title="$3" msg="$4"
    [[ "$SILENT_MODE" == "true" ]] && return
    command -v notify-send &>/dev/null || return
    notify-send \
        --urgency="$urgency" \
        --app-name="MKV Toolkit" \
        --icon="$icon" \
        "$title" "$msg"
}

notify_info()  {
    log_info  "$1 — $2"
    _notify low    video-x-generic  "$1" "$2"
}
notify_warn()  {
    log_warn  "$1 — $2"
    _notify normal dialog-warning   "$1" "$2"
}
notify_error() {
    log_error "$1 — $2"
    _notify critical dialog-error   "$1" "$2"
}


# ════════════════════════════════════════════════════════════
#  DEPENDENCY CHECKER
# ════════════════════════════════════════════════════════════

check_deps() {
    local -a required=(mkvmerge fzf)
    local -a optional=(yazi mediainfo notify-send unzip mkvpropedit ffmpeg)
    local missing=false

    for dep in "${required[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            log_error "Required dependency missing: $dep"
            missing=true
        fi
    done

    $missing && {
        log_error "Install missing required dependencies and restart."
        exit 1
    }

    for dep in "${optional[@]}"; do
        command -v "$dep" &>/dev/null || \
            log_warn "Optional dependency not found: $dep (some features disabled)"
    done
}


# ════════════════════════════════════════════════════════════
#  FZF PICKERS
# ════════════════════════════════════════════════════════════

# Pick a single file matching a glob pattern in a directory.
# Uses mediainfo for MKV preview, head for text files.
# Usage: pick_file <prompt_label> <search_dir> <glob>
# Output: prints selected path to stdout
pick_file() {
    local prompt="${1:-File}"
    local dir="${2:-.}"
    local glob="${3:-*}"
    find "$dir" -maxdepth 1 -name "$glob" -type f 2>/dev/null | sort | \
        fzf "${FZF_OPTS[@]}" \
            --prompt="${prompt} ❯ " \
            --preview='
                case {} in
                    *.mkv|*.mp4|*.avi) mediainfo {} 2>/dev/null ;;
                    *)                  head -50 {} 2>/dev/null ;;
                esac'
}

# Pick multiple files (Space to mark, Enter to confirm).
# Usage: pick_files <prompt_label> <search_dir> <glob>
# Output: newline-separated paths to stdout
pick_files() {
    local prompt="${1:-Files}"
    local dir="${2:-.}"
    local glob="${3:-*}"
    find "$dir" -maxdepth 1 -name "$glob" -type f 2>/dev/null | sort | \
        fzf "${FZF_OPTS[@]}" \
            --multi \
            --prompt="${prompt} ❯ " \
            --header="<Space> to select  |  <Enter> to confirm" \
            --header-first \
            --preview='
                case {} in
                    *.mkv|*.mp4) mediainfo {} 2>/dev/null ;;
                    *)            head -40 {} 2>/dev/null ;;
                esac'
}

# Pick a directory. Uses yazi when available (full navigation),
# falls back to find + fzf otherwise.
# Usage: pick_dir [start_dir]
# Output: prints selected directory path to stdout
pick_dir() {
    local start_dir="${1:-.}"
    if command -v yazi &>/dev/null; then
        local tmp
        tmp=$(mktemp) || { log_error "mktemp failed"; return 1 }
        yazi --chooser-file="$tmp" "$start_dir"
        local sel=$(<"$tmp")
        rm -f "$tmp"
        [[ -z "$sel" ]] && return 1
        # Return the directory: if a file was chosen, return its parent
        [[ -d "$sel" ]] && echo "$sel" || echo "${sel:h}"
    else
        find "$start_dir" -type d -not -path '*/.*' 2>/dev/null | \
            fzf "${FZF_OPTS[@]}" \
                --prompt="Directory ❯ " \
                --preview='ls -lah --color=always {}'
    fi
}


# ════════════════════════════════════════════════════════════
#  SUBTITLE HELPERS
# ════════════════════════════════════════════════════════════

# Find a subtitle for a given base name in a directory.
# Search priority: .ar.ass → .ar.srt → .ass → .srt
# Sets $REPLY to the found path, or "" if nothing found.
find_sub() {
    local dir="$1" base="$2"
    REPLY=""
    if   [[ -f "$dir/$base.ar.ass" ]]; then REPLY="$dir/$base.ar.ass"
    elif [[ -f "$dir/$base.ar.srt" ]]; then REPLY="$dir/$base.ar.srt"
    elif [[ -f "$dir/$base.ass"    ]]; then REPLY="$dir/$base.ass"
    elif [[ -f "$dir/$base.srt"    ]]; then REPLY="$dir/$base.srt"
    fi
}

# Populate the global SUB_ARGS array with properly tagged flags
# for use in the next mkvmerge call.
# Usage: build_sub_args <sub_file_path>
build_sub_args() {
    SUB_ARGS=(
        --language      "0:${SUB_LANG}"
        --track-name    "0:${SUB_LANG_NAME}"
        --default-track 0:yes
        --sub-charset   0:UTF-8
        "$1"
    )
}

# mkvmerge wrapper. Prints a readable error and sends a
# desktop notification if the command fails.
run_mkvmerge() {
    if ! mkvmerge "$@"; then
        notify_error "mkvmerge failed" "See terminal for details."
        return 1
    fi
}


# ════════════════════════════════════════════════════════════
#  BACKUP ENGINE
# ════════════════════════════════════════════════════════════

# Compute and set the global BACKUP_DIR for a given video directory.
# Result: BACKUP_BASE_DIR/<basename_of_vid_dir>
set_backup_dir() {
    local vid_dir="$1"
    local vid_dirname
    vid_dirname=$(basename "$(realpath "$vid_dir")")
    BACKUP_DIR="${BACKUP_BASE_DIR}/${vid_dirname}"
}

# Create the backup directory structure (videos/ and subs/ subdirs).
# Sets global BACKUP_DIR. Returns 1 on failure.
setup_backup_workspace() {
    local vid_dir="$1"
    set_backup_dir "$vid_dir"
    mkdir -p "$BACKUP_DIR/videos" "$BACKUP_DIR/subs" || {
        log_error "Cannot create backup directory: $BACKUP_DIR"
        return 1
    }
    log_info "Backup directory: $BACKUP_DIR"
}

# ════════════════════════════════════════════════════════════
#  PURGE BACKUP
# ════════════════════════════════════════════════════════════

# Interactively delete a backup directory after confirmation.
# If no path is given, prompts the user to pick one under BACKUP_BASE_DIR.
purge_backup_dir() {
    local target="$1"

    if [[ -z "$target" ]]; then
        # Let the user pick which backup to delete
        if [[ ! -d "$BACKUP_BASE_DIR" ]]; then
            log_error "Backup base directory not found: $BACKUP_BASE_DIR"
            return 1
        fi
        target=$(find "$BACKUP_BASE_DIR" -mindepth 1 -maxdepth 1 -type d | \
            fzf "${FZF_OPTS[@]}" \
                --prompt="Purge backup ❯ " \
                --header="Select a backup directory to permanently delete" \
                --header-first \
                --preview='echo "Files: $(find {} -type f | wc -l)"; ls -lah {}')
        [[ -z "$target" ]] && { log_info "Cancelled."; return }
    fi

    if [[ ! -d "$target" ]]; then
        log_error "Directory not found: $target"
        return 1
    fi

    local count
    count=$(find "$target" -type f | wc -l)
    read -r "confirm?  ⚠️  Permanently delete $target ($count files)? [y/N]: "
    if [[ "$confirm" == "y" ]]; then
        rm -rf "$target"
        log_success "Deleted: $target"
        notify_info "Backup purged" "$target"
    else
        log_info "Cancelled."
    fi
}
