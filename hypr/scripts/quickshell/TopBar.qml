//@ pragma UseQApplication
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray

PanelWindow {
    id: barWindow

    // Single status bar on the HP (primary) panel only.
    readonly property string primaryHyprOutput: {
        const e = Quickshell.env("QS_PRIMARY_OUTPUT");
        return (e && String(e).trim() !== "") ? String(e).trim() : "DP-3";
    }
    screen: {
        const screens = Quickshell.screens;
        const want = barWindow.primaryHyprOutput;
        for (let i = 0; i < screens.length; i++) {
            const s = screens[i];
            if (s && s.name === want)
                return s;
        }
        return screens.length ? screens[0] : undefined;
    }

	    property bool pendingReload: false

	    IpcHandler {
    		target: "topbar"
    
    		function forceReload() {
            	    Quickshell.reload(true) 
	        }

	        function queueReload() {
                    // If it's already closed, reload immediately. Otherwise, flag it.
                    if (!barWindow.isSettingsOpen && barWindow.sidebarHoleWidth <= 0.01) {
                        Quickshell.reload(true)
                    } else {
                        barWindow.pendingReload = true
                    }
                }
	    }

            anchors {
                bottom: true
                left: true
                right: true
            }
            
            // --- Responsive Scaling Logic ---
            Scaler {
                id: scaler
                currentWidth: barWindow.width
            }

            property real baseScale: scaler.baseScale
            
            // Helper function mapped to the external scaler
            function s(val) { 
                return scaler.s(val); 
            }

            // Same active player as music_info.sh / MPRIS: MPD → mpc; otherwise playerctl -p <name>
            function runPlayerTransport(verb) {
                const p = (musicData.playerName !== undefined && musicData.playerName !== null)
                    ? String(musicData.playerName) : "";
                const sh = Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/music/player_control.sh";
                Quickshell.execDetached(["bash", sh, verb, "", "", p]);
                musicForceRefresh.running = false;
                musicForceRefresh.running = true;
            }

            property int barHeight: s(48)

            height: barHeight
            margins { top: 0; bottom: 0; left: 0; right: 0 }
            exclusiveZone: barHeight
            color: "transparent"

            // Dynamic Matugen Palette
            MatugenColors {
                id: mocha
            }

            readonly property color barPillFill: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.92)

            // --- State Variables ---
            property bool showHelpIcon: true
            property bool isRecording: false // Track screen recording
            property bool updateAvailable: false // Track pending updates
            property int workspaceCount: 8
            property bool workspaceCountAuto: false
            
            // Tracks current qs widget to coordinate the sidebar transitions
            property string activeWidget: "" 
            property bool isSettingsOpen: activeWidget === "settings"

            // Consume a deferred reload request as soon as the Settings panel finishes closing.
            // This pairs with IpcHandler.queueReload so "Apply" in Settings takes effect
            // the moment the panel is dismissed — no manual TopBar reload needed.
            onIsSettingsOpenChanged: {
                if (!isSettingsOpen && barWindow.pendingReload) {
                    pendingReloadTimer.restart()
                }
            }
            Timer {
                id: pendingReloadTimer
                interval: 450  // wait for the sidebar-hole close animation (~400ms) to finish
                repeat: false
                onTriggered: {
                    if (barWindow.pendingReload && !barWindow.isSettingsOpen) {
                        barWindow.pendingReload = false
                        Quickshell.reload(true)
                    }
                }
            }

            // --- Dynamic Window Mask ---
            // Cuts a physical hole in the bar strip so the Settings panel can use the left edge
            property real targetSidebarHoleWidth: isSettingsOpen ? s(420) : 0
            property real sidebarHoleWidth: targetSidebarHoleWidth
            Behavior on sidebarHoleWidth { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }

            mask: Region { item: sidebarHole; intersection: Intersection.Xor }
            
            Item {
                id: sidebarHole
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                width: barWindow.sidebarHoleWidth
            }

            // Background poller for active widget state tracking
            Process {
                id: widgetPoller
                command: ["bash", "-c", "cat /tmp/qs_current_widget 2>/dev/null || echo ''"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (barWindow.activeWidget !== txt) barWindow.activeWidget = txt;
                    }
                }
            }

            Process {
                id: widgetWatcher
                command: ["bash", "-c", "while [ ! -f /tmp/qs_current_widget ]; do sleep 1; done; inotifywait -qq -e modify,close_write /tmp/qs_current_widget"]
                running: true
                onExited: {
                    widgetPoller.running = false;
                    widgetPoller.running = true;
                    running = false;
                    running = true;
                }
            }
            
            // Background poller to check if gpu-screen-recorder is active via its PID file
            Process {
                id: recPoller
                command: ["bash", "-c", "if [ -s ~/.cache/qs_recording_state/rec_pid ] && kill -0 $(cat ~/.cache/qs_recording_state/rec_pid) 2>/dev/null; then echo '1'; else echo '0'; fi"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        barWindow.isRecording = (this.text.trim() === "1");
                    }
                }
            }

            Timer {
                interval: 500; running: true; repeat: true
                onTriggered: {
                    recPoller.running = false;
                    recPoller.running = true;
                }
            }

            // Background poller to check for pending updates
            Process {
                id: updatePoller
                command: ["bash", "-c", "if [ -f ~/.cache/qs_update_pending ]; then echo '1'; else echo '0'; fi"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        barWindow.updateAvailable = (this.text.trim() === "1");
                    }
                }
            }

            Timer {
                interval: 2000; running: true; repeat: true
                onTriggered: {
                    updatePoller.running = false;
                    updatePoller.running = true;
                }
            }
            
            Process {
                id: settingsReader
                command: ["bash", "-c", "cat ~/.config/hypr/settings.json 2>/dev/null || echo '{}'"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            if (this.text && this.text.trim().length > 0 && this.text.trim() !== "{}") {
                                let parsed = JSON.parse(this.text);
                                
                                if (parsed.topbarHelpIcon !== undefined && barWindow.showHelpIcon !== parsed.topbarHelpIcon) {
                                    barWindow.showHelpIcon = parsed.topbarHelpIcon;
                                }
                                
                                // Detect if workspace count (or auto mode) changed and
                                // restart the daemon so it re-reads settings.json.
                                let wsChanged = false;
                                if (parsed.workspaceCount !== undefined && barWindow.workspaceCount !== parsed.workspaceCount) {
                                    barWindow.workspaceCount = parsed.workspaceCount;
                                    wsChanged = true;
                                }
                                let nextAuto = parsed.workspaceCountAuto === true;
                                if (barWindow.workspaceCountAuto !== nextAuto) {
                                    barWindow.workspaceCountAuto = nextAuto;
                                    wsChanged = true;
                                }
                                if (wsChanged) {
                                    wsDaemon.running = false;
                                    wsDaemon.running = true;
                                }
                            }
                        } catch (e) {}
                    }
                }
            }
            // EVENT-DRIVEN WATCHER FOR SETTINGS
            Process {
                id: settingsWatcher
                command: ["bash", "-c", "while [ ! -f ~/.config/hypr/settings.json ]; do sleep 1; done; inotifywait -qq -e modify,close_write ~/.config/hypr/settings.json"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        settingsReader.running = false;
                        settingsReader.running = true;
                        
                        settingsWatcher.running = false;
                        settingsWatcher.running = true;
                    }
                }
            }
            
            // Desktop Chassis Detection
            property bool isDesktop: false
            property string ethStatus: "Ethernet"

            Process {
                id: chassisDetector
                running: true
                command: ["bash", "-c", "if ls /sys/class/power_supply/BAT* 1> /dev/null 2>&1; then echo 'laptop'; else echo 'desktop'; fi"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        barWindow.isDesktop = (this.text.trim() === "desktop");
                    }
                }
            }

            // Triggers layout animations immediately to feel fast
            property bool isStartupReady: false
            Timer { interval: 10; running: true; onTriggered: barWindow.isStartupReady = true }
            
            // Prevents repeaters (Workspaces/Tray) from flickering on data updates
            property bool startupCascadeFinished: false
            Timer { interval: 1000; running: true; onTriggered: barWindow.startupCascadeFinished = true }
            
            // Data gating to prevent startup layout jumping
            property bool fastPollerLoaded: false
            
            property bool isDataReady: fastPollerLoaded
            // Failsafe: Force the layout to show after 600ms even if fast poller hangs
            Timer { interval: 600; running: true; onTriggered: barWindow.isDataReady = true }
            
            property string timeStr: ""
            property string fullDateStr: ""
            property int typeInIndex: 0
            property string dateStr: fullDateStr.substring(0, typeInIndex)

            property string weatherEmoji: "☁️"
            property string weatherTemp: "--°"
            property string weatherHex: mocha.yellow
            
            property string wifiStatus: "Off"
            property string wifiIcon: "󰤮"
            property string wifiSsid: ""
            
            property string btStatus: "Off"
            property string btIcon: "󰂲"
            property string btDevice: ""
            
            property string volPercent: "0%"
            property string volIcon: "󰕾"
            property bool isMuted: false
            
            property string batPercent: "100%"
            property string batIcon: "󰁹"
            property string batStatus: "Unknown"
            
            property string kbLayout: "us"

            // ===== System-stats fields ported from the legacy python taskbar =====
            property int    sysCpu: 0
            property int    sysRam: 0
            property int    sysTemp: 0
            property int    sysDisk: 0
            property int    sysGpu: 0
            property int    sysVram: 0
            property int    sysGpuTemp: 0
            property int    sysMicVol: 0
            property bool   sysMicMuted: true
            property bool   sysCamActive: false
            property string sysCamApp: "Idle"
            property string sysVpnStatus: "disconnected"
            property string sysVpnLoc: "Disconnected"
            property bool   sysUpsConnected: false
            property string sysUpsStatus: "N/A"
            property int    sysUpsRuntime: -1
            property int    sysUpsCharge: -1
            property int    sysNotifCount: 0

            // Pomodoro (qs_timer_state.json) — bar chip between clock and right cluster
            property bool   sysTimerActive: false
            property int    sysTimerDuration: 25
            property int    sysTimerRemaining: 1500
            property double sysTimerEnd: 0
            property double sysNowSec: 0

            readonly property int sysTimerSessionSec: Math.max(1, sysTimerDuration * 60)
            property int sysTimerSecsLeft: {
                if (sysTimerActive && sysTimerEnd > 0) {
                    let r = Math.max(0, Math.round(sysTimerEnd - sysNowSec));
                    return r;
                }
                return sysTimerRemaining;
            }
            readonly property bool sysTimerBarIdle: !sysTimerActive && sysTimerRemaining === sysTimerSessionSec
            readonly property bool showTimerChip: sysTimerSecsLeft > 0 && !sysTimerBarIdle

            function _fmtTimerMMSS(secs) {
                let m = Math.floor(secs / 60);
                let s = secs % 60;
                return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
            }
            
            ListModel { id: workspacesModel }
            
            // Default matches music_info.sh Stopped branch ("Not Playing") so the bar shows idle state until first refresh.
            property var musicData: { "status": "Stopped", "title": "Not Playing", "artUrl": "", "timeStr": "", "playerName": "" }

            // Derived properties for UI logic
            // No scroll-to-cycle player: always show the active MPRIS/MPD line (playing, paused, or "Not Playing" when stopped).
            property bool isMediaActive: (barWindow.musicData.title && barWindow.musicData.title.length > 0)
            property bool isWifiOn: barWindow.wifiStatus.toLowerCase() === "enabled" || barWindow.wifiStatus.toLowerCase() === "on"
            property bool isBtOn: barWindow.btStatus.toLowerCase() === "enabled" || barWindow.btStatus.toLowerCase() === "on"
            // Prefer Ethernet whenever the cable reports "Connected". Only fall back to the
            // WiFi status pill when the wire is out. This mirrors what `nmcli dev` shows.
            property bool showEthernet: barWindow.ethStatus === "Connected"
            
            property bool isSoundActive: !barWindow.isMuted && parseInt(barWindow.volPercent) > 0
            property int batCap: parseInt(barWindow.batPercent) || 0
            property bool isCharging: barWindow.batStatus === "Charging" || barWindow.batStatus === "Full"
            
            property color batDynamicColor: {
                if (isCharging) return mocha.green;
                if (batCap <= 20) return mocha.red;
                return mocha.text; 
            }

            // ==========================================
            // DATA FETCHING 
            // ==========================================

            // Workspaces --------------------------------
            Process {
                id: wsDaemon
                command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/workspaces.sh"]
                running: true
            }

            Process {
                id: wsReader
                command: ["cat", "/tmp/qs_workspaces.json"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (txt !== "") {
                            try { 
                                let newData = JSON.parse(txt);
                                
                                // 1. Add missing items if the user increased the workspace count
                                while (workspacesModel.count < newData.length) {
                                    workspacesModel.append({ "wsId": "", "wsState": "" });
                                }
                                
                                // 2. Remove excess items if the user decreased the workspace count
                                while (workspacesModel.count > newData.length) {
                                    workspacesModel.remove(workspacesModel.count - 1);
                                }
                                
                                // 3. Update all properties smoothly without breaking bindings
                                for (let i = 0; i < newData.length; i++) {
                                    if (workspacesModel.get(i).wsState !== newData[i].state) {
                                        workspacesModel.setProperty(i, "wsState", newData[i].state);
                                    }
                                    if (workspacesModel.get(i).wsId !== newData[i].id.toString()) {
                                        workspacesModel.setProperty(i, "wsId", newData[i].id.toString());
                                    }
                    }
                            } catch(e) {}
                        }
                    }
                }
            }

            Process {
                id: wsWatcher
                running: true
                command: ["bash", "-c", "inotifywait -qq -e close_write,modify /tmp/qs_workspaces.json"]
                onExited: {
                    wsReader.running = false;
                    wsReader.running = true;
                    running = false;
                    running = true;
                }
            }

            // Music -------------------------------------
            Process {
                id: musicForceRefresh
                running: true
                command: ["bash", "-c", "bash '" + Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/music/music_info.sh' | tee /tmp/music_info.json"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (txt !== "") {
                            try { barWindow.musicData = JSON.parse(txt); } catch(e) {}
                        }
                    }
                }
            }

            Timer {
                interval: 1000
                running: true
                repeat: true
                onTriggered: {
                    if (!barWindow.musicData || barWindow.musicData.status !== "Playing") return;
                    if (!barWindow.musicData.timeStr || barWindow.musicData.timeStr === "") return;

                    let parts = barWindow.musicData.timeStr.split(" / ");
                    if (parts.length !== 2) return;

                    let posParts = parts[0].split(":").map(Number);
                    let lenParts = parts[1].split(":").map(Number);

                    let posSecs = (posParts.length === 3) 
                        ? (posParts[0] * 3600 + posParts[1] * 60 + posParts[2]) 
                        : (posParts[0] * 60 + posParts[1]);

                    let lenSecs = (lenParts.length === 3) 
                        ? (lenParts[0] * 3600 + lenParts[1] * 60 + lenParts[2]) 
                        : (lenParts[0] * 60 + lenParts[1]);

                    if (isNaN(posSecs) || isNaN(lenSecs)) return;

                    posSecs++;
                    if (posSecs > lenSecs) posSecs = lenSecs;

                    let newPosStr = "";
                    if (posParts.length === 3) {
                        let h = Math.floor(posSecs / 3600);
                        let m = Math.floor((posSecs % 3600) / 60);
                        let s = posSecs % 60;
                        newPosStr = h + ":" + (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
                    } else {
                        let m = Math.floor(posSecs / 60);
                        let s = posSecs % 60;
                        newPosStr = (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
                    }

                    let newData = Object.assign({}, barWindow.musicData);
                    newData.timeStr = newPosStr + " / " + parts[1];
                    newData.positionStr = newPosStr;
                    if (lenSecs > 0) newData.percent = (posSecs / lenSecs) * 100;
                    
                    barWindow.musicData = newData;
                }
            }

            Process {
                id: mprisWatcher
                running: true
                command: ["bash", "-c", "dbus-monitor --session \"type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',arg0='org.mpris.MediaPlayer2.Player'\" \"type='signal',interface='org.mpris.MediaPlayer2.Player',member='Seeked'\" 2>/dev/null | grep -m 1 'member=' > /dev/null || sleep 2"]
                onExited: {
                    musicForceRefresh.running = false;
                    musicForceRefresh.running = true;
                    running = false;
                    running = true;
                }
            }

            // Periodic music polling fallback — ensures the pill updates even when
            // dbus-monitor misses events (ncmpcpp/MPD, Spotify startup race, etc.)
            Timer {
                interval: 5000; running: true; repeat: true
                onTriggered: {
                    musicForceRefresh.running = false;
                    musicForceRefresh.running = true;
                }
            }

            // ==========================================
            // MODULAR SYSTEM WATCHERS
            // ==========================================

            // --- KEYBOARD ---
            Process {
                id: kbPoller; running: true
                command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/kb_fetch.sh"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (txt !== "" && barWindow.kbLayout !== txt) barWindow.kbLayout = txt;
                        kbWaiter.running = false;
                        kbWaiter.running = true;
                        barWindow.fastPollerLoaded = true; // Gating flag
                    }
                }
            }
            Process { id: kbWaiter; command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/kb_wait.sh"]; onExited: { kbPoller.running = false; kbPoller.running = true; } }

            // --- AUDIO ---
            Process {
                id: audioPoller; running: true
                command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/audio_fetch.sh"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (txt !== "") {
                            try {
                                let data = JSON.parse(txt);
                                let newVol = data.volume.toString() + "%";
                                if (barWindow.volPercent !== newVol) barWindow.volPercent = newVol;
                                if (barWindow.volIcon !== data.icon) barWindow.volIcon = data.icon;
                                let newMuted = (data.is_muted === "true");
                                if (barWindow.isMuted !== newMuted) barWindow.isMuted = newMuted;
                            } catch(e) {}
                        }
                        audioWaiter.running = false;
                        audioWaiter.running = true;
                    }
                }
            }
            Process { id: audioWaiter; command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/audio_wait.sh"]; onExited: { audioPoller.running = false; audioPoller.running = true; } }

            // --- NETWORK ---
            Process {
                id: networkPoller; running: true
                command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/network_fetch.sh"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (txt !== "") {
                            try {
                                let data = JSON.parse(txt);
                                if (barWindow.wifiStatus !== data.status) barWindow.wifiStatus = data.status;
                                if (barWindow.wifiIcon !== data.icon) barWindow.wifiIcon = data.icon;
                                if (barWindow.wifiSsid !== data.ssid) barWindow.wifiSsid = data.ssid;
                                if (barWindow.ethStatus !== data.eth_status) barWindow.ethStatus = data.eth_status;
                            } catch(e) {}
                        }
                        networkWaiter.running = false;
                        networkWaiter.running = true;
                    }
                }
            }
        Process { id: networkWaiter; command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/network_wait.sh"]; onExited: { networkPoller.running = false; networkPoller.running = true; } }

            // --- BLUETOOTH ---
            Process {
                id: btPoller; running: true
                command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/bt_fetch.sh"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (txt !== "") {
                            try {
                                let data = JSON.parse(txt);
                                if (barWindow.btStatus !== data.status) barWindow.btStatus = data.status;
                                if (barWindow.btIcon !== data.icon) barWindow.btIcon = data.icon;
                                if (barWindow.btDevice !== data.connected) barWindow.btDevice = data.connected;
                            } catch(e) {}
                        }
                        btWaiter.running = false;
                        btWaiter.running = true;
                    }
                }
            }
            Process { id: btWaiter; command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/bt_wait.sh"]; onExited: { btPoller.running = false; btPoller.running = true; } }

            // --- BATTERY ---
            Process {
                id: batteryPoller; running: true
                command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/battery_fetch.sh"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (txt !== "") {
                            try {
                                let data = JSON.parse(txt);
                                let newBat = data.percent.toString() + "%";
                                if (barWindow.batPercent !== newBat) barWindow.batPercent = newBat;
                                if (barWindow.batIcon !== data.icon) barWindow.batIcon = data.icon;
                                if (barWindow.batStatus !== data.status) barWindow.batStatus = data.status;
                            } catch(e) {}
                        }
                        batteryWaiter.running = false;
                        batteryWaiter.running = true;
                    }
                }
            }
            Process { id: batteryWaiter; command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/battery_wait.sh"]; onExited: { batteryPoller.running = false; batteryPoller.running = true; } }

            // --- SYSTEM STATS (cpu/ram/temp/disk/gpu/mic/cam/vpn/ups/notif) ---
            Process {
                id: sysStatsPoller
                running: true
                command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/sys_stats.sh"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (txt === "") return;
                        try {
                            let d = JSON.parse(txt);
                            if (barWindow.sysCpu       !== d.cpu)        barWindow.sysCpu       = d.cpu;
                            if (barWindow.sysRam       !== d.ram)        barWindow.sysRam       = d.ram;
                            if (barWindow.sysTemp      !== d.temp)       barWindow.sysTemp      = d.temp;
                            if (barWindow.sysDisk      !== d.disk)       barWindow.sysDisk      = d.disk;
                            if (barWindow.sysGpu       !== d.gpu)        barWindow.sysGpu       = d.gpu;
                            if (barWindow.sysVram      !== d.vram)       barWindow.sysVram      = d.vram;
                            if (barWindow.sysGpuTemp   !== d.gpu_temp)   barWindow.sysGpuTemp   = d.gpu_temp;
                            if (barWindow.sysMicVol    !== d.mic_vol)    barWindow.sysMicVol    = d.mic_vol;
                            if (barWindow.sysMicMuted  !== d.mic_muted)  barWindow.sysMicMuted  = d.mic_muted;
                            if (barWindow.sysCamActive !== d.cam_active) barWindow.sysCamActive = d.cam_active;
                            if (barWindow.sysCamApp    !== d.cam_app)    barWindow.sysCamApp    = d.cam_app;
                            if (barWindow.sysVpnStatus !== d.vpn_status) barWindow.sysVpnStatus = d.vpn_status;
                            if (barWindow.sysVpnLoc    !== d.vpn_loc)    barWindow.sysVpnLoc    = d.vpn_loc;
                            let upsConn = d.ups_connected === true || d.ups_connected === "true" || d.ups_connected === "True";
                            if (barWindow.sysUpsConnected !== upsConn) barWindow.sysUpsConnected = upsConn;
                            if (barWindow.sysUpsStatus !== d.ups_status) barWindow.sysUpsStatus = d.ups_status;
                            if (barWindow.sysUpsRuntime !== d.ups_runtime) barWindow.sysUpsRuntime = d.ups_runtime;
                            if (barWindow.sysUpsCharge !== d.ups_charge) barWindow.sysUpsCharge = d.ups_charge;
                            if (barWindow.sysNotifCount !== d.notif_count) barWindow.sysNotifCount = d.notif_count;
                            if (d.timer) {
                                let t = d.timer;
                                if (typeof t === "string") {
                                    try {
                                        t = JSON.parse(t);
                                    } catch (e) {
                                        t = null;
                                    }
                                }
                                if (t) {
                                    let a = t.active;
                                    let act = a === true || a === "true" || a === "True";
                                    if (barWindow.sysTimerActive !== act)
                                        barWindow.sysTimerActive = act;
                                    let dur = parseInt(t.duration, 10);
                                    if (!isNaN(dur) && dur > 0 && barWindow.sysTimerDuration !== dur)
                                        barWindow.sysTimerDuration = dur;
                                    let rem = parseInt(t.remaining, 10);
                                    if (!isNaN(rem) && barWindow.sysTimerRemaining !== rem)
                                        barWindow.sysTimerRemaining = rem;
                                    let en = parseFloat(t.end);
                                    if (!isNaN(en) && barWindow.sysTimerEnd !== en)
                                        barWindow.sysTimerEnd = en;
                                }
                            }
                        } catch(e) { console.log("sys_stats parse error:", e); }
                    }
                }
            }
            Timer {
                // Slightly longer than sys_stats.sh worst-case (timeouts) so a poll
                // always finishes before the next one is started.
                interval: 2500; running: true; repeat: true; triggeredOnStart: true
                onTriggered: { sysStatsPoller.running = false; sysStatsPoller.running = true; }
            }

            // Native Qt time for the center bar clock
            Timer {
                interval: 1000; running: true; repeat: true; triggeredOnStart: true
                onTriggered: {
                    barWindow.sysNowSec = Date.now() / 1000;
                    let d = new Date();
                    barWindow.timeStr = Qt.formatDateTime(d, "hh:mm:ss AP");
                    barWindow.fullDateStr = Qt.formatDateTime(d, "dddd, MMMM dd");
                    if (barWindow.typeInIndex >= barWindow.fullDateStr.length) {
                        barWindow.typeInIndex = barWindow.fullDateStr.length;
                    }
                }
            }

            Process {
                id: weatherPoller
                command: ["bash", "-c", `
                    echo "$(~/.config/hypr/scripts/quickshell/calendar/weather.sh --current-emoji)"
                    echo "$(~/.config/hypr/scripts/quickshell/calendar/weather.sh --current-temp)"
                    echo "$(~/.config/hypr/scripts/quickshell/calendar/weather.sh --current-hex)"
                `]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let lines = this.text.trim().split("\n");
                        if (lines.length >= 3) {
                            barWindow.weatherEmoji = lines[0] || "☁️";
                            barWindow.weatherTemp = lines[1];
                            barWindow.weatherHex = lines[2] || mocha.yellow;
                        }
                    }
                }
            }
            Timer { interval: 150000; running: true; repeat: true; triggeredOnStart: true; onTriggered: { weatherPoller.running = false; weatherPoller.running = true; } }


            // ==========================================
            // UI LAYOUT  (Chrome OS shelf style)
            // ==========================================
            Item {
                id: barLayer
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: barHeight
                z: 0

                // ── Background ──────────────────────────────────────
                Rectangle {
                    anchors.fill: parent
                    color: barPillFill
                }

                // ── LEFT: Launcher + Workspace dots ──────────────────
                // ── LEFT: Workspace dots only ────────────────────────
                Row {
                    id: leftSection
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: s(12)
                    spacing: s(9)
                    Repeater {
                        model: workspacesModel
                        delegate: Item {
                            required property var modelData
                            property bool wsActive: modelData.wsState === "active"
                            property bool wsOccupied: modelData.wsState === "occupied"
                            width: wsActive ? s(20) : s(8)
                            height: barHeight
                            Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                            // Dot for inactive workspaces
                            Rectangle {
                                visible: !parent.wsActive
                                anchors.centerIn: parent
                                width: s(8); height: s(8)
                                radius: s(4)
                                color: parent.wsOccupied ? mocha.subtext0 : mocha.surface0
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            // Active workspace: just the number
                            Text {
                                visible: parent.wsActive
                                anchors.centerIn: parent
                                text: modelData.wsId
                                font.pixelSize: s(13)
                                font.weight: Font.Bold
                                color: mocha.accent
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Quickshell.execDetached(["bash", "-c", "hyprctl dispatch workspace " + modelData.wsId])
                            }
                        }
                    }
                }

                // ── RIGHT: Status cluster → Quick Settings ────────────
                MouseArea {
                    id: qsClusterArea
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: s(4)
                    height: barHeight - s(6)
                    width: statusRow.implicitWidth + s(20)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "toggle", "quicksettings"])

                    Rectangle {
                        anchors.fill: parent
                        radius: s(8)
                        color: qsClusterArea.containsMouse
                               ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.55)
                               : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.30)
                        Behavior on color { ColorAnimation { duration: 110 } }
                    }

                    Row {
                        id: statusRow
                        anchors.centerIn: parent
                        spacing: s(12)

                        // VPN — only when connected
                        Text {
                            visible: barWindow.sysVpnStatus === "connected"
                            text: "󰌾"
                            font.pixelSize: s(17)
                            color: mocha.green
                            font.family: "FiraCode Nerd Font"
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        // Microphone — only when unmuted and has signal
                        Text {
                            visible: !barWindow.sysMicMuted && barWindow.sysMicVol > 0
                            text: "󰍬"
                            font.pixelSize: s(17)
                            color: mocha.red
                            font.family: "FiraCode Nerd Font"
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        // Bluetooth — only when connected to a device
                        Text {
                            visible: barWindow.btDevice !== "" && barWindow.btDevice !== "none"
                            text: "󰂯"
                            font.pixelSize: s(17)
                            color: mocha.blue
                            font.family: "FiraCode Nerd Font"
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        // UPS — only on power cut (OB = On Battery), shows charge %
                        Row {
                            visible: barWindow.sysUpsConnected && barWindow.sysUpsStatus === "OB"
                            spacing: s(3)
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                text: "󰂄"
                                font.pixelSize: s(17)
                                color: barWindow.sysUpsCharge <= 20 ? mocha.red : mocha.yellow
                                font.family: "FiraCode Nerd Font"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: barWindow.sysUpsCharge + "%"
                                font.pixelSize: s(13)
                                color: barWindow.sysUpsCharge <= 20 ? mocha.red : mocha.yellow
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        // Network — always visible
                        // Ethernet: LAN plug icon (󰒍); WiFi: signal bars from wifiIcon
                        Text {
                            text: barWindow.showEthernet ? "󰒍" : barWindow.wifiIcon
                            font.pixelSize: s(17)
                            color: (barWindow.showEthernet || barWindow.isWifiOn) ? mocha.text : mocha.subtext0
                            font.family: "FiraCode Nerd Font"
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        // Volume — always visible
                        Text {
                            text: barWindow.volIcon
                            font.pixelSize: s(17)
                            color: barWindow.isMuted ? mocha.red : mocha.text
                            font.family: "FiraCode Nerd Font"
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        // Clock — always visible
                        Text {
                            text: barWindow.timeStr
                            font.pixelSize: s(14)
                            color: mocha.text
                            font.weight: Font.Medium
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            BackgroundEffect.blurRegion: Region { item: barLayer }
}
