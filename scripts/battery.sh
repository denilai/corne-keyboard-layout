#!/usr/bin/env bash
# Battery level of the Corne as the computer sees it (macOS and Linux).
#
#   scripts/battery.sh
#
# The central reports its own level and, with
# CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_PROXY (config/corne.conf), the
# level of each peripheral as an extra Battery Service. Whether the OS shows
# them depends on the OS: this prints everything it exposes for "Corne".
# With the dongle, the dongle is the central and is on USB: there is no
# Bluetooth device to read, use ZMK Studio or a host tool instead.
set -euo pipefail

case "$(uname)" in
Darwin)
    system_profiler SPBluetoothDataType -json 2>/dev/null | python3 -c '
import json, sys
found = False
for ctrl in json.load(sys.stdin).get("SPBluetoothDataType", []):
    for state, devices in ctrl.items():
        if not isinstance(devices, list):
            continue
        for d in devices:
            for name, info in d.items():
                if "corne" not in name.lower():
                    continue
                found = True
                levels = {k: v for k, v in info.items() if "battery" in k.lower()}
                where = state.replace("device_", "")
                print(f"{name} ({where}):",
                      ", ".join(f"{k}: {v}" for k, v in levels.items()) or "no battery level reported")
if not found:
    print("Corne is not among Bluetooth devices (dongle on USB, or not paired)")
'
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
