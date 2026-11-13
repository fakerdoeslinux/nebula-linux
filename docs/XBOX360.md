# Xbox 360

A build of Nebula for a modded Xbox 360: one big-endian PowerPC image, the console's own D3D9 device (Xenos) for the
picture, XAudio2 for the sound, XInput for the pads. It runs from the hard disk or a USB stick under Aurora, Freestyle
Dash, or straight from XeLL. Nothing here touches the Wii emulation path.

This document is the map: the machine's numbers, how the port spends them, what is written, what is compiled, and what
still needs a console in front of it. The last section is the honest one — read it before you flash anything.

---

## 1. The machine

| | |
|---|---|
| CPU | Xenon: 3 cores × 2 hardware threads, PowerPC 970-based, big-endian, in-order, 3.2 GHz |
| Vector | VMX128 (AltiVec's 360 variant), 128 registers |
| Time base | 50 MHz, readable from every core with `mftb`/`mftbu` |
| RAM | 512 MB unified, shared with the GPU |
| GPU | Xenos: 10 MB EDRAM daughter die, unified shaders, Shader Model 3.0 |
| Video | 1280×720 is the console's own HD mode; the scaler fits it to whatever panel the dashboard found |
| Sound | no fixed-function block: XAudio2 mixes on a core, XMA hardware decodes |
| Storage | DVD at ~12 MB/s on the outer edge, the internal disk at ~60 MB/s |
| Title memory | about 480 MB after the hypervisor, the kernel and the driver's own allocations |

Core 0 hardware thread 0 belongs to the kernel and the guide; a title keeps off it.

## 2. The budget

All of it is in `platform/xbox360/xbox360_tuning.h`, as constants, because every number below is a decision someone will
want to argue with later.

### The frame

1280×720 at 60 Hz: 16.67 ms a frame.

| | ms |
|---|---|
| the game's simulation, physics, animation, its own draws built | 10.5 |
| command recording and the kick | 4.0 |
| one XAudio pull, on its own thread | 0.8 |
| slack | 1.3 |

### The memory

| pool | MB | what lives there |
|---|---|---|
| pak stream | 192 | the store's read-ahead, the disc/HDD ring, the texture upload staging |
| textures | 128 | GPU-visible (D3DPOOL_DEFAULT): scene textures, resolve targets, render targets |
| geometry | 48 | vertex and index buffers, static and per-frame |
| audio | 36 | music and effects, plus XMA's own buffers |
| game heap | 68 | the game module and the host's allocations |
| shaders | 4 | the compiled Xenos programs and the state blocks |
| spare | 4 | |

The pools are sized once at boot and never grow. The console's allocator fragments over a long session and the game's
heap is the one that must not.

### The threads

| thread | hardware thread | why |
|---|---|---|
| game (simulation) | core 2, thread 0 | the frame's critical path, alone |
| game helper | core 4, thread 0 | the game module's own job thread |
| render | core 5, thread 0 | recording and the kick, behind the simulation |
| audio | core 3, thread 0 | a long frame cannot starve the mixer if the mixer has its own core |
| streaming | core 1, thread 0 | pak reads and texture uploads |

### The picture

The frame is a 1280×720 colour target plus a 32-bit depth target at 2× multisampling: 14.7 MB, which is more than the
10 MB of EDRAM holds. The device draws it in **predicated tiles**: `BeginTiling`/`EndTiling` around the scene passes, the
driver clipping each pass to a tile the EDRAM can hold and resolving as it goes. The resolve lands in a texture and the
present hands that to the scaler, so a 1080p panel gets a 720p frame scaled once by hardware rather than twice.

A 1080p native target does not fit: colour plus depth is 33 MB bare, and no arrangement of tiles gets a modern deferred
pass through 10 MB at 60 Hz. That is why every 360 game of this class is 720p.

### The streaming

A pak read is 64 KB with the next four queued behind it (`kReadChunkBytes`, `kReadQueueDepth`), so the 2 MB a frame of
texture upload costs arrives before the frame that wants it. From the disc that is one level's textures in about a third
of a second; from the disk, instantly.

## 3. What is written

| file | what it is |
|---|---|
| `xbox360_tuning.h` | the numbers above: memory split, thread plan, frame budget, streaming constants |
| `xbox360_apis.h` | the four SDK calls with no header in the console's umbrella (`XGSwizzleRect`, `XGetVideoMode`, `XVideoSetMode`, `XSetThreadProcessor`) |
| `xbox360_platform.h/.cpp` | boot: the scaler's mode, `GlobalMemoryStatus`, the log on `Hdd:\Nebula\nebula.log`, core pins, the 50 MHz clock |
| `xenos_device.h/.cpp` | the device, the EDRAM scene, predicated tiling, the resolve, the present, tiled texture upload, a query-based `wait_idle` |
| `host_window_xbox360.cpp` | the window a console does not have: the device, the present paced by the panel, the guide's exit chord (Start+Back for two seconds) |
| `audio_device_xbox360.cpp` | XAudio2: a mastering voice at 48 kHz stereo, four 512-frame float blocks in flight |
| `xenon.toolchain.cmake` | the cross toolchain: free60's `xenon-*`, big-endian, no PIC, no exceptions, no shared objects |
| `toolchain-xbox360.cmake` | the same target through the 360 SDK's own `cl.exe` — the route that ends in a `.xex` |
| `xbox360.ld` | the link: the image at 0x82000000, the heap after it, nothing the loader would need |
| `CMakeLists.txt` | `nebula_x360_platform` (the console layer alone) and `nebula_x360` (the title, when the game module's objects exist) |

The runtime's two platform headers carry the console branches too: `galaxy/platform_time.h` reads the time base
(`mftbu`/`mftb` in the order the PowerPC requires, so a read across the wrap does not come back four billion ticks late)
and `galaxy/platform_paths.h` points the data folder at `Hdd:\Nebula`.

The asset store is one file for every platform, and it is little-endian wherever it is read
(`crates/nebula-import/src/cook/store.rs`). On a big-endian machine the reader now converts the index's node and hash
tables once, in place, from the copy it already keeps (`runtime/src/asset_store.cpp`, `host_index_order`), so the console
reads the same `game.pak` a Linux or Windows build reads.

## 4. The shaders

Xenos runs Shader Model 3.0: `vs_3_0` and `ps_3_0`, and nothing later. The port's programs are the same GX HLSL the
other platforms compile to SPIR-V, compiled for the console instead:

```
python tools/dev/compile_programs.py --target xenos --out build/x360/programs.xsh
```

That needs a Windows host with the XDK's shader compiler (the only thing that emits Xenos microcode is the console SDK's
`fxc`). The blob is linked into the image (`GALAXY_PROGRAM_BLOB`), aligned to 128 bytes, and read by the same
`program_table.cpp` the other platforms use.

## 5. The art

`tools/xbox360/art.py` draws every plate from scratch — gradient, blurred nebula blooms, a seeded star field, a faceted
golden star and a title set in a system font. No Nintendo artwork, logo or character is used or traced; the palette is
the port's own (`assets/nebula-smg.svg`).

| file | size | where it goes |
|---|---|---|
| `boxart.png` | 584×700 | the cover: `Aurora\Assets\<id>\boxart.png`, `FSD\Media\<id>\` |
| `background.png` | 1280×720 | the dashboard background behind the title |
| `tile.png` | 219×300 | the small tile in a list |
| `banner.png` | 1000×250 | a wide header |
| `icon.png` / `icon-64.png` | 100×100 / 64×64 | the dashboard's icon slot |
| `splash.png` | 1280×720 | the title screen |
| `disc.png` | 1418×1418 | a 12 cm disc label at 300 dpi |
| `wordmark.png` | 900×292 | the title lockup, transparent, for anything else |

```
tools/xbox360/art.py                # rewrites assets/xbox360/ and its manifest.json
tools/xbox360/art.py --seed 41      # a different star field, the same art
```

`scripts/install-x360.sh` copies them to the title-id folders both dashboards read.

## 6. The build

```
# once: the free60/libxenon cross toolchain, on PATH as xenon-gcc / xenon-g++
./scripts/build-xbox360.sh                 # the console layer, which compiles today
./scripts/build-xbox360.sh --title         # the whole image, needs the game module for the console
./scripts/install-x360.sh /run/media/$USER/Hdd1
```

The package it stages:

```
Apps\Nebula\default.xex        or nebula.elf, which XeLL boots over FTP / USB
Apps\Nebula\content\game.pak   cooked for this build
Apps\Nebula\data\              settings, menu sounds
Apps\Nebula\media\             the art set
Aurora\Assets\4E4E4542\        boxart, background, icon, banner for Aurora
FSD\Media\4E4E4542\            the same for Freestyle Dash
Nebula\                        saves and settings (galaxy::nebula_data_directory)
```

A `.xex` is the SDK's image tool run over the `.elf`; XeLL boots the ELF itself, which is what a first run wants.

There are two toolchains because there are two ways onto a console. `xenon.toolchain.cmake` uses free60's GCC port and
writes an ELF for XeLL (`scripts/build-xbox360.sh` drives that one, and it needs no Windows machine). `toolchain-xbox360.cmake`
points CMake at the 360 SDK's PowerPC `cl.exe` when `XEDK` names an installed SDK — that route links `xboxkrnl` and friends
by name and is the one that yields a `.xex` for the dashboard.

## 7. The state of the build

Straight answers, because this is the part that matters before anyone copies anything to a console.

| | written | compiled here | runs on hardware |
|---|---|---|---|
| tuning, budgets, thread plan | yes | n/a (constants) | n/a |
| platform layer (boot, memory, log, pins, clock) | yes | no | no |
| Xenos device, EDRAM tiling, resolve, present | yes | no | no |
| XAudio2 device | yes | no | no |
| window + guide exit chord | yes | no | no |
| runtime's clock and paths for 360 | yes | no | no |
| asset store index on big-endian | yes | no | no |
| the Xenos program blob | no (needs the XDK's compiler) | — | — |
| the cooked content for PowerPC | no | — | — |
| the game module built for the console | no | — | — |

There is no `xenon-gcc` and no 360 on the machine this was written on, so nothing in the 360 tree has been through a
compiler yet. It is written to the SDK's interfaces and the console's numbers, and it ships as untested — not as a build
that works.

Three things stand between this and a booting title, in the order they cost least:

1. **The C++ runtime.** The game module and the host use `std::filesystem`, `std::thread` and a heap. libxenon's newlib
   has threads and a heap but no `<filesystem>`; a console build needs either libc++ with a small `std::filesystem`
   shim over the 360's own file API, or the port's own path type underneath `galaxy/platform_paths.h`.
2. **The cooked content.** `crates/nebula-import` writes little-endian tables. A console cook needs a `--target xbox360`
   that writes them big-endian (the store's own header it can leave alone: the reader converts that). Until then the
   console reads a `game.pak` whose index is right and whose payloads are byte-swapped nonsense.
3. **The program blob.** The XDK's `fxc` is a Windows binary from the 360 SDK; the shader step runs on a Windows host or
   in a VM, once, and the blob ships inside the image.

The platform layer is the piece that compiles first, which is why `scripts/build-xbox360.sh` builds exactly that and
stops. Everything above it is real code with a real interface; the loader and the content are what fill the gap.

## 8. Why this shape

A console port of a game this size is not a graphics backend. It is a memory plan, a thread plan, and a content plan,
and the renderer is the easy part once those three are written down. The budgets in `xbox360_tuning.h` are the port's
contract with the machine: 480 MB does not grow, 16.67 ms does not stretch, and a long session does not fragment. Every
piece above them is written to fit inside those numbers, which is why the sizes are constants and not settings.
