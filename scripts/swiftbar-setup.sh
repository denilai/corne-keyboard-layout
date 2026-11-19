#!/usr/bin/env bash
# Corne battery in the macOS menu bar with SwiftBar.
#
#   scripts/swiftbar-setup.sh     # build CorneBattery.app, install the plugin, start SwiftBar
#
# 1. SwiftBar (brew cask, into ~/Applications: no sudo needed).
# 2. ~/Applications/CorneBattery.app: scripts/battery-mac.swift compiled into a
#    background app (no Dock icon) with its own Bluetooth permission. SwiftBar
#    has none, and a plugin it starts may not use Bluetooth. macOS asks once
#    to allow Bluetooth for "CorneBattery".
# 3. Plugin folder ~/.config/swiftbar (set for SwiftBar if it has none yet),
#    with a link to macos/swiftbar/corne-battery.5m.sh: edits in the repo
#    apply on the next refresh.
#
# Run it again after changing battery-mac.swift.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$HOME/Applications/CorneBattery.app"
PLUGIN="$REPO/macos/swiftbar/corne-battery.5m.sh"
DOMAIN=com.ameba.SwiftBar

[ "$(uname)" = Darwin ] || { echo "macOS only" >&2; exit 1; }

# 1. SwiftBar
if [ ! -d "$HOME/Applications/SwiftBar.app" ] && [ ! -d /Applications/SwiftBar.app ]; then
    brew install --cask --appdir="$HOME/Applications" swiftbar
fi

# 2. CorneBattery.app
mkdir -p "$APP/Contents/MacOS"
cat >"$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.corne.battery</string>
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
codesign --force --sign - "$APP"
echo "built $APP"

# 3. Plugin
dir="$(defaults read "$DOMAIN" PluginDirectory 2>/dev/null || true)"
if [ -z "$dir" ]; then
    dir="$HOME/.config/swiftbar"
    defaults write "$DOMAIN" PluginDirectory -string "$dir"
fi
mkdir -p "$dir"
ln -sfn "$PLUGIN" "$dir/$(basename "$PLUGIN")"
echo "plugin: $dir/$(basename "$PLUGIN") -> $PLUGIN"

open -g -a SwiftBar
echo "SwiftBar is running: the menu bar shows ⌨ <left>·<right>."
echo "Refresh from its menu; first time macOS asks to allow Bluetooth for CorneBattery."
