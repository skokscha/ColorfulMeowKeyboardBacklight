#!/usr/bin/env bash
#
# meow-kbd-install.sh — подсветка клавиатуры COLORFIRE MEOW R15 24 (Clevo EC)
# на CachyOS/Arch Linux, одна команда.
#
#   sudo bash ~/meow-kbd/meow-kbd-install.sh
#
# Если LED не появился, повторить с другим типом:
#   sudo FORCE_TYPE=2   bash ~/meow-kbd/meow-kbd-install.sh   # 3 зоны
#   sudo FORCE_TYPE=243 bash ~/meow-kbd/meow-kbd-install.sh   # покей RGB
#
# Полный лог пишется в /tmp/opencode/meow-install.log.

set -uo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
LED=/sys/class/leds/rgb:kbdlight
LOG=/tmp/opencode/meow-install.log

mkdir -p "$(dirname "$LOG")" 2>/dev/null || LOG=/tmp/meow-install.log
exec > >(tee -a "$LOG") 2>&1

if [ "$(id -u)" -ne 0 ]; then
    echo "Запусти с sudo: sudo bash $REPO/meow-kbd-install.sh"
    exit 1
fi

echo ""
echo "══════ [1/4] Патченный tuxedo_keyboard через DKMS ══════"
FAIL=0
if ! ./install-driver.sh; then
    FAIL=1
fi

echo ""
echo "══════ [2/4] kbdlight (CLI + GUI + udev + сервисы) ══════"
./install.sh

if [ -e "$LED/brightness" ]; then
    echo ""
    echo "══════ [3/4] Дефолт: оранжевый 60 % (цвет MEOW) ══════"
    /usr/local/bin/kbdlight color orange 60 && /usr/local/bin/kbdlight save
else
    echo ""
    echo "══════ [3/4] LED не появился — дефолт не задан ══════"
    echo "Ретрай с другим типом подсветки:"
    echo "  sudo FORCE_TYPE=2   bash $REPO/meow-kbd-install.sh   # 3 зоны"
    echo "  sudo FORCE_TYPE=243 bash $REPO/meow-kbd-install.sh   # покей RGB"
fi

echo ""
echo "══════ [4/4] Итог ══════"
echo "-- LED --"
ls -l "$LED/brightness" 2>/dev/null || echo "(нет)"
echo "-- kbdlight status --"
/usr/local/bin/kbdlight status 2>/dev/null || true
echo "-- dkms --"
dkms status 2>/dev/null | grep -i tuxedo || echo "(tuxedo-drivers не установлен)"
echo "-- сервисы --"
systemctl is-enabled kbdlight-restore.service 2>/dev/null
systemctl is-enabled kbdlight-keys.service 2>/dev/null

if [ "$FAIL" -eq 1 ]; then
    echo ""
    echo "══════ Диагностика (install-driver.sh завершился с ошибкой) ══════"
    echo "-- dkms status (всё) --"
    dkms status 2>/dev/null || true
    echo "-- модули --"
    lsmod | grep -E 'clevo|tuxedo' || echo "(не загружены)"
    echo "-- dmesg (последние 40 строк) --"
    dmesg | tail -n 40
    echo "Полный лог: $LOG"
fi

echo ""
echo "Готово. Если LED появился — перезагрузись, чтобы проверить автозагрузку"
echo "и восстановление цвета на старте. После ребута:  kbdlight status"
