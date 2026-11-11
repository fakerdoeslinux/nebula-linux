# Super Mario Galaxy — native Linux port (Nebula)

A ready-to-run Linux build of [Nebula](https://github.com/keepvaibin/nebula), the decompilation of *Super Mario
Galaxy*, plus the five source changes, build scripts and desktop entry this port needs.

No Wine. No emulator. The game's code is compiled to a native Linux binary and runs on SDL3 + Vulkan.

```
$ ./scripts/build-linux.sh ~/Games/Super\ Mario\ Galaxy.rvz
[vulkan] device="AMD Radeon Vega Mobile Gfx (RADV RAVEN)" api=1.4
[vulkan] swapchain 1920x1080 transform=1 images=4
[input] gamepad "Xbox Series X Controller" 045e:0b13 scheme 1 connected
```

## What this repo gives you

| | |
|---|---|
| `scripts/build-linux.sh` | one-command build: dependencies, host, game module, importer, install |
| `scripts/run-nebula.sh` | launcher (sets up the shader cache, finds the module and content) |
| `scripts/set-video.sh` | resolution, aspect, upscaler and frame cap, written to `config.ini` |
| `scripts/install-app.sh` | application-menu entry, icon, desktop shortcut, Plasma task-bar pin |
| `patches/0001-linux-port.patch` | the five source changes upstream needs on Linux |
| `tools/CMakeLists.txt` | builds `galaxy_native_spirv` / `galaxy_utility_spirv` (upstream builds these on Windows only) |
| `assets/nebula-smg.svg` | the app icon |

## You need

- A 64-bit Linux install with a Vulkan 1.1+ GPU driver (Mesa RADV, Intel ANV, NVIDIA proprietary all work).
- Your own **Super Mario Galaxy** disc image: `.rvz`, `.iso` or `.wbfs`, region RMGE01 (USA), RMGP01 (EU) or
  RMGJ01 (JP). No game files are included or distributed here.
- ~7 GB free disk (4 GB of it is the imported `game.pak`) and ~8 GB RAM.
- `clang`, `cmake` ≥ 3.24, `ninja`, `git`, `pkg-config`, `python3`, Rust (rustup) and the Vulkan loader.

## Linux — quick install

```bash
git clone https://github.com/fakerdoeslinux/nebula-linux.git
cd nebula-linux
./scripts/build-linux.sh "/path/to/Super Mario Galaxy.rvz"
```

That is the whole install. It builds everything into `~/.local/share/nebula-smg-build`, installs the game to
`~/Documents/nebula-game`, adds **Super Mario Galaxy** to your application menu with its icon, and pins it to the
Plasma task bar.

Launch it from the menu, the desktop shortcut, or:

```bash
bash scripts/run-nebula.sh
```

### Ultrawide — 2560x1080, 21:9, 32:9

The scene **widens instead of cropping or stretching** (Hor+): the camera, the 2D screen and the HUD layouts all
follow the output's shape, through `experimental_ultrawide_aspect.h` and the game's `display_extent` callback. Both
the game module and the Vulkan renderer read one latched value, so a resize never shows a frame with the old camera
and the new layout.

2560x1080 is 21:9 — the ratio the engine already has as an aspect mode — and it is the default this port installs:

```bash
./scripts/set-video.sh --res 2560x1080 --aspect auto --fsr quality --fps 120 --display borderless
```

- `--aspect auto` follows the window's own shape, so 2560x1080 fills the panel exactly. Pick `21:9` or `32:9` to
  force a shape in a differently-shaped window, `16:9` for pillarboxed classic framing.
- `--fsr quality` is FidelityFX Super Resolution 1: the 3D scene renders at 1699x695 and is upscaled to the
  2548x1042 back buffer, with the HUD and menus still drawn at full output resolution.
- `--fps 120` presents 120 frames a second from the game's 60, with Nebula's own interpolation between them on the
  190 Hz panel this was tested on. `--fps 60` for the plain 1:1 cadence, `--fps 0` for the display's rate.

Measured on Ryzen 5 3550H + Radeon Vega 8 (RADV RAVEN, Mesa 26.2.6), GPU milliseconds per presented frame from the
`[vk-gpu] frame` line:

| Output | Scene target | Upscaler | GPU per frame | Holds |
|---|---|---|---|---|
| 2560x1080 | 2548x1042 | none | 9.5 ms | 60 fps |
| 2560x1080 | 1699x695 → 2548x1042 | FSR 1 quality | 4.1-5.8 ms | 120 fps |
| 2560x1080 | 1274x521 → 2548x1042 | FSR 1 performance | 4.8 ms | 120 fps |
| 854x480 | 853x480 | none | 2.8-4.5 ms | 60 fps |

So the ultrawide picture at FSR 1 quality costs about the same as the old 854x480 default and does not lose frames:
the 60 fps game step has a 16.6 ms budget and this fills 4-6 ms of it. The same numbers come from
`--fsr performance` if you want the extra margin; native 2560x1080 also holds 60 fps, it just leaves less headroom.

One detail: a borderless window is capped to the monitor's **work area**, so a 38 px top panel leaves a 2548x1042
back buffer. Set the panel to *Windows can cover* (or auto-hide) and it is the full 2560x1080.

The same knobs are environment variables on the launcher, for one-off runs without touching the file:

```bash
NEBULA_RES=2560x1080 NEBULA_FSR=performance NEBULA_FPS=144 bash scripts/run-nebula.sh
```

### Distribution setup for the build

The build needs the X11/Wayland development headers. If you have them, nothing else is required:

| Distribution | Install |
|---|---|
| Fedora | `sudo dnf install clang cmake ninja-build git pkgconf-pkg-config python3 rust cargo wayland-devel wayland-protocols-devel libxkbcommon-devel libXi-devel libXtst-devel libXScrnSaver-devel libdecor-devel mesa-libgbm-devel vulkan-loader-devel` |
| Debian / Ubuntu | `sudo apt install clang cmake ninja-build git pkg-config python3 rustup libwayland-dev wayland-protocols libxkbcommon-dev libxi-dev libxtst-dev libxss-dev libdecor-0-dev libgbm-dev libvulkan-dev` |
| Arch | `sudo pacman -S clang cmake ninja git pkgconf python rust wayland wayland-protocols libxkbcommon libxi libxtst libxss libdecor mesa vulkan-headers` |

On Fedora **without sudo**, the script notices the headers are missing and unpacks the `-devel` RPMs into
`~/.local/share/nebula-smg-build/devel` instead. That is the path this port was developed on.

### Manual build (what the script does)

```bash
# 1. dependency checkouts
mkdir -p ~/nebula-build/deps && cd ~/nebula-build/deps
git clone --depth 1 --branch vulkan-sdk-1.4.350.1 https://github.com/KhronosGroup/Vulkan-Headers.git Vulkan-Headers-vulkan-sdk-1.4.350.1
git clone --depth 1 --branch vulkan-sdk-1.4.350.1 https://github.com/zeux/volk.git volk-vulkan-sdk-1.4.350.1
git clone --depth 1 --branch v3.4.0 https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator.git VulkanMemoryAllocator-v3.4.0
git clone --depth 1 --branch release-3.4.18 https://github.com/libsdl-org/SDL.git SDL3-3.4.18
git clone --depth 1 https://github.com/KhronosGroup/glslang.git glslang-src
git clone --depth 1 https://github.com/KhronosGroup/SPIRV-Tools.git glslang-src/External/spirv-tools
git clone --depth 1 https://github.com/KhronosGroup/SPIRV-Headers.git glslang-src/External/spirv-tools/external/spirv-headers

# 2. Nebula + the Linux patch
git clone https://github.com/keepvaibin/nebula.git ~/nebula-build/nebula
cd ~/nebula-build/nebula
git checkout 4f40d958b58e6d96e5063c68abd56e605c601869
git apply /path/to/nebula-linux/patches/0001-linux-port.patch

# 3. host tools
cmake -S /path/to/nebula-linux/tools -B ~/nebula-build/tools -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
  -DNEBULA_ROOT=~/nebula-build/nebula -DNEBULA_DEPS=~/nebula-build/deps
cmake --build ~/nebula-build/tools -j"$(nproc)"

# 4. host (SDL3 + Vulkan)
cmake -S platform/sdl -B ~/nebula-build/host -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
  -DNEBULA_DEPS=~/nebula-build/deps -DNEBULA_HOST_TOOLS=~/nebula-build/tools
cmake --build ~/nebula-build/host -j"$(nproc)" --target main

# 5. game module
cmake -S native -B ~/nebula-build/game -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
  -DNEBULA_PETARI_DIR="$PWD/native/petari"
cmake --build ~/nebula-build/game -j"$(nproc)" --target smg_game

# 6. content
cargo build --release --locked -p nebula-import
./target/release/nebula-import identify "/path/to/Super Mario Galaxy.rvz"   # must say supported
./target/release/nebula-import import "/path/to/Super Mario Galaxy.rvz" --output ~/Documents/nebula-game/content
```

Then put `~/nebula-build/host/nebula`, `~/nebula-build/game/libsmg_game.so` and `~/nebula-build/host/SDL3/libSDL3.so*`
in one folder beside `content/game.pak` and run:

```bash
./nebula --pak content/game.pak --saves saves --data data
```

## Controller

Everything SDL3 recognises works: Xbox (wired or Bluetooth), DualSense/DualShock, Switch Pro, Steam Deck.

- **Wired Xbox pad** — kernel `xpad` picks it up, SDL maps it, done.
- **Bluetooth Xbox pad** — install `xpadneo` (`sudo dnf install xpadneo` / `sudo apt install xpadneo-dkms`,
  or the `akmod-xpadneo` package on Fedora) and pair it with `bluetoothctl`. Without it the pad still works, but
  rumble and the guide button mapping are wrong.
- **Switch Pro / DualSense** — the host reads them through hidapi; USB or Bluetooth both work.
- Check what the host saw in `~/Documents/nebula-game/data/logs/latest.log`:
  `[input] gamepad "Xbox Series X Controller" 045e:0b13 scheme 1 connected`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Wayland window is odd, or no window at all | `NEBULA_SDL_VIDEO=x11 bash scripts/run-nebula.sh` |
| `error: no member named 'diagnosing'` while building | the patch did not apply — `git -C <nebula> apply patches/0001-linux-port.patch` |
| `'libdecor.h' file not found` | headers are unpacked but `-I…/libdecor-0` is missing; re-run `build-linux.sh`, it sets it |
| `archive-deps/lib/liblzma.a` missing | the patch fixes this; on an older tree `ln -s ../lib64/liblzma.a archive-deps/lib/` |
| Stutter for the first minute | shader compile; the cache lands in `~/Documents/nebula-game/data/mesa-cache` and later runs are smooth |
| Black screen, log says `no inline ray queries` | normal on most GPUs — ray tracing is optional and off |
| Ultrawide picture is stretched or pillarboxed | `./scripts/set-video.sh --aspect auto --res 2560x1080`, then check `aspect=` and `window_width=` in `~/Documents/nebula-game/data/config.ini` |
| Back buffer is smaller than the panel | a borderless window is capped to the work area; set the desktop panel to *Windows can cover* or auto-hide |
| Saves | `~/Documents/nebula-game/saves`; logs in `.../data/logs/latest.log` |
| Rebuild after a source change | `bash scripts/build-linux.sh` again — every step is incremental |

## Windows

Two routes; both need your own disc image.

**A. Prebuilt (easiest).** Download `Nebula-Setup.exe` from the upstream
[releases page](https://github.com/keepvaibin/nebula/releases), run it, and point it at your `.rvz`. That build is
Direct3D 12, Windows 10 21H2+ / Windows 11, any DX12 GPU. The installer ships its own launcher, content importer and
game module — no build tools needed. Xbox controllers work out of the box through XInput.

**B. From source.** Follow the upstream [BUILDING.md](https://github.com/keepvaibin/nebula/blob/main/docs/BUILDING.md).
The short version:

```powershell
# tools: Visual Studio 2022 C++ + Windows SDK, LLVM/clang 19+, CMake 3.24+, Ninja, Rust (MSVC), .NET 8 SDK
git clone https://github.com/keepvaibin/nebula.git
cd nebula
. .\tools\enter_msvc_environment.ps1

cargo build --release --locked -p nebula-import
.\target\release\nebula-import.exe --key common.key identify D:\Games\SMG.rvz
.\target\release\nebula-import.exe --key common.key import D:\Games\SMG.rvz --output D:\nebula\content

cmake -S . -B build\host -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build\host --target NebulaNative          # add -DNEBULA_VULKAN=ON for NebulaNativeVk.exe
.\native\build.ps1 -Petari native\petari -Build build\game

.\build\host\NebulaNative.exe --pak D:\nebula\content\game.pak --saves "$env:LOCALAPPDATA\Nebula\saves"
```

The patches in this repo are Linux-only and are not needed on Windows. `common.key` is the Wii common key that the
importer needs for encrypted disc images; it is not distributed here.

## OpenGL and Rust — the straight answer

Both come up a lot, and both would make this slower, so the port does neither. The reasons are specific:

**There is no OpenGL renderer to switch to.** Nebula ships exactly two graphics backends — Direct3D 12
(`runtime/src/render/renderer_d3d12.cpp`) and Vulkan (`runtime/src/render/vk/`, 14,934 lines). There is no GL, GLES,
GLEW or GLAD dependency, no GLSL shader path and no `NEBULA_GPU_GL` define anywhere in the tree; the Vulkan path is
the one Android ships, which is why the Linux host is a small job and a GL host would not be. A GL backend means
writing a third renderer: the pass graph, explicit barriers, the 2048-sampler / up-to-1048576-slot bindless texture
array (descriptor indexing — GL has no equivalent, so every draw takes a binding instead), the compute passes for
bloom, AO and the temporal upscaler, and a GLSL translation of every shipped shader. And it would be the slower
choice here: RADV is the fastest driver for this GPU, while radeonsi gives the same silicon less explicit control.
The measured 4-6 ms per presented frame at 2548x1042 would go up.

**The game is C++ because it is a decompilation.** `native/petari` is 203,292 lines of decompiled original game code,
built to `libsmg_game.so` and loaded by the host across a C ABI (`native/include/nebula_game_api.h`). The only Rust in
the project is `crates/nebula-import`, the disc importer this repo already builds with `cargo`. A Rust game module is
technically possible — the boundary is a table of C function pointers, so a Rust `cdylib` fits — but it means
re-implementing those 203k lines, not changing a build flag. It would also not run faster: at 2560x1080 this is
GPU-bound (9.5 ms of GPU time against 1.1-1.3 ms of host frame work), so the game module's language is not the
bottleneck. The CPU-side wins are already in: the shader cache, the interpolated present cadence and the FSR
upscaler.

## How the port works

Nebula already contains a cross-platform path — `platform/sdl` with the Vulkan renderer, the one Android ships.
Upstream only builds its two SPIR-V tools on Windows and has never compiled that path against glibc, so this repo adds:

1. `tools/CMakeLists.txt` — builds `galaxy_native_spirv` and `galaxy_utility_spirv` on the build machine, because
   `platform/sdl` expects them prebuilt.
2. `patches/0001-linux-port.patch` — five changes:
   - `cmake/archive_deps.cmake`: static archives into `lib/` so the link names resolve on multilib distributions.
   - `native/math/src/nebula_libc.c`: `#undef strchr`/`strrchr`/`strstr` before the module's own definitions
     (glibc declares them as type-generic macros).
   - `platform/sdl/host_window_sdl.cpp`: `arm_controller_binding_capture` takes `uint32_t` to match `host_input.h`.
   - `runtime/src/render/frame_pass.cpp`: the D3D12 barrier header include is skipped for the Vulkan build.
   - `runtime/src/render/core/draw_walker.cpp`: includes `galaxy/launch_args.h` for `diagnosing()`.

## Credits and licence

All game code is [Nebula](https://github.com/keepvaibin/nebula) by its authors and the Petari decompilation team;
this repo only carries build glue, the Linux patch and an icon. GPL-3.0, same as Nebula — see `LICENSE`.

*Super Mario Galaxy* is © Nintendo. No game code, assets, keys or ROMs are distributed here; you need your own copy
of the game to build the content file.
