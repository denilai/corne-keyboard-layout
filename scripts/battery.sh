#!/usr/bin/env bash
# Battery levels of both halves, as the Corne reports them over Bluetooth.
#
#   scripts/battery.sh
#
# Works in the no-dongle setup: the left half (central) is a Bluetooth device
# of the computer and sends its own level and the right half's one
# (CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_FETCHING / _PROXY in
# config/corne.conf). With the dongle, the dongle is on USB: nothing to read.
#
# macOS ignores the Bluetooth Battery Service of keyboards (Settings and
# system_profiler show nothing), so on macOS the levels are read directly with
# CoreBluetooth: scripts/battery-mac.swift. The first run asks for Bluetooth
# access for the terminal app. Linux: upower reads the service itself.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$(uname)" in
Darwin)
    exec swift "$REPO/scripts/battery-mac.swift"
    ;;
Linux)
    upower -e | grep -i -E 'keyboard|battery_hid' | while read -r dev; do
        upower -i "$dev" | grep -E 'model|percentage' | paste -sd' ' -
    done
    ;;
*)
    echo "unsupported OS" >&2
    exit 1
    ;;
esac
