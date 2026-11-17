#!/usr/bin/env python3
"""Read the keymap from the keyboard over the ZMK Studio protocol (read-only).

Checks that the flashed central (dongle or left half) answers Studio RPC and
prints what it reports: device name, physical layout, layers and bindings.

    scripts/studio_check.py                     # auto-detect port, print keymap
    scripts/studio_check.py --save FILE         # also save the dump
    scripts/studio_check.py --check FILE        # diff against a saved dump
    scripts/studio_check.py --port /dev/ttyACM0

Keymap reads need the Studio lock open: press &studio_unlock
(Utils layer: hold the BSPC thumb, then the top-right key). The script waits.

Requires pyserial. Protocol: protobuf messages from zmk-studio-messages,
framed with SOF 0xAB / ESC 0xAC / EOF 0xAD.
"""
import argparse
import glob
import sys
import time

import serial

SOF, ESC, EOF = 0xAB, 0xAC, 0xAD
EXPECTED_LAYERS = ["Base", "Nav", "Num", "Utils"]
EXPECTED_KEYS = 42

# ---------------------------------------------------------------- protobuf --


def varint(n):
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        out.append(b | (0x80 if n else 0))
        if not n:
            return bytes(out)


def field(num, value):
    """Encode a field: int -> varint, bytes -> length-delimited."""
    if isinstance(value, int):
        return varint(num << 3) + varint(value)
    return varint(num << 3 | 2) + varint(len(value)) + value


def decode(buf):
    """Generic decode: {field_number: [values]}; values are int or bytes."""
    out, i = {}, 0
    while i < len(buf):
        key, i = _read_varint(buf, i)
        num, wt = key >> 3, key & 7
        if wt == 0:
            val, i = _read_varint(buf, i)
        elif wt == 2:
            ln, i = _read_varint(buf, i)
            val, i = bytes(buf[i:i + ln]), i + ln
        elif wt == 5:
            val, i = int.from_bytes(buf[i:i + 4], "little"), i + 4
        elif wt == 1:
            val, i = int.from_bytes(buf[i:i + 8], "little"), i + 8
        else:
            raise ValueError(f"wire type {wt}")
        out.setdefault(num, []).append(val)
    return out


def _read_varint(buf, i):
    n = shift = 0
    while True:
        b = buf[i]
        i += 1
        n |= (b & 0x7F) << shift
        shift += 7
        if not b & 0x80:
            return n, i


def one(msg, num, default=None):
    return msg.get(num, [default])[0]


def zigzag(n):
    return (n >> 1) ^ -(n & 1)


# ------------------------------------------------------------------- rpc ----


class Studio:
    SUBSYS = {"core": 3, "behaviors": 4, "keymap": 5}

    def __init__(self, port):
        self.s = serial.Serial(port, 115200, timeout=0.2)
        self.rid = 0
        self.buf = bytearray()
        self.notifications = []

    def _send(self, payload):
        frame = bytearray([SOF])
        for b in payload:
            if b in (SOF, ESC, EOF):
                frame.append(ESC)
            frame.append(b)
        frame.append(EOF)
        self.s.write(frame)

    def _frames(self, deadline):
        esc, cur, started = False, bytearray(), False
        while time.time() < deadline:
            for b in self.s.read(256):
                if esc:
                    cur.append(b)
                    esc = False
                elif b == ESC:
                    esc = True
                elif b == SOF:
                    cur, started = bytearray(), True
                elif b == EOF and started:
                    yield bytes(cur)
                    started = False
                elif started:
                    cur.append(b)

    def call(self, subsystem, req_field, req_value=1, timeout=3.0):
        self.rid += 1
        inner = field(req_field, req_value)
        self._send(field(1, self.rid) + field(self.SUBSYS[subsystem], inner))
        for frame in self._frames(time.time() + timeout):
            resp = decode(frame)
            if 2 in resp:  # notification
                self.notifications.append(decode(resp[2][0]))
                continue
            rr = decode(resp[1][0])
            if one(rr, 1) != self.rid:
                continue
            if 2 in rr:  # meta: error
                meta = decode(rr[2][0])
                err = one(meta, 2, 0)
                raise RpcError({0: "GENERIC", 1: "UNLOCK_REQUIRED", 2: "RPC_NOT_FOUND",
                                3: "MSG_DECODE_FAILED", 4: "MSG_ENCODE_FAILED"}.get(err, err))
            sub = decode(rr[self.SUBSYS[subsystem]][0])
            return sub[req_field][0] if req_field in sub else b""
        raise TimeoutError(f"no response to {subsystem}.{req_field}")


class RpcError(Exception):
    pass


# ---------------------------------------------------------------- names ----

KEY_NAMES = {0x28: "RET", 0x29: "ESC", 0x2A: "BSPC", 0x2B: "TAB", 0x2C: "SPACE",
             0x2D: "MINUS", 0x2E: "EQUAL", 0x2F: "LBKT", 0x30: "RBKT", 0x31: "BSLH",
             0x33: "SEMI", 0x34: "SQT", 0x35: "GRAVE", 0x36: "COMMA", 0x37: "DOT",
             0x38: "FSLH", 0x39: "CAPS", 0x46: "PSCRN", 0x4A: "HOME", 0x4B: "PG_UP",
             0x4C: "DEL", 0x4D: "END", 0x4E: "PG_DN", 0x4F: "RIGHT", 0x50: "LEFT",
             0x51: "DOWN", 0x52: "UP", 0x65: "K_APP", 0x67: "KP_EQUAL"}
KEY_NAMES.update({0x04 + i: c for i, c in enumerate("ABCDEFGHIJKLMNOPQRSTUVWXYZ")})
KEY_NAMES.update({0x1E + i: "N" + c for i, c in enumerate("1234567890")})
KEY_NAMES.update({0x3A + i: f"F{i + 1}" for i in range(12)})
KEY_NAMES.update({0x59 + i: "KP_N" + c for i, c in enumerate("1234567890")})
MODS = ["LCTRL", "LSHIFT", "LALT", "LGUI", "RCTRL", "RSHIFT", "RALT", "RGUI"]
KEY_NAMES.update({0xE0 + i: m for i, m in enumerate(MODS)})
CONSUMER = {0xE9: "C_VOL_UP", 0xEA: "C_VOL_DN", 0xE2: "C_MUTE", 0xCD: "C_PP",
            0xB5: "C_NEXT", 0xB6: "C_PREV"}


def usage(param):
    """ZMK encodes &kp params as (mods << 24) | (page << 16) | id."""
    mods, page, uid = param >> 24, (param >> 16) & 0xFF, param & 0xFFFF
    if page == 0x07:
        name = KEY_NAMES.get(uid, f"0x{uid:02X}")
    elif page == 0x0C:
        name = CONSUMER.get(uid, f"C_0x{uid:03X}")
    else:
        return str(param)
    for i, m in enumerate(MODS):
        if mods >> i & 1:
            name = f"{m[0]}{m[1]}({name})"  # LG(F11), LS(N1), ...
    return name


def binding_str(b, behaviors):
    bid = zigzag(one(b, 1, 0))
    p1, p2 = one(b, 2, 0), one(b, 3, 0)
    name = behaviors.get(bid, f"#{bid}")
    if name == "Key Press":
        return usage(p1)
    if name in ("Mod-Tap",):
        return f"MT {usage(p1)}/{usage(p2)}"
    params = [str(p) for p in (p1, p2) if p]
    return name + (" " + ",".join(params) if params else "")


# ------------------------------------------------------------------ main ----


def find_port():
    ports = sorted(glob.glob("/dev/serial/by-id/*ZMK*") + glob.glob("/dev/serial/by-id/*Corne*")
                   + glob.glob("/dev/tty.usbmodem*") + glob.glob("/dev/ttyACM*"))
    if not ports:
        sys.exit("no serial port found: is the central flashed with the studio snippet "
                 "and connected over USB?")
    return ports[0]


def dump(st):
    lines = []
    info = decode(st.call("core", 1))
    lines.append(f"device: {one(info, 1, b'').decode()}")

    layouts = decode(st.call("keymap", 6))
    for i, lay in enumerate(layouts.get(2, [])):
        lay = decode(lay)
        active = "*" if i == one(layouts, 1, 0) else " "
        lines.append(f"layout{active} {one(lay, 1, b'').decode()}: {len(lay.get(2, []))} keys")

    beh_ids = decode(st.call("behaviors", 1)).get(1, [])
    if beh_ids and isinstance(beh_ids[0], bytes):  # packed repeated uint32
        packed, beh_ids, i = beh_ids[0], [], 0
        while i < len(packed):
            v, i = _read_varint(packed, i)
            beh_ids.append(v)
    behaviors = {}
    for bid in beh_ids:
        det = decode(st.call("behaviors", 2, field(1, bid)))
        behaviors[bid] = one(det, 2, b"").decode()
    lines.append("behaviors: " + ", ".join(sorted(behaviors.values())))

    km = decode(st.call("keymap", 1))
    lines.append(f"layers: {len(km.get(1, []))} used, {one(km, 2, 0)} free")
    layers = []
    for raw in km.get(1, []):
        layer = decode(raw)
        name = one(layer, 2, b"").decode()
        binds = [binding_str(decode(b), behaviors) for b in layer.get(3, [])]
        layers.append((name, binds))
        lines.append(f"\n[{name}] ({len(binds)} keys)")
        for r in range(0, 36, 12):
            lines.append("  " + " | ".join(f"{b:>10.10}" for b in binds[r:r + 12]))
        lines.append("  " + " " * 39 + " | ".join(f"{b:>10.10}" for b in binds[36:42]))
    return lines, layers


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port")
    ap.add_argument("--save")
    ap.add_argument("--check")
    ap.add_argument("--wait-unlock", type=int, default=60)
    a = ap.parse_args()

    port = a.port or find_port()
    print(f"port: {port}")
    st = Studio(port)

    lock = st.call("core", 2)
    lock = lock if isinstance(lock, int) else 0
    if lock != 1:
        print(f"Studio is locked. Press &studio_unlock on the keyboard "
              f"(Utils layer: hold BSPC thumb + top-right key). Waiting {a.wait_unlock}s...")
        deadline = time.time() + a.wait_unlock
        while time.time() < deadline:
            v = st.call("core", 2)
            if isinstance(v, int) and v == 1:
                break
            time.sleep(1)
        else:
            sys.exit("still locked")
        print("unlocked")

    lines, layers = dump(st)
    print("\n".join(lines))

    problems = []
    names = [n for n, _ in layers]
    if names != EXPECTED_LAYERS:
        problems.append(f"layer names {names} != {EXPECTED_LAYERS}")
    for n, b in layers:
        if len(b) != EXPECTED_KEYS:
            problems.append(f"layer {n}: {len(b)} keys != {EXPECTED_KEYS}")
    if layers and layers[0][1][1:6] != ["Q", "W", "E", "R", "T"]:
        problems.append(f"base top row {layers[0][1][1:6]} != Q W E R T")

    text = "\n".join(lines) + "\n"
    if a.save:
        open(a.save, "w").write(text)
        print(f"\nsaved to {a.save}")
    if a.check:
        import difflib
        old = open(a.check).read()
        d = list(difflib.unified_diff(old.splitlines(), text.splitlines(),
                                      "expected", "keyboard", lineterm=""))
        if d:
            problems.append("differs from " + a.check + ":\n" + "\n".join(d))

    if problems:
        print("\nPROBLEMS:\n- " + "\n- ".join(problems))
        sys.exit(1)
    print("\nOK: keyboard answers Studio RPC and the keymap looks as expected")


if __name__ == "__main__":
    main()
