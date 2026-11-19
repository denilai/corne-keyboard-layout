#!/usr/bin/env python3
"""Post-process the keymap-drawer SVG: combos only on Base, plus a legend.

    python3 scripts/keymap_legend.py img/keymap-img/corne.svg   # edits in place

keymap-drawer has no legend, and it draws every combo on every layer it is
active on, which hides the keys of Nav/Num/Utils. This script (stdlib only,
called by scripts/draw-keymap.sh) removes combos from the other layers and
appends a legend that explains the marks, symbols and behaviors, and
puts a white background under everything. The legend
text is below in SAMPLES / SYMBOLS / NOTES.
"""
import sys
import xml.etree.ElementTree as ET

SVG = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG)
ET.register_namespace("xlink", "http://www.w3.org/1999/xlink")
NS = f"{{{SVG}}}"

KEY = 52          # key size, as in keymap_drawer.config.yaml (key_w/h minus inner pad)
LINE = 15         # text line height in the legend
COL_W = 420       # width of a text column
PAD_X = 30        # left margin, as layer labels

# Sample keys: (tap, hold, shifted, extra classes, caption lines)
SAMPLES = [
    ("A", "⌃", "", "", ["tap: letter", "hold: modifier", "(pink, bottom)"]),
    (";", "", ":", "", ["top: with Shift,", "or the shortcut", "the key sends"]),
    ("⇧", "sticky", "", "", ["sticky: acts on", "the next key"]),
    ("⎵", "Nav", "", "layer", ["hold: layer", "while held"]),
    ("", "", "", "held", ["key that holds", "this layer"]),
    ("▽", "", "", "", ["transparent:", "as on Base"]),
    ("(", "", "", "combo", ["combo: press the", "two keys around", "it together"]),
]

SYMBOLS = [
    ("⌘", "Cmd (Ctrl in the Linux build)"),
    ("⌃", "Ctrl (Super in the Linux build)"),
    ("⎇", "Opt / Alt"),
    ("⇧", "Shift"),
    ("Hyper", "⌃⎇⇧⌘ at once: app launch shortcuts"),
    ("⎋", "Esc; with ⇧ or ⌘ held: ` ~"),
    ("⏎ ↹ ⎵", "Enter, Tab, Space"),
    ("⌫ ⌦", "Backspace, Delete (forward)"),
    ("⇪ LOCK", "Caps Lock, held 300 ms for macOS"),
    ("⇪ WORD", "Caps Word: capitals until a space"),
    ("☀↓ ☀↑", "display brightness"),
    ("⏮ ⏯ ⏭", "previous, play/pause, next"),
]

NOTES = [
    ("Home-row mods", "hold, then a key of the other hand"),
    ("", "(same hand: hold longer than 219 ms)"),
    ("Num Nav Utils", "layer is on while the key is held"),
    ("Combos", "keys together, within 30 ms; drawn"),
    ("", "on Base, also work on other layers"),
    ("", "except ⇪ LOCK, ⇪ WORD, VOL"),
    ("' / 2× ⌘⏎", "tap: ', double tap: ⌘⏎"),
    (", . ?", "keypad 1 2 3; Karabiner makes them"),
    ("", ", . ? in any input source"),
    ("Lock, Shot…", "top text: the shortcut it sends"),
    ("BT 0–4", "Bluetooth profile"),
    ("BT CLR", "forget the host of this profile"),
    ("UNLOCK", "unlock ZMK Studio"),
    ("Drawn", "macOS build (Linux: README)"),
]


def el(parent, tag, text=None, **attrs):
    e = ET.SubElement(parent, NS + tag, {k.replace("_", "-"): str(v) for k, v in attrs.items()})
    if text is not None:
        e.text = text
    return e


def drop_combos_off_base(root):
    for layer in root.iter(NS + "g"):
        cls = layer.get("class", "")
        if not cls.startswith("layer-") or cls == "layer-Base":
            continue
        for parent in layer.iter():
            for child in list(parent):
                if child.get("class", "").split()[:1] == ["combo"]:
                    parent.remove(child)


def sample_key(g, x, y, tap, hold, shifted, kind):
    k = el(g, "g", transform=f"translate({x}, {y})")
    if kind == "combo":
        el(k, "rect", rx=6, ry=6, x=-14, y=-13, width=28, height=26, **{"class": "combo"})
        el(k, "text", tap, x=0, y=0, **{"class": "combo tap"})
        return
    rect_cls = "key held" if kind == "held" else "key"
    el(k, "rect", rx=6, ry=6, x=-KEY // 2, y=-KEY // 2, width=KEY, height=KEY, **{"class": rect_cls})
    if tap:
        el(k, "text", tap, x=0, y=0, **{"class": "key tap"})
    if hold:
        hold_cls = "key hold layer-activator" if kind == "layer" else "key hold"
        el(k, "text", hold, x=0, y=24, **{"class": hold_cls})
    if shifted:
        el(k, "text", shifted, x=0, y=-24, **{"class": "key shifted"})


def text_lines(g, x, y, lines, **attrs):
    t = el(g, "text", x=x, y=y, **attrs)
    for i, line in enumerate(lines):
        el(t, "tspan", line, x=x, dy=0 if i == 0 else LINE)


def legend(root, top):
    g = el(root, "g", transform=f"translate({PAD_X}, {top})", **{"class": "legend"})
    el(g, "text", "Legend", x=0, y=28, id="Legend", **{"class": "label"})

    y = 56 + KEY // 2 + 4
    step = 120
    for i, (tap, hold, shifted, kind, caption) in enumerate(SAMPLES):
        cx = 30 + i * step
        sample_key(g, cx, y, tap, hold, shifted, kind)
        text_lines(g, cx, y + KEY // 2 + 18, caption, style="font-size: 11px")

    y += KEY // 2 + 18 + 3 * LINE + 24
    rows = max(len(SYMBOLS), len(NOTES))
    for col, items, key_w in ((0, SYMBOLS, 64), (1, NOTES, 112)):
        x = col * (COL_W + 20)
        for r, (k, v) in enumerate(items):
            ry = y + r * (LINE + 3)
            el(g, "text", k, x=x, y=ry, style="text-anchor: start; font-size: 12px; font-weight: bold")
            el(g, "text", v, x=x + key_w, y=ry, style="text-anchor: start; font-size: 12px")
    return y + rows * (LINE + 3) + 20


def main():
    path = sys.argv[1]
    tree = ET.parse(path)
    root = tree.getroot()
    drop_combos_off_base(root)
    w, h = int(float(root.get("width"))), int(float(root.get("height")))
    h += legend(root, h)
    # White background: the SVG is transparent, unreadable on dark pages.
    style_end = list(root).index(root.find(NS + "style")) + 1
    bg = ET.Element(NS + "rect", {"x": "0", "y": "0", "width": str(w), "height": str(h),
                                  "style": "fill: #fff; stroke: none"})
    root.insert(style_end, bg)
    root.set("height", str(h))
    root.set("viewBox", f"0 0 {w} {h}")
    tree.write(path, encoding="unicode", xml_declaration=False)
    with open(path, "a") as f:
        f.write("\n")


if __name__ == "__main__":
    main()
