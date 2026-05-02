#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Matugen / theme consumers read this path (update matugen.toml outputs if you move it).
QS_JSON="$HOME/.config/hypr/matugen/qs_colors.json"

# ------------------------------------------------------------------------------
# 1. Flatten Matugen v4.0 nested JSON for flat consumers (AGS, scripts, etc.)
# ------------------------------------------------------------------------------
if [[ -f "$QS_JSON" ]]; then
python3 -c '
import json
import sys

def flatten_colors(obj):
    if isinstance(obj, dict):
        if "color" in obj and isinstance(obj["color"], str):
            return obj["color"]
        return {k: flatten_colors(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [flatten_colors(x) for x in obj]
    return obj

target_file = sys.argv[1]
try:
    with open(target_file, "r") as f:
        data = json.load(f)
    flat_data = flatten_colors(data)
    with open(target_file, "w") as f:
        json.dump(flat_data, f, indent=4)
except FileNotFoundError:
    pass
except Exception as e:
    print(f"Error flattening JSON: {e}")
' "$QS_JSON"
fi

python3 "$SCRIPT_DIR/render_hyprlock_from_qs_colors.py" 2>/dev/null || true

# ------------------------------------------------------------------------------
# 2. Flatten {"color": "#hex"} wrappers in text configs
# ------------------------------------------------------------------------------
TEXT_FILES=(
    "$QS_JSON"
    "$HOME/.config/kitty/kitty-matugen-colors.conf"
    "$HOME/.config/nvim/matugen_colors.lua"
    "$HOME/.config/cava/colors"
    "$HOME/.config/swayosd/style.css"
    "$HOME/.config/rofi/theme.rasi"
    "$HOME/.cache/matugen/colors-gtk.css"
    "$HOME/.config/qt5ct/colors/matugen.conf"
    "$HOME/.config/qt6ct/colors/matugen.conf"
    "$HOME/.config/qt5ct/qss/matugen-style.qss"
    "$HOME/.config/qt6ct/qss/matugen-style.qss"
)

for file in "${TEXT_FILES[@]}"; do
    if [ -f "$file" ] && [ -w "$file" ]; then
        sed -i -E 's/\{[[:space:]]*"color":[[:space:]]*"([^"]+)"[[:space:]]*\}/\1/g' "$file"
    elif [ -f "$file" ]; then
        echo "Warning: No write permission for $file (Skipping text clean-up)"
    fi
done

# ------------------------------------------------------------------------------
# 2b. Hyprland accent borders + shadow from qs_colors (no full config reload)
# ------------------------------------------------------------------------------
if command -v jq &>/dev/null && command -v hyprctl &>/dev/null && hyprctl version &>/dev/null; then
	if [[ -f "$QS_JSON" ]]; then
		_strip() { echo "${1//#/}"; }
		_blue=$(_strip "$(jq -r '.blue // empty' "$QS_JSON")")
		_inact=$(_strip "$(jq -r '.surface2 // .overlay0 // empty' "$QS_JSON")")
		_shadow=$(_strip "$(jq -r '.crust // .mantle // empty' "$QS_JSON")")
		[[ ${#_blue} -ge 6 ]] && hyprctl keyword general:col.active_border "rgba(${_blue:0:6}ee)" &>/dev/null
		[[ ${#_inact} -ge 6 ]] && hyprctl keyword general:col.inactive_border "rgba(${_inact:0:6}aa)" &>/dev/null
		[[ ${#_shadow} -ge 6 ]] && hyprctl keyword decoration:shadow:color "rgba(${_shadow:0:6}ee)" &>/dev/null
	fi
fi

# ------------------------------------------------------------------------------
# 3. Reload system components
# ------------------------------------------------------------------------------
if [[ -f "$QS_JSON" ]]; then
    python3 - "$QS_JSON" "$HOME/.config/kitty/kitty-matugen-colors.conf" << 'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    c = json.load(f)
def col(k, fallback="#000000"):
    v = c.get(k, fallback)
    return v if isinstance(v, str) else v.get("color", fallback)
lines = [
    f"background {col('base')}",
    f"foreground {col('text')}",
    f"selection_background {col('surface2')}",
    f"selection_foreground {col('text')}",
    f"cursor {col('blue')}",
    f"cursor_text_color {col('base')}",
    f"url_color {col('sapphire')}",
    f"color0  {col('crust')}",
    f"color1  {col('red')}",
    f"color2  {col('green')}",
    f"color3  {col('yellow')}",
    f"color4  {col('blue')}",
    f"color5  {col('mauve')}",
    f"color6  {col('teal')}",
    f"color7  {col('subtext1')}",
    f"color8  {col('surface2')}",
    f"color9  {col('red')}",
    f"color10 {col('green')}",
    f"color11 {col('peach')}",
    f"color12 {col('sapphire')}",
    f"color13 {col('pink')}",
    f"color14 {col('teal')}",
    f"color15 {col('text')}",
]
with open(sys.argv[2], 'w') as f:
    f.write('\n'.join(lines) + '\n')
PYEOF
fi

if command -v killall >/dev/null 2>&1; then
    killall -USR1 kitty 2>/dev/null || true
else
    pkill -USR1 kitty 2>/dev/null || true
fi

cat ~/.config/cava/config_base ~/.config/cava/colors > ~/.config/cava/config 2>/dev/null

if pgrep -x "cava" > /dev/null; then
    if command -v killall >/dev/null 2>&1; then
        killall -USR1 cava 2>/dev/null || true
    else
        pkill -USR1 cava 2>/dev/null || true
    fi
fi

if command -v killall >/dev/null 2>&1; then
    killall swayosd-server 2>/dev/null || true
else
    pkill swayosd-server 2>/dev/null || true
fi
swayosd-server --top-margin 0.06 --style "$HOME/.config/swayosd/style.css" > /dev/null 2>&1 &
disown

if command -v gsettings &> /dev/null; then
    gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita'
    sleep 0.05
    gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
    gsettings set org.gnome.desktop.interface color-scheme 'default'
    sleep 0.05
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
fi
