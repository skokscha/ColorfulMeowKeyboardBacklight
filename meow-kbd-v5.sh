#!/usr/bin/env bash
#
# meow-kbd-v5.sh — финальная выстреленная версия.
# Отличия от v4:
#   * dyndbg включается СРАЗУ на загружаемый модуль tuxedo_keyboard (видим
#     реальные pr_debug из clevo_leds_init: GET_SPECS/type);
#   * форс-параметр ставится на tuxedo_keyboard (там живёт devicеparam),
#     а не на clevo_acpi (v4 показал: 'unknown parameter ignored').
#
#   sudo bash ~/meow-kbd/meow-kbd-v5.sh
#   sudo FORCE_TYPE=2   bash ~/...meow-kbd-v5.sh   # 3 зоны
#   sudo FORCE_TYPE=243 bash ~/...meow-kbd-v5.sh   # покей RGB
#
# Лог: /tmp/opencode/meow-install-v5.log

set -uo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
LED=/sys/class/leds/rgb:kbdlight
LOG=/tmp/opencode/meow-install-v5.log
DKMSVER="4.18.1+commown1"

mkdir -p "$(dirname "$LOG")" 2>/dev/null || LOG=/tmp/meow-install-v5.log
exec > >(tee -a "$LOG") 2>&1

if [ "$(id -u)" -ne 0 ]; then
    echo "Запусти с sudo: sudo bash $REPO/meow-kbd-v5.sh"
    exit 1
fi

if ! grep -q 'COLORFIRE' "/usr/src/tuxedo-drivers-$DKMSVER/src/tuxedo_compatibility_check/tuxedo_compatibility_check.c" 2>/dev/null; then
    echo "Whitelist не патчен — сначала прошёл бы v4 (проверка пропущена)."
fi

echo "══════ [1/4] Выгрузка стека ══════"
modprobe -r clevo_wmi clevo_acpi uniwill_wmi tuxedo_keyboard tuxedo_io 2>/dev/null
modprobe -r ite_8297 ite_8291_lb ite_8291 ite_829x stk8321 gxtp7380 2>/dev/null
modprobe -r tuxedo_compatibility_check 2>/dev/null
lsmod | grep -q tuxedo_compatibility_check && echo "    ⚠ compat-check не выгрузился" || echo "    стек выгружен"

echo ""
echo "══════ [2/4] Загрузка с дебагом dyndbg=+p ══════"
modprobe tuxedo_keyboard dyndbg=+p
modprobe clevo_wmi
modprobe clevo_acpi
sleep 2
dmesg | grep -iE 'module init|interface initialized|GET_SPECS|backlight type'

try_led() {
    if [ -e "$LED/brightness" ]; then
        echo "    ✔ LED появился: $LED"; return 0
    fi
    echo "    ✘ LED нет"; return 1
}

MODE_SET=plain
FAILED=0
if ! try_led; then
    echo ""
    echo "══════ [3/4] Форс типа подсветки на tuxedo_keyboard ══════"
    FORCE="${FORCE_TYPE:-6}"
    printf 'options tuxedo_keyboard force_clevo_kb_backlight_type=%s\n' "$FORCE" \
        > /etc/modprobe.d/tuxedo-kbd.conf
    echo "    conf: $(cat /etc/modprobe.d/tuxedo-kbd.conf)"
    modprobe -r clevo_wmi clevo_acpi tuxedo_keyboard 2>/dev/null
    modprobe tuxedo_keyboard force_clevo_kb_backlight_type="$FORCE" dyndbg=+p
    modprobe clevo_wmi
    modprobe clevo_acpi
    sleep 2
    dmesg | grep -iE 'GET_SPECS|backlight type|forced' | tail -n 5
    try_led || FAILED=1
fi

echo ""
echo "══════ [4/4] Финализация ══════"
if [ "$FAILED" -eq 0 ]; then
    bash "$REPO/install.sh" | tail -n 6
    mkdir -p /etc/modules-load.d
    printf 'clevo_acpi\nclevo_wmi\n' > /etc/modules-load.d/tuxedo-kbd.conf
    /usr/local/bin/kbdlight color orange 60 && /usr/local/bin/kbdlight save
    echo "    автозагрузка + оранжевый 60%"
fi

echo ""
echo "══════ Итог ══════"
ls -l "$LED/brightness" 2>/dev/null || echo "(LED нет)"
/usr/local/bin/kbdlight status 2>/dev/null || true
echo "-- modules-load.d --"; cat /etc/modules-load.d/tuxedo-kbd.conf 2>/dev/null || echo "(нет)"
echo "-- modprobe.d --";    cat /etc/modprobe.d/tuxedo-kbd.conf 2>/dev/null || echo "(нет)"
echo "-- dkms --";          dkms status 2>/dev/null | grep -i tuxedo
systemctl is-enabled kbdlight-restore.service kbdlight-keys.service 2>/dev/null
echo 'module tuxedo_keyboard -p' > /sys/kernel/debug/dynamic_debug/control 2>/dev/null || true

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "➜ ПЕРЕЗАГРУЗИСЬ — проверяем автозагрузку и восстановление цвета."
else
    echo "➜ Ребут НЕ нужен. Ретрай:"
    echo "    sudo FORCE_TYPE=2   bash $REPO/meow-kbd-v5.sh   # 3 зоны"
    echo "    sudo FORCE_TYPE=243 bash $REPO/meow-kbd-v5.sh   # покей RGB"
    echo "  Не помогло — скажи мне, лог: $LOG"
fi
