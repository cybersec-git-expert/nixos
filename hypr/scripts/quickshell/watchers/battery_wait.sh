#!/usr/bin/env bash
# Wait for a battery state change. On desktop chassis there is nothing to watch,
# so just sleep so the QML poller gracefully retries every 30 s.

BAT=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)

if [[ -z "$BAT" ]] || ! command -v inotifywait >/dev/null; then
    sleep 30
    exit 0
fi

inotifywait -qq -e modify "$BAT/status" "$BAT/capacity" 2>/dev/null || sleep 30
