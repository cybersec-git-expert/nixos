#!/usr/bin/env bash
set -euo pipefail

# Force a consistent default output device after login.
# This prevents WirePlumber from restoring HDMI/headset as default.

SPEAKER_SINK_NAME="alsa_output.pci-0000_80_1f.3.analog-stereo"

watch_mode=false
if [[ "${1:-}" == "--watch" ]]; then
  watch_mode=true
fi

apply_defaults() {
  # Set default sink by name (PulseAudio compat)
  pactl set-default-sink "${SPEAKER_SINK_NAME}" >/dev/null 2>&1 || true

  # Also set PipeWire default node (persists via WirePlumber state)
  if command -v wpctl >/dev/null 2>&1; then
    wpctl set-default "${SPEAKER_SINK_NAME}" >/dev/null 2>&1 || true
  fi

  # Move any current playback streams to the default sink (best-effort)
  while read -r input_id _rest; do
    [[ -n "${input_id}" ]] || continue
    pactl move-sink-input "${input_id}" "${SPEAKER_SINK_NAME}" >/dev/null 2>&1 || true
  done < <(pactl list short sink-inputs 2>/dev/null || true)
}

# Wait a bit for PipeWire/WirePlumber to be ready
for _ in {1..30}; do
  if pactl info >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done

apply_defaults

if $watch_mode; then
  # Re-apply whenever sinks/server change (e.g., HDMI plugged in steals default).
  pactl subscribe 2>/dev/null | while read -r line; do
    case "$line" in
      *"Event 'new' on sink"*|*"Event 'change' on sink"*|*"Event 'change' on server"*)
        apply_defaults
        ;;
    esac
  done
fi

