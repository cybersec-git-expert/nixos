#!/usr/bin/env bash
# Used by TopBar stats tile: scroll = up|down, right-click = mute
STEP="${VOLUME_STEP:-5}"
ACTION="${1:-}"

nudge_up() {
  pamixer -i "$STEP" 2>/dev/null && return 0
  wpctl set-volume "@DEFAULT_AUDIO_SINK@" "${STEP}%+" 2>/dev/null && return 0
  pactl set-sink-volume "@DEFAULT_SINK@" "+${STEP}%" 2>/dev/null && return 0
  return 1
}

nudge_down() {
  pamixer -d "$STEP" 2>/dev/null && return 0
  wpctl set-volume "@DEFAULT_AUDIO_SINK@" "${STEP}%-" 2>/dev/null && return 0
  pactl set-sink-volume "@DEFAULT_SINK@" "-${STEP}%" 2>/dev/null && return 0
  return 1
}

do_mute() {
  pamixer -t 2>/dev/null && return 0
  wpctl set-mute "@DEFAULT_AUDIO_SINK@" toggle 2>/dev/null && return 0
  pactl set-sink-mute "@DEFAULT_SINK@" toggle 2>/dev/null && return 0
  return 1
}

case "$ACTION" in
  up)   nudge_up ;;
  down) nudge_down ;;
  mute) do_mute ;;
  *)    exit 1 ;;
esac
