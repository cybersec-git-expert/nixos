#!/usr/bin/env bash

# File to store the latest seek request
SEEK_FILE="/tmp/quickshell_music_seek_data"

# Arg mapping
command=$1
arg=$2
len_sec=$3
player_name=$4

# Fallback for player name (QML should pass the active `playerName` from music_info.sh, e.g. "mpd" or "spotify")
if [ -z "$player_name" ]; then
    player_name=$(playerctl status -f "{{playerName}}" 2>/dev/null | head -n 1)
fi
if [ -z "$player_name" ]; then exit 0; fi

case $command in
    "seek")
        # 1. WRITE: Save the latest target data to a file immediately.
        #    This overwrites any previous pending request.
        echo "$arg $len_sec $player_name" > "$SEEK_FILE"

        # 2. CHECK: Is a worker already running?
        #    We check for a specific marker we create below.
        lock_file="/tmp/quickshell_music_seek_lock"
        
        # If the lock file exists, a worker is already waiting to execute.
        # We just exit and let that worker pick up our new value from step 1.
        if [ -f "$lock_file" ]; then
            exit 0
        fi

        # 3. WORKER: Create the lock and run in background
        touch "$lock_file"
        
        (
            # Wait a tiny bit to gather rapid updates (Debounce)
            sleep 0.05
            
            # Read the LATEST value from the file (Step 1)
            read -r final_arg final_len final_player < "$SEEK_FILE"
            
            # Perform the Seek Logic
            if [ -n "$final_len" ] && [ "$final_len" != "0" ]; then
                if [ "$final_player" = "mpd" ] && command -v mpc &>/dev/null; then
                    # Percent matches music_info + playerctl UIs; mpc accepts 0–100% of the track
                    mpc seek "${final_arg}%" 2>/dev/null || true
                else
                    target_sec=$(awk -v len="$final_len" -v perc="$final_arg" 'BEGIN { printf "%.2f", (len * perc) / 100 }')
                    playerctl -p "$final_player" position "$target_sec" 2>/dev/null
                fi
            fi
            
            # Remove lock so a new batch can start
            rm "$lock_file"
        ) & 
        
        # Exit main script immediately to free up the UI
        exit 0
        ;;
    
    "next")
        if [ "$player_name" = "mpd" ] && command -v mpc &>/dev/null; then
            mpc next
        else
            playerctl -p "$player_name" next
        fi
        ;;

    "prev"|"previous")
        if [ "$player_name" = "mpd" ] && command -v mpc &>/dev/null; then
            mpc prev
        else
            playerctl -p "$player_name" previous
        fi
        ;;

    "play-pause")
        if [ "$player_name" = "mpd" ] && command -v mpc &>/dev/null; then
            mpc toggle
        else
            playerctl -p "$player_name" play-pause
        fi
        ;;

esac
