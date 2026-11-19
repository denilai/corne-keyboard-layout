#!/usr/bin/env bash
# Show or hide the keymap picture (img/keymap-img/corne.svg).
#
#   scripts/keymap-view.sh [toggle]   # open it, or close it if it is open
#   scripts/keymap-view.sh open|close
#   scripts/keymap-view.sh build      # macOS: (re)build KeymapView.app
#
# The keyboard runs it with the combo of the outer middle-row keys, which
# sends F19:
#   macOS: Karabiner rule "Corne: F19 = show / hide the keymap"
#          (macos/karabiner/corne-keymap-view.json, scripts/karabiner-setup.sh)
#   GNOME: Settings → Keyboard → Custom Shortcuts → command
#          "<repo>/scripts/keymap-view.sh", shortcut: press the combo (F19)
# macOS shows it in KeymapView.app (scripts/keymap-view.swift, built here on
# first use into ~/Applications): started with `open`, so it comes to the
# front with focus; Esc, Cmd+W or the combo again closes it. Linux: the GNOME
# image viewer (Loupe or eog).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMG="$REPO/img/keymap-img/corne.svg"
action="${1:-toggle}"

case "$(uname)" in
Darwin)
    APP="$HOME/Applications/KeymapView.app"
    BIN="$APP/Contents/MacOS/KeymapView"
    SRC="$REPO/scripts/keymap-view.swift"
    build() {
        mkdir -p "$APP/Contents/MacOS"
        cat >"$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.corne.keymapview</string>
    <key>CFBundleName</key><string>KeymapView</string>
    <key>CFBundleExecutable</key><string>KeymapView</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
        swiftc -O "$SRC" -o "$BIN"
        codesign --force --sign - "$APP" 2>/dev/null
    }
    is_open() { pgrep -x KeymapView >/dev/null; }
    open_it() {
        [ -x "$BIN" ] && [ ! "$SRC" -nt "$BIN" ] || build
        open -n "$APP" --args "$IMG"
    }
    close_it() { pkill -x KeymapView || true; }
    ;;
Linux)
    viewer="$(command -v loupe || command -v eog || true)"
    [ -n "$viewer" ] || { echo "no image viewer (loupe or eog)" >&2; exit 1; }
    pattern="$(basename "$viewer") $IMG"
    is_open() { pgrep -f "$pattern" >/dev/null; }
    open_it() { nohup "$viewer" "$IMG" >/dev/null 2>&1 & }
    close_it() { pkill -f "$pattern" || true; }
    ;;
*)
    echo "unsupported OS" >&2
    exit 1
    ;;
esac

case "$action" in
toggle) if is_open; then close_it; else open_it; fi ;;
open) is_open || open_it ;;
close) close_it ;;
build) [ "$(uname)" = Darwin ] && build ;;
*) sed -n '2,15p' "$0"; exit 2 ;;
esac
