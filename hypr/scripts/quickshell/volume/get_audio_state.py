#!/usr/bin/env python3
import subprocess
import json
import re


def run_cmd(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL).decode("utf-8")
    except Exception:
        return ""


def coerce_json_list(raw):
    """pactl -f json list * usually returns a JSON array; some builds wrap it in an object."""
    raw = (raw or "").strip()
    if not raw:
        return []
    try:
        data = json.loads(raw)
    except Exception:
        return []
    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        for k in (
            "sinks",
            "sources",
            "sink_inputs",
            "sink-inputs",
            "sinkInputs",
            "Sink Inputs",
        ):
            v = data.get(k)
            if isinstance(v, list):
                return v
    return []


def get_defaults():
    info_raw = run_cmd("pactl -f json info")
    if not info_raw.strip():
        return "", ""
    try:
        info = json.loads(info_raw)
        if isinstance(info, dict):
            return (
                str(info.get("default_sink_name", "") or ""),
                str(info.get("default_source_name", "") or ""),
            )
    except Exception:
        pass
    return "", ""


def get_valid_string(*args):
    for arg in args:
        if arg and str(arg).strip().lower() not in ["null", "none", ""]:
            return str(arg)
    return ""


def format_node(n, default_name="", is_app=False, force_default=False):
    vol = 0
    if "volume" in n and isinstance(n["volume"], dict):
        if "front-left" in n["volume"]:
            vol = int(n["volume"]["front-left"].get("value_percent", "0%").strip("%"))
        elif "mono" in n["volume"]:
            vol = int(n["volume"]["mono"].get("value_percent", "0%").strip("%"))

    props = n.get("properties", {}) or {}

    if is_app:
        display_name = get_valid_string(
            props.get("application.name"),
            props.get("application.process.binary"),
            "Unknown App",
        )
        sub_desc = get_valid_string(
            props.get("media.name"),
            props.get("window.title"),
            props.get("media.role"),
            "Audio Stream",
        )
    else:
        display_name = get_valid_string(
            props.get("device.description"),
            n.get("name"),
            "Unknown Device",
        )
        sub_desc = get_valid_string(n.get("name"), "Unknown")

    icon = get_valid_string(
        props.get("application.icon_name"),
        props.get("device.icon_name"),
        "audio-card",
    )

    is_default = bool(force_default or (default_name and n.get("name") == default_name))

    return {
        "id": str(n.get("index")),
        "name": sub_desc,
        "description": display_name,
        "volume": vol,
        "mute": bool(n.get("mute", False)),
        "is_default": is_default,
        "icon": icon,
    }


def wpctl_default_sink_bundle():
    """Build one synthetic output when pactl JSON is empty (PipeWire-only / pactl quirks)."""
    vol_line = run_cmd("wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null").strip()
    if not vol_line:
        return None
    mute = "MUTED" in vol_line.upper()
    m = re.search(r"([\d.]+)", vol_line)
    vol = int(float(m.group(1)) * 100) if m else 0
    insp = run_cmd("wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null")
    nid = "0"
    m = re.search(r"^id\s+(\d+)", insp, re.MULTILINE)
    if m:
        nid = m.group(1)
    title = "Default Output"
    for pat in (
        r'node\.nick\s*=\s*"([^"]+)"',
        r'node\.description\s*=\s*"([^"]+)"',
        r'alsa\.long_card_name\s*=\s*"([^"]+)"',
    ):
        m = re.search(pat, insp)
        if m:
            title = m.group(1)
            break
    return {
        "id": nid,
        "name": "@DEFAULT_AUDIO_SINK@",
        "description": title,
        "volume": vol,
        "mute": mute,
        "is_default": True,
        "icon": "audio-card",
    }


def wpctl_default_source_bundle():
    vol_line = run_cmd("wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null").strip()
    if not vol_line:
        return None
    mute = "MUTED" in vol_line.upper()
    m = re.search(r"([\d.]+)", vol_line)
    vol = int(float(m.group(1)) * 100) if m else 0
    insp = run_cmd("wpctl inspect @DEFAULT_AUDIO_SOURCE@ 2>/dev/null")
    nid = "0"
    m = re.search(r"^id\s+(\d+)", insp, re.MULTILINE)
    if m:
        nid = m.group(1)
    title = "Default Input"
    for pat in (
        r'node\.nick\s*=\s*"([^"]+)"',
        r'node\.description\s*=\s*"([^"]+)"',
    ):
        m = re.search(pat, insp)
        if m:
            title = m.group(1)
            break
    return {
        "id": nid,
        "name": "@DEFAULT_AUDIO_SOURCE@",
        "description": title,
        "volume": vol,
        "mute": mute,
        "is_default": True,
        "icon": "audio-input-microphone",
    }


def get_data():
    default_sink, default_source = get_defaults()

    sinks = coerce_json_list(run_cmd("pactl -f json list sinks"))
    sources = coerce_json_list(run_cmd("pactl -f json list sources"))
    sink_inputs = coerce_json_list(run_cmd("pactl -f json list sink-inputs"))

    outputs = [format_node(s, default_sink, False) for s in sinks]
    inputs = [format_node(s, default_source, False) for s in sources]

    if not outputs:
        fb = wpctl_default_sink_bundle()
        if fb:
            outputs = [fb]

    if not inputs:
        fb = wpctl_default_source_bundle()
        if fb:
            inputs = [fb]

    apps = []
    for s in sink_inputs:
        props = s.get("properties", {}) or {}
        if props.get("application.id") != "org.PulseAudio.pavucontrol":
            apps.append(format_node(s, "", True, False))

    print(json.dumps({"outputs": outputs, "inputs": inputs, "apps": apps}))


if __name__ == "__main__":
    get_data()
