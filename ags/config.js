import Gdk from 'gi://Gdk'
import GLib from 'gi://GLib'
import Hyprland from 'resource:///com/github/Aylur/ags/service/hyprland.js'
import Audio from 'resource:///com/github/Aylur/ags/service/audio.js'
import Bluetooth from 'resource:///com/github/Aylur/ags/service/bluetooth.js'
import Network from 'resource:///com/github/Aylur/ags/service/network.js'
import Notifications from 'resource:///com/github/Aylur/ags/service/notifications.js'
import Utils from 'resource:///com/github/Aylur/ags/utils.js'

/** All tray Gtk.Image icons use the same pixel size so they align visually. */
const TRAY_ICON_PX = 16

/** Quick-settings grid tiles — smaller icons = denser Win11-style pills. */
const QS_TILE_ICON_PX = 20

/**
 * Top margin for overlay flyouts/scrim — must be ≥ real bar height.
 * Overlay layer draws above `layer: 'top'` (the bar); a transparent scrim would otherwise cover the bar.
 */
const BAR_CLEARANCE_PX = 72

/** Snap workspace id to HP (odd) or MSI (even), then focus — matches Hyprland keybinds. */
const WORKSPACE_GOTO = `${GLib.get_home_dir()}/.config/hypr/scripts/workspace-goto.sh`

const time = Variable('', {
    poll: [
        1000,
        () => new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', hour12: false }),
    ],
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

/** Pick a UPower UPS/HID-battery path — device paths are usually `battery_hid_…`, not the word "ups". */
function upowerUpsPath() {
    let list = ''
    try {
        list = Utils.exec(['upower', '-e']) || ''
    } catch {
        return ''
    }
    for (const raw of list.trim().split('\n')) {
        const path = raw.trim()
        if (!path || path.includes('DisplayDevice')) continue
        let info = ''
        try {
            info = Utils.exec(['upower', '-i', path]) || ''
        } catch {
            continue
        }
        const hay = `${path}\n${info}`.toLowerCase()
        const upsLike =
            hay.includes('ups') ||
            hay.includes('prolink') ||
            hay.includes('megatec') ||
            hay.includes('uninterruptible') ||
            hay.includes('hid-uninterruptible') ||
            (hay.includes('battery_hid') && /ups|uninterrupt|megatec|prolink/i.test(info))
        if (!upsLike) continue
        return path
    }
    return ''
}

const UPS_STATUS_EMPTY = '{"connected":false}'

/** NUT ups name@host — match `power.ups.ups` in NixOS (default here: prolink@localhost). */
function nutUpsAddr() {
    return GLib.getenv('NUT_UPS') || 'prolink@localhost'
}

/**
 * `upsc` can keep returning old OL/% for a while after unplug; require USB id on the bus.
 * Set `NUT_USB_ID=0` to disable this check. Override id with e.g. `NUT_USB_ID=09da:1234`.
 */
function nutUsbPresenceNeedle() {
    const s = GLib.getenv('NUT_USB_ID')
    if (s === '0' || s === 'off') return null
    return s && String(s).trim() !== '' ? String(s).trim() : '0665:5161'
}

function nutUpsUsbPresent() {
    const needle = nutUsbPresenceNeedle()
    if (needle == null) return true
    try {
        const out = Utils.exec(['lsusb']) || ''
        return out.includes(needle)
    } catch {
        return false
    }
}

/** @returns {{ pct: number|null, state: string, onBattery: boolean, timeToEmpty: string, commLost: boolean }} */
function parseUpsNutUpsc(text) {
    const m = {}
    for (const line of String(text).split('\n')) {
        const i = line.indexOf(':')
        if (i === -1) continue
        m[line.slice(0, i).trim()] = line.slice(i + 1).trim()
    }
    const charge = m['battery.charge']
    let pct = null
    const chM = charge != null ? String(charge).match(/^(\d+)/) : null
    if (chM) pct = parseInt(chM[1], 10)
    const stRaw = String(m['ups.status'] || '')
    const st = stRaw.toLowerCase()
    const commLost = /\bcomm\b/i.test(stRaw) || /\bstale\b/i.test(stRaw)
    const onBattery =
        !commLost && (/\bob\b/i.test(st) || /\bdischrg\b/i.test(st) || /\blowbatt\b/i.test(st))
    let timeToEmpty = ''
    const rt = m['battery.runtime']
    if (rt && /^\d+/.test(rt)) timeToEmpty = `${Math.round(parseInt(rt, 10) / 60)} min`
    return { pct, state: st, onBattery, timeToEmpty, commLost }
}

/** @returns {{ pct: number|null, state: string, onBattery: boolean, timeToEmpty: string }} */
function parseUpsUpowerInfo(info) {
    const s = String(info)
    const pctM = s.match(/percentage:\s*(\d+)/i)
    const pct = pctM ? parseInt(pctM[1], 10) : null
    const stateM = s.match(/state:\s*([^\n]+)/i)
    const state = stateM ? stateM[1].trim().toLowerCase() : ''
    let onBattery = /discharg|pending-discharge|empty/.test(state)
    const onlineM = s.match(/online:\s*(\S+)/i)
    if (onlineM) onBattery = /^(no|false)$/i.test(onlineM[1].trim())
    const obM = s.match(/on-battery:\s*(\S+)/i)
    if (obM && /^(yes|true)$/i.test(obM[1].trim())) onBattery = true
    const tteM = s.match(/time to empty:\s*([^\n]+)/i)
    const timeToEmpty = tteM ? tteM[1].trim() : ''
    return { pct, state, onBattery, timeToEmpty }
}

/** @param {ReturnType<typeof parseUpsUpowerInfo>} p @param {boolean} connected UPower matched a UPS device */
function formatUpsCaption(p, connected) {
    if (!connected)
        return {
            line1: 'UPS',
            line2: '',
            detail: 'No UPS (UPower or NUT). On NixOS: enable power.ups, set secrets/nut.password, `upsc prolink@localhost`.',
        }
    if (p.pct == null) {
        if (p.onBattery)
            return {
                line1: 'On battery',
                line2: '—',
                detail: 'On mains loss; percentage not reported yet.',
            }
        return {
            line1: 'Connected',
            line2: '',
            detail: 'UPS detected. Waiting for charge % from UPower/NUT.',
        }
    }
    if (p.onBattery) {
        return {
            line1: `${p.pct}%`,
            line2: '',
            detail: `On battery · ${p.pct}%${p.timeToEmpty ? ` · ${p.timeToEmpty}` : ''}\nState: ${p.state || '—'}`,
        }
    }
    return {
        line1: 'Connected',
        line2: '',
        detail: `UPS on utility · ${p.pct}%\nState: ${p.state || '—'}`,
    }
}

/** @param {ReturnType<typeof parseUpsUpowerInfo>} p @param {boolean} connected */
function pickUpsIcon(p, connected) {
    if (!connected) return 'battery-symbolic'
    /* Papirus / many themes omit power-plug-symbolic — use battery symbolics only. */
    if (p.pct == null) return p.onBattery ? 'battery-empty-symbolic' : 'battery-full-charging-symbolic'
    if (p.onBattery) {
        if (p.pct <= 20) return 'battery-empty-symbolic'
        if (p.pct <= 50) return 'battery-caution-symbolic'
        if (p.pct <= 80) return 'battery-good-symbolic'
        return 'battery-full-symbolic'
    }
    const st = String(p.state || '')
    if (p.state === 'charging' || /\bchrg\b/i.test(st)) return 'battery-full-charging-symbolic'
    return 'battery-full-symbolic'
}

let __upsShutdownArmed = true

/** On battery and ≤50%: one-shot delayed poweroff (see hypr/scripts/ups-emergency-poweroff.sh). */
function maybeUpsEmergencyShutdown(parsed) {
    const pct = parsed.pct
    const onBattery = parsed.onBattery
    if (pct == null || Number.isNaN(pct)) return
    if (!onBattery || pct > 55) {
        __upsShutdownArmed = true
        return
    }
    if (pct > 50) return
    if (!__upsShutdownArmed) return
    __upsShutdownArmed = false
    const script = `${GLib.get_home_dir()}/.config/hypr/scripts/ups-emergency-poweroff.sh`
    Utils.execAsync(['bash', script, String(pct)]).catch(() => {})
}

const upsStatus = Variable(UPS_STATUS_EMPTY, {
    poll: [
        3_000,
        () => {
            try {
                const path = upowerUpsPath()
                if (path) {
                    const info = Utils.exec(['upower', '-i', path])
                    const parsed = parseUpsUpowerInfo(info)
                    maybeUpsEmergencyShutdown(parsed)
                    const cap = formatUpsCaption(parsed, true)
                    return JSON.stringify({
                        connected: true,
                        source: 'upower',
                        path,
                        ...parsed,
                        line1: cap.line1,
                        line2: cap.line2,
                        detail: cap.detail,
                        icon: pickUpsIcon(parsed, true),
                    })
                }
                const addr = nutUpsAddr()
                const nutOut = Utils.exec(['upsc', addr])
                if (!nutOut || String(nutOut).trim().length < 3) return UPS_STATUS_EMPTY
                if (!nutUpsUsbPresent()) return UPS_STATUS_EMPTY
                const parsed = parseUpsNutUpsc(nutOut)
                if (parsed.commLost) return UPS_STATUS_EMPTY
                maybeUpsEmergencyShutdown(parsed)
                const cap = formatUpsCaption(parsed, true)
                return JSON.stringify({
                    connected: true,
                    source: 'nut',
                    path: addr,
                    ...parsed,
                    line1: cap.line1,
                    line2: cap.line2,
                    detail: `${cap.detail}\n(NUT ${addr})`,
                    icon: pickUpsIcon(parsed, true),
                })
            } catch {
                return UPS_STATUS_EMPTY
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

/**
 * Tray icon that is hidden unless `init` sets the slot `visible`.
 * VPN / Bluetooth / UPS-on-battery use this; the main tray pill uses {@link TraySlot}.
 * @param {any} child
 * @param {(slot: any) => void} init hook services and assign `slot.visible`
 */
function TraySlotWhenActive(child, init) {
    return Widget.Box({
        class_name: 'tray-slot',
        valign: 'center',
        halign: 'center',
        child,
        setup: init,
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
                            Utils.exec(['bash', WORKSPACE_GOTO, String(id)])
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

function wifiMenuName(/** @type {number} */ m) {
    return `wifiMenu${m}`
}

function closeAllMonitorOverlays(/** @type {number} */ m) {
    App.closeWindow(trayFlyoutName(m))
    App.closeWindow(quickSettingsName(m))
    App.closeWindow(wifiMenuName(m))
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

function toggleWifiMenu(/** @type {number} */ m) {
    if (App.getWindow(wifiMenuName(m))?.visible) {
        closeAllMonitorOverlays(m)
        return
    }
    closeAllMonitorOverlays(m)
    try {
        Network.wifi?.scan?.()
    } catch {
        /* ignore */
    }
    try {
        Utils.exec(['nmcli', 'device', 'wifi', 'list', '--rescan', 'yes'])
    } catch {
        try {
            Utils.exec(['nmcli', 'device', 'wifi', 'rescan'])
        } catch {
            /* ignore */
        }
    }
    App.openWindow(flyoutScrimName(m))
    App.openWindow(wifiMenuName(m))
}

/** @returns {Map<string, boolean>} SSID → needs password */
function nmWifiSecurityMap() {
    const m = new Map()
    const parseTab = (out) => {
        for (const line of String(out).trim().split('\n')) {
            if (!line) continue
            const ix = line.indexOf('\t')
            if (ix === -1) continue
            const ssid = line.slice(0, ix)
            const sec = line.slice(ix + 1).trim()
            m.set(ssid, sec !== '--' && sec !== '')
        }
    }
    const parseColon = (out) => {
        for (const line of String(out).trim().split('\n')) {
            if (!line) continue
            const ix = line.lastIndexOf(':')
            if (ix <= 0) continue
            const ssid = line.slice(0, ix)
            const sec = line.slice(ix + 1).trim()
            m.set(ssid, sec !== '--' && sec !== '')
        }
    }
    try {
        parseTab(Utils.exec(['nmcli', '-m', 'tab', '-t', '-f', 'SSID,SECURITY', 'dev', 'wifi']) || '')
        return m
    } catch {
        m.clear()
        try {
            parseColon(Utils.exec(['nmcli', '-t', '-f', 'SSID,SECURITY', 'dev', 'wifi']) || '')
        } catch {
            /* ignore */
        }
        return m
    }
}

function wifiDedupedAps() {
    const w = Network.wifi
    if (!w) return []
    let raw
    try {
        raw = w.access_points
    } catch {
        return []
    }
    if (!raw?.length) return []
    /** @type {Map<string, any>} */
    const best = new Map()
    for (const ap of raw) {
        const ssid = ap.ssid
        if (!ssid) continue
        const prev = best.get(ssid)
        if (!prev || ap.strength > prev.strength) best.set(ssid, ap)
    }
    return [...best.values()].sort((a, b) => b.strength - a.strength)
}

function apIconSuggestsOpen(/** @type {any} */ ap) {
    const n = (ap.iconName || '').toLowerCase()
    return n.includes('open') || n.includes('unencrypt') || n.includes('unsecure')
}

function nmcliSignalIcon(/** @type {number} */ strength) {
    const s = Number(strength) || 0
    if (s >= 67) return 'network-wireless-signal-excellent-symbolic'
    if (s >= 34) return 'network-wireless-signal-good-symbolic'
    if (s > 0) return 'network-wireless-signal-ok-symbolic'
    return 'network-wireless-signal-none-symbolic'
}

/** First physical Ethernet device NM knows about, or null (no driver / no NIC). */
function nmcliEthernetDevice() {
    let out = ''
    try {
        out = Utils.exec(['nmcli', '-t', '-f', 'DEVICE,TYPE,STATE', 'device']) || ''
    } catch {
        return null
    }
    for (const line of String(out).trim().split('\n')) {
        if (!line) continue
        const [dev, type] = line.split(':')
        if (type !== 'ethernet' || !dev) continue
        if (dev.startsWith('veth') || dev.startsWith('br')) continue
        return dev
    }
    return null
}

/** Turn Wi-Fi radio off and ask NM to bring up wired (when an Ethernet device exists). */
function preferEthernetOverWifi() {
    const dev = nmcliEthernetDevice()
    Utils.execAsync(['nmcli', 'radio', 'wifi', 'off'])
        .then(() => (dev ? Utils.execAsync(['nmcli', '-w', '30', 'device', 'connect', dev]) : Promise.resolve()))
        .then(() =>
            Utils.execAsync([
                'notify-send',
                '-a',
                'Network',
                'Using wired',
                dev ? `Wi-Fi off · ${dev}` : 'Wi-Fi off (no Ethernet device in NM)',
            ]).catch(() => {}),
        )
        .catch(() =>
            Utils.execAsync(['notify-send', '-a', 'Network', 'Wired', 'Could not switch to wired']).catch(() => {}),
        )
}

/**
 * SSIDs from nmcli (several argv shapes — NM versions differ).
 * @returns {{ ssid: string, strength: number, active: boolean, secured: boolean, iconName: string }[]}
 */
function nmcliWifiRowsParsed() {
    /** @type {string[][]} */
    const attempts = [
        ['nmcli', '-m', 'tab', '-t', '-f', 'SSID,SIGNAL,SECURITY,IN-USE', 'device', 'wifi', 'list'],
        ['nmcli', '-m', 'tab', '-t', '-f', 'SSID,SIGNAL,SECURITY,ACTIVE', 'device', 'wifi', 'list'],
        ['nmcli', '-m', 'tab', '-t', '-f', 'SSID,SIGNAL,SECURITY', 'device', 'wifi', 'list'],
        ['nmcli', '-m', 'tab', '-t', '-f', 'SSID,SIGNAL,SECURITY', 'dev', 'wifi', 'list'],
        ['nmcli', '-m', 'tab', '-t', '-f', 'SSID,SIGNAL', 'device', 'wifi', 'list'],
        ['nmcli', '-m', 'tab', '-t', '-f', 'SSID,SIGNAL,SECURITY', 'device', 'wifi'],
        ['nmcli', '-m', 'tab', '-t', '-f', 'SSID,SIGNAL,SECURITY', 'dev', 'wifi'],
    ]
    let out = ''
    for (const cmd of attempts) {
        try {
            const o = Utils.exec(cmd) || ''
            const t = String(o).trim()
            if (t.length > 0 && !/^error\b/i.test(t)) {
                out = t
                break
            }
        } catch {
            /* try next */
        }
    }
    if (!out) return []

    let cur = null
    try {
        if (Network.wifi?.internet === 'connected' && Network.wifi?.ssid) {
            cur = String(Network.wifi.ssid)
        }
    } catch {
        cur = null
    }
    const secMap = nmWifiSecurityMap()
    const seen = new Set()
    /** @type {{ ssid: string, strength: number, active: boolean, secured: boolean, iconName: string }[]} */
    const rows = []
    for (const line of out.split('\n')) {
        if (!line) continue
        const p = line.split('\t')
        if (p.length < 2) continue
        const ssid = (p[0] || '').trim()
        if (!ssid || ssid === '--' || seen.has(ssid)) continue
        seen.add(ssid)
        const signal = parseInt(p[1], 10)
        const security = p.length >= 3 ? (p[2] || '').trim() : ''
        const useFlag = p.length >= 4 ? (p[3] || '').trim() : ''
        const inUse =
            useFlag === '*' ||
            useFlag.toLowerCase() === 'yes' ||
            (cur != null && ssid === cur)
        let secured
        if (p.length >= 3) {
            secured = security !== '' && security !== '--'
        } else if (secMap.has(ssid)) {
            secured = !!secMap.get(ssid)
        } else {
            secured = true
        }
        rows.push({
            ssid,
            strength: Number.isFinite(signal) ? signal : 0,
            active: inUse,
            secured,
            iconName: nmcliSignalIcon(signal),
        })
    }
    rows.sort((a, b) => b.strength - a.strength)
    return rows
}

/** @param {any[]} ags */
function wifiRowsFromAgs(ags) {
    const secMap = nmWifiSecurityMap()
    return ags.map((ap) => {
        let secured = secMap.get(ap.ssid)
        if (secured === undefined) secured = !apIconSuggestsOpen(ap)
        return {
            ssid: ap.ssid,
            strength: ap.strength ?? 0,
            active: !!ap.active,
            secured: !!secured,
            iconName: ap.iconName || nmcliSignalIcon(ap.strength ?? 0),
        }
    })
}

/**
 * Union of AGS + nmcli rows (AGS often omits APs; nmcli is the reliable list on many setups).
 */
function wifiRowsForMenu() {
    if (!Network.wifi?.enabled) return []

    const fromAgs = wifiRowsFromAgs(wifiDedupedAps())
    let fromNm = []
    try {
        fromNm = nmcliWifiRowsParsed()
    } catch {
        fromNm = []
    }

    /** @type {Map<string, { ssid: string, strength: number, active: boolean, secured: boolean, iconName: string }>} */
    const best = new Map()
    for (const r of [...fromAgs, ...fromNm]) {
        const prev = best.get(r.ssid)
        if (!prev) {
            best.set(r.ssid, { ...r })
            continue
        }
        const pick =
            r.strength > prev.strength ||
            (r.strength === prev.strength && r.active && !prev.active)
        if (pick) {
            best.set(r.ssid, {
                ...r,
                active: r.active || prev.active,
            })
        } else if (r.active && !prev.active) {
            best.set(r.ssid, { ...prev, active: true })
        }
    }
    return [...best.values()].sort((a, b) => b.strength - a.strength)
}

/** Win11-style Wi-Fi list (nmcli connect). */
function WifiMenuPanel(/** @type {number} */ monitor) {
    /** @type {string | null} */
    let selectedSsid = null

    const errLbl = Widget.Label({
        class_name: 'wifi-menu-err',
        xalign: 0,
        visible: false,
        wrap: true,
    })
    const passwordEntry = Widget.Entry({
        class_name: 'wifi-menu-entry',
        placeholder_text: 'Network security key',
        hexpand: true,
        visibility: false,
    })
    const autoSw = Widget.Switch({ valign: 'center', active: true })

    const listBin = Widget.Box({ vertical: true, class_name: 'wifi-menu-list' })

    const details = Widget.Box({
        class_name: 'wifi-menu-details',
        vertical: true,
        spacing: 8,
        visible: false,
    })

    function securedFor(ssid) {
        const secMap = nmWifiSecurityMap()
        if (secMap.has(ssid)) return !!secMap.get(ssid)
        const ap = wifiDedupedAps().find((a) => a.ssid === ssid)
        if (!ap) return true
        return !apIconSuggestsOpen(ap)
    }

    function applyDetails() {
        if (!selectedSsid) {
            details.visible = false
            details.children = []
            return
        }
        const secured = securedFor(selectedSsid)
        details.visible = true
        details.children = [
            Widget.Label({
                class_name: 'wifi-menu-sub',
                xalign: 0,
                label: secured ? 'Secured' : 'Open',
            }),
            ...(secured
                ? [
                      Widget.Box({
                          class_name: 'wifi-menu-pwrow',
                          spacing: 6,
                          children: [
                              passwordEntry,
                              Widget.Button({
                                  class_name: 'wifi-menu-eye',
                                  cursor: 'pointer',
                                  child: Widget.Icon({ icon: 'view-reveal-symbolic', size: 18 }),
                                  on_clicked: (btn) => {
                                      passwordEntry.visibility = !passwordEntry.visibility
                                      btn.child.icon = passwordEntry.visibility
                                          ? 'view-conceal-symbolic'
                                          : 'view-reveal-symbolic'
                                  },
                              }),
                          ],
                      }),
                  ]
                : []),
            Widget.Box({
                class_name: 'wifi-menu-auto',
                spacing: 8,
                valign: 'center',
                children: [
                    autoSw,
                    Widget.Label({
                        class_name: 'wifi-menu-sub',
                        xalign: 0,
                        label: 'Connect automatically',
                    }),
                ],
            }),
            Widget.Box({
                class_name: 'wifi-menu-actions',
                spacing: 8,
                children: [
                    Widget.Button({
                        class_name: 'wifi-menu-btn wifi-menu-btn-primary',
                        cursor: 'pointer',
                        hexpand: true,
                        label: 'Connect',
                        on_clicked: () => {
                            if (!selectedSsid) return
                            const sec = securedFor(selectedSsid)
                            if (sec && !passwordEntry.text) {
                                errLbl.label = 'Enter the network security key.'
                                errLbl.visible = true
                                return
                            }
                            errLbl.visible = false
                            const args = ['nmcli', 'device', 'wifi', 'connect', selectedSsid]
                            if (sec && passwordEntry.text) args.push('password', passwordEntry.text)
                            Utils.execAsync(args)
                                .then(() => {
                                    closeAllMonitorOverlays(monitor)
                                    try {
                                        Network.wifi?.scan?.()
                                    } catch {
                                        /* ignore */
                                    }
                                })
                                .catch(() => {
                                    errLbl.label =
                                        'Could not connect. Check the password and try again.'
                                    errLbl.visible = true
                                })
                        },
                    }),
                    Widget.Button({
                        class_name: 'wifi-menu-btn wifi-menu-btn-ghost',
                        cursor: 'pointer',
                        hexpand: true,
                        label: 'Cancel',
                        on_clicked: () => {
                            selectedSsid = null
                            passwordEntry.text = ''
                            errLbl.visible = false
                            rebuild()
                        },
                    }),
                ],
            }),
        ]
    }

    function rebuildList() {
        if (!Network.wifi?.enabled) {
            listBin.children = [
                Widget.Label({
                    class_name: 'wifi-menu-hint',
                    wrap: true,
                    xalign: 0.5,
                    label: 'Wi-Fi is off. Turn it on to see networks.',
                }),
            ]
            return
        }

        const rows = wifiRowsForMenu()
        if (rows.length === 0) {
            listBin.children = [
                Widget.Label({
                    class_name: 'wifi-menu-hint',
                    wrap: true,
                    xalign: 0.5,
                    label: 'Looking for networks…\nIf nothing appears, try again in a few seconds.',
                }),
            ]
        } else {
            listBin.children = rows.map((row) => {
                const ssid = row.ssid
                const sel = selectedSsid === ssid
                return Widget.EventBox({
                    class_name: `wifi-menu-row${sel ? ' wifi-menu-row-sel' : ''}${row.active ? ' wifi-menu-row-active' : ''}`,
                    cursor: 'pointer',
                    on_primary_click: () => {
                        const next = sel ? null : ssid
                        selectedSsid = next
                        if (next) passwordEntry.text = ''
                        errLbl.visible = false
                        rebuild()
                    },
                    child: Widget.Box({
                        class_name: 'wifi-menu-row-inner',
                        spacing: 8,
                        children: [
                            Widget.Box({
                                class_name: sel ? 'wifi-menu-sel-bar' : 'wifi-menu-sel-spacer',
                            }),
                            Widget.Icon({
                                icon: row.iconName || 'network-wireless-signal-good-symbolic',
                                size: 20,
                            }),
                            Widget.Label({
                                class_name: 'wifi-menu-ssid',
                                hexpand: true,
                                xalign: 0,
                                truncate: 'end',
                                label: ssid,
                            }),
                        ],
                    }),
                })
            })
        }
    }

    function rebuild() {
        if (!Network.wifi?.enabled) {
            rebuildList()
            selectedSsid = null
            errLbl.visible = false
            details.visible = false
            details.children = []
            return
        }
        rebuildList()
        if (selectedSsid && !wifiRowsForMenu().some((r) => r.ssid === selectedSsid)) {
            selectedSsid = null
            passwordEntry.text = ''
            errLbl.visible = false
        }
        applyDetails()
    }

    /** Avoid `notify::active` when syncing from Network (prevents NM / UI fighting). */
    let wifiSwitchProgrammatic = false

    /** @param {any} sw */
    function pullWifiSwitch(sw) {
        if (!Network.wifi) return
        const want = !!Network.wifi.enabled
        if (!!sw.active === want) return
        wifiSwitchProgrammatic = true
        sw.active = want
        wifiSwitchProgrammatic = false
    }

    const wifiSw = Widget.Switch({
        valign: 'center',
        class_name: 'wifi-menu-switch',
        setup: (sw) => {
            sw.connect('notify::active', () => {
                if (wifiSwitchProgrammatic || !Network.wifi) return
                const want = !!sw.active
                if (!!Network.wifi.enabled === want) return
                Network.wifi.enabled = want
                try {
                    Network.wifi.scan?.()
                } catch {
                    /* ignore */
                }
                GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
                    rebuildList()
                    return GLib.SOURCE_REMOVE
                })
                if (want) {
                    Utils.timeout(350, () => {
                        try {
                            Network.wifi?.scan?.()
                        } catch {
                            /* ignore */
                        }
                        try {
                            Utils.exec(['nmcli', 'device', 'wifi', 'list', '--rescan', 'yes'])
                        } catch {
                            try {
                                Utils.exec(['nmcli', 'device', 'wifi', 'rescan'])
                            } catch {
                                /* ignore */
                            }
                        }
                        rebuildList()
                    })
                    Utils.timeout(1200, () => {
                        try {
                            Network.wifi?.scan?.()
                        } catch {
                            /* ignore */
                        }
                        rebuildList()
                    })
                }
            })
        },
    })

    return Widget.Window({
        monitor,
        name: wifiMenuName(monitor),
        class_name: 'wifi-menu',
        anchor: ['top', 'right'],
        exclusivity: 'normal',
        layer: 'overlay',
        margins: [BAR_CLEARANCE_PX, 16, 0, 0],
        visible: false,
        setup: (self) => {
            self.hook(Network, () => {
                pullWifiSwitch(wifiSw)
                if (!Network.wifi?.enabled) {
                    selectedSsid = null
                    errLbl.visible = false
                    rebuild()
                    return
                }
                rebuildList()
                if (wifiRowsForMenu().length === 0) {
                    try {
                        Network.wifi.scan?.()
                    } catch {
                        /* ignore */
                    }
                    try {
                        Utils.exec(['nmcli', 'device', 'wifi', 'list', '--rescan', 'yes'])
                    } catch {
                        try {
                            Utils.exec(['nmcli', 'device', 'wifi', 'rescan'])
                        } catch {
                            /* ignore */
                        }
                    }
                }
                if (selectedSsid && !wifiRowsForMenu().some((r) => r.ssid === selectedSsid)) {
                    selectedSsid = null
                    passwordEntry.text = ''
                    errLbl.visible = false
                    applyDetails()
                }
            })
            rebuild()
            pullWifiSwitch(wifiSw)
        },
        child: Widget.Box({
            vertical: true,
            class_name: 'wifi-menu-shell',
            children: [
                Widget.Box({
                    class_name: 'wifi-menu-head',
                    valign: 'center',
                    spacing: 8,
                    children: [
                        Widget.Button({
                            class_name: 'wifi-menu-back',
                            cursor: 'pointer',
                            child: Widget.Icon({ icon: 'go-previous-symbolic', size: 18 }),
                            on_clicked: () => closeAllMonitorOverlays(monitor),
                        }),
                        Widget.Label({
                            class_name: 'wifi-menu-title',
                            hexpand: true,
                            xalign: 0,
                            label: 'Wi-Fi',
                        }),
                        wifiSw,
                    ],
                }),
                Widget.Scrollable({
                    class_name: 'wifi-menu-scroll',
                    vscroll: 'always',
                    hscroll: 'never',
                    hexpand: true,
                    css: 'min-height: 120px;',
                    child: listBin,
                }),
                errLbl,
                details,
                Widget.Button({
                    class_name: 'wifi-menu-more',
                    cursor: 'pointer',
                    halign: 'start',
                    label: 'More Wi-Fi settings',
                    on_clicked: () => {
                        Utils.execAsync(['nm-connection-editor']).catch(() => {})
                    },
                }),
            ],
        }),
    })
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
    const icoIn = Widget.Icon({ class_name: 'qs-tile-ico', size: QS_TILE_ICON_PX })
    const icoAct = Widget.Icon({ class_name: 'qs-tile-ico', size: QS_TILE_ICON_PX })

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
        vexpand: true,
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
        vexpand: true,
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
    // Do not require Network.primary === 'wired': NM often reports primary as Wi-Fi while
    // Ethernet still carries the default route, so the tile wrongly showed only Wi-Fi.
    const ethernetLive = () => !!Network.wired && Network.wired.internet === 'connected'

    const netTile = qsAdaptivePill(
        netLabel,
        () => {
            if (nmcliEthernetDevice() && Network.wifi?.enabled && !ethernetLive()) {
                preferEthernetOverWifi()
                return
            }
            if (ethernetLive() && Network.wifi) {
                Network.toggleWifi()
                return
            }
            if (!Network.wifi) {
                Utils.execAsync(['nm-connection-editor']).catch(() => {})
                return
            }
            if (!Network.wifi.enabled) {
                Network.wifi.enabled = true
                try {
                    Network.wifi.scan?.()
                } catch {
                    /* ignore */
                }
            }
            toggleWifiMenu(monitor)
        },
        () => {
            if (Network.wifi) toggleWifiMenu(monitor)
            else Utils.execAsync(['nm-connection-editor']).catch(() => {})
        },
        (_outer, icoIn) => {
            if (ethernetLive()) {
                icoIn.icon = 'video-display-symbolic'
                netLabel.label = 'Ethernet'
                return true
            }
            if (Network.wifi) {
                const w = Network.wifi
                icoIn.icon = w.icon_name || 'network-wireless-symbolic'
                netLabel.label =
                    w.enabled && w.internet === 'connected' && w.ssid ? w.ssid : 'Wi-Fi'
                return w.enabled && w.internet === 'connected'
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

    const vpnIcon = Widget.Icon({ class_name: 'qs-tile-ico', size: QS_TILE_ICON_PX, icon: 'network-vpn-symbolic' })
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
        size: QS_TILE_ICON_PX,
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

    const nightIcon = Widget.Icon({ class_name: 'qs-tile-ico', size: QS_TILE_ICON_PX, icon: 'weather-clear-symbolic' })
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

    const upsIcon = Widget.Icon({ class_name: 'qs-tile-ico', size: QS_TILE_ICON_PX, icon: 'battery-full-symbolic' })
    const upsCap = Widget.Label({ class_name: 'qs-tile-cap', label: 'UPS', xalign: 0.5, wrap: true, max_width_chars: 18 })
    const upsTile = Widget.Box({
        vertical: true,
        class_name: 'qs-tile-outer qs-tile-ups',
        hexpand: true,
        vexpand: true,
        children: [
            Widget.Button({
                class_name: 'qs-tile-simple',
                hexpand: true,
                vexpand: true,
                cursor: 'pointer',
                on_clicked: () => {
                    try {
                        const raw = upsStatus.value
                        const j = JSON.parse(typeof raw === 'string' ? raw : '{}')
                        const body = j.connected && j.detail ? String(j.detail).slice(0, 500) : 'No UPS data.'
                        Utils.execAsync(['notify-send', '-a', 'UPS', 'Status', body]).catch(() => {})
                    } catch {
                        /* ignore */
                    }
                },
                child: Widget.CenterBox({
                    class_name: 'qs-tile-simple-inner',
                    hexpand: true,
                    vexpand: true,
                    center_widget: upsIcon,
                }),
            }),
            upsCap,
        ],
        setup: (outer) => {
            const sync = () => {
                let j = { connected: false }
                try {
                    const raw = upsStatus.value
                    j = JSON.parse(typeof raw === 'string' ? raw : '{}')
                } catch {
                    j = { connected: false }
                }
                const connected = !!j.connected
                outer.toggleClassName('qs-tile-active', connected)
                outer.toggleClassName('qs-tile-ups-batt', !!(connected && j.onBattery))
                if (connected) {
                    upsIcon.icon = j.icon || 'battery-full-symbolic'
                    upsCap.label = j.line2 ? `${j.line1}\n${j.line2}` : String(j.line1 || 'UPS')
                    outer.tooltip_text = `${j.detail || ''}\n\n≤50% on battery → power off in 90s (see notify).`
                } else {
                    upsIcon.icon = 'battery-symbolic'
                    upsCap.label = 'UPS'
                    outer.tooltip_text = 'UPS · UPower (USB). Click for details.'
                }
            }
            outer.hook(upsStatus, sync)
            sync()
        },
    })

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
                    class_name: 'qs-header',
                    valign: 'center',
                    children: [
                        Widget.Label({
                            class_name: 'qs-header-date',
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
                Widget.Separator({ class_name: 'qs-sep' }),
                Widget.Box({
                    class_name: 'qs-slider-block',
                    vertical: true,
                    spacing: 12,
                    children: [qsSpeakerSliderRow(), qsMicSliderRow()],
                }),
                Widget.Separator({ class_name: 'qs-sep' }),
                Widget.Box({
                    class_name: 'qs-grid-surface',
                    vertical: true,
                    children: [
                        Widget.Box({
                            class_name: 'qs-grid',
                            vertical: true,
                            spacing: 8,
                            children: [
                                Widget.Box({
                                    class_name: 'qs-row',
                                    homogeneous: true,
                                    valign: 'fill',
                                    spacing: 8,
                                    children: [netTile, btTile],
                                }),
                                Widget.Box({
                                    class_name: 'qs-row',
                                    homogeneous: true,
                                    valign: 'fill',
                                    spacing: 8,
                                    children: [vpnTile, focusTile],
                                }),
                                Widget.Box({
                                    class_name: 'qs-row',
                                    homogeneous: true,
                                    valign: 'fill',
                                    spacing: 8,
                                    children: [nightTile, upsTile],
                                }),
                            ],
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
        child: Widget.Label({
            class_name: 'clock',
            xalign: 0,
            label: time.bind(),
        }),
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

/** Bar: only while UPS is on battery (mains lost); click opens quick settings. */
function UpsBarTray(/** @type {number} */ m) {
    const icon = Widget.Icon({ class_name: 'tray-ico', size: TRAY_ICON_PX, icon: 'battery-good-symbolic' })
    const lbl = Widget.Label({ class_name: 'ups-tray-pct', label: '', valign: 'center' })
    return Widget.EventBox({
        class_name: 'ups-tray',
        cursor: 'pointer',
        tooltip_text: 'UPS',
        on_primary_click: () => toggleQuickSettings(m),
        child: Widget.Box({
            class_name: 'ups-tray-inner',
            spacing: 4,
            valign: 'center',
            children: [icon, lbl],
        }),
        setup: (/** @type {any} */ self) => {
            /** @param {any} slot */
            self.syncUpsTray = (slot) => {
                let j = {}
                try {
                    const raw = upsStatus.value
                    j = JSON.parse(typeof raw === 'string' ? raw : '{}')
                } catch {
                    j = {}
                }
                const pct = j.pct != null ? Number(j.pct) : NaN
                const show = !!(j.connected && j.onBattery && !Number.isNaN(pct))
                slot.visible = show
                if (!show) return
                const p = {
                    pct,
                    state: String(j.state || ''),
                    onBattery: !!j.onBattery,
                    timeToEmpty: String(j.timeToEmpty || ''),
                }
                icon.icon = pickUpsIcon(p, true)
                lbl.label = `${pct}%`
                self.tooltip_text = `UPS on battery · ${pct}% · click for quick settings`
            }
        },
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

/** True when the default route looks connected (wired or Wi-Fi). */
function networkHasInternet() {
    if (Network.wired?.internet === 'connected') return true
    if (Network.wifi) {
        const w = Network.wifi
        return (
            !!w.enabled &&
            w.internet === 'connected' &&
            Network.connectivity !== 'none'
        )
    }
    return false
}

/** Network tray — Quick settings when online; Wi-Fi menu when offline (if Wi-Fi exists). */
function NetworkTrayIcon(/** @type {number} */ m) {
    return Widget.EventBox({
        class_name: 'net-tray',
        cursor: 'pointer',
        setup: (self) => {
            const tip = () => {
                if (
                    Network.wifi?.enabled &&
                    nmcliEthernetDevice() &&
                    Network.wired?.internet !== 'connected'
                ) {
                    self.tooltip_text =
                        'Network · Click: Wi-Fi off & use Ethernet · Right-click: connection editor'
                } else if (networkHasInternet()) {
                    self.tooltip_text = 'Network · Click: Quick settings · Right-click: connection editor'
                } else if (Network.wifi) {
                    self.tooltip_text = 'Network · Click: Wi-Fi · Right-click: connection editor'
                } else {
                    self.tooltip_text = 'Network · Click: Quick settings · Right-click: connection editor'
                }
            }
            self.hook(Network, tip)
            tip()
        },
        on_primary_click: () => {
            if (
                Network.wifi?.enabled &&
                nmcliEthernetDevice() &&
                Network.wired?.internet !== 'connected'
            ) {
                preferEthernetOverWifi()
                return
            }
            if (networkHasInternet()) toggleQuickSettings(m)
            else if (Network.wifi) toggleWifiMenu(m)
            else toggleQuickSettings(m)
        },
        on_secondary_click: () => {
            Utils.execAsync(['nm-connection-editor']).catch(() => {})
        },
        child: Widget.Icon({
            class_name: 'tray-ico',
            size: TRAY_ICON_PX,
            icon: 'video-display-symbolic',
            setup: (self) => {
                const sync = () => {
                    const on = networkHasInternet()
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
                spacing: 8,
                hpack: 'end',
                children: [
                    TraySlotWhenActive(VpnTrayIcon(monitor), (slot) => {
                        const sync = () => {
                            const act = Network.vpn?.activated_connections ?? []
                            const s = act[0]?.state
                            slot.visible =
                                s === 'connected' || s === 'connecting' || s === 'disconnecting'
                        }
                        slot.hook(Network, sync)
                        sync()
                    }),
                    TraySlotWhenActive(BluetoothTrayIcon(monitor), (slot) => {
                        const sync = () => {
                            const n = Bluetooth.connected_devices?.length ?? 0
                            slot.visible = !!Bluetooth.enabled && n > 0
                        }
                        slot.hook(Bluetooth, sync)
                        sync()
                    }),
                    TraySlotWhenActive(
                        Widget.Box({
                            class_name: 'tray-chip-circle tray-chip-ups',
                            valign: 'center',
                            child: UpsBarTray(monitor),
                        }),
                        (slot) => {
                            const upsEv = slot.child?.child
                            const sync = () => {
                                if (upsEv && typeof upsEv.syncUpsTray === 'function') upsEv.syncUpsTray(slot)
                            }
                            slot.hook(upsStatus, sync)
                            sync()
                        },
                    ),
                    Widget.Box({
                        class_name: 'tray-pill',
                        valign: 'center',
                        spacing: 0,
                        children: [
                            TraySlot(MicTray(monitor)),
                            TraySlot(NetworkTrayIcon(monitor)),
                            TraySlot(VolumeTray(monitor)),
                        ],
                    }),
                    Widget.Box({
                        class_name: 'tray-chip-circle',
                        valign: 'center',
                        child: TraySlot(NotificationTrayButton(monitor)),
                    }),
                ],
            }),
        }),
    })

const bars = [...Array(nMon).keys()].map((i) => Bar(i))
const flyoutScrims = [...Array(nMon).keys()].map((i) => FlyoutScrim(i))
const quickSettingsWins = [...Array(nMon).keys()].map((i) => QuickSettingsPanel(i))
const wifiMenuWins = [...Array(nMon).keys()].map((i) => WifiMenuPanel(i))
const trayFlyouts = [...Array(nMon).keys()].map((i) => TrayFlyout(i))

App.config({
    style: `${App.configDir}/style.css`,
    windows: [...bars, ...flyoutScrims, ...quickSettingsWins, ...wifiMenuWins, ...trayFlyouts],
})
