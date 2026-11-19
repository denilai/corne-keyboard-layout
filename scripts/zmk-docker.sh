#!/usr/bin/env bash
# Local ZMK build and keymap tests in Docker, without installing the toolchain.
#
#   scripts/zmk-docker.sh update            # west update (re-fetch ZMK main and modules)
#   scripts/zmk-docker.sh build [filter]    # build all firmware (scripts/firmware.py) -> firmware/*.uf2
#   scripts/zmk-docker.sh build --mode no-dongle --os mac --reset
#                                           # only the parts of one setup
#   scripts/zmk-docker.sh test  [case...]   # run keymap tests from tests/cases
#   scripts/zmk-docker.sh shell             # shell inside the build container
#
# The west workspace (zephyr + zmk + modules, ~2 GB) lives in a Docker
# volume, so it is downloaded once and the repo stays clean.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${ZMK_IMAGE:-docker.io/zmkfirmware/zmk-build-arm:4.1}"
VOLUME="${ZMK_VOLUME:-zmk-corne-workspace}"

run() {
    local tty=()
    [ -t 0 ] && tty=(-it)
    # ${tty[@]+...}: an empty array is "unbound" under set -u in bash 3.2 (macOS)
    docker run --rm ${tty[@]+"${tty[@]}"} \
        -u "$(id -u):$(id -g)" -e HOME=/ws/.home -e ZEPHYR_BASE=/ws/zephyr -e ACCEPT -e J \
        -v "$VOLUME:/ws" -v "$REPO:/repo" -w /ws \
        "$IMAGE" bash -c "$1" _ "${@:2}"
}

ensure_volume() {
    # Volume is created as root; hand it to the current user once.
    if ! docker volume inspect "$VOLUME" >/dev/null 2>&1; then
        docker volume create "$VOLUME" >/dev/null
        docker run --rm -v "$VOLUME:/ws" "$IMAGE" sh -c "touch /ws/.keep && chown -R $(id -u):$(id -g) /ws"
    fi
}

WS_INIT='
set -e
if [ ! -d /ws/.west ]; then
    mkdir -p /ws/config && cp /repo/config/west.yml /ws/config/west.yml
    west init -l /ws/config
fi
if [ -d /ws/zephyr ] && [ ! -d /ws/.home/.cmake/packages/Zephyr ]; then
    west zephyr-export >/dev/null
fi
'

cmd="${1:-}"; shift || true
ensure_volume

case "$cmd" in
update)
    run "$WS_INIT"'
        cp /repo/config/west.yml /ws/config/west.yml
        west update --fetch-opt=--filter=tree:0 && west zephyr-export'
    ;;
build)
    run "$WS_INIT"'exec python3 /repo/scripts/build_matrix.py "$@"' "$@"
    ;;
test)
    run "$WS_INIT"'exec python3 /repo/tests/run_tests.py "$@"' "$@"
    ;;
shell)
    run "$WS_INIT"'exec bash'
    ;;
*)
    sed -n '2,12p' "$0"; exit 1
    ;;
esac
