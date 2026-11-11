#!/usr/bin/env bash
# Build Nebula (Super Mario Galaxy) natively on Linux: SDL3 host + Vulkan renderer + game module.
#
#   ./scripts/build-linux.sh /path/to/super-mario-galaxy.rvz
#
# What it does, in order:
#   1. checks the toolchain, and on Fedora unpacks the X11/Wayland -devel headers into a user prefix (no sudo)
#   2. clones the pinned dependency checkouts (SDL3, glslang, Vulkan-Headers, volk, VulkanMemoryAllocator)
#   3. clones Nebula at the pinned commit and applies patches/0001-linux-port.patch
#   4. builds the host tools (SPIR-V compilers), the host, the game module, and the disc importer
#   5. imports your disc image into game.pak and installs the desktop entry + icon
#
# Environment:
#   NEBULA_WORKDIR   build root            (default ~/.local/share/nebula-smg-build)
#   NEBULA_HOME      install root          (default ~/Documents/nebula-game)
#   NEBULA_DEVEL_PREFIX  unpacked -devel RPMs (default <workdir>/devel)
#   JOBS             parallel builds       (default: nproc)
#   SMG_DISC         disc image, in place of the first argument
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${NEBULA_WORKDIR:-$HOME/.local/share/nebula-smg-build}"
DEPS="$WORK/deps"
SRC="$WORK/nebula"
BUILD="$WORK/build"
DEVEL="${NEBULA_DEVEL_PREFIX:-$WORK/devel}"
NEBULA_HOME="${NEBULA_HOME:-$HOME/Documents/nebula-game}"
JOBS="${JOBS:-$(nproc)}"
DISC="${1:-${SMG_DISC:-}}"

# Nebula 2 main, the commit this port was built and tested at.
NEBULA_COMMIT="4f40d958b58e6d96e5063c68abd56e605c601869"
SDL_VERSION="release-3.4.18"
VULKAN_SDK_TAG="vulkan-sdk-1.4.350.1"

say()  { printf '\n\033[1;35m== %s\033[0m\n' "$*"; }
note() { printf '   %s\n' "$*"; }
die()  { printf '\n error: %s\n' "$*" >&2; exit 1; }

say "1/9 toolchain"
for tool in clang clang++ cmake ninja git pkg-config python3 cargo; do
  command -v "$tool" >/dev/null 2>&1 || die "missing $tool — install clang, cmake, ninja, git, pkg-config, python3 and Rust (https://rustup.rs)"
done
clang --version | head -1
cmake --version | head -1
note "workdir: $WORK"
note "install: $NEBULA_HOME"

say "2/9 system headers"
have_headers() {
  PKG_CONFIG_PATH="$PKG_CONFIG_PATH" pkg-config --exists wayland-client xkbcommon xi xtst xscrnsaver libdecor-0 gbm wayland-protocols
}

DEVEL_CFLAGS=""
DEVEL_LIBS=""
if have_headers; then
  note "X11 + Wayland headers found on the system"
elif command -v dnf >/dev/null 2>&1; then
  note "unpacking Fedora -devel RPMs into $DEVEL (no sudo)"
  mkdir -p "$DEVEL/rpms" "$DEVEL/root"
  ( cd "$DEVEL/rpms" && dnf download --destdir . \
      libxkbcommon-devel libXi-devel libXtst-devel libXScrnSaver-devel \
      libdecor-devel mesa-libgbm-devel wayland-protocols-devel wayland-devel ) || \
    die "dnf download failed — connect to the network or install the -devel packages"
  for rpm in "$DEVEL"/rpms/*x86_64.rpm "$DEVEL"/rpms/*noarch.rpm; do
    [ -e "$rpm" ] || continue
    rpm2cpio "$rpm" | ( cd "$DEVEL/root" && cpio -idm --quiet )
  done
  # The .pc files carry prefix=/usr; point them at the unpacked tree.
  find "$DEVEL/root" -name '*.pc' -print0 | xargs -0 sed -i "s|^prefix=/usr$|prefix=$DEVEL/root/usr|"
  # Unversioned .so symlinks point at sonames the loader resolves from the system paths.
  find "$DEVEL/root/usr/lib64" -maxdepth 1 -type l 2>/dev/null | while read -r link; do
    target="$(readlink "$link")"
    case "$target" in /*) continue ;; esac
    [ -e "$DEVEL/root/usr/lib64/$target" ] || [ ! -e "/usr/lib64/$target" ] || ln -sf "/usr/lib64/$target" "$DEVEL/root/usr/lib64/$target"
  done
  export PKG_CONFIG_PATH="$DEVEL/root/usr/lib64/pkgconfig:$DEVEL/root/usr/share/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
  DEVEL_CFLAGS="-I$DEVEL/root/usr/include -I$DEVEL/root/usr/include/libdecor-0"
  DEVEL_LIBS="-L$DEVEL/root/usr/lib64"
  have_headers || die "still missing X11/Wayland headers — see the package list in README.md"
else
  die "missing X11/Wayland headers. Fedora: sudo dnf install wayland-devel wayland-protocols-devel libxkbcommon-devel libXi-devel libXtst-devel libXScrnSaver-devel libdecor-devel mesa-libgbm-devel
       Debian/Ubuntu: sudo apt install libwayland-dev wayland-protocols libxkbcommon-dev libxi-dev libxtst-dev libxss-dev libdecor-0-dev libgbm-dev
       Arch: sudo pacman -S wayland wayland-protocols libxkbcommon libxi libxtst libxss libdecor mesa"
fi
export CFLAGS="$DEVEL_CFLAGS ${CFLAGS:-}"
export CXXFLAGS="$DEVEL_CFLAGS ${CXXFLAGS:-}"

say "3/9 dependency checkouts"
mkdir -p "$DEPS"
clone() { # clone <url> <dir> [branch]
  local url="$1" dir="$2" branch="${3:-}"
  if [ -d "$DEPS/$dir/.git" ]; then note "have $dir"; return; fi
  if [ -n "$branch" ]; then
    git clone --depth 1 --branch "$branch" "$url" "$DEPS/$dir"
  else
    git clone --depth 1 "$url" "$DEPS/$dir"
  fi
}
clone https://github.com/KhronosGroup/Vulkan-Headers.git "Vulkan-Headers-$VULKAN_SDK_TAG" "$VULKAN_SDK_TAG"
clone https://github.com/zeux/volk.git "volk-$VULKAN_SDK_TAG" "$VULKAN_SDK_TAG"
clone https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator.git VulkanMemoryAllocator-v3.4.0 v3.4.0
clone https://github.com/libsdl-org/SDL.git SDL3-3.4.18 "$SDL_VERSION"
if [ ! -d "$DEPS/glslang-src/.git" ]; then
  git clone --depth 1 https://github.com/KhronosGroup/glslang.git "$DEPS/glslang-src"
  git clone --depth 1 https://github.com/KhronosGroup/SPIRV-Tools.git "$DEPS/glslang-src/External/spirv-tools"
  # Case-sensitive filesystems: SPIRV-Tools looks for its headers in lowercase external/.
  git clone --depth 1 https://github.com/KhronosGroup/SPIRV-Headers.git "$DEPS/glslang-src/External/spirv-tools/external/spirv-headers"
fi

say "4/9 Nebula source at $NEBULA_COMMIT"
if [ ! -d "$SRC/.git" ]; then
  git clone https://github.com/keepvaibin/nebula.git "$SRC"
fi
git -C "$SRC" fetch --depth 1 origin "$NEBULA_COMMIT" 2>/dev/null || true
git -C "$SRC" checkout --quiet "$NEBULA_COMMIT"
if git -C "$SRC" apply --reverse --check "$REPO/patches/0001-linux-port.patch" 2>/dev/null; then
  note "patch already applied"
else
  git -C "$SRC" apply "$REPO/patches/0001-linux-port.patch"
  note "applied patches/0001-linux-port.patch"
fi

say "5/9 host tools (SPIR-V for the shipped shaders)"
cmake -S "$REPO/tools" -B "$BUILD/tools" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
  -DNEBULA_ROOT="$SRC" -DNEBULA_DEPS="$DEPS"
cmake --build "$BUILD/tools" -j "$JOBS" --target galaxy_native_spirv galaxy_utility_spirv

say "6/9 host (platform/sdl: SDL3 + Vulkan)"
cmake -S "$SRC/platform/sdl" -B "$BUILD/host" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
  -DNEBULA_DEPS="$DEPS" -DNEBULA_HOST_TOOLS="$BUILD/tools" \
  -DCMAKE_INCLUDE_PATH="$DEVEL/root/usr/include" \
  -DCMAKE_PREFIX_PATH="$DEVEL/root/usr" \
  -DCMAKE_LIBRARY_PATH="$DEVEL/root/usr/lib64" \
  -DCMAKE_C_FLAGS="$CFLAGS" -DCMAKE_CXX_FLAGS="$CXXFLAGS"
# Upstream's archive deps link <prefix>/lib/liblzma.a; older checkouts install xz into lib64.
if [ -f "$BUILD/host/archive-deps/lib64/liblzma.a" ] && [ ! -e "$BUILD/host/archive-deps/lib/liblzma.a" ]; then
  ln -sf ../lib64/liblzma.a "$BUILD/host/archive-deps/lib/liblzma.a"
fi
cmake --build "$BUILD/host" -j "$JOBS" --target main

say "7/9 game module (Petari decompilation)"
cmake -S "$SRC/native" -B "$BUILD/game" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
  -DNEBULA_PETARI_DIR="$SRC/native/petari"
cmake --build "$BUILD/game" -j "$JOBS" --target smg_game

say "8/9 disc importer"
( cd "$SRC" && cargo build --release --locked -p nebula-import )

say "9/9 install"
mkdir -p "$NEBULA_HOME/bin" "$NEBULA_HOME/content" "$NEBULA_HOME/saves" "$NEBULA_HOME/data"
install -m755 "$BUILD/host/nebula" "$NEBULA_HOME/bin/nebula"
install -m755 "$BUILD/game/libsmg_game.so" "$NEBULA_HOME/bin/libsmg_game.so"
cp -f "$BUILD/host/SDL3"/libSDL3.so* "$NEBULA_HOME/bin/" 2>/dev/null || true
install -m755 "$REPO/scripts/run-nebula.sh" "$NEBULA_HOME/bin/run-nebula.sh"
install -m755 "$REPO/scripts/set-video.sh" "$NEBULA_HOME/bin/set-video.sh"

# 2560x1080 ultrawide, Hor+, FSR 1 quality and 120 presented frames unless a config.ini already exists.
if [ ! -f "$NEBULA_HOME/data/config.ini" ]; then
  NEBULA_HOME="$NEBULA_HOME" bash "$REPO/scripts/set-video.sh" --res "${NEBULA_RES:-2560x1080}" --aspect auto \
    --fsr "${NEBULA_FSR:-quality}" --fps "${NEBULA_FPS:-120}" --display borderless
fi

if [ -n "$DISC" ]; then
  [ -f "$DISC" ] || die "no disc image at $DISC"
  "$SRC/target/release/nebula-import" identify "$DISC"
  "$SRC/target/release/nebula-import" import "$DISC" --output "$NEBULA_HOME/content"
elif [ ! -f "$NEBULA_HOME/content/game.pak" ]; then
  note "no disc image given — import later with:"
  note "  $SRC/target/release/nebula-import import /path/to/game.rvz --output $NEBULA_HOME/content"
fi

NEBULA_HOME="$NEBULA_HOME" bash "$REPO/scripts/install-app.sh"

say "done"
note "launch from the application menu, or: NEBULA_HOME=$NEBULA_HOME bash $REPO/scripts/run-nebula.sh"
