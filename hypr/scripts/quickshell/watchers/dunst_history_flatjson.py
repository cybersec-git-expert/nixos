#!/usr/bin/env python3
"""Emit a JSON array of flat notifications for Quickshell (dunst history fallback)."""
import json
import subprocess
import sys


def compute_section_key(app_name: str, body: str, category: str) -> str:
    a = (app_name or "").lower()
    b = (body or "").lower()
    c = (category or "").lower()
    if c and any(x in c for x in ("im", "message", "email")):
        return "messaging"
    if "whatsapp" in a or "web.whatsapp" in b or "whatsapp" in b:
        return "messaging"
    if any(x in a for x in ("telegram", "signal", "discord", "slack", "element")):
        return "messaging"
    if a == "system" or "packagekit" in a or "pamac" in a:
        return "system"
    if any(x in a for x in ("spotify", "mpv", "vlc")):
        return "media"
    if any(x in a for x in ("brave", "chrome", "chromium", "firefox", "zen")):
        return "web"
    if any(x in a for x in ("code", "cursor", "obsidian")):
        return "work"
    return "other"


def section_label_from_key(key: str) -> str:
    return {
        "messaging": "Messaging & chat",
        "system": "System & devices",
        "web": "Browser",
        "work": "Productivity",
        "media": "Media",
        "other": "Other",
    }.get(key, "Other")


def main() -> None:
    try:
        raw = subprocess.check_output(["dunstctl", "history"], text=True, timeout=3, stderr=subprocess.DEVNULL)
    except (subprocess.CalledProcessError, FileNotFoundError, OSError):
        print("[]")
        return
    try:
        j = json.loads(raw)
    except json.JSONDecodeError:
        print("[]")
        return
    out = []
    groups = j.get("data") or []
    if not groups:
        print("[]")
        return
    for item in groups[0] if isinstance(groups[0], list) else []:
        if not isinstance(item, dict):
            continue

        def gv(k: str) -> str:
            v = item.get(k)
            if isinstance(v, dict) and "data" in v:
                return str(v.get("data") or "")
            return str(v) if v is not None else ""

        id_raw = item.get("id", {})
        did = -1
        if isinstance(id_raw, dict) and "data" in id_raw:
            try:
                did = int(id_raw.get("data"))
            except (TypeError, ValueError):
                did = -1

        app = gv("appname") or "System"
        body = gv("body") or ""
        cat = gv("category") or ""
        sk = compute_section_key(app, body, cat)
        out.append(
            {
                "appName": app,
                "summary": gv("summary") or "Notification",
                "body": body,
                "iconPath": gv("icon_path") or "",
                "image": "",
                "sectionKey": sk,
                "sectionLabel": section_label_from_key(sk),
                "dunstCategory": cat,
                "dunstId": did,
            }
        )
    print(json.dumps(out, ensure_ascii=False))


if __name__ == "__main__":
    main()
    sys.stdout.flush()
