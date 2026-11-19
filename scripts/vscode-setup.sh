#!/usr/bin/env bash
# Add the keybindings from macos/vscode/keybindings.json to VS Code and Cursor.
#
#   scripts/vscode-setup.sh          # add the missing ones, backup first
#   scripts/vscode-setup.sh --diff   # show what would change, write nothing
#
# Now: in the integrated terminal Cmd+C sends Ctrl+C (SIGINT) when nothing is
# selected and copies when text is selected; the editor copies as usual.
# Only VS Code knows the focus and the selection, so this cannot be a
# Karabiner rule (Karabiner sees only the frontmost app).
#
# The user keybindings.json (~/Library/Application Support/<app>/User/) is
# JSON with comments: entries are appended before the closing "]", nothing
# else is changed. An entry counts as present when an entry with the same
# key, command and "when" is already there. Backup:
# keybindings.json.bak-<date> next to it.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO/macos/vscode/keybindings.json"
mode="${1:-apply}"

for app in Code Cursor; do
    f="$HOME/Library/Application Support/$app/User/keybindings.json"
    [ -d "$(dirname "$f")" ] || { echo "$app: not installed, skipped"; continue; }
    [ -f "$f" ] || echo '[]' >"$f"
    python3 - "$SRC" "$f" "$mode" "$app" <<'PY'
import json, re, shutil, sys, time
src, dst, mode, app = sys.argv[1:]
want = json.load(open(src))
text = open(dst).read()

def strip_comments(t):
    # drop // and /* */ outside strings, then trailing commas
    out, i, n, in_str = [], 0, len(t), False
    while i < n:
        c = t[i]
        if in_str:
            out.append(c)
            if c == "\\":
                out.append(t[i + 1]); i += 2; continue
            if c == '"': in_str = False
        elif c == '"':
            in_str = True; out.append(c)
        elif t.startswith("//", i):
            i = t.find("\n", i); i = n if i < 0 else i; continue
        elif t.startswith("/*", i):
            i = t.find("*/", i) + 2; continue
        else:
            out.append(c)
        i += 1
    return re.sub(r",(\s*[\]}])", r"\1", "".join(out))

have = json.loads(strip_comments(text) or "[]")
ident = lambda e: (e.get("key"), e.get("command"), e.get("when"))
missing = [e for e in want if ident(e) not in {ident(h) for h in have}]
if not missing:
    print(f"{app}: up to date"); sys.exit()
block = ",\n".join("    " + json.dumps(e, indent=4, ensure_ascii=True).replace("\n", "\n    ") for e in missing)
end = text.rstrip().rfind("]")
head = text[:end].rstrip()
sep = "," if head and head[-1] not in "[," else ""
new = head + sep + "\n" + block + "\n]\n"
if mode == "--diff":
    print(f"{app}: would add\n{block}"); sys.exit()
shutil.copy(dst, dst + ".bak-" + time.strftime("%Y%m%d-%H%M%S"))
open(dst, "w").write(new)
print(f"{app}: added {len(missing)} keybinding(s)")
PY
done
