#!/usr/bin/env bash
# Прошить одну часть клавиатуры файлом из firmware/*.uf2 (Linux и macOS).
#
#   scripts/flash.sh dongle         # плата (nice!nano / XIAO) определяется по флешке
#   scripts/flash.sh left           # левая половина (схема с донглом)
#   scripts/flash.sh right          # правая половина
#   scripts/flash.sh central-left   # левая половина как central (без донгла)
#   scripts/flash.sh reset          # settings_reset: стереть BT-пары и настройки
#
# Скрипт ждёт появления UF2-флешки (двойной reset на части), копирует
# прошивку и ждёт, пока флешка исчезнет (плата перезагрузилась).
# Таймаут ожидания: FLASH_TIMEOUT секунд (по умолчанию 300).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FW="$REPO/firmware"
part="${1:?usage: flash.sh dongle|left|right|central-left|reset}"
timeout="${FLASH_TIMEOUT:-300}"

case "$part" in
dongle) shield=corne_central_dongle ;;
left) shield=corne_peripheral_left ;;
right) shield=corne_peripheral_right ;;
central-left) shield=corne_central_left ;;
reset) shield=settings_reset ;;
*) echo "неизвестная часть: $part" >&2; exit 2 ;;
esac

uf2_drive() {
    local d
    for d in /media/"$USER"/* /run/media/"$USER"/* /Volumes/*; do
        [ -f "$d/INFO_UF2.TXT" ] && { echo "$d"; return 0; }
    done
    return 1
}

echo "Жду UF2-флешку: дважды нажми reset ($part)..."
drive=""
for _ in $(seq "$timeout"); do
    drive="$(uf2_drive)" && break
    sleep 1
done
[ -n "$drive" ] || { echo "флешка не появилась за ${timeout} с" >&2; exit 1; }

info="$(cat "$drive/INFO_UF2.TXT")"
case "$info" in
*nice*nano* | *NICENANO* | *nRF52840-Nano*) board=nice_nano_zmk ;;
*XIAO* | *Seeed*) board=xiao_ble_zmk ;;
*) echo "неизвестная плата на $drive:" >&2; echo "$info" >&2; exit 1 ;;
esac

uf2="$FW/$shield-$board.uf2"
[ -f "$uf2" ] || { echo "нет файла $uf2 (собери: scripts/zmk-docker.sh build)" >&2; exit 1; }
echo "Флешка: $drive ($board)"
echo "Записываю $(basename "$uf2")..."
# Плата перезагружается сразу после записи, поэтому cp может вернуть ошибку.
cp "$uf2" "$drive/" 2>/dev/null || true
sync || true

# Ждём, пока флешка исчезнет: значит, плата перезагрузилась в новую прошивку.
for _ in $(seq 30); do
    [ -d "$drive" ] && [ -f "$drive/INFO_UF2.TXT" ] || { echo "Готово: $part прошит ($(basename "$uf2"))"; exit 0; }
    sleep 1
done
echo "Флешка $drive не исчезла за 30 с: прошивка могла не записаться" >&2
exit 1
