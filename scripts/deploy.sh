#!/usr/bin/env bash
set -euo pipefail
umask 077

usage () {
    cat <<'EOF'
Использование: deploy.sh [--dry-run|--apply]

  --dry-run  показать, что будет применено (по умолчанию)
  --apply    применить настройки и создать бэкап

Настройки dconf применяются только при живой сессионной шине D-Bus.
На headless-системах (сервер, контейнер, ssh без сессии) они пропускаются,
файлы при этом копируются как обычно.
EOF
}

MODE="${1:---dry-run}"
case "$MODE" in
    --dry-run|--apply) ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
esac

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/snapshot"
[[ -d "$SRC" ]] || {
    echo "Нет snapshot. Сначала выполни collect.sh на ноутбуке." >&2
    exit 1
}
[[ -f "$SRC/files.txt" ]] || {
    echo "Повреждён снимок: нет $SRC/files.txt" >&2
    exit 1
}

# Манифесты и снимок должны быть из одного прогона collect.sh.
for manifest in files.txt dconf-paths.txt; do
    if [[ -f "$ROOT/manifests/$manifest" && -f "$SRC/$manifest" ]] && \
        ! cmp -s -- "$ROOT/manifests/$manifest" "$SRC/$manifest"; then
        echo "Внимание: manifests/$manifest отличается от snapshot/$manifest —" >&2
        echo "снимок устарел, перезапусти collect.sh на машине-источнике." >&2
    fi
done

# dconf пишет в базу через сервис ca.desrt.dconf, поэтому нужна живая
# сессионная шина D-Bus. Без неё (headless) это не ошибка — просто пропуск.
dconf_ping () {
    gdbus call --address "$1" \
        --dest ca.desrt.dconf \
        --object-path /ca/desrt/dconf \
        --method org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1
}

dconf_session_ready () {
    local address socket
    local -a addresses=()

    [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && addresses+=("$DBUS_SESSION_BUS_ADDRESS")
    socket="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus"
    addresses+=("unix:path=$socket")

    if command -v gdbus >/dev/null 2>&1; then
        for address in "${addresses[@]}"; do
            dconf_ping "$address" && return 0
        done

        return 1
    fi

    # Проверить сервис нечем — достаточно, чтобы существовал сокет шины.
    [[ -S "$socket" ]]
}

DCONF_OK=0
DCONF_SKIP_REASON=''
DCONF_FAILED=0

if ! command -v dconf >/dev/null 2>&1; then
    DCONF_SKIP_REASON='dconf не установлен'
elif ! dconf_session_ready; then
    DCONF_SKIP_REASON='нет доступной сессионной шины D-Bus'
else
    DCONF_OK=1
fi

if [[ -f "$SRC/metadata/gnome.txt" ]]; then
    echo "Источник: $(cat "$SRC/metadata/gnome.txt")"
fi
if command -v gnome-shell >/dev/null 2>&1; then
    echo "Приёмник: $(gnome-shell --version 2>/dev/null || echo 'версия неизвестна')"
else
    echo "Приёмник: gnome-shell не найден."
fi
if (( DCONF_OK )); then
    echo "dconf: доступен"
else
    echo "dconf: пропущен — $DCONF_SKIP_REASON"
fi
echo "Расширения и зависимости автоматически не устанавливаются."

BACKUP=''
if [[ "$MODE" == "--apply" ]]; then
    STATE="${XDG_STATE_HOME:-$HOME/.local/state}/env/backups"
    mkdir -p "$STATE"
    BACKUP="$(mktemp -d "$STATE/$(date +%F-%H%M%S).XXXXXX")"
    mkdir -p "$BACKUP/home"
    if (( DCONF_OK )); then
        mkdir -p "$BACKUP/dconf"
    fi
    if [[ -f "$SRC/dconf-paths.txt" ]]; then
        cp -- "$SRC/dconf-paths.txt" "$BACKUP/dconf-paths.txt"
    fi
fi

APPLIED=0
SKIPPED=0

while IFS= read -r path || [[ -n "$path" ]]; do
    [[ -z "$path" || "$path" == \#* ]] && continue
    [[ "$path" != /* && "$path" != *..* ]] || exit 1
    if [[ "$path" == */ ]]; then
        rel="${path%/}"
        if [[ ! -d "$SRC/home/$rel" ]]; then
            echo "Пропущено (нет в снимке): ~/$rel/"
            SKIPPED=$((SKIPPED + 1))
            continue
        fi

        echo "Папка: ~/$rel/"
        if [[ "$MODE" == "--apply" ]]; then
            if [[ -e "$HOME/$rel" || -L "$HOME/$rel" ]]; then
                mkdir -p "$BACKUP/home/$(dirname -- "$rel")"
                cp -a -- "$HOME/$rel" "$BACKUP/home/$(dirname -- "$rel")/"
            else
                echo "$rel/" >> "$BACKUP/previously-absent.txt"
            fi

            mkdir -p "$HOME/$rel"
            cp -a --no-preserve=ownership -- "$SRC/home/$rel/." "$HOME/$rel/"
        fi
        APPLIED=$((APPLIED + 1))
        continue
    fi

    if [[ ! -f "$SRC/home/$path" ]]; then
        echo "Пропущено (нет в снимке): ~/$path"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    echo "Файл: ~/$path"
    if [[ "$MODE" == "--apply" ]]; then
        if [[ -e "$HOME/$path" || -L "$HOME/$path" ]]; then
            mkdir -p "$BACKUP/home/$(dirname -- "$path")"
            cp -a -- "$HOME/$path" "$BACKUP/home/$path"
        else
            echo "$path" >> "$BACKUP/previously-absent.txt"
        fi

        mkdir -p "$HOME/$(dirname -- "$path")"
        tmp="$(mktemp "$HOME/$(dirname -- "$path")/.env-deploy.XXXXXX")"
        cp --preserve=mode -- "$SRC/home/$path" "$tmp"
        mv -fT -- "$tmp" "$HOME/$path"
    fi
    APPLIED=$((APPLIED + 1))
done < "$SRC/files.txt"

if (( DCONF_OK )); then
    if [[ ! -f "$SRC/dconf-paths.txt" ]]; then
        echo "dconf: в снимке нет dconf-paths.txt, пропущено." >&2
    else
        while IFS= read -r path || [[ -n "$path" ]]; do
            [[ -z "$path" || "$path" == \#* ]] && continue
            [[ "$path" == /*/ && "$path" != *..* ]] || exit 1

            name="${path//\//_}"
            file="$SRC/dconf/$name.ini"
            if [[ ! -f "$file" ]]; then
                echo "dconf: нет дампа для $path, пропущено." >&2
                SKIPPED=$((SKIPPED + 1))
                continue
            fi

            echo "dconf: $path"
            if [[ "$MODE" == "--apply" ]]; then
                dconf dump "$path" > "$BACKUP/dconf/$name.ini"
                if ! dconf load "$path" < "$file"; then
                    echo "dconf: не удалось применить $path" >&2
                    DCONF_FAILED=1
                fi
            fi
            APPLIED=$((APPLIED + 1))
        done < "$SRC/dconf-paths.txt"
    fi
fi

if (( DCONF_FAILED )); then
    echo "Не удалось применить часть настроек dconf (см. выше)." >&2
fi

if [[ "$MODE" == "--apply" ]]; then
    echo "Готово. Применено: $APPLIED, пропущено: $SKIPPED. Бэкап: $BACKUP"
    echo "Для полного применения может потребоваться выход из сеанса."
else
    echo "План: применить $APPLIED, пропустить $SKIPPED. Для применения: $0 --apply"
fi

(( DCONF_FAILED == 0 ))
