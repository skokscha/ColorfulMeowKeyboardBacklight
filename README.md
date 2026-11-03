# MEOW-KBD — управление RGB-подсветкой клавиатуры на COLORFIRE MEOW R15 24 (CachyOS)

**Ноутбук:** COLORFIRE MEOW R15 24 (Ryzen 8845HS + RTX 4060), CachyOS, ядро 7.3.1-1-cachyos (clang/LTO/MODULE_SIG)
**DMI:** `sys_vendor = COLORFIRE`, `product_name = MEOW R15 24`, PCI SSID `1558:35a1` → **Clevo barebone** (3C-сертификация через 蓝天/Clevo).
**Подсветка:** 1-zone RGB, управляется встроенным контроллером (EC) через интерфейсы Clevo WMI/ACPI. USB RGB-контроллера нет → OpenRGB бесполезен.

## Быстрый старт

```bash
git clone https://github.com/skokscha/ColorfulMeowKeyboardBacklight.git
cd meow-kbd
sudo bash ./meow-kbd-v5.sh      # идемпотентный фикс: драйвер + LED + оранжевый 60%
./check-after-reboot.sh         # проверка: модули / LED / цвет / сервисы
```

Дальше — `kbdlight color "#33ccff"`, `kbdlight on|off`, `kbdlight-gui`. Подробности ниже.

Поддерживаемые модели — см. `driver/0003-colorfire-compat.patch` (COLORFIRE / COLORFUL / Clevo-ребренды).
Если у тебя другая модель — заводи issue по шаблону в `.github/ISSUE_TEMPLATE/`.

## Что именно было сделано (TL;DR)

1. Выяснили: стоковый пакет `tuxedo-drivers-dkms 4.25.0` уже стоял, модули собирались, но НЕ загружались: `could not insert 'tuxedo_keyboard': No such device` (`-ENODEV`).
2. Причина №1 — **вендор-гейт**: TUXEDO с версии 4.x закрыл драйверы белым списком (`tuxedo_is_compatible()` в `tuxedo_compatibility_check.c`): DMI-вендор должен быть TUXEDO/PCSpecialist/Ekimia/… и т.п.; таблицы «исключений» по CPU Intel накрывали P15 23 автора проекта 4all3n, а **Ryzen 8845HS (family 0x19, model 0x74) в списке нет** → на COLORFIRE отваливалось всё.
3. Лечение №1 — патч `driver/0003-colorfire-compat.patch`: добавлены `COLORFIRE` и `COLORFUL` во все три DMI-поля (Sys/Board/Chassis).
4. Причина №2 — патченный модуль пересобрался, но **в работающем ядре оставался старый загруженный `tuxedo_compatibility_check`**, который и отдавал старую функцию → перед загрузкой стека его надо выгружать (это делает v4/v5).
5. Причина №3 — прошивка отдаёт `pointer[0x0f] = 0x00` (даже не 0x26, как у родственной COLORFUL P15 23) → `Keyboard backlight type: 0x00` → LED не создаётся. Форсим: **`force_clevo_kb_backlight_type=6`** (1-zone RGB) на модуле `tuxedo_keyboard` (это его `module_param` из `clevo_leds.h`; ставить на `clevo_acpi` бесполезно — ядро отвечает `unknown parameter ignored`).
6. Финал: `✔ LED появился: /sys/class/leds/rgb:kbdlight`, дефолт **оранжевый 60%** (`255 90 0`), всё переживает ребут/сон.

## Файлы проекта

| Файл | Назначение |
|---|---|
| `meow-kbd-v2.sh` | разблок-степ: собирает патченный драйвер (commown fork + 0001/0002) через DKMS |
| `meow-kbd-v5.sh` | **главный** идемпотентный фикс: [выгрузка стека] → [загрузка с dyndbg] → [форс типа 6] → [kbdlight/udev/сервисы] → [оранжевый 60%] |
| `meow-kbd-v4.sh` | как v5, с ручным сравнением .ko — оставлен для истории |
| `meow-kbd-v3.sh`, `meow-kbd-install.sh` | ранние шаги, оставлены для истории |
| `meow-probe.sh` | диагностика: ACPI-ноды, WMI-девы, verbose modprobe, dmesg |
| `driver/0003-colorfire-compat.patch` | **мой патч** whitelist'а (contains COLORFIRE/COLORFUL) |
| `driver/0001-*`, `driver/0002-*` | патчи от 4all3n (форс типа + LED-ренейм + совместимость с ядром 7.3) |
| `install-driver.sh`, `install.sh` | родные установщики проекта 4all3n (dkms-сборка и CLI/GUI) |
| `kbdlight`, `kbdlight-gui.py`, `kbdlight-listen` | CLI/GUI/Fn-listener (ставятся в `/usr/local/bin`) |
| `data/` | udev-правило, desktop-файл, systemd-юниты |
| `docs/logs/` | все логи этапов v2→v5 + probe |
| `check-after-reboot.sh` | проверка состояния после ребута (без sudo) |

## Установка после ребута: что должно работать

```bash
./check-after-reboot.sh    # модули / LED / цвет / сервисы
```

Контроль подсветки — **без sudo** (udev-правило даёт доступ группе `users`):

```bash
kbdlight status
kbdlight color "#33ccff"        # любой HEX
kbdlight color pink 80          # именованный цвет + яркость %
kbdlight set 60 | up | down
kbdlight on | off | toggle
kbdlight-gui                    # GUI ( GTK4/Libadwaita )
kbdlight save                   # запомнить текущее как дефолт (переживёт ребут/сон)
```

Именованные цвета: `white red green blue cyan magenta yellow orange amber purple pink warm`.

Fn-клавиши: зажми **Fn** и жми клавиши яркости/режима на правом блоке (Fn+*, Fn++, Fn+-) — работают через `kbdlight-keys.service`.

## Системные артефакты (где что лежит)

- DKMS-исходники: `/usr/src/tuxedo-drivers-4.18.1+commown1` (патчено: compat whitelist 0003, по 0001/0002 — форс типа/LED-name/kernel 7.3)
- Автозагрузка модулей: `/etc/modules-load.d/tuxedo-kbd.conf` (`clevo_acpi`, `clevo_wmi`)
- Опции модулей: `/etc/modprobe.d/tuxedo-kbd.conf` (`options tuxedo_keyboard force_clevo_kb_backlight_type=6`)
- Дефолтное состояние LED: `/var/lib/kbdlight/state` (`kbdlight save`)
- Сервисы: `kbdlight-restore.service` (boot), `kbdlight-keys.service` (Fn), хук сна `/usr/lib/systemd/system-sleep/kbdlight-resume`
- udev-правило: `/etc/udev/rules.d/99-kbdlight.rules`
- CLI/GUI: `/usr/local/bin/kbdlight{,-gui,-listen}`, ярлык `kbdlight.desktop`

## ⚠️ ВАЖНО: после обновлений системы

У тебя стоит **два** DKMS-набора с одинаковыми именами файлов: `tuxedo-drivers/4.18.1+commown1` (наш, патченный) и `tuxedo-drivers/4.25.0` (AUR `tuxedo-drivers-dkms`). Кто установил модули последним — тот и «победил». Сейчас это 4.18.1+commown1 — так пусть и остаётся.

При `pacman -Syu` с обновлением **`tuxedo-drivers-dkms`** или **ядра** AUR-версия может перезаписать модули в `/lib/modules/*/updates/dkms/*.ko.zst` — LED пропадёт после ребута.

**Излечение одно-командное:**

```bash
sudo bash ~/meow-kbd/meow-kbd-v5.sh
```

(он и патч проверит, и пересоберёт DKMS при нужде, и модули переставит, и LED вернёт).

Альтернатива: заморозить AUR-пакет — `IgnorePkg = tuxedo-drivers-dkms` в `/etc/pacman.conf` (тогда не забудь, что его придётся обновить вручную как-нибудь потом).

## Эксперименты для «крутого»

1. **3 зоны RGB** (лев/центр/право — каждый свой цвет):

   ```bash
   sudo FORCE_TYPE=2 bash ~/meow-kbd/meow-kbd-v5.sh
   ```

   Вернуться на 1-zone: `sudo FORCE_TYPE=6 bash ~/meow-kbd/meow-kbd-v5.sh`.

2. **Per-key RGB (0xf3, 243)** — самый навороченный, на MEOW может не взлететь (прошивка может не поддерживать): `sudo FORCE_TYPE=243 bash ~/meow-kbd/meow-kbd-v5.sh`.

3. **Autostart в DE** — `kbdlight color "#RRGGBB"` в автозагрузку (KDE: Параметры → автостарт), удобно для профилей.

4. **Вентиляторы/профили питания** — Tuxedo Control Center (AUR `tuxedo-control-center`): должен подхватить `tuxedo_io` из нашей сборки. Осторожно с матерью-EC!

5. **Апстрим патча** — наш `0003-colorfire-compat.patch` открывает драйвер для всех COLORFIRE/COLORFUL и прочих Clevo-ребрендов. Жест добра: оформить issue/PR в https://github.com/4all3n/colorful-p15-keyboard-backlight и/или форк commown — автор просил сообщать DMI-строки и значение типа подсветки. Вот они:
   ```
   sys_vendor: COLORFIRE      product_name: MEOW R15 24
   GET_SPECS pointer[0x0f] = 0x00  (тип 0x00, НЕ 0x26 как у P15 23)
   рабочее лечение: force_clevo_kb_backlight_type=6 (1-zone RGB)
   ```

## Демонтаж (если когда-нибудь надоест)

```bash
cd ~/meow-kbd && sudo ./uninstall.sh            # CLI/GUI/сервисы/udev
sudo dkms remove tuxedo-drivers/4.18.1+commown1 --all
sudo rm -f /etc/modules-load.d/tuxedo-kbd.conf /etc/modprobe.d/tuxedo-kbd.conf
sudo pacman -R tuxedo-drivers-dkms              # remove AUR-цела (если вообще не нужно)
```

## Кредиты

- идеи/патчи/инструменты: [4all3n/colorful-p15-keyboard-backlight](https://github.com/4all3n/colorful-p15-keyboard-backlight)
- основа драйверов: [TUXEDO Computers tuxedo-drivers](https://github.com/tuxedocomputers/tuxedo-drivers) через fork [commown/tuxedo-drivers](https://gitlab.com/commown/tuxedo-drivers) (commit 4e1fb3a)
- гайд по Clevo-клавиатурам на Linux: [NovaCustom](https://novacustom.com/clevo-keyboard-backlight-control-for-linux/)
- вдохновение из r/GamingLaptops (Colorfire MEOW R15 24 Linux)

## Финальная строка

Этот драйвер формально не должен был работать на AMD-COLORFIRE: до патча 0003 проект 4all3n дружил только с Intel-моделями (вендор-гейт TUXEDO + отсутствие Ryzen family 0x19/model 0x74 в таблице исключений). Теперь — работает. 🐯
