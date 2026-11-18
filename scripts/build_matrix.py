#!/usr/bin/env python3
"""Build every target from build.yaml (same matrix as GitHub Actions).

Runs inside the zmk-build container (see scripts/zmk-docker.sh).
Usage: build_matrix.py [substring filter...]
Output: /repo/firmware/<artifact-name>.uf2 (default <shield>-<board>), as in CI
"""
import re
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path("/repo")
WS = Path("/ws")
OUT = REPO / "firmware"


def load_matrix():
    # build.yaml is a flat list of maps; parse it without PyYAML.
    items, cur = [], None
    for line in (REPO / "build.yaml").read_text().splitlines():
        line = line.split("#", 1)[0].rstrip()
        m = re.match(r"^\s*(-\s+)?([\w-]+):\s*(.*)$", line)
        if not m or m.group(2) == "include":
            continue
        if m.group(1):
            cur = {}
            items.append(cur)
        cur[m.group(2)] = m.group(3).strip().strip('"')
    return items


def main():
    filters = sys.argv[1:]
    OUT.mkdir(exist_ok=True)
    failed = []
    for t in load_matrix():
        name = t.get("artifact-name") or \
            f"{t.get('shield', '')}-{t['board'].replace('//', '_').replace('/', '_')}"
        if filters and not any(f in name for f in filters):
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
