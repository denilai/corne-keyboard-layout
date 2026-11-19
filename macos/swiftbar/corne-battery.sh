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
# When to read the battery: corne-watch (scripts/corne-watch.swift) reports
# IOKit events, so the menu follows the keyboard at once:
#   connected      the left half woke up / connected: read after SETTLE s
#   disconnected   it fell asleep or went away: show "asleep", no reading
#   tick           every CONNECTED_S while connected, ASLEEP_S while not
# Reading does not count as key activity, it does not keep the halves awake.
#
# SwiftBar has no Bluetooth permission, so the reader (scripts/battery-mac.swift)
# is built into its own app, CorneBattery.app; `open` starts it and its output
# comes back through a file.
#
# Menu format: first line is the menu bar title, after "---" the dropdown;
# "| key=value" sets color, actions etc.
set -uo pipefail

APP="$HOME/Applications/CorneBattery.app"
WATCH="$HOME/Library/Application Support/CorneBattery/corne-watch"
LOW=20          # % for the red title and a notification
SETTLE=5        # s after connecting before reading: services and the right half
CONNECTED_S=120
ASLEEP_S=300
DATA="${SWIFTBAR_PLUGIN_DATA_PATH:-${TMPDIR:-/tmp}/corne-battery}"
mkdir -p "$DATA"
LOW_FLAG="$DATA/low"   # a notification was sent for the current drop
LAST="$DATA/last"      # "left right HH:MM" of the last read

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

read_battery() {
    local out left right min color
    out="$(mktemp)"
    # open's own stderr: "Unable to block on application" when the reader exits
    # before open has its pid (keyboard not connected), harmless.
    open -g -j -W -n --stdout "$out" --stderr "$out" "$APP" 2>/dev/null
    left="$(sed -n 's/^left half *: *\([0-9]*\)%.*/\1/p' "$out")"
    right="$(sed -n 's/^right half *: *\([0-9]*\)%.*/\1/p' "$out")"

    if [ -z "$left$right" ] && grep -q "not connected" "$out"; then
        rm -f "$out"
        asleep
        return
    fi
    if [ -z "$left$right" ]; then
        echo "⌨ –"
        echo "---"
        sed 's/|/¦/g' "$out"   # the reason ("|" would be parsed by SwiftBar)
        last_line
        footer
        rm -f "$out"
        return
    fi
    rm -f "$out"
    echo "${left:-?} ${right:-?} $(date +%H:%M)" >"$LAST"

    min=100
    for v in $left $right; do [ "$v" -lt "$min" ] && min=$v; done
    color=""
    [ "$min" -lt "$LOW" ] && color=" | color=red"
    echo "⌨ ${left:-?}·${right:-?}${color}"

    # One notification per drop below LOW, again only after charging above it.
    if [ "$min" -lt "$LOW" ]; then
        if [ ! -f "$LOW_FLAG" ]; then
            osascript -e "display notification \"Left ${left:-?}%, right ${right:-?}%\" with title \"Corne battery low\"" 2>/dev/null
            touch "$LOW_FLAG"
        fi
    else
        rm -f "$LOW_FLAG"
    fi

    echo "---"
    echo "Left half: ${left:-?}%"
    echo "Right half: ${right:-?}%"
    echo "Updated $(date +%H:%M) | size=11"
    footer
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
    read_battery
    exit 0
fi

first=1
"$WATCH" "$CONNECTED_S" "$ASLEEP_S" | while read -r event; do
    [ "$first" = 1 ] || echo "~~~"
    first=0
    case "$event" in
    connected) sleep "$SETTLE"; read_battery ;;
    tick) read_battery ;;
    disconnected) asleep ;;
    esac
done
