#!/bin/bash
# Screenshot Manager - saves to /Vault/Pictures/Screenshots

SAVE_DIR="/Vault/Pictures/Screenshots"
mkdir -p "$SAVE_DIR"
timestamp=$(date +"%Y-%m-%d_%H-%M-%S")

case "${1#--}" in
    "full")
        filename="$SAVE_DIR/fullscreen_$timestamp.png"
        grim "$filename"
        wl-copy < "$filename"
        notify-send "📸 Screenshot" "Full screen saved\nCopied to clipboard" -t 3000
        ;;
    "area")
        filename="$SAVE_DIR/area_$timestamp.png"
        grim -g "$(slurp)" "$filename"
        wl-copy < "$filename"
        notify-send "📸 Screenshot" "Area saved\nCopied to clipboard" -t 3000
        ;;
    "window")
        filename="$SAVE_DIR/window_$timestamp.png"
        grim -g "$(hyprctl activewindow -j | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')" "$filename"
        wl-copy < "$filename"
        notify-send "📸 Screenshot" "Window saved\nCopied to clipboard" -t 3000
        ;;
    "edit")
        tmpfile="/tmp/screenshot-edit-$timestamp.png"
        outfile="$SAVE_DIR/edit_$timestamp.png"
        grim -g "$(slurp)" "$tmpfile" && \
            swappy -f "$tmpfile" -o "$outfile" && \
            wl-copy < "$outfile" && \
            notify-send "✏️ Screenshot" "Edited screenshot saved" -t 3000
        rm -f "$tmpfile"
        ;;
    "menu"|*)
        choice=$(echo -e "📱 Full Screen\n🖱️ Select Area\n🪟 Active Window\n✏️ Capture & Edit\n📁 Open Folder" | \
            rofi -dmenu -i \
            -theme ~/.config/rofi/themes/hacker-theme.rasi \
            -p "SCREENSHOT>")
        case "$choice" in
            "📱 Full Screen")   bash "$0" full ;;
            "🖱️ Select Area")   bash "$0" area ;;
            "🪟 Active Window") bash "$0" window ;;
            "✏️ Capture & Edit") bash "$0" edit ;;
            "📁 Open Folder")   xdg-open "$SAVE_DIR" & ;;
        esac
        ;;
esac
