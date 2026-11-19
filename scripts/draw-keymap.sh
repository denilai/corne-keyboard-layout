#!/usr/bin/env bash
# Draw the keymap picture with keymap-drawer (img/keymap-img/corne.{yaml,svg}).
#
#   scripts/draw-keymap.sh          # render and overwrite the images
#   scripts/draw-keymap.sh --check  # fail if the committed images are outdated
#
# Uses `keymap` from PATH if it is the pinned version, otherwise runs it in a
# python container. Version is pinned so local and CI renders are identical.
set -euo pipefail

VERSION="0.23.0"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="img/keymap-img"
CFG="$OUT/keymap_drawer.config.yaml"
KEYMAP="config/corne.keymap"
IMAGE="keymap-drawer:$VERSION"

keymap() {
    if command -v keymap >/dev/null && pip show keymap-drawer 2>/dev/null | grep -qx "Version: $VERSION"; then
        (cd "$REPO" && command keymap "$@")
        return
    fi
    if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
        echo "building $IMAGE (once)..." >&2
        printf 'FROM docker.io/library/python:3.12-slim\nRUN pip install --no-cache-dir keymap-drawer==%s\n' "$VERSION" |
            docker build -q -t "$IMAGE" - >/dev/null
    fi
    docker run --rm -i -u "$(id -u):$(id -g)" -v "$REPO:/repo" -w /repo "$IMAGE" keymap "$@"
}

# Render into .draw-tmp inside the repo (the container only sees the repo).
WORK="$REPO/.draw-tmp"
render() {
    mkdir -p "$WORK"
    trap 'rm -rf "$WORK"' EXIT
    keymap -c "$CFG" parse -z "$KEYMAP" >"$WORK/corne.yaml"
    keymap -c "$CFG" draw .draw-tmp/corne.yaml >"$WORK/corne.svg"
    python3 "$REPO/scripts/keymap_legend.py" "$WORK/corne.svg"   # combos on Base only, legend
}

case "${1:-}" in
"")
    render
    cp "$WORK/corne.yaml" "$WORK/corne.svg" "$REPO/$OUT/"
    echo "updated $OUT/corne.yaml, $OUT/corne.svg"
    ;;
--check)
    render
    if cmp -s "$WORK/corne.yaml" "$REPO/$OUT/corne.yaml" && cmp -s "$WORK/corne.svg" "$REPO/$OUT/corne.svg"; then
        echo "keymap drawing is up to date"
    else
        diff -u "$REPO/$OUT/corne.yaml" "$WORK/corne.yaml" | head -40 || true
        echo "keymap drawing is outdated: run scripts/draw-keymap.sh and commit $OUT/" >&2
        exit 1
    fi
    ;;
*)
    sed -n '2,8p' "$0"
    exit 2
    ;;
esac
