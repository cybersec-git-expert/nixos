#!/usr/bin/env bash
# Split one wallpaper across two Hyprland outputs (Nitrogen-style "flow").
# Vertical stack: builds a virtual canvas max(W)×(H1+H2), scales the image to
# cover it, then crops bands by each monitor's height so the seam matches the
# physical join — not a naive 50%/50% of the source pixels (wrong when monitors
# differ a lot, e.g. 1080p over 3440×1440).
# Horizontal row: max(H)×(W1+W2) the same idea on the x axis.
# Usage: wallpaper-flow-split.sh vertical|horizontal /path/to/image.png
set -euo pipefail

MODE="${1:-}"
SRC="${2:-}"

if [[ "$MODE" != "vertical" && "$MODE" != "horizontal" ]]; then
  echo "Usage: $(basename "$0") vertical|horizontal /path/to/image" >&2
  exit 2
fi
[[ -f "$SRC" ]] || { echo "Not a file: $SRC" >&2; exit 1; }
command -v magick >/dev/null 2>&1 || { echo "wallpaper-flow-split: install ImageMagick (magick)" >&2; exit 1; }
command -v hyprctl >/dev/null 2>&1 || { echo "wallpaper-flow-split: hyprctl not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "wallpaper-flow-split: jq not found" >&2; exit 1; }
command -v swww >/dev/null 2>&1 || { echo "wallpaper-flow-split: swww not found" >&2; exit 1; }

ensure_hyprland_env() {
  [[ -n "${XDG_RUNTIME_DIR:-}" ]] || export XDG_RUNTIME_DIR="/run/user/$(id -u)"
  if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    return 0
  fi
  local d
  for d in "$XDG_RUNTIME_DIR/hypr"/*; do
    [[ -d "$d" ]] || continue
    export HYPRLAND_INSTANCE_SIGNATURE="$(basename "$d")"
    return 0
  done
  return 1
}

CACHE="${HOME}/.cache/wallpaper-manager/flow"
mkdir -p "$CACHE"
LOG="${CACHE}/last_run.log"
{
  echo "=== $(date -Iseconds) mode=$MODE src=$SRC ==="
} >>"$LOG" 2>&1 || true

ensure_hyprland_env || true

if ! pgrep -x swww-daemon >/dev/null 2>&1; then
  swww-daemon >/dev/null 2>&1 &
  disown 2>/dev/null || true
fi
i=0
while ! swww query >/dev/null 2>&1 && (( i < 20 )); do
  sleep 0.25
  (( ++i ))
done

MON_JSON=""
N=0
for _try in 1 2 3 4 5 6 7 8 9 10; do
  ensure_hyprland_env || true
  MON_JSON="$(hyprctl monitors -j 2>/dev/null || true)"
  [[ -n "$MON_JSON" ]] || MON_JSON="[]"
  N="$(echo "$MON_JSON" | jq 'if type == "array" then length else 0 end')"
  if [[ "$N" -ge 2 ]]; then
    break
  fi
  sleep 0.12
done

if [[ "$N" -eq 1 ]]; then
  out_name="$(echo "$MON_JSON" | jq -r '.[0].name')"
  for _ in {1..8}; do
    if env WGPU_BACKEND=vulkan swww img "$SRC" --outputs "$out_name" --resize crop --transition-type none --transition-fps 60 --transition-duration 0.1 >/dev/null 2>&1 \
      || swww img "$SRC" --outputs "$out_name" --resize crop --transition-type none --transition-fps 60 --transition-duration 0.1 >/dev/null 2>&1; then
      exit 0
    fi
    sleep 0.25
  done
  exit 1
fi

if [[ "$N" -lt 2 ]]; then
  echo "wallpaper-flow-split: need Hyprland monitor list (got N=$N). Is HYPRLAND_INSTANCE_SIGNATURE set? Try: hyprctl monitors -j" | tee -a "$LOG" >&2
  exit 1
fi

swww_apply() {
  local out="$1"
  local name="$2"
  local j
  for j in 1 2 3 4 5 6 7 8 9 10; do
    if env WGPU_BACKEND=vulkan swww img "$out" --outputs "$name" --resize crop --transition-type none --transition-fps 60 --transition-duration 0.1 >/dev/null 2>&1 \
      || swww img "$out" --outputs "$name" --resize crop --transition-type none --transition-fps 60 --transition-duration 0.1 >/dev/null 2>&1; then
      echo "swww ok: $name <- $out" >>"$LOG" 2>&1 || true
      return 0
    fi
    sleep 0.15
  done
  echo "swww failed: $name <- $out" >>"$LOG" 2>&1 || true
  return 1
}

ec=0
if [[ "$MODE" == "vertical" ]]; then
  SORTED="$(echo "$MON_JSON" | jq -c 'sort_by(.y) | .[:2]')"
  M0="$(echo "$SORTED" | jq '.[0]')"
  M1="$(echo "$SORTED" | jq '.[1]')"
  W0="$(echo "$M0" | jq -r '.width')"
  H0="$(echo "$M0" | jq -r '.height')"
  N0="$(echo "$M0" | jq -r '.name')"
  W1="$(echo "$M1" | jq -r '.width')"
  H1="$(echo "$M1" | jq -r '.height')"
  N1="$(echo "$M1" | jq -r '.name')"
  Wvirt=$W0
  (( W1 > Wvirt )) && Wvirt=$W1
  Hvirt=$(( H0 + H1 ))
  CANVAS="${CACHE}/canvas_v.png"
  magick "$SRC" -resize "${Wvirt}x${Hvirt}^" -gravity center -extent "${Wvirt}x${Hvirt}" "$CANVAS"
  STR0="${CACHE}/strip_${N0}.png"
  STR1="${CACHE}/strip_${N1}.png"
  FIT0="${CACHE}/fit-${N0}.png"
  FIT1="${CACHE}/fit-${N1}.png"
  magick "$CANVAS" -crop "${Wvirt}x${H0}+0+0" +repage "$STR0"
  magick "$CANVAS" -crop "${Wvirt}x${H1}+0+${H0}" +repage "$STR1"
  magick "$STR0" -resize "${W0}x${H0}^" -gravity center -extent "${W0}x${H0}" "$FIT0"
  magick "$STR1" -resize "${W1}x${H1}^" -gravity center -extent "${W1}x${H1}" "$FIT1"
  {
    echo "vertical: top=$N0 ${W0}x${H0} bottom=$N1 ${W1}x${H1} canvas=${Wvirt}x${Hvirt}"
    magick identify "$FIT0" "$FIT1" 2>/dev/null || true
  } >>"$LOG" 2>&1 || true
  swww_apply "$FIT0" "$N0" || ec=1
  swww_apply "$FIT1" "$N1" || ec=1
else
  SORTED="$(echo "$MON_JSON" | jq -c 'sort_by(.x) | .[:2]')"
  M0="$(echo "$SORTED" | jq '.[0]')"
  M1="$(echo "$SORTED" | jq '.[1]')"
  W0="$(echo "$M0" | jq -r '.width')"
  H0="$(echo "$M0" | jq -r '.height')"
  N0="$(echo "$M0" | jq -r '.name')"
  W1="$(echo "$M1" | jq -r '.width')"
  H1="$(echo "$M1" | jq -r '.height')"
  N1="$(echo "$M1" | jq -r '.name')"
  Wvirt=$(( W0 + W1 ))
  Hvirt=$H0
  (( H1 > Hvirt )) && Hvirt=$H1
  CANVAS="${CACHE}/canvas_h.png"
  magick "$SRC" -resize "${Wvirt}x${Hvirt}^" -gravity center -extent "${Wvirt}x${Hvirt}" "$CANVAS"
  STR0="${CACHE}/strip_${N0}.png"
  STR1="${CACHE}/strip_${N1}.png"
  FIT0="${CACHE}/fit-${N0}.png"
  FIT1="${CACHE}/fit-${N1}.png"
  magick "$CANVAS" -crop "${W0}x${Hvirt}+0+0" +repage "$STR0"
  magick "$CANVAS" -crop "${W1}x${Hvirt}+${W0}+0" +repage "$STR1"
  magick "$STR0" -resize "${W0}x${H0}^" -gravity center -extent "${W0}x${H0}" "$FIT0"
  magick "$STR1" -resize "${W1}x${H1}^" -gravity center -extent "${W1}x${H1}" "$FIT1"
  {
    echo "horizontal: left=$N0 ${W0}x${H0} right=$N1 ${W1}x${H1} canvas=${Wvirt}x${Hvirt}"
    magick identify "$FIT0" "$FIT1" 2>/dev/null || true
  } >>"$LOG" 2>&1 || true
  swww_apply "$FIT0" "$N0" || ec=1
  swww_apply "$FIT1" "$N1" || ec=1
fi
exit "$ec"
