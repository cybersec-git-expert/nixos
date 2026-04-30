#!/usr/bin/env bash
# cycle_player.sh [up|down]
# Cycles the preferred music source and writes it to /tmp/qs_preferred_player

DIRECTION="${1:-up}"
STATE_FILE="/tmp/qs_preferred_player"

# Build player list: MPRIS players first, then mpd if mpc is available
players=()
while IFS= read -r p; do
    [ -n "$p" ] && players+=("$p")
done < <(playerctl -l 2>/dev/null)

if command -v mpc &>/dev/null; then
    MPC_S=$(mpc status 2>/dev/null)
    if echo "$MPC_S" | grep -qE '\[playing\]|\[paused\]'; then
        players+=("mpd")
    fi
fi

count=${#players[@]}
[ "$count" -eq 0 ] && exit 0

# Read current preferred player
current=""
[ -f "$STATE_FILE" ] && current=$(cat "$STATE_FILE")

# Find current index (-1 if not found → will wrap to 0 on "up")
idx=-1
for i in "${!players[@]}"; do
    if [ "${players[$i]}" = "$current" ]; then
        idx=$i; break
    fi
done

# Cycle index
if [ "$DIRECTION" = "up" ]; then
    idx=$(( (idx + 1) % count ))
else
    idx=$(( (idx - 1 + count) % count ))
fi

echo "${players[$idx]}" > "$STATE_FILE"
