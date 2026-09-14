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