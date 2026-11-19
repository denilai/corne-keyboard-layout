#!/usr/bin/env bash
# Corne battery in the macOS menu bar with SwiftBar: install and maintain.
#
#   scripts/swiftbar.sh install     # SwiftBar + CorneBattery.app + plugin link, start SwiftBar
#   scripts/swiftbar.sh status      # what is installed, running, allowed, connected
#   scripts/swiftbar.sh show        # run the plugin here: prints what the menu bar shows
#   scripts/swiftbar.sh refresh     # refresh the menu bar item now
#   scripts/swiftbar.sh rebuild     # rebuild CorneBattery.app (after editing battery-mac.swift)
#   scripts/swiftbar.sh start|stop  # start / quit SwiftBar
#   scripts/swiftbar.sh uninstall [--all]
#                                   # remove the plugin link, CorneBattery.app and its
#                                   # Bluetooth permission; --all also SwiftBar and its settings
#
# Parts:
#   ~/Applications/SwiftBar.app     brew cask, in ~/Applications: no sudo
#   ~/Applications/CorneBattery.app scripts/battery-mac.swift as a background app
#                                   with its own Bluetooth permission (SwiftBar has
#                                   none, a plugin it starts may not use Bluetooth)
#   ~/.config/swiftbar/             plugin folder, link to macos/swiftbar/corne-battery.2m.sh
#                                   (edits of the plugin apply on the next refresh)
# Start at login: SwiftBar → Preferences → "Launch at Login" (not set by this script).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPS="$HOME/Applications"
APP="$APPS/CorneBattery.app"
BUNDLE_ID=local.corne.battery
PLUGIN="$REPO/macos/swiftbar/corne-battery.2m.sh"
NAME=corne-battery            # plugin name for swiftbar:// URLs
DOMAIN=com.ameba.SwiftBar

[ "$(uname)" = Darwin ] || { echo "macOS only" >&2; exit 1; }

b=$'\e[1m' g=$'\e[32m' r=$'\e[31m' n=$'\e[0m'
ok() { printf '%s\n' "${g}✔${n} $*"; }
bad() { printf '%s\n' "${r}✘${n} $*"; }

swiftbar_app() {
    for d in "$APPS/SwiftBar.app" /Applications/SwiftBar.app; do
        [ -d "$d" ] && { echo "$d"; return 0; }
    done
    return 1
}

plugin_dir() {
    defaults read "$DOMAIN" PluginDirectory 2>/dev/null || true
}

running() { pgrep -qx SwiftBar; }

build_app() {
    mkdir -p "$APP/Contents/MacOS"
    cat >"$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>CorneBattery</string>
    <key>CFBundleExecutable</key><string>corne-battery</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSUIElement</key><true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Reads the battery level of the Corne keyboard halves.</string>
</dict>
</plist>
PLIST
    swiftc -O "$REPO/scripts/battery-mac.swift" -o "$APP/Contents/MacOS/corne-battery"
    codesign --force --sign - "$APP" 2>/dev/null
    ok "built $APP"
}

refresh() {
    running && open -g "swiftbar://refreshplugin?name=$NAME"
}

cmd="${1:-}"; shift || true
case "$cmd" in
install)
    if swiftbar_app >/dev/null; then
        ok "SwiftBar: $(swiftbar_app)"
    else
        brew install --cask --appdir="$APPS" swiftbar
    fi
    build_app
    dir="$(plugin_dir)"
    if [ -z "$dir" ]; then
        dir="$HOME/.config/swiftbar"
        defaults write "$DOMAIN" PluginDirectory -string "$dir"
    fi
    mkdir -p "$dir"
    ln -sfn "$PLUGIN" "$dir/$(basename "$PLUGIN")"
    ok "plugin: $dir/$(basename "$PLUGIN") -> $PLUGIN"
    open -g -a "$(swiftbar_app)"
    refresh || true
    echo
    echo "${b}Menu bar: ⌨ <left>·<right>.${n} Left to do by hand:"
    echo "  - allow Bluetooth for CorneBattery when macOS asks"
    echo "  - SwiftBar → Preferences → Launch at Login"
    ;;
rebuild)
    build_app
    refresh || true
    ;;
refresh)
    running || { bad "SwiftBar is not running: scripts/swiftbar.sh start"; exit 1; }
    refresh
    ok "refresh sent"
    ;;
show)
    "$PLUGIN"
    ;;
start)
    open -g -a "$(swiftbar_app)"
    ok "SwiftBar started"
    ;;
stop)
    osascript -e 'quit app "SwiftBar"' 2>/dev/null || true
    ok "SwiftBar quit"
    ;;
status)
    if app="$(swiftbar_app)"; then ok "SwiftBar installed: $app"; else bad "SwiftBar not installed: scripts/swiftbar.sh install"; fi
    if running; then ok "SwiftBar running"; else bad "SwiftBar not running: scripts/swiftbar.sh start"; fi
    dir="$(plugin_dir)"
    link="$dir/$(basename "$PLUGIN")"
    if [ -n "$dir" ] && [ "$(readlink "$link" 2>/dev/null)" = "$PLUGIN" ]; then
        ok "plugin linked: $link"
    else
        bad "plugin not linked (plugin folder: ${dir:-not set}): scripts/swiftbar.sh install"
    fi
    if [ -x "$APP/Contents/MacOS/corne-battery" ]; then
        if [ "$REPO/scripts/battery-mac.swift" -nt "$APP/Contents/MacOS/corne-battery" ]; then
            bad "CorneBattery.app is older than battery-mac.swift: scripts/swiftbar.sh rebuild"
        else
            ok "CorneBattery.app built"
        fi
    else
        bad "CorneBattery.app missing: scripts/swiftbar.sh install"
    fi
    if tccutil list -b "$BUNDLE_ID" 2>/dev/null | grep -qx BluetoothAlways; then
        ok "Bluetooth allowed for CorneBattery"
    else
        bad "Bluetooth not allowed for CorneBattery yet (asked on first read; or Privacy & Security → Bluetooth)"
    fi
    echo "${b}Plugin output:${n}"
    "$PLUGIN" | sed 's/^/  /'
    ;;
uninstall)
    dir="$(plugin_dir)"
    [ -n "$dir" ] && rm -f "$dir/$(basename "$PLUGIN")"
    rm -rf "$APP"
    tccutil reset BluetoothAlways "$BUNDLE_ID" >/dev/null 2>&1 || true
    ok "removed the plugin link, CorneBattery.app and its Bluetooth permission"
    if [ "${1:-}" = --all ]; then
        osascript -e 'quit app "SwiftBar"' 2>/dev/null || true
        brew uninstall --cask swiftbar || true
        defaults delete "$DOMAIN" 2>/dev/null || true
        ok "removed SwiftBar and its settings"
    else
        refresh || true
    fi
    ;;
*)
    sed -n '2,13p' "$0"
    exit 2
    ;;
esac
