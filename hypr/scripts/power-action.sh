#!/usr/bin/env bash
# Shared power actions for Rofi menu, hyprlock (Quickshell Lock.qml), keybinds, etc.
# Ensures /run/current-system/sw/bin is on PATH (NixOS) so systemctl is found from minimal environments.
set -euo pipefail
PATH="${PATH}:/run/current-system/sw/bin:/usr/bin:/bin"

# UPS safety — block suspend/hibernate when on battery and charge ≤ 50% (same policy as rofi-power-menu.sh)
ups_safe_to_suspend() {
    command -v upsc &>/dev/null || return 0
    local ups_name
    ups_name=$(upsc -l 2>/dev/null | head -1)
    [[ -z "$ups_name" ]] && return 0

    local status charge
    status=$(upsc "$ups_name" ups.status 2>/dev/null)
    charge=$(upsc "$ups_name" battery.charge 2>/dev/null)

    if [[ "$status" == *OB* ]] && [[ "$charge" =~ ^[0-9]+$ ]] && (( charge <= 50 )); then
        notify-send -u critical "Power" \
            "UPS battery at ${charge}% on battery power. Suspend/hibernate blocked — shutting down safely instead." \
            -i system-shutdown 2>/dev/null || true
        return 1
    fi
    return 0
}

cmd="${1:-}"
case "$cmd" in
    suspend|sleep)
        ups_safe_to_suspend || exec systemctl poweroff
        exec systemctl suspend
        ;;
    hibernate)
        ups_safe_to_suspend || exec systemctl poweroff
        exec systemctl hibernate
        ;;
    reboot|restart)
        exec systemctl reboot
        ;;
    poweroff|shutdown)
        exec systemctl poweroff
        ;;
    *)
        echo "Usage: $0 suspend | hibernate | reboot | poweroff" >&2
        exit 1
        ;;
esac
