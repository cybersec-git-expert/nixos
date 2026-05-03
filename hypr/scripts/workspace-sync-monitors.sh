#!/usr/bin/env bash
# Move numeric workspaces 1–20 onto the correct output (odd→HP, even→MSI). Safe on reload.
set -uo pipefail
command -v hyprctl >/dev/null 2>&1 || exit 0
hyprctl version >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

mons=$(hyprctl monitors -j 2>/dev/null) || exit 0
msi=$(echo "$mons" | jq -r '.[] | select(.description | test("PC2M024802637")) | .name' | head -1)
hp=$(echo "$mons" | jq -r '.[] | select(.description | test("6CM1420GCS")) | .name' | head -1)
[[ -n "$msi" && -n "$hp" ]] || exit 0

hyprctl workspaces -j 2>/dev/null | jq -c '.[]' | while read -r row; do
	wid=$(echo "$row" | jq -r '.id')
	wm=$(echo "$row" | jq -r '.monitor')
	[[ "$wid" =~ ^[0-9]+$ ]] || continue
	((wid >= 1 && wid <= 20)) || continue
	if ((wid % 2 == 1)); then
		want=$hp
	else
		want=$msi
	fi
	if [[ "$wm" != "$want" ]]; then
		hyprctl dispatch moveworkspacetomonitor "$wid" "$want" >/dev/null 2>&1 || true
	fi
done
