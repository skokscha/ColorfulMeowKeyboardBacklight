#!/usr/bin/env bash
#
# meow-probe.sh — детальная диагностика, почему clevo-модули не грузятся.
#   sudo bash ~/meow-kbd/meow-probe.sh
# Лог: /tmp/opencode/meow-probe.log
set -uo pipefail
LOG=/tmp/opencode/meow-probe.log
mkdir -p "$(dirname "$LOG")" 2>/dev/null || LOG=/tmp/meow-probe.log
exec > >(tee -a "$LOG") 2>&1
[ "$(id -u)" -eq 0 ] || { echo "Запусти с sudo"; exit 1; }

echo "══ A. ACPI-ноды ══"
for d in /sys/bus/platform/devices/CLV*; do
    [ -e "$d" ] || continue
    echo "-- $d"
    cat "$d/modalias" 2>/dev/null
    readlink "$d/driver" 2>/dev/null || echo "(driver: не привязан)"
done

echo ""
echo "══ B. WMI-девы ══"
ls /sys/bus/wmi/devices/ 2>/dev/null

echo ""
echo "══ C.(modVerbose) грузим по одному verbosely ══"
modprobe -r clevo_wmi clevo_acpi tuxedo_keyboard 2>/dev/null
echo "-- modprobe -v tuxedo_keyboard"
modprobe -v tuxedo_keyboard; echo "rc=$?"
echo "-- modprobe -v clevo_wmi"
modprobe -v clevo_wmi; echo "rc=$?"
echo "-- modprobe -v clevo_acpi"
modprobe -v clevo_acpi; echo "rc=$?"

echo ""
echo "══ D. драйверы на шине ══"
ls -l /sys/bus/platform/drivers/ 2>/dev/null | grep -iE 'clevo|tuxedo'
lsmod | grep -E 'clevo|tuxedo' || echo "(ничего не загружено)"

echo ""
echo "══ E. LED ══"
ls /sys/class/leds/ | grep -iE 'kbd|rgb' || echo "(нет LED)"

echo ""
echo "══ F. dmesg хвост ══"
dmesg | tail -n 45

echo ""
echo "Лог: $LOG"
