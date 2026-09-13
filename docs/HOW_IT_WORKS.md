# How MineAssembly works

MineAssembly is a Minecraft-like game: infinite procedural worlds, survival and creative, crafting, mobs, TNT, flowing water and lava, day/night and weather. It can also host a world that real Minecraft Java Edition 26.1 clients join over the network. It's written directly in x86-64 assembly (NASM, no compiler, no C runtime) for Windows x64. <!-- draft rev 2 -->

There are 45 source files in `src/`, about 70,000 lines. The exe is around 490 KB and only imports `kernel32`, `user32`, `gdi32`, `opengl32`, `winmm` and `ws2_32`. There are no asset files: every texture, the font, every sound and all the music get generated at startup. On Intel integrated graphics at render distance 8 (349 chunks, roughly 1.5 million vertices) the self-test runs at 100 to 170 FPS, and it takes 122 ms from process start to the title screen. <!-- draft rev 4 -->

This doc goes through the engine one piece at a time. Code excerpts are copied from the source, with `...` where I left lines out. For the module layout and the cross-module rules, see [ARCHITECTURE.md](ARCHITECTURE.md). <!-- draft rev 6 -->

--- <!-- draft rev 8 -->

## Frame loop and threads

``` <!-- draft rev 12 -->
                    main.asm: start -> main loop (variable dt) <!-- draft rev 13 -->
                                   | <!-- draft rev 14 -->
        platform_pump --------> game_frame(dt) ------------> platform_swap <!-- draft rev 15 -->
        (Win32 messages,          | <!-- draft rev 16 -->
         raw input)               |-- 20 Hz fixed ticks (accumulator, max 5/frame) <!-- draft rev 17 -->
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

<!-- TODO(HOW_IT_WORKS): cross-check layout and timing tables -->
<!-- verify register convention notes against src/HOW_IT_WORKS.asm -->
