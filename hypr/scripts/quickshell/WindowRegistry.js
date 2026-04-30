.pragma library

function getScale(mw, userScale) {
    if (mw <= 0) return 1.0;
    let r = mw / 1920.0;
    let baseScale = 1.0;
    
    if (r <= 1.0) {
        baseScale = Math.max(0.35, Math.pow(r, 0.85));
    } else {
        baseScale = Math.pow(r, 0.5);
    }
    
    return baseScale * (userScale !== undefined ? userScale : 1.0);
}

function s(val, scale) {
    return Math.round(val * scale);
}

function getLayout(name, mx, my, mw, mh, userScale) {
    let scale = getScale(mw, userScale);

    // Space reserved for the bottom bar + mask (keep in sync with TopBar barHeight: 48px)
    let barReserve = 52;
    function ryOpenAbove(h) {
        return Math.max(s(8, scale), mh - h - s(barReserve, scale));
    }

    // Calendar: never wider than the shell width (avoids clipped wings); rx must use the same calW as w.
    let calIdeal = s(1680, scale);
    let calW = Math.min(calIdeal, Math.max(s(1040, scale), mw - s(32, scale)));
    let calRx = Math.max(0, Math.floor((mw - calW) / 2));
    let calH = s(750, scale);

    let base = {
        "volume":        { w: s(480, scale), h: s(760, scale), rx: mw - s(500, scale), ry: ryOpenAbove(s(760, scale)), comp: "volume/VolumePopup.qml" },
        "quicksettings": { w: s(380, scale), h: s(410, scale), rx: mw - s(394, scale), ry: ryOpenAbove(s(410, scale)), comp: "quicksettings/QuickSettingsPopup.qml" },
        "calendar":  { w: calW, h: calH, rx: calRx, ry: ryOpenAbove(calH), comp: "calendar/CalendarPopup.qml" },
        "music":     { w: s(700, scale), h: s(320, scale), rx: s(12, scale), ry: ryOpenAbove(s(320, scale)), comp: "music/MusicPopup.qml" },
        "network":   { w: s(900, scale), h: s(700, scale), rx: mw - s(920, scale), ry: ryOpenAbove(s(700, scale)), comp: "network/NetworkPopup.qml" },
        "stewart":   { w: s(800, scale), h: s(600, scale), rx: Math.floor((mw/2)-(s(800, scale)/2)), ry: Math.floor((mh/2)-(s(600, scale)/2)), comp: "stewart/stewart.qml" },
        "monitors":  { w: s(850, scale), h: s(580, scale), rx: Math.floor((mw/2)-(s(850, scale)/2)), ry: Math.floor((mh/2)-(s(580, scale)/2)), comp: "monitors/MonitorPopup.qml" },
        "focustime": { w: s(900, scale), h: s(720, scale), rx: Math.floor((mw/2)-(s(900, scale)/2)), ry: Math.floor((mh/2)-(s(720, scale)/2)), comp: "focustime/FocusTimePopup.qml" },
        "timer":     { w: s(400, scale), h: s(300, scale), rx: Math.floor((mw/2)-(s(400, scale)/2)), ry: Math.floor((mh/2)-(s(300, scale)/2)), comp: "timer/TimerPopup.qml" },
        "guide":     { w: s(1200, scale), h: s(750, scale), rx: Math.floor((mw/2)-(s(1200, scale)/2)), ry: Math.floor((mh/2)-(s(750, scale)/2)), comp: "guide/GuidePopup.qml" },
        "settings":  { w: s(450, scale), h: mh - barReserve, rx: s(0, scale), ry: s(0, scale), comp: "settings/SettingsPopup.qml" },
        "updater":   { w: s(450, scale), h: s(350, scale), rx: Math.floor((mw/2)-(s(450, scale)/2)), ry: Math.floor((mh/2)-(s(350, scale)/2)), comp: "updater/UpdaterPopup.qml" },
        // Right-edge column: main content area is above the 65px bottom bar strip
        "notifications": {
            w: s(400, scale),
            h: mh - barReserve,
            rx: mw - s(400, scale),
            ry: 0,
            comp: "notifications/NotificationCenter.qml"
        },
        "sidepanel": { w: s(600, scale), h: mh - barReserve, rx: mw - s(604, scale), ry: 0, comp: "sidepanel/SidePanel.qml" },
        "wallpaper": { w: mw, h: s(650, scale), rx: 0, ry: Math.floor((mh/2)-(s(650, scale)/2)), comp: "wallpaper/WallpaperPicker.qml" },
        "hidden":    { w: 1, h: 1, rx: -5000 - mx, ry: -5000 - my, comp: "" } 
    };

    if (!base[name]) return null;
    
    let t = base[name];
    t.x = mx + t.rx;
    t.y = my + t.ry;
    
    return t;
}

function getPopupLayout(mw, userScale) {
    let scale = getScale(mw, userScale);
    return {
        w: s(350, scale),
        // Bottom-docked bar: toasts sit above the bar, flush to the right
        marginBottom: s(70, scale),
        marginRight: s(20, scale),
        spacing: s(12, scale),
        radius: s(14, scale),
        padding: s(12, scale)
    };
}
