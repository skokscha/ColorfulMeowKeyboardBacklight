#!/usr/bin/env bash
#
# check-after-reboot.sh — быстрый осмотр состояния подсветки после ребута.
# Запускать БЕЗ sudo:  bash ~/meow-kbd/check-after-reboot.sh
set -uo pipefail

LED=/sys/class/leds/rgb:kbdlight
OK=0; BAD=0
step() { printf '  %s  %s\n' "$1" "$2"; }

echo "══ Проверка после перезагрузки ══"

if lsmod | grep -q 'clevo_acpi'; then
    step "✔" "модули загружены (clevo_acpi / clevo_wmi)"
else
    step "✘" "clevo-модули НЕ загружены"; BAD=1
fi

if [ -e "$LED/brightness" ]; then
    step "✔" "LED: $LED (права: $(ls -l "$LED/brightness" | awk '{print $1, $3":"$4}'))"
else
    step "✘" "LED отсутствует"; BAD=1
fi

if [ "$BAD" -eq 0 ]; then
    B="$(cat "$LED/brightness" 2>/dev/null)"
    C="$(cat "$LED/multi_intensity" 2>/dev/null)"
    step "•" "яркость: $B/255   цвет: $C (ожидание: 153 / 255 90 0 = оранжевый 60%)"
fi

if systemctl is-enabled kbdlight-restore.service &>/dev/null && systemctl is-enabled kbdlight-keys.service &>/dev/null; then
    step "✔" "сервисы: kbdlight-restore + kbdlight-keys включены"
else
    step "✘" "сервисы kbdlight не enabled"; BAD=1
fi

if [ -x /usr/local/bin/kbdlight ]; then
    if /usr/local/bin/kbdlight status > /dev/null 2>&1; then
        step "✔" "kbdlight работает без sudo"
        /usr/local/bin/kbdlight status | sed 's/^/      /'
    else
        step "✘" "kbdlight не может достучаться до LED"
        BAD=1
    fi
else
    step "✘" "/usr/local/bin/kbdlight отсутствует"; BAD=1
fi

echo ""
if [ "$BAD" -eq 0 ]; then
    echo "➜ Всё на месте. Цвет можно менять:  kbdlight color \"#33ccff\""
else
    echo "➜ Что-то отвалилось. Чинится одной командой:"
    echo "    sudo bash ~/meow-kbd/meow-kbd-v5.sh"
    echo "  (см. ~/meow-kbd/README.md ← раздел про обновления системы)"
fi
