# CLI (программы всех систем)

## zsh

```bash
wget https://raw.githubusercontent.com/Suntechnic/env/refs/heads/main/.zshrc -O ~/.zshrc;
```

# GUI (программы десктопа)

## gTitle

### Экспорт в главной системе

```bash
dconf dump /org/gnome/shell/extensions/gtile/ > ~/projects/env/dconf/org-gnome-shell-extensions-gtile.ini
```

### Импорт

```bash
wget https://raw.githubusercontent.com/Suntechnic/env/refs/heads/main/dconf/org-gnome-shell-extensions-gtile.ini -O /tmp/org-gnome-shell-extensions-gtile.ini;
dconf load /org/gnome/shell/extensions/gtile/ < /tmp/org-gnome-shell-extensions-gtile.ini;
```

## Guake

### Экспорт в главной системе

```bash
guake --save-preferences="~/projects/env$/guake/preferences.conf"
```

### Импорт

```bash
wget https://raw.githubusercontent.com/Suntechnic/env/refs/heads/main/guake/preferences.conf -O /tmp/preferences.conf;
guake --restore-preferences="/tmp/preferences.conf"
```

# Сбор и развертывание настроек (collect/deploy)

Этот репозиторий включает скрипты `scripts/collect.sh` и `scripts/deploy.sh` для сбора настроек с локальной машины и их развертывания на целевой машине (например, удаленном компьютере).

## Сбор настроек (collect.sh)

Выполните `scripts/collect.sh` на машине, с которой хотите собрать настройки (обычно ноутбуке):

```bash
cd ~/projects/env
./scripts/collect.sh
```

Скрипт создает каталог `snapshot/` со следующими файлами:

- `snapshot/home/.zshrc` — конфигурация Zsh.
- `snapshot/dconf/*.ini` — дампы настроек GNOME (keybindings, preferences, media-keys, gtile, guake и т.д.).
- `snapshot/extensions/*.txt` — списки установленных и включенных расширений GNOME.
- `snapshot/metadata/gnome.txt` — версия GNOME Shell.
- `snapshot/metadata/os-release` — информация об ОС.

**Важно:** `collect.sh` теперь проверяет снимок на утечки персональных данных (IP-адреса, пути вида `/home/<пользователь>/`, сертификаты, `lan://`, данные GSConnect/KDE Connect, имя машины) и прерывает выполнение, если что-то обнаружено.

## Развертывание настроек (deploy.sh)

Чтобы применить собранные настройки на целевой машине (например, удаленном компьютере):

1. Скопируйте каталог `snapshot/` на целевую машину (например, через `scp -r ~/projects/env/snapshot user@remote:/path/to/env/`).
2. Перейдите в каталог `env/` на целевой машине:

```bash
cd /path/to/env
```

3. Выполните `scripts/deploy.sh` в режиме dry-run, чтобы увидеть, что будет применено:

```bash
./scripts/deploy.sh --dry-run
```

4. Если всё в порядке, примените настройки:

```bash
./scripts/deploy.sh --apply
```

Скрипт:

- Копирует файлы (например, `~/.zshrc`) в целевую систему, создавая бэкапы.
- Загружает дампы dconf (`*.ini`) в целевую систему.
- Создает каталог бэкапов в `${XDG_STATE_HOME:-$HOME/.local/state}/env/backups/`.

**Примечание:** Развертывание может потребовать выхода из сеанса GNOME для применения некоторых настроек.

## Пример работы

```bash
# На локальной машине (ноутбуке)
cd ~/projects/env
./scripts/collect.sh

# Копируем snapshot на удаленный компьютер
scp -r ~/projects/env/snapshot user@remote:/home/user/projects/env/

# На удаленном компьютере
cd /home/user/projects/env
./scripts/deploy.sh --apply
```
