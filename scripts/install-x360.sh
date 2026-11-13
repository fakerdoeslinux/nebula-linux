#!/usr/bin/env bash
# Put the Xbox 360 build on a console's drive: the title under Apps, the art where Aurora and Freestyle look for it, the
# writable side under <root>/Nebula.
#
#   ./scripts/install-x360.sh /run/media/$USER/Hdd1          # a mounted RGH/JTAG drive
#   ./scripts/install-x360.sh ~/x360-stick --staging         # a folder to copy over later
#
# The drive is what a console sees as Hdd:\ (or Usb0:\). This script writes:
#
#   Apps\Nebula\default.xex         the title (or nebula.elf, which XeLL boots)
#   Apps\Nebula\content\            game.pak
#   Apps\Nebula\data\               settings, menu sounds
#   Aurora\Assets\4E4E4542\         boxart, background, icon, banner (Aurora's own folder)
#   FSD\Media\4E4E4542\             the same for Freestyle Dash
#   Nebula\                         saves and settings (galaxy::nebula_data_directory)
#
# Environment:
#   NEBULA_X360_STAGE   the package scripts/build-xbox360.sh staged (default <workdir>/build/x360/Nebula)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${NEBULA_WORKDIR:-$HOME/.local/share/nebula-smg-build}"
STAGE="${NEBULA_X360_STAGE:-$WORK/build/x360/Nebula}"
PLAYER="$(printf '4E4E4542' | tr 'A-F' 'a-f')"   # "NNEB" as the dashboard shows it
TITLE_ID="4E4E4542"
STAGING=0
ROOT=""

for argument in "$@"; do
  case "$argument" in
    --staging) STAGING=1 ;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -* ) printf 'unknown option: %s\n' "$argument" >&2; exit 2 ;;
    *) ROOT="$argument" ;;
  esac
done

say()  { printf '\n\033[1;35m== %s\033[0m\n' "$*"; }
note() { printf '   %s\n' "$*"; }
die()  { printf '\n error: %s\n' "$*" >&2; exit 1; }

[[ -n "$ROOT" ]] || die "usage: scripts/install-x360.sh /run/media/\$USER/Hdd1 [--staging]"
[[ -d "$STAGE" ]] || die "nothing staged at $STAGE — run scripts/build-xbox360.sh first"
ROOT="${ROOT%/}"
mkdir -p "$ROOT"

say "1/4 destination"
if [[ $STAGING -eq 0 ]]; then
  # A console's drive has at least one of the folders its dashboards keep. A blank USB stick is fine too: the caller
  # spells --staging when it means "make the layout here, I will copy it".
  if ! compgen -G "$ROOT/*" >/dev/null && [[ ! -d "$ROOT/Content" && ! -d "$ROOT/Apps" ]]; then
    note "$ROOT is empty — writing the layout anyway (a fresh USB stick looks like this)"
  else
    note "$(ls -1 "$ROOT" | head -8 | tr '\n' ' ')"
  fi
fi
note "root: $ROOT"
note "title id: $TITLE_ID"

say "2/4 the title"
APPS="$ROOT/Apps/Nebula"
mkdir -p "$APPS/content" "$APPS/data"
if [[ -f "$STAGE/default.xex" ]]; then
  install -m644 "$STAGE/default.xex" "$APPS/default.xex"
  note "default.xex   $(du -h "$STAGE/default.xex" | cut -f1)"
elif [[ -f "$STAGE/nebula.elf" ]]; then
  install -m644 "$STAGE/nebula.elf" "$APPS/nebula.elf"
  note "nebula.elf    $(du -h "$STAGE/nebula.elf" | cut -f1)  (XeLL boots this; a .xex comes from the XDK's image tool)"
else
  die "the staged package has no default.xex and no nebula.elf"
fi
if [[ -d "$STAGE/content" ]] && compgen -G "$STAGE/content/*" >/dev/null; then
  cp -f "$STAGE"/content/* "$APPS/content/"
  note "content       $(du -sh "$APPS/content" | cut -f1)"
else
  note "content       empty: a console build's game.pak is cooked for PowerPC (docs/XBOX360.md)"
fi
cp -rf "$STAGE"/data/* "$APPS/data/" 2>/dev/null || true
install -m644 "$STAGE/readme.txt" "$APPS/readme.txt" 2>/dev/null || true

say "3/4 the art"
# Aurora and Freestyle both key their art on the title id, in their own folders, under the names they document.
for home in "Aurora/Assets" "FSD/Media"; do
  target="$ROOT/$home/$TITLE_ID"
  mkdir -p "$target"
  for pic in boxart background icon banner tile splash; do
    [[ -f "$REPO/assets/xbox360/$pic.png" ]] && install -m644 "$REPO/assets/xbox360/$pic.png" "$target/$pic.png"
  done
  # Freestyle wants the cover as "Boxart.png" and the rest lower case; both spellings cost nothing on a FATX drive.
  [[ -f "$REPO/assets/xbox360/boxart.png" ]] && install -m644 "$REPO/assets/xbox360/boxart.png" "$target/Boxart.png"
  install -m644 "$REPO/assets/xbox360/manifest.json" "$target/manifest.json"
  note "$home/$TITLE_ID   $(ls -1 "$target" | tr '\n' ' ')"
done
# The same set beside the title, for a dashboard that reads a folder instead of a title id.
mkdir -p "$APPS/media"
for art in "$REPO"/assets/xbox360/*.png "$REPO/assets/xbox360/manifest.json"; do
  install -m644 "$art" "$APPS/media/"
done
note "Apps/Nebula/media   $(ls -1 "$APPS/media" | tr '\n' ' ')"

say "4/4 the writable side"
mkdir -p "$ROOT/Nebula/data/menu-sounds" "$ROOT/Nebula/saves"
if compgen -G "$REPO/assets/menu-sounds/*.wav" >/dev/null; then
  cp -f "$REPO"/assets/menu-sounds/*.wav "$ROOT/Nebula/data/menu-sounds/"
  note "menu sounds   $(ls -1 "$ROOT/Nebula/data/menu-sounds" | wc -l) files"
else
  note "menu sounds   not in this checkout: the game falls back to its own system sounds"
fi

printf '\n\033[1;35m== done\033[0m\n'
note "on the console: launch Apps/Nebula (Aurora or Freestyle), or point XeLL at Apps/Nebula/nebula.elf"
note "saves and settings land in $(printf 'Hdd:\\')Nebula"
note "the art also lives in Apps/Nebula/media if your dashboard reads a folder instead of the title id"
