#!/usr/bin/env bash
# Пошаговая прошивка всей клавиатуры с подсказками (Linux и macOS).
#
#   scripts/flash-all.sh              # донгл, левая, правая + проверка Studio
#   scripts/flash-all.sh --no-dongle  # левая (central), правая
#   scripts/flash-all.sh --reset      # сначала settings_reset на все части
#                                     # (если половины не соединяются с донглом)
#   scripts/flash-all.sh --skip-check # без проверки через Studio в конце
#   scripts/flash-all.sh --os linux   # ОС центральной части: mac | linux
#                                     # (по умолчанию ОС этого компьютера)
#
# Каждый шаг: подсказка что сделать -> Enter -> ожидание флешки -> запись ->
# ожидание перезагрузки. Прошивки берутся из firmware/ (scripts/zmk-docker.sh build).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLASH="$REPO/scripts/flash.sh"
export FLASH_TIMEOUT="${FLASH_TIMEOUT:-600}"

mode=dongle reset=0 check=1 os=""
case "$(uname)" in Darwin) os=mac ;; Linux) os=linux ;; esac
while [ $# -gt 0 ]; do
    a="$1"; shift
    case "$a" in
    --os) os="${1:-}"; shift || true ;;
    --no-dongle) mode=no-dongle ;;
    --reset) reset=1 ;;
    --skip-check) check=0 ;;
    -h | --help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "неизвестный аргумент: $a" >&2; exit 2 ;;
    esac
done
case "$os" in mac | linux) ;; *) echo "--os mac|linux" >&2; exit 2 ;; esac

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
need=()
if [ "$mode" = dongle ]; then
    need+=("corne_central_dongle-*-$os" corne_peripheral_left corne_peripheral_right)
else
    need+=("corne_central_left-*-$os" corne_peripheral_right)
fi
[ $reset = 1 ] && need+=(settings_reset)
for s in "${need[@]}"; do
    ls "$REPO"/firmware/$s*.uf2 >/dev/null 2>&1 || die "нет firmware/$s*.uf2. Собери: scripts/zmk-docker.sh build"
done
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

say "План, шагов: $total (центральная часть — под $os)"
for i in "${!steps[@]}"; do echo "  $((i + 1)). ${steps[$i]#*|}"; done
echo
echo "Reset: nice!nano — кнопка или дважды замкнуть RST и GND; XIAO — кнопка RST у USB-C."
echo "Левую и правую не путай: скрипт их не различает (обе nice!nano)."

# ---- прошивка ------------------------------------------------------------
for i in "${!steps[@]}"; do
    step $((i + 1)) "${steps[$i]%%|*}" "${steps[$i]#*|}"
done

# ---- проверка ------------------------------------------------------------
say "Прошивка завершена"
if [ "$mode" = dongle ]; then
    echo "Подключи донгл в USB, отключи кабель от половины, включи обе половины."
else
    echo "Подключи левую половину в USB, включи правую."
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
