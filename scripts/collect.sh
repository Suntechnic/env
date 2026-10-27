#!/usr/bin/env bash
set -euo pipefail
umask 077

[[ $EUID -ne 0 ]] || {
    echo "Запусти обычным пользователем, без sudo." >&2
    exit 1
}

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/snapshot"

for cmd in dconf gnome-extensions gnome-shell; do
    command -v "$cmd" >/dev/null || {
        echo "Не найдена команда: $cmd" >&2
        exit 1
    }
done

TMP="$(mktemp -d "$ROOT/.snapshot.XXXXXX")"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/home" "$TMP/dconf" "$TMP/extensions" "$TMP/metadata"

cp "$ROOT/manifests/files.txt" "$TMP/files.txt"
cp "$ROOT/manifests/dconf-paths.txt" "$TMP/dconf-paths.txt"

while IFS= read -r path || [[ -n "$path" ]]; do
    [[ -z "$path" || "$path" == \#* ]] && continue
    [[ "$path" != /* && "$path" != *..* ]] || exit 1

    if [[ -f "$HOME/$path" ]]; then
        mkdir -p "$TMP/home/$(dirname -- "$path")"
        cp -L -- "$HOME/$path" "$TMP/home/$path"
    else
        echo "Пропущен отсутствующий файл: $path"
    fi
done < "$TMP/files.txt"

while IFS= read -r path || [[ -n "$path" ]]; do
    [[ -z "$path" || "$path" == \#* ]] && continue
    [[ "$path" == /*/ && "$path" != *..* ]] || exit 1
    name="${path//\//_}"
    dconf dump "$path" > "$TMP/dconf/$name.ini"
done < "$TMP/dconf-paths.txt"

gnome-extensions list | sort > "$TMP/extensions/installed.txt"
gnome-extensions list --enabled | sort > "$TMP/extensions/enabled.txt"
gnome-shell --version > "$TMP/metadata/gnome.txt"
cp /etc/os-release "$TMP/metadata/os-release"

if [[ -e "$DEST" ]]; then
    PREVIOUS="$(mktemp -d "$ROOT/.snapshot-previous.XXXXXX")"
    mv -- "$DEST" "$PREVIOUS/snapshot"
    echo "Предыдущий сбор сохранён: $PREVIOUS"
fi

mv -- "$TMP" "$DEST"
trap - EXIT

echo "Настройки собраны. Проверь перед коммитом:"
git -C "$ROOT" status --short
git -C "$ROOT" diff --stat
