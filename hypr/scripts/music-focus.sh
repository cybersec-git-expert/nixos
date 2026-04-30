#!/usr/bin/env bash
# Hyprland/Kitty often skip login shells; user Nix profile may not be on PATH
if [[ -d "$HOME/.nix-profile/bin" ]]; then
  PATH="$HOME/.nix-profile/bin${PATH:+:$PATH}"
fi
set -euo pipefail

# Alternative Music Studio — ncmpcpp + cava in tmux (Music Studio)

echo "🎵 Starting Music-First Studio..."

# Check if MPD is running, start if needed
if ! systemctl --user is-active --quiet mpd; then
    echo "Starting MPD service..."
    systemctl --user start mpd
    sleep 2
fi

if ! command -v tmux >/dev/null 2>&1; then
    echo "tmux is not on PATH. Run: sudo nixos-rebuild switch" >&2
    echo "Opening ncmpcpp only (rebuild to get the split with cava)." >&2
    exec ncmpcpp
fi

# Kill any existing tmux session named "music"
tmux kill-session -t music 2>/dev/null || true

# Create new tmux session starting with ncmpcpp
tmux new-session -d -s music "echo 'Loading ncmpcpp...' && sleep 1 && ncmpcpp"

# Add cava in a split below (30% of screen)
tmux split-window -v -p 30 -t music "echo 'Loading audio visualizer...' && sleep 2 && cava"

# Make sure we start focused on ncmpcpp (top pane)
tmux select-pane -t music:0.0

# Show startup message
echo "🎯 Music Studio ready!"
echo "   • You'll start in ncmpcpp (music player)"
echo "   • Press Enter on a song to play it"
echo "   • Use Ctrl+B then ↓ to see visualizer"
echo ""

# Attach to the session focused on music player
exec tmux attach-session -t music
