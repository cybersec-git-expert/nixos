#!/usr/bin/env bash

# ============================================================================
# 1. ZOMBIE PREVENTION
# Kills any older instances of this script. When Quickshell reloads, 
# it can leave the old listener pipelines running in the background infinitely.
# ============================================================================
for pid in $(pgrep -f "quickshell/workspaces.sh"); do
    if [ "$pid" != "$$" ] && [ "$pid" != "$PPID" ]; then
        kill -9 "$pid" 2>/dev/null
    fi
done

# Cleanly kill immediate children (like socat) when the script exits normally
cleanup() {
    pkill -P $$ 2>/dev/null
}
trap cleanup EXIT SIGTERM SIGINT

# --- Special Cleanup for Network/Bluetooth ---
# The network toggle starts a background bluetooth scan that must be killed explicitly.
BT_PID_FILE="$HOME/.cache/bt_scan_pid"

if [ -f "$BT_PID_FILE" ]; then
    kill $(cat "$BT_PID_FILE") 2>/dev/null
    rm -f "$BT_PID_FILE"
fi

# Ensure bluetooth scan is explicitly turned off (timeout prevents deadlocks on fresh installs)
(timeout 2 bluetoothctl scan off > /dev/null 2>&1) &
# ---------------------------------------------

# Configuration: Parse from settings.json dynamically, fallback to 8
SETTINGS_FILE="$HOME/.config/hypr/settings.json"
WS_AUTO=$(jq -r '.workspaceCountAuto // false' "$SETTINGS_FILE" 2>/dev/null)
WS_STATIC=$(jq -r '.workspaceCount // 8' "$SETTINGS_FILE" 2>/dev/null)
# Sanity check — if the JSON parse failed or the value isn't an int, fall back.
if ! [[ "$WS_STATIC" =~ ^[0-9]+$ ]]; then
    WS_STATIC=8
fi

# In auto mode keep a small floor so the bar never collapses to a single pip
# when only workspace 1 is active; the ceiling grows to match whichever
# workspace is currently occupied/focused.
WS_AUTO_FLOOR=1

# Compute the desired sequence end for *this* refresh:
#   - static mode: the user-picked count
#   - auto mode: max(active id, highest occupied id, floor)
compute_seq_end() {
    local spaces="$1" active="$2"
    if [ "$WS_AUTO" != "true" ]; then
        echo "$WS_STATIC"
        return
    fi
    local max_ws
    max_ws=$(echo "$spaces" | jq --argjson a "$active" --argjson floor "$WS_AUTO_FLOOR" -r '
        ([ .[] | select(.id > 0) | .id ] + [$a, $floor]) | max
    ' 2>/dev/null)
    if ! [[ "$max_ws" =~ ^[0-9]+$ ]] || [ "$max_ws" -lt "$WS_AUTO_FLOOR" ]; then
        max_ws=$WS_AUTO_FLOOR
    fi
    echo "$max_ws"
}

print_workspaces() {
    # Get raw data with a timeout fallback
    spaces=$(timeout 2 hyprctl workspaces -j 2>/dev/null)
    active=$(timeout 2 hyprctl activeworkspace -j 2>/dev/null | jq '.id')

    # Failsafe if hyprctl crashes to prevent jq from outputting errors
    if [ -z "$spaces" ] || [ -z "$active" ]; then return; fi

    # Seq end is recomputed every tick so auto-mode follows Hyprland live.
    SEQ_END=$(compute_seq_end "$spaces" "$active")

    # Generate the JSON and write it atomically to prevent UI flickering
    echo "$spaces" | jq --unbuffered --argjson a "$active" --arg end "$SEQ_END" -c '
        # Create a map of workspace ID -> workspace data for easy lookup
        (map( { (.id|tostring): . } ) | add) as $s
        |
        # Iterate from 1 to SEQ_END
        [range(1; ($end|tonumber) + 1)] | map(
            . as $i |
            # Determine state: active -> occupied -> empty
            (if $i == $a then "active"
             elif ($s[$i|tostring] != null and $s[$i|tostring].windows > 0) then "occupied"
             else "empty" end) as $state |

            # Get window title for tooltip (if exists)
            (if $s[$i|tostring] != null then $s[$i|tostring].lastwindowtitle else "Empty" end) as $win |

            {
                id: $i,
                state: $state,
                tooltip: $win
            }
        )
    ' > /tmp/qs_workspaces.tmp
    
    mv /tmp/qs_workspaces.tmp /tmp/qs_workspaces.json
}

# Print initial state
print_workspaces

# ============================================================================
# 2. THE EVENT DEBOUNCER
# Listen to Hyprland socket wrapped in an infinite loop
# ============================================================================
while true; do
    socat -u UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock - | while read -r line; do
        case "$line" in
            workspace*|focusedmon*|activewindow*|createwindow*|closewindow*|movewindow*|destroyworkspace*)
                
                # -> THE FIX <-
                # Hyprland emits HUNDREDS of events a second when you move/resize windows.
                # This reads and discards all subsequent events arriving within a 50ms window.
                # It bundles the storm into a single UI update, completely preventing CPU clogging!
                while read -t 0.05 -r extra_line; do
                    continue
                done

                print_workspaces
                ;;
        esac
    done
    sleep 1
done
