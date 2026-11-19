#!/usr/bin/env bash
# Show or hide the keymap picture (img/keymap-img/corne.svg).
#
#   scripts/keymap-view.sh [toggle]   # open it, or close it if it is open
#   scripts/keymap-view.sh open|close
#
# The keyboard runs it with the combo of the outer middle-row keys, which
# sends F19:
#   macOS: Karabiner rule "Corne: F19 = show / hide the keymap"
#          (macos/karabiner/corne-keymap-view.json, scripts/karabiner-setup.sh)
#   GNOME: Settings → Keyboard → Custom Shortcuts → command
#          "<repo>/scripts/keymap-view.sh", shortcut: press the combo (F19)
# macOS shows it in Quick Look (Esc or the combo again closes it), Linux in
# the GNOME image viewer (eog, or Loupe on newer GNOME).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMG="$REPO/img/keymap-img/corne.svg"
action="${1:-toggle}"

case "$(uname)" in
Darwin)
    pattern="qlmanage -p $IMG"
    is_open() { pgrep -f "$pattern" >/dev/null; }
    open_it() { nohup qlmanage -p "$IMG" >/dev/null 2>&1 & }
    close_it() { pkill -f "$pattern" || true; }
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
*) sed -n '2,15p' "$0"; exit 2 ;;
esac
