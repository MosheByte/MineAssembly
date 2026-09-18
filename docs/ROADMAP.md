# Roadmap

Ideas for where MineAssembly could go. None of this is a promise, and there are no dates. It's roughly ordered by how much I think it would matter to players and contributors, and each item names the modules it touches so you can judge the blast radius. If you want to take something on, open an issue first so we can agree on the design. Anything that changes `include/*` affects every module.

The ground rules don't change: everything is written directly in x86-64 assembly, there are no asset files, and all content is original.

## Linux port

This is the one I care about most. The plan is to keep the internal Win64 calling convention everywhere and translate only at the OS boundary: each libc/X11/GLX/ALSA call goes through a small thunk that moves `rcx, rdx, r8, r9` into `rdi, rsi, rdx, rcx` and respects System V's red zone and alignment rules. The other 44 files keep their `PROC` frames as they are.

What it needs: a `platform_linux.asm` implementing the platform group of `api.inc` (X11 window, GLX context, XInput2 raw mouse motion, `clock_gettime`, `mmap`, files, threads), an ELF build path in `tools/mb_build.asm`, `gl.asm` using `glXGetProcAddress`, an ALSA or PulseAudio backend, and BSD sockets in place of Winsock for `net.asm`. The mixer thread in `audio.asm` only really needs a "buffer done" signal.

The open question is whether to link libc for X11/GL convenience or talk to the kernel directly and load `libX11`/`libGL` with a hand-rolled `dlopen`. The no-C-runtime rule says the second. Being practical says start with the first.

After X11 works, Wayland would be next. macOS is unlikely given OpenGL's deprecation and Apple's linking constraints, though I'd happily read a design sketch. Smaller platform things: key rebinding in `options.txt` (`config.asm`, `player.asm`, `menus.asm`), gamepad support through XInput (a new DLL import, so design issue first), and a WASAPI backend for lower latency than `waveOut`.

## Multiplayer

The first piece is done: MineAssembly can host a world that real Minecraft Java Edition 26.1 clients join (see [MULTIPLAYER.md](MULTIPLAYER.md)). What's still missing:

- Chunks only load around the host, so a Java player who walks past the host's render distance runs out of ground. `chunkmgr.asm` would need to keep the area around each remote player loaded as well (`chunkmgr.asm`, `mcplay.asm`).
- Java players are always in creative. Survival needs health, hunger, damage, item drops and real inventories on the wire.
- Mobs, dropped items, TNT, falling blocks and weather aren't sent to Java clients yet, so they only see terrain, blocks and players (`mcplay.asm`, `mcmap.asm`, `entity.asm`).
- MineAssembly joining MineAssembly. Terrain is a pure function of the seed, so a client only needs the seed and the list of changed blocks, which is what `save.asm` already writes. A client side for the same protocol would let two copies of the game play together.
- A headless `--server` mode that skips the window, GL and audio, which the module boundaries already allow through `--stubs`.

## World and content

- More biomes: badlands with banded stone, birch swamp, blossom groves with an original tree shape, ice spikes. Worldgen already blends on continuous weights, so a new biome is mostly a new region in the climate table plus surface rules (`worldgen.asm`, `world.asm`, `texgen.asm`).
- Taller worlds. `CHUNK_H` is 128. Going to 256 means 16 sections, a bigger `CHUNK` slot, repacking the light queue (y needs 8 bits) and a save format version bump.
- Dungeons, grown from the existing mossy ruins, with chests. Cross-chunk features already work through the 3×3 candidate replay.
- A second dimension, say the Underdeep: a dark cavern world lit by glowcrystal, reached through a crafted gateway, with its own fog, music mood and mobs.
- Farming. `B_FARMLAND` is already reserved. Hoes, crops driven by random ticks, and bread from crops instead of only from loot.
- Doors, slabs, stairs and fences, which need new mesher models, physics boxes and raycast boxes (`mesher.asm`, `physics.asm`, `raycast.asm`).
- Beds, spawn points and sleeping through the night.

Some original mob ideas: a Burrower that digs little tunnels in sand and dirt, a Cave Lurker that only lives in darkness below y 40 and flees torchlight (it would read the light field directly), a slow flying Drifter at night that drops a lantern material, and river fish that use the fluid levels to move. The existing mobs could use better behaviour too: short-range A* for the Shambler (it steers straight at you today), herds for Boars and Woollies, and not walking into lava or cacti.

## Pulsewire

Pulsewire would be a redstone-style logic system: a dust crafted from glowcrystal shards that carries a 0-15 signal, dropping by 1 per block. The block set I have in mind: the wire itself, a pulse torch (inverter and constant source), a relay with 1-4 tick delay, a sensor that reads container fill levels, lever, button, pressure plate, a pusher that moves up to 12 blocks, and a lamp.

Signal strength is another flood fill, very close to the block-light BFS in `light.asm`, and updates can ride on `ticks.asm`'s scheduled ticks, whose deterministic FIFO order is exactly what circuits need. The hard part is storage: block ids are 8-bit, so the signal needs a per-block metadata byte, which is a `structs.inc` and save format change and worth designing carefully.

## Rendering

- Shadow mapping for the sun and moon (one depth pass from the light, PCF in the chunk shader). Needs FBOs, so GL 3.0 or `EXT_framebuffer_object`.
- Bloom on glowcrystal, lava and torches, and on the sun at sunset.
- Better water: screen-space refraction, depth-based colour, soft shoreline foam from the per-vertex liquid level.
- Light shafts through leaves at sunrise, and caustics on the sea floor.
- Indexed quad drawing. Vertices are already packed to 16 bytes (`i16` chunk-local coords); sharing an index buffer across sections would cut vertex count from 6 per quad to 4.
- Cave occlusion culling, flood-filling visibility between section faces so rock-enclosed caves aren't drawn.
- Meshing on worker threads. The mesher already works on a private 18³ padded copy, so it's a natural fit; upload stays on the main thread.
- A GL 3.3 core-profile path next to the current GL 2.0 one.

## Gameplay and UI

An options screen in the pause menu for every `options.txt` field. Statistics and achievements with original names. A map item or minimap drawn from the heightmap and top block colour (the same data `tests/world/test_worldgen_preview.asm` renders). Signs and writable notes. Localization would need a glyph generator for more than ASCII, since that's all the font covers.

## Tooling

CI already runs the unit tests (`mabuild test --nogpu`). The next step is running a subset of scenarios headlessly and uploading the screenshots as artifacts, plus golden-image comparisons for the `--selftest` shots with some tolerance. Other things I'd like: per-subsystem timers in the F3 overlay (mesh, light, worldgen, entities, mixer), fuzzing the save loader with corrupted files (it already validates everything, fuzzing would prove it), region files that group 32×32 chunks per file, a `mabuild` command to inspect `MASW`/`MASC` saves, and a reading guide through the codebase for people learning x86-64.

## Not planned

Bundling texture, sound or music files, since that defeats the whole point. Using Minecraft's code or assets. The Java Edition bridge uses the protocol and its id tables so real clients can connect, but the game itself is original and isn't affiliated with Mojang or Microsoft. Rewriting modules, tools or tests in C or any other language.
