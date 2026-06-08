#!/bin/zsh
# modules/strip.sh — Strip embedded subtitle tracks from MKV files.
#
# Respects BACKUP_ENABLED the same way as the merge engine:
#   true  → move originals to BACKUP_DIR/videos/, output to vid_dir
#   false → write to .tmp first, then atomically overwrite original
#
# Entry point: menu_strip()

strip_embedded_subs() {
    local vid_dir="$1"
    setopt local_options NULL_GLOB

    local -a mkv_files=("$vid_dir"/*.mkv)
    if (( ${#mkv_files} == 0 )); then
        log_error "No MKV files found in: $vid_dir"
        return 1
    fi

    log_info "Stripping embedded subtitles from ${#mkv_files} file(s) in: $vid_dir"

    # Collect basenames before any file movement
    local -a bases=()
    for vid in "${mkv_files[@]}"; do
        bases+=("$(basename "${vid%.*}")")
    done

    local success=0 failed=0

    # ── BACKUP=TRUE path ──────────────────────────────────────
    if [[ "$BACKUP_ENABLED" == "true" ]]; then

        setup_backup_workspace "$vid_dir" || return 1
        local ws_vid="$BACKUP_DIR/videos"

        # Move originals to backup before processing
        for base in "${bases[@]}"; do
            mv -- "$vid_dir/$base.mkv" "$ws_vid/$base.mkv" || {
                log_error "Failed to move to backup: $base.mkv"
                return 1
            }
        done
        log_step "Moved ${#bases} file(s) → $ws_vid"

        # Strip from backup, write clean version to vid_dir
        for base in "${bases[@]}"; do
            log_step "Stripping: $base.mkv"
            if run_mkvmerge -o "$vid_dir/$base.mkv" \
                             --no-subtitles "$ws_vid/$base.mkv"; then
                (( success++ ))
            else
                # Restore from backup on failure
                cp -- "$ws_vid/$base.mkv" "$vid_dir/$base.mkv"
                log_warn "Restored original: $base.mkv"
                (( failed++ ))
            fi
        done

        log_success "Done — Stripped: $success  |  Failed: $failed"
        notify_info "Strip complete" "Stripped: $success | Failed: $failed"
        log_info "Originals backed up: $BACKUP_DIR"

    # ── BACKUP=FALSE path ─────────────────────────────────────
    else

        for base in "${bases[@]}"; do
            local src="$vid_dir/$base.mkv"
            local tmp="$vid_dir/$base.mkv.tmp"

            log_step "Stripping: $base.mkv"
            if run_mkvmerge -o "$tmp" --no-subtitles "$src"; then
                mv -f -- "$tmp" "$src"   # atomically overwrite original
                (( success++ ))
            else
                rm -f -- "$tmp"          # original is untouched
                (( failed++ ))
            fi
        done

        log_success "Done — Stripped: $success  |  Failed: $failed"
        notify_info "Strip complete" "Stripped: $success | Failed: $failed"
    fi
}

menu_strip() {
    log_info "Select the directory containing MKV files to strip:"
    local vid_dir
    vid_dir=$(pick_dir ".") || { log_warn "Cancelled."; return }
    [[ -z "$vid_dir" ]] && { log_warn "Cancelled."; return }
    strip_embedded_subs "$vid_dir"
}
