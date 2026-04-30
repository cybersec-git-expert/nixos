import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    // Explicitly typed as 'color' for strict QML binding
    property color base: "#1e1e2e"
    property color mantle: "#181825"
    property color crust: "#11111b"
    property color text: "#cdd6f4"
    property color subtext0: "#a6adc8"
    property color subtext1: "#bac2de"
    property color surface0: "#313244"
    property color surface1: "#45475a"
    property color surface2: "#585b70"
    property color overlay0: "#6c7086"
    property color overlay1: "#7f849c"
    property color overlay2: "#9399b2"
    property color blue: "#89b4fa"
    property color onPrimary: "#0a0a0a"
    property color sapphire: "#74c7ec"
    property color peach: "#fab387"
    property color green: "#a6e3a1"
    property color red: "#f38ba8"
    property color mauve: "#cba6f7"
    property color pink: "#f5c2e7"
    property color yellow: "#f9e2af"
    property color maroon: "#eba0ac"
    property color teal: "#94e2d5"

    // Single accent for interactive chrome (maps to Material primary from wallpaper).
    readonly property color accent: blue

    // Frosted panels: follow `text` / `blue` so they stay coherent when qs_colors.json updates.
    readonly property color glassFill: Qt.rgba(text.r, text.g, text.b, 0.05)
    readonly property color glassFillHover: Qt.rgba(text.r, text.g, text.b, 0.08)
    readonly property color glassFillStrong: Qt.rgba(text.r, text.g, text.b, 0.10)
    readonly property color glassBorder: Qt.rgba(text.r, text.g, text.b, 0.12)
    readonly property color glassBorderStrong: Qt.rgba(text.r, text.g, text.b, 0.18)
    readonly property color glassTintAccent: Qt.rgba(blue.r, blue.g, blue.b, 0.14)

    property string rawJson: ""
    // Bumped whenever qs_colors.json is re-applied so any subtree that accidentally
    // cached an old color still re-evaluates (workspace strip + media pill).
    property int paletteRevision: 0

    function hexFromToken(v) {
        if (typeof v === "string")
            return v;
        if (v && typeof v === "object" && typeof v.color === "string")
            return v.color;
        return "";
    }

    Process {
        id: themeReader
        command: ["cat", Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/qs_colors.json"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let txt = this.text.trim();
                if (txt !== "" && txt !== root.rawJson) {
                    root.rawJson = txt;
                    try {
                        let c = JSON.parse(txt);
                        let h;
                        h = root.hexFromToken(c.base);
                        if (h) root.base = h;
                        h = root.hexFromToken(c.mantle);
                        if (h) root.mantle = h;
                        h = root.hexFromToken(c.crust);
                        if (h) root.crust = h;
                        h = root.hexFromToken(c.text);
                        if (h) root.text = h;
                        h = root.hexFromToken(c.subtext0);
                        if (h) root.subtext0 = h;
                        h = root.hexFromToken(c.subtext1);
                        if (h) root.subtext1 = h;
                        h = root.hexFromToken(c.surface0);
                        if (h) root.surface0 = h;
                        h = root.hexFromToken(c.surface1);
                        if (h) root.surface1 = h;
                        h = root.hexFromToken(c.surface2);
                        if (h) root.surface2 = h;
                        h = root.hexFromToken(c.overlay0);
                        if (h) root.overlay0 = h;
                        h = root.hexFromToken(c.overlay1);
                        if (h) root.overlay1 = h;
                        h = root.hexFromToken(c.overlay2);
                        if (h) root.overlay2 = h;
                        h = root.hexFromToken(c.blue);
                        if (h) root.blue = h;
                        h = root.hexFromToken(c.onPrimary);
                        if (h) root.onPrimary = h;
                        h = root.hexFromToken(c.sapphire);
                        if (h) root.sapphire = h;
                        h = root.hexFromToken(c.peach);
                        if (h) root.peach = h;
                        h = root.hexFromToken(c.green);
                        if (h) root.green = h;
                        h = root.hexFromToken(c.red);
                        if (h) root.red = h;
                        h = root.hexFromToken(c.mauve);
                        if (h) root.mauve = h;
                        h = root.hexFromToken(c.pink);
                        if (h) root.pink = h;
                        h = root.hexFromToken(c.yellow);
                        if (h) root.yellow = h;
                        h = root.hexFromToken(c.maroon);
                        if (h) root.maroon = h;
                        h = root.hexFromToken(c.teal);
                        if (h) root.teal = h;
                        root.paletteRevision++;
                    } catch (e) {}
                }
            }
        }
    }

    // Quickshell Process only re-runs when `running` goes false → true; a bare
    // `running = true` each tick does nothing after the first cat.
    Timer {
        id: themeReaderKick
        interval: 1
        repeat: false
        onTriggered: themeReader.running = true
    }

    Timer {
        interval: 400
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            themeReader.running = false;
            themeReaderKick.start();
        }
    }
}
