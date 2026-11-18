#!/usr/bin/env bash
# Configure Karabiner-Elements (macOS) for the Corne from files in this repo.
#
#   scripts/karabiner-setup.sh           # apply to ~/.config/karabiner/karabiner.json and start Karabiner
#   scripts/karabiner-setup.sh --diff    # show what would change, write nothing
#
# Karabiner is configured by one file, ~/.config/karabiner/karabiner.json.
# It watches the file and reloads it on save: no restart needed. The settings
# window edits the same file. This script changes only the parts below, in the
# selected profile, and leaves everything else as is (backup goes to
# ~/.config/karabiner/automatic_backups/ before writing):
#
#   - devices: Corne is modified, the built-in keyboard is ignored. Karabiner
#     sends all keys of grabbed keyboards through one virtual keyboard of one
#     type (ANSI/ISO), so it should grab only the Corne.
#   - virtual_hid_keyboard.keyboard_type_v2 = ansi: the Corne sends ANSI codes.
#     With "iso" macOS swaps ` ~ and § ± on the Corne.
#   - Corne fn_function_keys: F1..F12 stay F-keys (Karabiner maps them to
#     brightness/volume by default).
#   - Corne simple_modifications: Control <-> Command, left and right. macOS
#     "Modifier Keys" settings do not apply to a device Karabiner grabs (the
#     events come from its virtual keyboard), so the swap set there for the
#     Corne is repeated here.
#   - complex_modifications: rules whose description starts with "Corne:" are
#     replaced with the ones from macos/karabiner/*.json (the punctuation rule).
#     The rule files are also copied to assets/complex_modifications, where the
#     settings window lists them under "Add predefined rule".
#
# To change the characters: edit macos/karabiner/corne-punctuation.json
# (key names: Karabiner-EventViewer, or
# https://karabiner-elements.pqrs.org/docs/json/) and run the script again.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RULES_DIR="$REPO/macos/karabiner"
KDIR="$HOME/.config/karabiner"
CONFIG="$KDIR/karabiner.json"
CLI="/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"
mode="${1:-apply}"

[ -x "$CLI" ] || { echo "Karabiner-Elements is not installed" >&2; exit 1; }
"$CLI" --lint-complex-modifications "$RULES_DIR"/*.json

new="$(mktemp)"
trap 'rm -f "$new"' EXIT
[ -f "$CONFIG" ] || echo '{"profiles":[{"name":"Default profile","selected":true}]}' >"$CONFIG"

python3 - "$CONFIG" "$new" "$RULES_DIR"/*.json <<'PY'
import json, sys
src, dst, *rule_files = sys.argv[1:]
cfg = json.load(open(src))

CORNE = {"is_keyboard": True, "is_pointing_device": True, "vendor_id": 7504, "product_id": 24926}
BUILT_IN = {"is_keyboard": True, "vendor_id": 0, "product_id": 0}

profile = next((p for p in cfg["profiles"] if p.get("selected")), cfg["profiles"][0])
profile.setdefault("virtual_hid_keyboard", {})["keyboard_type_v2"] = "ansi"

ours = [CORNE, BUILT_IN]
devices = [d for d in profile.get("devices", []) if d.get("identifiers") not in ours]
swap = [("left_control", "left_command"), ("right_control", "right_command")]
devices.append({
    "identifiers": CORNE,
    "ignore": False,
    "simple_modifications": [
        {"from": {"key_code": a}, "to": [{"key_code": b}]} for x, y in swap for a, b in ((x, y), (y, x))
    ],
    "fn_function_keys": [
        {"from": {"key_code": f"f{i}"}, "to": [{"key_code": f"f{i}"}]} for i in range(1, 13)
    ],
})
devices.append({"identifiers": BUILT_IN, "ignore": True})
profile["devices"] = devices

cm = profile.setdefault("complex_modifications", {})
rules = [r for r in cm.get("rules", []) if not r.get("description", "").startswith("Corne:")]
for f in rule_files:
    rules += json.load(open(f))["rules"]
cm["rules"] = rules

json.dump(cfg, open(dst, "w"), indent=4, ensure_ascii=False)
PY

if [ "$mode" = "--diff" ]; then
    diff -u "$CONFIG" "$new" || true
    exit 0
fi

if cmp -s "$CONFIG" "$new"; then
    echo "karabiner.json is up to date"
else
    mkdir -p "$KDIR/automatic_backups"
    cp "$CONFIG" "$KDIR/automatic_backups/karabiner_$(date +%Y%m%d-%H%M%S)-corne.json"
    cat "$new" >"$CONFIG"   # keep the inode and permissions Karabiner watches
    echo "updated $CONFIG"
fi

mkdir -p "$KDIR/assets/complex_modifications"
cp "$RULES_DIR"/*.json "$KDIR/assets/complex_modifications/"

open -g -a Karabiner-Elements
echo "Karabiner-Elements is running. Check Settings → Devices: only Corne is modified."
