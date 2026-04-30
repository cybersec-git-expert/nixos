#!/usr/bin/env bash
set -euo pipefail

# Sync Hyprlock background to the current wallpaper (set by wallpaper-manager),
# then run hyprlock. Keeps lockscreen consistent after wallpaper changes.

WALL_STATE_DIR="${HOME}/.config/wallpaper-manager"
WALL_STATE_FILE="${WALL_STATE_DIR}/current_wallpaper.txt"

HYPRLOCK_WALL_DIR="${HOME}/.config/hyprlock/wallpapers"
HYPRLOCK_WALL_LINK="${HYPRLOCK_WALL_DIR}/lockscreen"

mkdir -p "${HYPRLOCK_WALL_DIR}"

src=""
if [[ -f "${WALL_STATE_FILE}" ]]; then
  src="$(head -n1 "${WALL_STATE_FILE}" 2>/dev/null || true)"
fi

if [[ -n "${src}" && -f "${src}" ]]; then
  ext="${src##*.}"
  ext="${ext,,}"

  # Only sync static images. For videos/unknown types, fall back to screenshot mode.
  if [[ "${ext}" =~ ^(png|jpg|jpeg|webp|bmp)$ ]]; then
    dst="${HYPRLOCK_WALL_DIR}/lockscreen-src.${ext}"
    cp -f -- "${src}" "${dst}"
    ln -sfn -- "$(basename "${dst}")" "${HYPRLOCK_WALL_LINK}"
  fi
fi

exec hyprlock -c "${HOME}/.config/hypr/hyprlock.minimal.conf"

