#!/usr/bin/env bash
hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // "?"' 2>/dev/null || echo "?"
