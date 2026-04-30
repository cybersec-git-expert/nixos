#!/usr/bin/env bash
# Route F4–F6 media keys: prefer whoever is Playing, then Quickshell preferred
# (/tmp/qs_preferred_player), then Paused. Uses mpc for MPD so Spotify does not
# receive transport when you were using mpd/mpc.
#
# Usage: playerctl-mediakey.sh play-pause|previous|next|stop

cmd="${1:-}"
[ -z "$cmd" ] && exit 0

PREF_FILE="/tmp/qs_preferred_player"

mpc_cmd() {
	command -v mpc &>/dev/null || return 0
	case "$cmd" in
	play-pause) mpc -q toggle ;;
	previous) mpc -q prev ;;
	next) mpc -q next ;;
	stop) mpc -q stop ;;
	esac
}

playerctl_cmd() {
	local player="$1"
	case "$cmd" in
	play-pause) playerctl -p "$player" play-pause ;;
	previous) playerctl -p "$player" previous ;;
	next) playerctl -p "$player" next ;;
	stop) playerctl -p "$player" stop 2>/dev/null || playerctl -p "$player" pause ;;
	esac
}

pick_target() {
	local p s pref paused_mpris=""

	while IFS= read -r p; do
		[ -z "$p" ] && continue
		s=$(playerctl -p "$p" status 2>/dev/null || true)
		if [ "$s" = "Playing" ]; then
			echo "mpris:$p"
			return 0
		fi
		if [ "$s" = "Paused" ] && [ -z "$paused_mpris" ]; then
			paused_mpris="$p"
		fi
	done < <(playerctl -l 2>/dev/null)

	if command -v mpc &>/dev/null; then
		if mpc status 2>/dev/null | grep -qF '[playing]'; then
			echo "mpc"
			return 0
		fi
	fi

	pref=""
	[ -f "$PREF_FILE" ] && pref=$(tr -d '\n\r ' <"$PREF_FILE" 2>/dev/null || true)
	if [ -n "$pref" ]; then
		if [ "$pref" = "mpd" ] && command -v mpc &>/dev/null; then
			if mpc status 2>/dev/null | grep -qE '\[playing\]|\[paused\]'; then
				echo "mpc"
				return 0
			fi
		else
			s=$(playerctl -p "$pref" status 2>/dev/null || true)
			if [ "$s" = "Playing" ] || [ "$s" = "Paused" ]; then
				echo "mpris:$pref"
				return 0
			fi
		fi
	fi

	if [ -n "$paused_mpris" ]; then
		echo "mpris:$paused_mpris"
		return 0
	fi

	if command -v mpc &>/dev/null; then
		if mpc status 2>/dev/null | grep -qF '[paused]'; then
			echo "mpc"
			return 0
		fi
	fi

	p=$(playerctl -l 2>/dev/null | head -n1)
	if [ -n "$p" ]; then
		echo "mpris:$p"
		return 0
	fi

	if command -v mpc &>/dev/null; then
		echo "mpc"
		return 0
	fi

	return 1
}

t=$(pick_target) || exit 0
[ -z "$t" ] && exit 0

case "$t" in
mpc) mpc_cmd ;;
mpris:*) playerctl_cmd "${t#mpris:}" ;;
esac
