#!/usr/bin/env bash
# AGS calls this when UPS is on battery and charge ≤50%. Abort: kill this PID before 90s.
set -eu
pct="${1:-?}"
export PATH="/run/current-system/sw/bin:${PATH:-}"
notify-send -u critical -a "UPS" "Battery ${pct}% (on UPS)" "Power off in 90s. Restore AC, or run: kill $$" 2>/dev/null || true
sleep 90
loginctl poweroff 2>/dev/null || systemctl poweroff 2>/dev/null || true
