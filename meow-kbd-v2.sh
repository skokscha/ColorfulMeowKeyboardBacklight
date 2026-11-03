#!/usr/bin/env bash
#
# meow-kbd-v2.sh — подсветка COLORFIRE MEOW R15 24 (Clevo EC), CachyOS.
# Адаптивно: 1) пробует уже установленный стоковый tuxedo-drivers 4.25.0,
# 2) если прошивка отдаёт неизвестный тип RGB — ставит патченный драйвер 4all3n,
# 3) ставит kbdlight CLI/GUI/Iudc-права/сервисы и дефолтный цвет.
#
#   sudo bash ~/meow-kbd/meow-kbd-v2.sh
#   sudo FORCE_TYPE=2   bash ~/meow-kbd/meow-kbd-v2.sh   # 3 зоны
#   sudo FORCE_TYPE=243 bash ~/meow-kbd/meow-kbd-v2.sh   # покей RGB
#
# Полный лог: /tmp/opencode/meow-install-v2.log

set -uo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
LED=/sys/class/leds/rgb:kbdlight
LOG=/tmp/opencode/meow-install-v2.log

mkdir -p "$(dirname "$LOG")" 2>/dev/null || LOG=/tmp/meow-install-v2.log
exec > >(tee -a "$LOG") 2>&1

if [ "$(id -u)" -ne 0 ]; then
    echo "Запусти с sudo: sudo bash $REPO/meow-kbd-v2.sh"
    exit 1
fi

echo "pwd=$(pwd)"
echo "REPO=$REPO"
chmod +x "$REPO"/install-driver.sh "$REPO"/install.sh

echo ""
echo "══════ [1/4] Проба установленного стокового tuxedo-drivers 4.25.0 ══════"
modprobe -r tuxedo_io clevo_wmi clevo_acpi uniwill_wmi tuxedo_keyboard 2>/dev/null
echo 'module clevo_acpi +p' > /sys/kernel/debug/dynamic_debug/control 2>/dev/null || true
echo 'module clevo_wmi +p'  > /sys/kernel/debug/dynamic_debug/control 2>/dev/null || true
modprobe clevo_wmi  || true
modprobe clevo_acpi || true
sleep 2
lsmod | grep -E 'clevo|tuxedo' || echo "(модули не загрузились)"

FAIL=0
if [ -e "$LED/brightness" ]; then
    echo "✔ Стоковый драйвер работает, патч не нужен"
else
    echo "✘ Стоковый LED не появился → нужен патч проекта"
    echo ""
    echo "══════ [2/4] Патченный tuxedo_keyboard через DKMS ══════"
    if ! bash "$REPO/install-driver.sh"; then
        FAIL=1
    fi
fi

echo ""
echo "══════ [3/4] kbdlight CLI/GUI + udev + сервисы ══════"
bash "$REPO/install.sh"

if [ -e "$LED/brightness" ]; then
    mkdir -p /etc/modules-load.d
    printf 'clevo_acpi\nclevo_wmi\n' > /etc/modules-load.d/tuxedo-kbd.conf
    echo ""
    echo "══════ [4/4] Дефолт: оранжевый 60% ══════"
    /usr/local/bin/kbdlight color orange 60 && /usr/local/bin/kbdlight save
fi

echo ""
echo "══════ Итог ══════"
echo "-- LED --"
ls -l "$LED/brightness" 2>/dev/null || echo "(нет)"
echo "-- kbdlight --"
/usr/local/bin/kbdlight status 2>/dev/null || true
echo "-- автозагрузка --"
cat /etc/modules-load.d/tuxedo-kbd.conf 2>/dev/null || echo "(нет conf)"
cat /etc/modprobe.d/tuxedo-kbd.conf 2>/dev/null
echo "-- dkms --"
dkms status 2>/dev/null | grep -i tuxedo
echo "-- сервисы --"
systemctl is-enabled kbdlight-restore.service 2>/dev/null
systemctl is-enabled kbdlight-keys.service 2>/dev/null

if [ "$FAIL" -eq 1 ]; then
    echo ""
    echo "══════ Дополнительная диагностика ══════"
    dmesg | grep -iE 'clevo|tuxedo|backlight' | tail -n 20
    dmesg | tail -n 15
fi

echo ""
echo "Полный лог: $LOG"
if [ -e "$LED/brightness" ]; then
    echo "➜ ПЕРЕЗАГРУЗИСЬ, чтобы проверить автозагрузку и восстановление цвета."
else
    echo "➜ Ребут пока НЕ нужен: сначала ретрай (см. подсказки выше, если они есть)."
fi
