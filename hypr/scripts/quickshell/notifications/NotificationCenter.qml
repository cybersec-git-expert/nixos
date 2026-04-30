import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "../"

// Right-docked notification history (grouped like Windows: categories + icons + inline reply when supported).
Item {
    id: window
    focus: true

    property var notifModel: null
    property var globalNotifSource: null

    Scaler {
        id: scaler
        currentWidth: Screen.width
    }

    function s(val) { return scaler.s(val); }

    function headerTitle(key) {
        switch (key) {
        case "messaging": return "Messaging & chat";
        case "system": return "System & devices";
        case "web": return "Browser";
        case "work": return "Productivity";
        case "media": return "Media";
        case "other": return "Other";
        default: return (key && key.length) ? key : "Other";
        }
    }

    function iconUri(path) {
        if (!path || path.length < 1)
            return "";
        if (path.indexOf("file://") === 0)
            return path;
        if (path.indexOf("http://") === 0 || path.indexOf("https://") === 0)
            return path;
        return "file://" + path;
    }
    // Prefer chat avatar, then app icon, then in-app monogram
    function primaryImageSource(model) {
        const p = (model && model.image) ? model.image : "";
        if (p && p.length)
            return iconUri(p);
        const ic = (model && model.iconPath) ? model.iconPath : "";
        if (ic && ic.length)
            return iconUri(ic);
        return "";
    }

    MatugenColors { id: _theme }
    readonly property color base: _theme.base
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color red: _theme.red
    readonly property color blue: _theme.blue
    readonly property color panelBg: Qt.rgba(
        _theme.mantle.r, _theme.mantle.g, _theme.mantle.b, 0.88)

    function dismissAt(index) {
        if (index < 0 || !notifModel || index >= notifModel.count)
            return;
        const item = notifModel.get(index);
        const did = item.dunstId;
        if (did !== undefined && did >= 0) {
            Quickshell.execDetached(["dunstctl", "history-rm", String(did)]);
            notifModel.remove(index);
            return;
        }
        if (item && item.notif && typeof item.notif.close === "function")
            item.notif.close();
        if (globalNotifSource && index < globalNotifSource.count)
            globalNotifSource.remove(index);
        notifModel.remove(index);
    }

    function clearAll() {
        if (!notifModel)
            return;
        let allDunst = true;
        for (let i = 0; i < notifModel.count; i++) {
            const it = notifModel.get(i);
            if (it.dunstId === undefined || it.dunstId < 0) {
                allDunst = false;
                break;
            }
        }
        if (allDunst && notifModel.count > 0) {
            Quickshell.execDetached(["dunstctl", "history-clear"]);
            notifModel.clear();
            return;
        }
        while (notifModel.count > 0) {
            const item = notifModel.get(0);
            if (item && item.notif && typeof item.notif.close === "function")
                item.notif.close();
            if (globalNotifSource && globalNotifSource.count > 0)
                globalNotifSource.remove(0);
            notifModel.remove(0);
        }
    }

    Keys.onEscapePressed: {
        Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "close"]);
        event.accepted = true;
    }

    Rectangle {
        id: body
        anchors.fill: parent
        radius: window.s(12)
        color: window.panelBg
        border.width: 0
        clip: true
    }

    Rectangle {
        z: 2
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: 1
        color: window.surface1
    }

    ColumnLayout {
        z: 1
        anchors.fill: parent
        anchors.margins: window.s(16)
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: window.s(14)
            spacing: window.s(8)

            Text {
                text: "Notifications"
                font.family: "JetBrains Mono"
                font.weight: Font.Medium
                font.pixelSize: window.s(15)
                color: window.text
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                visible: notifModel && notifModel.count > 0
                Layout.preferredHeight: window.s(30)
                Layout.preferredWidth: clearLabel.width + window.s(18)
                radius: window.s(6)
                color: clearMa.containsMouse ? Qt.lighter(window.surface0, 1.1) : window.surface0
                border.color: clearMa.containsMouse ? window.surface1 : "transparent"
                border.width: 1

                Text {
                    id: clearLabel
                    anchors.centerIn: parent
                    text: "Clear all"
                    font.family: "JetBrains Mono"
                    font.pixelSize: window.s(12)
                    color: window.subtext0
                }
                MouseArea {
                    id: clearMa
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: window.clearAll()
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ListView {
                id: list
                anchors.fill: parent
                model: notifModel
                spacing: window.s(8)
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 500

                // Manual section headers: ViewSection/section.* is not available in all Qt/Quickshell embeds
                // and can crash the engine when the panel is opened.
                delegate: Column {
                    id: delCol
                    width: list.width
                    spacing: window.s(4)
                    property string sk: (model.sectionKey && String(model.sectionKey).length)
                        ? String(model.sectionKey) : "other"
                    property bool showHeader: (function() {
                        if (index === 0) return true;
                        if (!window.notifModel || index < 1) return true;
                        var p = window.notifModel.get(index - 1);
                        var psk = (p && p.sectionKey && String(p.sectionKey).length) ? String(p.sectionKey) : "other";
                        return psk !== delCol.sk;
                    })()

                    Item {
                        width: list.width
                        height: showHeader ? window.s(28) : 0
                        visible: showHeader
                        z: 2
                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: window.headerTitle(sk)
                            font.family: "JetBrains Mono"
                            font.pixelSize: window.s(12)
                            font.weight: Font.Medium
                            color: window.blue
                        }
                    }

                    Rectangle {
                        id: delRoot
                        width: list.width
                        property var rowNotif: model.notif
                        color: dHover.containsMouse
                           ? Qt.lighter(window.base, 1.04)
                           : window.surface0
                    border.width: 1
                    border.color: window.surface1
                    radius: window.s(10)
                    height: innerCol.height + window.s(16)

                    MouseArea {
                        id: dHover
                        anchors.fill: innerCol
                        acceptedButtons: Qt.NoButton
                        hoverEnabled: true
                    }

                    ColumnLayout {
                        id: innerCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: window.s(8)
                        width: list.width - window.s(16)
                        spacing: window.s(8)

                        RowLayout {
                            id: topRow
                            Layout.fillWidth: true
                            spacing: window.s(10)

                            Item {
                                Layout.preferredWidth: window.s(40)
                                Layout.preferredHeight: window.s(40)
                                Layout.alignment: Qt.AlignTop
                                Rectangle {
                                    anchors.fill: parent
                                    radius: window.s(8)
                                    color: _theme.crust
                                    border.width: 1
                                    border.color: window.surface1
                                    clip: true
                                    Image {
                                        id: iconImg
                                        anchors.fill: parent
                                        anchors.margins: 1
                                        source: window.primaryImageSource({
                                            "image": model.image,
                                            "iconPath": model.iconPath
                                        })
                                        fillMode: Image.PreserveAspectCrop
                                        sourceSize: Qt.size(window.s(40), window.s(40))
                                        asynchronous: true
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        text: (model.appName && model.appName.length) ? model.appName.charAt(0).toUpperCase() : "?"
                                        font.pixelSize: window.s(16)
                                        font.weight: Font.Bold
                                        color: window.subtext0
                                        visible: (iconImg.status === Image.Error)
                                            || (String(iconImg.source) === "" || !iconImg.source)
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignTop
                                spacing: window.s(3)

                                Text {
                                    text: model.appName || "System"
                                    font.pixelSize: window.s(11)
                                    color: window.subtext0
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    font.family: "JetBrains Mono"
                                }
                                Text {
                                    text: model.summary || ""
                                    font.weight: Font.Medium
                                    font.pixelSize: window.s(14)
                                    color: window.text
                                    font.family: "JetBrains Mono"
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                                Text {
                                    visible: (model.body || "") !== ""
                                    text: {
                                        const b = model.body || "";
                                        return b.replace(/<[^>]+>/g, " ");
                                    }
                                    font.pixelSize: window.s(12)
                                    color: window.subtext0
                                    font.family: "JetBrains Mono"
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }

                                // Standard notification actions (Open, Dismiss, …) — use Row, not Flow (broader QML support)
                                Row {
                                    id: actRow
                                    Layout.fillWidth: true
                                    spacing: window.s(6)
                                    visible: {
                                        const n = delRoot.rowNotif;
                                        if (!n || !n.actions) return false;
                                        const nAct = n.actions;
                                        if (nAct && nAct.length !== undefined) return nAct.length > 0;
                                        if (nAct && nAct.count !== undefined) return nAct.count > 0;
                                        return false;
                                    }
                                    Repeater {
                                        id: actRep
                                        model: (function() {
                                            const n = delRoot.rowNotif;
                                            if (!n || !n.actions) return 0;
                                            if (n.actions.length !== undefined) return n.actions.length;
                                            if (n.actions.count !== undefined) return n.actions.count;
                                            return 0;
                                        })()
                                        delegate: ToolButton {
                                            required property int index
                                            text: {
                                                const n = delRoot.rowNotif;
                                                if (!n || !n.actions) return "";
                                                return n.actions[index] ? n.actions[index].text : "";
                                            }
                                            leftPadding: window.s(8)
                                            rightPadding: window.s(8)
                                            onClicked: {
                                                const n = delRoot.rowNotif;
                                                if (n && n.actions && n.actions[index] && n.actions[index].invoke)
                                                    n.actions[index].invoke();
                                            }
                                        }
                                    }
                                }
                            }

                            Text {
                                text: "✕"
                                font.pixelSize: window.s(15)
                                color: xMa.containsMouse ? window.red : window.subtext0
                                Layout.alignment: Qt.AlignTop
                                padding: window.s(2)
                                MouseArea {
                                    id: xMa
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true
                                    onClicked: window.dismissAt(index)
                                }
                            }
                        }

                        // Inline reply: requires NotificationServer.inlineReplySupported + app supports it (e.g. some Chromium toasts)
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: model.hasInlineReply === true
                                     && delRoot.rowNotif
                                     && (typeof delRoot.rowNotif.sendInlineReply === "function")
                            spacing: window.s(6)
                            TextField {
                                id: replyField
                                Layout.fillWidth: true
                                placeholderText: (model.inlineReplyPlaceholder || "Reply")
                                font.pixelSize: window.s(12)
                                font.family: "JetBrains Mono"
                                color: window.text
                                background: Rectangle {
                                    radius: window.s(6)
                                    color: _theme.crust
                                    border.color: window.surface1
                                }
                            }
                            Button {
                                text: "Send"
                                font.family: "JetBrains Mono"
                                font.pixelSize: window.s(12)
                                onClicked: {
                                    const n = delRoot.rowNotif;
                                    if (n && n.sendInlineReply)
                                        n.sendInlineReply(replyField.text);
                                }
                            }
                        }
                    }
                }
                }

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle {
                        implicitWidth: window.s(4)
                        radius: window.s(2)
                        color: window.surface2
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: !notifModel || notifModel.count === 0
                text: "No new notifications"
                font.pixelSize: window.s(14)
                color: window.subtext0
                font.family: "JetBrains Mono"
            }
        }
    }
}
