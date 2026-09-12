# Перенос и синхронизация окружений

## zsh

```bash
wget https://raw.githubusercontent.com/Suntechnic/env/refs/heads/main/.zshrc -O ~/.zshrc;
```

## gTitle

### Экспорт в главной системе

```bash
dconf dump /org/gnome/shell/extensions/gtile/ > ~/projects/env/dconf/org-gnome-shell-extensions-gtile.ini
```

### Импорт

```bash
wget https://raw.githubusercontent.com/Suntechnic/env/refs/heads/main/dconf/org-gnome-shell-extensions-gtile.ini -O ~/projects/env/dconf/org-gnome-shell-extensions-gtile.ini;
dconf load /org/gnome/shell/extensions/gtile/ < ~/projects/env/dconf/org-gnome-shell-extensions-gtile.ini;
```