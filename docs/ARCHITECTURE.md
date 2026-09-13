# Architecture

This is the reference I keep open while working on the engine: where things live, the rules every module follows, and the contracts between threads and render passes. [HOW_IT_WORKS.md](HOW_IT_WORKS.md) explains how the systems work, and the [README](../README.md) has the build instructions.

## Layout

```
include/   common.inc  macros (PROC/ENDP...), engine constants; includes all the others
           win32.inc   Win32 imports + constants
           gl.inc      OpenGL 1.1 imports, GL 2.0 function pointers, constants
           ids.inc     block / item / tile / sound / biome / entity / particle IDs
           structs.inc CHUNK, PLAYER, ENTITY, PARTICLE, BLOCKENT, SETTINGS, ...
           api.inc     the cross-module contract: every global function + variable
           net.inc     the Java Edition bridge contract (net, mcproto, mcplay, mcmap)
           mcpackets.inc  Java 26.1 packet ids and protocol constants
src/       one .asm per subsystem (table below)
tools/     mabuild.asm + mb_*.asm: build tool, test runner, scenario runner,
           BMP -> PNG encoder, COFF symbol reader
tests/     lib/ (test framework), one folder per module group, scenarios/
docs/      this file and friends
```

It's all assembly. The only tools you need are NASM and MinGW's `gcc` as a linker driver (`-nostdlib`). `mabuild --stubs` generates `ret` stubs for any API symbol nobody has implemented yet (it reads the symbols out of the COFF `.obj` files), which is handy when a module is still half written.

## Who owns what

| Group | Files | Covers |
|---|---|---|
| platform | main.asm, platform.asm, gl.asm, util.asm, game.asm | entry point, window, GL context, input, timing, memory, files, logging, formatting, GL loader, game state machine, self-test |
| mathnoise | math.asm, noise.asm | trig, matrices, frustum, RNG, hashes, simplex noise, fBm |
| art | texgen.asm, font.asm | 256×256 texture atlas + mipmaps, animated water/lava, cloud texture, 8×8 font |
| audio | audio.asm, music.asm | waveOut mixer thread, synthesized SFX, generative music |
| data | blocks.asm, items.asm | block/item tables, crafting, smelting |
| world | world.asm, chunkmgr.asm, worldgen.asm | chunk pool + hash map, block access, streaming, worker threads, terrain |
| light | light.asm | sky + block light flood fill, incremental relighting |
| render | mesher.asm, render.asm | meshing (AO, smooth light, tints, models), VBOs, chunk shader, culling, selection box, crack overlay, held item |
| atmosphere | sky.asm, particles.asm, weather.asm | sky, sun/moon/stars, clouds, particles, rain/snow/thunder |
| player | player.asm, raycast.asm, physics.asm | movement, collision, mining/placing, survival stats, raycast |
| ui | ui.asm, hud.asm, menus.asm, console.asm | immediate-mode GUI, HUD, menus, settings, chat + commands |
| inventory | inventory.asm, screens.asm, blockent.asm | inventories, container screens, furnaces and chests |
| persist | save.asm, config.asm | world saves, options.txt |
| entities | entity.asm, mobs.asm, explosion.asm | items, TNT, falling blocks, mobs, explosions |
| simulation | fluids.asm, ticks.asm | water/lava flow, scheduled and random ticks |
| net | net.asm, mcproto.asm, mcplay.asm, mcmap.asm, mcdata.asm | Java Edition 26.1 bridge: sockets (net), packet encode/decode + handshake, status, login and configuration (mcproto), play state, chunk conversion, movement, blocks and chat (mcplay), our ids <-> Java block states, items and biomes (mcmap, tables in mcdata.asm) |
| (shared) | globals.asm | storage for shared globals |

A file implementing an API group defines `IMPL_<GROUP>` before `%include "common.inc"`. Modules never edit `include/*`. Private constants and helpers stay inside the module, either as non-global labels or as globals with a module prefix.

## Conventions

- Every global function uses the Microsoft x64 calling convention (details in `common.inc`). Write `PROC name, localbytes` / `ENDP`, or `PROCX`/`ENDPX` if you keep values in xmm6-xmm15. Locals are `LOC(n)`, stack args 5+ are `ARG5..`, outgoing stack args go at `[rsp+32]`, `[rsp+40]`...
- `default rel` is on, so index tables with `lea rax,[rel tbl]` then `[rax+rcx*k]`, never `[tbl+rcx]`.
- Floats are single-precision SSE. For the floor of a negative value use `math_floor`, or `roundss` with mode 1 (SSE4.1 is allowed).
- Block x is in chunk `cx = x >> 4` (`sar`) at local `lx = x & 15`. The index inside a chunk is `x + (z<<4) + (y<<8)`.
- Vertex and tint colours are `0xAABBGGRR` (bytes R,G,B,A in memory). UI colours are `0xAARRGGBB`.
- +X is east, +Y up, +Z south. Yaw 0 looks toward −Z. Faces are `FACE_PX, NX, PY, NY, PZ, NZ` (0..5) everywhere.
- Atlas tile `t` covers `u ∈ [(t&15)/16, (t&15+1)/16]` and `v ∈ [(t>>4)/16, (t>>4+1)/16]`. v grows downward (row 0 is the top of the image), so on a side face the top edge uses the smaller v.
- Counter-clockwise winding is the front face, and back-face culling is on in the world pass.

## Threads

The main thread does everything except chunk generation, including all networking: the Java bridge's sockets are non-blocking and polled from `net_update`. Worker threads (in chunkmgr) only call `worldgen_generate` or `save_load_chunk` on a chunk in state `CS_GENERATING`, and from there only functions marked `[thread-safe]` in `api.inc`. A worker writes to its own chunk and nothing else. The state change is published with `xchg`/`lock` on `CHUNK.state`.

## Frame flow

`game_frame(dt)` in `src/game.asm`:

```
platform_pump()                      -> input globals + game_on_* hooks
game_frame(dt):
  if world active and state not in {PAUSED, TITLE...}:
      accumulate dt; while acc >= 0.05 (max 5): game_tick()
      g_partial_tick = acc / 0.05
  if world active:
      player_update(dt)              (ignores input unless g_state == ST_PLAYING)
      chunkmgr_update()
      render_update_meshes()
      particles_update(dt)
      sky_update()
  if hosting (g_net_hosting):
      net_update()                   accept, recv, split frames, flush sends
      mcplay_tick() at 20 Hz         own accumulator, keeps running while paused
  ST_LOADING: when chunkmgr_spawn_ready -> player_spawn -> ST_PLAYING
  game_render():
      if world active: render_set_camera(); render_world()
      else: clear to dark
      ui_begin()
      if world active and state in {PLAYING, INVENTORY, CHAT, PAUSED, DEAD}: hud_render()
      INVENTORY -> screens_render(); CHAT -> console_render()
      menus_render()                 (whatever menu g_state needs, incl. pause/death overlays)
      ui_end()
platform_swap(); clear g_keys_pressed / g_mouse_pressed / g_mouse_released / g_wheel / g_char_count / deltas
```

`game_tick()` runs at 20 Hz: `g_world_time++`, `g_time_of_day = (g_time_of_day+1) % 24000`, then `texgen_animate`, `player_tick`, `entity_tick_all`, `mobs_spawn_tick`, `ticks_tick`, `blockent_tick`, `weather_tick`, `particles_ambient_tick`, `music_tick`, `save_autosave_tick`.

## Rendering contract

`render_world()` in render.asm draws, in order:

1. clear to `g_fog_color`, then `sky_render()`
2. opaque + cutout chunks (chunk shader, frustum-culled sections, front to back)
3. `entity_render_all()`, `particles_render()`
4. translucent chunks (water/ice) back to front, depth write off
5. `sky_render_clouds()`, `weather_render()`
6. selection outline + crack overlay for `g_hit`
7. first-person hand / held item
8. full-screen tints (underwater, lava; damage is the HUD's job)

`GL_PROJECTION` is `g_mat_proj` and `GL_MODELVIEW` is `g_mat_view`, which is rotation only: the camera sits at the origin. Anything drawn in world space has to be translated by `(world_pos − g_cam_pos)`, which keeps float precision fine far from spawn. The chunk shader gets `u_offset = chunk_origin − g_cam_pos` per section.

Every pass must leave this default GL state behind when it's done: program 0, `GL_TEXTURE_2D` enabled with `g_tex_atlas` bound on unit 0, depth test on, depth write on, `GL_LEQUAL`, blend off (func SRC_ALPHA, ONE_MINUS_SRC_ALPHA), cull face on (back), alpha test off, no client or attrib arrays enabled, `GL_ARRAY_BUFFER` = 0, colour (1,1,1,1), matrix mode `GL_MODELVIEW`.

The chunk vertex is `VERTEX` (16 bytes) in structs.inc. Attribute locations: 0 `a_pos` (3 floats), 1 `a_uv` (2 floats), 2 `a_light` (4 normalized ubytes: sky, block, shade, flags), 3 `a_color` (4 normalized ubytes, the tint).

## Self-test and tests

`MineAssembly.exe --selftest [--seed N]` creates a fresh creative world called `selftest`, waits for the spawn area, flies a scripted camera for about 12 s, saves `selftest_1.bmp` to `selftest_5.bmp` (front, side, ground, midnight, aerial), appends stats to `mineassembly.log` and exits 0 (2 means load timeout, 3 means GL/init failure). `--bench` flies for 30 s and logs average and min FPS. `tests/platform/test_selftest_smoke.asm` runs the self-test in a clean folder and checks the exit code and the BMPs.

`MineAssembly.exe --script FILE` replays a scenario (format in `tests/scenarios/README.md`). `mabuild scenario tests/scenarios/<name>.txt [--tag T] [--nobuild] [--timeout S] [--keep]` builds a private exe, runs it in a fresh `build/scen_<name>/` with a hard timeout, converts the screenshots to PNG and prints the log tail and the exit code (0 ok, 1-5 game errors, 124 timeout).

Unit tests are `tests/<group>/test_*.asm` programs built against `tests/lib/testlib.inc`. The header lines `; @link`, `@timeout N`, `@gpu` and `@preview` control how they're built and run. `mabuild test` links each one with `tests/lib/testlib.asm`, `src/globals.asm` and its `@link` files, stubs every other `api.inc` symbol, builds a console exe under `build/t_<group>/` and runs it with a timeout, several in parallel. Exit code 0 means pass (the code is the number of failed checks). CI runs `mabuild test --nogpu`, which skips the `@gpu` tests. More in [tests/lib/README.md](../tests/lib/README.md).
