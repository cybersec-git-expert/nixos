#!/usr/bin/env bash
# Start Main.qml + TopBar.qml after Hyprland IPC is ready.
# Avoid: `hyprctl | head` under pipefail — SIGPIPE makes the pipeline fail even when JSON is valid.
set -u

MAIN="${HOME}/.config/hypr/scripts/quickshell/Main.qml"
BAR="${HOME}/.config/hypr/scripts/quickshell/TopBar.qml"
LOG="${HOME}/.cache/quickshell/autostart.log"
mkdir -p "$(dirname "$LOG")"
# Create file immediately so `cat ~/.cache/quickshell/autostart.log` works after any partial run.
: >"$LOG"
exec >>"$LOG" 2>&1
echo "$(date -Is) autostart begin (WAYLAND_DISPLAY=${WAYLAND_DISPLAY-})"

QS="${QUICKSHELL_BIN:-}"
if [[ -z "$QS" || ! -x "$QS" ]]; then
  QS="$(command -v quickshell 2>/dev/null || true)"
fi
if [[ -z "$QS" || ! -x "$QS" ]]; then
  QS="$(command -v qs 2>/dev/null || true)"
fi
if [[ -z "$QS" || ! -x "$QS" ]]; then
  QS="/usr/bin/quickshell"
fi
if [[ ! -x "$QS" ]]; then
  echo "$(date -Is) ERROR: quickshell not found (set QUICKSHELL_BIN or install quickshell)"
  exit 1
fi
echo "$(date -Is) using QS=$QS"

# If two TopBar (or Main) processes are already running (double exec, race), drop extras or bars stack.
dedupe_instances() {
  local n
  n=$(pgrep -f "quickshell.*TopBar\\.qml" 2>/dev/null | wc -l)
  n=${n// /}
  if [ "${n:-0}" -gt 1 ]; then
    echo "$(date -Is) dedupe: $n TopBar processes — killing all, will restart one"
    pkill -f "quickshell.*TopBar\\.qml" 2>/dev/null || true
    sleep 0.5
  fi
  n=$(pgrep -f "quickshell.*Main\\.qml" 2>/dev/null | wc -l)
  n=${n// /}
  if [ "${n:-0}" -gt 1 ]; then
    echo "$(date -Is) dedupe: $n Main processes — killing all, will restart one"
    pkill -f "quickshell.*Main\\.qml" 2>/dev/null || true
    sleep 0.5
  fi
}
dedupe_instances

# Wait for compositor (do not use `| head` with pipefail — breaks on SIGPIPE).
for i in $(seq 1 45); do
  mon_json="$(hyprctl monitors -j 2>/dev/null)" || mon_json=""
  if [[ "${mon_json:0:1}" == "[" ]]; then
    echo "$(date -Is) hyprctl ready after ${i}s"
    break
  fi
  sleep 1
done
sleep 1

running_main() { pgrep -af "quickshell" 2>/dev/null | grep -qF "Main.qml"; }
running_bar() { pgrep -af "quickshell" 2>/dev/null | grep -qF "TopBar.qml"; }

# Inject QtMultimedia QML path so the wallpaper picker works on NixOS.
# Match the exact Qt version quickshell is built against to avoid ABI mismatch.
_qs_qt_ver="$(strings "$QS" 2>/dev/null | grep -oP 'qtbase-\K6\.[0-9]+\.[0-9]+' | head -1)"
if [[ -n "$_qs_qt_ver" ]]; then
  _qs_multimedia="$(find /nix/store -maxdepth 1 -name "*qtmultimedia-${_qs_qt_ver}*" -type d 2>/dev/null | sort -V | tail -1)"
else
  _qs_multimedia="$(find /nix/store -maxdepth 1 -name '*qtmultimedia-6*' -type d 2>/dev/null | sort -V | tail -1)"
fi
if [[ -n "$_qs_multimedia" && -d "$_qs_multimedia/lib/qt-6/qml" ]]; then
  _qs_mm_qml="$_qs_multimedia/lib/qt-6/qml"
  export QML2_IMPORT_PATH="${_qs_mm_qml}${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"
  export NIXPKGS_QT6_QML_IMPORT_PATH="${_qs_mm_qml}${NIXPKGS_QT6_QML_IMPORT_PATH:+:$NIXPKGS_QT6_QML_IMPORT_PATH}"
  echo "$(date -Is) injected QtMultimedia QML path (Qt $_qs_qt_ver): $_qs_mm_qml"
  # Also inject the multimedia plugin dir so Qt can find the GStreamer backend
  if [[ -d "$_qs_multimedia/lib/qt-6/plugins" ]]; then
    export QT_PLUGIN_PATH="${_qs_multimedia}/lib/qt-6/plugins${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"
    echo "$(date -Is) injected QtMultimedia plugin path (Qt $_qs_qt_ver): ${_qs_multimedia}/lib/qt-6/plugins"
  fi
else
  echo "$(date -Is) WARNING: could not find qtmultimedia-${_qs_qt_ver:-6.x} in nix store"
fi

start_one() {
  local qml="$1"
  local label="$2"
  if [[ "$label" == main ]] && running_main; then
    echo "$(date -Is) skip Main (already running)"
    return 0
  fi
  if [[ "$label" == bar ]] && running_bar; then
    echo "$(date -Is) skip TopBar (already running)"
    return 0
  fi
  echo "$(date -Is) starting $label: $QS -p $qml"
  "$QS" -p "$qml" &
  disown 2>/dev/null || true
}

start_one "$MAIN" main
sleep 1.2
start_one "$BAR" bar

# TopBar often races Main / Wayland; verify and retry a few times.
for attempt in $(seq 1 8); do
  if running_bar; then
    echo "$(date -Is) TopBar process OK (check attempt $attempt)"
    exit 0
  fi
  echo "$(date -Is) TopBar missing, retry $attempt/8 …"
  start_one "$BAR" bar
  sleep 1.5
done

echo "$(date -Is) WARNING: TopBar still not running after retries; try: Super+X or quickshell-panel.sh toggle volume"
exit 0
