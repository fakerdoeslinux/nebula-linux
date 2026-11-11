#!/usr/bin/env bash
# Launch the native Linux Nebula build of Super Mario Galaxy.
#
#   NEBULA_HOME   install root (default: ~/Documents/nebula-game)
#   NEBULA_SDL_VIDEO  x11 to force the X11 backend, wayland to force Wayland
#   NEBULA_EXTRA_ARGS extra arguments for the host (see docs/COMMAND_LINE.md upstream)
set -euo pipefail

NEBULA_HOME="${NEBULA_HOME:-$HOME/Documents/nebula-game}"
BIN="$NEBULA_HOME/bin"
PAK="$NEBULA_HOME/content/game.pak"

if [[ ! -f "$PAK" ]]; then
  echo "no game.pak at $PAK — import your disc image first" >&2
  exit 1
fi
if [[ ! -x "$BIN/nebula" ]]; then
  echo "no host binary at $BIN/nebula — run install-app.sh first" >&2
  exit 1
fi

if [[ -n "${NEBULA_SDL_VIDEO:-}" ]]; then
  export SDL_VIDEO_DRIVER="$NEBULA_SDL_VIDEO"
fi

# RADV/Intel ANV shader cache: first launch compiles, later ones are instant.
export MESA_SHADER_CACHE_DIR="${MESA_SHADER_CACHE_DIR:-$NEBULA_HOME/data/mesa-cache}"
export MESA_SHADER_CACHE_MAX_SIZE="${MESA_SHADER_CACHE_MAX_SIZE:-4G}"

mkdir -p "$NEBULA_HOME/saves" "$NEBULA_HOME/data"

ARGS=(--pak "$PAK" --saves "$NEBULA_HOME/saves" --data "$NEBULA_HOME/data")
if [[ -n "${NEBULA_EXTRA_ARGS:-}" ]]; then
  read -r -a EXTRA <<< "$NEBULA_EXTRA_ARGS"
  ARGS+=("${EXTRA[@]}")
fi

cd "$BIN"
export LD_LIBRARY_PATH="$BIN${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
if command -v gamemoderun >/dev/null 2>&1; then
  exec gamemoderun ./nebula "${ARGS[@]}"
fi
exec ./nebula "${ARGS[@]}"
