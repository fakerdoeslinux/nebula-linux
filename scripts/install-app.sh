#!/usr/bin/env bash
# Put the game in the desktop's application menu, with its icon, and (Plasma) pin it to the task bar.
#
#   NEBULA_HOME  install root (default: ~/Documents/nebula-game)
#
# Safe to run again: it rewrites the entry and skips the pin when it is already there.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEBULA_HOME="${NEBULA_HOME:-$HOME/Documents/nebula-game}"
NAME="Super Mario Galaxy"
ICON_ID="nebula-smg"

APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICONS="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"

mkdir -p "$APPS" "$ICONS/scalable/apps"

install -m644 "$REPO/assets/$ICON_ID.svg" "$ICONS/scalable/apps/$ICON_ID.svg"
if [[ -f "$REPO/assets/$ICON_ID.png" ]]; then
  for size in 512 256 128 64 48 32; do
    mkdir -p "$ICONS/${size}x${size}/apps"
    if command -v magick >/dev/null 2>&1; then
      magick "$REPO/assets/$ICON_ID.png" -resize "${size}x${size}" "$ICONS/${size}x${size}/apps/$ICON_ID.png"
    else
      cp -f "$REPO/assets/$ICON_ID.png" "$ICONS/${size}x${size}/apps/$ICON_ID.png"
    fi
  done
fi
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -f -t "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor" >/dev/null 2>&1 || true

ENTRY="$APPS/$ICON_ID.desktop"
cat > "$ENTRY" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=$NAME
GenericName=$NAME (native port)
Comment=Native Linux Nebula build — Vulkan + SDL3, Xbox/PlayStation/Switch controllers
Exec=bash "$REPO/scripts/run-nebula.sh"
Path=$NEBULA_HOME/bin
Icon=$ICON_ID
Terminal=false
StartupNotify=true
StartupWMClass=nebula
Categories=Game;ActionGame;
Keywords=mario;galaxy;nebula;wii;platformer;
X-KDE-StartupNotify=true
EOF
chmod +x "$ENTRY"

command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 >/dev/null 2>&1 || true
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" >/dev/null 2>&1 || true

# A desktop shortcut, trusted so Plasma launches it without a prompt.
DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
if [[ -d "$DESKTOP_DIR" ]]; then
  install -m755 "$ENTRY" "$DESKTOP_DIR/$ICON_ID.desktop"
  gio set "$DESKTOP_DIR/$ICON_ID.desktop" metadata::trusted true >/dev/null 2>&1 || true
fi

# Plasma: pin to the icons-only task manager, the way the launcher's own "Pin" does.
if command -v gdbus >/dev/null 2>&1 && gdbus call --session --dest org.kde.plasmashell \
    --object-path /PlasmaShell --method org.kde.PlasmaShell.evaluateScript 'print("ok")' >/dev/null 2>&1; then
  gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell \
    --method org.kde.PlasmaShell.evaluateScript "
var changed = 0;
panels().forEach(function (panel) {
  panel.widgets().forEach(function (widget) {
    if (widget.type === 'org.kde.plasma.icontasks') {
      widget.currentConfigGroup = ['General'];
      var list = String(widget.readConfig('launchers', ''));
      if (list.indexOf('$ICON_ID') === -1) {
        widget.writeConfig('launchers', list.length ? list + ',applications:$ICON_ID.desktop' : 'applications:$ICON_ID.desktop');
        widget.reloadConfig();
        changed += 1;
      }
    }
  });
});
print('pinned=' + changed);
" >/dev/null 2>&1 || true
fi

# The menu's six sounds (assets/menu-sounds): the game plays them for row focus, select, page, open, close and OK. They
# live in the data folder, which the launcher passes as --data; without them the game falls back to its own system sounds.
SOUNDS="$NEBULA_HOME/data/menu-sounds"
if compgen -G "$REPO/assets/menu-sounds/*.wav" >/dev/null; then
  mkdir -p "$SOUNDS"
  for sound in "$REPO"/assets/menu-sounds/*.wav; do
    install -m644 "$sound" "$SOUNDS/$(basename "$sound")"
  done
  echo "sounds:    $SOUNDS ($(ls -1 "$SOUNDS" | wc -l) files)"
fi

echo "installed: $ENTRY"
echo "icon:      $ICONS/scalable/apps/$ICON_ID.svg"
echo "launch:    bash $REPO/scripts/run-nebula.sh"