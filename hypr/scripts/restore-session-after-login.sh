#!/usr/bin/env bash
# One-shot restore after login if user chose "Reopen windows" before reboot/shutdown.
# Called from autostart with a delay so Quickshell / bar are already up.

PENDING="${HOME}/.config/hypr/session-restore.pending"
JSON="${HOME}/.config/hypr/session-restore.json"
PY="${HOME}/.config/hypr/scripts/restore-session-after-login.py"

[[ -f "$PENDING" ]] || exit 0
[[ -f "$JSON" ]] || { rm -f "$PENDING"; exit 0; }

command -v hyprctl &>/dev/null || exit 0
hyprctl version &>/dev/null || exit 0

rm -f "$PENDING"

if python3 "$PY" 2>/dev/null; then
	notify-send -u low "Session" "Restored saved applications to their workspaces." 2>/dev/null || true
fi
rm -f "$JSON"
