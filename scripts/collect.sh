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

    if [[ "$path" == */ ]]; then
        rel="${path%/}"
        if [[ -d "$HOME/$rel" ]]; then
            mkdir -p "$TMP/home/$(dirname -- "$rel")"
            cp -RL -- "$HOME/$rel" "$TMP/home/$(dirname -- "$rel")/"
        else
            echo "Пропущена отсутствующая папка: $path"
        fi
    elif [[ -f "$HOME/$path" ]]; then
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

# Защита от утечки: снимок в репозитории не должен содержать адреса, пути,
# сертификаты, ключи и имена машин/устройств. При совпадении сбор прерывается.
leak_pattern='([0-9]{1,3}\.){3}[0-9]{1,3}|/home/[^/[:space:]]+/|BEGIN [A-Z ]*(KEY|CERTIFICATE)|lan://|gsconnect/device|kdeconnect\.|PRIVATE KEY'
if grep -rEi -- "$leak_pattern" "$TMP"; then
    echo "Найдены возможные персональные данные (см. выше), сбор прерван." >&2
    exit 1
fi
if grep -rFi -- "$(hostname)" "$TMP"; then
    echo "Найдено имя этой машины (см. выше), сбор прерван." >&2
    exit 1
fi

rm -rf -- "$DEST"
mv -- "$TMP" "$DEST"
trap - EXIT

echo "Настройки собраны. Проверь перед коммитом:"
git -C "$ROOT" status --short
git -C "$ROOT" diff --stat
