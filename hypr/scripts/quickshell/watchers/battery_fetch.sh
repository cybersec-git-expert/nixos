#!/usr/bin/env bash
# Battery info for the TopBar. On desktop systems (no /sys/class/power_supply/BAT*)
# returns a sane stub the QML treats as "Unknown 100%". The pill itself is hidden
# on desktop chassis (replaced by the power-off button).

BAT=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)

if [[ -z "$BAT" ]]; then
    echo '{"percent":100,"icon":"\udb80\udc83","status":"Unknown"}'
    exit 0
fi

PCT=$(< "$BAT/capacity" 2>/dev/null); PCT=${PCT:-100}
STATUS=$(< "$BAT/status" 2>/dev/null); STATUS=${STATUS:-Unknown}

# Pick a Nerd-Font glyph for the current charge tier
if   (( PCT >= 90 )); then ICON="󰁹"
elif (( PCT >= 70 )); then ICON="󰂁"
elif (( PCT >= 50 )); then ICON="󰁿"
elif (( PCT >= 30 )); then ICON="󰁽"
elif (( PCT >= 15 )); then ICON="󰁻"
else                       ICON="󰁺"
fi
[[ "$STATUS" == "Charging" ]] && ICON="󰂄"

printf '{"percent":%d,"icon":"%s","status":"%s"}\n' "$PCT" "$ICON" "$STATUS"
