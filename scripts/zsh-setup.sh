#!/usr/bin/env bash
# Shift+arrows select text in the zsh command line: zsh-shift-select.
#
#   scripts/zsh-setup.sh          # install / update the plugin, add it to ~/.zshrc
#   scripts/zsh-setup.sh --diff   # show what would be added to ~/.zshrc
#
# Terminals send Shift+← as "ESC [1;2D"; plain zsh has nothing bound to it and
# prints ";2D" or runs other line-editor commands. The plugin
# (https://github.com/jirutka/zsh-shift-select, MIT, ~100 lines of zle
# widgets, no network) binds the Shift keys and selects as in an editor:
#   Shift+← → ↑ ↓          select by character / line
#   Shift+Home / End       select to the start / end of the line
#   Shift+Opt+← →          select by word (macOS; Shift+Ctrl on Linux)
#   Backspace / Delete     delete the selection; typing replaces it
#   any other key          drops the selection
# Opt+W copies the selection to the zsh kill buffer, Ctrl+Y pastes it.
#
# The plugin needs the emacs keymap: with EDITOR=vim zsh may start in vi mode,
# so the block sets `bindkey -e` first. The plugin is pinned to COMMIT and
# cloned into ~/.local/share/zsh-shift-select; ~/.zshrc gets a marked block
# (backup first), re-running the script changes nothing.
set -euo pipefail

URL=https://github.com/jirutka/zsh-shift-select.git
COMMIT=3f45aaf    # 2026-10-20, v0.1.1; reviewed
DIR="$HOME/.local/share/zsh-shift-select"
RC="$HOME/.zshrc"
BEGIN="# >>> zsh-shift-select (corne-keyboard-layout/scripts/zsh-setup.sh) >>>"
END="# <<< zsh-shift-select <<<"
BLOCK="$BEGIN
# Shift+arrows select text in the command line (emacs keymap needed).
bindkey -e
source \"$DIR/zsh-shift-select.plugin.zsh\"
$END"

if [ "${1:-}" = --diff ]; then
    grep -qF "$BEGIN" "$RC" 2>/dev/null && echo "~/.zshrc: block present" || printf '~/.zshrc would get:\n%s\n' "$BLOCK"
    exit 0
fi

if [ -d "$DIR/.git" ]; then
    git -C "$DIR" fetch -q origin
else
    git clone -q "$URL" "$DIR"
fi
git -C "$DIR" -c advice.detachedHead=false checkout -q "$COMMIT"
echo "plugin: $DIR at $(git -C "$DIR" log -1 --format='%h %cs')"

if grep -qF "$BEGIN" "$RC" 2>/dev/null; then
    echo "~/.zshrc: block present"
else
    cp "$RC" "$RC.bak-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
    printf '\n%s\n' "$BLOCK" >>"$RC"
    echo "~/.zshrc: block added (backup next to it); open a new terminal"
fi
