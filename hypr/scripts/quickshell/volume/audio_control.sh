#!/usr/bin/env bash

ACTION=$1
TYPE=$2
ID=$3
VAL=$4

case $ACTION in
    set-volume)
        # Type should be 'sink', 'source', or 'sink-input'
        if ! pactl "set-${TYPE}-volume" "$ID" "${VAL}%" 2>/dev/null; then
            wpctl set-volume "$ID" "${VAL}%" 2>/dev/null || true
        fi
        ;;
    toggle-mute)
        if ! pactl "set-${TYPE}-mute" "$ID" toggle 2>/dev/null; then
            wpctl set-mute "$ID" toggle 2>/dev/null || true
        fi
        ;;
    set-default)
        if ! pactl "set-default-${TYPE}" "$ID" 2>/dev/null; then
            wpctl set-default "$ID" 2>/dev/null || true
        fi
        ;;
esac
