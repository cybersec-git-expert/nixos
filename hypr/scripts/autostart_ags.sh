#!/usr/bin/env bash
# Single AGS instance (GTK shell bar).
set -euo pipefail
export PATH="/run/current-system/sw/bin:${HOME}/.nix-profile/bin:${PATH:-}"
LOG="${HOME}/.cache/ags/autostart.log"
mkdir -p "$(dirname "$LOG")"
{
  echo "=== $(date -Is) autostart_ags ==="
  command -v ags || echo "ERROR: ags not in PATH (add pkgs.ags to NixOS and nixos-rebuild switch)"
} >>"$LOG" 2>&1
command -v ags >/dev/null 2>&1 || exit 0
pkill -x ags 2>/dev/null || true
sleep 0.45
nohup ags >>"$LOG" 2>&1 &
disown 2>/dev/null || true
