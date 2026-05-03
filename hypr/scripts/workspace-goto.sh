#!/usr/bin/env bash
# Odd workspaces → HP (6CM…), even → MSI (PC2…). Forces placement before focus.
set -euo pipefail
N="${1:?workspace id}"
[[ "$N" =~ ^[0-9]+$ ]] || exit 1
command -v hyprctl >/dev/null 2>&1 || exit 0
hyprctl version >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

mons=$(hyprctl monitors -j 2>/dev/null) || exit 0
msi=$(echo "$mons" | jq -r '.[] | select(.description | test("PC2M024802637")) | .name' | head -1)
hp=$(echo "$mons" | jq -r '.[] | select(.description | test("6CM1420GCS")) | .name' | head -1)

if ((N % 2 == 1)); then
	target=$hp
else
	target=$msi
fi
[[ -n "${target:-}" ]] || exit 0

# Focus output first so *new* workspaces are created on the right head (else they follow cursor/HOME output).
hyprctl dispatch focusmonitor "$target" >/dev/null 2>&1 || true
hyprctl dispatch moveworkspacetomonitor "$N" "$target" >/dev/null 2>&1 || true
hyprctl dispatch workspace "$N" >/dev/null 2>&1 || true
hyprctl dispatch focusmonitor "$target" >/dev/null 2>&1 || true
