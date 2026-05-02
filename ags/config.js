import Gdk from 'gi://Gdk'
import Hyprland from 'resource:///com/github/Aylur/ags/service/hyprland.js'
import Audio from 'resource:///com/github/Aylur/ags/service/audio.js'
import Network from 'resource:///com/github/Aylur/ags/service/network.js'
import Utils from 'resource:///com/github/Aylur/ags/utils.js'

const time = Variable('', {
    poll: [1000, () => new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })],
})

/** Map GDK monitor index → Hyprland monitor (by layout origin). */
function hyprMonitorForGdk(gdkIdx) {
    const disp = Gdk.Display.get_default()
    if (!disp) return Hyprland.monitors[gdkIdx]
    const gm = disp.get_monitor(gdkIdx)
    if (!gm) return Hyprland.monitors[gdkIdx]
    const geo = gm.get_geometry()
    const match = Hyprland.monitors.find((m) => m.x === geo.x && m.y === geo.y)
    return match ?? Hyprland.monitors[gdkIdx]
}

/** Workspace ids on this monitor, active in brackets. */
function workspacesLabel(gdkIdx) {
    return Utils.merge([Hyprland.bind('workspaces'), Hyprland.bind('monitors')], () => {
        const mon = hyprMonitorForGdk(gdkIdx)
        if (!mon) return '—'
        const strip = Hyprland.workspaces
            .filter((w) => w.monitorID === mon.id)
            .sort((a, b) => a.id - b.id)
            .map((w) => (mon.activeWorkspace.id === w.id ? `[${w.id}]` : ` ${w.id} `))
            .join('')
        return strip.trim() || `[${mon.activeWorkspace.id}]`
    })
}

/** Focused window title when input focus is on this monitor. */
function windowTitle(gdkIdx) {
    return Utils.merge(
        [
            Hyprland.active.client.bind('title'),
            Hyprland.active.client.bind('class'),
            Hyprland.active.monitor.bind('id'),
            Hyprland.bind('monitors'),
        ],
        (title, cls, activeMonId) => {
            const mon = hyprMonitorForGdk(gdkIdx)
            if (!mon || mon.id !== activeMonId) return ''
            const raw = (title || '').trim() || cls || ''
            return raw.length > 72 ? `${raw.slice(0, 69)}…` : raw
        },
    )
}

function volumeGlyph() {
    return Utils.merge(
        [Audio.speaker.bind('volume'), Audio.speaker.bind('is_muted')],
        (v, muted) => {
            if (muted) return '󰝟'
            const pct = Math.round((v ?? 0) * 100)
            if (pct < 33) return ''
            if (pct < 66) return ''
            return '󰕾'
        },
    )
}

/** Monitor / “PC” look (freedesktop symbolic), not Wi‑Fi waves. */
function NetworkComputerIcon() {
    return Widget.Icon({
        class_name: 'tray-ico net',
        size: 20,
        icon: 'video-display-symbolic',
        setup: (self) => {
            const online = () => {
                if (Network.primary === 'wired')
                    return Network.wired?.internet === 'connected'
                if (Network.primary === 'wifi' && Network.wifi) {
                    const w = Network.wifi
                    return (
                        !!w.enabled &&
                        w.internet === 'connected' &&
                        Network.connectivity !== 'none'
                    )
                }
                return false
            }
            const sync = () => {
                const on = online()
                self.opacity = on ? 1 : 0.45
                self.toggleClassName('offline', !on)
            }
            self.hook(Network, sync)
            sync()
        },
    })
}

const gdk = Gdk.Display.get_default()
const nMon = gdk ? gdk.get_n_monitors() : 1

/** @param {number} monitor */
const Bar = (monitor) =>
    Widget.Window({
        monitor,
        name: `bar${monitor}`,
        class_name: 'bar',
        anchor: ['top', 'left', 'right'],
        exclusivity: 'exclusive',
        layer: 'top',
        child: Widget.CenterBox({
            start_widget: Widget.Box({
                class_name: 'left',
                spacing: 10,
                hpack: 'start',
                children: [
                    Widget.Label({
                        class_name: 'ws',
                        xalign: 0,
                        label: workspacesLabel(monitor),
                    }),
                    Widget.Label({
                        class_name: 'app',
                        xalign: 0,
                        truncate: 'end',
                        max_width_chars: 64,
                        label: windowTitle(monitor),
                    }),
                ],
            }),
            center_widget: Widget.Label({
                class_name: 'clock',
                xalign: 0.5,
                label: time.bind(),
            }),
            end_widget: Widget.Box({
                class_name: 'right',
                spacing: 14,
                hpack: 'end',
                children: [
                    Widget.Label({
                        class_name: 'tray-ico vol',
                        label: volumeGlyph(),
                    }),
                    NetworkComputerIcon(),
                ],
            }),
        }),
    })

App.config({
    style: `${App.configDir}/style.css`,
    windows: [...Array(nMon).keys()].map((i) => Bar(i)),
})
