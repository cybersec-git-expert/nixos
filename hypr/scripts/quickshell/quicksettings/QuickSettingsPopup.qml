import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtCore
import Quickshell
import Quickshell.Io
import "../"

// Chrome OS-style Quick Settings popup
// Opened by: qs_manager.sh toggle quicksettings
// Position:  bottom-right above bar (set in WindowRegistry.js)
Item {
    id: root
    focus: true

    // Passed from Main.qml (for embedded notifications list, if used)
    property var notifModel: null
    property var globalNotifSource: null

    // ── Scaling (self-contained; avoids Scaler import issues) ─────────────────
    readonly property real _scale: {
        const mw = Screen.width > 0 ? Screen.width : 1920;
        const r = mw / 1920.0;
        const base = (r <= 1.0) ? Math.max(0.35, Math.pow(r, 0.85)) : Math.pow(r, 0.5);
        return base;
    }
    function s(val) { return Math.round(val * root._scale); }

    // ── Theme (self-contained fallback) ───────────────────────────────────────
    // This avoids dependency on MatugenColors loading; tweak these to match your bar.
    QtObject {
        id: mocha
        property color base:     "#1f1f23"
        property color surface0: "#2a2a2f"
        property color surface1: "#33333a"
        property color text:     "#e6e6ea"
        property color subtext0: "#b7b7c2"
        property color accent:   "#7aa2f7"
        property color blue:     "#7aa2f7"
        property color green:    "#9ece6a"
        property color yellow:   "#e0af68"
        property color red:      "#f7768e"
    }

    // ── Dismiss on Escape ─────────────────────────────────────────────────────
    Shortcut {
        sequence: "Escape"
        onActivated: Quickshell.execDetached(["bash",
            Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "close"])
    }

    // ── Data: Audio ───────────────────────────────────────────────────────────
    property int  volPercent:  50
    property bool isMuted:     false
    property int  micPercent:  0
    property bool micMuted:    true
    property int  brightness:  100

    Process {
        id: audioWatcher
        command: ["bash", "-c",
            "~/.config/hypr/scripts/quickshell/watchers/audio_fetch.sh"]
        running: true
        stdout: SplitParser {
            onRead: function(line) {
                // audio_fetch.sh outputs JSON: {"volume":"30","icon":"…","is_muted":"false"}
                try {
                    var j = JSON.parse(line);
                    root.volPercent = parseInt(j.volume) || 0;
                    root.isMuted    = (String(j.is_muted).trim() === "true");
                } catch(e) {
                    // Backwards-compatible fallback if output is ever pipe-delimited.
                    var parts = line.split("|");
                    if (parts.length >= 2) {
                        root.volPercent = parseInt(parts[0]) || 0;
                        root.isMuted    = parts[1].trim() === "true";
                    }
                    if (parts.length >= 4) {
                        root.micPercent = parseInt(parts[2]) || 0;
                        root.micMuted   = parts[3].trim() === "true";
                    }
                }
            }
        }
    }
    Timer { interval: 2000; running: true; repeat: true;
        onTriggered: { audioWatcher.running = false; audioWatcher.running = true; } }

    // ── Data: Brightness ──────────────────────────────────────────────────────
    Process {
        id: brightnessWatcher
        command: ["bash", "-c", "brightnessctl -m | awk -F, '{print $4}' | tr -d '%'"]
        running: true
        stdout: SplitParser {
            onRead: function(line) { root.brightness = parseInt(line.trim()) || 100; }
        }
    }
    Timer { interval: 3000; running: true; repeat: true;
        onTriggered: { brightnessWatcher.running = false; brightnessWatcher.running = true; } }

    // ── Data: Battery ─────────────────────────────────────────────────────────
    property int    batPercent:   100
    property string batStatus:    ""
    property string batIcon:      "󰁹"
    property color  batColor:     mocha.green

    Process {
        id: batteryWatcher
        command: ["bash", "-c",
            "~/.config/hypr/scripts/quickshell/watchers/battery_fetch.sh"]
        running: true
        stdout: SplitParser {
            onRead: function(line) {
                var parts = line.split("|");
                if (parts.length >= 3) {
                    root.batPercent = parseInt(parts[0]) || 0;
                    root.batIcon    = parts[1].trim();
                    root.batStatus  = parts[2].trim();
                    root.batColor   = root.batPercent <= 20 ? mocha.red
                                   : root.batPercent <= 50 ? mocha.yellow
                                   :                         mocha.green;
                }
            }
        }
    }
    Timer { interval: 10000; running: true; repeat: true;
        onTriggered: { batteryWatcher.running = false; batteryWatcher.running = true; } }

    // ── Data: Network ─────────────────────────────────────────────────────────
    property bool   wifiOn:       false
    property string wifiSsid:     ""
    property string wifiIcon:     "󰤭"
    property bool   showEthernet: false

    Process {
        id: networkWatcher
        command: ["bash", "-c",
            "~/.config/hypr/scripts/quickshell/watchers/network_fetch.sh"]
        running: true
        stdout: SplitParser {
            onRead: function(line) {
                try {
                    var j = JSON.parse(line);
                    root.wifiOn       = j.status === "enabled";
                    root.wifiIcon     = j.icon   || "󰤭";
                    root.wifiSsid     = j.ssid   || "";
                    root.showEthernet = j.eth_status === "Connected";
                } catch(e) {}
            }
        }
    }
    Timer { interval: 5000; running: true; repeat: true;
        onTriggered: { networkWatcher.running = false; networkWatcher.running = true; } }

    // ── Data: Bluetooth ───────────────────────────────────────────────────────
    property bool   btOn:     false
    property string btDevice: ""

    Process {
        id: btWatcher
        command: ["bash", "-c",
            "~/.config/hypr/scripts/quickshell/watchers/bt_fetch.sh"]
        running: true
        stdout: SplitParser {
            onRead: function(line) {
                var parts = line.split("|");
                if (parts.length >= 2) {
                    root.btOn     = parts[0].trim() === "true";
                    root.btDevice = parts[1].trim();
                }
            }
        }
    }
    Timer { interval: 5000; running: true; repeat: true;
        onTriggered: { btWatcher.running = false; btWatcher.running = true; } }

    // ── Data: VPN ─────────────────────────────────────────────────────────────
    property bool   vpnOn:  false
    property string vpnLoc: ""

    Process {
        id: vpnWatcher
        command: ["bash", "-c",
            "grep -q 'VPN_STATUS=connected' /tmp/qs_vpn_state 2>/dev/null && echo 'true|' || echo 'false|'"]
        running: true
        stdout: SplitParser {
            onRead: function(line) {
                var parts = line.split("|");
                root.vpnOn  = parts[0].trim() === "true";
                root.vpnLoc = parts.length > 1 ? parts[1].trim() : "";
            }
        }
    }
    Timer { interval: 8000; running: true; repeat: true;
        onTriggered: { vpnWatcher.running = false; vpnWatcher.running = true; } }

    // ── Action runner ─────────────────────────────────────────────────────────
    Process { id: actionRunner; command: [] }
    function run(cmd) {
        actionRunner.command = ["bash", "-c", cmd];
        actionRunner.running = true;
    }

    // ── Volume setter (debounced) ─────────────────────────────────────────────
    property int pendingVol: -1
    Timer {
        id: volDebounce; interval: 80; repeat: false
        onTriggered: {
            if (root.pendingVol < 0)
                return;
            // Match the Super+V volume panel backend and avoid triggering SwayOSD OSD.
            // Prefer pactl default sink name + shared audio_control.sh; fall back to wpctl.
            root.run(
                "SINK=$(pactl get-default-sink 2>/dev/null || true); "
                + "if [ -n \"$SINK\" ]; then "
                + "  ~/.config/hypr/scripts/quickshell/volume/audio_control.sh set-volume sink \"$SINK\" " + root.pendingVol + " >/dev/null 2>&1 || true; "
                + "else "
                + "  wpctl set-volume @DEFAULT_AUDIO_SINK@ " + root.pendingVol + "% >/dev/null 2>&1 || true; "
                + "fi"
            );
        }
    }

    // ── Brightness setter (debounced) ─────────────────────────────────────────
    property int pendingBright: -1
    Timer {
        id: brightDebounce; interval: 80; repeat: false
        onTriggered: {
            if (root.pendingBright >= 0)
                root.run("brightnessctl s " + root.pendingBright + "%");
        }
    }

    // ── Data: Do Not Disturb ──────────────────────────────────────────────────
    property bool isDnd: false
    Process {
        id: dndWatcher
        command: ["bash", "-c", "dunstctl is-paused 2>/dev/null || echo false"]
        running: true
        stdout: SplitParser {
            onRead: function(line) { root.isDnd = line.trim() === "true"; }
        }
    }
    Timer { interval: 4000; running: true; repeat: true;
        onTriggered: { dndWatcher.running = false; dndWatcher.running = true; } }

    // ── Dark theme state (toggled by script) ──────────────────────────────────
    property bool isDarkTheme: true

    // ── Clock for date display ────────────────────────────────────────────────
    property string currentDate: Qt.formatDateTime(new Date(), "ddd, MMM d")
    Timer { interval: 60000; running: true; repeat: true;
        onTriggered: root.currentDate = Qt.formatDateTime(new Date(), "ddd, MMM d") }

    // ═══════════════════════════════════════════════════════════════════════════
    // VISUAL LAYOUT
    // ═══════════════════════════════════════════════════════════════════════════
    // (TogglePill component is defined further down in this file)

    component TogglePill: Item {
        property string icon:        ""
        property string label:       ""
        property bool   active:      false
        property color  activeColor: mocha.accent
        property string settingsCmd: ""
        signal toggled()
        width:  (mainCol.width - 2 * s(8)) / 3
        height: s(64)
        Rectangle {
            id: pillBg
            anchors.fill: parent
            radius: s(14)
            color:  active
                    ? Qt.rgba(activeColor.r, activeColor.g, activeColor.b, 0.22)
                    : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.7)
            border.color: active
                          ? Qt.rgba(activeColor.r, activeColor.g, activeColor.b, 0.5)
                          : "transparent"
            border.width: 1
            Behavior on color { ColorAnimation { duration: 130 } }
        }
        // If not active, show single full pill
        Item {
            anchors.fill: parent
            visible: !active || settingsCmd === ""
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: toggled()
                Column {
                    anchors.centerIn: parent
                    spacing: s(4)
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: icon
                        font.pixelSize: s(20)
                        color: active ? activeColor : mocha.subtext0
                        font.family: "FiraCode Nerd Font"
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: label
                        font.pixelSize: s(11)
                        color: active ? mocha.text : mocha.subtext0
                        elide: Text.ElideRight
                        width: parent.parent.width - s(8)
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
        // If active, show split pill with arrow
        Row {
            anchors.fill: parent
            visible: active && settingsCmd !== ""
            spacing: 0
            // Toggle area
            MouseArea {
                width: parent.parent.width - s(28)
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                cursorShape: Qt.PointingHandCursor
                onClicked: toggled()
                Column {
                    anchors.centerIn: parent
                    spacing: s(4)
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: icon
                        font.pixelSize: s(20)
                        color: active ? activeColor : mocha.subtext0
                        font.family: "FiraCode Nerd Font"
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: label
                        font.pixelSize: s(11)
                        color: active ? mocha.text : mocha.subtext0
                        elide: Text.ElideRight
                        width: parent.parent.width - s(36)
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
            // Divider
            Rectangle {
                width: 1
                height: parent.height * 0.55
                color: active ? Qt.rgba(activeColor.r, activeColor.g, activeColor.b, 0.45)
                         : Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.8)
                anchors.verticalCenter: parent.verticalCenter
            }
            // Arrow button
            MouseArea {
                width: s(28)
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: root.run(parent.parent.settingsCmd)
                Rectangle {
                    anchors.fill: parent
                    color: parent.containsMouse ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.5) : "transparent"
                    Behavior on color { ColorAnimation { duration: 100 } }
                }
                Text {
                    anchors.centerIn: parent
                    text: "›"
                    font.pixelSize: s(16)
                    color: active ? activeColor : mocha.subtext0
                    font.family: "FiraCode Nerd Font"
                }
            }
        }
    }

    Rectangle {
        id: panel
        anchors.fill: parent
        radius: s(16)
        color: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.94)
        border.color: Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.6)
        border.width: 1

        Column {
            id: mainCol
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: s(14)
            anchors.leftMargin: s(14)
            anchors.rightMargin: s(14)
            spacing: s(8)

            Row {
                width: parent.width
                spacing: s(8)
                anchors.topMargin: s(4)
                anchors.bottomMargin: s(4)

                // Network — toggle wifi, arrow opens nm-connection-editor
                TogglePill {
                    icon:        root.showEthernet ? "󰒍" : (root.wifiOn ? root.wifiIcon : "󰤭")
                    label:       root.showEthernet ? "Ethernet" : (root.wifiOn ? (root.wifiSsid !== "" ? root.wifiSsid : "WiFi") : "WiFi")
                    active:      root.showEthernet || root.wifiOn
                    activeColor: mocha.blue
                    settingsCmd: "nm-connection-editor"
                    onToggled:   root.run("nmcli radio wifi " + ((root.wifiOn && !root.showEthernet) ? "off" : "on"))
                }

                // Bluetooth — toggle power, arrow opens blueman
                TogglePill {
                    icon:        root.btOn ? "󰂯" : "󰂲"
                    label:       root.btOn ? (root.btDevice !== "" ? root.btDevice : "Bluetooth") : "Bluetooth"
                    active:      root.btOn
                    activeColor: mocha.blue
                    settingsCmd: "blueman-manager"
                    onToggled:   root.run("bluetoothctl power " + (root.btOn ? "off" : "on"))
                }

                // VPN — toggle, arrow opens nm-connection-editor
                TogglePill {
                    icon:        root.vpnOn ? "󰌾" : "󰌿"
                    label:       root.vpnOn ? "VPN On" : "VPN"
                    active:      root.vpnOn
                    activeColor: mocha.green
                    settingsCmd: "nm-connection-editor"
                    onToggled:   root.run("~/.config/hypr/scripts/vpn-toggle.sh")
                }
            }

            // ── DIVIDER ──────────────────────────────────────────────────────
            Rectangle { width: parent.width; height: 1; color: mocha.surface0; opacity: 0.8 }

            // ── MAIN ACTION TILES: Screenshot | Dark Theme | Do Not Disturb ──
            Row {
                width: parent.width
                spacing: s(8)
                anchors.topMargin: s(4)
                anchors.bottomMargin: s(4)

                component ActionTile: Rectangle {
                    property string icon:        ""
                    property string label:       ""
                    property bool   active:      false
                    property color  activeColor: mocha.accent
                    signal clicked()
                    width:  (parent.width - 2 * s(8)) / 3
                    height: s(72)
                    radius: s(14)
                    color:  active
                            ? Qt.rgba(activeColor.r, activeColor.g, activeColor.b, 0.18)
                            : (tileHov.containsMouse
                               ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.9)
                               : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.6))
                    Behavior on color { ColorAnimation { duration: 110 } }
                    Column {
                        anchors.centerIn: parent
                        spacing: s(5)
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text:           icon
                            font.pixelSize: s(22)
                            color:          active ? activeColor : mocha.text
                            font.family:    "FiraCode Nerd Font"
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text:           label
                            font.pixelSize: s(11)
                            color:          active ? activeColor : mocha.subtext0
                        }
                    }
                    MouseArea {
                        id: tileHov
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape:  Qt.PointingHandCursor
                        onClicked:    parent.clicked()
                    }
                }
                ActionTile {
                    icon:  "󰹑"
                    label: "Screenshot"
                    onClicked: root.run("grimblast copy area")
                }
                ActionTile {
                    icon:        root.isDarkTheme ? "󰖔" : "󰖙"
                    label:       root.isDarkTheme ? "Dark" : "Light"
                    active:      root.isDarkTheme
                    activeColor: mocha.blue
                    onClicked: {
                        root.isDarkTheme = !root.isDarkTheme;
                        root.run("~/.config/hypr/scripts/toggle-dark.sh");
                    }
                }
                ActionTile {
                    icon:        root.isDnd ? "󰂛" : "󰂚"
                    label:       root.isDnd ? "Silent" : "Notify"
                    active:      root.isDnd
                    activeColor: mocha.red
                    onClicked:   root.run("dunstctl set-paused toggle")
                }
            }

            // ── VOLUME SLIDER (moved to bottom) ────────────────────────────
            Item { width: parent.width; height: s(4) }

        } // mainCol

        // ── VOLUME SLIDER (bottom, above date) ─────────────────────────────
        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            // Lift the bottom cluster so the slider/date aren't glued to the border.
            anchors.bottomMargin: s(16)
            anchors.leftMargin: s(14)
            anchors.rightMargin: s(14)
            spacing: s(6)
            Row {
                width: parent.width
                Text {
                    text:           root.isMuted ? "󰝟" : "󰕾"
                    font.pixelSize: s(17)
                    color:          root.isMuted ? mocha.red : mocha.text
                    font.family:    "FiraCode Nerd Font"
                    anchors.verticalCenter: parent.verticalCenter
                }
                Item { width: s(8); height: 1 }
                Text {
                    text:           "Volume"
                    font.pixelSize: s(13)
                    color:          mocha.subtext0
                    anchors.verticalCenter: parent.verticalCenter
                }
                Item { width: 1; height: 1 }
                Text {
                    text:           root.volPercent + "%"
                    font.pixelSize: s(13)
                    color:          mocha.text
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            Item {
                width: parent.width
                height: s(22)
                Rectangle {
                    id: volTrack
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: s(6)
                    radius: s(3)
                    color: mocha.surface1
                    Rectangle {
                        width: volTrack.width * (root.volPercent / 100)
                        height: parent.height
                        radius: parent.radius
                        color: mocha.accent
                    }
                }
                Rectangle {
                    width: s(18); height: s(18)
                    radius: s(9)
                    color: mocha.accent
                    x: (volTrack.width - width) * (root.volPercent / 100)
                    anchors.verticalCenter: parent.verticalCenter
                }
                MouseArea {
                    anchors.fill: parent
                    property bool pressed: false
                    onPressed:         function(e) { pressed = true; setVol(e.x); }
                    onReleased:        function(e) { pressed = false; }
                    onPositionChanged: function(e) { if (pressed) setVol(e.x); }
                    function setVol(x) {
                        var pct = Math.max(0, Math.min(100, Math.round(x / width * 100)));
                        root.volPercent = pct;
                        root.pendingVol = pct;
                        volDebounce.restart();
                    }
                }
            }
            // ── DATE — bottom left ───────────────────────────────────────
            Text {
                anchors.left: parent.left
                text:           root.currentDate
                font.pixelSize: s(12)
                color:          mocha.subtext0
                // Small extra breathing room within the bottom cluster.
                padding: s(2)
            }
        }
        // Column

    } // Rectangle panel
} // Item root
