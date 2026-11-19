#!/usr/bin/env bash
# Пошаговая прошивка всей клавиатуры с подсказками (Linux и macOS).
#
#   scripts/flash-all.sh                    # схема с донглом: донгл, левая, правая + проверка Studio
#   scripts/flash-all.sh --mode no-dongle   # без донгла: левая (central), правая
#                                           # (--no-dongle — то же самое)
#   scripts/flash-all.sh --reset            # сначала settings_reset на все части
#                                           # (если половины не соединяются с central)
#   scripts/flash-all.sh --no-reset         # не сбрасывать, даже если схема сменилась
#   scripts/flash-all.sh --skip-check       # без проверки через Studio в конце
#   scripts/flash-all.sh --os linux         # ОС центральной части: mac | linux
#                                           # (по умолчанию ОС этого компьютера)
#
# Схемы и их части описаны в scripts/firmware.py. Схема последней прошивки
# запоминается (.git/corne-flashed-mode); при смене схемы сброс включается
# сам: половины хранят пару со старым central и к новому не подключатся.
#
# Каждый шаг: подсказка что сделать -> Enter -> ожидание флешки -> запись ->
# ожидание перезагрузки. Прошивки берутся из firmware/
# (scripts/zmk-docker.sh build --mode <схема> --os <ос> --reset).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLASH="$REPO/scripts/flash.sh"
export FLASH_TIMEOUT="${FLASH_TIMEOUT:-600}"

mode=dongle reset=0 no_reset=0 check=1 os=""
case "$(uname)" in Darwin) os=mac ;; Linux) os=linux ;; esac
while [ $# -gt 0 ]; do
    a="$1"; shift
    case "$a" in
    --os) os="${1:-}"; shift || true ;;
    --mode) mode="${1:-}"; shift || true ;;
    --no-dongle) mode=no-dongle ;;
    --reset) reset=1 ;;
    --no-reset) no_reset=1 ;;
    --skip-check) check=0 ;;
    -h | --help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "неизвестный аргумент: $a" >&2; exit 2 ;;
    esac
done
case "$os" in mac | linux) ;; *) echo "--os mac|linux" >&2; exit 2 ;; esac
python3 "$REPO/scripts/firmware.py" modes | grep -qx -- "$mode" ||
    { echo "--mode $(python3 "$REPO/scripts/firmware.py" modes | paste -sd'|' -)" >&2; exit 2; }

# Схема последней прошивки этой клавиатуры с этого клона.
state="$(git -C "$REPO" rev-parse --absolute-git-dir 2>/dev/null || echo "$REPO/firmware")/corne-flashed-mode"
last="$(cat "$state" 2>/dev/null || true)"

b=$'\e[1m' g=$'\e[32m' y=$'\e[33m' r=$'\e[31m' n=$'\e[0m'
say() { printf '\n%s\n' "${b}$*${n}"; }
ok() { printf '%s\n' "${g}✔ $*${n}"; }
warn() { printf '%s\n' "${y}! $*${n}"; }
die() { printf '%s\n' "${r}✘ $*${n}" >&2; exit 1; }

uf2_drive() {
    local d
    for d in /media/"$USER"/* /run/media/"$USER"/* /Volumes/*; do
        [ -f "$d/INFO_UF2.TXT" ] && { echo "$d"; return 0; }
    done
    return 1
}

studio_port() {
    ls /dev/serial/by-id/*ZMK* /dev/tty.usbmodem* 2>/dev/null | head -1
}

# Ни одна часть не должна быть в загрузчике до подсказки, иначе
# прошивка запишется не туда.
ensure_no_drive() {
    local d
    d="$(uf2_drive)" || return 0
    warn "Уже подключена UF2-флешка $d. Отключи эту плату или дождись её перезагрузки."
    while uf2_drive >/dev/null; do sleep 1; done
}

step() { # step <номер> <part> <текст подсказки>
    local num="$1" part="$2" text="$3"
    say "[$num/$total] $text"
    ensure_no_drive
    read -rp "  Нажми Enter, когда подключил кабель (затем дважды reset)... " _
    local args=("$part")
    case "$part" in dongle | central-left) args+=("$os") ;; esac
    "$FLASH" "${args[@]}" || die "шаг $num ($part) не удался. Повтори: scripts/flash.sh ${args[*]}"
    ok "шаг $num готов"
}

# ---- проверки перед началом ----------------------------------------------
say "Проверка"
if [ -n "$last" ] && [ "$last" != "$mode" ] && [ $reset = 0 ]; then
    if [ $no_reset = 1 ]; then
        warn "схема меняется ($last -> $mode), сброс отключён (--no-reset): половины могут не соединиться"
    else
        warn "схема меняется ($last -> $mode): включаю сброс настроек (settings_reset) на каждой части"
        reset=1
    fi
fi
[ -z "$last" ] && [ $reset = 0 ] &&
    warn "схема прошлой прошивки неизвестна: если она была не $mode, запусти с --reset"
build_hint="scripts/zmk-docker.sh build --mode $mode --os $os --reset"
reset_flag=(); [ $reset = 1 ] && reset_flag=(--reset)
# Донгл бывает nice!nano или XIAO: хватает любого из вариантов.
missing=0
for f in $(python3 "$REPO/scripts/firmware.py" list --mode "$mode" --os "$os" ${reset_flag[@]+"${reset_flag[@]}"}); do
    [ -f "$REPO/firmware/$f.uf2" ] && continue
    case "$f" in
    *xiao_ble*) ls "$REPO/firmware/${f/xiao_ble/nice_nano}.uf2" >/dev/null 2>&1 && continue ;;
    *nice_nano*) ls "$REPO/firmware/${f/nice_nano/xiao_ble}.uf2" >/dev/null 2>&1 && continue ;;
    esac
    warn "нет firmware/$f.uf2"; missing=1
done
[ $missing = 0 ] || die "собери прошивки: $build_hint"
ok "прошивки на месте: $(ls "$REPO"/firmware/*.uf2 | wc -l | tr -d ' ') файлов в firmware/"

if [ $check = 1 ] && ! python3 -c 'import serial' 2>/dev/null; then
    die "для проверки Studio нужен pyserial: python3 -m pip install --user pyserial (или --skip-check)"
fi
if [ "$(uname)" = Linux ] && [ ! -f /etc/udev/rules.d/70-zmk-studio.rules ]; then
    warn "нет udev-правила: Studio не получит доступ к порту. Поставь:"
    echo "    sudo cp $REPO/scripts/udev/70-zmk-studio.rules /etc/udev/rules.d/ && sudo udevadm control --reload-rules"
fi
warn "Пока прошиты не все части, клавиатура может не печатать: держи под рукой другую."

# ---- план ----------------------------------------------------------------
steps=()
# add <part> <подсказка>: с --reset перед прошивкой части идёт её сброс,
# кабель между ними не переключается.
add() {
    if [ $reset = 1 ]; then
        steps+=("reset|$2 — сброс настроек (settings_reset)"
            "$1|$2 — та же часть, снова двойной reset: основная прошивка")
    else
        steps+=("$1|$2")
    fi
}
if [ "$mode" = dongle ]; then
    add dongle "ДОНГЛ: донгл в USB"
    add left "ЛЕВАЯ половина: подключи ЛЕВУЮ кабелем (донгл можно не вынимать)"
    add right "ПРАВАЯ половина: отключи левую, подключи ПРАВУЮ кабелем"
else
    add central-left "ЛЕВАЯ половина (central): подключи ЛЕВУЮ кабелем"
    add right "ПРАВАЯ половина: отключи левую, подключи ПРАВУЮ кабелем"
fi
total=${#steps[@]}

say "План, шагов: $total (схема $mode, центральная часть — под $os)"
for i in "${!steps[@]}"; do echo "  $((i + 1)). ${steps[$i]#*|}"; done
echo
echo "Reset: nice!nano — кнопка или дважды замкнуть RST и GND; XIAO — кнопка RST у USB-C."
echo "Левую и правую не путай: скрипт их не различает (обе nice!nano)."

# ---- прошивка ------------------------------------------------------------
for i in "${!steps[@]}"; do
    step $((i + 1)) "${steps[$i]%%|*}" "${steps[$i]#*|}"
done

# ---- проверка ------------------------------------------------------------
echo "$mode" >"$state"
say "Прошивка завершена"
if [ "$mode" = dongle ]; then
    echo "Подключи донгл в USB, отключи кабель от половины, включи обе половины."
else
    echo "Отключи донгл (иначе он перехватит правую половину), подключи левую половину в USB, включи правую."
    echo "К компьютеру по Bluetooth: «Corne» в настройках Bluetooth (связь идёт через левую половину)."
fi
[ $check = 1 ] || exit 0

say "Проверка Studio"
echo "Жду порт Studio..."
port=""
for _ in $(seq 60); do
    port="$(studio_port)" && [ -n "$port" ] && break
    sleep 1
done
[ -n "$port" ] || die "порт Studio не появился за 60 с: central подключён по USB?"
ok "порт: $port"

echo "Набери что-нибудь на клавиатуре: половины должны печатать."
echo "Затем разблокируй Studio: зажми BSPC (правый thumb, средняя) + правая верхняя клавиша."
ref="$REPO/tests/hardware/keymap.$os.txt"
args=(--port "$port" --wait-unlock 300)
if [ -f "$ref" ]; then
    args+=(--check "$ref")
else
    args+=(--save "$ref")
    warn "эталона $ref нет: сохраню прочитанную раскладку, проверь её и закоммить"
fi
if python3 "$REPO/scripts/studio_check.py" "${args[@]}"; then
    ok "клавиатура отвечает, раскладка совпадает с эталоном (или сохранена как эталон)"
else
    die "проверка не прошла (см. вывод выше). Если половины не печатают: scripts/flash-all.sh --reset"
fi
