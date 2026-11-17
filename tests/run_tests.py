#!/usr/bin/env python3
"""Keymap tests: simulate key presses on the real config/corne.keymap and
compare the HID reports ZMK sends with the expected ones.

How it works
------------
Each tests/cases/*.test is turned into a tiny ZMK config that #includes the
real keymap and replaces the key matrix with ZMK's mock kscan (a scripted
list of press/release events). It is compiled for the `native_sim` board, so
the firmware runs as a normal Linux process: no keyboard, no USB, no host OS
involved. The HID reports it logs are translated to key names and diffed
against the expected block of the case file.

Case file format (tests/cases/<name>.test)
------------------------------------------
    # comment
    press A          # key names come from POSITIONS below
    wait 300         # ms until the next event (default 10 ms)
    release A
    tap C            # = press C, 10 ms, release C
    ---
    press LGUI       # expected HID output: press/release <usage> [+MODS]
    press C
    release C
    release LGUI

Runs inside the zmk-build container (see scripts/zmk-docker.sh test).
Env: ACCEPT=1 overwrites the expected block with the actual output.
A case whose comments contain `@xfail` is a known issue: a mismatch is
reported as XFAIL and does not fail the run.
"""
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO = Path(os.environ.get("REPO", "/repo"))
WS = Path(os.environ.get("WS", "/ws"))
CASES = REPO / "tests" / "cases"
BUILD = WS / "build" / "tests"
KEYMAP = REPO / "config" / "corne.keymap"

# Physical key names by position (row-major, 12 per row, thumbs 36-41).
# Named after the base layer legends so cases read naturally.
POSITIONS = """
ESC  Q W E R T   Y U I O P LBKT
LCTL A S D F G   H J K L SEMI SQT
LSFT Z X C V B   N M COMMA DOT FSLH RSFT
T1 T2 T3   T4 T5 T6
""".split()
assert len(POSITIONS) == 42
COLS = 12
DEFAULT_GAP = 10
FINAL_GAP = 1000  # let hold-tap / combo / sticky timers expire before exit

MODS = ["LCTRL", "LSHIFT", "LALT", "LGUI", "RCTRL", "RSHIFT", "RALT", "RGUI"]


def _keyboard_names():
    n = {}
    for i, c in enumerate("ABCDEFGHIJKLMNOPQRSTUVWXYZ"):
        n[0x04 + i] = c
    for i, c in enumerate("1234567890"):
        n[0x1E + i] = "N" + c
    n.update({
        0x28: "RET", 0x29: "ESC", 0x2A: "BSPC", 0x2B: "TAB", 0x2C: "SPACE",
        0x2D: "MINUS", 0x2E: "EQUAL", 0x2F: "LBKT", 0x30: "RBKT",
        0x31: "BSLH", 0x33: "SEMI", 0x34: "SQT", 0x35: "GRAVE",
        0x36: "COMMA", 0x37: "DOT", 0x38: "FSLH", 0x39: "CAPS",
        0x46: "PSCRN", 0x4A: "HOME", 0x4B: "PG_UP", 0x4C: "DEL",
        0x4D: "END", 0x4E: "PG_DN", 0x4F: "RIGHT", 0x50: "LEFT",
        0x51: "DOWN", 0x52: "UP", 0x65: "K_APP", 0x67: "KP_EQUAL",
    })
    for i in range(12):
        n[0x3A + i] = f"F{i + 1}"
    for i, c in enumerate("1234567890"):
        n[0x59 + i] = "KP_N" + c
    for i, m in enumerate(MODS):
        n[0xE0 + i] = m
    return n


USAGE = {
    0x07: _keyboard_names(),
    0x0C: {0xE9: "C_VOL_UP", 0xEA: "C_VOL_DN", 0xE2: "C_MUTE",
           0xCD: "C_PP", 0xB5: "C_NEXT", 0xB6: "C_PREV"},
}

HID_RE = re.compile(r"hid_listener_keycode_(pressed|released): usage_page 0x(\w+) "
                    r"keycode 0x(\w+) implicit_mods 0x(\w+) explicit_mods 0x(\w+)")
MOUSE_RE = re.compile(r"zmk_hid_mouse_buttons?_\w+: Mouse buttons set to 0x(\w+)")


def mods_str(bits):
    return "+".join(m for i, m in enumerate(MODS) if bits >> i & 1)


def render(log):
    out = []
    for line in log.splitlines():
        if m := HID_RE.search(line):
            act, page, code, imp, exp = m.groups()
            page, code = int(page, 16), int(code, 16)
            name = USAGE.get(page, {}).get(code, f"0x{page:02X}:0x{code:02X}")
            mods = mods_str(int(imp, 16) | int(exp, 16))
            act = {"pressed": "press", "released": "release"}[act]
            out.append(f"{act} {name}" + (f" [{mods}]" if mods else ""))
        elif m := MOUSE_RE.search(line):
            out.append(f"mouse 0x{int(m.group(1), 16):02X}")
    return out


def parse_case(path):
    text = path.read_text()
    if "\n---" not in text:
        raise ValueError(f"{path.name}: no '---' separator")
    script, expected = text.split("\n---", 1)
    events = []  # [kind, position, gap]
    for n, raw in enumerate(script.splitlines(), 1):
        line = raw.split("#", 1)[0].split()
        if not line:
            continue
        op, *args = line
        if op == "wait":
            if not events:
                raise ValueError(f"{path.name}:{n}: wait before first event")
            events[-1][2] = int(args[0])
            continue
        if op not in ("press", "release", "tap") or len(args) != 1:
            raise ValueError(f"{path.name}:{n}: bad line: {raw!r}")
        if args[0] not in POSITIONS:
            raise ValueError(f"{path.name}:{n}: unknown key {args[0]!r}")
        pos = POSITIONS.index(args[0])
        if op == "tap":
            events += [["PRESS", pos, DEFAULT_GAP], ["RELEASE", pos, DEFAULT_GAP]]
        else:
            events.append([op.upper(), pos, DEFAULT_GAP])
    if not events:
        raise ValueError(f"{path.name}: no events")
    if events[-1][2] == DEFAULT_GAP:
        events[-1][2] = FINAL_GAP
    exp = [l.split("#", 1)[0].strip() for l in expected.splitlines()]
    return script, events, [l for l in exp if l]


def write_config(name, events):
    cfg = BUILD / name / "config"
    cfg.mkdir(parents=True, exist_ok=True)
    ev = "\n".join(f"        ZMK_MOCK_{k}({p // COLS},{p % COLS},{g})" for k, p, g in events)
    keymap = (f'#include "{KEYMAP}"\n\n'
              f"&kscan {{\n    rows = <4>;\n    columns = <{COLS}>;\n"
              f"    events = <\n{ev}\n    >;\n}};\n")
    # Write only on change so incremental builds stay fast.
    for fname, body in (("native_sim.keymap", keymap),
                        ("native_sim.conf", "CONFIG_ZMK_POINTING=y\n")):
        f = cfg / fname
        if not f.exists() or f.read_text() != body:
            f.write_text(body)
    return cfg


def run_case(path):
    name = path.stem
    try:
        script, events, expected = parse_case(path)
    except ValueError as e:
        return name, "ERROR", str(e)
    cfg = write_config(name, events)
    bdir = BUILD / name / "build"
    b = subprocess.run(
        ["west", "build", "-p", "auto", "-s", str(WS / "zmk" / "app"), "-d", str(bdir),
         "-b", "native_sim//zmk_test_mock", "--",
         "-DCONFIG_ASSERT=y", f"-DZMK_CONFIG={cfg}"],
        cwd=WS, capture_output=True, text=True)
    if b.returncode:
        return name, "BUILD", (b.stdout + b.stderr)[-4000:]
    r = subprocess.run([str(bdir / "zephyr" / "zmk.exe")], capture_output=True,
                       text=True, timeout=60)
    (BUILD / name / "full.log").write_text(r.stdout + r.stderr)
    actual = render(r.stdout + r.stderr)
    xfail = "@xfail" in script
    if actual == expected:
        return name, ("XPASS" if xfail else "PASS"), (
            "marked @xfail but passes now: remove the mark" if xfail else "")
    if os.environ.get("ACCEPT"):
        path.write_text(script + "\n---\n" + "\n".join(actual) + "\n")
        return name, "ACCEPTED", ""
    diff = ["   expected | actual"]
    for i in range(max(len(expected), len(actual))):
        e = expected[i] if i < len(expected) else ""
        a = actual[i] if i < len(actual) else ""
        diff.append(f"{'  ' if e == a else '>>'} {e:<24} | {a}")
    return name, ("XFAIL" if xfail else "FAIL"), "\n".join(diff) + f"\n   full log: {BUILD / name / 'full.log'}"


def main():
    names = sys.argv[1:]
    cases = sorted(CASES.glob("*.test"))
    if names:
        cases = [c for c in cases if any(n in c.stem for n in names)]
    if not cases:
        sys.exit("no test cases matched")
    with ThreadPoolExecutor(int(os.environ.get("J", os.cpu_count() or 4))) as pool:
        results = list(pool.map(run_case, cases))
    bad = 0
    for name, status, detail in results:
        print(f"{status:8} {name}")
        if status in ("FAIL", "BUILD", "ERROR"):
            bad += 1
        if detail:
            print("\n".join("         " + l for l in detail.splitlines()))
    print(f"\n{len(results) - bad}/{len(results)} passed")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
