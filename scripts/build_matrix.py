#!/usr/bin/env python3
"""Build firmware targets (same list as build.yaml / GitHub Actions).

Runs inside the zmk-build container (see scripts/zmk-docker.sh).
Usage: build_matrix.py [--mode dongle|no-dongle] [--os mac|linux] [--reset]
                       [substring filter...]
  no options        every target from scripts/firmware.py (all setups, both OSes)
  --mode/--os       only the parts of that setup / OS (--reset adds settings_reset)
  filters           keep targets whose name contains any of the substrings
Output: /repo/firmware/<artifact-name>.uf2 (default <shield>-<board>), as in CI
"""
import argparse
import shutil
import subprocess
import sys
from pathlib import Path

import firmware

REPO = Path("/repo")
WS = Path("/ws")
OUT = REPO / "firmware"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=list(firmware.MODES))
    ap.add_argument("--os", choices=firmware.OSES)
    ap.add_argument("--reset", action="store_true")
    ap.add_argument("filters", nargs="*")
    a = ap.parse_args()
    if a.mode or a.os:
        todo = firmware.targets(a.mode, a.os, reset=a.reset)
    else:
        todo = firmware.targets()
    OUT.mkdir(exist_ok=True)
    failed = []
    for t in todo:
        name = firmware.name(t)
        if a.filters and not any(f in name for f in a.filters):
            continue
        bdir = WS / "build" / name
        cmd = ["west", "build", "-p", "auto", "-s", "zmk/app", "-d", str(bdir),
               "-b", t["board"]]
        if t.get("snippet"):
            cmd += ["-S", t["snippet"]]
        cmd += ["--", f"-DZMK_CONFIG={REPO / 'config'}"]
        if t.get("shield"):
            cmd += [f"-DSHIELD={t['shield']}"]
        if t.get("cmake-args"):
            cmd += t["cmake-args"].split()
        print(f"=== {name}", flush=True)
        r = subprocess.run(cmd, cwd=WS, capture_output=True, text=True)
        if r.returncode:
            print(r.stdout[-6000:], r.stderr[-6000:], sep="\n")
            failed.append(name)
            continue
        uf2 = bdir / "zephyr" / "zmk.uf2"
        shutil.copy(uf2, OUT / f"{name}.uf2")
        print(f"    ok -> firmware/{name}.uf2")
    if failed:
        sys.exit("FAILED: " + ", ".join(failed))


if __name__ == "__main__":
    main()
