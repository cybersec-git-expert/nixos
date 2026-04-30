#!/usr/bin/env bash
# Consolidated system-stats watcher for the Quickshell TopBar.
# Outputs ONE JSON object on stdout containing every "extra" module that the
# legacy python taskbar used to render. The QML side polls this every ~2s.
#
# All fields have sensible defaults so a missing tool never breaks JSON parsing.
#
# Every external command that can block on a missing daemon (NUT upsc, VPN,
# GPU driver, sensors, fuser) is wrapped in `timeout` so this script always
# finishes in well under the poll interval. Otherwise the TopBar kills/restarts
# the poller while the script is still running and stats never update.

set +e

# ---------- helpers ----------
clamp_int() { local v="${1:-0}"; v=${v%%.*}; [[ "$v" =~ ^-?[0-9]+$ ]] || v=0; echo "$v"; }
json_str()  { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# ---------- CPU% ----------
cpu_usage() {
    # Prefer /proc/stat delta (no extra deps)
    read -r _ a b c d e f g h _ < /proc/stat
    local idle1=$d total1=$((a + b + c + d + e + f + g + h))
    sleep 0.2
    read -r _ a b c d e f g h _ < /proc/stat
    local idle2=$d total2=$((a + b + c + d + e + f + g + h))
    local dt=$((total2 - total1))
    local di=$((idle2 - idle1))
    (( dt <= 0 )) && { echo 0; return; }
    awk -v dt="$dt" -v di="$di" 'BEGIN{printf "%d", (1 - di/dt) * 100}'
}

# ---------- RAM% ----------
ram_usage() {
    awk '/MemTotal:/{t=$2} /MemAvailable:/{a=$2} END{ if(t>0) printf "%d", (t-a)*100/t; else print 0 }' /proc/meminfo
}

# ---------- CPU temp (°C) ----------
cpu_temp() {
    local t=""
    if command -v sensors >/dev/null; then
        # Try several common labels in priority order (bounded — sensors can hang on some SMBus chips)
        t=$(timeout 1.5 sensors 2>/dev/null | awk '
            /^(Tctl|Package id 0|CPU|Tdie):/ { for (i=1;i<=NF;i++) if ($i ~ /\+[0-9.]+°C/) { gsub(/[+°C]/, "", $i); print int($i); exit }
        }')
    fi
    if [[ -z "$t" ]]; then
        for z in /sys/class/thermal/thermal_zone*/temp; do
            [[ -r "$z" ]] || continue
            local v; v=$(< "$z")
            (( v > 1000 )) && { t=$((v / 1000)); break; }
        done
    fi
    clamp_int "${t:-0}"
}

# ---------- Disk% (/) ----------
disk_usage() { df -P / 2>/dev/null | awk 'NR==2{gsub("%","",$5); print $5}'; }

# ---------- GPU (nvidia-smi if present) ----------
gpu_stats() {
    if command -v nvidia-smi >/dev/null; then
        # gpu_util,vram_used,vram_total,gpu_temp
        local line; line=$(timeout 2 nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu \
                            --format=csv,noheader,nounits 2>/dev/null | head -1)
        if [[ -n "$line" ]]; then
            local util mu mt tp
            IFS=',' read -r util mu mt tp <<< "$line"
            util=$(clamp_int "$util"); mu=$(clamp_int "$mu"); mt=$(clamp_int "$mt"); tp=$(clamp_int "$tp")
            local vram=0
            (( mt > 0 )) && vram=$(( mu * 100 / mt ))
            echo "$util $vram $tp"
            return
        fi
    fi
    echo "0 0 0"
}

# ---------- Microphone (pamixer) ----------
mic_stats() {
    local v=0 m=true
    if command -v pamixer >/dev/null; then
        v=$(pamixer --default-source --get-volume 2>/dev/null || echo 0)
        if pamixer --default-source --get-mute 2>/dev/null | grep -q true; then m=true; else m=false; fi
    fi
    echo "$(clamp_int "$v") $m"
}

# ---------- Camera ----------
cam_stats() {
    local active=false app="Idle"
    # If any /dev/video* device is opened by a process, camera is active
    if compgen -G "/dev/video*" >/dev/null 2>&1; then
        if command -v fuser >/dev/null; then
            local pids
            pids=$(timeout 1 fuser /dev/video* 2>/dev/null | tr -s ' ' '\n' | grep -E '^[0-9]+$' | head -1)
            if [[ -n "$pids" ]]; then
                active=true
                app=$(ps -p "$pids" -o comm= 2>/dev/null | head -1)
                [[ -z "$app" ]] && app="Camera"
            fi
        fi
    fi
    printf '%s|%s' "$active" "$(json_str "$app")"
}

# ---------- VPN (mullvad) ----------
vpn_stats() {
    local status="disconnected" loc="Disconnected"
    if command -v mullvad >/dev/null; then
        local out; out=$(timeout 2 mullvad status 2>/dev/null)
        if   echo "$out" | grep -qi "Connected";  then status="connected";  loc=$(echo "$out" | grep -i "Relay:" | sed 's/^.*Relay:[[:space:]]*//' | head -1)
        elif echo "$out" | grep -qi "Connecting"; then status="connecting"; loc="Connecting…"
        else status="disconnected"; loc="Disconnected"
        fi
    fi
    [[ -z "$loc" ]] && loc="Connected"
    printf '%s|%s' "$status" "$(json_str "$loc")"
}

# ---------- UPS (NUT) ----------
ups_stats() {
    local connected=false status="N/A" runtime=-1 charge=-1
    if command -v upsc >/dev/null; then
        # upsc blocks for many seconds when upsd is not reachable — kills TopBar stats polling.
        local list=""
        if [[ -n "${NUT_UPS:-}" ]]; then
            list="$NUT_UPS"
        else
            list=$(timeout 2 upsc -l 2>/dev/null | head -1)
        fi
        if [[ -z "$list" ]] && [[ -z "${NUT_UPS:-}" ]]; then
            if timeout 2 upsc "ups@localhost" 2>/dev/null | grep -q .; then
                list="ups@localhost"
            fi
        fi
        if [[ -n "$list" ]]; then
            local raw; raw=$(timeout 2 upsc "$list" 2>/dev/null)
            if [[ -n "$raw" ]]; then
                connected=true
                status=$(echo "$raw"  | awk -F': ' '/^ups\.status:/{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}')
                runtime=$(echo "$raw" | awk -F': ' '/^battery\.runtime:/{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}')
                charge=$(echo "$raw"  | awk -F': ' '/^battery\.charge:/{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}')
                [[ -z "$status"  ]] && status="OL"
                [[ -z "$runtime" ]] && runtime=-1
                [[ -z "$charge"  ]] && charge=-1

                # Auto-shutdown: UPS on battery and charge ≤ 50%
                if [[ "$status" == *OB* ]] && [[ "$charge" =~ ^[0-9]+$ ]] && (( charge <= 50 )); then
                    # Guard: only shut down once (flag file prevents repeat triggers each poll)
                    _flag="/tmp/.ups_shutdown_triggered"
                    if [[ ! -f "$_flag" ]]; then
                        touch "$_flag"
                        systemctl poweroff
                    fi
                else
                    rm -f "/tmp/.ups_shutdown_triggered"
                fi
            fi
        fi
    fi
    printf '%s|%s|%s|%s' "$connected" "$(json_str "$status")" "$(clamp_int "$runtime")" "$(clamp_int "$charge")"
}

# ---------- Pomodoro Timer ----------
timer_stats() {
    local state_file="$HOME/.cache/qs_timer_state.json"
    if [[ -r "$state_file" ]]; then
        cat "$state_file"
    else
        echo '{"active":false,"duration":25,"remaining":1500,"end":0}'
    fi
}

# ---------- Notification count ----------
# Quickshell writes qs_notif_count when it owns the bus; if dunst owns it, use dunst history count
notif_count() {
    local f="$HOME/.cache/qs_notif_count"
    local qs=0
    [[ -r "$f" ]] && qs=$(clamp_int "$(cat "$f")")
    local ds=0
    if command -v dunstctl &>/dev/null; then
        ds=$(dunstctl count history 2>/dev/null) || ds=0
        ds=$(clamp_int "$ds")
    fi
    if (( ds > qs )); then echo "$ds"; else echo "$qs"; fi
}

# ---------- Assemble JSON ----------
CPU=$(cpu_usage); RAM=$(ram_usage); TMP=$(cpu_temp); DSK=$(disk_usage)
read -r GPU VRAM GTMP <<< "$(gpu_stats)"
read -r MIC MIC_M  <<< "$(mic_stats)"
IFS='|' read -r CAM_A CAM_APP        <<< "$(cam_stats)"
IFS='|' read -r VPN_S VPN_L          <<< "$(vpn_stats)"
IFS='|' read -r UPS_C UPS_S UPS_R UPS_CH <<< "$(ups_stats)"
TMR=$(timer_stats)
NOTIF=$(notif_count)

cat <<EOF
{"cpu":$CPU,"ram":$RAM,"temp":$TMP,"disk":${DSK:-0},"gpu":$GPU,"vram":$VRAM,"gpu_temp":$GTMP,"mic_vol":$MIC,"mic_muted":$MIC_M,"cam_active":$CAM_A,"cam_app":"$CAM_APP","vpn_status":"$VPN_S","vpn_loc":"$VPN_L","ups_connected":$UPS_C,"ups_status":"$UPS_S","ups_runtime":$UPS_R,"ups_charge":$UPS_CH,"timer":$TMR,"notif_count":$NOTIF}
EOF
