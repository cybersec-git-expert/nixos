#!/usr/bin/env bash
# Cold session: outputs + workspaces settle after ~1s (avoids ws ids like 22 on wrong head).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$DIR/apply-monitor-layout.sh"
bash "$DIR/workspace-sync-monitors.sh"
bash "$DIR/workspace-goto.sh" 1
