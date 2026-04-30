#!/usr/bin/env bash
# Pomodoro timer state machine for the TopBar.
# State file: ~/.cache/qs_timer_state.json
#
# Schema: { "active": bool, "duration": minutes, "remaining": seconds, "end": unix_ts }
#   - When active=true:  end = unix_ts when timer finishes; remaining is recomputed by QML
#   - When active=false and remaining < duration*60:  paused
#   - When active=false and remaining == duration*60: idle/reset
#
# Usage:
#   timer_ctl.sh toggle              # start (from idle/paused) or pause (if running)
#   timer_ctl.sh reset               # back to default duration, inactive
#   timer_ctl.sh adjust  +5  | -5    # bump duration by N minutes (only when paused/idle)
#   timer_ctl.sh open               # toggle the compact Pomodoro panel (qs_manager timer)

STATE="$HOME/.cache/qs_timer_state.json"
mkdir -p "$(dirname "$STATE")"

read_field() { python3 -c "import json,sys; d=json.load(open('$STATE')) if __import__('os').path.exists('$STATE') else {}; print(d.get('$1', ''))" 2>/dev/null; }

now=$(date +%s)
DUR_DEFAULT=25

if [[ ! -f "$STATE" ]]; then
    printf '{"active":false,"duration":%d,"remaining":%d,"end":0}\n' "$DUR_DEFAULT" $((DUR_DEFAULT*60)) > "$STATE"
fi

active=$(read_field active)
duration=$(read_field duration); duration=${duration:-$DUR_DEFAULT}
remaining=$(read_field remaining); remaining=${remaining:-$((duration*60))}
end=$(read_field end); end=${end:-0}

[[ "$active" == "True"  ]] && active=true
[[ "$active" == "False" ]] && active=false

write() {
    printf '{"active":%s,"duration":%d,"remaining":%d,"end":%d}\n' "$1" "$2" "$3" "$4" > "$STATE"
    # Pomodoro popup uses QS_TIMER_NO_CLOSE=1 so controls do not dismiss the overlay.
    if [[ "${QS_TIMER_NO_CLOSE:-}" != "1" ]]; then
        echo "close" > /tmp/qs_widget_state 2>/dev/null || true
    fi
}

case "$1" in
    toggle)
        if [[ "$active" == "true" ]]; then
            # Pause: store remaining
            r=$(( end - now ))
            (( r < 0 )) && r=0
            write false "$duration" "$r" 0
        else
            # Resume / start
            (( remaining <= 0 )) && remaining=$((duration*60))
            write true "$duration" "$remaining" $(( now + remaining ))
            # Close the Pomodoro popup so the top-bar chip takes over (still respects QS_TIMER_NO_CLOSE in write).
            echo "close" > /tmp/qs_widget_state 2>/dev/null || true
        fi
        ;;
    reset)
        write false "$duration" $((duration*60)) 0
        ;;
    adjust)
        delta=${2:-5}
        # No-op while running
        [[ "$active" == "true" ]] && exit 0
        new=$(( duration + delta ))
        (( new < 1 )) && new=1
        (( new > 180 )) && new=180
        write false "$new" $((new*60)) 0
        ;;
    open)
        bash "$HOME/.config/hypr/scripts/qs_manager.sh" toggle timer
        ;;
    *)
        echo "usage: timer_ctl.sh {toggle|reset|adjust ±N|open}" >&2
        exit 1
        ;;
esac
