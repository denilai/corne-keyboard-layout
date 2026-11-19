#!/usr/bin/env python3
"""Build firmware targets (same list as build.yaml / GitHub Actions).

Runs inside the zmk-build container (see scripts/zmk-docker.sh).
Usage: build_matrix.py [--mode dongle|no-dongle] [--os mac|linux] [--reset]
                       [--cmake-arg=-DCONFIG_...=...]... [substring filter...]
  no options        every target from scripts/firmware.py (all setups, both OSes)
  --mode/--os       only the parts of that setup / OS (--reset adds settings_reset)
  filters           keep targets whose name contains any of the substrings
  --cmake-arg       extra CMake argument for every target, e.g. a Kconfig
                    override for a test build:
                    --cmake-arg=-DCONFIG_ZMK_IDLE_SLEEP_TIMEOUT=60000 (with "=")
                    The .uf2 names stay the same: rebuild without it after testing.
Output: /repo/firmware/<artifact-name>.uf2 (default <shield>-<board>), as in CI,
and <artifact-name>.info next to it: commit, date, extra CMake arguments and
the resulting sleep setting. scripts/flash.sh prints it before flashing and
warns about a test build (one with --cmake-arg).
"""
import argparse
import datetime
import re
import shutil
import subprocess
import sys
from pathlib import Path

import firmware

REPO = Path("/repo")
WS = Path("/ws")
OUT = REPO / "firmware"


def git(*args):
    r = subprocess.run(["git", "-c", "safe.directory=*", "-C", str(REPO), *args],
                       capture_output=True, text=True)
    return r.stdout.strip()


def build_info(bdir, extra):
    """Text of firmware/<name>.info: where the build came from, what it does."""
    kconfig = (bdir / "zephyr" / ".config").read_text()

    def opt(name):
        m = re.search(rf"^CONFIG_{name}=(.*)$", kconfig, re.M)
        return m.group(1).strip('"') if m else None

    dirty = ", uncommitted changes" if git("status", "--porcelain", "--untracked-files=no") else ""
    if opt("ZMK_SLEEP") == "y":
        sleep = f"after {int(opt('ZMK_IDLE_SLEEP_TIMEOUT')) / 60000:g} min without key presses"
    else:
        sleep = "off"
    lines = [
        f"built:  {datetime.datetime.now(datetime.timezone.utc):%Y-%m-%d %H:%M} UTC",
        f"commit: {git('rev-parse', '--short', 'HEAD')} ({git('branch', '--show-current')}{dirty})",
        f"sleep:  {sleep}",
        f"extra:  {' '.join(extra) or 'none'}",
    ]
    if extra:
        lines.append("TEST BUILD: extra CMake arguments, rebuild without --cmake-arg for normal use")
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=list(firmware.MODES))
    ap.add_argument("--os", choices=firmware.OSES)
    ap.add_argument("--reset", action="store_true")
    ap.add_argument("--cmake-arg", action="append", default=[])
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
        # CMake keeps -D values in its cache: a test override (--cmake-arg)
        # would survive a later build without it. Start clean when the extra
        # arguments differ from the previous build in this directory.
        extra_file = bdir / "extra-cmake-args"
        prev = extra_file.read_text() if extra_file.exists() else ""
        pristine = "always" if prev != " ".join(a.cmake_arg) else "auto"
        cmd = ["west", "build", "-p", pristine, "-s", "zmk/app", "-d", str(bdir),
               "-b", t["board"]]
        if t.get("snippet"):
            cmd += ["-S", t["snippet"]]
        cmd += ["--", f"-DZMK_CONFIG={REPO / 'config'}"]
        if t.get("shield"):
            cmd += [f"-DSHIELD={t['shield']}"]
        if t.get("cmake-args"):
            cmd += t["cmake-args"].split()
        cmd += a.cmake_arg
        print(f"=== {name}", flush=True)
        r = subprocess.run(cmd, cwd=WS, capture_output=True, text=True)
        if r.returncode:
            print(r.stdout[-6000:], r.stderr[-6000:], sep="\n")
            failed.append(name)
            continue
        extra_file.write_text(" ".join(a.cmake_arg))
        uf2 = bdir / "zephyr" / "zmk.uf2"
        shutil.copy(uf2, OUT / f"{name}.uf2")
        info = build_info(bdir, a.cmake_arg)
        (OUT / f"{name}.info").write_text(info)
        print(f"    ok -> firmware/{name}.uf2")
        if a.cmake_arg:
            print("    TEST BUILD: " + " ".join(a.cmake_arg))
    if failed:
        sys.exit("FAILED: " + ", ".join(failed))


if __name__ == "__main__":
    main()
