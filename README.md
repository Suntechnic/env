# env — настройки рабочего окружения

Репозиторий устроен как конвейер «манифест → снимок → деплой»:

```
manifests/   files.txt и dconf-paths.txt (что собирать), tools.txt (что ставить)
scripts/     collect.sh, deploy.sh, bootstrap.sh, doctor.sh
snapshot/    собранный снимок; именно он раскатывается на целевой машине
.zshrc       легаси-копия snapshot/home/.zshrc для старых машин
```

`snapshot/` — источник истины. Всё, что должно попасть на целевую машину,
сначала появляется в снимке.

Поддерживаемые системы: **Ubuntu/Debian** и **CentOS/AlmaLinux**, как с
графической сессией GNOME, так и без неё (серверы, контейнеры). На headless
системах настройки dconf пропускаются, файлы применяются как обычно.

# zsh

Установка на целевой машине (канонический путь — из снимка):

```bash
wget https://raw.githubusercontent.com/Suntechnic/env/refs/heads/main/snapshot/home/.zshrc -O ~/.zshrc;
```

Часть старых машин читает `.zshrc` из корня репозитория. Это легаси-копия,
`collect.sh` автоматически синхронизирует её со снимком:

```bash
wget https://raw.githubusercontent.com/Suntechnic/env/refs/heads/main/.zshrc -O ~/.zshrc;
```

Плагины (autosuggestions, history-substring-search, syntax-highlighting) и
обновление конфигурации `zsh-update` тянут файл из `snapshot/home/.zshrc`.

# Что входит в снимок

- `snapshot/home/` — файлы из `manifests/files.txt` (`.zshrc`, `.face`,
  конфиги micro и т.д.).
- `snapshot/dconf/*.ini` — дампы dconf для путей из `manifests/dconf-paths.txt`
  (клавиши GNOME, media-keys, gTile, Guake, раскладки, тайлинг).
- `snapshot/extensions/` — списки установленных и включённых расширений GNOME.
- `snapshot/metadata/` — версия GNOME Shell и `/etc/os-release`.
- `snapshot/files.txt`, `snapshot/dconf-paths.txt` — копии манифестов, чтобы
  архив с репозитория был самодостаточным.
- `manifests/tools.txt` — список инструментов для `bootstrap.sh` и `doctor.sh`
  (`имя|пакет Debian|пакет RHEL|бинарник`).

# Требования

Скриптам нужен только `bash` и стандартные утилиты (`cp`, `grep`, `mktemp`,
`git`, `curl`). Остальное — по желанию, в зависимости от того, что собираешь
и куда ставишь.

| Компонент | Debian/Ubuntu | CentOS/AlmaLinux |
|---|---|---|
| zsh, git, curl | `zsh git curl` | `zsh git curl` |
| сбор снимка | `dconf-cli gnome-shell` | `dconf gnome-shell` |
| dconf на приёмнике | `dconf-cli libglib2.0-bin` | `dconf glib2` |
| micro, guake, flameshot | `micro guake flameshot` | обычно Flatpak/EPEL |
| xbindkeys, wmctrl | `xbindkeys wmctrl` | `xbindkeys wmctrl` |

`dconf-cli`/`dconf` даёт `dconf`, `libglib2.0-bin`/`glib2` — `gsettings`,
`gdbus` и `dbus-send` (в части дистрибутивов `dbus-send` лежит в `dbus-tools`).
`gdbus` нужен только для проверки шины; если его нет, проверяется наличие
сокета шины.

`collect.sh` запускается на GNOME-машине и требует `dconf`, `gnome-shell` и
`gnome-extensions`. `deploy.sh` работает и без GNOME: если нет `dconf` или
сессионной шины, dconf-часть пропускается, файлы применяются как обычно.

# Сбор настроек (collect.sh)

Выполняется на машине-источнике, обычно на ноутбуке:

```bash
cd ~/projects/env
./scripts/collect.sh
```

Что происходит:

1. Снимок собирается во временный каталог `.snapshot.XXXXXX` рядом с репозиторием.
2. Проверяются персональные данные (см. ниже). При находке сбор прерывается,
   старый `snapshot/` остаётся нетронутым.
3. Только после успешной проверки временный каталог подменяет `snapshot/`.
4. Корневой `.zshrc` синхронизируется с `snapshot/home/.zshrc`.

## Проверка на персональные данные

Снимок публикуется, поэтому `collect.sh` сканирует его перед публикацией.
Находки делятся на две группы.

Прерывают сбор (жёсткие):

- IPv4-адреса и `lan://`;
- домашние каталоги `/home/<пользователь>/`, `/Users/<пользователь>/`, `/root/`;
- приватные ключи и сертификаты (`BEGIN ... PRIVATE KEY`, `BEGIN CERTIFICATE`);
- токены: AWS (`AKIA…`/`ASIA…`), GitHub (`ghp_…`, `github_pat_…`),
  GitLab (`glpat-…`), Slack (`xox…`), OpenAI-подобные (`sk-…`), Google API (`AIza…`);
- данные GSConnect/KDE Connect (`gsconnect/device`, `kdeconnect.`);
- имя текущей машины (короткое и полное);
- имя пользователя в именах файлов.

Только предупреждают (сбор продолжается):

- MAC-адреса устройств;
- строки вида `password=`, `token:`, `api_key=`;
- адреса электронной почты (кроме `git@` и `noreply@`); проверяются только
  домашние конфиги и dconf — UUID расширений GNOME вида `name@domain`
  предупреждением не считаются.

Если находка ожидаема (например, в конфиге намеренно лежит e-mail), сбор можно
выполнить с явным подтверждением:

```bash
./scripts/collect.sh --force
```

`--force` отключает **обе** проверки целиком, поэтому применять его стоит
только осознанно: снимок уходит в открытый репозиторий.

# Развёртывание настроек (deploy.sh)

Снимок уже лежит в репозитории, поэтому на целевой машине достаточно скопировать
репозиторий (или скачать архив) и выполнить:

```bash
./scripts/deploy.sh --dry-run   # показать план
./scripts/deploy.sh --apply     # применить и создать бэкап
```

Скрипт:

- копирует файлы из `snapshot/home/` в `$HOME`, создавая бэкап существующих;
- загружает дампы dconf (`dconf load`);
- создаёт бэкап в `${XDG_STATE_HOME:-$HOME/.local/state}/env/backups/<дата>.XXXXXX`;
- печатает итог: сколько применено, сколько пропущено.

Если `manifests/` расходится с копиями манифестов внутри `snapshot/`, скрипт
предупредит, что снимок устарел, — значит, `collect.sh` не перезапускали.

Код возврата: `0` — успех (включая пропуск dconf на headless), `1` — ошибка
применения dconf или некорректный вызов.

## Поведение на headless-системах

dconf пишет в базу через сервис `ca.desrt.dconf`, поэтому ему нужна живая
сессионная шина D-Bus. Если её нет, деплой **не падает**: настройки dconf
пропускаются с понятной причиной, а файлы копируются как обычно.

Причины пропуска dconf:

- `dconf` не установлен;
- нет доступной сессионной шины D-Bus (сервер, контейнер, ssh без сессии);
- в снимке нет дампа для конкретного пути.

Схемы gsettings намеренно не проверяются: схемы пользовательских расширений
GNOME (gTile, tiling-assistant) лежат в каталоге самого расширения и не видны
`gsettings list-schemas`, а `dconf load` пишет ключи без валидации схем. Проверка
по схемам давала бы ложный пропуск на машинах, где расширение установлено.

Если во время `--apply` dconf-настройка не применилась при живой шине, скрипт
сообщит об ошибке и завершится с кодом 1 — это настоящая ошибка, а не headless.

## Бэкап и `previously-absent.txt`

В каталоге бэкапа лежат:

- `home/…` — прежние версии перезаписанных файлов;
- `dconf/*.ini` — прежние значения затронутых путей dconf;
- `dconf-paths.txt` — какие пути dconf затрагивались;
- `previously-absent.txt` — пути, которых **до деплоя не было** (файл или
  каталог создан с нуля, а не перезаписан).

`previously-absent.txt` — только диагностика: он показывает, что именно деплой
добавил на машину. Восстановление из него не делается, `snapshot` считается
источником истины.

## Быстрый деплой одной командой

Скачивает архив во временную папку, применяет настройки и удаляет папку:

```bash
d=$(mktemp -d /tmp/env-deploy.XXXXXX) && curl -fsSL https://github.com/Suntechnic/env/archive/refs/heads/main.tar.gz | tar -xz -C "$d" --strip-components=1 && "$d"/scripts/deploy.sh --apply; rm -rf "$d"
```

Для предварительного просмотра замените `--apply` на `--dry-run`.

# Установка пакетов (bootstrap.sh)

Ставит инструменты из [manifests/tools.txt](manifests/tools.txt): zsh, git,
screen, htop, micro, curl, ufw, netcat, dig, ranger, ripgrep.

```bash
./scripts/bootstrap.sh --dry-run   # показать план, ничего не меняя
./scripts/bootstrap.sh             # спросит подтверждение
./scripts/bootstrap.sh --yes       # без вопросов
```

Повторный запуск безопасен: уже установленное пропускается. Скрипт сам
определяет семейство дистрибутива и менеджер пакетов (`apt-get`, `dnf`/`yum`).

- `--no-update` — не обновлять индекс пакетов;
- `--epel` — включить EPEL на CentOS/AlmaLinux (оттуда ставятся htop, ranger,
  ripgrep, ufw);
- `micro` в RHEL-репозиториях отсутствует, поэтому при неудаче ставится
  статический бинарник из официальных релизов GitHub в `~/.local/bin`
  (или в `/usr/local/bin`, если запущено от root).

Часть имён пакетов различается: `netcat-openbsd` → `nmap-ncat`,
`dnsutils` → `bind-utils`. Если какой-то пакет поставить не удалось, скрипт
покажет команду для ручной установки и завершится с кодом 1.

# Диагностика (doctor.sh)

```bash
./scripts/doctor.sh
```

Показывает, что реально работает на этой машине:

- ОС, ядро, семейство дистрибутива, контейнер;
- графическая сессия (wayland/x11/tty), D-Bus и доступность dconf;
- инструменты из `manifests/tools.txt` и GUI-утилиты;
- состояние снимка: состав, совпадение `manifests/` со `snapshot/`, версия
  GNOME и дистрибутив, на которых он собран;
- расхождения между снимком и текущим `$HOME` (файлы и dconf);
- локаль: предупредит, если она не UTF-8.

Скрипт только читает и ничего не меняет. Расхождения в списке «Отличается» и
«Нет в `$HOME`» — повод выполнить `./scripts/deploy.sh --dry-run`.

# Пример работы

```bash
# На машине-источнике
cd ~/projects/env
./scripts/collect.sh
git add -A && git commit -m "Обновление снимка" && git push

# На целевой машине
d=$(mktemp -d /tmp/env-deploy.XXXXXX) && curl -fsSL https://github.com/Suntechnic/env/archive/refs/heads/main.tar.gz | tar -xz -C "$d" --strip-components=1 && "$d"/scripts/deploy.sh --apply; rm -rf "$d"
```

# Ограничения

- `deploy.sh` не ставит пакеты, он только раскладывает конфиги. Для установки
  базовых инструментов есть `scripts/bootstrap.sh`; расширения GNOME
  автоматически не устанавливаются — без них настройки просто не прочитаются.
- Настройки, которых нет в системе (Guake, gTile, tiling-assistant, xbindkeys),
  остаются «мёртвыми» — это нормально для машин без GUI.
- Для части настроек GNOME нужен выход из сеанса.
- Секреты в репозиторий не попадают: ключи, токены и пароли отсекает
  `collect.sh`. Если нужен локальный секрет — держи его в `~/.zshrc.local`
  или в файле вне репозитория.
