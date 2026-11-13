#!/usr/bin/env bash
# Build Nebula (Super Mario Galaxy) for the Xbox 360: one big-endian PowerPC image, Xenos for the picture, XAudio2 for
# the sound, XInput for the pad. See docs/XBOX360.md for what runs on the console today and what does not.
#
#   ./scripts/build-xbox360.sh                    # the console layer (platform, device, audio, window, input)
#   ./scripts/build-xbox360.sh --title            # the whole title, needs a game module built for the console
#
# Environment:
#   XENON_PREFIX        cross compiler prefix            (default xenon)
#   LIBXENON            libxenon's root                  (default /usr/local/libxenon or $HOME/libxenon)
#   NEBULA_WORKDIR      build root                       (default ~/.local/share/nebula-smg-build)
#   NEBULA_SRC          the Nebula checkout              (default <workdir>/nebula)
#   NEBULA_X360_GAME_OBJECTS  the game module's .a files, semicolon separated (--title)
#
# The console has no dynamic loader: the host and the game module are linked into one image. A .elf is what XeLL boots
# over FTP or from a USB stick; a dashboard entry wants a .xex, which the XDK's image tool makes from the .elf (the
# scripts say what to run).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${NEBULA_WORKDIR:-$HOME/.local/share/nebula-smg-build}"
SRC="${NEBULA_SRC:-$WORK/nebula}"
BUILD="${NEBULA_X360_BUILD:-$WORK/build/x360}"
STAGE="$BUILD/Nebula"
XENON_PREFIX="${XENON_PREFIX:-xenon}"
TITLE=0

for argument in "$@"; do
  case "$argument" in
    --title) TITLE=1 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'unknown argument: %s\n' "$argument" >&2; exit 2 ;;
  esac
done

say()  { printf '\n\033[1;35m== %s\033[0m\n' "$*"; }
note() { printf '   %s\n' "$*"; }
die()  { printf '\n error: %s\n' "$*" >&2; exit 1; }

say "1/5 toolchain"
command -v "${XENON_PREFIX}-gcc" >/dev/null 2>&1 || die \
  "${XENON_PREFIX}-gcc not found. Install the free60/libxenon cross toolchain (docs/XBOX360.md) and set XENON_PREFIX."
note "$("${XENON_PREFIX}-gcc" --version | head -1)"
note "libxenon: ${LIBXENON:-/usr/local/libxenon}"
[[ -d "$SRC" ]] || die "no Nebula checkout at $SRC (set NEBULA_SRC, or run scripts/build-linux.sh once for a Linux build)"

say "2/5 configure"
cmake -S "$SRC/platform/xbox360" -B "$BUILD" \
  -DCMAKE_TOOLCHAIN_FILE="$SRC/platform/xbox360/xenon.toolchain.cmake" \
  -DXENON_PREFIX="$XENON_PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  ${TITLE:+-DNEBULA_X360_GAME_OBJECTS="${NEBULA_X360_GAME_OBJECTS:-}"} | sed 's/^/   /'
note "build: $BUILD"

say "3/5 build"
if [[ $TITLE -eq 1 ]]; then
  [[ -n "${NEBULA_X360_GAME_OBJECTS:-}" ]] || die \
    "--title needs NEBULA_X360_GAME_OBJECTS (the game module's static libraries built for the console)"
  cmake --build "$BUILD" --target nebula_x360 -j "${JOBS:-$(nproc)}" | sed 's/^/   /'
else
  cmake --build "$BUILD" --target nebula_x360_platform -j "${JOBS:-$(nproc)}" | sed 's/^/   /'
  note "the console layer built; --title builds nebula.elf once the game module has console objects"
fi

say "4/5 shaders"
PROGRAMS="$BUILD/programs.xsh"
if [[ -f "$PROGRAMS" ]]; then
  note "Xenos programs: $PROGRAMS ($(stat -c%s "$PROGRAMS") bytes)"
else
  note "no programs.xsh yet: the Xenos programs come from tools/dev/compile_programs.py --target xenos"
  note "on a Windows host with the XDK's shader compiler; the game draws nothing without them"
fi

say "5/5 stage the package"
mkdir -p "$STAGE/media" "$STAGE/data" "$STAGE/content"
if [[ -f "$BUILD/nebula.elf" ]]; then
  install -m644 "$BUILD/nebula.elf" "$STAGE/nebula.elf"
fi
for art in "$REPO"/assets/xbox360/*.png; do
  install -m644 "$art" "$STAGE/media/"
done
install -m644 "$REPO/assets/xbox360/manifest.json" "$STAGE/media/manifest.json"
for sound in "$REPO"/assets/menu-sounds/*.wav; do
  [[ -e "$sound" ]] && install -m644 "$sound" "$STAGE/data/menu-sounds/"
done
cat > "$STAGE/readme.txt" <<EOF
Super Mario Galaxy - Nebula Edition (Xbox 360)
==============================================

Apps\Nebula\nebula.elf      the title (XeLL boots it; a .xex goes through the XDK's image tool)
Apps\Nebula\content\        game.pak, cooked for this build
Apps\Nebula\data\           settings, menu sounds, saves' folder
Apps\Nebula\media\          the art: boxart, background, tile, icon, banner, disc label

Install it with scripts/install-x360.sh, which puts the art where Aurora and Freestyle look for it.
EOF
note "package: $STAGE"
note "$(find "$STAGE" -type f | wc -l) files, $(du -sh "$STAGE" | cut -f1)"
printf '\n   next: scripts/install-x360.sh /run/media/%s/Hdd1\n\n' "${USER:-you}"
