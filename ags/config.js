import Gdk from 'gi://Gdk'
import Hyprland from 'resource:///com/github/Aylur/ags/service/hyprland.js'
import Audio from 'resource:///com/github/Aylur/ags/service/audio.js'
import Bluetooth from 'resource:///com/github/Aylur/ags/service/bluetooth.js'
import Network from 'resource:///com/github/Aylur/ags/service/network.js'
import Notifications from 'resource:///com/github/Aylur/ags/service/notifications.js'
import Utils from 'resource:///com/github/Aylur/ags/utils.js'

/** All tray Gtk.Image icons use the same pixel size so they align visually. */
const TRAY_ICON_PX = 16

/**
 * Top margin for overlay flyouts/scrim — must be ≥ real bar height.
 * Overlay layer draws above `layer: 'top'` (the bar); a transparent scrim would otherwise cover the bar.
 */
const BAR_CLEARANCE_PX = 72

const time = Variable('', {
    poll: [1000, () => new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })],
})

const dateLong = Variable('', {
    poll: [
        60_000,
        () =>
            new Date().toLocaleDateString(undefined, {
                weekday: 'long',
                year: 'numeric',
                month: 'long',
                day: 'numeric',
            }),
    ],
})

const dateFooter = Variable('', {
    poll: [
        60_000,
        () =>
            new Date().toLocaleDateString(undefined, {
                weekday: 'short',
                month: 'short',
                day: 'numeric',
                year: 'numeric',
            }),
    ],
})

const nightLightActive = Variable(false, {
    poll: [
        8000,
        () => {
            try {
                const o = Utils.exec([
                    'bash',
                    '-c',
                    'pgrep -x gammastep >/dev/null 2>&1 || pgrep -x wlsunset >/dev/null 2>&1 || pgrep -x redshift >/dev/null 2>&1 && echo 1 || echo 0',
                ])
                return String(o).trim() === '1'
            } catch {
                return false
            }
        },
    ],
})

const upsSummary = Variable('', {
    poll: [
        30_000,
        () => {
            try {
                const path = Utils.exec([
                    'bash',
                    '-c',
                    'upower -e 2>/dev/null | grep -i ups | head -1',
                ])?.trim()
                if (!path) return ''
                const info = Utils.exec(['upower', '-i', path])
                const m = String(info).match(/percentage:\s+(\d+)/i)
                return m ? `${m[1]}%` : ''
            } catch {
                return ''
            }
        },
    ],
})

/** @param {any} cal */
function monthYearFromCal(cal) {
    const [y, mo] = cal.date
    return new Date(y, mo, 1).toLocaleDateString(undefined, { month: 'long', year: 'numeric' })
}

/** Fixed-width cell so every tray control lines up the same. */
/** @param {any} child */
function TraySlot(child) {
    return Widget.Box({
        class_name: 'tray-slot',
        valign: 'center',
        halign: 'center',
        child,
    })
}

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

/** Rounded workspace pills for this monitor (click to switch). */
function WorkspacePills(gdkIdx) {
    return Widget.Box({
        class_name: 'workspace-pills',
        spacing: 6,
        valign: 'center',
        setup: (self) => {
            const sync = () => {
                const mon = hyprMonitorForGdk(gdkIdx)
                if (!mon) {
                    self.children = []
                    return
                }
                const ids = Hyprland.workspaces
                    .filter((w) => w.monitorID === mon.id)
                    .sort((a, b) => a.id - b.id)
                    .map((w) => w.id)
                const active = mon.activeWorkspace.id
                self.children = ids.map((id) =>
                    Widget.Button({
                        class_name: `ws-pill${id === active ? ' active' : ''}`,
                        label: String(id),
                        cursor: 'pointer',
                        valign: 'center',
                        tooltip_text: `Workspace ${id}`,
                        on_clicked: () => {
                            Hyprland.message(`dispatch workspace ${id}`)
                        },
                    }),
                )
            }
            self.hook(Hyprland, sync)
            sync()
        },
    })
}

function flyoutScrimName(/** @type {number} */ m) {
    return `flyoutScrim${m}`
}

function trayFlyoutName(/** @type {number} */ m) {
    return `trayFlyout${m}`
}

function quickSettingsName(/** @type {number} */ m) {
    return `quickSettings${m}`
}

function closeAllMonitorOverlays(/** @type {number} */ m) {
    App.closeWindow(trayFlyoutName(m))
    App.closeWindow(quickSettingsName(m))
    App.closeWindow(flyoutScrimName(m))
}

function toggleTrayFlyout(/** @type {number} */ m) {
    if (App.getWindow(trayFlyoutName(m))?.visible) {
        closeAllMonitorOverlays(m)
        return
    }
    closeAllMonitorOverlays(m)
    App.openWindow(flyoutScrimName(m))
    App.openWindow(trayFlyoutName(m))
}

function toggleQuickSettings(/** @type {number} */ m) {
    if (App.getWindow(quickSettingsName(m))?.visible) {
        closeAllMonitorOverlays(m)
        return
    }
    closeAllMonitorOverlays(m)
    App.openWindow(flyoutScrimName(m))
    App.openWindow(quickSettingsName(m))
}

/** @param {any} n */
function notificationRow(n) {
    const ts = n.time
    const when = new Date(ts > 1e12 ? ts : ts * 1000).toLocaleTimeString([], {
        hour: '2-digit',
        minute: '2-digit',
    })
    return Widget.Box({
        class_name: 'nc-notif',
        vertical: true,
        children: [
            Widget.Box({
                class_name: 'nc-notif-head',
                valign: 'start',
                spacing: 10,
                children: [
                    Widget.Icon({
                        class_name: 'nc-notif-ico',
                        size: 28,
                        icon: n.app_icon || 'dialog-information-symbolic',
                    }),
                    Widget.Box({
                        vertical: true,
                        hexpand: true,
                        spacing: 4,
                        children: [
                            Widget.Box({
                                children: [
                                    Widget.Label({
                                        class_name: 'nc-app',
                                        xalign: 0,
                                        hexpand: true,
                                        truncate: 'end',
                                        label: n.app_name,
                                    }),
                                    Widget.Label({
                                        class_name: 'nc-time',
                                        xalign: 1,
                                        label: when,
                                    }),
                                ],
                            }),
                            Widget.Label({
                                class_name: 'nc-sum',
                                xalign: 0,
                                wrap: true,
                                label: n.summary,
                            }),
                            Widget.Label({
                                class_name: 'nc-body',
                                xalign: 0,
                                wrap: true,
                                visible: !!n.body,
                                label: n.body || '',
                            }),
                        ],
                    }),
                    Widget.Button({
                        class_name: 'nc-dismiss',
                        label: '×',
                        valign: 'start',
                        tooltip_text: 'Dismiss',
                        on_clicked: () => {
                            n.close()
                        },
                    }),
                ],
            }),
        ],
    })
}

function NotificationList() {
    return Widget.Box({
        vertical: true,
        spacing: 0,
        setup: (self) => {
            const sync = () => {
                const list = [...Notifications.notifications].sort((a, b) => b.time - a.time)
                if (list.length === 0) {
                    self.children = [
                        Widget.Label({
                            class_name: 'nc-empty',
                            wrap: true,
                            label:
                                'No notifications here.\nIf you use Dunst as the daemon, history stays in Dunst — try `dunstctl history`.',
                        }),
                    ]
                    return
                }
                self.children = list.map((n) => notificationRow(n))
            }
            self.hook(Notifications, sync)
            sync()
        },
    })
}

/** Fullscreen (below bar) click-catcher — closes flyout when clicking outside the panel. */
function FlyoutScrim(/** @type {number} */ monitor) {
    return Widget.Window({
        monitor,
        name: flyoutScrimName(monitor),
        class_name: 'flyout-scrim',
        anchor: ['top', 'bottom', 'left', 'right'],
        exclusivity: 'ignore',
        layer: 'overlay',
        margins: [BAR_CLEARANCE_PX, 0, 0, 0],
        visible: false,
        focusable: false,
        child: Widget.EventBox({
            hexpand: true,
            vexpand: true,
            on_primary_click: () => {
                closeAllMonitorOverlays(monitor)
                return true
            },
            child: Widget.Box({
                class_name: 'flyout-scrim-fill',
                hexpand: true,
                vexpand: true,
            }),
        }),
    })
}

/** Calendar block (stacked above notifications in `TrayFlyout`). */
function CalendarBlock() {
    const calWidget = Widget.Calendar({
        class_name: 'cal-grid',
        show_heading: false,
        show_day_names: true,
        show_week_numbers: false,
    })
    const monthLbl = Widget.Label({ class_name: 'cal-month', hexpand: true, xalign: 0.5 })
    const syncMonth = () => {
        monthLbl.label = monthYearFromCal(calWidget)
    }
    const bump = (/** @type {number} */ delta) => {
        const [y, mo] = calWidget.date
        let nm = mo + delta
        let ny = y
        while (nm < 0) {
            nm += 12
            ny -= 1
        }
        while (nm > 11) {
            nm -= 12
            ny += 1
        }
        calWidget.select_month(nm, ny)
        syncMonth()
    }
    syncMonth()
    calWidget.connect('day-selected', syncMonth)
    calWidget.connect('prev-month', syncMonth)
    calWidget.connect('next-month', syncMonth)

    return Widget.Box({
        vertical: true,
        class_name: 'cal-inner',
        children: [
            Widget.Box({
                class_name: 'cal-date-row',
                valign: 'center',
                children: [
                    Widget.Label({
                        class_name: 'cal-date-main',
                        hexpand: true,
                        xalign: 0,
                        wrap: true,
                        label: dateLong.bind(),
                    }),
                    Widget.Icon({ class_name: 'cal-chev', icon: 'pan-down-symbolic', size: 14 }),
                ],
            }),
            Widget.Box({
                class_name: 'cal-nav',
                valign: 'center',
                spacing: 4,
                children: [
                    Widget.Button({
                        class_name: 'cal-nav-btn',
                        cursor: 'pointer',
                        child: Widget.Icon({ icon: 'go-previous-symbolic', size: 14 }),
                        on_clicked: () => bump(-1),
                    }),
                    monthLbl,
                    Widget.Button({
                        class_name: 'cal-nav-btn',
                        cursor: 'pointer',
                        child: Widget.Icon({ icon: 'go-next-symbolic', size: 14 }),
                        on_clicked: () => bump(1),
                    }),
                ],
            }),
            calWidget,
        ],
    })
}

/** Calendar on top, notifications below — top-right under the bar. */
function TrayFlyout(/** @type {number} */ monitor) {
    return Widget.Window({
        monitor,
        name: trayFlyoutName(monitor),
        class_name: 'tray-flyout',
        anchor: ['top', 'right'],
        exclusivity: 'normal',
        layer: 'overlay',
        margins: [BAR_CLEARANCE_PX, 16, 0, 0],
        visible: false,
        child: Widget.Box({
            vertical: true,
            class_name: 'flyout-stack',
            spacing: 12,
            children: [
                CalendarBlock(),
                Widget.Box({
                    vertical: true,
                    class_name: 'nc-inner',
                    children: [
                        Widget.Box({
                            class_name: 'nc-header',
                            valign: 'center',
                            children: [
                                Widget.Label({
                                    class_name: 'nc-heading',
                                    hexpand: true,
                                    xalign: 0,
                                    label: 'Notifications',
                                }),
                                Widget.Button({
                                    class_name: 'nc-clear',
                                    label: 'Clear all',
                                    on_clicked: () => {
                                        Notifications.clear().catch(() => {})
                                    },
                                }),
                            ],
                        }),
                        Widget.Scrollable({
                            class_name: 'nc-scroll',
                            vscroll: 'always',
                            hscroll: 'never',
                            css: 'min-height: 140px;',
                            child: NotificationList(),
                        }),
                    ],
                }),
            ],
        }),
    })
}

function toggleNightLightShell() {
    Utils.execAsync([
        'bash',
        '-c',
        `if pgrep -x gammastep >/dev/null 2>&1; then pkill gammastep;
        elif pgrep -x wlsunset >/dev/null 2>&1; then pkill wlsunset;
        elif pgrep -x redshift >/dev/null 2>&1; then pkill redshift;
        else
          (command -v gammastep >/dev/null && nohup gammastep -O 4500 >/dev/null 2>&1 &) ||
          (command -v wlsunset >/dev/null && nohup wlsunset -t 4500 -T 6500 >/dev/null 2>&1 &) ||
          (command -v redshift >/dev/null && nohup redshift -O 4500 >/dev/null 2>&1 &);
        fi`,
    ]).catch(() => {})
}

function qsMicSliderRow() {
    return Widget.Box({
        class_name: 'qs-slider-row',
        spacing: 10,
        valign: 'center',
        children: [
            Widget.Icon({
                size: 22,
                setup: (self) => {
                    const sync = () => syncMicSymbolic(self)
                    self.hook(Audio, sync)
                    sync()
                },
            }),
            Widget.Slider({
                class_name: 'qs-slider',
                hexpand: true,
                draw_value: false,
                min: 0,
                max: 1,
                step: 0.02,
                setup: (self) => {
                    let syncing = false
                    const syncFromAudio = () => {
                        if (self.dragging) return
                        syncing = true
                        self.value = Audio.microphone.volume
                        syncing = false
                    }
                    self.hook(Audio, syncFromAudio)
                    syncFromAudio()
                    self.connect('value-changed', () => {
                        if (syncing) return
                        const m = Audio.microphone
                        m.volume = self.value
                        if (m.is_muted && self.value > 0.02) m.is_muted = false
                    })
                },
            }),
        ],
    })
}

function qsSpeakerSliderRow() {
    return Widget.Box({
        class_name: 'qs-slider-row',
        spacing: 10,
        valign: 'center',
        children: [
            Widget.Icon({
                size: 22,
                setup: (self) => {
                    const sync = () => syncSpeakerSymbolic(self)
                    self.hook(Audio, sync)
                    sync()
                },
            }),
            Widget.Slider({
                class_name: 'qs-slider',
                hexpand: true,
                draw_value: false,
                min: 0,
                max: 1,
                step: 0.02,
                setup: (self) => {
                    let syncing = false
                    const syncFromAudio = () => {
                        if (self.dragging) return
                        syncing = true
                        self.value = Audio.speaker.volume
                        syncing = false
                    }
                    self.hook(Audio, syncFromAudio)
                    syncFromAudio()
                    self.connect('value-changed', () => {
                        if (syncing) return
                        const sp = Audio.speaker
                        sp.volume = self.value
                        if (sp.is_muted && self.value > 0.02) sp.is_muted = false
                    })
                },
            }),
            Widget.Button({
                class_name: 'qs-mixer-btn',
                cursor: 'pointer',
                tooltip_text: 'Open mixer',
                valign: 'center',
                child: Widget.Icon({ icon: 'preferences-system-details-symbolic', size: 16 }),
                on_clicked: () => {
                    Utils.execAsync(['bash', '-c', 'command -v pavucontrol >/dev/null && exec pavucontrol']).catch(() => {})
                },
            }),
        ],
    })
}

/**
 * Pill with optional split: inactive = centered icon only; active = [ icon | › ].
 * @param {any} captionWidget
 * @param {() => void} onMain
 * @param {() => void} onMore
 * @param {(outer: any, icoIn: any, icoAct: any) => boolean} syncAll updates icons/labels; returns active (split + blue).
 * @param {any[]} services services to hook for refresh
 */
function qsAdaptivePill(captionWidget, onMain, onMore, syncAll, services) {
    const icoIn = Widget.Icon({ class_name: 'qs-tile-ico', size: 26 })
    const icoAct = Widget.Icon({ class_name: 'qs-tile-ico', size: 26 })

    const inactiveBtn = Widget.Button({
        class_name: 'qs-tile-whole',
        hexpand: true,
        vexpand: true,
        cursor: 'pointer',
        tooltip_text: 'Toggle',
        on_clicked: onMain,
        child: Widget.CenterBox({
            class_name: 'qs-tile-whole-inner',
            hexpand: true,
            vexpand: true,
            center_widget: icoIn,
        }),
    })

    const activeRow = Widget.Box({
        class_name: 'qs-tile-split',
        hexpand: true,
        vexpand: true,
        children: [
            Widget.Button({
                class_name: 'qs-tile-main',
                hexpand: true,
                vexpand: true,
                cursor: 'pointer',
                tooltip_text: 'Toggle',
                on_clicked: onMain,
                child: Widget.CenterBox({
                    class_name: 'qs-tile-main-inner',
                    hexpand: true,
                    vexpand: true,
                    center_widget: icoAct,
                }),
            }),
            Widget.Separator({
                class_name: 'qs-tile-vsep',
                vertical: true,
            }),
            Widget.Button({
                class_name: 'qs-tile-more',
                cursor: 'pointer',
                tooltip_text: 'More',
                valign: 'fill',
                vexpand: true,
                on_clicked: onMore,
                child: Widget.CenterBox({
                    hexpand: true,
                    vexpand: true,
                    center_widget: Widget.Icon({
                        class_name: 'qs-tile-chevron-ico',
                        icon: 'pan-end-symbolic',
                        size: 14,
                    }),
                }),
            }),
        ],
    })

    const stack = Widget.Stack({
        class_name: 'qs-tile-stack',
        transition: 'none',
        hexpand: true,
        children: {
            inactive: inactiveBtn,
            active: activeRow,
        },
        shown: 'inactive',
    })

    return Widget.Box({
        vertical: true,
        class_name: 'qs-tile-outer',
        hexpand: true,
        children: [stack, captionWidget],
        setup: (outer) => {
            const run = () => {
                const active = syncAll(outer, icoIn, icoAct)
                icoAct.icon = icoIn.icon
                outer.toggleClassName('qs-tile-active', active)
                stack.shown = active ? 'active' : 'inactive'
            }
            for (const s of services) outer.hook(s, run)
            run()
        },
    })
}

function qsWin11SimpleTile(iconWidget, captionRoot, onMain, setupSync) {
    return Widget.Box({
        vertical: true,
        class_name: 'qs-tile-outer',
        hexpand: true,
        children: [
            Widget.Button({
                class_name: 'qs-tile-simple',
                hexpand: true,
                vexpand: true,
                cursor: 'pointer',
                on_clicked: onMain,
                child: Widget.CenterBox({
                    class_name: 'qs-tile-simple-inner',
                    hexpand: true,
                    vexpand: true,
                    center_widget: iconWidget,
                }),
            }),
            captionRoot,
        ],
        setup: (self) => {
            setupSync(self)
        },
    })
}

function QuickSettingsPanel(/** @type {number} */ monitor) {
    const netLabel = Widget.Label({ class_name: 'qs-tile-cap', xalign: 0.5, wrap: true, max_width_chars: 14 })
    const netTile = qsAdaptivePill(
        netLabel,
        () => {
            if (Network.wifi) Network.toggleWifi()
            else Utils.execAsync(['nm-connection-editor']).catch(() => {})
        },
        () => {
            Utils.execAsync(['nm-connection-editor']).catch(() => {})
        },
        (_outer, icoIn) => {
            if (Network.primary === 'wifi' && Network.wifi) {
                icoIn.icon = Network.wifi.icon_name || 'network-wireless-symbolic'
                netLabel.label = Network.wifi.ssid || 'Wi-Fi'
                return Network.wifi.enabled && Network.wifi.internet === 'connected'
            }
            if (Network.primary === 'wired' && Network.wired) {
                icoIn.icon = 'video-display-symbolic'
                netLabel.label = 'Ethernet'
                return Network.wired.internet === 'connected'
            }
            icoIn.icon = 'network-offline-symbolic'
            netLabel.label = 'Network'
            return false
        },
        [Network],
    )

    const btTile = qsAdaptivePill(
        Widget.Label({ class_name: 'qs-tile-cap', label: 'Bluetooth', xalign: 0.5 }),
        () => {
            Bluetooth.enabled = !Bluetooth.enabled
        },
        () => {
            Utils.execAsync([
                'bash',
                '-c',
                'command -v blueman-manager >/dev/null && exec blueman-manager; command -v blueberry >/dev/null && exec blueberry; exit 0',
            ]).catch(() => {})
        },
        (_outer, icoIn) => {
            if (!Bluetooth.enabled) {
                icoIn.icon = 'bluetooth-disabled-symbolic'
            } else if ((Bluetooth.connected_devices?.length ?? 0) > 0) {
                icoIn.icon = 'bluetooth-active-symbolic'
            } else {
                icoIn.icon = 'bluetooth-symbolic'
            }
            return Bluetooth.enabled
        },
        [Bluetooth],
    )

    const vpnIcon = Widget.Icon({ class_name: 'qs-tile-ico', size: 26, icon: 'network-vpn-symbolic' })
    const vpnTile = qsWin11SimpleTile(
        vpnIcon,
        Widget.Label({ class_name: 'qs-tile-cap', label: 'VPN', xalign: 0.5 }),
        () => {
            Utils.execAsync(['nm-connection-editor']).catch(() => {})
        },
        (outer) => {
            const sync = () => {
                const act = Network.vpn?.activated_connections ?? []
                const c = act[0]
                const on = c?.state === 'connected'
                outer.toggleClassName('qs-tile-active', !!on)
                if (c?.state === 'connecting' || c?.state === 'disconnecting') {
                    vpnIcon.icon = 'network-vpn-acquiring-symbolic'
                } else {
                    vpnIcon.icon = 'network-vpn-symbolic'
                }
            }
            outer.hook(Network, sync)
            sync()
        },
    )

    const focusIcon = Widget.Icon({
        class_name: 'qs-tile-ico',
        size: 26,
        icon: 'preferences-system-notifications-symbolic',
    })
    const focusTile = qsWin11SimpleTile(
        focusIcon,
        Widget.Label({ class_name: 'qs-tile-cap', label: 'Focus assist', xalign: 0.5 }),
        () => {
            Notifications.dnd = !Notifications.dnd
        },
        (outer) => {
            const sync = () => {
                const dnd = Notifications.dnd
                outer.toggleClassName('qs-tile-active', dnd)
                focusIcon.icon = dnd ? 'weather-clear-night-symbolic' : 'preferences-system-notifications-symbolic'
            }
            outer.hook(Notifications, sync)
            sync()
        },
    )

    const nightIcon = Widget.Icon({ class_name: 'qs-tile-ico', size: 26, icon: 'weather-clear-symbolic' })
    const nightTile = qsWin11SimpleTile(
        nightIcon,
        Widget.Label({ class_name: 'qs-tile-cap', label: 'Night light', xalign: 0.5 }),
        () => toggleNightLightShell(),
        (outer) => {
            const sync = () => {
                const on = nightLightActive.value
                outer.toggleClassName('qs-tile-active', on)
                nightIcon.icon = on ? 'weather-clear-night-symbolic' : 'weather-clear-symbolic'
            }
            nightLightActive.connect('notify::value', sync)
            sync()
        },
    )

    const upsTile = qsWin11SimpleTile(
        Widget.Icon({ class_name: 'qs-tile-ico', size: 26, icon: 'battery-full-symbolic' }),
        Widget.Label({ class_name: 'qs-tile-cap', label: 'UPS', xalign: 0.5 }),
        () => {},
        (outer) => {
            const sync = () => {
                const v = String(upsSummary.value ?? '').trim()
                const ok = v.length > 0 && v !== '—'
                outer.toggleClassName('qs-tile-active', ok)
                outer.tooltip_text = ok ? `UPS · ${v}` : 'UPS'
            }
            upsSummary.connect('notify::value', sync)
            sync()
        },
    )

    return Widget.Window({
        monitor,
        name: quickSettingsName(monitor),
        class_name: 'qs-panel',
        anchor: ['top', 'right'],
        exclusivity: 'normal',
        layer: 'overlay',
        margins: [BAR_CLEARANCE_PX, 16, 0, 0],
        visible: false,
        child: Widget.Box({
            vertical: true,
            class_name: 'qs-shell',
            children: [
                Widget.Box({
                    class_name: 'qs-grid',
                    vertical: true,
                    spacing: 8,
                    children: [
                        Widget.Box({
                            class_name: 'qs-row',
                            homogeneous: true,
                            spacing: 10,
                            children: [netTile, btTile, vpnTile],
                        }),
                        Widget.Box({
                            class_name: 'qs-row',
                            homogeneous: true,
                            spacing: 10,
                            children: [focusTile, nightTile, upsTile],
                        }),
                    ],
                }),
                Widget.Separator({ class_name: 'qs-sep' }),
                qsMicSliderRow(),
                qsSpeakerSliderRow(),
                Widget.Separator({ class_name: 'qs-sep' }),
                Widget.Box({
                    class_name: 'qs-footer',
                    valign: 'center',
                    children: [
                        Widget.Label({
                            class_name: 'qs-footer-date',
                            hexpand: true,
                            xalign: 0,
                            label: dateFooter.bind(),
                        }),
                        Widget.Button({
                            class_name: 'qs-settings-btn',
                            cursor: 'pointer',
                            tooltip_text: 'Settings',
                            valign: 'center',
                            child: Widget.Icon({ icon: 'emblem-system-symbolic', size: 20 }),
                            on_clicked: () => {
                                Utils.execAsync([
                                    'bash',
                                    '-c',
                                    'command -v gnome-control-center >/dev/null && exec gnome-control-center; command -v systemsettings5 >/dev/null && exec systemsettings5; exit 0',
                                ]).catch(() => {})
                            },
                        }),
                    ],
                }),
            ],
        }),
    })
}

function ClockBlock() {
    return Widget.Box({
        class_name: 'clock-wrap',
        valign: 'center',
        hpack: 'center',
        spacing: 8,
        children: [
            Widget.Icon({
                class_name: 'clock-ico',
                size: 18,
                icon: 'preferences-system-time-symbolic',
            }),
            Widget.Label({
                class_name: 'clock',
                xalign: 0,
                label: time.bind(),
            }),
        ],
    })
}

/** Opens the notification and calendar flyouts together (right of volume). */
function NotificationTrayButton(/** @type {number} */ gdkMonitor) {
    return Widget.EventBox({
        class_name: 'notif-tray',
        cursor: 'pointer',
        tooltip_text: 'Notifications & calendar',
        on_primary_click: () => {
            toggleTrayFlyout(gdkMonitor)
        },
        child: Widget.Label({
            class_name: 'tray-ico tray-bell',
            /* Font Awesome bell (Nerd Font) */
            label: '\uf0f3',
            setup: (self) => {
                const sync = () => {
                    const n = Notifications.notifications?.length ?? 0
                    self.opacity = n > 0 ? 1 : 0.55
                }
                self.hook(Notifications, sync)
                sync()
            },
        }),
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

/** @param {any} icon */
function syncSpeakerSymbolic(icon) {
    const sp = Audio.speaker
    if (sp.is_muted) icon.icon = 'audio-volume-muted-symbolic'
    else if ((sp.volume ?? 0) < 0.34) icon.icon = 'audio-volume-low-symbolic'
    else if ((sp.volume ?? 0) < 0.67) icon.icon = 'audio-volume-medium-symbolic'
    else icon.icon = 'audio-volume-high-symbolic'
}

/** @param {any} icon */
function syncMicSymbolic(icon) {
    const m = Audio.microphone
    icon.icon = m.is_muted ? 'audio-input-microphone-muted-symbolic' : 'audio-input-microphone-symbolic'
}

const VOL_SCROLL_STEP = 0.05
const MIC_SCROLL_STEP = 0.05

function VpnTrayIcon(/** @type {number} */ m) {
    return Widget.EventBox({
        class_name: 'vpn-tray',
        cursor: 'pointer',
        tooltip_text: 'VPN · Click: Quick settings · Right-click: editor',
        on_primary_click: () => toggleQuickSettings(m),
        on_secondary_click: () => {
            Utils.execAsync(['nm-connection-editor']).catch(() => {})
        },
        child: Widget.Icon({
            class_name: 'tray-ico',
            size: TRAY_ICON_PX,
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

function BluetoothTrayIcon(/** @type {number} */ m) {
    return Widget.EventBox({
        class_name: 'bt-tray',
        cursor: 'pointer',
        tooltip_text: 'Bluetooth · Click: Quick settings · Right-click: manager',
        on_primary_click: () => toggleQuickSettings(m),
        on_secondary_click: () => {
            Utils.execAsync([
                'bash',
                '-c',
                'command -v blueman-manager >/dev/null && exec blueman-manager; command -v blueberry >/dev/null && exec blueberry; exit 0',
            ]).catch(() => {})
        },
        child: Widget.Icon({
            class_name: 'tray-ico',
            size: TRAY_ICON_PX,
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

function MicTray(/** @type {number} */ m) {
    return Widget.EventBox({
        class_name: 'mic-tray',
        cursor: 'pointer',
        tooltip_text: 'Click: Quick settings · Scroll: mic · Right-click: mute',
        on_primary_click: () => toggleQuickSettings(m),
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
        child: Widget.Icon({
            class_name: 'tray-ico',
            size: TRAY_ICON_PX,
            icon: 'audio-input-microphone-symbolic',
            setup: (self) => {
                const sync = () => {
                    syncMicSymbolic(self)
                    self.opacity = 1
                }
                self.hook(Audio, sync)
                sync()
            },
        }),
    })
}

function VolumeTray(/** @type {number} */ m) {
    return Widget.EventBox({
        class_name: 'vol-tray',
        cursor: 'pointer',
        tooltip_text: 'Click: Quick settings · Scroll: volume · Right-click: mute',
        on_primary_click: () => toggleQuickSettings(m),
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
        child: Widget.Icon({
            class_name: 'tray-ico',
            size: TRAY_ICON_PX,
            icon: 'audio-volume-medium-symbolic',
            setup: (self) => {
                const sync = () => {
                    syncSpeakerSymbolic(self)
                    self.opacity = 1
                }
                self.hook(Audio, sync)
                sync()
            },
        }),
    })
}

/** Network tray — opens Quick settings (bar styling unchanged). */
function NetworkTrayIcon(/** @type {number} */ m) {
    return Widget.EventBox({
        class_name: 'net-tray',
        cursor: 'pointer',
        tooltip_text: 'Network · Click: Quick settings · Right-click: connections',
        on_primary_click: () => toggleQuickSettings(m),
        on_secondary_click: () => {
            Utils.execAsync(['nm-connection-editor']).catch(() => {})
        },
        child: Widget.Icon({
            class_name: 'tray-ico',
            size: TRAY_ICON_PX,
            icon: 'video-display-symbolic',
            setup: (self) => {
                const online = () => {
                    if (Network.primary === 'wired') return Network.wired?.internet === 'connected'
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
        }),
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
                spacing: 12,
                hpack: 'start',
                valign: 'center',
                children: [
                    WorkspacePills(monitor),
                    Widget.Separator({
                        class_name: 'title-sep',
                        vertical: true,
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
            center_widget: ClockBlock(),
            end_widget: Widget.Box({
                class_name: 'right',
                spacing: 4,
                hpack: 'end',
                children: [
                    TraySlot(VpnTrayIcon(monitor)),
                    TraySlot(MicTray(monitor)),
                    TraySlot(BluetoothTrayIcon(monitor)),
                    TraySlot(NetworkTrayIcon(monitor)),
                    TraySlot(VolumeTray(monitor)),
                    TraySlot(NotificationTrayButton(monitor)),
                ],
            }),
        }),
    })

const bars = [...Array(nMon).keys()].map((i) => Bar(i))
const flyoutScrims = [...Array(nMon).keys()].map((i) => FlyoutScrim(i))
const quickSettingsWins = [...Array(nMon).keys()].map((i) => QuickSettingsPanel(i))
const trayFlyouts = [...Array(nMon).keys()].map((i) => TrayFlyout(i))

App.config({
    style: `${App.configDir}/style.css`,
    windows: [...bars, ...flyoutScrims, ...quickSettingsWins, ...trayFlyouts],
})
