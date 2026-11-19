#!/usr/bin/env bash
# Watch the Corne's Bluetooth connection to see deep sleep at work (macOS).
#
#   scripts/sleep-watch.sh [interval_s]   # default every 5 s, Ctrl+C to stop
#
# Prints a line with the time on each change: "connected" / "not connected".
# In the no-dongle setup the left half is the Bluetooth device: when it falls
# asleep it disconnects, a key press on it wakes it and it connects again.
# The right half sleeps on its own timer; its state is not visible here, check
# it by typing on it after the left one woke up.
#
# Test with a short timeout instead of 30 min:
#   scripts/zmk-docker.sh build --mode no-dongle --os mac \
#       --cmake-arg=-DCONFIG_ZMK_IDLE_SLEEP_TIMEOUT=60000
#   flash both halves, run this, keep hands off the keyboard for a minute.
#   Afterwards rebuild without --cmake-arg and flash again.
set -euo pipefail

[ "$(uname)" = Darwin ] || { echo "macOS only (Linux: bluetoothctl info <address>)" >&2; exit 1; }
interval="${1:-5}"

state() {
    system_profiler SPBluetoothDataType -json 2>/dev/null | python3 -c '
import json, sys
for ctrl in json.load(sys.stdin).get("SPBluetoothDataType", []):
    for key, devices in ctrl.items():
        if isinstance(devices, list) and any("corne" in n.lower() for d in devices for n in d):
            print("connected" if key == "device_connected" else "not connected")
            sys.exit()
print("not paired")
'
}

last="" since=$SECONDS
echo "watching every ${interval}s, Ctrl+C to stop"
while :; do
    now="$(state)"
    if [ "$now" != "$last" ]; then
        extra=""
        [ -n "$last" ] && extra=" (was $last for $((SECONDS - since)) s)"
        echo "$(date +%H:%M:%S) $now$extra"
        last="$now" since=$SECONDS
    fi
    sleep "$interval"
done
