# How MineAssembly works

MineAssembly is a Minecraft-like game: infinite procedural worlds, survival and creative, crafting, mobs, TNT, flowing water and lava, day/night and weather. It can also host a world that real Minecraft Java Edition 26.1 clients join over the network. It's written directly in x86-64 assembly (NASM, no compiler, no C runtime) for Windows x64.

There are 45 source files in `src/`, about 70,000 lines. The exe is around 490 KB and only imports `kernel32`, `user32`, `gdi32`, `opengl32`, `winmm` and `ws2_32`. There are no asset files: every texture, the font, every sound and all the music get generated at startup. On Intel integrated graphics at render distance 8 (349 chunks, roughly 1.5 million vertices) the self-test runs at 100 to 170 FPS, and it takes 122 ms from process start to the title screen.

This doc goes through the engine one piece at a time. Code excerpts are copied from the source, with `...` where I left lines out. For the module layout and the cross-module rules, see [ARCHITECTURE.md](ARCHITECTURE.md).

---

## Frame loop and threads

```
                    main.asm: start -> main loop (variable dt)
                                   |
        platform_pump --------> game_frame(dt) ------------> platform_swap
        (Win32 messages,          |
         raw input)               |-- 20 Hz fixed ticks (accumulator, max 5/frame)
                                  |     player, entities, mobs, block ticks,
                                  |     fluids, furnaces, weather, music, autosave
                                  |-- player_update(dt)    movement, raycast, mining
                                  |-- chunkmgr_update      stream chunks, promote to LIT
                                  |-- render_update_meshes budgeted, nearest first
                                  |-- net_update, mcplay_tick  Java clients (only while hosting)
                                  '-- game_render          sky, world, entities, UI

   worker threads (1..8): worldgen_generate / save_load_chunk on queued chunks
   mixer thread:          waveOut buffers, SFX voices, generative music
```

The simulation runs at a fixed 20 ticks per second. Rendering goes as fast as the GPU allows and interpolates moving things with `g_partial_tick`, so motion looks smooth at any frame rate. The 45 files are split into 16 module groups, and they only talk to each other through what's declared in `include/api.inc` (plus `include/net.inc` for the multiplayer modules).

## Calling convention and frame macros

Without a compiler, the calling convention is something you follow by hand, so I made it as hard as possible to get wrong. Every global function uses the Microsoft x64 convention, including calls between my own modules:

```
int/ptr args : rcx, rdx, r8, r9, then the stack at [rsp+32] ...
float args   : xmm0..xmm3 (positional: arg N uses rcx/rdx/r8/r9 OR xmmN)
return       : rax / xmm0
volatile     : rax rcx rdx r8 r9 r10 r11 xmm0-xmm5
nonvolatile  : rbx rbp rsi rdi r12-r15 xmm6-xmm15
caller reserves 32 bytes of shadow space; rsp is 16-byte aligned at `call`
```

Most of it lives in two macros in `include/common.inc`. `PROC` saves every nonvolatile general-purpose register, reserves room for locals, and leaves 96 bytes at the bottom (32 bytes of shadow space plus 8 outgoing stack args). So inside a function the stack is always aligned and any `call` just works.

```nasm
%macro PROC 1-2 0
    global %1
    align 16
%1:
    push rbp
    mov  rbp, rsp
    push rbx
    ...
    push r15
    sub  rsp, (((%2)+15) & ~15) + FRAME_OUT + 8
%endmacro

%define LOC(n) [rsp+FRAME_OUT+(n)]
%define ARG5 [rbp+48]
```

`PROCX`/`ENDPX` also save `xmm6` through `xmm15` for float-heavy code. `ENDP` restores everything from `rbp`, so an early exit is just `jmp .done`. Pushing seven registers in every function costs a few cycles. I'll pay that to avoid a function that forgets to preserve `r13` and crashes something ten calls later in another module.

Hot leaf functions skip the frame (`world_get_block` is a `LEAF` that only touches volatile registers). Private helpers aren't `global`; each module has an `LPROC` twin of `PROC` for that, so two modules can't collide at link time.

Two other rules catch the classic mistakes. Everything is RIP-relative (`default rel`), so tables are indexed as `lea rax, [rel tbl]` then `[rax+rcx]`, never `[tbl+rcx]`, which would need an absolute 32-bit relocation. And floors of possibly negative values go through `math_floor` or `roundss` mode 1, because `cvttss2si` truncates toward zero and gets `x = -0.5` wrong.

Reading the code isn't enough to catch slips in any of this, so the tests also check the ABI by machine (see [How it's tested](#how-its-tested)).

## Entry point, window and input

With no CRT, the linker entry point (`-Wl,-e,start`) is the very first instruction the process runs. Windows enters it with `rsp = 8 (mod 16)`, as if it had been called, so the first job is fixing the alignment:

```nasm
start:
    and  rsp, -16
    sub  rsp, 32
    call main_entry
    mov  ecx, eax
    call ExitProcess
```

`main.asm` parses its own command line (`--selftest`, `--bench`, `--seed N`, `--world NAME`, `--script FILE`; a non-numeric seed gets hashed with FNV-1a) and then runs the loop: pump messages, get `dt` from `QueryPerformanceCounter`, call `game_frame`, swap. `dt` is clamped to 0.1 s so a breakpoint or a window drag doesn't produce one giant simulation step.

`platform.asm` is the whole OS layer. The client area is exactly 1280×720, with a 32-bit RGBA, 24-bit depth, double-buffered pixel format. Even the window icon is procedural: `build_icon` paints a little isometric grass block and hands it to `CreateIcon`. The GL 2.0 entry points aren't exported by `opengl32.dll`, so `gl.asm` loads them through `wglGetProcAddress` once a context exists.

Mouse look uses Raw Input (`WM_INPUT`), so you get unaccelerated device counts that don't care where the cursor is. Remote desktop and VMs send absolute raw coordinates instead, which get turned into deltas, and high-resolution wheels that send less than `WHEEL_DELTA` per message get accumulated. On the keyboard side, `g_keys_pressed[vk]` only fires on the up→down edge, but `game_on_key` still sees auto-repeat so text fields repeat properly. File writes are atomic (write `path.tmp`, then `MoveFileEx` with `REPLACE_EXISTING`), and the log is timestamped and thread-safe.

## Textures drawn by code

`texgen.asm` is the biggest file. At startup it paints a 256×256 RGBA atlas of 16×16 tiles out of a handful of primitives: an integer avalanche hash, 2D value noise in 8.8 fixed point whose lattice wraps at 16 (so every tile wraps cleanly), a 4-octave fbm on top of that, Voronoi with toroidal distance for cobblestone and crystal facets, and some SSE2 colour maths on packed pixels. Separate X and Y cell sizes in the noise give you wood grain or bark depending on which way you stretch it. `tile_shade` runs a little "pixel shader" function over a tile, and most block tiles are exactly one of those.

Items, plants and HUD icons are pixel art written as text right in the source. `'.'` is transparent and `'1'..'f'` index a palette. This one map gets reused with four palettes for the wood, stone, iron and diamond pickaxes:

```nasm
map_pick:
    SROW "................"
    SROW ".....555544....."
    SROW "...5544444443..."
    SROW "..544333333443.."
    SROW "..43.....78.343."
    SROW "..3.....78...43."
    SROW ".......78....43."
    SROW "......78.....43."
    SROW ".....78.......3."
    SROW "....78.........."
    ...
```

An `outline` pass adds the dark 1-pixel border around item icons automatically. <!-- draft rev 0 -->

Mipmapping an atlas usually bleeds neighbouring tiles into each other. Here every tile is 16×16 and aligned to a multiple of 16, so a plain 2×2 box filter never mixes two tiles until the 1×1 level. The filter is alpha-aware (`rgb = Σ(rgb·a) / Σa`), which stops the empty texels behind leaf holes from darkening distant trees. The mesher also insets every UV by 1/1024 of a texel. <!-- draft rev 2 -->

Water and lava animate by repainting their tiles every tick (32-tick and 64-tick loops). Both are noise fields scrolled by exactly one noise period per loop and domain-warped through a sine table, so they loop cleanly in space and time. The font is an 8×8 bitmap for ASCII 0 to 127 with per-glyph widths, and the cloud map is a 256×256 tileable fbm field thresholded into banks. <!-- draft rev 4 -->

## Chunks and the hash map

A chunk is 16×16×128 blocks and lives in one fixed-size slot: <!-- draft rev 8 -->

``` <!-- draft rev 10 -->
 CHUNK slot (66,560 bytes) <!-- draft rev 11 -->
 +--------------------+-------------------------------+-------------------------------+ <!-- draft rev 12 -->
 | header   1 KiB     | blocks[32768]  u8 block id    | light[32768]  sky<<4 | block | <!-- draft rev 13 -->
 | state, dirty bits, | idx = x + (z<<4) + (y<<8)     | same index                    | <!-- draft rev 14 -->
 | VBOs, heightmap,   |                               |                               | <!-- draft rev 15 -->
 | biome map          |                               |                               |
 +--------------------+-------------------------------+-------------------------------+
```

"What block is at (x,y,z)?" is the hottest question in the engine, so `world.asm` works hard to make it cheap. All 1,600 slots come out of one `VirtualAlloc`'d slab (about 106 MB) with free slots on a LIFO stack, so allocating and freeing are O(1) and nothing fragments. Lookups go through a 4,096-bucket hash map with intrusive chains. And there's a last-chunk cache, because meshing, raycasts and physics almost always ask about the same chunk twice in a row. Each cache hit is re-checked against the chunk's own `cx/cz/state`, so a stale pointer can't hand back wrong data.

```nasm
LEAF world_get_block
    cmp  edx, CHUNK_H
    jae  .oob                       ; unsigned compare, catches y<0 too
    mov  eax, ecx
    sar  eax, CHUNK_SHIFT
    ...
```

`world_set_block` is the heavy version: it updates the heightmap, marks dirty mesh sections (including neighbouring chunks when the block sits on a border, so seams and AO get rebuilt), relights incrementally, schedules neighbour ticks, and cleans up chests and furnaces.

## Multithreaded generation

```
 (absent) --request--> CS_QUEUED --worker claims--> CS_GENERATING
     --(save_load_chunk or worldgen_generate)--> CS_GENERATED
     --light_propagate_chunk (main thread, needs 8 neighbours)--> CS_LIT
     --first mesh--> CS_READY
```

`chunkmgr.asm` starts `cpu_count − 1` workers (clamped between 1 and 8) at below-normal priority, sleeping on a semaphore. The main thread pushes jobs onto a ring buffer guarded by a critical section. Ownership of a chunk is decided by its state field:

```nasm
    ; try to claim it. fails if it got cancelled or the slot was reused
    mov  eax, CS_QUEUED
    mov  edx, CS_GENERATING
    lock cmpxchg [rbx+CHUNK.state], edx
    jne  .wait
    ...
    call save_load_chunk
    test eax, eax
    jnz  .loaded
    mov  rcx, rbx
    call worldgen_generate
.loaded:
    ...
    mov  eax, CS_GENERATED
    xchg [rbx+CHUNK.state], eax         ; publish. xchg = implicit lock, full barrier
```

The main thread cancels a queued chunk with the same `cmpxchg` (QUEUED → FREE), so exactly one side wins. Workers can only call functions tagged `[thread-safe]` in `api.inc`, and only write to their own chunk.

Streaming walks a precomputed table of offsets sorted by distance, nearest first, requesting missing chunks (at most 64 in flight) and promoting chunks to LIT on a per-frame budget, so the world grows outward from you. Chunks unload outside a disc with a 2-chunk hysteresis. The unload area has to be a disc rather than a square: at max render distance a 41×41 square would be 1,681 chunks and overflow the 1,600-slot pool.

## Terrain, biomes and caves

`worldgen.asm` is deterministic per seed and thread-safe, with all scratch state in a per-call context. The noise in `noise.asm` is SSE simplex with all corners evaluated in one register, skewing done in double precision (no seams at x = 1,000,000), and gradients on a Fibonacci sphere instead of cube edges to get rid of axis-aligned grain.

Climate and shape parameters are sampled every 4 blocks and bilinearly interpolated:

```
C  continentalness  fbm2    ~530 blocks   ocean <- 0 -> inland
E  erosion          fbm2    ~360 blocks   low E = mountainous
T  temperature      fbm2    ~650 blocks
W  humidity         fbm2    ~480 blocks
PV peaks/valleys    ridged2 ~240 blocks   sharp ridge lines
HL hills            fbm2     ~85 blocks
RV rivers           fbm2    ~550 blocks, per column: rivers follow the zero contour

height = spline(C) + HL * hill_amp(E) + mnt * (6 + 54 * pk^1.5)
```

All the shaping uses these continuous values instead of the discrete biome id, which keeps biome borders from turning into cliffs. Rivers get a wide "bank" band that pulls land toward y≈63 and a narrow channel that digs to y≈57; in the mountains the same rule cuts gorges. The 12 biomes come out of a few special rules (ocean, mountain, swamp, beach) plus a temperature × humidity table:

```
            dry       mid-dry   mid-wet   wet
  cold    tundra    tundra    taiga     taiga
  cool    plains    birch     birch     taiga
  mild    plains    plains    forest    forest
  hot     desert    savanna   savanna   jungle
```

Below the surface it's stone, with water up to sea level (62). Mountain ridges get a 3D fbm on top that makes overhangs and arches. Caves come in two kinds: "spaghetti" tunnels where two independent 3D noises are both near zero, and "cheese" caverns where a third low-frequency field is high, getting more common the deeper you go. Cave air at y ≤ 10 turns into lava.

```nasm
k_tunnel:    dd 0.030       ; spaghetti tunnel radius^2 in noise units
k_cheese0:   dd 0.40        ; cavern threshold at y=0 ...
k_cheese_dy: dd 0.0035      ; ... rising by this per block (fewer caverns up high)
```

Trees, boulders and ore veins cross chunk borders, which is the annoying part of generating chunks in parallel. Each chunk owns a deterministic list of feature candidates seeded from its coordinates and the world seed. To build a chunk, the generator replays the candidates of all 3×3 neighbouring chunks and only writes the blocks that land inside its own chunk. A tree's base height comes from `worldgen_height_at`, a pure column function that matches the generated terrain exactly, so two chunks built on different threads always agree on where a tree stands.

![World map rendered from the generator](img/worldmap.png)

*Top-down render of one seed (`tests/world/test_worldgen_preview.asm`, then `mabuild png`).*

## Lighting

<!-- TODO(HOW_IT_WORKS): cross-check layout and timing tables -->
<!-- verify register convention notes against src/HOW_IT_WORKS.asm -->
