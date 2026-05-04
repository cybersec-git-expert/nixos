#!/usr/bin/env bash
# Shared power actions for Rofi menu, hyprlock (Quickshell Lock.qml), keybinds, etc.
# Uses systemctl as your user (logind + Polkit). NixOS: allow wheel in security.polkit.extraConfig
# so suspend/hibernate are not blocked. Do not use `sudo systemctl hibernate` with Hyprland —
# it runs as root and often freezes then aborts without completing hibernate.
set -euo pipefail
PATH="${PATH}:/run/current-system/sw/bin:/usr/bin:/bin"
SYSTEMCTL="/run/current-system/sw/bin/systemctl"

# Hibernate needs enough *swap* to hold the RAM image. If swap < RAM, the kernel usually
# aborts mid-way: screens go dark, then the session resumes and hypridle’s after_sleep_cmd
# turns monitors back on — looks like “PC never powered off” / “woke by itself”.
hibernate_preflight() {
    local mem_kb swap_kb
    mem_kb=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
    swap_kb=$(awk '/^SwapTotal:/{print $2}' /proc/meminfo)
    if (( swap_kb == 0 )); then
        notify-send -u critical "Hibernate" \
            "No swap (SwapTotal=0). NixOS needs a real swap partition (or file) sized ≥ RAM for hibernate." \
            -i system-shutdown 2>/dev/null || true
        return 1
    fi
    if (( swap_kb < mem_kb )); then
        notify-send -u critical "Hibernate" \
            "Swap (${swap_kb} KiB) is smaller than RAM (${mem_kb} KiB). Hibernate usually aborts; enlarge swap or use Suspend." \
            -i system-shutdown 2>/dev/null || true
        return 1
    fi
    return 0
}

# UPS safety — block suspend/hibernate when on battery and charge ≤ 50%
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
        ups_safe_to_suspend || exec "$SYSTEMCTL" poweroff
        exec "$SYSTEMCTL" suspend
        ;;
    hibernate)
        ups_safe_to_suspend || exec "$SYSTEMCTL" poweroff
        hibernate_preflight || exit 1
        exec "$SYSTEMCTL" hibernate
        ;;
    reboot|restart)
        exec "$SYSTEMCTL" reboot
        ;;
    poweroff|shutdown)
        exec "$SYSTEMCTL" poweroff
        ;;
    *)
        echo "Usage: $0 suspend | hibernate | reboot | poweroff" >&2
        exit 1
        ;;
esac
