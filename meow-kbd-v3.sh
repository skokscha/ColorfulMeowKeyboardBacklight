#!/usr/bin/env bash
#
# meow-kbd-v3.sh —终结: добавление COLORFIRE/COLORFUL в whitelist tuxedo_compatibility_check,
# пересборка DKMS, загрузка, (при нужде) форс типа подсветки, дефолтный цвет.
#
#   sudo bash ~/meow-kbd/meow-kbd-v3.sh
#   sudo FORCE_TYPE=2   bash ~/meow-kbd/meow-kbd-v3.sh   # 3 зоны
#   sudo FORCE_TYPE=243 bash ~/meow-kbd/meow-kbd-v3.sh   # покей RGB
#
# Лог: /tmp/opencode/meow-install-v3.log

set -uo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
LED=/sys/class/leds/rgb:kbdlight
LOG=/tmp/opencode/meow-install-v3.log
DKMSVER="4.18.1+commown1"
KCVER="$(uname -r)"
SRC="/usr/src/tuxedo-drivers-$DKMSVER"

mkdir -p "$(dirname "$LOG")" 2>/dev/null || LOG=/tmp/meow-install-v3.log
exec > >(tee -a "$LOG") 2>&1

if [ "$(id -u)" -ne 0 ]; then
    echo "Запусти с sudo: sudo bash $REPO/meow-kbd-v3.sh"
    exit 1
fi

if [ ! -d "$SRC" ]; then
    echo "ERROR: DKMS-источник $SRC не найден."
    echo "Сначала собери драйвер: sudo bash $REPO/meow-kbd-v2.sh"
    exit 1
fi

echo "══════ [1/6] Патч whitelist'а в $SRC ══════"
if grep -q 'COLORFIRE' "$SRC/src/tuxedo_compatibility_check/tuxedo_compatibility_check.c" 2>/dev/null; then
    echo "    уже патчен — пропускаю"
else
    patch -p1 -d "$SRC" < "$REPO/driver/0003-colorfire-compat.patch" || {
        echo "ERROR: патч не применился"; exit 1; }
    echo "    патч применён"
fi

echo ""
echo "══════ [2/6] Пересборка DKMS (${DKMSVER} @ ${KCVER}) ══════"
FAIL=0
if ! dkms build -m tuxedo-drivers -v "$DKMSVER" -k "$KCVER" --force; then
    FAIL=1
else
    if ! dkms install -m tuxedo-drivers -v "$DKMSVER" -k "$KCVER" --force; then
        FAIL=1
    fi
fi
if [ "$FAIL" -eq 1 ]; then
    echo "ERROR: пересборка не удалась — смотри вывод выше и $LOG"
    exit 1
fi
echo "    готово: $(dkms status tuxedo-drivers | tail -1)"

echo ""
echo "══════ [3/6] Проба загрузки ══════"
echo 'module clevo_acpi +p' > /sys/kernel/debug/dynamic_debug/control 2>/dev/null || true
echo 'module clevo_wmi +p'  > /sys/kernel/debug/dynamic_debug/control 2>/dev/null || true
modprobe -r clevo_wmi clevo_acpi uniwill_wmi tuxedo_keyboard 2>/dev/null
modprobe tuxedo_keyboard && echo "    tuxedo_keyboard: OK"
modprobe clevo_wmi  && echo "    clevo_wmi: OK"
modprobe clevo_acpi && echo "    clevo_acpi: OK"
sleep 2
lsmod | grep -E 'clevo|tuxedo' | head -6

try_led() {
    [ -e "$LED/brightness" ] && { echo "    ✔ LED появился: $LED"; return 0; }
    echo "    ✘ LED нет"; return 1
}

if ! try_led; then
    echo ""
    echo "══════ [4/6] Тип подсветки прошивки и форс ══════"
    echo "-- dmesg (тип подсветки):"
    dmesg | grep -iE 'backlight|GET_SPECS' | tail -n 5 || echo "(debug-строк нет)"
    FORCE="${FORCE_TYPE:-6}"
    printf 'options clevo_acpi force_clevo_kb_backlight_type=%s\n' "$FORCE" \
        > /etc/modprobe.d/tuxedo-kbd.conf
    echo "    conf: $(cat /etc/modprobe.d/tuxedo-kbd.conf)"
    modprobe -r clevo_wmi clevo_acpi tuxedo_keyboard 2>/dev/null
    modprobe tuxedo_keyboard 2>/dev/null
    modprobe clevo_wmi 2>/dev/null
    modprobe clevo_acpi 2>/dev/null
    sleep 2
    try_led || true
fi

echo ""
echo "══════ [5/6] Финализация (CLI/GUI/сервисы/дефолт) ══════"
if [ -e "$LED/brightness" ]; then
    bash "$REPO/install.sh" | tail -n 8
    mkdir -p /etc/modules-load.d
    printf 'clevo_acpi\nclevo_wmi\n' > /etc/modules-load.d/tuxedo-kbd.conf
    /usr/local/bin/kbdlight color orange 60 && /usr/local/bin/kbdlight save
    echo "    автозагрузка + оранжевый 60% заданы"
fi

echo ""
echo "══════ [6/6] Итог ══════"
ls -l "$LED/brightness" 2>/dev/null || echo "(LED нет)"
/usr/local/bin/kbdlight status 2>/dev/null || true
echo "-- modules-load.d --";  cat /etc/modules-load.d/tuxedo-kbd.conf 2>/dev/null || echo "(нет)"
echo "-- modprobe.d --";      cat /etc/modprobe.d/tuxedo-kbd.conf 2>/dev/null || echo "(нет)"
echo "-- dkms --";            dkms status 2>/dev/null | grep -i tuxedo
systemctl is-enabled kbdlight-restore.service kbdlight-keys.service 2>/dev/null
echo 'module clevo_acpi -p' > /sys/kernel/debug/dynamic_debug/control 2>/dev/null || true
echo 'module clevo_wmi -p'  > /sys/kernel/debug/dynamic_debug/control 2>/dev/null || true

echo ""
if [ -e "$LED/brightness" ]; then
    echo "➜ ПЕРЕЗАГРУЗИСЬ — проверяем автозагрузку и восстановление цвета."
else
    echo "➜ Ребут НЕ нужен. Ретрай с другими типами:"
    echo "    sudo FORCE_TYPE=2   bash $REPO/meow-kbd-v3.sh   # 3 зоны"
    echo "    sudo FORCE_TYPE=243 bash $REPO/meow-kbd-v3.sh   # покей RGB"
    echo "  Если ни один не завёлся — скажи мне, лог: $LOG"
fi
