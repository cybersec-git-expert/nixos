#!/usr/bin/env bash
# Cold session: Hyprland often spawns a stray high id (e.g. 21) on the second head before rules apply.
# Activate legal even ws on MSI, then return to ws 1 on HP (odd).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$DIR/apply-monitor-layout.sh"
bash "$DIR/workspace-sync-monitors.sh"
bash "$DIR/workspace-goto.sh" 2
bash "$DIR/workspace-sync-monitors.sh"
bash "$DIR/workspace-goto.sh" 1
