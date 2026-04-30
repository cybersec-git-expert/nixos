#!/usr/bin/env bash
# Parses the user's Hyprland config and emits a JSON array describing every
# `bind*` line in a human-friendly form for the Quickshell Guide panel.
#
# Output schema: [{ k1, k2, action, cmd }, ...]
#   k1 — modifier keys as they appear in the binding (e.g. "SUPER", "SUPER+SHIFT")
#   k2 — primary key (e.g. "RETURN", "D"), empty string when there is no second key
#   action — short human title derived from the dispatcher + arguments
#   cmd — the raw command, so the guide can still "Click to execute"
#
# Works with bindd/bindl/bindm variants too. Resolves $mainMod and any other
# `$var = ...` aliases declared earlier in the file.

set -euo pipefail

HYPR_CONF="${1:-$HOME/.config/hypr/hyprland.conf}"

if [[ ! -r "$HYPR_CONF" ]]; then
    echo "[]"
    exit 0
fi

python3 - "$HYPR_CONF" <<'PY'
import json
import os
import re
import sys

cfg = sys.argv[1]

# First pass: collect `source = ...` includes and `$var = ...` aliases.
vars_ = {}
files = [cfg]
seen = set()

def expand(path):
    # Hyprland supports ~ and env vars; keep it simple.
    return os.path.expandvars(os.path.expanduser(path.strip()))

COMMENT_STRIP = re.compile(r"(?<!\\)\s+#.*$")  # strip trailing "... # comment"

def strip_comment(s):
    # Hyprland treats `#` as a comment marker. Strip everything from `#` onward
    # unless it is at the very start (full-line comment already filtered).
    return COMMENT_STRIP.sub("", s).rstrip()

def load_file(p, depth=0):
    if depth > 5 or p in seen or not os.path.isfile(p):
        return []
    seen.add(p)
    out = []
    with open(p, errors="ignore") as f:
        for raw in f:
            line = raw.rstrip("\n")
            stripped = line.strip()
            if stripped.startswith("#") or not stripped:
                continue
            stripped = strip_comment(stripped)
            if not stripped:
                continue
            m = re.match(r"^source\s*=\s*(.+)$", stripped)
            if m:
                inc = expand(m.group(1))
                if not os.path.isabs(inc):
                    inc = os.path.join(os.path.dirname(p), inc)
                out.extend(load_file(inc, depth + 1))
                continue
            m = re.match(r"^\$(\w+)\s*=\s*(.+)$", stripped)
            if m:
                vars_[m.group(1)] = m.group(2).strip()
                continue
            out.append(stripped)
    return out

all_lines = load_file(cfg)

def resolve(s):
    # Repeatedly expand $var references (e.g. $mainMod, $fileManager).
    for _ in range(5):
        def sub(m):
            name = m.group(1)
            return vars_.get(name, m.group(0))
        new = re.sub(r"\$(\w+)", sub, s)
        if new == s:
            break
        s = new
    return s

# Friendly labels for common dispatchers and common exec targets.
DISPATCH_LABELS = {
    "killactive":        "Close Active Window",
    "togglefloating":    "Toggle Floating",
    "togglesplit":       "Toggle Split",
    "fullscreen":        "Toggle Fullscreen",
    "fullscreenstate":   "Cycle Fullscreen",
    "pin":               "Pin Window",
    "centerwindow":      "Center Window",
    "movefocus":         "Move Focus",
    "movewindow":        "Move Window",
    "swapwindow":        "Swap Window",
    "resizeactive":      "Resize Window",
    "workspace":         "Switch Workspace",
    "movetoworkspace":   "Move Window to Workspace",
    "movetoworkspacesilent": "Move Window to Workspace (silent)",
    "togglespecialworkspace": "Toggle Scratchpad",
    "cyclenext":         "Cycle Windows",
    "focuscurrentorlast":"Focus Last Window",
    "exit":              "Exit Hyprland",
}

EXEC_HINTS = [
    (re.compile(r"\b(kitty|alacritty|foot|wezterm|gnome-terminal|konsole)\b"), "Open Terminal"),
    (re.compile(r"\bsafe-terminal\.sh\b"), "Open Terminal"),
    (re.compile(r"\bbetter-dropdown\.sh\b"), "Dropdown Terminal"),
    (re.compile(r"\brofi .*?-show\s+drun\b"), "App Launcher"),
    (re.compile(r"\brofi .*?-show\s+window\b"), "Window Switcher"),
    (re.compile(r"\brofi-power-menu\b"), "Power Menu"),
    (re.compile(r"\brofi-.*clipboard\b|cliphist"), "Clipboard History"),
    (re.compile(r"\bfirefox\b"), "Open Firefox"),
    (re.compile(r"\bbrave\b"), "Open Brave"),
    (re.compile(r"\bchromium|google-chrome\b"), "Open Browser"),
    (re.compile(r"\bdolphin\b"), "Open File Manager (Dolphin)"),
    (re.compile(r"\bnautilus\b"), "Open File Manager (Nautilus)"),
    (re.compile(r"\bthunar\b"), "Open File Manager (Thunar)"),
    (re.compile(r"\bnemo\b"),    "Open File Manager (Nemo)"),
    (re.compile(r"\bhyprlock\b|\block\.sh\b"), "Lock Screen"),
    (re.compile(r"\bhyprctl\s+reload\b"), "Reload Hyprland"),
    (re.compile(r"\bbtop\b"), "Open System Monitor"),
    (re.compile(r"\bobsidian\b"), "Open Obsidian"),
    (re.compile(r"\bscreenshot.*area"), "Screenshot (Area)"),
    (re.compile(r"\bscreenshot.*menu"), "Screenshot (Menu)"),
    (re.compile(r"\bscreenshot.*full"), "Screenshot (Full)"),
    (re.compile(r"\bscreenshot"), "Screenshot"),
    (re.compile(r"\bswaync-client\b"), "Toggle Notifications"),
    (re.compile(r"\bapply-matugen\b"), "Refresh Matugen Theme"),
    (re.compile(r"quickshell-panel\.sh\s+toggle\s+(\w+)"), None),  # special
    (re.compile(r"qs_manager\.sh\s+toggle\s+(\w+)"), None),          # special
    (re.compile(r"playerctl-mediakey\.sh\s+play-pause"), "Play / Pause Media (active source)"),
    (re.compile(r"playerctl-mediakey\.sh\s+next"), "Next Track (active source)"),
    (re.compile(r"playerctl-mediakey\.sh\s+previous"), "Previous Track (active source)"),
    (re.compile(r"playerctl\s+play-pause"), "Play / Pause Media"),
    (re.compile(r"playerctl\s+next"), "Next Track"),
    (re.compile(r"playerctl\s+previous"), "Previous Track"),
    (re.compile(r"swayosd-client --output-volume raise|\bpamixer -i"), "Volume Up"),
    (re.compile(r"swayosd-client --output-volume lower|\bpamixer -d"), "Volume Down"),
    (re.compile(r"swayosd-client --output-volume mute-toggle|\bpamixer -t"), "Toggle Mute"),
    (re.compile(r"swayosd-client --input-volume mute-toggle|\bpamixer --default-source -t"), "Toggle Mic Mute"),
    (re.compile(r"swayosd-client --brightness raise|\bbrightnessctl .*\+"), "Brightness Up"),
    (re.compile(r"swayosd-client --brightness lower|\bbrightnessctl .*\-"), "Brightness Down"),
]

PANEL_LABELS = {
    "calendar": "Toggle Calendar",
    "wallpaper": "Toggle Wallpaper Picker",
    "music": "Toggle Music",
    "volume": "Toggle Volume",
    "network": "Toggle Network",
    "focustime": "Toggle Focus Timer",
    "timer": "Toggle Pomodoro Timer",
    "notifications": "Toggle Notification Center",
    "guide": "Toggle Guide",
    "monitors": "Toggle Monitors",
    "battery": "Toggle Battery",
    "settings": "Toggle Settings",
    "close": "Close Active Panel",
}

def friendly_action(dispatcher, args):
    dispatcher = (dispatcher or "").strip()
    args = (args or "").strip()

    if dispatcher == "exec":
        for rx, label in EXEC_HINTS:
            m = rx.search(args)
            if not m:
                continue
            if label is None:
                slot = m.group(1)
                return PANEL_LABELS.get(slot, f"Toggle {slot.title()}")
            return label
        # Fallback: use first word of the exec argument as the label.
        first = args.split()[0] if args else "exec"
        return f"Run {os.path.basename(first)}"

    if dispatcher == "workspace":
        return f"Switch to Workspace {args.strip()}"
    if dispatcher in ("movetoworkspace", "movetoworkspacesilent"):
        return f"Move Window to Workspace {args.strip()}"

    return DISPATCH_LABELS.get(dispatcher, dispatcher.capitalize() if dispatcher else "Unbound")

# Normalize the modifier side (left of first comma) for the UI.
KEY_ALIASES = {
    "return": "RETURN",
    "print":  "PRINT",
    "escape": "ESC",
    "space":  "SPACE",
    "tab":    "TAB",
    "minus":  "-",
    "plus":   "+",
    "equal":  "=",
    "slash":  "/",
    "semicolon": ";",
    "comma":  ",",
    "period": ".",
    "xf86audioraisevolume": "Vol+",
    "xf86audiolowervolume": "Vol-",
    "xf86audiomute":        "Mute",
    "xf86audiomicmute":     "MicMute",
    "xf86audioplay":        "Play",
    "xf86audionext":        "Next",
    "xf86audioprev":        "Prev",
    "xf86monbrightnessup":  "Bright+",
    "xf86monbrightnessdown":"Bright-",
}

def pretty_key(k):
    k = k.strip()
    if not k:
        return ""
    low = k.lower()
    if low in KEY_ALIASES:
        return KEY_ALIASES[low]
    if len(k) == 1:
        return k.upper()
    # Arrow keys
    if low in ("left", "right", "up", "down"):
        return low.capitalize()
    return k.upper()

def pretty_mods(mods):
    mods = mods.strip()
    if not mods:
        return ""
    parts = [p.strip() for p in re.split(r"\s+", mods) if p.strip()]
    return "+".join(p.upper() for p in parts)

# Match a bind line. Hyprland supports bind, bindd, bindl, bindr, bindm, binde, binde+, bindn, bind+ etc.
BIND_RE = re.compile(r"^\s*bind[a-z]*\s*=\s*(.+)$")

results = []

for raw in all_lines:
    m = BIND_RE.match(raw)
    if not m:
        continue
    payload = resolve(m.group(1)).strip()
    # Split into exactly 4 comma-separated fields: mods, key, dispatcher, args
    fields = [f.strip() for f in payload.split(",", 3)]
    if len(fields) < 3:
        continue
    mods, key = fields[0], fields[1]
    dispatcher = fields[2] if len(fields) >= 3 else ""
    args = fields[3] if len(fields) >= 4 else ""

    k1 = pretty_mods(mods) or pretty_key(key)
    k2 = pretty_key(key) if pretty_mods(mods) else ""
    # If mods were empty but key had modifier-like text (rare), push key to k1.
    if not k1:
        k1 = pretty_key(key)
        k2 = ""

    action = friendly_action(dispatcher, args)
    cmd = args if dispatcher == "exec" else f"hyprctl dispatch {dispatcher} {args}".strip()

    results.append({"k1": k1, "k2": k2, "action": action, "cmd": cmd})

# De-duplicate identical rows while preserving order.
seen_rows = set()
deduped = []
for r in results:
    key = (r["k1"], r["k2"], r["action"])
    if key in seen_rows:
        continue
    seen_rows.add(key)
    deduped.append(r)

json.dump(deduped, sys.stdout, ensure_ascii=False)
PY
