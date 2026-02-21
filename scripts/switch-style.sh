#!/usr/bin/env bash
set -euo pipefail

# Switch waybar style by creating symlinks for config and css and restarting waybar

WORKDIR="$(dirname "$(realpath "$0")")/.."
STYLES_DIR="$WORKDIR/styles"
BACKUP_DIR="$WORKDIR/backups"
LAUNCH_SCRIPT="$WORKDIR/scripts/launch.sh"

mkdir -p "$BACKUP_DIR"

list_styles() {
  for d in "$STYLES_DIR"/*/; do
    [ -d "$d" ] || continue
    basename "$d"
  done
}

choose_style_interactive() {
  local choices
  choices=$(list_styles)
  if command -v rofi >/dev/null 2>&1; then
    echo "$choices" | rofi -dmenu -p "Waybar style"
    return
  fi
  if command -v dmenu >/dev/null 2>&1; then
    echo "$choices" | dmenu -p "Waybar style"
    return
  fi
  echo "Available styles:"
  echo "$choices"
  echo -n "Choose style: "
  read -r sel
  echo "$sel"
}

STYLE="${1-}" # first arg if provided
if [ -z "$STYLE" ]; then
  STYLE=$(choose_style_interactive)
fi

if [ -z "$STYLE" ]; then
  echo "No style selected. Exiting." >&2
  exit 2
fi

STYLE_DIR="$STYLES_DIR/$STYLE"
if [ ! -d "$STYLE_DIR" ]; then
  echo "Style '$STYLE' not found in $STYLES_DIR" >&2
  exit 3
fi

TS=$(date +%s)
for f in config.jsonc style.css; do
  SRC="$STYLE_DIR/$f"
  if [ ! -e "$SRC" ]; then
    echo "Warning: $SRC does not exist, skipping." >&2
    continue
  fi

  DEST="$WORKDIR/$f"

  # backup existing file if it exists and isn't the same file
  if [ -e "$DEST" ] && [ "$(readlink -f "$DEST")" != "$(readlink -f "$SRC")" ]; then
    cp -a "$DEST" "$BACKUP_DIR/${f}.${TS}"
    echo "Backed up $DEST -> $BACKUP_DIR/${f}.${TS}"
  fi

  # create symlink (force)
  ln -sf "$SRC" "$DEST"
  echo "Linked $DEST -> $SRC"
done

# Restart waybar using the provided launch script if available
if [ -x "$LAUNCH_SCRIPT" ]; then
  "$LAUNCH_SCRIPT"
  echo "Restarted waybar via $LAUNCH_SCRIPT"
else
  # fallback: try to kill and restart waybar
  pkill -x waybar || true
  nohup waybar >/dev/null 2>&1 &
  echo "Restarted waybar" 
fi

echo "Switched style to: $STYLE"
