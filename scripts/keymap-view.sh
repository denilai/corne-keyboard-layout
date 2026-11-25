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
    # With AeroSpace (tiling window manager) the window must stay floating on the
    # current workspace: put it there and give the focus back, otherwise AeroSpace
    # jumps to the workspace of the last active window when this one is empty.
    # The floating rule is in the dotfiles repo (.aerospace.toml); no AeroSpace: skip.
    AS="$(command -v aerospace || true)"
    [ -x /opt/homebrew/bin/aerospace ] && AS=/opt/homebrew/bin/aerospace
    focused_ws() { [ -n "$AS" ] && "$AS" list-workspaces --focused 2>/dev/null || true; }
    open_it() {
        local ws id="" i
        [ -x "$BIN" ] && [ ! "$SRC" -nt "$BIN" ] || build
        ws="$(focused_ws)"
        open -n "$APP" --args "$IMG"
        [ -n "$ws" ] || return 0
        for i in $(seq 1 30); do
            id="$("$AS" list-windows --monitor all --app-bundle-id local.corne.keymapview --format '%{window-id}' 2>/dev/null | head -1)"
            [ -n "$id" ] && break
            sleep 0.1
        done
        [ -n "$id" ] || return 0
        "$AS" move-node-to-workspace --window-id "$id" "$ws" >/dev/null 2>&1 || true
        "$AS" workspace "$ws" >/dev/null 2>&1 || true
        "$AS" focus --window-id "$id" >/dev/null 2>&1 || true
    }
    close_it() {
        local ws
        ws="$(focused_ws)"
        pkill -x KeymapView || true
        if [ -n "$ws" ]; then sleep 0.2; "$AS" workspace "$ws" >/dev/null 2>&1 || true; fi
    }
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
