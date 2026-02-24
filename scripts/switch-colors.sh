#!/usr/bin/env bash
set -euo pipefail

# Switch waybar color palette between available color files (e.g. gruvbox, rose-pine)
# It updates each styles/*/style.css import to point at the chosen colors/<name>.css

WORKDIR="$(dirname "$(realpath "$0")")/.."
COLORS_DIR="$WORKDIR/colors"
BACKUP_DIR="$WORKDIR/backups"
LAUNCH_SCRIPT="$WORKDIR/scripts/launch.sh"

mkdir -p "$BACKUP_DIR"

list_colors() {
  for f in "$COLORS_DIR"/*.css; do
    [ -f "$f" ] || continue
    basename "$f" .css
  done
}

choose_color_interactive() {
  local choices
  choices=$(list_colors)
  if command -v rofi >/dev/null 2>&1; then
    echo "$choices" | rofi -dmenu -p "Waybar colors"
    return
  fi
  if command -v dmenu >/dev/null 2>&1; then
    echo "$choices" | dmenu -p "Waybar colors"
    return
  fi
  echo "Available colors:"
  echo "$choices"
  echo -n "Choose colors: "
  read -r sel
  echo "$sel"
}

COLOR="${1-}"
if [ -z "$COLOR" ]; then
  COLOR=$(choose_color_interactive)
fi

if [ -z "$COLOR" ]; then
  echo "No color selected. Exiting." >&2
  exit 2
fi

COLOR_FILE="$COLORS_DIR/$COLOR.css"
if [ ! -f "$COLOR_FILE" ]; then
  echo "Color file '$COLOR_FILE' not found." >&2
  exit 3
fi

gsettings set org.gnome.desktop.interface gtk-theme "$COLOR"

# Try to find spicetify binary (Waybar may run with a limited PATH)
if ! command -v spicetify >/dev/null 2>&1; then
  SPICETIFY_BIN="$HOME/.spicetify/spicetify"
else
  SPICETIFY_BIN="$(command -v spicetify)"
fi

# Stop Spotify: handle Flatpak and regular installs
flatpak kill com.spotify.Client 2>/dev/null || pkill -x spotify 2>/dev/null || true

# Set spicetify settings (use separate invocations to avoid argument parsing issues)
"$SPICETIFY_BIN" config current_theme "Default"
"$SPICETIFY_BIN" config color_scheme "$COLOR"

# Apply the theme changes — let failures surface so they can be diagnosed
"$SPICETIFY_BIN" apply

# Restart Spotify (Flatpak) in background
flatpak run com.spotify.Client >/dev/null 2>&1 &

# Update rofi theme symlink
ROFI_THEME_DIR="$HOME/.local/share/rofi/themes"
ROFI_LINK="$ROFI_THEME_DIR/curr_theme.rasi"
ROFI_THEME_FILE="$ROFI_THEME_DIR/colors/$COLOR.rasi"

mkdir -p "$ROFI_THEME_DIR"

if [ -f "$ROFI_THEME_FILE" ]; then
  ln -sfn "$ROFI_THEME_FILE" "$ROFI_LINK"
  echo "Updated rofi theme symlink -> $ROFI_THEME_FILE"
else
  echo "No matching rofi theme found at $ROFI_THEME_FILE (skipping rofi update)"
fi

TS=$(date +%s)

# Update each style's style.css to import the chosen color file
for style_css in "$WORKDIR"/styles/*/style.css; do
  [ -f "$style_css" ] || continue

  style_name=$(basename "$(dirname "$style_css")")
  backup="$BACKUP_DIR/style.${style_name}.${TS}.css"
  cp -a "$style_css" "$backup"
  echo "Backed up $style_css -> $backup"

  # Replace existing import line if present
  if grep -q "@import 'colors/.*\.css';" "$style_css"; then
    sed -E -i "s|@import 'colors/[^']+\.css';|@import 'colors/${COLOR}.css';|" "$style_css"
    echo "Updated import in $style_css -> colors/${COLOR}.css"
  else
    # Prepend import if none exists
    tmpf="${style_css}.tmp"
    printf "@import 'colors/%s.css';\n\n" "$COLOR" > "$tmpf"
    cat "$style_css" >> "$tmpf"
    mv "$tmpf" "$style_css"
    echo "Inserted import into $style_css -> colors/${COLOR}.css"
  fi
done

# Also update any top-level style.css files if present
if [ -f "$WORKDIR/style.css" ]; then
  backup="$BACKUP_DIR/style.root.${TS}.css"
  cp -a "$WORKDIR/style.css" "$backup"
  if grep -q "@import 'colors/.*\.css';" "$WORKDIR/style.css"; then
    sed -E -i "s|@import 'colors/[^']+\.css';|@import 'colors/${COLOR}.css';|" "$WORKDIR/style.css"
  else
    tmpf="${WORKDIR}/style.css.tmp"
    printf "@import 'colors/%s.css';\n\n" "$COLOR" > "$tmpf"
    cat "$WORKDIR/style.css" >> "$tmpf"
    mv "$tmpf" "$WORKDIR/style.css"
  fi
  echo "Updated top-level style.css -> colors/${COLOR}.css (backup: $backup)"
fi

# Restart waybar using launch script if available
if [ -x "$LAUNCH_SCRIPT" ]; then
  "$LAUNCH_SCRIPT"
  echo "Restarted waybar via $LAUNCH_SCRIPT"
else
  pkill -x waybar || true
  nohup waybar >/dev/null 2>&1 &
  echo "Restarted waybar"
fi

# Also update terminal colors if matching sequences exist for the chosen theme
SEQ_DIR="$HOME/.config/fish/terminal-sequences"
SEQ_FILE="$SEQ_DIR/${COLOR}.txt"
if [ -f "$SEQ_FILE" ]; then
  me=$(id -un)
  # Send the terminal escape sequences to all pseudo-terminals owned by the current user
  for tty in /dev/pts/*; do
    [ -e "$tty" ] || continue
    [ "$tty" = "/dev/ptmx" ] && continue
    owner=$(stat -c %U "$tty" 2>/dev/null || true)
    if [ "$owner" = "$me" ]; then
      # Ignore errors writing to a tty
      # send sequences without trailing newline
printf "%s" "$(cat "$SEQ_FILE")" > "$tty" 2>/dev/null || true

# hard reset formatting
printf '\033[0m' > "$tty" 2>/dev/null || true
    fi
    done
  echo "Updated terminal colors from: $SEQ_FILE"
fi

echo "Switched colors to: $COLOR"

# --- Random wallpaper per theme ---
WALL_BASE="$HOME/Pictures/Wallpapers"
WALL_DIR="$WALL_BASE/$COLOR"

if [ -d "$WALL_DIR" ]; then
  mapfile -t WALLS < <(find "$WALL_DIR" -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.webp" \))

  if [ "${#WALLS[@]}" -gt 0 ]; then
    RANDOM_WALL="${WALLS[$RANDOM % ${#WALLS[@]}]}"
    
    # Ensure swww daemon is running
    if ! pgrep -x swww-daemon >/dev/null; then
      swww-daemon >/dev/null 2>&1 &
      sleep 0.3
    fi

    swww img "$RANDOM_WALL" -t wipe --transition-fps 165 --transition-duration 0.3
    cp -a "$RANDOM_WALL" "$WALL_BASE/active_wallpaper"
    echo "Set random wallpaper: $RANDOM_WALL"
  else
    echo "No wallpapers found in $WALL_DIR"
  fi
else
  echo "Wallpaper directory not found: $WALL_DIR"
fi

# Persist the active theme for other tools (fish config uses this on startup)
FISH_CUR_DIR="$HOME/.config/fish"
FISH_CUR_FILE="$FISH_CUR_DIR/current_theme"
mkdir -p "$FISH_CUR_DIR"
printf "%s\n" "$COLOR" > "$FISH_CUR_FILE"

# If the theme has terminal sequences, also copy them to an "active" file so
# new terminals can source a single known path (optional, convenient)
if [ -f "$SEQ_FILE" ]; then
  cp -a "$SEQ_FILE" "$SEQ_DIR/active.txt"
fi
