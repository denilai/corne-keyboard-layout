#!/usr/bin/env bash
# <xbar.title>Corne battery</xbar.title>
# <xbar.desc>Battery of both Corne halves (no-dongle setup), read over Bluetooth.</xbar.desc>
# <swiftbar.type>streamable</swiftbar.type>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
#
# SwiftBar streamable plugin: it runs all the time and prints a new menu after
# each "~~~" line. Installed by scripts/swiftbar.sh install as a link from the
# plugin folder.
#
# Two sources write lines into one FIFO, the plugin redraws on each:
#   corne-watch (scripts/corne-watch.swift), IOKit, no permission:
#     connected / disconnected   the left half woke up / fell asleep
#     tick                       timer: make sure the reader runs
#   CorneBattery.app --watch (scripts/battery-mac.swift), Bluetooth:
#     levels <left> <right>      at start and on every change, as GATT
#                                notifications: also when the right half wakes
#                                up and connects to the left one ("-" = asleep)
#     disconnected               the left half went away; the reader exits
#     alive                      heartbeat, ignored
# The reader runs only while the left half is connected. Reading does not
# count as key activity, it does not keep the halves awake.
#
# SwiftBar has no Bluetooth permission, so the reader is its own app with its
# own permission; `open` starts it with its output going into the FIFO.
#
# Menu format: first line is the menu bar title, after "---" the dropdown;
# "| key=value" sets color, actions etc.
set -uo pipefail

APP="$HOME/Applications/CorneBattery.app"
WATCH="$HOME/Library/Application Support/CorneBattery/corne-watch"
LOW=20          # % for the red title and a notification
SETTLE=3        # s after the left half connects before the reader starts
TICK_S=120      # how often to check that the reader runs (connected)
ASLEEP_TICK_S=300
DATA="${SWIFTBAR_PLUGIN_DATA_PATH:-${TMPDIR:-/tmp}/corne-battery}"
mkdir -p "$DATA"
LOW_FLAG="$DATA/low"   # a notification was sent for the current drop
LAST="$DATA/last"      # "left right HH:MM" of the last read
FIFO="$DATA/events"

footer() {
    echo "---"
    echo "Refresh | refresh=true"
    echo "Bluetooth settings | href=x-apple.systempreferences:com.apple.BluetoothSettings"
}

last_line() {
    [ -f "$LAST" ] || return 0
    read -r l r t <"$LAST"
    echo "Last read: left $l%, right $r% at $t | size=11"
}

asleep() {
    echo "⌨ zz"
    echo "---"
    echo "Corne not connected: asleep or off (a key press wakes it)"
    last_line
    footer
}

problem() {   # a message from the reader instead of levels
    echo "⌨ –"
    echo "---"
    echo "$*" | sed 's/|/¦/g'   # "|" would be parsed by SwiftBar
    last_line
    footer
}

# levels <left> <right>, "-" = that half is not connected
levels() {
    local left="$1" right="$2" min=100 color="" shown_r="$2" shown_l="$1"
    [ "$right" = - ] && shown_r=zz
    [ "$left" = - ] && shown_l=?
    echo "$left $right $(date +%H:%M)" >"$LAST"

    for v in $left $right; do
        [ "$v" = - ] && continue
        [ "$v" -lt "$min" ] && min=$v
    done
    [ "$min" -lt "$LOW" ] && color=" | color=red"
    echo "⌨ ${shown_l}·${shown_r}${color}"

    # One notification per drop below LOW, again only after charging above it.
    if [ "$min" -lt "$LOW" ]; then
        if [ ! -f "$LOW_FLAG" ]; then
            osascript -e "display notification \"Left $left%, right $right%\" with title \"Corne battery low\"" 2>/dev/null
            touch "$LOW_FLAG"
        fi
    else
        rm -f "$LOW_FLAG"
    fi

    echo "---"
    echo "Left half: $([ "$left" = - ] && echo "no value" || echo "$left%")"
    echo "Right half: $([ "$right" = - ] && echo "asleep (a key press on it wakes it)" || echo "$right%")"
    echo "Updated $(date +%H:%M) | size=11"
    footer
}

reader_running() { pgrep -qf "corne-battery --watch"; }

start_reader() {
    reader_running && return 0
    # open's own stderr: "Unable to block on application" and similar, harmless.
    open -g -j -n --stdout "$FIFO" --stderr /dev/null "$APP" --args --watch 2>/dev/null
}

for f in "$APP" "$WATCH"; do
    if [ ! -e "$f" ]; then
        echo "⌨ ?"
        echo "---"
        echo "$(basename "$f") is missing: run scripts/swiftbar.sh install"
        exit 0
    fi
done

# CORNE_ONCE=1: print one menu and exit (scripts/swiftbar.sh show / status).
if [ -n "${CORNE_ONCE:-}" ]; then
    out="$(mktemp)"
    open -g -j -W -n --stdout "$out" --stderr "$out" "$APP" 2>/dev/null
    l="$(sed -n 's/^left half *: *\([0-9]*\)%.*/\1/p' "$out")"
    r="$(sed -n 's/^right half *: *\([0-9]*\)%.*/\1/p' "$out")"
    if [ -n "$l$r" ]; then
        levels "${l:--}" "${r:--}"
    elif grep -q "not connected" "$out"; then
        asleep
    else
        problem "$(cat "$out")"
    fi
    rm -f "$out"
    exit 0
fi

rm -f "$FIFO"
mkfifo "$FIFO"
exec 3<>"$FIFO"   # read end kept open: no EOF when a writer exits
cleanup() {
    pkill -f "corne-battery --watch" 2>/dev/null
    [ -n "${watch_pid:-}" ] && kill "$watch_pid" 2>/dev/null
    rm -f "$FIFO"
}
trap cleanup EXIT
trap 'exit 0' TERM INT

"$WATCH" "$TICK_S" "$ASLEEP_TICK_S" >"$FIFO" &
watch_pid=$!

first=1
redraw() { [ "$first" = 1 ] || echo "~~~"; first=0; }

while read -r event a b <&3; do
    case "$event" in
    connected) sleep "$SETTLE"; start_reader ;;
    tick) start_reader ;;
    disconnected) redraw; asleep ;;
    levels) redraw; levels "$a" "$b" ;;
    alive) ;;
    *) redraw; problem "$event $a $b" ;;
    esac
done
