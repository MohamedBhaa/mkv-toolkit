#!/bin/zsh
# modules/subtitles.sh — Subtitle operations.
#
# Provides:
#   rename_subtitles   : rename sub files to match MKV names (by count or fzf)
#   extract_zip_subs   : extract a .zip of subtitles to a temp dir
#   _do_merge          : unified internal merge engine (handles backup logic)
#   merge_auto         : public: auto-match merge, picks source via fzf
#   merge_manual       : public: manually pair one video + one subtitle
#   menu_subtitles     : fzf submenu entry point (called by main runner)


# ════════════════════════════════════════════════════════════
#  SUBTITLE RENAMING
# ════════════════════════════════════════════════════════════

# Renames subtitle files in sub_dir to match MKV names in vid_dir.
#
# Strategy:
#   Equal counts  → sort both lists alphabetically, pair by position
#   Unequal counts → fzf manual pairing per video file
#
# Preserves the .ar. language tag in the new filename if present
# in the original subtitle filename.
rename_subtitles() {
    local vid_dir="${1:-.}"
    local sub_dir="${2:-.}"
    setopt local_options NULL_GLOB

    # Collect MKV files
    local -a mkv_files=("$vid_dir"/*.mkv)
    if (( ${#mkv_files} == 0 )); then
        log_error "No MKV files found in: $vid_dir"
        return 1
    fi

    # Collect subtitle files (deduplicated via find)
    local -a sub_files
    sub_files=("${(@f)$(
        find "$sub_dir" -maxdepth 1 \( -name "*.ass" -o -name "*.srt" \) \
            -type f 2>/dev/null | sort
    )}")

    if (( ${#sub_files} == 0 )); then
        log_error "No subtitle files found in: $sub_dir"
        return 1
    fi

    log_info "Found ${#mkv_files} MKV(s) and ${#sub_files} subtitle(s)."

    if (( ${#mkv_files} == ${#sub_files} )); then
        # ── Auto-pair by sorted position ─────────────────────
        log_info "Counts match — renaming by sorted position."
        for (( i = 1; i <= ${#mkv_files}; i++ )); do
            local vid="${mkv_files[$i]}"
            local sub="${sub_files[$i]}"
            local vid_base
            vid_base=$(basename "${vid%.*}")
            local sub_base
            sub_base=$(basename "$sub")

            # Detect language tag and extension
            local new_name
            if   [[ "$sub_base" == *.ar.ass ]]; then new_name="${vid_base}.ar.ass"
            elif [[ "$sub_base" == *.ar.srt ]]; then new_name="${vid_base}.ar.srt"
            elif [[ "$sub_base" == *.ass     ]]; then new_name="${vid_base}.ass"
            else                                      new_name="${vid_base}.srt"
            fi

            local dest="$sub_dir/$new_name"
            if [[ "$sub" == "$dest" ]]; then
                log_info "Already named correctly: $sub_base"
                continue
            fi
            mv -- "$sub" "$dest"
            log_step "$sub_base  →  $new_name"
        done
        log_success "Renaming complete."

    else
        # ── Manual fzf pairing ────────────────────────────────
        log_warn "Count mismatch (${#mkv_files} MKV vs ${#sub_files} sub)."
        log_info "Switching to manual fzf pairing. Press Esc to skip a file."

        local -a remaining_subs=("${sub_files[@]}")

        for vid in "${mkv_files[@]}"; do
            local vid_base
            vid_base=$(basename "${vid%.*}")

            local sub
            sub=$(printf '%s\n' "${remaining_subs[@]}" | \
                fzf "${FZF_OPTS[@]}" \
                    --prompt="Subtitle for ${vid_base} ❯ " \
                    --header="Pair a subtitle with: $(basename $vid)" \
                    --header-first \
                    --preview='head -30 {}')

            if [[ -z "$sub" ]]; then
                log_warn "Skipped: $(basename $vid)"
                continue
            fi

            local sub_base
            sub_base=$(basename "$sub")
            local new_name
            if   [[ "$sub_base" == *.ar.ass ]]; then new_name="${vid_base}.ar.ass"
            elif [[ "$sub_base" == *.ar.srt ]]; then new_name="${vid_base}.ar.srt"
            elif [[ "$sub_base" == *.ass     ]]; then new_name="${vid_base}.ass"
            else                                      new_name="${vid_base}.srt"
            fi

            local dest="$sub_dir/$new_name"
            mv -- "$sub" "$dest"
            log_step "$sub_base  →  $new_name"

            # Remove the used sub from the remaining list
            remaining_subs=("${remaining_subs[@]:#$sub}")
        done
        log_success "Manual pairing complete."
    fi
}


# ════════════════════════════════════════════════════════════
#  ZIP EXTRACTION
# ════════════════════════════════════════════════════════════

# Extracts a .zip file into a fresh temp directory.
# Sets $REPLY to the extraction path on success.
# The caller is responsible for cleaning up $REPLY when done.
extract_zip_subs() {
    local zip_file="$1"

    if ! command -v unzip &>/dev/null; then
        log_error "unzip not installed. Run: sudo pacman -S unzip"
        return 1
    fi

    local extract_dir
    extract_dir=$(mktemp -d "${TMPDIR:-/tmp}/mkv-subs.XXXXXX") || {
        log_error "mktemp -d failed."
        return 1
    }

    log_info "Extracting: $(basename "$zip_file")  →  $extract_dir"
    if ! unzip -q "$zip_file" -d "$extract_dir"; then
        log_error "Extraction failed for: $(basename "$zip_file")"
        rm -rf "$extract_dir"
        return 1
    fi

    local count
    count=$(find "$extract_dir" \( -name "*.ass" -o -name "*.srt" \) | wc -l)
    log_success "Extracted $count subtitle file(s) from ZIP."
    REPLY="$extract_dir"
}


# ════════════════════════════════════════════════════════════
#  MERGE ENGINE
# ════════════════════════════════════════════════════════════
#
# _do_merge handles all merge cases with two code paths:
#
#   BACKUP_ENABLED=true
#     1. Collect pairs (video→subtitle) before touching any file.
#     2. Create $BACKUP_DIR/videos/ and $BACKUP_DIR/subs/.
#     3. Move videos from vid_dir → backup/videos/.
#        Move subs (if collocated) or copy subs (if cross-dir) → backup/subs/.
#     4. Merge: backup/videos/base.mkv + backup/subs/sub → vid_dir/base.mkv
#     5. On failure: restore original from backup.
#
#   BACKUP_ENABLED=false
#     1. Collect pairs.
#     2. Merge in-place: vid_dir/base.mkv → vid_dir/base.mkv.tmp
#     3. On success: overwrite original with .tmp (mv -f).
#     4. On failure: delete .tmp, original survives untouched.

_do_merge() {
    local vid_dir="$1"
    local sub_dir="$2"
    setopt local_options NULL_GLOB

    # Detect if video and subtitle directories are the same location
    local resolved_vid resolved_sub
    resolved_vid=$(realpath "$vid_dir")
    resolved_sub=$(realpath "$sub_dir")
    local collocated=false
    [[ "$resolved_vid" == "$resolved_sub" ]] && collocated=true

    # ── Collect pairs BEFORE any file operations ─────────────
    local -a mkv_files=("$vid_dir"/*.mkv)
    if (( ${#mkv_files} == 0 )); then
        log_error "No MKV files found in: $vid_dir"
        return 1
    fi

    local -a vid_bases=()
    local -a sub_paths=()
    for vid in "${mkv_files[@]}"; do
        local base
        base=$(basename "${vid%.*}")
        find_sub "$sub_dir" "$base"
        if [[ -n "$REPLY" ]]; then
            vid_bases+=("$base")
            sub_paths+=("$REPLY")
        else
            log_warn "No subtitle match for: $base"
        fi
    done

    if (( ${#vid_bases} == 0 )); then
        log_error "No matched video/subtitle pairs found. Aborting."
        return 1
    fi

    log_info "Matched ${#vid_bases} pair(s). Starting merge..."

    # ── BACKUP=TRUE path ──────────────────────────────────────
    if [[ "$BACKUP_ENABLED" == "true" ]]; then

        setup_backup_workspace "$vid_dir" || return 1
        local ws_vid="$BACKUP_DIR/videos"
        local ws_sub="$BACKUP_DIR/subs"

        # Move videos into backup
        for base in "${vid_bases[@]}"; do
            mv -- "$vid_dir/$base.mkv" "$ws_vid/$base.mkv" || {
                log_error "Failed to move: $base.mkv → backup"
                return 1
            }
        done
        log_step "Moved ${#vid_bases} video(s) → $ws_vid"

        # Move subs if collocated, copy if cross-directory
        for sub in "${sub_paths[@]}"; do
            if $collocated; then
                mv -- "$sub" "$ws_sub/"
            else
                cp -- "$sub" "$ws_sub/"
            fi
        done
        local sub_action
        $collocated && sub_action="Moved" || sub_action="Copied"
        log_step "$sub_action ${#sub_paths} subtitle(s) → $ws_sub"

        # Merge
        local success=0 failed=0
        for (( i = 1; i <= ${#vid_bases}; i++ )); do
            local base="${vid_bases[$i]}"
            local sub_name
            sub_name=$(basename "${sub_paths[$i]}")
            local src_vid="$ws_vid/$base.mkv"
            local src_sub="$ws_sub/$sub_name"
            local out="$vid_dir/$base.mkv"

            log_step "$base.mkv  +  $sub_name"
            build_sub_args "$src_sub"
            if run_mkvmerge -o "$out" "$src_vid" "${SUB_ARGS[@]}"; then
                (( success++ ))
            else
                # Restore original from backup on failure
                cp -- "$src_vid" "$out" && log_warn "Restored original: $base.mkv"
                (( failed++ ))
            fi
        done

        log_success "Done — Merged: $success  |  Failed: $failed"
        notify_info "Merge complete" "Merged: $success | Failed: $failed"
        log_info "Originals backed up: $BACKUP_DIR"

    # ── BACKUP=FALSE path ─────────────────────────────────────
    else

        local success=0 failed=0
        for (( i = 1; i <= ${#vid_bases}; i++ )); do
            local base="${vid_bases[$i]}"
            local src_vid="$vid_dir/$base.mkv"
            local src_sub="${sub_paths[$i]}"
            local tmp="$vid_dir/$base.mkv.tmp"

            log_step "$base.mkv  +  $(basename "$src_sub")"
            build_sub_args "$src_sub"

            if run_mkvmerge -o "$tmp" "$src_vid" "${SUB_ARGS[@]}"; then
                mv -f -- "$tmp" "$src_vid"   # atomically overwrite original
                (( success++ ))
            else
                rm -f -- "$tmp"              # original is untouched
                (( failed++ ))
            fi
        done

        log_success "Done — Merged: $success  |  Failed: $failed"
        notify_info "Merge complete" "Merged: $success | Failed: $failed"
    fi
}


# ════════════════════════════════════════════════════════════
#  PUBLIC: AUTO-MATCH MERGE
# ════════════════════════════════════════════════════════════

# User selects video directory and subtitle source (same dir,
# different dir, or a .zip file). Calls _do_merge.
merge_auto() {
    log_info "Select the VIDEO directory:"
    local vid_dir
    vid_dir=$(pick_dir ".") || { log_warn "Cancelled."; return }
    [[ -z "$vid_dir" ]] && { log_warn "Cancelled."; return }

    local sub_source
    sub_source=$(printf '%s\n' \
        "Same directory as videos" \
        "Different directory" \
        "ZIP file" | \
        fzf "${FZF_OPTS[@]}" \
            --prompt="Subtitle source ❯ " \
            --header="Where are the subtitle files?" \
            --header-first \
            --no-info)
    [[ -z "$sub_source" ]] && { log_warn "Cancelled."; return }

    case "$sub_source" in

        "Same directory as videos")
            _do_merge "$vid_dir" "$vid_dir"
            ;;

        "Different directory")
            log_info "Select the SUBTITLE directory:"
            local sub_dir
            sub_dir=$(pick_dir ".") || { log_warn "Cancelled."; return }
            [[ -z "$sub_dir" ]] && { log_warn "Cancelled."; return }
            _do_merge "$vid_dir" "$sub_dir"
            ;;

        "ZIP file")
            log_info "Select the subtitle ZIP file:"
            local zip_file
            zip_file=$(pick_file "ZIP" "." "*.zip")
            [[ -z "$zip_file" ]] && { log_warn "Cancelled."; return }

            local zip_extract_dir
            extract_zip_subs "$zip_file" || return
            zip_extract_dir="$REPLY"

            _do_merge "$vid_dir" "$zip_extract_dir"

            # Always remove the ZIP extraction temp dir when done
            rm -rf "$zip_extract_dir"
            ;;
    esac
}


# ════════════════════════════════════════════════════════════
#  PUBLIC: MANUAL MERGE (single pair via fzf)
# ════════════════════════════════════════════════════════════

# User picks one video and one subtitle file manually via fzf.
# Respects backup settings the same way as auto merge.
merge_manual() {
    log_info "Select the VIDEO file:"
    local video
    video=$(pick_file "Video" "." "*.mkv")
    [[ -z "$video" ]] && { log_warn "Cancelled."; return }

    local sub_source
    sub_source=$(printf '%s\n' \
        "Browse for subtitle file" \
        "ZIP file" | \
        fzf "${FZF_OPTS[@]}" \
            --prompt="Subtitle source ❯ " \
            --header="How to select the subtitle?" \
            --header-first \
            --no-info)
    [[ -z "$sub_source" ]] && { log_warn "Cancelled."; return }

    local sub zip_extract_dir=""
    case "$sub_source" in

        "Browse for subtitle file")
            log_info "Select the SUBTITLE directory:"
            local sub_dir
            sub_dir=$(pick_dir ".") || { log_warn "Cancelled."; return }
            [[ -z "$sub_dir" ]] && { log_warn "Cancelled."; return }
            sub=$(find "$sub_dir" -maxdepth 1 \( -name "*.srt" -o -name "*.ass" \) | \
                fzf "${FZF_OPTS[@]}" \
                    --prompt="Subtitle ❯ " \
                    --preview='head -50 {}')
            ;;

        "ZIP file")
            local zip_file
            zip_file=$(pick_file "ZIP" "." "*.zip")
            [[ -z "$zip_file" ]] && { log_warn "Cancelled."; return }
            extract_zip_subs "$zip_file" || return
            zip_extract_dir="$REPLY"
            sub=$(find "$zip_extract_dir" \( -name "*.srt" -o -name "*.ass" \) | \
                fzf "${FZF_OPTS[@]}" \
                    --prompt="Subtitle ❯ " \
                    --preview='head -50 {}')
            ;;
    esac

    [[ -z "$sub" ]] && {
        [[ -n "$zip_extract_dir" ]] && rm -rf "$zip_extract_dir"
        log_warn "Cancelled."
        return
    }

    local vid_dir="${video:h}"   # zsh: parent directory of $video
    local base="${video:t:r}"    # zsh: filename without extension

    # ── Backup=true path ──────────────────────────────────────
    if [[ "$BACKUP_ENABLED" == "true" ]]; then
        setup_backup_workspace "$vid_dir" || return 1
        local ws_vid="$BACKUP_DIR/videos"
        local ws_sub="$BACKUP_DIR/subs"

        mv -- "$video" "$ws_vid/$base.mkv"
        cp -- "$sub"   "$ws_sub/"
        log_step "Backed up: $base.mkv + $(basename "$sub")"

        local src_sub="$ws_sub/$(basename "$sub")"
        build_sub_args "$src_sub"
        log_step "Merging: $base.mkv + $(basename "$sub")"

        if run_mkvmerge -o "$video" "$ws_vid/$base.mkv" "${SUB_ARGS[@]}"; then
            log_success "Output: $video"
            notify_info "Merge complete" "$(basename "$video")"
        else
            cp -- "$ws_vid/$base.mkv" "$video"
            log_warn "Restored original: $base.mkv"
            notify_error "Merge failed" "$(basename "$video")"
        fi

    # ── Backup=false path ─────────────────────────────────────
    else
        local tmp="$vid_dir/$base.mkv.tmp"
        build_sub_args "$sub"
        log_step "Merging: $base.mkv + $(basename "$sub")"

        if run_mkvmerge -o "$tmp" "$video" "${SUB_ARGS[@]}"; then
            mv -f -- "$tmp" "$video"
            log_success "Output: $video"
            notify_info "Merge complete" "$(basename "$video")"
        else
            rm -f -- "$tmp"
            notify_error "Merge failed" "$(basename "$video")"
        fi
    fi

    [[ -n "$zip_extract_dir" ]] && rm -rf "$zip_extract_dir"
}


# ════════════════════════════════════════════════════════════
#  SUBTITLE SUBMENU
# ════════════════════════════════════════════════════════════

menu_subtitles() {
    local -a items=(
        "Auto-match merge     ▸ pair by filename, pick source"
        "Manual merge         ▸ select one video + one subtitle"
        "Rename subtitles     ▸ match sub names to MKV names"
        "← Back"
    )

    while true; do
        local sel
        sel=$(printf '%s\n' "${items[@]}" | \
            fzf "${FZF_OPTS[@]}" \
                --prompt="  Subtitles ❯ " \
                --header="Subtitle Operations" \
                --header-first \
                --no-info)

        case "$sel" in
            "Auto-match merge"*)  merge_auto ;;
            "Manual merge"*)      merge_manual ;;
            "Rename subtitles"*)
                log_info "Select the VIDEO directory (contains MKVs):"
                local vid_dir
                vid_dir=$(pick_dir ".") || continue
                [[ -z "$vid_dir" ]] && continue

                log_info "Select the SUBTITLE directory (or same as video):"
                local sub_dir
                sub_dir=$(pick_dir ".") || continue
                [[ -z "$sub_dir" ]] && continue

                rename_subtitles "$vid_dir" "$sub_dir"
                ;;
            "← Back"|"") break ;;
        esac
    done
}
