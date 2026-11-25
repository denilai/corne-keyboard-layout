#!/usr/bin/env bash
# Предупреждает, если эталон Studio (tests/hardware/keymap.<os>.txt) снят не с того
# config/corne.keymap, который лежит в индексе git. Коммит не блокирует: сначала
# коммитят keymap, потом собирают, прошивают и снимают эталон с клавиатуры, так что
# между этими шагами эталон устарел всегда.
#
# Запускается из .githooks/pre-commit, когда в коммит попал keymap; можно вручную:
#   scripts/check-studio-reference.sh
#
# Эталон хука снять не может: ему нужны USB, нажатая вручную Studio Unlock и клавиатура
# с прошивкой именно этого коммита (см. CLAUDE.md).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

cur="$(git rev-parse :config/corne.keymap | cut -c1-12)"
for f in tests/hardware/keymap.*.txt; do
    [ -e "$f" ] || continue
    # эталон из индекса (если он в этом же коммите), иначе рабочая копия
    ref="$(git show ":$f" 2>/dev/null | sed -n '1s/^# keymap: //p' || true)"
    [ -n "$ref" ] || ref="$(sed -n '1s/^# keymap: //p' "$f")"
    if [ "$ref" != "$cur" ]; then
        cat >&2 <<EOF
⚠ Эталон Studio устарел: $f снят с keymap $ref, а в коммите keymap $cur.
  Это нормально, пока прошивка не залита. Дальше: собрать и прошить, затем
  .venv/bin/python scripts/studio_check.py --save $f
  (USB и Studio Unlock) и закоммитить эталон. См. CLAUDE.md.
EOF
    fi
done
