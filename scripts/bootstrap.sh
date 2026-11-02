#!/usr/bin/env bash
set -euo pipefail

usage () {
    cat <<'EOF'
Использование: bootstrap.sh [--dry-run] [--yes] [--no-update] [--epel]

Ставит базовый набор CLI-инструментов из manifests/tools.txt.
Поддерживаются Debian/Ubuntu (apt-get) и CentOS/AlmaLinux (dnf/yum).

  --dry-run    показать план, ничего не устанавливая
  --yes, -y    не спрашивать подтверждения
  --no-update  не обновлять индекс пакетов
  --epel       включить EPEL на CentOS/AlmaLinux (для части пакетов)
EOF
}

DRY_RUN=0
ASSUME_YES=0
NO_UPDATE=0
ENABLE_EPEL=0

while (( $# )); do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --yes|-y) ASSUME_YES=1 ;;
        --no-update) NO_UPDATE=1 ;;
        --epel) ENABLE_EPEL=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
    shift
done

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_FILE="$ROOT/manifests/tools.txt"
[[ -f "$TOOLS_FILE" ]] || {
    echo "Нет $TOOLS_FILE" >&2
    exit 1
}

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
fi

case " ${ID:-} ${ID_LIKE:-} " in
    *debian*|*ubuntu*) FAMILY=deb ;;
    *rhel*|*centos*|*almalinux*|*rocky*|*fedora*|*ol*) FAMILY=rhel ;;
    *)
        echo "Неизвестный дистрибутив (ID=${ID:-?})." >&2
        echo "Поддерживаются Debian/Ubuntu и CentOS/AlmaLinux." >&2
        exit 1
        ;;
esac

if [[ "$FAMILY" == deb ]]; then
    PKG=apt-get
else
    PKG="$(command -v dnf || command -v yum || true)"
fi
if [[ -z "${PKG:-}" ]] || ! command -v "$PKG" >/dev/null 2>&1; then
    echo "Не найден менеджер пакетов (apt-get/dnf/yum)." >&2
    exit 1
fi

if (( EUID == 0 )); then
    SUDO=()
    BIN_DIR=/usr/local/bin
else
    command -v sudo >/dev/null 2>&1 || {
        echo "Нужен sudo или запуск от root." >&2
        exit 1
    }
    SUDO=(sudo)
    BIN_DIR="$HOME/.local/bin"
fi

run () {
    if (( DRY_RUN )); then
        printf '  + %s\n' "$*"
    else
        "$@"
    fi
}

has_tool () {
    command -v "$1" >/dev/null 2>&1 && return 0
    [[ -x "$BIN_DIR/$1" ]]
}

install_pkg () {
    local pkg="$1"

    case "$FAMILY" in
        deb)
            run "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive \
                apt-get install -y "$pkg"
            ;;
        rhel)
            run "${SUDO[@]}" "$PKG" install -y "$pkg"
            ;;
    esac
}

# micro есть в Debian/Ubuntu, но отсутствует в репозиториях RHEL-семейства.
# Резервный путь — статический бинарник из официальных релизов на GitHub.
install_micro_binary () {
    local arch version url tmp

    case "$(uname -m)" in
        x86_64|amd64) arch=linux64 ;;
        aarch64|arm64) arch=linux-arm64 ;;
        armv7l|armhf) arch=linux-arm ;;
        *)
            echo "micro: неизвестная архитектура $(uname -m)" >&2
            return 1
            ;;
    esac

    command -v curl >/dev/null 2>&1 || {
        echo "micro: для загрузки нужен curl" >&2
        return 1
    }

    version="$(
        curl -fsSL --max-time 30 \
            https://api.github.com/repos/zyedidia/micro/releases/latest 2>/dev/null \
            | grep -m1 '"tag_name"' \
            | sed -E 's/.*"v?([^"]+)".*/\1/' || true
    )"
    if [[ -z "$version" ]]; then
        echo "micro: не удалось определить последнюю версию" >&2
        return 1
    fi

    url="https://github.com/zyedidia/micro/releases/download/v${version}/micro-${version}-${arch}.tar.gz"
    tmp="$(mktemp -d)"
    if ! curl -fsSL --max-time 120 "$url" -o "$tmp/micro.tar.gz"; then
        rm -rf -- "$tmp"
        echo "micro: не удалось скачать $url" >&2
        return 1
    fi
    if ! tar -xzf "$tmp/micro.tar.gz" -C "$tmp"; then
        rm -rf -- "$tmp"
        echo "micro: не удалось распаковать архив" >&2
        return 1
    fi
    if [[ ! -x "$tmp/micro-${version}/micro" ]]; then
        rm -rf -- "$tmp"
        echo "micro: в архиве нет бинарника" >&2
        return 1
    fi

    mkdir -p "$BIN_DIR"
    install -m 755 "$tmp/micro-${version}/micro" "$BIN_DIR/micro"
    rm -rf -- "$tmp"
    echo "micro: установлен в $BIN_DIR/micro"
}

declare -a PRESENT=()
declare -a MISSING=()
declare -a PLANNED=()

while IFS='|' read -r name apt_pkg dnf_pkg binary; do
    [[ -z "$name" || "$name" == \#* ]] && continue

    case "$FAMILY" in
        deb) pkg="$apt_pkg" ;;
        rhel) pkg="$dnf_pkg" ;;
    esac

    if has_tool "$binary"; then
        PRESENT+=("$name|$(command -v "$binary" 2>/dev/null || echo "$BIN_DIR/$binary")")
        continue
    fi

    if (( DRY_RUN )); then
        PLANNED+=("$name|$pkg")
    else
        MISSING+=("$name|$pkg|$binary")
    fi
done < "$TOOLS_FILE"

if (( DRY_RUN )); then
    if (( ${#PLANNED[@]} == 0 )); then
        echo "Всё уже установлено (${#PRESENT[@]} инструментов)."
        exit 0
    fi

    echo "Будет установлено:"
    for entry in "${PLANNED[@]}"; do
        IFS='|' read -r name pkg <<< "$entry"
        printf '  %-10s %s install %s\n' "$name" "$PKG" "$pkg"
    done
    echo "Ничего не изменено (--dry-run)."
    exit 0
fi

if (( ${#MISSING[@]} == 0 )); then
    echo "Всё уже установлено (${#PRESENT[@]} инструментов)."
    exit 0
fi

echo "Не установлено: ${#MISSING[@]} из $(( ${#PRESENT[@]} + ${#MISSING[@]} ))"
for entry in "${MISSING[@]}"; do
    IFS='|' read -r name pkg _ <<< "$entry"
    printf '  %-10s %s\n' "$name" "$pkg"
done

if (( ! ASSUME_YES )); then
    if [[ -t 0 ]]; then
        printf 'Установить? [y/N] '
        read -r answer
        case "$answer" in
            y|Y|yes|YES) ;;
            *) echo "Отменено."; exit 0 ;;
        esac
    else
        echo "Нет интерактивного ввода: запусти с --yes." >&2
        exit 2
    fi
fi

if (( ENABLE_EPEL )) && [[ "$FAMILY" == rhel ]]; then
    echo "Включаю EPEL..."
    run "${SUDO[@]}" "$PKG" install -y epel-release || \
        echo "EPEL включить не удалось, продолжаю без него." >&2
fi

if (( ! NO_UPDATE )); then
    echo "Обновляю индекс пакетов..."
    case "$FAMILY" in
        deb)
            run "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get update || \
                echo "apt-get update завершился с ошибкой, продолжаю." >&2
            ;;
        rhel)
            run "${SUDO[@]}" "$PKG" -y makecache || \
                echo "makecache завершился с ошибкой, продолжаю." >&2
            ;;
    esac
fi

declare -a FAILED=()

for entry in "${MISSING[@]}"; do
    IFS='|' read -r name pkg binary <<< "$entry"
    printf '→ %s (%s)\n' "$name" "$pkg"

    if ! install_pkg "$pkg"; then
        if [[ "$name" == micro ]]; then
            echo "  пакет micro недоступен, ставлю бинарник с GitHub..." >&2
            install_micro_binary || {
                FAILED+=("$name|$pkg")
                continue
            }
        else
            FAILED+=("$name|$pkg")
            continue
        fi
    fi

    if ! has_tool "$binary"; then
        FAILED+=("$name|$pkg")
    fi
done

echo
if (( ${#FAILED[@]} == 0 )); then
    echo "Готово: установлено ${#MISSING[@]}, уже было ${#PRESENT[@]}."
    exit 0
fi

echo "Не удалось поставить ${#FAILED[@]} из ${#MISSING[@]}:" >&2
for entry in "${FAILED[@]}"; do
    IFS='|' read -r name pkg <<< "$entry"
    printf '  %-10s %s\n' "$name" "$pkg" >&2
    case "$FAMILY" in
        deb) printf '             вручную: sudo apt-get install %s\n' "$pkg" >&2 ;;
        rhel) printf '             вручную: sudo %s install %s\n' "$PKG" "$pkg" >&2 ;;
    esac
done
if [[ "$FAMILY" == rhel ]]; then
    echo "Для части пакетов (htop, ranger, ripgrep, ufw) может понадобиться EPEL: --epel" >&2
fi
if [[ " ${FAILED[*]} " == *micro* ]]; then
    echo "micro можно поставить вручную: https://github.com/zyedidia/micro/releases" >&2
fi

exit 1
