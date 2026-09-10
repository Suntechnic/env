# Настройка плагинов для zsh
ZSH_PLUGINS_DIR="$HOME/.config/zsh/plugins"
ZSH_PLUGINS_UPDATE_FILE="$HOME/.cache/zsh/plugins-last-update"
ZSH_PLUGINS_UPDATE_INTERVAL=604800

typeset -a lstZshPluginNames
lstZshPluginNames=(
    zsh-autosuggestions
    zsh-history-substring-search
    zsh-syntax-highlighting
)

typeset -A refZshPluginEntryFiles
refZshPluginEntryFiles=(
    zsh-autosuggestions 'zsh-autosuggestions.zsh'
    zsh-history-substring-search 'zsh-history-substring-search.zsh'
    zsh-syntax-highlighting 'zsh-syntax-highlighting.zsh'
)

zsh-plugin-is-installed () {
    local PluginName="$1"
    local PluginDir="$ZSH_PLUGINS_DIR/$PluginName"
    local PluginEntryFile="${refZshPluginEntryFiles[$PluginName]}"

    [[ -d "$PluginDir/.git" ]] && \
        [[ -r "$PluginDir/$PluginEntryFile" ]]
}

zsh-plugin-clone () {
    local PluginName="$1"
    local PluginDir="$ZSH_PLUGINS_DIR/$PluginName"

    print -n -P "%F{yellow}↻ zsh:%f установка %F{cyan}$PluginName%f... "

    if GIT_TERMINAL_PROMPT=0 \
        git -c http.version=HTTP/1.1 \
            clone --depth 1 \
            "https://github.com/zsh-users/$PluginName.git" \
            "$PluginDir"; then
        print -P "%F{green}готово%f"

        return 0
    fi

    print -P "%F{red}ошибка%f"

    return 1
}

zsh-plugin-update () {
    local PluginName="$1"
    local PluginDir="$ZSH_PLUGINS_DIR/$PluginName"
    local UpdateOutput
    local ExitCode

    UpdateOutput="$(
        GIT_TERMINAL_PROMPT=0 \
        git -c http.version=HTTP/1.1 \
            -C "$PluginDir" pull --ff-only --quiet 2>&1
    )"
    ExitCode=$?

    if (( ExitCode != 0 )); then
        print -u2 -P "%F{red}✗ zsh:%f не удалось обновить %F{yellow}$PluginName%f"
        print -u2 -- "$UpdateOutput"

        return 1
    fi

    if [[ "$UpdateOutput" == *'Already up to date.'* ]]; then
        print -P "%F{242}· zsh:%f $PluginName — актуален"
    else
        print -P "%F{green}✓ zsh:%f обновлён %F{cyan}$PluginName%f"
    fi

    return 0
}

zsh-plugins-update () {
    local PluginName
    local PluginDir
    local UpdateFailed=0

    print -P "%F{yellow}↻ zsh:%f принудительная проверка плагинов"

    for PluginName in "${lstZshPluginNames[@]}"; do
        PluginDir="$ZSH_PLUGINS_DIR/$PluginName"

        if [[ ! -d "$PluginDir/.git" ]]; then
            zsh-plugin-clone "$PluginName" || UpdateFailed=1
            continue
        fi

        zsh-plugin-update "$PluginName" || UpdateFailed=1
    done

    if (( UpdateFailed )); then
        print -u2 -P "%F{red}✗ zsh:%f не все плагины удалось обновить"

        return 1
    fi

    touch "$ZSH_PLUGINS_UPDATE_FILE"
    print -P "%F{green}✓ zsh:%f плагины проверены"

    return 0
}

mkdir -p "$ZSH_PLUGINS_DIR" "${ZSH_PLUGINS_UPDATE_FILE:h}"

for PluginName in "${lstZshPluginNames[@]}"; do
    PluginDir="$ZSH_PLUGINS_DIR/$PluginName"

    if zsh-plugin-is-installed "$PluginName"; then
        continue
    fi

    if [[ -e "$PluginDir" ]]; then
        print -P "%F{yellow}⚠ zsh:%f повреждённый плагин %F{cyan}$PluginName%f будет установлен повторно"
        rm -rf "$PluginDir"
    fi

    zsh-plugin-clone "$PluginName"
done

if [[ ! -f "$ZSH_PLUGINS_UPDATE_FILE" ]] || \
    (( $(date +%s) - $(stat -c %Y "$ZSH_PLUGINS_UPDATE_FILE") >= ZSH_PLUGINS_UPDATE_INTERVAL )); then

    print -P "%F{yellow}↻ zsh:%f проверка обновлений плагинов"
    UpdateFailed=0

    for PluginName in "${lstZshPluginNames[@]}"; do
        PluginDir="$ZSH_PLUGINS_DIR/$PluginName"

        if [[ -d "$PluginDir/.git" ]]; then
            zsh-plugin-update "$PluginName" || UpdateFailed=1
        fi
    done

    if (( ! UpdateFailed )); then
        touch "$ZSH_PLUGINS_UPDATE_FILE"
    else
        print -u2 -P "%F{yellow}⚠ zsh:%f marker обновлений не обновлён из-за ошибки"
    fi
fi



# Режим редактирования командной строки в стиле Emacs
bindkey -e

# История
HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000

setopt append_history
setopt share_history
setopt hist_ignore_dups
setopt hist_find_no_dups
setopt hist_reduce_blanks
setopt inc_append_history

# Completion zsh
autoload -Uz compinit
zmodload zsh/complist
compinit

# Интерфейс completion
zstyle ':completion:*' menu select=1
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'
zstyle ':completion:*:warnings' format '%F{red}Нет совпадений%f'

# Fish-подобные серые подсказки
if [[ -r "$ZSH_PLUGINS_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
    source "$ZSH_PLUGINS_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh"
    ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
else
    print -u2 -P "%F{yellow}⚠ zsh:%f плагин zsh-autosuggestions недоступен"
fi

# Ctrl+F принимает подсказку целиком, → — следующий символ
bindkey '^F' autosuggest-accept
bindkey "${terminfo[kcuf1]}" forward-char

# Поиск истории по любому фрагменту, как в fish
source "$ZSH_PLUGINS_DIR/zsh-history-substring-search/zsh-history-substring-search.zsh"

HISTORY_SUBSTRING_SEARCH_ENSURE_UNIQUE=1

bindkey "${terminfo[kcuu1]}" history-substring-search-up
bindkey "${terminfo[kcud1]}" history-substring-search-down

# Fallback для SSH, tmux и терминалов без подходящего terminfo
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
bindkey '\eOA' history-substring-search-up
bindkey '\eOB' history-substring-search-down

# Prompt
autoload -Uz colors vcs_info
colors

setopt prompt_subst
zstyle ':vcs_info:git:*' formats ' %F{magenta}git:%b%f'
zstyle ':vcs_info:*' enable git

precmd () {
    vcs_info
}

if (( EUID == 0 )); then
    PROMPT_IDENTITY='%F{red}%n@%m%f'
    PROMPT_SYMBOL='%F{red}❯%f'
else
    PROMPT_IDENTITY='%F{green}%n@%m%f'
    PROMPT_SYMBOL='%F{cyan}❯%f'
fi

PROMPT='
${PROMPT_IDENTITY} %F{blue}%~%f${vcs_info_msg_0_}
%(?..%F{red}↳ %?%f )${PROMPT_SYMBOL} '

RPROMPT='%F{242}%D{%H:%M}%f'

# Подсветка синтаксиса: всегда последней
if [[ -r "$ZSH_PLUGINS_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
    source "$ZSH_PLUGINS_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
else
    print -u2 -P "%F{yellow}⚠ zsh:%f плагин zsh-syntax-highlighting недоступен"
fi


export PATH="$HOME/.local/bin:$PATH"

# GitHub Copilot CLI
COPILOT_PROXY_ENV_FILE="$HOME/.vscode-server-insiders/server-env-setup"
copilot () {
    if [[ ! -r "$COPILOT_PROXY_ENV_FILE" ]]; then
        print -u2 -P \
            "%F{red}Copilot не запущен:%f нет или недоступен файл %F{yellow}$COPILOT_PROXY_ENV_FILE%f"

        return 1
    fi

    (
        source "$COPILOT_PROXY_ENV_FILE" || exit 1

        command copilot "$@"
    )
}

# Обновление конфигурации zsh из GitHub
zsh-update () {
    local ConfigUrl='https://raw.githubusercontent.com/Suntechnic/howto/refs/heads/main/hosts/files/.zshrc'
    local TempFile
    local BackupFile="$HOME/.zshrc.bak"

    TempFile="$(mktemp "${TMPDIR:-/tmp}/zshrc.XXXXXX")" || return 1

    if ! curl --fail --silent --show-error --location \
        "$ConfigUrl" \
        --output "$TempFile"; then
        print -u2 -P "%F{red}✗ zsh:%f не удалось скачать конфигурацию"
        rm -f "$TempFile"

        return 1
    fi

    if ! zsh -n "$TempFile"; then
        print -u2 -P "%F{red}✗ zsh:%f синтаксическая ошибка в скачанном .zshrc"
        rm -f "$TempFile"

        return 1
    fi

    cp "$HOME/.zshrc" "$BackupFile" || {
        print -u2 -P "%F{red}✗ zsh:%f не удалось создать резервную копию"
        rm -f "$TempFile"

        return 1
    }

    mv "$TempFile" "$HOME/.zshrc"

    print -P "%F{green}✓ zsh:%f конфигурация обновлена"
    print -P "%F{242}Резервная копия:%f $BackupFile"

    source "$HOME/.zshrc"

    if ! zsh-plugins-update; then
        print -u2 -P "%F{yellow}⚠ zsh:%f конфигурация обновлена, но плагины обновились с ошибками"

        return 1
    fi

    print -P "%F{green}✓ zsh:%f конфигурация и плагины обновлены"

    exec zsh
}