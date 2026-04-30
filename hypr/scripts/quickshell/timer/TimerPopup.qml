import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: window
    focus: true

    Scaler {
        id: scaler
        currentWidth: (window.width > 0 ? window.width
            : (window.parent && window.parent.width > 0 ? window.parent.width : 1920))
    }

    function s(val) {
        return scaler.s(val);
    }

    MatugenColors { id: _theme }
    readonly property color base: _theme.base
    readonly property color crust: _theme.crust
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color overlay0: _theme.overlay0
    readonly property color red: _theme.red
    readonly property color green: _theme.green

    readonly property string statePath: Quickshell.env("HOME") + "/.cache/qs_timer_state.json"
    readonly property string ctl: Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/watchers/timer_ctl.sh"

    property bool tmActive: false
    property int tmDuration: 25
    property int tmRemaining: 1500
    property double tmEnd: 0
    property double nowSec: Date.now() / 1000

    property int secsLeft: {
        if (tmActive && tmEnd > 0) {
            return Math.max(0, Math.round(tmEnd - nowSec));
        }
        return tmRemaining;
    }

    readonly property int sessionLenSec: Math.max(1, tmDuration * 60)
    readonly property real progressFrac: Math.min(1, secsLeft / sessionLenSec)

    readonly property bool isIdle: !tmActive && tmRemaining === sessionLenSec

    function fmtMMSS(secs) {
        let m = Math.floor(secs / 60);
        let sec = secs % 60;
        return (m < 10 ? "0" : "") + m + ":" + (sec < 10 ? "0" : "") + sec;
    }

    function statusLine() {
        if (tmActive)
            return "Running";
        if (isIdle)
            return "Idle";
        return "Paused";
    }

    function parseState(txt) {
        if (!txt || txt.trim() === "")
            return;
        try {
            let d = JSON.parse(txt.trim());
            let a = d.active;
            window.tmActive = a === true || a === "true" || a === "True";
            window.tmDuration = parseInt(d.duration, 10) || 25;
            window.tmRemaining = parseInt(d.remaining, 10);
            if (isNaN(window.tmRemaining))
                window.tmRemaining = window.tmDuration * 60;
            window.tmEnd = parseFloat(d.end) || 0;
        } catch (e) {}
    }

    function ctlEnv(extra) {
        return ["bash", "-c", "QS_TIMER_NO_CLOSE=1 exec \"" + window.ctl + "\" " + extra];
    }

    Keys.onEscapePressed: {
        Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "close"]);
        event.accepted = true;
    }

    Process {
        id: stateReader
        running: false
        command: ["cat", window.statePath]
        stdout: StdioCollector {
            onStreamFinished: window.parseState(this.text)
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            window.nowSec = Date.now() / 1000;
            stateReader.running = false;
            stateReader.running = true;
        }
    }

    Component.onCompleted: {
        stateReader.running = true;
    }

    Rectangle {
        anchors.fill: parent
        radius: window.s(16)
        color: window.base
        border.color: window.surface1
        border.width: 1
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: window.s(22)
            spacing: window.s(14)

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Pomodoro"
                font.family: "JetBrains Mono"
                font.weight: Font.Medium
                font.pixelSize: window.s(12)
                color: window.subtext0
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: window.fmtMMSS(window.secsLeft)
                font.family: "JetBrains Mono"
                font.pixelSize: window.s(42)
                font.weight: Font.Black
                color: window.tmActive ? window.red : window.text
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: window.statusLine() + " · " + window.tmDuration + " min session"
                font.family: "JetBrains Mono"
                font.pixelSize: window.s(11)
                color: window.overlay0
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: window.s(8)
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: window.surface0
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: Math.max(0, parent.width * window.progressFrac)
                        radius: parent.radius
                        color: window.tmActive ? window.red : window.surface1
                        Behavior on width {
                            NumberAnimation {
                                duration: 400
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: window.s(4)
                spacing: window.s(10)

                Rectangle {
                    implicitWidth: window.s(52)
                    implicitHeight: window.s(40)
                    radius: window.s(10)
                    color: minusMa.containsMouse ? window.surface1 : window.surface0
                    opacity: window.tmActive ? 0.35 : 1
                    Text {
                        anchors.centerIn: parent
                        text: "−5"
                        font.family: "JetBrains Mono"
                        font.pixelSize: window.s(12)
                        font.weight: Font.Bold
                        color: window.text
                    }
                    MouseArea {
                        id: minusMa
                        anchors.fill: parent
                        enabled: !window.tmActive
                        onClicked: Quickshell.execDetached(window.ctlEnv("adjust -5"))
                    }
                }

                Rectangle {
                    implicitWidth: window.s(64)
                    implicitHeight: window.s(44)
                    radius: window.s(12)
                    color: playMa.containsMouse ? window.surface1 : window.surface0
                    Text {
                        anchors.centerIn: parent
                        text: window.tmActive ? "󰏤" : "󰐊"
                        font.family: "Iosevka Nerd Font"
                        font.pixelSize: window.s(26)
                        color: window.green
                    }
                    MouseArea {
                        id: playMa
                        anchors.fill: parent
                        onClicked: Quickshell.execDetached(window.ctlEnv("toggle"))
                    }
                }

                Rectangle {
                    implicitWidth: window.s(52)
                    implicitHeight: window.s(40)
                    radius: window.s(10)
                    color: plusMa.containsMouse ? window.surface1 : window.surface0
                    opacity: window.tmActive ? 0.35 : 1
                    Text {
                        anchors.centerIn: parent
                        text: "+5"
                        font.family: "JetBrains Mono"
                        font.pixelSize: window.s(12)
                        font.weight: Font.Bold
                        color: window.text
                    }
                    MouseArea {
                        id: plusMa
                        anchors.fill: parent
                        enabled: !window.tmActive
                        onClicked: Quickshell.execDetached(window.ctlEnv("adjust 5"))
                    }
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: window.s(12)

                Rectangle {
                    implicitWidth: window.s(120)
                    implicitHeight: window.s(36)
                    radius: window.s(10)
                    color: resetMa.containsMouse ? window.surface1 : window.surface0
                    Text {
                        anchors.centerIn: parent
                        text: "Reset"
                        font.family: "JetBrains Mono"
                        font.pixelSize: window.s(11)
                        font.weight: Font.DemiBold
                        color: window.subtext0
                    }
                    MouseArea {
                        id: resetMa
                        anchors.fill: parent
                        onClicked: Quickshell.execDetached(window.ctlEnv("reset"))
                    }
                }

                Rectangle {
                    implicitWidth: window.s(160)
                    implicitHeight: window.s(36)
                    radius: window.s(10)
                    color: ftMa.containsMouse ? window.surface1 : window.surface0
                    Text {
                        anchors.centerIn: parent
                        text: "FocusTime…"
                        font.family: "JetBrains Mono"
                        font.pixelSize: window.s(11)
                        font.weight: Font.DemiBold
                        color: window.subtext0
                    }
                    MouseArea {
                        id: ftMa
                        anchors.fill: parent
                        onClicked: Quickshell.execDetached(["bash", "-c",
                            "~/.config/hypr/scripts/qs_manager.sh toggle focustime"])
                    }
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: window.s(4)
                text: "Esc closes · state ~/.cache/qs_timer_state.json"
                font.family: "JetBrains Mono"
                font.pixelSize: window.s(9)
                color: window.overlay0
            }
        }
    }
}
