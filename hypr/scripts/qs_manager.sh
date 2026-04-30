#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# CONSTANTS & ARGUMENTS
# -----------------------------------------------------------------------------
QS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BT_PID_FILE="$HOME/.cache/bt_scan_pid"
BT_SCAN_LOG="$HOME/.cache/bt_scan.log"
SRC_DIR="${WALLPAPER_DIR:-${srcdir:-/Vault/Pictures/Wallpapers}}"
THUMB_DIR="$HOME/.cache/wallpaper_picker/thumbs"

# User-specific cache directory matching the QML logic
QS_NETWORK_CACHE="${XDG_RUNTIME_DIR:-$HOME/.cache}/qs_network"
mkdir -p "$QS_NETWORK_CACHE"

IPC_FILE="/tmp/qs_widget_state"
NETWORK_MODE_FILE="$QS_NETWORK_CACHE/mode"

ACTION="$1"
TARGET="$2"
SUBTARGET="$3"

MAIN_QML_PATH="$HOME/.config/hypr/scripts/quickshell/Main.qml"
BAR_QML_PATH="$HOME/.config/hypr/scripts/quickshell/TopBar.qml"
QS_BIN="${QUICKSHELL_BIN:-/usr/bin/quickshell}"

# Prefer qs ipc → Main.qml IpcHandler.dispatchFromWidget (no missed inotify events).
# quickshell may exit 0 even when the IPC method is missing; treat that as failure and
# fall back to the file path so the inotify watcher still opens the panel.
main_dispatch() {
    local line="$1"
    local i=0 out st
    while [ "$i" -lt 25 ]; do
        st=0
        out=$("$QS_BIN" -p "$MAIN_QML_PATH" ipc call main dispatchFromWidget "$line" 2>&1) || st=$?
        if [[ $st -eq 0 ]] && [[ "$out" != *"Function not found"* ]] && [[ "$out" != *"No running instances"* ]]; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "$line" > "$IPC_FILE"
}

# Stray second TopBar/Main (double autostart, raced qs_manager, manual + autostart) stacks two bars.
dedupe_quickshell_topbar_main() {
    local nb nm
    nb=$(pgrep -f "quickshell.*TopBar\\.qml" 2>/dev/null | wc -l)
    nb=${nb// /}
    nm=$(pgrep -f "quickshell.*Main\\.qml" 2>/dev/null | wc -l)
    nm=${nm// /}
    if [ "${nb:-0}" -gt 1 ]; then
        pkill -f "quickshell.*TopBar\\.qml" 2>/dev/null || true
        sleep 0.4
    fi
    if [ "${nm:-0}" -gt 1 ]; then
        pkill -f "quickshell.*Main\\.qml" 2>/dev/null || true
        sleep 0.4
    fi
}

dedupe_quickshell_topbar_main

if ! pgrep -f "quickshell.*Main\.qml" >/dev/null; then
    "$QS_BIN" -p "$MAIN_QML_PATH" >/dev/null 2>&1 &
    disown
fi
if ! pgrep -f "quickshell.*TopBar\.qml" >/dev/null; then
    "$QS_BIN" -p "$BAR_QML_PATH" >/dev/null 2>&1 &
    disown
fi

# -----------------------------------------------------------------------------
# FAST PATH: WORKSPACE SWITCHING
# -----------------------------------------------------------------------------
if [[ "$ACTION" =~ ^[0-9]+$ ]]; then
    WORKSPACE_NUM="$ACTION"
    main_dispatch "close"

    CMD="workspace $WORKSPACE_NUM"
    [[ "$2" == "move" ]] && CMD="movetoworkspace $WORKSPACE_NUM"
    hyprctl --batch "dispatch $CMD" >/dev/null 2>&1
    exit 0
fi

# -----------------------------------------------------------------------------
# PREP FUNCTIONS
# -----------------------------------------------------------------------------
handle_wallpaper_prep() {
    mkdir -p "$THUMB_DIR"
    
    # The lock is now inside the subshell. It stops duplicate thumbnailers,
    # but never blocks the main script from opening/closing the widget instantly.
    (
        LOCKFILE="/tmp/qs_manager_wallpaper.lock"
        exec 9> "$LOCKFILE"
        if ! flock -n 9; then
            exit 0
        fi

        for thumb in "$THUMB_DIR"/*; do
            [ -e "$thumb" ] || continue
            filename=$(basename "$thumb")
            clean_name="${filename#000_}"
            if [ ! -f "$SRC_DIR/$clean_name" ]; then rm -f "$thumb"; fi
        done

        for img in "$SRC_DIR"/*.{jpg,jpeg,png,webp,gif,mp4,mkv,mov,webm}; do
            [ -e "$img" ] || continue
            filename=$(basename "$img")
            extension="${filename##*.}"

            if [[ "${extension,,}" == "webp" ]]; then
                new_img="${img%.*}.jpg"
                magick "$img" "$new_img"
                rm -f "$img"
                img="$new_img"
                filename=$(basename "$img")
                extension="jpg"
            fi

            if [[ "${extension,,}" =~ ^(mp4|mkv|mov|webm)$ ]]; then
                thumb="$THUMB_DIR/000_$filename"
                [ -f "$THUMB_DIR/$filename" ] && rm -f "$THUMB_DIR/$filename"
                if [ ! -f "$thumb" ]; then
                     ffmpeg -y -ss 00:00:05 -i "$img" -vframes 1 -f image2 -q:v 2 "$thumb" > /dev/null 2>&1
                fi
            else
                thumb="$THUMB_DIR/$filename"
                if [ ! -f "$thumb" ]; then
                    magick "$img" -resize x420 -quality 70 "$thumb"
                fi
            fi
        done
    ) &

    TARGET_THUMB=""
    CURRENT_SRC=""

    if pgrep -a "mpvpaper" > /dev/null; then
        CURRENT_SRC=$(pgrep -a mpvpaper | grep -o "$SRC_DIR/[^' ]*" | head -n1)
        [ -n "$CURRENT_SRC" ] && CURRENT_SRC=$(basename "$CURRENT_SRC")
    fi

    if [ -z "$CURRENT_SRC" ] && command -v swww >/dev/null; then
        CURRENT_SRC=$(swww query 2>/dev/null | grep -o "$SRC_DIR/[^ ]*" | head -n1)
        [ -n "$CURRENT_SRC" ] && CURRENT_SRC=$(basename "$CURRENT_SRC")
    fi

    if [ -n "$CURRENT_SRC" ]; then
        EXT="${CURRENT_SRC##*.}"
        if [[ "${EXT,,}" =~ ^(mp4|mkv|mov|webm)$ ]]; then
            TARGET_THUMB="000_$CURRENT_SRC"
        else
            TARGET_THUMB="$CURRENT_SRC"
        fi
    fi
    
    export WALLPAPER_THUMB="$TARGET_THUMB"
}

handle_network_prep() {
    echo "" > "$BT_SCAN_LOG"
    { echo "scan on"; sleep infinity; } | stdbuf -oL bluetoothctl > "$BT_SCAN_LOG" 2>&1 &
    echo $! > "$BT_PID_FILE"
    (nmcli device wifi rescan) &
}

# -----------------------------------------------------------------------------
# IPC ROUTING
# -----------------------------------------------------------------------------
if [[ "$ACTION" == "close" ]]; then
    main_dispatch "close"
    if [[ "$TARGET" == "network" || "$TARGET" == "all" || -z "$TARGET" ]]; then
        if [ -f "$BT_PID_FILE" ]; then
            kill $(cat "$BT_PID_FILE") 2>/dev/null
            rm -f "$BT_PID_FILE"
        fi
        (bluetoothctl scan off > /dev/null 2>&1) &
    fi
    exit 0
fi

if [[ "$ACTION" == "open" || "$ACTION" == "toggle" ]]; then
    CURRENT_MODE=$(cat "$NETWORK_MODE_FILE" 2>/dev/null)

    if [[ "$TARGET" == "network" ]]; then
        handle_network_prep
        [[ -n "$SUBTARGET" ]] && echo "$SUBTARGET" > "$NETWORK_MODE_FILE"
        main_dispatch "$ACTION:$TARGET:${SUBTARGET:-}"
        exit 0
    fi

    if [[ "$TARGET" == "wallpaper" ]]; then
        handle_wallpaper_prep
        main_dispatch "$ACTION:$TARGET:${WALLPAPER_THUMB:-}"
    else
        main_dispatch "$ACTION:$TARGET:${SUBTARGET:-}"
    fi
    exit 0
fi
