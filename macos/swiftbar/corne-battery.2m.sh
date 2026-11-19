#!/usr/bin/env bash
# <xbar.title>Corne battery</xbar.title>
# <xbar.desc>Battery of both Corne halves (no-dongle setup), read over Bluetooth.</xbar.desc>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
#
# SwiftBar plugin, refreshed every 2 minutes (".2m" in the file name). Reading the battery
# does not count as key activity: it does not keep the halves from sleeping,
# and a sleeping left half is just shown as not connected.
# Installed by scripts/swiftbar.sh install as a link from the plugin folder.
#
# SwiftBar runs plugins as its child processes and has no Bluetooth
# permission, so the reader (scripts/battery-mac.swift) is built into its own
# small app, CorneBattery.app, with its own permission. `open` starts it as a
# separate app and takes its output through a file.
#
# Output format (SwiftBar): first line is the menu bar title, after "---" the
# dropdown; "| key=value" sets color, actions etc.
set -uo pipefail

APP="$HOME/Applications/CorneBattery.app"
LOW=20   # % for the red title and a notification
STATE="${SWIFTBAR_PLUGIN_DATA_PATH:-${TMPDIR:-/tmp}}/corne-battery-low"

out="$(mktemp)"
trap 'rm -f "$out"' EXIT

if [ ! -d "$APP" ]; then
    echo "⌨ ?"
    echo "---"
    echo "CorneBattery.app is missing: run scripts/swiftbar.sh install"
    exit 0
fi

open -g -j -W -n --stdout "$out" --stderr "$out" "$APP"

left="$(sed -n 's/^left half *: *\([0-9]*\)%.*/\1/p' "$out")"
right="$(sed -n 's/^right half *: *\([0-9]*\)%.*/\1/p' "$out")"

if [ -z "$left$right" ]; then
    echo "⌨ –"
    echo "---"
    sed 's/|/¦/g' "$out"   # the reason, e.g. "not connected" ("|" would be parsed)
    echo "Refresh | refresh=true"
    exit 0
fi

min=100
for v in $left $right; do [ "$v" -lt "$min" ] && min=$v; done
color=""
[ "$min" -lt "$LOW" ] && color=" | color=red"
echo "⌨ ${left:-?}·${right:-?}${color}"

# One notification per drop below LOW, again only after charging above it.
if [ "$min" -lt "$LOW" ]; then
    if [ ! -f "$STATE" ]; then
        osascript -e "display notification \"Left ${left:-?}%, right ${right:-?}%\" with title \"Corne battery low\"" 2>/dev/null
        mkdir -p "$(dirname "$STATE")" && touch "$STATE"
    fi
else
    rm -f "$STATE"
fi

echo "---"
echo "Left half: ${left:-?}%"
echo "Right half: ${right:-?}%"
echo "Updated $(date +%H:%M) | size=11"
echo "---"
echo "Refresh | refresh=true"
echo "Bluetooth settings | href=x-apple.systempreferences:com.apple.BluetoothSettings"
