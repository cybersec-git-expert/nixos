#!/usr/bin/env bash
# Generate Material-You outputs from an image, then run matugen_reload.sh.
# Usage: apply_matugen_wallpaper.sh /path/to/image.png

img="${1:?image path required}"
reload="$(dirname "$0")/matugen_reload.sh"

[[ -f "$img" ]] || exit 1

matugen image "$img" --source-color-index 0 2>/dev/null \
	|| matugen image "$img" --prefer saturation 2>/dev/null \
	|| true

[[ -x "$reload" ]] && bash "$reload"
