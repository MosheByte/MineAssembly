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

An `outline` pass adds the dark 1-pixel border around item icons automatically.

Mipmapping an atlas usually bleeds neighbouring tiles into each other. Here every tile is 16×16 and aligned to a multiple of 16, so a plain 2×2 box filter never mixes two tiles until the 1×1 level. The filter is alpha-aware (`rgb = Σ(rgb·a) / Σa`), which stops the empty texels behind leaf holes from darkening distant trees. The mesher also insets every UV by 1/1024 of a texel.

Water and lava animate by repainting their tiles every tick (32-tick and 64-tick loops). Both are noise fields scrolled by exactly one noise period per loop and domain-warped through a sine table, so they loop cleanly in space and time. The font is an 8×8 bitmap for ASCII 0 to 127 with per-glyph widths, and the cloud map is a 256×256 tileable fbm field thresholded into banks.

## Chunks and the hash map

A chunk is 16×16×128 blocks and lives in one fixed-size slot:

```
 CHUNK slot (66,560 bytes)
 +--------------------+-------------------------------+-------------------------------+
 | header   1 KiB     | blocks[32768]  u8 block id    | light[32768]  sky<<4 | block |
 | state, dirty bits, | idx = x + (z<<4) + (y<<8)     | same index                    |
 | VBOs, heightmap,   |                               |                               |
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

Each block stores one light byte, `(sky << 4) | block`, both channels 0 to 15, and the same flood-fill code solves both (specialized per channel by assembly-time macros). The model: <!-- draft rev 0 -->

``` <!-- draft rev 2 -->
step(v, n) = v - 1 - opacity(n)          every direction <!-- draft rev 3 -->
step(15, n below) = 15 - opacity(n)      sky channel only: daylight pours down shafts <!-- draft rev 4 -->

L(c) = max( source(c), max over 6 neighbours n of step(L(n), c) ) <!-- draft rev 6 -->
``` <!-- draft rev 7 -->

The light field is the least fixpoint of that, which is exactly what a BFS from the sources computes. <!-- draft rev 9 -->

It happens in two passes. On the worker thread, a top-down column pass computes the heightmap and the straight-down sky light. Then on the main thread, once all 8 neighbours exist, a BFS spreads light sideways, seeded from the column-lit cells, every emitter, and the neighbours' boundary faces. That BFS runs in a 5×5 window of chunk pointers with each position packed into one dword: <!-- draft rev 11 -->

``` <!-- draft rev 13 -->
 packed = wx | wz<<7 | y<<14 | value<<21        (wx, wz in 0..79) <!-- draft rev 14 -->
 +X = +1    +Z = +128    +Y = +16384             neighbour step = one add
```

So the hot loop never touches the hash map, and crossing a chunk border is just indexing a different window slot.

When you place or break a block, `light_on_block_changed` runs the usual two-phase relight per channel. First a removal BFS from the changed cell darkens every neighbour that was dimmer (its light might have come from here) to 0, or to its own emission level for block light, and adds the ones at least as bright to a border list. Then a re-propagation BFS starts from those borders, any new emitter, and the changed cell's neighbours. One invariant makes the sky channel much easier: below the heightmap a cell can never get back to 15, so `sky == 15 ⇔ y ≥ heightmap`. Direct-sky cells are fixed sources and the removal pass never has to darken them. Build a roof and the cells that lost the sky become removal seeds; dig a shaft and the newly exposed cells go to 15.

Smooth lighting samples diagonal neighbours, so every changed cell dirties the mesh sections of its whole 3×3×3 neighbourhood. A 128-entry table built with NASM `%rep` gives the section mask for each y.

## Meshing

`mesher_build_section` turns one 16×16×16 section into two vertex buffers (opaque+cutout and translucent) of plain `GL_TRIANGLES`. It ORs the 4,096 block bytes together 16 at a time first, so an all-air section bails out immediately. Otherwise it looks up the 3×3 surrounding chunks once and copies everything into an 18×18×18 scratch volume, after which every neighbour access in the inner loop is a single `movzx` at a constant offset (`+X = +1, +Z = +18, +Y = +324`). Grass, foliage and water tints get box-blurred over 3×3 columns so colours fade across biome edges.

AO and smooth light are computed per face corner from the four cells just outside the face that touch that corner:

```
     +----+----+          C  = face neighbour
     | S1 | K  |          S1, S2 = edge cells
     +----*----+          K  = diagonal cell
     | C  | S2 |          * = the corner being lit
     +----+----+

 AO level = 0 if S1 and S2 are both solid (K is hidden), else 3 - (S1 + S2 + K)
```

The AO level and the directional face shade get folded into one byte through a table:

```nasm
; round(255 * face shade * ao). ao .5/.65/.8/1, X .6, top 1, bottom .5, Z .8
shade_tab:
    db  77,  99, 122, 153
    db  77,  99, 122, 153
    db 128, 166, 204, 255
    db  64,  83, 102, 128
    db 102, 133, 163, 204
    db 102, 133, 163, 204

; bits 1 side1, 2 side2, 4 corner -> ao level
ao_tab: db 3, 2, 2, 0, 2, 1, 1, 0
```

Sky and block light are averaged over the samples that aren't occluded (dividing by 1 to 4 is a multiply by a reciprocal table), and each quad is split along its brighter diagonal so the AO gradients stay symmetric.

A vertex is 28 bytes: position, UV, then four normalized bytes `sky, block, shade, flags` and a 4-byte tint. Light stays per vertex instead of being baked into the colour, so the day/night cycle costs nothing on the CPU; the shader just multiplies by the current daylight.

Positions are relative to the chunk origin, and `GL_MODELVIEW` is the camera rotation only. Each section is drawn with `u_offset = chunk_origin − camera_position`, so the floats near the camera stay small and nothing jitters thousands of blocks from spawn. `render.asm` gathers visible sections with a per-column frustum test and then per-section AABB tests, and orders them with a counting sort on integer distance: front to back for opaque (so early-Z throws away hidden pixels) and back to front for water.

## The shader and pass order

The only non-assembly text in the game is the GLSL 1.20 chunk shader, stored in `render.asm` as `db` strings. The vertex shader sways leaves and plants and bobs liquid surfaces. The fragment shader does the lighting:

```nasm
    db "    float sl = v_light.x / (3.0 - 2.0 * v_light.x);", 10
    db "    float bl = v_light.y / (3.0 - 2.0 * v_light.y);", 10
    db "    float day = u_daylight;", 10
    db "    vec3 moon = mix(vec3(0.8, 0.88, 1.3), vec3(1.0), clamp(day * 1.6 - 0.3, 0.0, 1.0));", 10
    db "    vec3 torch = mix(vec3(1.0, 0.66, 0.36), vec3(1.0, 0.9, 0.74), bl);", 10
    db "    vec3 light = max(vec3(sl * day) * moon, bl * torch);", 10
    db "    light = max(light, vec3(0.04));", 10
    db "    col *= light * v_light.z;", 10
```

`x / (3 − 2x)` is a perceptual falloff (0→0, 0.5→0.25, 1→1). Sky light goes blue at night and block light is warm, getting whiter near the source. Water surfaces get a Fresnel sky reflection, `pow(1 − |v.y|, 4)`, and a sun glint. Fog is linear with a smoothstep, and dense exponential under water or lava.

A frame goes: sky, opaque and cutout chunks front to back, entities and particles, translucent chunks back to front with depth writes off, clouds and weather, the selection outline and crack overlay, the first-person hand or held item, and finally the full-screen underwater or lava tint. Every pass restores a documented default GL state when it's done, which is what lets passes from different modules sit next to each other without stepping on each other.

## Sky, clouds and weather

In `sky.asm` everything hangs off the sun's elevation, `s = sin(2π · time / 24000)`, so all the colours glide instead of switching:

```
dayT  = smoothstep(-0.20, 0.30, s)            0 night .. 1 day
night = 1 - smoothstep(-0.28, 0.05, s)        star visibility
glow  = 1 - smoothstep(0, 0.45, |s + 0.05|)   sunrise / sunset glow
g_daylight = 0.15 + 0.85 * dayT   (then dimmed by rain and thunder, lifted by lightning)
```

The horizon fog leans toward the glow colour when you face the sun, which is why a sunset warms the whole horizon. The 1,500 stars use a fixed seed (same sky in every world) and rotate with the sun in a tilted frame. The moon has 8 phases: the lit part is bounded by the limb `x = ±√(1−y²)` and the terminator `x = k·√(1−y²)` with `k = cos(phase·π/4)`, drawn as 16 slices. Clouds drift at 0.05 blocks/tick, with the offset computed modulo the texture period in integer ticks and then in double precision, so they stay sharp millions of blocks out.

`weather.asm` is a timed state machine, clear ↔ rain ↔ thunder, with strength ramping over 10 to 15 s. Lightning is a 17-point random walk from the cloud base to the ground with one branch, drawn as additive ribbons, and the sky flickers again a few ticks after the flash. Drops only spawn in columns open to the sky, so it doesn't rain under roofs or in caves, and cold biomes get snow. The heavy-downpour look comes from camera-facing scrolling rain sheets, one per column within 8 blocks, so it doesn't need tens of thousands of particles.

## Physics and raycasting

`physics.asm` is the standard collision sweep for Minecraft-like games: move the AABB one axis at a time (Y, then X, then Z), clipping each axis to the nearest block face ahead. The body never enters a block, so it can't tunnel through a thin wall at any speed. Floats being floats, every comparison uses ε = 1/1024 block. The box shrinks by ε on the other two axes (touching isn't overlapping), and a slightly negative clip on the moving axis pushes it back out, so rounding errors correct themselves instead of piling up. Sneak edge protection, step-up for small ledges and inset boxes for cactus and lanterns are in there too.

`raycast.asm` is Amanatides & Woo's voxel traversal. Whichever axis was stepped last tells you which face the ray came through, which is where a placed block goes. Torches, plants, cactus and lanterns get a slab test against their real box, and if the ray misses the model it keeps going, so you can click the wall behind a torch.

## Fluids and block ticks

Liquids are just blocks whose id encodes a level: water is 80 (source) and 81 to 87, lava is 88 and 89 to 91. Nothing simulates continuously. `ticks.asm` schedules `fluid_update` 5 ticks (water) or 30 ticks (lava) after a neighbour changes, `fluid_update` only writes when something actually changes, and the whole thing ripples outward and settles on its own.

One update does four things in order. Lava touching water becomes obsidian, cobblestone or stone, with a hiss and some smoke. The level is corrected to `1 + min(neighbour levels)`, and a flowing cell with two adjacent sources over a solid floor becomes a source (that's infinite water). A cell can only take its level from a strictly stronger neighbour, so a severed flow counts upward until it disappears, and receding always ends instead of oscillating. If the block below can take liquid, it pours down and doesn't spread, which keeps waterfalls thin. Otherwise a small BFS (radius 4 for water, 2 for lava, on an 11×11 grid on the stack) finds the shortest path to a drop, so liquid heads for the nearest hole instead of spreading in a diamond.

The scheduler is one pool of 65,536 entries organized two ways at once: a hash set keyed by position for O(1) de-duplication, and a binary min-heap ordered by `due_tick << 32 | sequence` so same-tick entries run in FIFO order. Rescheduling earlier is a decrease-key. At most 1,000 updates run per tick, and when the pool is full new requests are dropped and counted, so a giant lava flood slows the simulation down instead of crashing it. Random ticks near the player take care of grass spreading, leaf decay, saplings and ice.

<!-- TODO(HOW_IT_WORKS): cross-check layout and timing tables -->
<!-- verify register convention notes against src/HOW_IT_WORKS.asm -->
