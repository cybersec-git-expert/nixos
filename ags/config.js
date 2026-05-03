import Gdk from 'gi://Gdk'
import Hyprland from 'resource:///com/github/Aylur/ags/service/hyprland.js'
import Audio from 'resource:///com/github/Aylur/ags/service/audio.js'
import Bluetooth from 'resource:///com/github/Aylur/ags/service/bluetooth.js'
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

const VOL_SCROLL_STEP = 0.05
const MIC_SCROLL_STEP = 0.05

function VpnTrayIcon() {
    return Widget.EventBox({
        class_name: 'vpn-tray',
        cursor: 'pointer',
        tooltip_text: 'VPN · Click: connection editor',
        on_primary_click: () => {
            Utils.execAsync(['nm-connection-editor']).catch(() => {})
        },
        child: Widget.Icon({
            class_name: 'tray-ico vpn',
            size: 20,
            icon: 'network-vpn-symbolic',
            setup: (self) => {
                const sync = () => {
                    const act = Network.vpn?.activated_connections ?? []
                    const c = act[0]
                    const hasProfiles = (Network.vpn?.connections?.length ?? 0) > 0
                    if (c?.state === 'connected') {
                        self.icon = c.icon_name || 'network-vpn-symbolic'
                        self.opacity = 1
                    } else if (c?.state === 'connecting' || c?.state === 'disconnecting') {
                        self.icon = 'network-vpn-acquiring-symbolic'
                        self.opacity = 1
                    } else if (!hasProfiles) {
                        self.icon = 'network-vpn-symbolic'
                        self.opacity = 0.3
                    } else {
                        self.icon = 'network-vpn-symbolic'
                        self.opacity = 0.55
                    }
                }
                self.hook(Network, sync)
                sync()
            },
        }),
    })
}

function BluetoothTrayIcon() {
    return Widget.EventBox({
        class_name: 'bt-tray',
        cursor: 'pointer',
        tooltip_text: 'Bluetooth · Click to open',
        on_primary_click: () => {
            Utils.execAsync([
                'bash',
                '-c',
                'command -v blueman-manager >/dev/null && exec blueman-manager; command -v blueberry >/dev/null && exec blueberry; exit 0',
            ]).catch(() => {})
        },
        child: Widget.Icon({
            class_name: 'tray-ico bt',
            size: 20,
            icon: 'bluetooth-disabled-symbolic',
            setup: (self) => {
                const sync = () => {
                    if (!Bluetooth.enabled) {
                        self.icon = 'bluetooth-disabled-symbolic'
                        self.opacity = 0.45
                        return
                    }
                    const n = Bluetooth.connected_devices?.length ?? 0
                    if (n > 0) {
                        self.icon = 'bluetooth-active-symbolic'
                        self.opacity = 1
                    } else {
                        self.icon = 'bluetooth-symbolic'
                        self.opacity = 0.82
                    }
                }
                self.hook(Bluetooth, sync)
                sync()
            },
        }),
    })
}

function micGlyph() {
    return Utils.merge(
        [Audio.microphone.bind('volume'), Audio.microphone.bind('is_muted')],
        (_v, muted) => (muted ? '󰍭' : '󰍬'),
    )
}

function MicTray() {
    return Widget.EventBox({
        class_name: 'mic-tray',
        cursor: 'pointer',
        tooltip_text: 'Scroll: mic level · Right-click: mute mic',
        on_scroll_up: () => {
            const m = Audio.microphone
            if (m.is_muted) m.is_muted = false
            m.volume = Math.min(1, (m.volume ?? 0) + MIC_SCROLL_STEP)
        },
        on_scroll_down: () => {
            const m = Audio.microphone
            m.volume = Math.max(0, (m.volume ?? 0) - MIC_SCROLL_STEP)
        },
        on_secondary_click: () => {
            const m = Audio.microphone
            m.is_muted = !(m.is_muted ?? false)
        },
        child: Widget.Label({
            class_name: 'tray-ico mic',
            label: micGlyph(),
        }),
    })
}

function VolumeTray() {
    return Widget.EventBox({
        class_name: 'vol-tray',
        cursor: 'pointer',
        tooltip_text: 'Scroll: volume · Right-click: mute / unmute',
        on_scroll_up: () => {
            const sp = Audio.speaker
            if (sp.is_muted) sp.is_muted = false
            sp.volume = Math.min(1, (sp.volume ?? 0) + VOL_SCROLL_STEP)
        },
        on_scroll_down: () => {
            const sp = Audio.speaker
            sp.volume = Math.max(0, (sp.volume ?? 0) - VOL_SCROLL_STEP)
        },
        on_secondary_click: () => {
            const sp = Audio.speaker
            sp.is_muted = !(sp.is_muted ?? false)
        },
        child: Widget.Label({
            class_name: 'tray-ico vol',
            label: volumeGlyph(),
        }),
    })
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
                    VpnTrayIcon(),
                    BluetoothTrayIcon(),
                    MicTray(),
                    VolumeTray(),
                    NetworkComputerIcon(),
                ],
            }),
        }),
    })

App.config({
    style: `${App.configDir}/style.css`,
    windows: [...Array(nMon).keys()].map((i) => Bar(i)),
})
