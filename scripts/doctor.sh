#!/usr/bin/env bash
set -euo pipefail

usage () {
    cat <<'EOF'
Использование: doctor.sh

Показывает, что реально работает на этой системе: дистрибутив, графическая
сессия и dconf, инструменты из manifests/tools.txt, состояние снимка и
расхождения между снимком и текущим $HOME.

Скрипт только читает и ничего не меняет.
EOF
}

while (( $# )); do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
    shift
done

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/snapshot"
TOOLS_FILE="$ROOT/manifests/tools.txt"

if command -v locale >/dev/null 2>&1 && \
    [[ "$(locale charmap 2>/dev/null || true)" == UTF-8 ]]; then
    OK='✓'
    BAD='✗'
    WARN='⚠'
else
    OK='[ok]'
    BAD='[--]'
    WARN='[!!]'
fi

field () {
    printf '  %-14s %s\n' "$1:" "$2"
}

section () {
    printf '\n== %s ==\n' "$1"
}

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
fi

case " ${ID:-} ${ID_LIKE:-} " in
    *debian*|*ubuntu*) FAMILY=deb ;;
    *rhel*|*centos*|*almalinux*|*rocky*|*fedora*|*ol*) FAMILY=rhel ;;
    *) FAMILY=unknown ;;
esac

case "$FAMILY" in
    deb) PKG=apt-get ;;
    rhel) PKG="$(command -v dnf || command -v yum || true)" ;;
    *) PKG='' ;;
esac
PKG="${PKG:-?}"

CONTAINER='нет'
if [[ -f /.dockerenv ]]; then
    CONTAINER='docker'
elif command -v systemd-detect-virt >/dev/null 2>&1; then
    CONTAINER="$(systemd-detect-virt --container 2>/dev/null || true)"
    [[ -z "$CONTAINER" || "$CONTAINER" == none ]] && CONTAINER='нет'
fi

dconf_ready () {
    command -v dconf >/dev/null 2>&1 || return 1

    local socket address
    local -a addresses=()
    socket="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus"

    if command -v gdbus >/dev/null 2>&1; then
        [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && addresses+=("$DBUS_SESSION_BUS_ADDRESS")
        addresses+=("unix:path=$socket")
        for address in "${addresses[@]}"; do
            if gdbus call --address "$address" \
                --dest ca.desrt.dconf \
                --object-path /ca/desrt/dconf \
                --method org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1; then
                return 0
            fi
        done

        return 1
    fi

    [[ -S "$socket" ]]
}

has_tool () {
    command -v "$1" >/dev/null 2>&1 && return 0
    [[ -x "$HOME/.local/bin/$1" ]]
}

section "Система"
field "ОС" "${PRETTY_NAME:-${ID:-неизвестно}}"
field "Ядро" "$(uname -r) ($(uname -m))"
field "Семейство" "$FAMILY ($PKG)"
field "Пользователь" "$(id -un) (uid $(id -u))"
field "Shell" "$(basename -- "${SHELL:-?}")"
field "Zsh" "$(zsh --version 2>/dev/null || echo 'не установлен')"
field "Контейнер" "$CONTAINER"

section "Графическая сессия"
if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    SESSION='wayland'
elif [[ -n "${DISPLAY:-}" ]]; then
    SESSION='x11'
else
    SESSION='tty (графической сессии нет)'
fi
field "Сессия" "$SESSION"
field "Рабочий стол" "${XDG_CURRENT_DESKTOP:-не определён}"
field "GNOME Shell" "$(gnome-shell --version 2>/dev/null || echo 'не установлен')"

if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    field "D-Bus" "есть ($DBUS_SESSION_BUS_ADDRESS)"
elif [[ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus" ]]; then
    field "D-Bus" "есть (сокет сессионной шины)"
else
    field "D-Bus" "нет"
fi

DCONF_READY=0
if dconf_ready; then
    DCONF_READY=1
    field "dconf" "$OK доступен, настройки GNOME применятся"
else
    field "dconf" "$WARN недоступен, настройки GNOME будут пропущены при деплое"
fi

section "Инструменты"
TOOLS_TOTAL=0
TOOLS_MISSING=0

if [[ ! -f "$TOOLS_FILE" ]]; then
    echo "  $WARN нет $TOOLS_FILE"
else
    while IFS='|' read -r name apt_pkg dnf_pkg binary; do
        [[ -z "$name" || "$name" == \#* ]] && continue

        case "$FAMILY" in
            deb) pkg="$apt_pkg" ;;
            rhel) pkg="$dnf_pkg" ;;
            *) pkg="$apt_pkg" ;;
        esac

        TOOLS_TOTAL=$((TOOLS_TOTAL + 1))
        if has_tool "$binary"; then
            printf '  %s %-10s %s\n' "$OK" "$name" "$(command -v "$binary" 2>/dev/null || echo "$HOME/.local/bin/$binary")"
        else
            TOOLS_MISSING=$((TOOLS_MISSING + 1))
            printf '  %s %-10s нет (%s install %s)\n' "$BAD" "$name" "$PKG" "$pkg"
        fi
    done < "$TOOLS_FILE"
fi

echo
echo "  дополнительно (нужно только на машине с GUI):"
for tool in dconf gsettings gnome-shell gnome-extensions guake flameshot xbindkeys wmctrl; do
    if has_tool "$tool"; then
        printf '  %s %-16s %s\n' "$OK" "$tool" "$(command -v "$tool" 2>/dev/null || echo "$HOME/.local/bin/$tool")"
    else
        printf '  %s %-16s нет\n' "$BAD" "$tool"
    fi
done

if command -v gnome-extensions >/dev/null 2>&1; then
    ENABLED_EXT="$(gnome-extensions list --enabled 2>/dev/null || true)"
    for ext in 'gTile@' 'tiling-assistant@'; do
        if grep -qE "^${ext//./\\.}" <<< "$ENABLED_EXT"; then
            printf '  %s расширение %s включено\n' "$OK" "${ext%@}"
        else
            printf '  %s расширение %s не включено\n' "$WARN" "${ext%@}"
        fi
    done
fi

SNAP_STALE=0
SNAP_PRESENT=0
SNAP_FILES=0
SNAP_DCONF=0
DCONF_WITHOUT_DUMP=0
SAME=0
DIFFER=0
ABSENT=0
NOT_IN_SNAP=0

section "Снимок"
if [[ ! -d "$SRC" ]]; then
    echo "  $WARN снимка нет — выполни ./scripts/collect.sh на машине-источнике"
elif [[ ! -f "$SRC/files.txt" ]]; then
    echo "  $WARN каталог snapshot есть, но в нём нет files.txt — снимок повреждён"
else
    SNAP_PRESENT=1

    if [[ -d "$SRC/home" ]]; then
        SNAP_FILES="$(find "$SRC/home" -type f 2>/dev/null | wc -l)"
    fi
    if [[ -d "$SRC/dconf" ]]; then
        SNAP_DCONF="$(find "$SRC/dconf" -name '*.ini' -type f 2>/dev/null | wc -l)"
    fi

    field "Содержимое" "$SNAP_FILES файлов, $SNAP_DCONF путей dconf"
    if [[ -f "$SRC/metadata/gnome.txt" ]]; then
        field "Собран на" "$(cat "$SRC/metadata/gnome.txt")"
    fi
    if [[ -f "$SRC/metadata/os-release" ]]; then
        SOURCE_OS="$(
            # shellcheck disable=SC1091
            (. "$SRC/metadata/os-release" && printf '%s' "${PRETTY_NAME:-неизвестно}") 2>/dev/null || true
        )"
        field "Дистрибутив" "${SOURCE_OS:-неизвестно}"
    fi

    for manifest in files.txt dconf-paths.txt; do
        if [[ -f "$ROOT/manifests/$manifest" && -f "$SRC/$manifest" ]]; then
            if cmp -s -- "$ROOT/manifests/$manifest" "$SRC/$manifest"; then
                field "Манифест" "$OK $manifest совпадает"
            else
                field "Манифест" "$WARN $manifest отличается — снимок устарел"
                SNAP_STALE=1
            fi
        fi
    done
fi

if (( SNAP_PRESENT )); then
    section "Конфиги в \$HOME"
    MISMATCH=()

    while IFS= read -r path || [[ -n "$path" ]]; do
        [[ -z "$path" || "$path" == \#* ]] && continue

        if [[ "$path" == */ ]]; then
            rel="${path%/}"
            if [[ ! -d "$SRC/home/$rel" ]]; then
                NOT_IN_SNAP=$((NOT_IN_SNAP + 1))
            elif [[ ! -e "$HOME/$rel" ]]; then
                ABSENT=$((ABSENT + 1))
                MISMATCH+=("нет в \$HOME: $path")
            elif diff -rq -- "$SRC/home/$rel" "$HOME/$rel" >/dev/null 2>&1; then
                SAME=$((SAME + 1))
            else
                DIFFER=$((DIFFER + 1))
                MISMATCH+=("отличается: $path")
            fi
            continue
        fi

        if [[ ! -f "$SRC/home/$path" ]]; then
            NOT_IN_SNAP=$((NOT_IN_SNAP + 1))
        elif [[ ! -e "$HOME/$path" ]]; then
            ABSENT=$((ABSENT + 1))
            MISMATCH+=("нет в \$HOME: $path")
        elif cmp -s -- "$SRC/home/$path" "$HOME/$path"; then
            SAME=$((SAME + 1))
        else
            DIFFER=$((DIFFER + 1))
            MISMATCH+=("отличается: $path")
        fi
    done < "$SRC/files.txt"

    field "Совпадает" "$SAME"
    field "Отличается" "$DIFFER"
    field "Нет в \$HOME" "$ABSENT"
    field "Нет в снимке" "$NOT_IN_SNAP"

    for line in "${MISMATCH[@]}"; do
        printf '    - %s\n' "$line"
    done

    section "Настройки dconf"
    if (( ! DCONF_READY )); then
        echo "  $WARN проверить нельзя: dconf недоступен (это нормально для headless)"
    elif [[ ! -f "$SRC/dconf-paths.txt" ]]; then
        echo "  $WARN в снимке нет dconf-paths.txt"
    else
        DSAME=0
        DDIFFER=0
        while IFS= read -r path || [[ -n "$path" ]]; do
            [[ -z "$path" || "$path" == \#* ]] && continue

            file="$SRC/dconf/${path//\//_}.ini"
            if [[ ! -f "$file" ]]; then
                DCONF_WITHOUT_DUMP=$((DCONF_WITHOUT_DUMP + 1))
                printf '  %s нет дампа: %s\n' "$WARN" "$path"
                continue
            fi
            if diff -q <(dconf dump "$path" 2>/dev/null) "$file" >/dev/null 2>&1; then
                DSAME=$((DSAME + 1))
            else
                DDIFFER=$((DDIFFER + 1))
                printf '  %s отличается: %s\n' "$WARN" "$path"
            fi
        done < "$SRC/dconf-paths.txt"

        field "Совпадает" "$DSAME"
        field "Отличается" "$DDIFFER"
    fi
fi

section "Локаль"
CHARMAP="$(locale charmap 2>/dev/null || true)"
field "LANG" "${LANG:-не задан}"
field "charmap" "${CHARMAP:-неизвестно}"
if [[ "$CHARMAP" == UTF-8 ]]; then
    echo "  $OK приглашение и сообщения в UTF-8 отобразятся корректно"
else
    echo "  $WARN не UTF-8: кириллица и символы приглашения могут ломаться"
fi

section "Итог"
if (( TOOLS_MISSING == 0 )); then
    echo "  $OK инструменты: $TOOLS_TOTAL из $TOOLS_TOTAL"
else
    echo "  $WARN инструменты: $((TOOLS_TOTAL - TOOLS_MISSING)) из $TOOLS_TOTAL (нет: $TOOLS_MISSING)"
fi
if (( ! SNAP_PRESENT )); then
    echo "  $WARN снимок не найден"
elif (( SNAP_STALE )); then
    echo "  $WARN снимок устарел относительно manifests/"
else
    echo "  $OK снимок на месте и совпадает с манифестами"
fi
if (( DCONF_READY )); then
    echo "  $OK dconf доступен"
else
    echo "  $WARN dconf недоступен — настройки GNOME при деплое будут пропущены"
fi

HINTS=()
if (( TOOLS_MISSING > 0 )); then
    HINTS+=("установить инструменты: ./scripts/bootstrap.sh")
fi
if (( ! SNAP_PRESENT )); then
    HINTS+=("собрать снимок: ./scripts/collect.sh")
elif (( SNAP_STALE )); then
    HINTS+=("обновить снимок: ./scripts/collect.sh")
fi
if (( SNAP_PRESENT )) && (( DIFFER + ABSENT > 0 )); then
    HINTS+=("применить снимок: ./scripts/deploy.sh --dry-run, затем --apply")
fi
if (( DCONF_WITHOUT_DUMP > 0 )); then
    HINTS+=("в снимке нет дампов для $DCONF_WITHOUT_DUMP путей dconf — перезапусти ./scripts/collect.sh")
fi

if (( ${#HINTS[@]} > 0 )); then
    echo
    echo "Подсказки:"
    for hint in "${HINTS[@]}"; do
        printf '  - %s\n' "$hint"
    done
fi

exit 0
