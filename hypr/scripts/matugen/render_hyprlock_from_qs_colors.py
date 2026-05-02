#!/usr/bin/env python3
"""Write hyprlock.matugen.conf from flat qs_colors.json (after matugen + flatten)."""
import json
import sys
from pathlib import Path

QS = Path.home() / ".config/hypr/matugen/qs_colors.json"
OUT = Path.home() / ".config/hypr/hyprlock.matugen.conf"
LOCK_BG = Path.home() / ".config/wallpaper-manager/lockscreen_blurred.jpg"
LOCK_BG_CACHED = Path.home() / ".config/wallpaper-manager/lock_background.png"


def hx(data: dict, key: str, default: str = "#ffffff") -> str:
    v = data.get(key) or default
    if isinstance(v, dict) and "color" in v:
        v = v["color"]
    return str(v).lstrip("#") if isinstance(v, str) else "ffffff"


def main() -> int:
    if not QS.is_file():
        return 0
    try:
        data = json.loads(QS.read_text())
    except (json.JSONDecodeError, OSError):
        return 0

    base = hx(data, "base", "#1e1e2e")
    text = hx(data, "text", "#cdd6f4")
    sub = hx(data, "subtext1", "#bac2de")
    blue = hx(data, "blue", "#89b4fa")
    err = hx(data, "red", "#f38ba8")
    warn = hx(data, "yellow", "#f9e2af")

    if LOCK_BG.is_file():
        lock_path = LOCK_BG
    elif LOCK_BG_CACHED.is_file():
        lock_path = LOCK_BG_CACHED
    else:
        lock_path = Path("/tmp/lock_bg.png")

    out = f"""# Generated from qs_colors.json — do not edit by hand

general {{
    hide_cursor = true
    no_fade_in = false
    grace = 0
    disable_loading_bar = true
}}

background {{
    monitor =
    path = {lock_path}
    color = rgba({base}ff)

    blur_passes = 0
    blur_size = 7
    noise = 0.0117
    contrast = 0.8000
    brightness = 0.5000
    vibrancy = 0.1696
    vibrancy_darkness = 0.0
}}

label {{
    monitor =
    text = cmd[update:1000] echo "$(date +"%H:%M:%S")"
    color = rgba({text}ff)
    font_size = 80
    font_family = JetBrainsMono Nerd Font Bold
    position = 0, 100
    halign = center
    valign = center
}}

label {{
    monitor =
    text = cmd[update:1000] echo "$(date +"%A, %B %d")"
    color = rgba({text}b3)
    font_size = 22
    font_family = JetBrainsMono Nerd Font
    position = 0, 30
    halign = center
    valign = center
}}

label {{
    monitor =
    text = cmd[update:60000] id -un
    color = rgba({sub}d9)
    font_size = 16
    font_family = JetBrainsMono Nerd Font
    position = 0, -120
    halign = center
    valign = center
}}

label {{
    monitor =
    text = cmd[update:86400000] echo "Enter password to unlock"
    color = rgba({sub}a6)
    font_size = 13
    font_family = JetBrainsMono Nerd Font
    position = 0, -88
    halign = center
    valign = center
}}

input-field {{
    monitor =
    size = 350, 45
    outline_thickness = 1
    dots_size = 0.25
    dots_spacing = 0.15
    dots_center = true
    dots_rounding = -1
    outer_color = rgba({blue}ee)
    inner_color = rgba(00000000)
    font_color = rgba({text}ff)
    fade_on_empty = false
    fade_timeout = 1000
    placeholder_text =
    hide_input = false
    rounding = 20
    check_color = rgba({warn}ff)
    fail_color = rgba({err}ff)
    fail_text = $FAIL <b>($ATTEMPTS)</b>
    fail_transition = 300
    capslock_color = -1
    numlock_color = -1
    bothlock_color = -1
    invert_numlock = false
    swap_font_color = false

    position = 0, -50
    halign = center
    valign = center
}}
"""
    try:
        OUT.write_text(out)
    except OSError as e:
        print(e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
