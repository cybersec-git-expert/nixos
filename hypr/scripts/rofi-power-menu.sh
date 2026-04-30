#!/usr/bin/env bash
# Rofi Power Menu — Hyprland
# Actions: Lock | Logout | Sleep | Hibernate | Restart | Shutdown
# Sleep/hibernate/reboot/poweroff go through power-action.sh (UPS policy + NixOS PATH).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POWER_ACTION="${SCRIPT_DIR}/power-action.sh"
ROFI_THEME="$HOME/.config/rofi/themes/hacker-theme.rasi"

notify_action() {
    notify-send -u "${2:-normal}" "Power Menu" "$1" -i system-shutdown
}

# Simple Yes / No confirmation
confirm_action() {
    local prompt="$1"
    local choice
    choice=$(printf '✅ Yes\n❌ No' | rofi -dmenu \
        -theme "$ROFI_THEME" \
        -p "$prompt" \
        -no-custom \
        -lines 2 \
        -width 380 \
        -location 0)
    [[ "$choice" == "✅ Yes" ]]
}

execute_action() {
    case "$1" in
        lock)
            notify_action "Locking screen..." "low"
            if [[ -x "$HOME/.config/hypr/scripts/hyprlock-with-wallpaper.sh" ]]; then
                "$HOME/.config/hypr/scripts/hyprlock-with-wallpaper.sh" &
            else
                hyprlock -c "$HOME/.config/hypr/hyprlock.matugen.conf" &
            fi
            ;;
        logout)
            confirm_action "Logout from Hyprland?" || { notify_action "Logout cancelled" "low"; return; }
            notify_action "Logging out..." "normal"
            sleep 1
            hyprctl dispatch exit
            ;;
        sleep)
            confirm_action "Suspend (Sleep) the system?" || { notify_action "Suspend cancelled" "low"; return; }
            notify_action "Suspending..." "normal"
            execute_action lock
            sleep 1
            if ! "$POWER_ACTION" suspend; then
                notify_action "Suspend failed — check logind / power permissions" "critical"
                return
            fi
            ;;
        hibernate)
            confirm_action "Hibernate the system?" || { notify_action "Hibernate cancelled" "low"; return; }
            notify_action "Hibernating..." "normal"
            execute_action lock
            sleep 1
            if ! "$POWER_ACTION" hibernate; then
                notify_action "Hibernate failed — check swap, resume= kernel param, and boot.resumeDevice" "critical"
                return
            fi
            ;;
        restart)
            confirm_action "Restart the system?" || { notify_action "Restart cancelled" "low"; return; }
            notify_action "Restarting..." "critical"
            sleep 1
            "$POWER_ACTION" reboot || { notify_action "Reboot failed — check logind / power permissions" "critical"; return; }
            ;;
        shutdown)
            confirm_action "Shut down the system?" || { notify_action "Shutdown cancelled" "low"; return; }
            notify_action "Shutting down..." "critical"
            sleep 1
            "$POWER_ACTION" poweroff || { notify_action "Shutdown failed — check logind / power permissions" "critical"; return; }
            ;;
        cancel)
            exit 0
            ;;
    esac
}

show_power_menu() {
    local chosen
    chosen=$(printf \
        '🔒 Lock\n🚪 Logout\n💤 Sleep\n❄️ Hibernate\n🔄 Restart\n⏻ Shutdown\n❌ Cancel' \
        | rofi -dmenu \
            -theme "$ROFI_THEME" \
            -p "Power Menu" \
            -mesg "Choose your action" \
            -no-custom \
            -lines 7 \
            -width 300 \
            -location 0)

    case "$chosen" in
        "🔒 Lock")       execute_action lock ;;
        "🚪 Logout")     execute_action logout ;;
        "💤 Sleep")      execute_action sleep ;;
        "❄️ Hibernate")  execute_action hibernate ;;
        "🔄 Restart")    execute_action restart ;;
        "⏻ Shutdown")   execute_action shutdown ;;
        "❌ Cancel"|"")  exit 0 ;;
    esac
}

main() {
    case "${1:-}" in
        -l|--lock)      execute_action lock ;;
        -o|--logout)    execute_action logout ;;
        -s|--sleep)     execute_action sleep ;;
        -H|--hibernate) execute_action hibernate ;;
        -r|--restart)   execute_action restart ;;
        -p|--shutdown)  execute_action shutdown ;;
        "")             show_power_menu ;;
        *)  echo "Usage: $0 [-l|-o|-s|-H|-r|-p]"; exit 1 ;;
    esac
}

main "$@"
