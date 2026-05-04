#!/usr/bin/env bash
# Quit AGS and start the bar again (Hyprland Super+X). AGS v1 has no `ags reload`.
set -euo pipefail
export PATH="/run/current-system/sw/bin:${HOME}/.nix-profile/bin:${PATH:-}"
_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v ags >/dev/null 2>&1; then
    command -v notify-send >/dev/null 2>&1 && notify-send -a AGS 'ags not in PATH' 'Add ags to systemPackages or use a full path.' || true
    exit 1
fi
ags -q 2>/dev/null || true
sleep 0.55
bash "${_script_dir}/autostart_ags.sh"
