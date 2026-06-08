# MKV Media Toolkit

A modular, interactive command-line toolkit for batch processing MKV files.
Built on top of [MKVToolNix](https://mkvtoolnix.download/), [fzf](https://github.com/junegunn/fzf), and [yazi](https://github.com/sxyazi/yazi).

All file and directory selection is driven by `fzf` with live previews. No manual path typing required.

---

## Features

- **Subtitle merging** — auto-match by filename or manually pair files with fzf
- **Subtitle renaming** — rename subtitle files to match MKV names by count or manual fzf pairing
- **ZIP extraction** — select a `.zip` of subtitles and the toolkit extracts it automatically before merging
- **Strip embedded subtitles** — remove all embedded subtitle tracks from a batch of MKV files
- **Language tagging** — all merged tracks are tagged with a configurable ISO 639-2 language code
- **Backup system** — originals are moved to a configurable backup directory before any processing
- **In-place mode** — toggle backup off to overwrite files directly with no copies kept
- **Desktop notifications** — `notify-send` alerts on completion or failure (toggleable)
- **Modular architecture** — add new features by dropping a `.sh` file into `modules/`

---

## Directory Structure

```
mkv-toolkit/
├── mkv-toolkit.sh       # Main runner — sources config + all modules, shows menu
├── config.sh            # User-editable defaults (language, backup path, etc.)
└── modules/
    ├── utils.sh         # Shared: logging, notifications, fzf helpers, backup engine
    ├── subtitles.sh     # Subtitle merge, rename, and ZIP extraction
    ├── strip.sh         # Strip embedded subtitle tracks
    ├── remux.sh         # Placeholder: container conversion (MKV ↔ MP4)
    └── metadata.sh      # Placeholder: MKV tag editing via mkvpropedit
```

---

## Dependencies

### Required

| Tool | Package | Purpose |
|---|---|---|
| `mkvmerge` | `mkvtoolnix-cli` | MKV muxing and subtitle embedding |
| `fzf` | `fzf` | All interactive selection and menus |

### Optional

| Tool | Package | Purpose |
|---|---|---|
| `yazi` | `yazi` | Directory picker (falls back to `find + fzf`) |
| `mediainfo` | `mediainfo` | Live file info in fzf preview pane |
| `notify-send` | `libnotify` | Desktop notifications on completion/failure |
| `unzip` | `unzip` | ZIP subtitle extraction |
| `mkvpropedit` | `mkvtoolnix-cli` | Tag editing (metadata module, not yet implemented) |
| `ffmpeg` | `ffmpeg` | Container conversion (remux module, not yet implemented) |

### Install on Arch Linux

```bash
# Required
sudo pacman -S mkvtoolnix-cli fzf

# Optional (recommended)
sudo pacman -S yazi mediainfo libnotify unzip
```

### Install on Debian / Ubuntu

```bash
sudo apt install mkvtoolnix fzf yazi mediainfo libnotify-bin unzip
```

---

## Setup

```bash
git clone https://github.com/your-username/mkv-toolkit.git
cd mkv-toolkit
chmod +x mkv-toolkit.sh
./mkv-toolkit.sh
```

No installation step required. The toolkit runs from wherever it lives.

---

## Usage

Launch the toolkit from any terminal:

```bash
./mkv-toolkit.sh
```

An `fzf` menu appears. Navigate with arrow keys, confirm with Enter, cancel with Escape.

```
  Subtitles   ▸ merge, rename, extract
  Strip embedded subtitles
  Remux / Convert  [placeholder]
  Edit MKV metadata  [placeholder]
⚙  Settings
✕  Exit
```

### Subtitle Merge

Two modes are available under **Subtitles → Auto-match merge**:

**Same directory** — place subtitle files next to MKV files. The toolkit pairs them by base filename.

```
/videos/
  Show.S01E01.mkv
  Show.S01E02.mkv
  Show.S01E01.ar.ass    ← matched by name
  Show.S01E02.ar.ass
```

**Different directory** — pick the video folder and subtitle folder separately. The toolkit handles moving files into a workspace before merging.

**ZIP file** — select a `.zip` archive of subtitles. Contents are extracted automatically to a temp directory, merged, then cleaned up.

### Subtitle Matching Priority

When looking for a subtitle for a given video, the toolkit checks in this order:

1. `filename.ar.ass`
2. `filename.ar.srt`
3. `filename.ass`
4. `filename.srt`

### Subtitle Renaming

**Subtitles → Rename subtitles** renames subtitle files to match MKV filenames.

- If the count of MKV files and subtitle files is equal, they are paired by sorted alphabetical position.
- If counts differ, fzf opens for each MKV so you can manually pick its subtitle.

The `.ar.` language tag in filenames is detected and preserved in the new name.

### Strip Embedded Subtitles

**Strip embedded subtitles** removes all embedded subtitle tracks from every MKV in a selected directory. The video and audio streams are untouched.

---

## Backup System

The backup system is controlled by two settings in `config.sh` (or via the Settings menu at runtime).

### `BACKUP_ENABLED=true` (default)

Before any processing, original files are **moved** to a backup directory:

```
~/tmp/<name-of-video-directory>/
  videos/    ← original MKV files
  subs/      ← original subtitle files
```

The default base path is `~/tmp`. This is configurable via Settings.

If a merge fails, the original is automatically restored from backup.

### `BACKUP_ENABLED=false`

No backup is created. The toolkit writes output to a `.tmp` file first, then atomically overwrites the original only on success. If processing fails, the original is completely untouched.

---

## Configuration

Edit `config.sh` to change persistent defaults:

```bash
# Subtitle language tag (ISO 639-2)
SUB_LANG="ara"
SUB_LANG_NAME="Arabic"

# Backup settings
BACKUP_ENABLED=true
BACKUP_BASE_DIR="${HOME}/tmp"

# Suppress notify-send desktop notifications
SILENT_MODE=false
```

All settings can also be changed at runtime through the **Settings** menu without editing any file. Changes apply immediately for the current session.

---

## Adding a New Module

The toolkit auto-sources every `.sh` file in `modules/` on startup. Adding a feature requires three steps and no changes to existing files (except registering the menu entry):

**1. Create `modules/myfeature.sh`:**

```bash
#!/bin/zsh
# modules/myfeature.sh — Description of what this module does.

my_feature_function() {
    log_info "Doing something..."
    local dir
    dir=$(pick_dir ".") || return
    # your logic here
    log_success "Done."
}

menu_myfeature() {
    my_feature_function
}
```

**2. Register it in `MAIN_MENU_ITEMS` inside `mkv-toolkit.sh`:**

```bash
MAIN_MENU_ITEMS=(
    ...
    "  My Feature   ▸ short description|menu_myfeature"
    ...
)
```

**3. Done.** The file is sourced automatically at next launch.

### Utilities available to all modules

All functions defined in `modules/utils.sh` are available globally:

| Function | Description |
|---|---|
| `log_info / log_warn / log_error / log_success / log_step` | Coloured terminal output |
| `notify_info / notify_warn / notify_error` | Terminal + optional desktop notification |
| `pick_file <prompt> <dir> <glob>` | fzf single-file picker with mediainfo preview |
| `pick_files <prompt> <dir> <glob>` | fzf multi-file picker |
| `pick_dir [start_dir]` | Directory picker via yazi or find+fzf |
| `find_sub <dir> <base>` | Find subtitle for a base name, sets `$REPLY` |
| `build_sub_args <sub_file>` | Populate `$SUB_ARGS` with mkvmerge track flags |
| `run_mkvmerge [args...]` | mkvmerge wrapper with error handling |
| `setup_backup_workspace <vid_dir>` | Create backup directory structure, set `$BACKUP_DIR` |
| `purge_backup_dir [path]` | Interactively delete a backup directory |

---

## Planned Modules

### Remux / Convert (`modules/remux.sh`)

Re-wrap video streams between containers without re-encoding any tracks.

- MKV → MP4 via `ffmpeg -c copy`
- MP4 / AVI → MKV via `mkvmerge`

### MKV Metadata Editor (`modules/metadata.sh`)

Edit MKV container properties in-place using `mkvpropedit` (no remux needed).

- Set container title
- Fix language tags on audio and subtitle tracks
- Add or remove cover art attachments
- Batch-apply across a full season directory

Requires `mkvtoolnix-cli` (`sudo pacman -S mkvtoolnix-cli`).

---

## License

MIT
