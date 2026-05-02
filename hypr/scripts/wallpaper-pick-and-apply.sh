#!/usr/bin/env bash
# Replace Quickshell wallpaper picker: pick an image, matugen + swww.
set -euo pipefail
dir="${WALLPAPER_DIR:-$HOME/Pictures/Wallpapers}"
f="$(zenity --file-selection --title="Choose wallpaper" --filename="${dir}/" 2>/dev/null)" || exit 0
[[ -f "$f" ]] || exit 0
bash "$HOME/.config/hypr/scripts/matugen/apply_matugen_wallpaper.sh" "$f"
bash "$HOME/.config/hypr/scripts/wallpaper-manager.sh" apply "$f" "*"
