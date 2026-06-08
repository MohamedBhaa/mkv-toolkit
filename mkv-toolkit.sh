#!/bin/zsh
# mkv-toolkit.sh — Main runner script.
#
# Execution order:
#   1. Resolve TOOLKIT_DIR (the directory this script lives in)
#   2. Source config.sh  (defaults and runtime state variables)
#   3. Source modules/utils.sh explicitly (other modules depend on it)
#   4. Auto-source every remaining *.sh in modules/ alphabetically
#   5. Run check_deps (exits early if mkvmerge or fzf are missing)
#   6. Enter the main fzf-driven menu loop
#
# Adding a new feature:
#   • Drop a new .sh file in modules/
#   • Define a menu_<feature>() function inside it
#   • Add one line to MAIN_MENU_ITEMS below
#   • Nothing else changes

setopt NULL_GLOB


# ════════════════════════════════════════════════════════════
#  BOOTSTRAP
# ════════════════════════════════════════════════════════════

# Resolve the absolute path of the directory containing this script.
TOOLKIT_DIR="${0:A:h}"

# Source configuration (must come before modules)
source "$TOOLKIT_DIR/config.sh" || {
    print "✗ Failed to source config.sh — aborting." >&2
    exit 1
}

# Source utils first (all other modules depend on its functions)
source "$TOOLKIT_DIR/modules/utils.sh" || {
    print "✗ Failed to source modules/utils.sh — aborting." >&2
    exit 1
}

# Auto-source all remaining modules in alphabetical order.
# To add a module: drop a .sh file in modules/ — no other change needed.
for _mod in "$TOOLKIT_DIR/modules/"*.sh; do
    [[ "$_mod" == */utils.sh ]] && continue   # already sourced above
    [[ -f "$_mod" ]] || continue
    source "$_mod" || log_warn "Failed to source module: $_mod"
done
unset _mod

# Verify required binaries exist before showing the menu
check_deps


# ════════════════════════════════════════════════════════════
#  SETTINGS MENU
# ════════════════════════════════════════════════════════════
#
# Each setting is shown with its current value. The user picks
# one to change it, then the menu redraws with the updated value.

menu_settings() {
    while true; do
        local -a items=(
            "Language tag        :  ${SUB_LANG} (${SUB_LANG_NAME})"
            "Backup enabled      :  ${BACKUP_ENABLED}"
            "Backup base dir     :  ${BACKUP_BASE_DIR}"
            "Silent mode         :  ${SILENT_MODE}"
            "Purge a backup      :  delete a backup directory"
            "← Back"
        )

        local sel
        sel=$(printf '%s\n' "${items[@]}" | \
            fzf "${FZF_OPTS[@]}" \
                --prompt="  Settings ❯ " \
                --header="Settings  (current values shown)" \
                --header-first \
                --no-info)

        case "$sel" in

            "Language tag"*)
                print ""
                print "  Common ISO 639-2 codes:"
                print "  ara=Arabic  eng=English  jpn=Japanese"
                print "  fre=French  spa=Spanish  ger=German"
                print "  kor=Korean  zho=Chinese  por=Portuguese"
                print ""
                read -r "SUB_LANG?  Language code  [${SUB_LANG}]: "
                read -r "SUB_LANG_NAME?  Display name   [${SUB_LANG_NAME}]: "
                log_success "Language set to: ${SUB_LANG} / ${SUB_LANG_NAME}"
                ;;

            "Backup enabled"*)
                if [[ "$BACKUP_ENABLED" == "true" ]]; then
                    BACKUP_ENABLED=false
                else
                    BACKUP_ENABLED=true
                fi
                log_success "Backup enabled: ${BACKUP_ENABLED}"
                ;;

            "Backup base dir"*)
                print ""
                print "  Current: ${BACKUP_BASE_DIR}"
                print "  Backup directories are created as:"
                print "  <base_dir>/<name_of_video_directory>"
                print ""
                read -r "new_dir?  New base dir [${BACKUP_BASE_DIR}]: "
                if [[ -n "$new_dir" ]]; then
                    # Expand ~ manually since read doesn't do shell expansion
                    BACKUP_BASE_DIR="${new_dir/#\~/$HOME}"
                    log_success "Backup base dir set to: ${BACKUP_BASE_DIR}"
                fi
                ;;

            "Silent mode"*)
                if [[ "$SILENT_MODE" == "true" ]]; then
                    SILENT_MODE=false
                else
                    SILENT_MODE=true
                fi
                log_success "Silent mode: ${SILENT_MODE}"
                ;;

            "Purge a backup"*)
                purge_backup_dir
                ;;

            "← Back"|"") break ;;
        esac
    done
}


# ════════════════════════════════════════════════════════════
#  MAIN MENU
# ════════════════════════════════════════════════════════════
#
# Format: "Display label|function_name"
# The label (left of |) is shown in fzf.
# The function (right of |) is called on selection.
#
# To register a new module in the menu, append one line here.

MAIN_MENU_ITEMS=(
    "  Subtitles   ▸ merge, rename, extract|menu_subtitles"
    "  Strip embedded subtitles|menu_strip"
    "  Remux / Convert  [placeholder]|menu_remux"
    "  Edit MKV metadata  [placeholder]|menu_metadata"
    "⚙  Settings|menu_settings"
    "✕  Exit|_exit_toolkit"
)

_exit_toolkit() {
    print "\n  Goodbye.\n"
    exit 0
}

# Dispatch: find the function mapped to the selected label and call it.
_dispatch() {
    local selection="$1"
    local item fn
    for item in "${MAIN_MENU_ITEMS[@]}"; do
        if [[ "${item%|*}" == "$selection" ]]; then
            fn="${item#*|}"
            break
        fi
    done
    [[ -n "$fn" ]] && "$fn"
}

main_menu() {
    while true; do
        # Build the display list (labels only, no function names)
        local -a labels=()
        local item
        for item in "${MAIN_MENU_ITEMS[@]}"; do
            labels+=("${item%|*}")
        done

        local selection
        selection=$(printf '%s\n' "${labels[@]}" | \
            fzf "${FZF_OPTS[@]}" \
                --prompt="  Toolkit ❯ " \
                --header="MKV Media Toolkit  ·  $(pwd)" \
                --header-first \
                --no-info)

        # Esc / empty = exit
        [[ -z "$selection" ]] && _exit_toolkit

        _dispatch "$selection"
    done
}

main_menu
