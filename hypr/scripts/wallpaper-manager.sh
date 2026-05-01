#!/usr/bin/env bash
# Simple wallpaper restore helper for Hyprland + swww/mpvpaper.
# Used by ~/.config/hypr/autostart.conf: `wallpaper-manager.sh init`
set -euo pipefail

cmd="${1:-}"
WALL_DIR="${HOME}/.config/wallpaper-manager"
WALL_FILE_TXT="${WALL_DIR}/current_wallpaper.txt"
WALL_OUTPUTS_TXT="${WALL_DIR}/current_wallpaper_outputs.txt"
# Persists across reboot (/tmp is cleared). Quickshell Lock + hyprlock use this.
LOCK_BG_PERSIST="${WALL_DIR}/lock_background.png"
THUMB_CACHE="${HOME}/.cache/wallpaper_picker/thumbs"

sync_lock_background() {
  local wp="$1"
  [[ -n "$wp" ]] || return 0
  [[ -f "$wp" ]] || return 0
  mkdir -p "$WALL_DIR"
  local ext="${wp##*.}"
  ext="${ext,,}"
  if [[ "$ext" =~ ^(mp4|mkv|mov|webm)$ ]]; then
    local base="${wp##*/}"
    if [[ -f "${THUMB_CACHE}/${base}" ]]; then
      cp -f -- "${THUMB_CACHE}/${base}" "$LOCK_BG_PERSIST" 2>/dev/null || true
    elif command -v ffmpeg >/dev/null 2>&1; then
      ffmpeg -hide_banner -loglevel error -y -i "$wp" -vf "scale=1920:-2" -vframes 1 "$LOCK_BG_PERSIST" 2>/dev/null || true
    fi
  else
    if command -v magick >/dev/null 2>&1; then
      magick "$wp" -strip -resize '3840x3840>' "$LOCK_BG_PERSIST" 2>/dev/null || cp -f -- "$wp" "$LOCK_BG_PERSIST" 2>/dev/null || true
    else
      cp -f -- "$wp" "$LOCK_BG_PERSIST" 2>/dev/null || true
    fi
  fi
  if [[ -f "$LOCK_BG_PERSIST" ]]; then
    cp -f -- "$LOCK_BG_PERSIST" /tmp/lock_bg.png 2>/dev/null || true
  fi
}

ensure_swww() {
  if ! command -v swww >/dev/null 2>&1; then
    return 0
  fi
  if ! pgrep -x swww-daemon >/dev/null 2>&1; then
    swww-daemon >/dev/null 2>&1 &
    disown 2>/dev/null || true
  fi
  # Wait up to 5s for swww-daemon to be ready (query returns exit 0 when ready)
  local i=0
  while ! swww query >/dev/null 2>&1 && (( i < 20 )); do
    sleep 0.25
    (( i++ ))
  done
}

apply_wallpaper() {
  local wp="$1"
  local outputs="${2:-}"
  [[ -n "$wp" ]] || return 0
  [[ -f "$wp" ]] || return 0

  mkdir -p "$WALL_DIR"

  if [[ -z "$outputs" ]] && [[ -f "$WALL_OUTPUTS_TXT" ]]; then
    outputs="$(head -n1 "$WALL_OUTPUTS_TXT" 2>/dev/null || true)"
  fi
  [[ -n "$outputs" ]] || outputs="*"

  # Stop any video wallpaper first (safe even if not running).
  pkill mpvpaper >/dev/null 2>&1 || true

  local ext="${wp##*.}"
  ext="${ext,,}"
  if [[ "$ext" =~ ^(mp4|mkv|mov|webm)$ ]]; then
    if command -v mpvpaper >/dev/null 2>&1; then
      mpvpaper -o 'loop --no-audio --hwdec=auto --profile=high-quality --video-sync=display-resample --interpolation --tscale=oversample' "$outputs" "$wp" >/dev/null 2>&1 &
      disown 2>/dev/null || true
    fi
    sync_lock_background "$wp"
    return 0
  fi

  ensure_swww
  if command -v swww >/dev/null 2>&1; then
    # Hyprland outputs are not always ready immediately after login; retry a few times.
    local ok=0 attempt
    for attempt in 1 2 3 4 5 6 7 8; do
      if [[ "$outputs" == "*" ]]; then
        if env WGPU_BACKEND=vulkan swww img "$wp" --resize crop --transition-type any --transition-pos 0.5,0.5 --transition-fps 144 --transition-duration 1 >/dev/null 2>&1 \
          || swww img "$wp" --resize crop --transition-type any --transition-pos 0.5,0.5 --transition-fps 144 --transition-duration 1 >/dev/null 2>&1; then
          ok=1
          break
        fi
      else
        if env WGPU_BACKEND=vulkan swww img "$wp" --outputs "$outputs" --resize crop --transition-type any --transition-pos 0.5,0.5 --transition-fps 144 --transition-duration 1 >/dev/null 2>&1 \
          || swww img "$wp" --outputs "$outputs" --resize crop --transition-type any --transition-pos 0.5,0.5 --transition-fps 144 --transition-duration 1 >/dev/null 2>&1; then
          ok=1
          break
        fi
      fi
      sleep 1
    done
  fi
  sync_lock_background "$wp"
}

case "$cmd" in
  init|"")
    if [[ -f "$WALL_FILE_TXT" ]]; then
      wp="$(head -n1 "$WALL_FILE_TXT" || true)"
      outputs="*"
      if [[ -f "$WALL_OUTPUTS_TXT" ]]; then
        outputs="$(head -n1 "$WALL_OUTPUTS_TXT" 2>/dev/null || true)"
      fi
      # Wait up to 15s for the wallpaper file to be accessible
      # (covers cases where /Vault or other drives mount slowly)
      if [[ -n "$wp" ]]; then
        wait_i=0
        while [[ ! -f "$wp" ]] && (( wait_i < 60 )); do
          sleep 0.25
          (( wait_i++ ))
        done
      fi
      apply_wallpaper "${wp:-}" "${outputs:-*}"
    fi
    ;;
  apply)
    # wallpaper-manager.sh apply /path/to/file [outputs]
    wp="${2:-}"
    outputs="${3:-*}"
    mkdir -p "$WALL_DIR"
    printf '%s\n' "$wp" > "$WALL_FILE_TXT"
    printf '%s\n' "$outputs" > "$WALL_OUTPUTS_TXT"
    apply_wallpaper "$wp" "$outputs"
    ;;
  *)
    echo "Usage: $(basename "$0") init | apply /path/to/wallpaper"
    exit 2
    ;;
esac

