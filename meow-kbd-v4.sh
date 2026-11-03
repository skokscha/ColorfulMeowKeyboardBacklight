#!/usr/bin/env bash
#
# meow-kbd-v4.sh — как v3, но перед загрузкой ВЫГРУЖАЕТ tuxedo_compatibility_check:
# иначе в работающем ядре остаётся старая функция tuxedo_is_compatible() и
# патч whitelist'а не действует (симптом: -ENODEV после пересборки).
#
#   sudo bash ~/meow-kbd/meow-kbd-v4.sh
#   sudo FORCE_TYPE=2   bash ~/meow-kbd/meow-kbd-v4.sh   # 3 зоны
#   sudo FORCE_TYPE=243 bash ~/meow-kbd/meow-kbd-v4.sh   # покей RGB
#
# Лог: /tmp/opencode/meow-install-v4.log

set -uo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
LED=/sys/class/leds/rgb:kbdlight
LOG=/tmp/opencode/meow-install-v4.log
DKMSVER="4.18.1+commown1"
KCVER="$(uname -r)"
SRC="/usr/src/tuxedo-drivers-$DKMSVER"

mkdir -p "$(dirname "$LOG")" 2>/dev/null || LOG=/tmp/meow-install-v4.log
exec > >(tee -a "$LOG") 2>&1

if [ "$(id -u)" -ne 0 ]; then
    echo "Запусти с sudo: sudo bash $REPO/meow-kbd-v4.sh"
    exit 1
fi

if [ ! -d "$SRC" ]; then
    echo "ERROR: DKMS-источник $SRC не найден — сначала sudo bash $REPO/meow-kbd-v2.sh"
    exit 1
fi

echo "══════ [1/6] Патч whitelist'а (idempotent) ══════"
if grep -q 'COLORFIRE' "$SRC/src/tuxedo_compatibility_check/tuxedo_compatibility_check.c" 2>/dev/null; then
    echo "    уже патчен — пропускаю"
else
    patch -p1 -d "$SRC" < "$REPO/driver/0003-colorfire-compat.patch" || { echo "ERROR: патч"; exit 1; }
    echo "    патч применён"
fi

echo ""
echo "══════ [2/6] Пересборка DKMS (если в дереве свежие патчи) ══════"
NEED=0
grep -q 'COLORFIRE' "$SRC/src/tuxedo_compatibility_check/tuxedo_compatibility_check.c" || NEED=1
# проверь: пересобранный ли сейчас .ko в /lib/modules (сравнение md5 build vs installed)
BUILD_KO="/var/lib/dkms/tuxedo-drivers/$DKMSVER/$KCVER/x86_64/module/tuxedo_compatibility_check.ko.zst" 2>/dev/null || true
INST_KO="/lib/modules/$KCVER/updates/dkms/tuxedo_compatibility_check.ko.zst"
if [ -s "$BUILD_KO" ] && [ -e "$INST_KO" ]; then
    if ! cmp -s "$BUILD_KO" "$INST_KO"; then
        NEED=1
        echo "    установленный .ko отличается от собранного → нужна переустановка"
    fi
else
    NEED=1
fi
if [ "$NEED" -eq 1 ]; then
    if dkms build -m tuxedo-drivers -v "$DKMSVER" -k "$KCVER" --force; then
        dkms install -m tuxedo-drivers -v "$DKMSVER" -k "$KCVER" --force
        echo "    DKMS обновлён";
    else
        echo "ERROR: пересборка не удалась — смотри вывод выше и $LOG"
        exit 1
    fi
else
    echo "    .ko актуален — пересборка не нужна"
fi

echo ""
echo "══════ [3/6] Полная выгрузка стека (включая compat-check!) ══════"
modprobe -r clevo_wmi clevo_acpi uniwill_wmi tuxedo_keyboard tuxedo_io 2>/dev/null
modprobe -r ite_8297 ite_8291_lb ite_8291 ite_829x stk8321 gxtp7380 2>/dev/null
modprobe -r tuxedo_compatibility_check 2>/dev/null
if lsmod | grep -q tuxedo_compatibility_check; then
    echo "    ⚠ tuxedo_compatibility_check не выгрузился (держит кто-то?)"
    lsmod | grep -E 'tuxedo|clevo' || true
else
    echo "    стек выгружен чисто"
fi

echo ""
echo "══════ [4/6] Загрузка патченного стека ══════"
echo 'module clevo_acpi +p' > /sys/kernel/debug/dynamic_debug/control 2>/dev/null || true
echo 'module clevo_wmi +p'  > /sys/kernel/debug/dynamic_debug/control 2>/dev/null || true
modprobe tuxedo_keyboard && echo "    tuxedo_keyboard: ✔"
modprobe clevo_wmi  && echo "    clevo_wmi: ✔"
modprobe clevo_acpi && echo "    clevo_acpi: ✔"
sleep 2
lsmod | grep -E 'clevo|tuxedo' | head -8

try_led() {
    if [ -e "$LED/brightness" ]; then
        echo "    ✔ LED появился: $LED"; return 0
    fi
    echo "    ✘ LED нет"; return 1
}

FAILED=0
if ! try_led; then
    echo ""
    echo "══════ [5/6] Тип подсветки и форс ══════"
    echo "-- dmesg:"
    dmesg | grep -iE 'backlight|GET_SPECS|Clevo' | tail -n 8 || echo "(debug-строк нет)"
    FORCE="${FORCE_TYPE:-6}"
    printf 'options clevo_acpi force_clevo_kb_backlight_type=%s\n' "$FORCE" \
        > /etc/modprobe.d/tuxedo-kbd.conf
    modprobe -r clevo_wmi clevo_acpi tuxedo_keyboard 2>/dev/null
    modprobe tuxedo_keyboard 2>/dev/null
    modprobe clevo_wmi 2>/dev/null
    modprobe clevo_acpi 2>/dev/null
    sleep 2
    try_led || FAILED=1
fi

echo ""
echo "══════ [6/6] Финализация ══════"
if [ "$FAILED" -eq 0 ]; then
    bash "$REPO/install.sh" | tail -n 6
    mkdir -p /etc/modules-load.d
    printf 'clevo_acpi\nclevo_wmi\n' > /etc/modules-load.d/tuxedo-kbd.conf
    /usr/local/bin/kbdlight color orange 60 && /usr/local/bin/kbdlight save
    echo "    автозагрузка + оранжевый 60% заданы"
fi

echo ""
echo "══════ Итог ══════"
ls -l "$LED/brightness" 2>/dev/null || echo "(LED нет)"
/usr/local/bin/kbdlight status 2>/dev/null || true
echo "-- modules-load.d --"; cat /etc/modules-load.d/tuxedo-kbd.conf 2>/dev/null || echo "(нет)"
echo "-- modprobe.d --";    cat /etc/modprobe.d/tuxedo-kbd.conf 2>/dev/null || echo "(нет)"
echo "-- dkms --";          dkms status 2>/dev/null | grep -i tuxedo
systemctl is-enabled kbdlight-restore.service kbdlight-keys.service 2>/dev/null
echo 'module clevo_acpi -p' > /sys/kernel/debug/dynamic_debug/control 2>/dev/null || true
echo 'module clevo_wmi -p'  > /sys/kernel/debug/dynamic_debug/control 2>/dev/null || true

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "➜ ПЕРЕЗАГРУЗИСЬ — проверяем автозагрузку и восстановление цвета."
else
    echo "➜ Ребут НЕ нужен. Ретрай:"
    echo "    sudo FORCE_TYPE=2   bash $REPO/meow-kbd-v4.sh   # 3 зоны"
    echo "    sudo FORCE_TYPE=243 bash $REPO/meow-kbd-v4.sh   # покей RGB"
    echo "  Не помогло — скажи мне, лог: $LOG"
fi
