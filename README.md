# ColorfulMeowKeyboardBacklight

Управление RGB-подсветкой клавиатуры ноутбука **COLORFIRE MEOW R15 24** (Clevo barebone) на Linux: патчи для DKMS-драйвера + CLI, GUI и обработчик Fn-клавиш.

Без этих патчей подсветка не работает: модули `tuxedo-drivers` собираются, но не загружаются, потому что вендор `COLORFIRE` отсутствует в белом списке TUXEDO, а прошивка отдаёт неизвестный тип подсветки (`0x00`).

## Зачем это нужно

Ноутбук управляет подсветкой через встроенный контроллер (EC) по протоколу Clevo WMI/ACPI. Отдельного USB RGB-контроллера нет, поэтому OpenRGB и подобные инструменты бесполезны — нужен именно драйвер ядра.

Проект решает три конкретные проблемы:

| Проблема | Причина | Решение |
|---|---|---|
| `could not insert 'tuxedo_keyboard': No such device` | Вендор-гейт `tuxedo_is_compatible()` пропускает только TUXEDO/PCSpecialist/Ekimia и таблицы некоторых Intel-моделей; `COLORFIRE` там нет | `driver/0003-colorfire-compat.patch` добавляет `COLORFIRE`/`COLORFUL` во все три DMI-поля (Sys/Board/Chassis) |
| LED не появляется, в dmesg `Keyboard backlight type: 0x00` | Прошивка не сообщает тип подсветки | Форс `force_clevo_kb_backlight_type=6` (1-zone RGB) на модуле `tuxedo_keyboard` |
| Драйвер не собирается на ядрах 7.3+ | Изменился API ACPI/DSM GUID | `driver/0002-linux-7.3-acpi-compatibility.patch` |

После применения патчей создаётся LED-устройство `/sys/class/leds/rgb:kbdlight`.

## Поддерживаемое железо

| | |
|---|---|
| Ноутбук | COLORFIRE MEOW R15 24 (Ryzen 8845HS + RTX 4060) |
| DMI | `sys_vendor = COLORFIRE`, `product_name = MEOW R15 24` |
| PCI SSID | `1558:35a1` → Clevo barebone |
| Подсветка | 1-zone RGB через EC |
| Проверено на | CachyOS, ядро 7.3.1-1-cachyos (clang/LTO/MODULE_SIG) |

Патч белого списка открывает драйвер для всех Clevo-ребрендов (COLORFUL/Tongfang и подобные), но на других моделях работоспособность не проверялась: значение типа подсветки и набор Fn-клавиш могут отличаться. Для другой модели — issue по шаблону из `.github/ISSUE_TEMPLATE/`.

## Требования

- Arch Linux / CachyOS (установщики рассчитаны на `pacman`), `systemd`
- DKMS и заголовки ядра (`linux-cachyos-headers` или аналог)
- `git`, `make`, `gcc`, `clang`/`lld` — для сборки модуля
- GTK4 + Libadwaita + `python-gobject` — только для GUI (ставится через `install.sh`)
- root-права на этапе установки; повседневное управление подсветкой идёт без sudo

## Установка

```bash
git clone https://github.com/skokscha/ColorfulMeowKeyboardBacklight.git
cd ColorfulMeowKeyboardBacklight
sudo bash ./meow-kbd-v2.sh     # первый запуск: проверка стока, при необходимости — сборка патченного DKMS
sudo bash ./meow-kbd-v5.sh     # идемпотентный фикс: перезагрузка стека, форс типа, LED, сервисы
./check-after-reboot.sh        # проверка: модули / LED / цвет / сервисы (без sudo)
```

Рекомендуется перезагрузиться после установки, чтобы проверить автозагрузку модулей и восстановление цвета.

Быстрая проверка без полной установки:

```bash
sudo bash ./meow-probe.sh      # ACPI-ноды, WMI-устройства, verbose modprobe, dmesg
```

## Использование

Контроль подсветки не требует sudo: udev-правило выдаёт доступ группе `users` (переопределяется `KBDLIGHT_GROUP`).

```bash
kbdlight status
kbdlight color "#33ccff"        # любой HEX
kbdlight color pink 80          # именованный цвет + яркость %
kbdlight set 60                 # яркость в процентах
kbdlight up | down
kbdlight on | off | toggle
kbdlight save                   # текущее состояние как дефолт (переживает ребут и сон)
kbdlight-gui                    # GUI на GTK4/Libadwaita
```

Именованные цвета: `white red green blue cyan magenta yellow orange amber purple pink warm`.

Fn-клавиши: зажать **Fn** и нажимать клавиши яркости/режима — обрабатывает `kbdlight-keys.service` (яркость клавиатуры, не экрана; конфликтующие сочетания GNOME отключаются при установке).

## Что устанавливается в систему

| Путь | Назначение |
|---|---|
| `/sys/class/leds/rgb:kbdlight` | LED-устройство, создаётся драйвером |
| `/usr/src/tuxedo-drivers-4.18.1+commown1` | патченные DKMS-исходники |
| `/etc/modules-load.d/tuxedo-kbd.conf` | автозагрузка `clevo_acpi`, `clevo_wmi` |
| `/etc/modprobe.d/tuxedo-kbd.conf` | `options tuxedo_keyboard force_clevo_kb_backlight_type=6` |
| `/var/lib/kbdlight/state` | сохранённое состояние (`kbdlight save`) |
| `/etc/systemd/system/kbdlight-restore.service` | восстановление цвета при загрузке |
| `/etc/systemd/system/kbdlight-keys.service` | обработка Fn-клавиш |
| `/usr/lib/systemd/system-sleep/kbdlight-resume` | восстановление после сна |
| `/etc/udev/rules.d/99-kbdlight.rules` | доступ группе `users` без sudo |
| `/usr/local/bin/kbdlight{,-gui,-listen}` | CLI, GUI, слушатель клавиш |
| `/usr/share/applications/kbdlight.desktop` | ярлык в меню |

## Структура репозитория

| Путь | Описание |
|---|---|
| `meow-kbd-v5.sh` | основной идемпотентный фикс (рекомендуется) |
| `meow-kbd-v2.sh` | установка с проверкой стокового драйвера и сборкой DKMS |
| `meow-kbd-v3.sh`, `meow-kbd-v4.sh`, `meow-kbd-install.sh` | промежуточные версии, оставлены для истории |
| `install-driver.sh` | сборка и установка патченного драйвера через DKMS |
| `install.sh` | установка CLI/GUI, udev-правила и systemd-юнитов |
| `meow-probe.sh` | диагностика: ACPI-ноды, WMI, verbose modprobe, dmesg |
| `check-after-reboot.sh` | проверка состояния после перезагрузки |
| `kbdlight`, `kbdlight-gui.py`, `kbdlight-listen` | CLI, GUI, обработчик Fn-клавиш |
| `data/` | udev-правило, desktop-файл, systemd-юниты |
| `driver/0001-*` | форс типа подсветки и переименование LED (4all3n) |
| `driver/0002-*` | совместимость с ядром 7.3+ |
| `driver/0003-colorfire-compat.patch` | патч белого списка DMI (ключевой для этой модели) |
| `docs/logs/` | логи установки и диагностики |
| `uninstall.sh` | удаление CLI/GUI/сервисов/udev-правила |

## Типичные проблемы

**Подсветка пропала после `pacman -Syu`.** В системе могут оказаться два DKMS-набора с одинаковыми именами файлов: `tuxedo-drivers/4.18.1+commown1` (этот проект) и `tuxedo-drivers/4.25.0` (AUR-пакет `tuxedo-drivers-dkms`). Побеждает тот, что установил модули последним. Лечение одной командой:

```bash
sudo bash ./meow-kbd-v5.sh
```

Чтобы не повторялось, AUR-пакет можно заморозить: `IgnorePkg = tuxedo-drivers-dkms` в `/etc/pacman.conf` (тогда обновлять его нужно вручную).

**LED не появляется.** Запустить `sudo bash ./meow-probe.sh` и посмотреть `dmesg | grep -i "backlight type"`. Если тип не `6`, задать его явно (см. ниже) и перезапустить `meow-kbd-v5.sh`.

**Ядро обновилось, но система не перезагружена.** `install-driver.sh` по умолчанию собирает модуль под ядро с установленными заголовками; при необходимости ядро задаётся вручную: `sudo KVER=7.3.1-1-cachyos ./install-driver.sh`.

## Эксперименты

**3 зоны RGB** (лево/центр/право — каждая своим цветом):

```bash
sudo FORCE_TYPE=2 bash ./meow-kbd-v5.sh
sudo FORCE_TYPE=6 bash ./meow-kbd-v5.sh     # вернуться к 1-zone
```

**Per-key RGB** (тип `243`/`0xf3`) — на этой модели может не поддерживаться прошивкой:

```bash
sudo FORCE_TYPE=243 bash ./meow-kbd-v5.sh
```

**Автостарт в DE.** Добавить `kbdlight color "#RRGGBB"` в автозагрузку окружения — удобно для разных профилей.

**Вентиляторы и профили питания.** `tuxedo-control-center` (AUR) обычно подхватывает `tuxedo_io` из этой сборки. Работа с EC материнской платы — на свой риск.

## Удаление

```bash
sudo ./uninstall.sh
sudo dkms remove tuxedo-drivers/4.18.1+commown1 --all
sudo rm -f /etc/modules-load.d/tuxedo-kbd.conf /etc/modprobe.d/tuxedo-kbd.conf
sudo pacman -R tuxedo-drivers-dkms     # если AUR-пакет больше не нужен
```

## Кредиты

- [4all3n/colorful-p15-keyboard-backlight](https://github.com/4all3n/colorful-p15-keyboard-backlight) — идеи, патчи типа подсветки и LED-переименования, форк драйвера
- [TUXEDO Computers / tuxedo-drivers](https://github.com/tuxedocomputers/tuxedo-drivers) — основа драйверов, через форк [commown/tuxedo-drivers](https://gitlab.com/commown/tuxedo-drivers) (commit `4e1fb3a`)
- [NovaCustom: Clevo keyboard backlight control for Linux](https://novacustom.com/clevo-keyboard-backlight-control-for-linux/)

## Лицензия

GPL-2.0 — см. [LICENSE](LICENSE). Патчи в `driver/` распространяются на условиях лицензии исходного драйвера.
