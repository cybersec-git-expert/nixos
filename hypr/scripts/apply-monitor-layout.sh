#!/usr/bin/env bash
# MSI on top (centered over ultrawide), HP below. Connector names change; match EDID serials.
# `monitor=` in hyprland.conf is not reliably applied on `hyprctl reload`; `exec` re-runs this.
set -euo pipefail
command -v hyprctl >/dev/null 2>&1 || exit 0
hyprctl version >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

mons=$(hyprctl monitors -j 2>/dev/null) || exit 0
[[ -n "$mons" ]] || exit 0

msi=$(echo "$mons" | jq -r '.[] | select(.description | test("PC2M024802637")) | .name' | head -1)
hp=$(echo "$mons" | jq -r '.[] | select(.description | test("6CM1420GCS")) | .name' | head -1)

if [[ -n "$msi" ]]; then
	hyprctl keyword monitor "$msi,1920x1080@100,760x0,1" >/dev/null 2>&1 || true
fi
if [[ -n "$hp" ]]; then
	hyprctl keyword monitor "$hp,3440x1440@165,0x1080,1" >/dev/null 2>&1 || true
fi
