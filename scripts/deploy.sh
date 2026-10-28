#!/usr/bin/env bash
set -euo pipefail
umask 077

MODE="${1:---dry-run}"
[[ "$MODE" == "--dry-run" || "$MODE" == "--apply" ]] || {
    echo "Использование: $0 [--dry-run|--apply]" >&2
    exit 1
}

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/snapshot"
[[ -d "$SRC" ]] || {
    echo "Нет snapshot. Сначала выполни collect.sh на ноутбуке." >&2
    exit 1
}

HAS_DCONF=1
command -v dconf >/dev/null || {
    HAS_DCONF=0
    echo "dconf не найден, настройки dconf пропущены."
}

if [[ -f "$SRC/metadata/gnome.txt" ]]; then
    echo "Источник: $(cat "$SRC/metadata/gnome.txt")"
fi
if command -v gnome-shell >/dev/null; then
    echo "Приёмник: $(gnome-shell --version)"
else
    echo "gnome-shell не найден."
fi
echo "Расширения и зависимости автоматически не устанавливаются."

BACKUP=""
if [[ "$MODE" == "--apply" ]]; then
    STATE="${XDG_STATE_HOME:-$HOME/.local/state}/env/backups"
    mkdir -p "$STATE"
    BACKUP="$(mktemp -d "$STATE/$(date +%F-%H%M%S).XXXXXX")"
    mkdir -p "$BACKUP/home" "$BACKUP/dconf"
    cp "$SRC/dconf-paths.txt" "$BACKUP/dconf-paths.txt"
fi

while IFS= read -r path || [[ -n "$path" ]]; do
    [[ -z "$path" || "$path" == \#* ]] && continue
    [[ "$path" != /* && "$path" != *..* ]] || exit 1
    if [[ "$path" == */ ]]; then
        rel="${path%/}"
        [[ -d "$SRC/home/$rel" ]] || continue

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
        continue
    fi

    [[ -f "$SRC/home/$path" ]] || continue

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
        cp -- "$SRC/home/$path" "$tmp"
        mv -fT -- "$tmp" "$HOME/$path"
    fi
done < "$SRC/files.txt"

if [[ "$HAS_DCONF" == 1 ]]; then
    while IFS= read -r path || [[ -n "$path" ]]; do
        [[ -z "$path" || "$path" == \#* ]] && continue
        [[ "$path" == /*/ && "$path" != *..* ]] || exit 1
        name="${path//\//_}"
        file="$SRC/dconf/$name.ini"
        [[ -f "$file" ]] || {
            echo "Нет дампа: $file" >&2
            exit 1
        }

        echo "dconf: $path"
        if [[ "$MODE" == "--apply" ]]; then
            dconf dump "$path" > "$BACKUP/dconf/$name.ini"
            dconf load "$path" < "$file"
        fi
    done < "$SRC/dconf-paths.txt"
fi

if [[ "$MODE" == "--apply" ]]; then
    echo "Готово. Бэкап: $BACKUP"
    echo "Для полного применения может потребоваться выход из сеанса."
else
    echo "Это только план. Для применения: $0 --apply"
fi
