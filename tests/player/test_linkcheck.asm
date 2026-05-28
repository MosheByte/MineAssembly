; test_linkcheck.asm - links every src module into one exe so duplicate globals and
; unresolved refs fail the build. main.asm stays out (testlib owns `start`), its
; three globals are faked below. at runtime it only checks the entry points differ.
;
; @link src/audio.asm src/blockent.asm src/blocks.asm src/chunkmgr.asm src/config.asm
; @link src/console.asm src/entity.asm src/explosion.asm src/fluids.asm src/font.asm
; @link src/game.asm src/gl.asm src/hud.asm src/inventory.asm src/items.asm src/light.asm
; @link src/math.asm src/menus.asm src/mesher.asm src/mobs.asm src/music.asm src/noise.asm
; @link src/particles.asm src/physics.asm src/platform.asm src/player.asm src/raycast.asm
; @link src/render.asm src/save.asm src/screens.asm src/sky.asm src/texgen.asm src/ticks.asm
; @link src/ui.asm src/util.asm src/weather.asm src/world.asm src/worldgen.asm
; @link src/net.asm src/mcproto.asm src/mcplay.asm src/mcmap.asm src/mcdata.asm
; @link tests/player/ptest.asm
; @timeout 120
%include "common.inc"
%include "net.inc"
%include "testlib.inc"
%include "../player/ptest.inc"

global main_cmd_world, main_cmd_script, main_cmd_host

section .bss
main_cmd_world:  resb 64            ; fakes for main.asm's
main_cmd_script: resb 260
main_cmd_host:   resd 1

section .rdata
align 8
; one symbol per module, any will do
entries:
    dq audio_init, blockent_tick, blocks_init, chunkmgr_update, config_load
    dq console_open, entity_spawn_item, explosion_create, fluid_update, font_init
    dq game_frame, gl_load_functions, hud_render, inv_add, items_init, light_on_block_changed
    dq vec3_normalize, menus_render, mesher_build_section, mobs_ai_tick, music_tick, noise2
    dq particles_ambient_tick, physics_move, platform_init, player_update, raycast_blocks
    dq render_set_camera, save_world, screens_open, sky_render, texgen_init, ticks_tick
    dq ui_button, str_len, weather_tick, world_get_block, worldgen_place_tree
    dq net_update, mc_handle_packet, mcplay_tick, mcmap_block_state
N_ENTRIES equ ($ - entries) / 8

section .text

PROC test_main, 0
    TEST "linkcheck: every module linked"
    lea  rbx, [rel entries]
    xor  esi, esi
    xor  edi, edi                       ; problems
.outer:
    mov  rax, [rbx+rsi*8]
    test rax, rax
    jz   .bad
    lea  ecx, [rsi+1]
.inner:
    cmp  ecx, N_ENTRIES
    jae  .next
    cmp  rax, [rbx+rcx*8]
    je   .bad
    inc  ecx
    jmp  .inner
.bad:
    inc  edi
.next:
    inc  esi
    cmp  esi, N_ENTRIES
    jb   .outer
    ICHK edi, OP_EQ, 0, "null or aliased module entry points"
    ICHK esi, OP_EQ, 42, "modules checked"
ENDP
