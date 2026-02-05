# Scenario scripts

A scenario drives the real game from a text file. It starts a world (or stays on the title screen), replays timed input and console commands, and takes screenshots along the way. I use these to reproduce a situation and get pictures of it without touching the keyboard.

```
MineAssembly.exe --script path\to\scenario.txt      (path relative to the working directory)
mabuild scenario tests/scenarios/example_build.txt [--tag T] [--nobuild] [--timeout S] [--keep] [--tail N]
```

`mabuild scenario` (`tools/mb_scenario.asm`) builds a private copy of the game (`build/<tag>/`, tag `scen` by default), runs it in a fresh `build/scen_<name>/` with a timeout, converts every BMP the run wrote into a PNG next to it, and prints the log tail, the exit code and the PNG list. `--nobuild` reuses the existing exe, `--timeout S` defaults to 330, `--keep` skips wiping the directory (so saves survive for a `keep` world), and `--tail N` sets how many log lines to print. Its own exit code is the game's, or 124 if the timeout killed it, or 2 for a usage error or failed build. `mabuild png IN.bmp OUT.png` converts a single screenshot.

## What changes in script mode

`--script` sets `g_run_mode = 3`. Real keyboard and mouse input is ignored; the script's input goes through the same hooks the window procedure uses (`game_on_key`, `game_on_char`, `game_on_mouse_button`, `game_on_wheel`). The mouse is never captured, so the window can sit in the background. Vsync is on, the client area is 1280x720, and fullscreen from options.txt is ignored. The game mode comes from the setup line, though `cmd /gamemode ...` still works later. Every executed line is logged as `script: t=1.00 cmd /give torch 64`, and so is the console output of commands (chat messages go to `mineassembly.log`).

## File format

One directive per line, blank lines ignored. A line starting with `#` is a comment, and on every line except `type` a `#` after a blank starts a trailing comment. Keywords and key names are case-insensitive. CRLF or LF and a UTF-8 BOM are all fine.

The first directive is the setup line:

| Line | Meaning |
|---|---|
| `world <name> <seed> <survival\|creative> [keep]` | Delete `saves\<name>` (unless `keep`), then load it if it still exists or create it with `<seed>`. The timeline starts when the spawn area is ready. `<name>` is 1-63 of `A-Z a-z 0-9 - _ .`, not starting with `.`. `<seed>` is a number or any text (hashed like `--seed`). |
| `title` | Stay on the title screen. The timeline starts right away. |

Every other line is `<t> <directive> [arguments]`, where `t` is seconds since the timeline started (decimals allowed) and must never go down from one line to the next. A line runs on the first frame whose time is at least `t`. Lines with the same time run in file order in the same frame, with the exceptions listed under frame rules.

| Directive | Effect |
|---|---|
| `cmd <console line>` | `console_execute`, the leading `/` is optional: `cmd /give torch 64`, `cmd /time set night`, `cmd /tp 0 80 0`, `cmd /fill ~-3 ~-1 ~-3 ~3 ~-1 ~3 stone` |
| `pos <x> <y> <z>` | Teleport the player's feet (floats), velocity zeroed. The teleport doesn't count as a fall. Gravity still applies unless flying. |
| `look <yaw> <pitch>` | Set the view. Yaw 0 looks north (-Z), 90 east. Negative pitch looks down (clamped to +-89.9). |
| `turn <dyaw> <dpitch> <secs>` | Rotate smoothly by that many degrees over `secs` (0 = instantly). |
| `key <NAME> down\|up\|tap` | Key state (`g_keys`, `g_keys_pressed`) + `game_on_key`, exactly like the window procedure, including the `WM_CHAR` Windows adds for `BACK` (8) and `ENTER` (13), so `key BACK tap` deletes a character in a text box. A key held with `down` auto-repeats like a real keyboard (first repeat after 0.5 s, then 30/s, only the most recently pressed key), so `key BACK down` ... `key BACK up` deletes several. `tap` is down now, up next frame. Names: `A`-`Z`, `0`-`9`, `SPACE SHIFT CTRL ALT ESC ENTER TAB BACK DELETE HOME END PGUP PGDN UP DOWN LEFT RIGHT SLASH F1`..`F12` (aliases `ESCAPE RETURN BACKSPACE CONTROL /`). |
| `type <text...>` | The rest of the line, verbatim, into `g_char_queue` + `game_on_char` like WM_CHAR. At most 64 characters per frame; the rest carries over. |
| `mouse <x> <y>` | Cursor position in window pixels (0..1279, 0..719). Stays until changed, starts at 640 360. |
| `click left\|right\|middle [x y]` | Optionally move the cursor, press this frame, release next frame. |
| `hold left\|right\|middle <secs>` | Press now, release after `secs` (mining in survival, eating). |
| `wheel <n>` | Wheel notches (`+` is away from you, which moves the hotbar left). |
| `shot <file.bmp>` | Save this frame after it's drawn (24-bit BMP, path relative to the working directory, folders must exist). |
| `frames <every_n> <count> <prefix>` | Save every n-th frame starting with this one as `<prefix>_0001.bmp` ... `<prefix>_<count>.bmp`. Good for GIFs. |
| `hidehud on\|off` | Hide or show the HUD, like F1 (only while playing). |
| `wait` | Does nothing, but keeps the script alive until `t` + 1 s. |
| `quit [code]` | Exit now with `code` (default 0). |

Without `quit`, the game exits with 0 one second after the last action, or after the last `hold` / `turn` finishes, whichever is later.

### Frame rules

Input is applied at the start of a frame, before the world update, in this order: releases from the previous frame's taps and clicks, expired holds, `turn` progress, pending `type` text, then the due actions. A few things get pushed to the next frame so the result matches what real input would do:

- a `shot` ends the frame's batch. The picture shows everything before it, and lines after it (even with the same `t`) run next frame;
- a `key` / `click` / `hold` whose key or button still has a tap or click waiting to be released;
- any line with a later time than a `key ... tap` or `click` in the same frame, so a tap or click is always a full press and release before the next scripted event (otherwise a `mouse` right after a `click` would turn it into a drag);
- a `key` after a `type` in the same frame, because the game reads typed characters while drawing but keys immediately, and `Enter` has to come after the text;
- a `type` in the same frame as the key that opens chat or the inventory, since that frame drops typed characters in the real game too.

So `1.0 key T tap` / `1.0 type hello` / `1.0 key ENTER tap` sends "hello" to chat over three frames. `key SLASH tap` opens chat with `/` already typed; follow it with `type time set noon` and `key ENTER tap`.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Script finished (or `quit` / `quit 0`) |
| 1 | A screenshot couldn't be written, or the window closed / the game quit before the script finished |
| 2 | Spawn area not ready within 90 s |
| 3 | No OpenGL 2.0 window |
| 4 | Hard timeout: still running 300 s after start |
| 5 | Bad script: unreadable file, missing setup line, unknown directive, bad argument, decreasing time (the log names the line), or a `keep` world with a damaged level.dat (it's never replaced with a new world) |
| other | `quit <code>` |

## Determinism

Mouse coordinates are window pixels, and menu and inventory positions depend on the GUI scale. Since `mabuild scenario` runs in a fresh directory, options.txt is always at its defaults there. World content depends only on the seed.

The timeline is game time, not wall-clock time. It advances by each frame's dt, capped at 0.1 s like the simulation, so a slow frame (a screenshot, a busy machine) delays the following lines rather than making several seconds of them due at once. On a slow machine a script just takes longer. Frame-exact things like particles, mob movement or the exact moment a `hold` ends can still differ a little between machines.

If you need a predictable stage regardless of terrain, clear it first, for example `cmd /fill ~-6 ~-1 ~-12 ~6 ~-1 ~2 grass_block` then `cmd /fill ~-6 ~ ~-12 ~6 ~10 ~2 air` (`example_build.txt` does this).

## Examples

- `example_build.txt`: survival world, `/give` planks, cobblestone and torches, places blocks and a torch with right clicks, walks back with `key S`, hides the HUD, switches to midnight. Shots `build_1_start` to `build_4_night`.
- `example_inventory.txt`: opens the inventory with `E`, clicks two planks into the crafting grid (sticks appear), hovers an item for its tooltip, closes with `ESC`, switches to creative and opens the creative inventory. Shots `inventory_1_open` to `inventory_4_creative`.
- `example_title.txt`: title screen, hovers and clicks "Singleplayer". Shots `title_1`, `title_2_hover`, `title_3_worlds`.
