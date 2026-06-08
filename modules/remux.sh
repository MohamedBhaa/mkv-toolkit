#!/bin/zsh
# modules/remux.sh — [PLACEHOLDER] Remux / container conversion.
#
# Planned feature: re-wrap video streams between containers
# (MKV ↔ MP4 ↔ AVI) without re-encoding, preserving all tracks.
#
# Intended tools:
#   mkvmerge  → MKV output (already a dependency)
#   ffmpeg    → MP4/AVI output (optional dependency)
#
# To implement this module:
#   1. Fill in remux_files() below with your logic.
#   2. The menu entry in mkv-toolkit.sh will pick it up automatically.
#   3. No changes to the runner or other modules are needed.
#
# Suggested function signature:
#   remux_files <input_dir> <output_format>
#   where output_format ∈ { mkv mp4 avi }

remux_files() {
    local vid_dir="$1"
    local output_fmt="${2:-mkv}"
    log_warn "Remux module is not yet implemented."
    log_info  "Planned: convert files in '$vid_dir' to .$output_fmt"
    notify_warn "MKV Toolkit" "Remux feature coming soon."
}

menu_remux() {
    print ""
    log_warn "[Remux / Convert] is a placeholder — not yet implemented."
    log_info  "Planned: re-wrap MKV/MP4/AVI without re-encoding."
    print ""
    read -r "?  Press Enter to return to the menu..."
}
