# Contributing

MineAssembly is my personal project ([MosheByte](https://github.com/MosheByte)), a Minecraft-like game written straight in x86-64 NASM for Windows. Help of any size is welcome, whether that's a bug report, a review comment on some assembly, a test, a port or a feature.

Read these before you start: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) (who owns what, conventions, threads, frame flow), [include/api.inc](include/api.inc) (every function and variable shared between modules) and [docs/HOW_IT_WORKS.md](docs/HOW_IT_WORKS.md).

## Building

You need [NASM](https://www.nasm.us/) 2.15+ and [MinGW-w64](https://www.mingw-w64.org/), both on `PATH`. `gcc` is only the linker driver here (`-nostdlib`, no C runtime). Everything in the repo is assembly: the game in `src/`, the build tool in `tools/`, the tests in `tests/`.

Bootstrap the build tool once, from the repo root in `cmd.exe`:

```
nasm -f win64 -I include\ -I tools\ tools\mabuild.asm -o mabuild.obj
gcc -nostdlib -o mabuild.exe mabuild.obj -Wl,-e,start -Wl,--subsystem,console -lkernel32 -luser32
```

(PowerShell wants the `-Wl,...` arguments in quotes.) Once you have it, `mabuild self` rebuilds it in place whenever `tools/*.asm` changes.

```
mabuild                              MineAssembly.exe in the repo root
mabuild --run --world test           build, then run with these arguments
mabuild check src/light.asm          assemble one module only
mabuild --tag mytag                  private build in build/mytag/MineAssembly.exe
mabuild --stubs                      stub out every API symbol nobody implements yet
mabuild --help                       everything else
```

Under the hood each `src/*.asm` goes through `nasm -f win64 -Werror=label-orphan -I include\` and then gets linked with `gcc -nostdlib -nostartfiles -Wl,-e,start` against `kernel32 user32 gdi32 opengl32 winmm ws2_32`. CI (`.github/workflows/build.yml`) does the same bootstrap, builds, and runs `mabuild test --nogpu` on every push and PR.

The game itself takes a few flags:

```
MineAssembly.exe                         normal game
MineAssembly.exe --world test --seed 42  skip the title screen
MineAssembly.exe --selftest [--seed N]   scripted render test
MineAssembly.exe --bench                 30 s fly-over, logs avg/min FPS
MineAssembly.exe --script FILE           scripted scenario
MineAssembly.exe --host PORT             open each world to Java Edition clients once it loads
```

It writes `mineassembly.log`, `options.txt` and `saves\` into the working directory (all git-ignored).

## Testing

There are three layers, and I'd like PRs to touch whichever ones apply.

### Self-test

`MineAssembly.exe --selftest --seed 42` creates a fresh creative world, flies a fixed camera path, saves `selftest_1.bmp` to `selftest_5.bmp`, logs some stats and exits. Exit code 0 means pass, 2 means the spawn area didn't load within 90 s, 3 means GL or init failed. Open the five pictures and look at them; rendering bugs usually show up there first. `mabuild test tests/platform/test_selftest_smoke.asm` runs it in a clean folder and checks the exit code and the BMPs for you.

### Scenarios

Scenarios drive the real game from a timed script (console commands, key presses, clicks, camera moves, screenshots). The format is in [tests/scenarios/README.md](tests/scenarios/README.md).

```
mabuild scenario tests/scenarios/simulation_water.txt
mabuild scenario tests/scenarios/survival_mining.txt --nobuild
```

The runner builds a private exe into `build/scen/`, runs it in a fresh `build/scen_<name>/`, converts the screenshots to PNG and prints the log tail and exit code (0 ok, 5 bad script, 124 timeout...). There are 143 of them. Run the ones near whatever you changed, and if you fix a gameplay bug, add a scenario that reproduces it.

### Unit tests

Each unit test is a small assembly program, `tests/<group>/test_*.asm`, that defines `test_main`, uses the `TEST` / `CHECK_*` macros from [tests/lib/testlib.inc](tests/lib/testlib.inc), and lists the modules it needs in a `; @link` header line. A lot of them link a fake world written in asm (`tests/<group>/fakeworld.asm`) instead of the real one. The exe's exit code is its number of failed checks. Details in [tests/lib/README.md](tests/lib/README.md).

```
mabuild test                                   every test, in parallel
mabuild test tests/light                       one group
mabuild test tests/simulation/test_fluids.asm  one file
mabuild test --nogpu                           skip tests that need a GL window (CI does this)
```

Several groups also have a `test_abi.asm`. It loads sentinel values into every nonvolatile register (`rbx rbp rsi rdi r12-r15`, `xmm6-xmm15`), calls each exported function, and fails if any sentinel moved. The fake worlds also count calls made with a misaligned stack. If you add or change an exported function, please make sure the ABI test for that module covers it. This is the kind of bug that crashes ten calls later in someone else's code.

## Conventions

The full list lives in `include/common.inc` and [ARCHITECTURE.md](docs/ARCHITECTURE.md). These are the ones that matter most in review:

- Every global function is Microsoft x64 ABI: args in `rcx, rdx, r8, r9` / `xmm0-xmm3` (positional), return in `rax` / `xmm0`, preserve `rbx rbp rsi rdi r12-r15 xmm6-xmm15`, 32 bytes of shadow space, `rsp` 16-byte aligned at `call`.
- Write functions with `PROC name, localbytes` ... `ENDP` (or `PROCX`/`ENDPX` if you keep values in `xmm6-xmm15`). Early exits are `jmp .done` with `.done:` right before `ENDP`. Locals are `LOC(n)`, incoming stack args `ARG5`, `ARG6`..., outgoing ones `[rsp+32]`, `[rsp+40]`... up to 8.
- `LEAF` functions have no frame, so they either stick to volatile registers or save what they use. If you invent a custom register convention, write it in the comment above the function.
- Private helpers are not `global`; use a local `LPROC` macro like `src/light.asm` does. If a module-specific symbol has to be exported for tests, give it a module prefix (`save_rle_encode`, `light_stat_cells`).
- `default rel` is on, so index tables with `lea rax, [rel tbl]` then `[rax+rcx*k]`, never `[tbl+rcx]`.
- Single-precision SSE floats. To floor something that might be negative, use `math_floor` or `roundss` mode 1 (SSE4.1 is fine), not a bare `cvttss2si`.
- `include/*.inc` is the shared contract and changes to it hit every module. Keep them small, explain them in the PR, and update the `api.inc` comments (registers, units, `[thread-safe]`) in the same PR. Worker threads may only call functions tagged `[thread-safe]`.
- Every render pass has to restore the default GL state listed under [Rendering contract](docs/ARCHITECTURE.md#rendering-contract) in ARCHITECTURE.md.
- Each file starts with a header explaining how the module works. If you change how it works, fix the header. Comment the why next to anything non-obvious. ASCII only, spaces not tabs.

No asset files, ever. New textures go into `src/texgen.asm` (a tile shader or a 16×16 `SROW` pixel map) and new sounds into the patch table in `src/audio.asm`. And please don't copy code, textures, sounds or names from Minecraft or any other game. This is an original game in the same genre. The one exception is the Java Edition protocol data that the multiplayer bridge needs to talk to real clients: `include/mcpackets.inc` and `src/mcdata.asm` hold the 26.1 packet ids, block state ids, registry names and vanilla tag lists.

## Before you open a PR

- `mabuild` builds with no NASM warnings and `mabuild test` passes.
- `MineAssembly.exe --selftest --seed 42` exits 0 and the screenshots look right.
- The unit tests for the modules you touched pass, `test_abi.asm` included where there is one.
- Related scenarios pass, and a gameplay fix comes with a new scenario.
- New or changed globals are declared in `include/api.inc` with registers, units and thread safety.
- No new DLL imports beyond kernel32, user32, gdi32, opengl32, winmm and ws2_32 (open an issue first if you really need one).
- The PR says what changed and how you tested it, with before/after screenshots for anything visual.

One feature or fix per PR, please. Anything big, and especially anything touching `include/`, should start as an issue so we can talk about the design first.

## Small things to pick up

These each touch one or two modules:

- `--help` / `--version` on the command line (`src/main.asm`).
- Key rebinding in `options.txt` (`src/config.asm`, `src/player.asm`). Movement keys would be a good start.
- A new console command in `src/console.asm`, like `/seed`, `/biome` or `/count <block>`, plus a scenario that runs it.
- A new sound patch in `src/audio.asm`, for example a distinct furnace-open sound. It's just data in the patch table.
- A new item sprite or block texture in `src/texgen.asm`.
- A new crafting recipe in `src/items.asm`.
- Scenarios for features that don't have any yet (sapling edge cases, furnace fuel...).
- A `test_abi.asm` for a module group that doesn't have one.
- Make `--bench` log the 1% low FPS too (`src/game.asm`).
- Diagrams for HOW_IT_WORKS.md, or a reading guide for people learning x86-64 from this code.

Bigger stuff is in [docs/ROADMAP.md](docs/ROADMAP.md).

## Reporting bugs

Tell me your Windows version, CPU and GPU (the top of `mineassembly.log` has the GL vendor and renderer), paste the relevant bit of the log, and give the seed, coordinates (F3 shows them) and steps to reproduce. A screenshot helps for anything visual. A scenario script that reproduces it is even better.

## License

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).
