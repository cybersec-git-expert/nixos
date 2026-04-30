#!/usr/bin/env bash
# Thin wrapper around qs_manager.sh, which handles thumbnail prep
# (wallpaper picker), bluetooth/wifi prep (network), and zombie respawn.
#
# Usage:
#   quickshell-panel.sh toggle network
#   quickshell-panel.sh open music
#   quickshell-panel.sh close
#
# Available panels (after stripping topbar + battery):
#   network calendar music volume monitors timer focustime guide
#   wallpaper notifications updater settings stewart

exec "$(dirname "$(readlink -f "$0")")/qs_manager.sh" "$@"
