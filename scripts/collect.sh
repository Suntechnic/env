#!/usr/bin/env bash
set -euo pipefail
umask 077

usage () {
    cat <<'EOF'
Использование: collect.sh [--force]

  --force  собрать снимок, даже если проверка нашла персональные данные.
           Снимок публикуется в открытом репозитории — включай осознанно.
EOF
}

FORCE=0
while (( $# )); do
    case "$1" in
        --force) FORCE=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
    shift
done

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

# Защита от утечки: снимок в публичном репозитории не должен содержать адреса,
# пути, сертификаты, ключи, токены и имена машин/устройств.
# Совпадения из FAIL-списка прерывают сбор; WARN-список только предупреждает.
LEAK_FAIL_PATTERNS=(
    # сеть и адреса
    '([0-9]{1,3}\.){3}[0-9]{1,3}'
    'lan://'
    # домашние каталоги
    '/home/[^/[:space:]]+/'
    '/Users/[^/[:space:]]+/'
    '/root/'
    # ключи и сертификаты
    'BEGIN [A-Z ]*PRIVATE KEY'
    'BEGIN CERTIFICATE'
    # токены облаков и сервисов
    '(AKIA|ASIA)[0-9A-Z]{16}'
    'ghp_[A-Za-z0-9]{36}'
    'github_pat_[A-Za-z0-9_]{20,}'
    'glpat-[A-Za-z0-9_-]{20,}'
    'xox[baprs]-[A-Za-z0-9-]{10,}'
    'sk-[A-Za-z0-9]{20,}'
    'AIza[0-9A-Za-z_-]{35}'
    # синхронизация с телефонами
    'gsconnect/device'
    'kdeconnect\.'
)

LEAK_WARN_PATTERNS=(
    # MAC-адреса устройств
    '([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}'
    # поля с паролями и токенами
    '(password|passwd|secret|token|api[_-]?key)[[:space:]]*[=:]'
)

leak_scan_fail () {
    local pattern host name
    local -i found=0
    local -a names=()

    for pattern in "${LEAK_FAIL_PATTERNS[@]}"; do
        if grep -rEnI -- "$pattern" "$TMP"; then
            printf '  ↑ шаблон: %s\n' "$pattern" >&2
            found=1
        fi
    done

    host="$(hostname -s 2>/dev/null || true)"
    if [[ -n "$host" ]]; then
        names+=("$host")
    fi
    host="$(hostname -f 2>/dev/null || true)"
    if [[ -n "$host" && "$host" != "${names[0]:-}" ]]; then
        names+=("$host")
    fi

    for host in "${names[@]}"; do
        # Короткие и служебные имена дают слишком много ложных срабатываний.
        if (( ${#host} < 3 )) || [[ "$host" == localhost || "$host" == localhost.localdomain ]]; then
            continue
        fi
        if grep -rFIwn -- "$host" "$TMP"; then
            printf '  ↑ имя этой машины: %s\n' "$host" >&2
            found=1
        fi
    done

    if [[ -n "${USER:-}" ]] && (( ${#USER} >= 4 )); then
        # Ищем по путям относительно TMP: абсолютный путь содержит /home/<user>/
        # и давал бы совпадение на каждом файле.
        while IFS= read -r -d '' name; do
            printf '  ↑ имя файла содержит имя пользователя: %s\n' "$name" >&2
            found=1
        done < <( (cd -- "$TMP" && find . -iname "*${USER}*" -print0) 2>/dev/null || true )
    fi

    return "$found"
}

leak_scan_warn () {
    local pattern line

    for pattern in "${LEAK_WARN_PATTERNS[@]}"; do
        while IFS= read -r line; do
            if [[ "$line" != *'git@'* && "$line" != *'noreply@'* ]]; then
                printf '  ⚠ возможно персональные данные: %s\n' "$line" >&2
            fi
        done < <(grep -rEnI -- "$pattern" "$TMP" || true)
    done

    # E-mail ищем только в конфигах: в extensions/*.txt лежат UUID вида
    # name@domain, которые под этот шаблон подходят, но персональными данными
    # не являются.
    while IFS= read -r line; do
        if [[ "$line" != *'git@'* && "$line" != *'noreply@'* ]]; then
            printf '  ⚠ возможно e-mail: %s\n' "$line" >&2
        fi
    done < <(grep -rEnI -- '[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}' \
        "$TMP/home" "$TMP/dconf" 2>/dev/null || true)
}

if (( FORCE )); then
    echo "Проверка на персональные данные отключена (--force)." >&2
else
    leak_scan_warn
    if ! leak_scan_fail; then
        echo "Найдены возможные персональные данные (см. выше), сбор прерван." >&2
        echo "Если они там уместны, запусти: $0 --force" >&2
        exit 1
    fi
fi

rm -rf -- "$DEST"
mv -- "$TMP" "$DEST"
trap - EXIT

# Корневой .zshrc — легаси-копия для машин, которые читают его оттуда.
# Источник истины — snapshot, поэтому копию держим синхронной.
LEGACY_ZSH="$ROOT/.zshrc"
if [[ -f "$LEGACY_ZSH" && -f "$DEST/home/.zshrc" ]] && \
    ! cmp -s -- "$DEST/home/.zshrc" "$LEGACY_ZSH"; then
    cp -- "$DEST/home/.zshrc" "$LEGACY_ZSH"
    echo "Легаси-копия .zshrc в корне обновлена из снимка."
fi

echo "Настройки собраны. Проверь перед коммитом:"
git -C "$ROOT" status --short || true
git -C "$ROOT" diff --stat || true
