import QtQuick
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications
import "WindowRegistry.js" as Registry

import "notifications" as Notifs

PanelWindow {
    id: masterWindow
    color: "transparent"

    // Pin overlay UI (Super+C stack, wallpaper picker, etc.) to the HP panel (Hyprland output).
    readonly property string primaryHyprOutput: {
        const e = Quickshell.env("QS_PRIMARY_OUTPUT");
        return (e && String(e).trim() !== "") ? String(e).trim() : "DP-3";
    }
    screen: {
        const screens = Quickshell.screens;
        const want = masterWindow.primaryHyprOutput;
        for (let i = 0; i < screens.length; i++) {
            const s = screens[i];
            if (s && s.name === want)
                return s;
        }
        return screens.length ? screens[0] : undefined;
    }
    
    IpcHandler {
        target: "main"
    
        function forceReload() {
            Quickshell.reload(true) 
        }

        // Direct dispatch from qs_manager / qs ipc — avoids races where inotify misses
        // a write that happened before Main's file watcher was listening.
        // Types are required or Quickshell will not register the handler (see IpcHandler docs).
        function dispatchFromWidget(raw: string): void {
            masterWindow.processWidgetIpc(raw !== undefined && raw !== null ? String(raw) : "");
        }
    }

    WlrLayershell.namespace: "qs-master"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    exclusionMode: ExclusionMode.Ignore 
    focusable: true

    width: Screen.width
    height: Screen.height

    visible: isVisible

    mask: Region { item: bottomBarHole; intersection: Intersection.Xor }
    
    Item {
        id: bottomBarHole
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 65 
    }

    MouseArea {
        anchors.fill: parent
        enabled: masterWindow.isVisible
        onClicked: switchWidget("hidden", "")
    }

    property string currentActive: "hidden"

    onCurrentActiveChanged: {
        // Broadcast active state so TopBar knows when to morph
        Quickshell.execDetached(["bash", "-c", "echo '" + currentActive + "' > /tmp/qs_current_widget"]);
    }

    property bool isVisible: false
    property string activeArg: ""
    property bool disableMorph: false 
    property int morphDuration: 500
    property int exitDuration: 300 // Controls how fast the outgoing widget disappears

    property real animW: 1
    property real animH: 1
    property real animX: 0
    property real animY: 0
    
    property real targetW: 1
    property real targetH: 1

    property real globalUiScale: 1.0

    // Shared frosted-surface tint for all in-window widgets (calendar/music/network/etc.)
    // Desktop blur is provided by Hyprland layerrule blur + (if supported) BackgroundEffect.
    readonly property color frostTint: Qt.rgba(0.10, 0.10, 0.12, 0.52)

    // dunst history fallback (Quickshell cannot receive toasts if dunst/mako owns the FD.o bus)
    readonly property string dunstFlatJsonPath: Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/watchers/dunst_history_flatjson.py"

    // QQmlListModel does not create a role for null members; accessing model.notif then segfaults in data().
    function notifRoleForListModel(n) {
        if (n !== undefined && n !== null)
            return n;
        return {};
    }

    // --- Notification center: category buckets (stable keys) + section titles ---
    function sectionTitleFromKey(key) {
        switch (key) {
        case "messaging": return "Messaging & chat";
        case "system": return "System & devices";
        case "web": return "Browser";
        case "work": return "Productivity";
        case "media": return "Media";
        default: return "Other";
        }
    }
    function sectionOrderRank(key) {
        const m = { messaging: 0, system: 1, web: 2, work: 3, media: 4, other: 5 };
        return m[key] !== undefined ? m[key] : 5;
    }
    function computeSectionKey(appName, body, categoryHint) {
        const a = (appName || "").toLowerCase();
        const b = (body || "").toLowerCase();
        const c = (categoryHint || "").toLowerCase();
        if (c && (c.indexOf("im") >= 0 || c.indexOf("message") >= 0 || c.indexOf("email") >= 0))
            return "messaging";
        if (a.indexOf("whatsapp") >= 0 || b.indexOf("web.whatsapp") >= 0 || b.indexOf("whatsapp") >= 0)
            return "messaging";
        if (a.indexOf("telegram") >= 0 || a.indexOf("signal") >= 0 || a.indexOf("discord") >= 0
            || a.indexOf("slack") >= 0 || a.indexOf("element") >= 0)
            return "messaging";
        if (a === "system" || a.indexOf("packagekit") >= 0 || a.indexOf("pamac") >= 0)
            return "system";
        if (a.indexOf("spotify") >= 0 || a.indexOf("mpv") >= 0 || a.indexOf("vlc") >= 0)
            return "media";
        if (a.indexOf("brave") >= 0 || a.indexOf("chrome") >= 0 || a.indexOf("chromium") >= 0
            || a.indexOf("firefox") >= 0 || a.indexOf("zen") >= 0)
            return "web";
        if (a.indexOf("code") >= 0 || a.indexOf("cursor") >= 0 || a.indexOf("obsidian") >= 0)
            return "work";
        return "other";
    }
    function notifDataFromReceived(n) {
        const appName = n.appName !== "" ? n.appName : "System";
        const body = n.body !== "" ? n.body : "";
        const sk = masterWindow.computeSectionKey(appName, body, "");
        n.tracked = true;
        return {
            "appName": appName,
            "summary": n.summary !== "" ? n.summary : "No Title",
            "body": body,
            "iconPath": n.appIcon !== "" ? n.appIcon : "",
            "image": n.image !== "" ? n.image : "",
            "sectionKey": sk,
            "sectionLabel": masterWindow.sectionTitleFromKey(sk),
            "hasInlineReply": n.hasInlineReply === true,
            "inlineReplyPlaceholder": n.inlineReplyPlaceholder || "Reply",
            "dunstCategory": "",
            "dunstId": -1,
            "notif": notifRoleForListModel(n)
        };
    }

    // =========================================================
    // --- DAEMON: NOTIFICATION HANDLING
    // =========================================================
    // 1. Permanent History (For the Notification Center)
    ListModel {
        id: globalNotificationHistory
    }
    // What NotificationCenter shows: quickshell history, or (if empty) entries from `dunstctl history`
    ListModel {
        id: notificationCenterDisplay
    }

    // 2. Transient Popups (For the OSD)
    ListModel {
        id: activePopupsModel
    }

    property int _popupCounter: 0

    function removePopup(uid) {
        for (let i = 0; i < activePopupsModel.count; i++) {
            if (activePopupsModel.get(i).uid === uid) {
                activePopupsModel.remove(i);
                break;
            }
        }
    }

    NotificationServer {
        id: globalNotificationServer
        bodySupported: true
        actionsSupported: true
        imageSupported: true
        // inlineReplySupported and actionIconsSupported require newer quickshell; omit for compatibility

        onNotification: (n) => {
            console.log("Saving to history:", n.appName, "-", n.summary);
            const notifData = masterWindow.notifDataFromReceived(n);
            // A. Insert into the permanent center
            globalNotificationHistory.insert(0, notifData);

            // B. Append to the on-screen popups
            masterWindow._popupCounter++;
            let popupData = Object.assign({ "uid": masterWindow._popupCounter }, notifData);
            activePopupsModel.append(popupData);

            masterWindow.publishNotifCount();
        }
    }    
    // StackView / NotificationCenter use this; it is filled from `globalNotificationHistory` or dunst
    property var notifModel: notificationCenterDisplay

    function displayRowFromGlobal(row, origIndex) {
        const app = row.appName !== undefined ? row.appName : "System";
        const body = row.body !== undefined ? row.body : "";
        const dcat = row.dunstCategory !== undefined ? row.dunstCategory : "";
        const sk = row.sectionKey
            || masterWindow.computeSectionKey(app, body, dcat);
        return {
            "appName": app,
            "summary": row.summary !== undefined ? row.summary : "",
            "body": body,
            "iconPath": row.iconPath !== undefined ? row.iconPath : "",
            "image": row.image !== undefined ? row.image : "",
            "sectionKey": sk,
            "sectionLabel": row.sectionLabel || masterWindow.sectionTitleFromKey(sk),
            "hasInlineReply": row.hasInlineReply === true,
            "inlineReplyPlaceholder": row.inlineReplyPlaceholder || "Reply",
            "dunstCategory": dcat,
            "dunstId": row.dunstId !== undefined ? row.dunstId : -1,
            "notif": notifRoleForListModel(row.notif),
            "_order": origIndex
        };
    }
    function refreshNotificationCenterModel() {
        notificationCenterDisplay.clear();
        const rows = [];
        for (let i = 0; i < globalNotificationHistory.count; i++)
            rows.push(masterWindow.displayRowFromGlobal(globalNotificationHistory.get(i), i));
        rows.sort((a, b) => {
            const ra = masterWindow.sectionOrderRank(a.sectionKey);
            const rb = masterWindow.sectionOrderRank(b.sectionKey);
            if (ra !== rb)
                return ra - rb;
            return a._order - b._order;
        });
        for (let j = 0; j < rows.length; j++) {
            const r = rows[j];
            notificationCenterDisplay.append({
                "appName": r.appName,
                "summary": r.summary,
                "body": r.body,
                "iconPath": r.iconPath,
                "image": r.image,
                "sectionKey": r.sectionKey,
                "sectionLabel": r.sectionLabel,
                "hasInlineReply": r.hasInlineReply,
                "inlineReplyPlaceholder": r.inlineReplyPlaceholder,
                "dunstCategory": r.dunstCategory,
                "dunstId": r.dunstId,
                "notif": notifRoleForListModel(r.notif)
            });
        }
        if (notificationCenterDisplay.count === 0) {
            dunstHistoryLoader.running = false;
            dunstHistoryLoader.running = true;
        }
    }

    Process {
        id: dunstHistoryLoader
        running: false
        command: ["python3", masterWindow.dunstFlatJsonPath]
        stdout: StdioCollector {
            onStreamFinished: {
                if (globalNotificationHistory.count > 0)
                    return;
                const txt = this.text.trim();
                if (txt === "")
                    return;
                try {
                    const arr = JSON.parse(txt);
                    if (!Array.isArray(arr) || arr.length === 0)
                        return;
                    const drows = [];
                    for (let j = 0; j < arr.length; j++)
                        drows.push(arr[j]);
                    drows.sort((a, b) => {
                        const ra = masterWindow.sectionOrderRank(a.sectionKey || "other");
                        const rb = masterWindow.sectionOrderRank(b.sectionKey || "other");
                        if (ra !== rb)
                            return ra - rb;
                        return 0;
                    });
                    for (let k = 0; k < drows.length; k++) {
                        const row = drows[k];
                        const sk = row.sectionKey
                            || masterWindow.computeSectionKey(row.appName, row.body, row.dunstCategory);
                        notificationCenterDisplay.append({
                            "appName": row.appName || "System",
                            "summary": row.summary || "",
                            "body": row.body || "",
                            "iconPath": row.iconPath || "",
                            "image": row.image || "",
                            "sectionKey": sk,
                            "sectionLabel": row.sectionLabel || masterWindow.sectionTitleFromKey(sk),
                            "hasInlineReply": false,
                            "inlineReplyPlaceholder": "Reply",
                            "dunstCategory": row.dunstCategory || "",
                            "notif": notifRoleForListModel(null),
                            "dunstId": row.dunstId !== undefined ? row.dunstId : -1
                        });
                    }
                } catch (e) {
                    console.log("dunst history parse:", e);
                }
            }
        }
    }

    // Persist Quickshell-side count; TopBar `sys_stats` also merges `dunstctl count history` when dunst is active
    function publishNotifCount() {
        const home = Quickshell.env("HOME");
        const f = home + "/.cache/qs_notif_count";
        Quickshell.execDetached(["bash", "-c", "mkdir -p \"" + home + "/.cache\" && echo " + globalNotificationHistory.count + " > \"" + f + "\""]);
    }
    Connections {
        target: globalNotificationHistory
        function onCountChanged() { masterWindow.publishNotifCount(); }
    }
    Component.onCompleted: publishNotifCount()
    
    // --- INSTANTIATE THE POPUP OVERLAY ---
    Notifs.NotificationPopups {
        id: osdPopups
        popupModel: activePopupsModel
        uiScale: masterWindow.globalUiScale
    }
    // =========================================================

    onGlobalUiScaleChanged: {
        handleNativeScreenChange();
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
                        if (parsed.uiScale !== undefined && masterWindow.globalUiScale !== parsed.uiScale) {
                            masterWindow.globalUiScale = parsed.uiScale;
                        }
                    }
                } catch (e) {
                    console.log("Error parsing settings.json in main.qml:", e);
                }
            }
        }
    }

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

    function getLayout(name) {
        return Registry.getLayout(name, 0, 0, Screen.width, Screen.height, masterWindow.globalUiScale);
    }

    function processWidgetIpc(rawCmd) {
        if (rawCmd === "")
            return;

        let parts = rawCmd.split(":");
        let cmd = parts[0];

        if (cmd === "close") {
            switchWidget("hidden", "");
        } else if (cmd === "toggle" || cmd === "open") {
            let targetWidget = parts.length > 1 ? parts[1] : "";
            let arg = parts.length > 2 ? parts.slice(2).join(":") : "";

            delayedClear.stop();

            if (targetWidget === masterWindow.currentActive) {
                let currentItem = widgetStack.currentItem;

                if (arg !== "" && currentItem && currentItem.activeMode !== undefined && currentItem.activeMode !== arg) {
                    currentItem.activeMode = arg;
                } else if (cmd === "toggle") {
                    switchWidget("hidden", "");
                }
            } else if (getLayout(targetWidget)) {
                switchWidget(targetWidget, arg);
            }
        } else if (getLayout(cmd)) {
            let arg = parts.length > 1 ? parts.slice(1).join(":") : "";
            delayedClear.stop();

            if (cmd === masterWindow.currentActive) {
                let currentItem = widgetStack.currentItem;
                if (arg !== "" && currentItem && currentItem.activeMode !== undefined && currentItem.activeMode !== arg) {
                    currentItem.activeMode = arg;
                } else {
                    switchWidget("hidden", "");
                }
            } else {
                switchWidget(cmd, arg);
            }
        }
    }

    Connections {
        target: Screen
        function onWidthChanged() { handleNativeScreenChange(); }
        function onHeightChanged() { handleNativeScreenChange(); }
    }

    function handleNativeScreenChange() {
        if (masterWindow.currentActive === "hidden") return;
        
        let t = getLayout(masterWindow.currentActive);
        if (t) {
            masterWindow.animX = t.rx;
            masterWindow.animY = t.ry;
            masterWindow.animW = t.w;
            masterWindow.animH = t.h;
            masterWindow.targetW = t.w;
            masterWindow.targetH = t.h;
        }
    }

    onIsVisibleChanged: {
        if (isVisible) {
            widgetContainer.forceActiveFocus();
        }
    }

    // User-dragged offset added on top of the layout-computed position.
    property real userDragX: 0
    property real userDragY: 0
    property bool userDragging: false

    Item {
        id: widgetContainer
        x: masterWindow.animX + masterWindow.userDragX
        y: masterWindow.animY + masterWindow.userDragY
        width: masterWindow.animW
        height: masterWindow.animH
        clip: true 
        layer.enabled: true 

        focus: true
        // Catch ESC at this level so it works even when child widgets steal focus.
        Keys.onEscapePressed: (event) => {
            switchWidget("hidden", "");
            event.accepted = true;
        }

        // Smoother easing type: OutExpo makes animations feel snappy yet perfectly fluid
        Behavior on x { enabled: !masterWindow.disableMorph && !masterWindow.userDragging; NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutExpo } }
        Behavior on y { enabled: !masterWindow.disableMorph && !masterWindow.userDragging; NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutExpo } }
        Behavior on width { enabled: !masterWindow.disableMorph; NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutExpo } }
        Behavior on height { enabled: !masterWindow.disableMorph; NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutExpo } }

        opacity: masterWindow.isVisible ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: masterWindow.morphDuration === 500 ? 300 : 200; easing.type: Easing.InOutSine } }

        MouseArea {
            anchors.fill: parent
        }

        // Must fill the morphing container (animW × animH). Centering here with a fixed
        // targetW while parent.width follows animW shifts the whole StackView by
        // (animW − targetW)/2 — the drag pill then sits off the true window center vs the bar clock.
        Item {
            anchors.fill: parent

            // Unified background (tint) behind every widget view.
            // Individual widgets can still draw their own chrome on top.
            Rectangle {
                anchors.fill: parent
                color: masterWindow.frostTint
                radius: 18 * masterWindow.globalUiScale
                z: -10
            }

            StackView {
                id: widgetStack
                anchors.fill: parent
                focus: true

                // Forward unhandled keys to the container so ESC always closes.
                Keys.forwardTo: [widgetContainer]

                Keys.onEscapePressed: (event) => {
                    switchWidget("hidden", "");
                    event.accepted = true;
                }

                onCurrentItemChanged: {
                    if (currentItem) currentItem.forceActiveFocus();
                }

                // Handle content-driven resize requests (e.g. MusicPopup EQ toggle)
                Connections {
                    target: widgetStack.currentItem
                    ignoreUnknownSignals: true
                    function onResizeRequested(newH) {
                        masterWindow.animH = newH;
                        masterWindow.targetH = newH;
                    }
                }

                replaceEnter: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 400; easing.type: Easing.OutExpo }
                        NumberAnimation { property: "scale"; from: 0.98; to: 1.0; duration: 400; easing.type: Easing.OutBack }
                    }
                }
                replaceExit: Transition {
                    ParallelAnimation {
                        // Uses the dynamically set exitDuration
                        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: masterWindow.exitDuration; easing.type: Easing.InExpo }
                        NumberAnimation { property: "scale"; from: 1.0; to: 1.02; duration: masterWindow.exitDuration; easing.type: Easing.InExpo }
                    }
                }
            }

            // ---------------------------------------------------------------
            // DRAG HANDLE: thin strip at the top of every widget. Click-drag
            // to reposition the popup. Double-click to snap back to default.
            // ---------------------------------------------------------------
            Item {
                id: dragHandle
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                height: 18
                z: 9999

                Rectangle {
                    anchors.centerIn: parent
                    width: 56
                    height: 5
                    radius: 3
                    color: dragArea.pressed ? "#aaffffff"
                         : dragArea.containsMouse ? "#88ffffff"
                         : "#44ffffff"
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                MouseArea {
                    id: dragArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    acceptedButtons: Qt.LeftButton

                    property real startMouseX: 0
                    property real startMouseY: 0
                    property real startDragX: 0
                    property real startDragY: 0

                    onPressed: (mouse) => {
                        startMouseX = mouse.x;
                        startMouseY = mouse.y;
                        startDragX = masterWindow.userDragX;
                        startDragY = masterWindow.userDragY;
                        masterWindow.userDragging = true;
                    }
                    onPositionChanged: (mouse) => {
                        if (!pressed) return;
                        masterWindow.userDragX = startDragX + (mouse.x - startMouseX);
                        masterWindow.userDragY = startDragY + (mouse.y - startMouseY);
                    }
                    onReleased: {
                        masterWindow.userDragging = false;
                    }
                    onDoubleClicked: {
                        masterWindow.userDragX = 0;
                        masterWindow.userDragY = 0;
                    }
                }
            }
        }
    }

    function switchWidget(newWidget, arg) {
        // REMOVED: Quickshell.execDetached file writing. State is strictly in memory now.

        prepTimer.stop();
        delayedClear.stop();

        // Reset any user drag whenever we change the active widget so each
        // panel reopens at its registry-defined home position.
        if (newWidget !== currentActive) {
            masterWindow.userDragX = 0;
            masterWindow.userDragY = 0;
            masterWindow.userDragging = false;
        }

        if (newWidget === "hidden") {
            if (currentActive !== "hidden") {
                masterWindow.morphDuration = 250; 
                masterWindow.exitDuration = 250;
                masterWindow.disableMorph = false;
                
                masterWindow.animW = 1;
                masterWindow.animH = 1;
                masterWindow.isVisible = false; 
                
                delayedClear.start();
            }
        } else {
            if (currentActive === "hidden") {
                masterWindow.morphDuration = 250;
                masterWindow.exitDuration = 300;
                masterWindow.disableMorph = false;
                
                let t = getLayout(newWidget);
                masterWindow.animX = t.rx;
                masterWindow.animY = t.ry;
                masterWindow.animW = 1;
                masterWindow.animH = 1;

                prepTimer.newWidget = newWidget;
                prepTimer.newArg = arg;
                prepTimer.start();
                
            } else {
                // Morphing directly between widgets (including wallpaper)
                masterWindow.morphDuration = 500;
                masterWindow.disableMorph = false;
                
                // If transitioning to wallpaper, make the previous widget disappear significantly faster
                masterWindow.exitDuration = (newWidget === "wallpaper") ? 100 : 300;
                
                executeSwitch(newWidget, arg, false);
            }
        }
    }

    Timer {
        id: prepTimer
        interval: 50
        property string newWidget: ""
        property string newArg: ""
        onTriggered: executeSwitch(newWidget, newArg, false)
    }

    function executeSwitch(newWidget, arg, immediate) {
        if (newWidget === "notifications")
            masterWindow.refreshNotificationCenterModel();

        masterWindow.currentActive = newWidget;
        masterWindow.activeArg = arg;
        
        let t = getLayout(newWidget);
        masterWindow.animX = t.rx;
        masterWindow.animY = t.ry;
        masterWindow.animW = t.w;
        masterWindow.animH = t.h;
        masterWindow.targetW = t.w;
        masterWindow.targetH = t.h;
        
        let props = newWidget === "wallpaper" ? { "widgetArg": arg } : {};
        // Only pass notif models to widgets that declare them.
        if (newWidget === "notifications" || newWidget === "quicksettings") {
            props["notifModel"] = masterWindow.notifModel;
            props["globalNotifSource"] = masterWindow.globalNotificationHistory;
        }

        if (immediate) {
            widgetStack.replace(t.comp, props, StackView.Immediate);
        } else {
            widgetStack.replace(t.comp, props);
        }
        
        masterWindow.isVisible = true;
    }

    // =========================================================
    // --- IPC: EVENT-DRIVEN WATCHER
    // =========================================================
    Process {
        id: ipcWatcher
        command: ["bash", "-c",
            "touch /tmp/qs_widget_state; " +
            "inotifywait -qq -e close_write /tmp/qs_widget_state 2>/dev/null; " +
            "cat /tmp/qs_widget_state"
        ]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                masterWindow.processWidgetIpc(this.text.trim());
                ipcWatcher.running = false;
                ipcWatcher.running = true;
            }
        }
    }    
    Timer {
        id: delayedClear
        interval: masterWindow.morphDuration 
        onTriggered: {
            masterWindow.currentActive = "hidden";
            widgetStack.clear();
            masterWindow.disableMorph = false;
        }
    }

    // Compositor blur behind the widget surface (ext-background-effect-v1).
    // If the compositor doesn't support the protocol, Hyprland's layerrule blur still handles it.
    BackgroundEffect.blurRegion: Region { item: widgetContainer }
}
