#!/bin/zsh
# modules/metadata.sh — [PLACEHOLDER] MKV metadata editor.
#
# Planned feature: edit MKV container properties without remuxing,
# using mkvpropedit (part of MKVToolNix, install: sudo pacman -S mkvtoolnix-cli).
#
# Planned operations:
#   - Set/clear container title
#   - Set track names and language tags on audio/video/subtitle tracks
#   - Add/remove cover art attachments
#   - Batch-apply tags across an entire season directory
#
# To implement this module:
#   1. Fill in edit_metadata() below.
#   2. The menu entry in mkv-toolkit.sh picks it up automatically.
#   3. No changes to the runner or other modules are needed.
#
# Suggested function signature:
#   edit_metadata <mkv_file> [--title "..."] [--track-lang 0 ara] ...

edit_metadata() {
    local mkv_file="$1"
    if ! command -v mkvpropedit &>/dev/null; then
        log_error "mkvpropedit not found. Install: sudo pacman -S mkvtoolnix-cli"
        return 1
    fi
    log_warn "Metadata module is not yet implemented."
    log_info  "Planned: edit tags/tracks in '$mkv_file' via mkvpropedit."
    notify_warn "MKV Toolkit" "Metadata editor coming soon."
}

menu_metadata() {
    print ""
    log_warn "[Edit MKV Metadata] is a placeholder — not yet implemented."
    log_info  "Planned: set titles, language tags, and cover art via mkvpropedit."
    print ""
    read -r "?  Press Enter to return to the menu..."
}
