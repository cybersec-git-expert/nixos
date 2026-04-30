#!/usr/bin/env bash
# Confirmation dialog before closing the active window (Super+Q)

ROFI_THEME="$HOME/.config/rofi/themes/hacker-theme.rasi"

ACTIVE=$(hyprctl activewindow -j 2>/dev/null | jq -r '.title // "this window"' 2>/dev/null || echo "this window")

CHOICE=$(printf '✅ Yes\n❌ No' | rofi -dmenu \
  -theme "$ROFI_THEME" \
  -p "Close window?" \
  -mesg "$(printf '%s' "$ACTIVE")" \
  -no-custom \
  -lines 2 \
  -width 380 \
  -location 0)

[[ "$CHOICE" == "✅ Yes" ]] && hyprctl dispatch killactive
