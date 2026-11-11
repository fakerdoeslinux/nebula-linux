#!/usr/bin/env bash
# Set the picture: size, shape, upscaler and cap. Writes Nebula's config.ini, keeping every other key.
#
#   ./scripts/set-video.sh --res 2560x1080 --aspect auto --fsr quality --fps 120
#
#   --res WxH           client size (windowed: the window; borderless: capped to the monitor's work area)
#   --aspect NAME       auto | 4:3 | 3:2 | 16:10 | 16:9 | 21:9 | 32:9   (auto follows the window's shape)
#   --fsr NAME          off | quality | balanced | performance | ultra-performance | ultra-quality
#   --fps N             presented frames per second: 60, 120, 144, 0 (the display's rate)
#   --display MODE      windowed | borderless
#   --sharpness N       RCAS strength 0-100, 0 skips the pass
#
# NEBULA_HOME names the install root (default ~/Documents/nebula-game); the settings folder is its data/.
set -euo pipefail

NEBULA_HOME="${NEBULA_HOME:-$HOME/Documents/nebula-game}"
DATA="$NEBULA_HOME/data"
CONFIG="$DATA/config.ini"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

res="" aspect="" fsr="" fps="" display="" sharpness=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --res)       res="${2:?--res needs WxH}"; shift 2 ;;
    --aspect)    aspect="${2:?--aspect needs a name}"; shift 2 ;;
    --fsr)       fsr="${2:?--fsr needs a name}"; shift 2 ;;
    --fps)       fps="${2:?--fps needs a number}"; shift 2 ;;
    --display)   display="${2:?--display needs windowed or borderless}"; shift 2 ;;
    --sharpness) sharpness="${2:?--sharpness needs a number}"; shift 2 ;;
    -h|--help)   sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)           die "unknown option $1" ;;
  esac
done

mkdir -p "$DATA"
[[ -f "$CONFIG" ]] || : > "$CONFIG"

# set_key <key> <value>: replace the key in place, or append it. Other lines are untouched.
set_key() {
  local key="$1" value="$2" tmp
  tmp="$(mktemp "$DATA/.config.ini.XXXXXX")"
  awk -v k="$key" -v v="$value" '
    BEGIN { done = 0 }
    $0 ~ ("^" k "=") { print k "=" v; done = 1; next }
    { print }
    END { if (!done) print k "=" v }
  ' "$CONFIG" > "$tmp"
  mv -f "$tmp" "$CONFIG"
}

if [[ -n "$res" ]]; then
  [[ "$res" =~ ^([0-9]+)x([0-9]+)$ ]] || die "--res wants WIDTHxHEIGHT, e.g. 2560x1080"
  set_key window_width  "${BASH_REMATCH[1]}"
  set_key window_height "${BASH_REMATCH[2]}"
fi

if [[ -n "$aspect" ]]; then
  case "$aspect" in
    auto|4:3|3:2|16:10|16:9|21:9|32:9) set_key aspect "$aspect" ;;
    *) die "--aspect wants one of: auto 4:3 3:2 16:10 16:9 21:9 32:9" ;;
  esac
fi

if [[ -n "$fsr" ]]; then
  case "$fsr" in
    off)               set_key upscaler 0; set_key spatial_quality 0 ;;
    quality)           set_key upscaler 1; set_key spatial_quality 1 ;;
    balanced)          set_key upscaler 1; set_key spatial_quality 2 ;;
    performance)       set_key upscaler 1; set_key spatial_quality 3 ;;
    ultra-performance) set_key upscaler 1; set_key spatial_quality 4 ;;
    ultra-quality)     set_key upscaler 1; set_key spatial_quality 5 ;;
    *) die "--fsr wants one of: off quality balanced performance ultra-performance ultra-quality" ;;
  esac
fi

if [[ -n "$fps" ]]; then
  [[ "$fps" =~ ^[0-9]+$ ]] || die "--fps wants a number (0 is the display's rate)"
  set_key max_fps "$fps"
fi

if [[ -n "$display" ]]; then
  case "$display" in
    windowed)   set_key display_mode 0 ;;
    borderless) set_key display_mode 1 ;;
    *) die "--display wants windowed or borderless" ;;
  esac
fi

if [[ -n "$sharpness" ]]; then
  [[ "$sharpness" =~ ^[0-9]+$ ]] || die "--sharpness wants 0-100"
  set_key sharpness "$sharpness"
fi

printf '%s\n' "$CONFIG" >&2
grep -E '^(window_width|window_height|display_mode|aspect|upscaler|spatial_quality|max_fps|sharpness)=' "$CONFIG" | sed 's/^/  /' >&2
