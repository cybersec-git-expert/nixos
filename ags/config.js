import GLib from 'gi://GLib'
import Gdk from 'gi://Gdk'

const decoder = new TextDecoder()

const time = Variable('', {
    poll: [1000, () => new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })],
})

const wsScript = GLib.build_filenamev([GLib.get_home_dir(), '.config/hypr/scripts/hypr-active-workspace.sh'])

const workspace = Variable('?', {
    poll: [
        1500,
        () => {
            const [, stdout] = GLib.spawn_command_line_sync(wsScript)
            if (!stdout) return '?'
            const t = decoder.decode(stdout).trim()
            return t || '?'
        },
    ],
})

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
            start_widget: Widget.Label({
                class_name: 'ws',
                hpack: 'start',
                label: workspace.bind(),
            }),
            center_widget: Widget.Label({
                class_name: 'title',
                label: 'Hyprland',
            }),
            end_widget: Widget.Label({
                class_name: 'clock',
                hpack: 'end',
                label: time.bind(),
            }),
        }),
    })

App.config({
    style: `${App.configDir}/style.css`,
    windows: [...Array(nMon).keys()].map((i) => Bar(i)),
})
