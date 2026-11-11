#!/usr/bin/env bash
# Launch the native Linux Nebula build of Super Mario Galaxy.
#
#   NEBULA_HOME        install root (default ~/Documents/nebula-game)
#   NEBULA_RES         client size, e.g. 2560x1080 (written to config.ini before the launch)
#   NEBULA_ASPECT      auto | 4:3 | 3:2 | 16:10 | 16:9 | 21:9 | 32:9
#   NEBULA_FSR         off | quality | balanced | performance | ultra-performance | ultra-quality
#   NEBULA_FPS         presented frames per second: 60, 120, 144, 0 (the display's rate)
#   NEBULA_DISPLAY     windowed | borderless
#   NEBULA_HUD         on | off — draw the HUD and menus at the output resolution
#   NEBULA_SDL_VIDEO   x11 to force the X11 backend, wayland to force Wayland
#   NEBULA_EXTRA_ARGS  extra arguments for the host (see docs/COMMAND_LINE.md upstream)
#
# Any NEBULA_RES/ASPECT/FSR/FPS/DISPLAY/HUD that is set is applied to config.ini first; unset ones leave the file alone.
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# Video knobs: apply them through set-video.sh, which only touches config.ini.
video_args=()
[[ -n "${NEBULA_RES:-}" ]]     && video_args+=(--res "$NEBULA_RES")
[[ -n "${NEBULA_ASPECT:-}" ]]  && video_args+=(--aspect "$NEBULA_ASPECT")
[[ -n "${NEBULA_FSR:-}" ]]     && video_args+=(--fsr "$NEBULA_FSR")
[[ -n "${NEBULA_FPS:-}" ]]     && video_args+=(--fps "$NEBULA_FPS")
[[ -n "${NEBULA_DISPLAY:-}" ]] && video_args+=(--display "$NEBULA_DISPLAY")
[[ -n "${NEBULA_HUD:-}" ]]     && video_args+=(--hud "$NEBULA_HUD")
if [[ ${#video_args[@]} -gt 0 ]]; then
  set_video="$SELF_DIR/set-video.sh"
  [[ -x "$set_video" ]] || set_video="$SELF_DIR/../scripts/set-video.sh"
  if [[ -x "$set_video" ]]; then
    NEBULA_HOME="$NEBULA_HOME" "$set_video" "${video_args[@]}" 2>/dev/null || true
  else
    echo "set-video.sh not found beside $0 — video knobs ignored" >&2
  fi
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
