#!/usr/bin/env bash
# Move focused window to workspace N, then snap N to the correct monitor and focus it.
set -euo pipefail
N="${1:?workspace id}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hyprctl dispatch movetoworkspace "$N" >/dev/null 2>&1 || true
bash "$SCRIPT_DIR/workspace-goto.sh" "$N"
