; game.asm - state machine, frame/tick glue, input routing, plus the
; selftest/bench autopilot and the --script runner. menus.asm draws whatever
; g_state says, this file just decides transitions. script format is in
; tests/scenarios/README.md

%define IMPL_GAME
%include "common.inc"

extern platform_last_shot
extern main_cmd_world
extern main_cmd_script
extern main_cmd_host
global game_exit_code

%macro FUNC 1-2 0
    align 16
%1:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub  rsp, (((%2)+15) & ~15) + FRAME_OUT + 8
%endmacro

; state sets, test with bt
%define SIM_STATES  ((1<<ST_PLAYING)|(1<<ST_INVENTORY)|(1<<ST_CHAT)|(1<<ST_DEAD))
%define HUD_STATES  ((1<<ST_PLAYING)|(1<<ST_INVENTORY)|(1<<ST_CHAT)|(1<<ST_PAUSED)|(1<<ST_DEAD))
%define MENU_STATES ((1<<ST_TITLE)|(1<<ST_WORLDSELECT)|(1<<ST_CREATEWORLD)|(1<<ST_LOADING)|(1<<ST_PAUSED)|(1<<ST_DEAD)|(1<<ST_SETTINGS))
%define LIVE_STATES ((1<<ST_PLAYING)|(1<<ST_INVENTORY)|(1<<ST_CHAT))

%define MOOD_DAY    0
%define MOOD_NIGHT  1
%define MOOD_MENU   2
%define MOOD_CAVE   3

%define AUTO_OFF        0
%define AUTO_LOADING    1
%define AUTO_RUNNING    2
%define AUTO_DONE       3
%define SELFTEST_SHOTS  5

section .rdata
align 4
f_tick:         dd 0.05                 ; 20 tps
f_max_acc:      dd 0.25                 ; max 5 ticks per frame, one slow frame shouldn't snowball
f_one:          dd 1.0
f_half:         dd 0.5
f_eye:          dd 1.62
f_bench_speed:  dd 12.0
f_bench_y:      dd 100.0
f_bench_pitch:  dd -10.0
f_spin:         dd 20.0                 ; deg/s
align 8
d_load_timeout: dq 90.0
d_selftest_end: dq 12.0
d_bench_end:    dq 30.0
d_one:          dq 1.0
d_two:          dq 2.0
d_notice_secs:  dq 8.0

; yaw, pitch, height above spawn, time of day
align 4
selftest_poses:
    dd   0.0,  -8.0,  2.0, 6000
    dd  90.0,  -8.0,  2.0, 6000
    dd  45.0, -60.0,  2.0, 6000
    dd   0.0,  12.0,  2.0, 18000  ; midnight, for stars/moon/torches
    dd  30.0, -35.0, 40.0, 6000
    dd  30.0, -35.0, 40.0, 6000  ; slow spin after the last shot

s_world_selftest: db "selftest", 0
s_world_bench:  db "bench", 0
s_saves:        db "saves", 0
s_save_dir:     db "saves\%s", 0
s_chunk_dir:    db "saves\%s\chunks", 0
s_shot_name:    db "selftest_%d.bmp", 0
s_shot_chat:    db "Saved screenshot as %s", 0
s_init_start:   db "game: initialising subsystems", 0
s_init_done:    db "game: ready in %d ms (vsync %d, gui scale %d, render distance %d)", 0
s_no_audio:     db "game: no audio device - continuing without sound", 0
s_start_fmt:    db "game: %s world '%s', seed %l, %s mode", 0
s_new:          db "new", 0
s_loaded:       db "loading", 0
s_survival:     db "survival", 0
s_creative:     db "creative", 0
s_load_fail:    db "game: ERROR world '%s' could not be loaded (level.dat missing or damaged) - left untouched, not opened", 0
s_load_fail_ui: db 'World "%s" could not be loaded: level.dat is damaged', 0
s_bad_world:    db "game: ERROR '%s' is not a valid world folder name", 0
s_new_taken:    db "game: ERROR cannot create world '%s': a world with that folder already exists", 0
s_stale_chunks: db "game: removed %d stale chunk file(s) from saves\%s\chunks (a world that was never saved)", 0
s_glob_fmt:     db "%s\*", 0
s_path_fmt:     db "%s\%s", 0
s_bad_chars:    db '\/:*?"<>|', 0
s_ready_fmt:    db "game: spawn area ready after %d ms", 0
s_exit_world:   db "game: world '%s' saved and closed", 0
s_shutdown:     db "game: shutting down", 0
s_death:        db "game: player died", 0
s_auto_start:   db "autopilot: %s run started (seed %l)", 0
s_auto_ready:   db "autopilot: spawn area ready after %.1f s at %.1f %.1f %.1f", 0
s_auto_timeout: db "autopilot: FAIL - spawn area not ready after 90 s", 0
s_auto_stats:   db "selftest: t=%2ds fps=%d chunks=%d sections=%d vertices=%d meshes=%d entities=%d particles=%d", 0
s_auto_shot:    db "selftest: screenshot %d/5 -> %s %s", 0
s_shot_ok:      db "ok", 0
s_shot_bad:     db "FAILED", 0
s_auto_pass:    db "selftest: PASS (%l frames, %d screenshots)", 0
s_auto_fail:    db "selftest: FAIL (%d of 5 screenshots could not be written)", 0
s_bench_sec:    db "bench: t=%2ds fps=%d chunks=%d sections=%d vertices=%d", 0
s_bench_done:   db "bench: average %.1f FPS, minimum %d FPS, %d frames in %.1f s", 0
s_auto_abort:   db "autopilot: FAIL - run interrupted before it finished (exit code 1)", 0

section .data
align 4
game_exit_code: dd 0
s_mood:         dd -1

section .bss
alignb 8
s_auto_t0:      resq 1
s_bench_sec_t0: resq 1
s_tick_acc:     resd 1                  ; float secs not simulated yet
s_new_world:    resd 1
s_chunkmgr_on:  resd 1
s_swallow_char: resd 1                  ; eat the WM_CHAR of the key that opened chat
s_prev_focus:   resd 1
s_prev_dead:    resd 1
s_shot_request: resd 1
s_load_ms:      resd 1
s_auto_phase:   resd 1
s_auto_shots:   resd 1
s_auto_shot_fail: resd 1
s_auto_next_log: resd 1
s_auto_base:    resd 3
s_bench_frames: resd 1
s_bench_sec_frames: resd 1
s_bench_min:    resd 1
s_spawn:        resd 4
s_notice_until: resq 1
s_notice:       resb 160
s_net_acc:      resd 1                  ; java bridge tick, runs while paused too

section .text

FUNC is_simulating, 0
    xor  eax, eax
    cmp  dword [rel g_world_active], 0
    je   .ret
    mov  ecx, [rel g_state]
    cmp  ecx, 31
    ja   .ret
    mov  edx, SIM_STATES
    bt   edx, ecx
    setc al
.ret:
    ENDP

; cvttss2si truncates toward zero, wrong for negative coords
%macro FLOOR_INT 2
    roundss %2, %2, 1
    cvttss2si %1, %2
%endmacro

FUNC update_mood, 0
    mov  ebx, MOOD_MENU
    cmp  dword [rel g_world_active], 0
    je   .apply
    cmp  dword [rel g_state], ST_LOADING
    je   .apply
    ; cave = deep enough and dark at head height
    movss xmm0, [rel g_player + PLAYER.y]
    addss xmm0, [rel f_eye]
    FLOOR_INT esi, xmm0
    cmp  esi, SEA_LEVEL - 10
    jge  .surface
    movss xmm0, [rel g_player + PLAYER.x]
    FLOOR_INT edi, xmm0
    movss xmm0, [rel g_player + PLAYER.z]
    FLOOR_INT r12d, xmm0
    mov  ecx, edi
    mov  edx, esi
    mov  r8d, r12d
    call world_get_light
    shr  eax, 4  ; high nibble = sky light
    mov  ebx, MOOD_CAVE
    cmp  eax, 4
    jb   .apply
.surface:
    mov  ebx, MOOD_DAY
    mov  eax, [rel g_time_of_day]
    cmp  eax, 12500
    jb   .apply
    cmp  eax, 23500
    jae  .apply
    mov  ebx, MOOD_NIGHT
.apply:
    cmp  ebx, [rel s_mood]
    je   .ret
    mov  [rel s_mood], ebx
    mov  ecx, ebx
    call music_set_mood
.ret:
    ENDP

FUNC mask_input, 0
    lea  rcx, [rel g_keys]
    mov  edx, 256
    call mem_zero
    lea  rcx, [rel g_keys_pressed]
    mov  edx, 256
    call mem_zero
    xor  eax, eax
    mov  [rel g_mouse_buttons], eax
    mov  [rel g_mouse_pressed], eax
    mov  [rel g_mouse_released], eax
    mov  [rel g_mouse_dx], eax
    mov  [rel g_mouse_dy], eax
    mov  [rel g_wheel], eax
    mov  [rel g_char_count], eax
    ENDP

PROC game_init, 0
    lea  rcx, [rel s_init_start]
    call log_write
    call time_ms
    mov  r12, rax

    call config_load
    mov  ecx, [rel g_settings + SETTINGS.vsync]
    xor  eax, eax
    cmp  dword [rel g_run_mode], 2  ; bench wants uncapped fps
    cmove ecx, eax
    mov  eax, 1
    cmp  dword [rel g_run_mode], 3
    cmove ecx, eax
    call platform_set_vsync
    cmp  dword [rel g_run_mode], 0
    jne  .no_fs
    cmp  dword [rel g_settings + SETTINGS.fullscreen], 0
    je   .no_fs
    call platform_toggle_fullscreen
.no_fs:
    call blocks_init
    call items_init
    call texgen_init
    call font_init
    call render_init
    call sky_init
    call particles_init
    call entity_init
    call ticks_init
    call ui_init
    call audio_init
    test eax, eax
    jnz  .audio_ok
    lea  rcx, [rel s_no_audio]
    call log_write
.audio_ok:
    call music_init
    call world_init

    call time_ms
    sub  rax, r12
    mov  edx, eax
    lea  rcx, [rel s_init_done]
    mov  r8d, [rel g_settings + SETTINGS.vsync]
    mov  r9d, [rel g_settings + SETTINGS.gui_scale]
    mov  eax, [rel g_settings + SETTINGS.render_dist]
    mov  [rsp+32], rax
    call log_printf

    mov  dword [rel g_state], ST_TITLE
    mov  dword [rel g_prev_state], ST_TITLE
    mov  eax, [rel g_window_focused]
    mov  [rel s_prev_focus], eax

    cmp  dword [rel g_run_mode], 1
    jne  .not_selftest
    lea  rcx, [rel s_world_selftest]
    call auto_begin
    jmp  .ret
.not_selftest:
    cmp  dword [rel g_run_mode], 2
    jne  .not_bench
    lea  rcx, [rel s_world_bench]
    call auto_begin
    jmp  .ret
.not_bench:
    cmp  dword [rel g_run_mode], 3
    jne  .not_script
    call script_begin
    jmp  .ret
.not_script:
    cmp  byte [rel main_cmd_world], 0
    je   .title
    ; --world NAME, created if missing (--seed or random)
    lea  rcx, [rel main_cmd_world]
    call save_world_exists
    xor  r9d, r9d
    test eax, eax
    sete r9b
    mov  rdx, [rel g_cmd_seed]
    test rdx, rdx
    jnz  .seed_ok
    rdtsc
    shl  rdx, 32
    or   rdx, rax
    mov  rax, 0x9E3779B97F4A7C15
    imul rdx, rax
.seed_ok:
    lea  rcx, [rel main_cmd_world]
    mov  r8d, GM_SURVIVAL
    call game_start_world
    test eax, eax
    jnz  .ret
.title:
    mov  ecx, ST_TITLE
    call game_set_state
.ret:
    ENDP

; selftest/bench always start from a fresh creative world
FUNC auto_begin, 0
    mov  rsi, rcx
    call save_delete_world
    mov  rbx, [rel g_cmd_seed]
    test rbx, rbx
    jnz  .seed
    mov  ebx, 1337
.seed:
    lea  rcx, [rel s_auto_start]
    mov  rdx, rsi
    mov  r8, rbx
    call log_printf
    mov  rcx, rsi
    mov  rdx, rbx
    mov  r8d, GM_CREATIVE
    mov  r9d, 1
    call game_start_world
    mov  dword [rel s_auto_phase], AUTO_LOADING
    call time_seconds
    movsd [rel s_auto_t0], xmm0
    ENDP

PROC game_set_state, 0
    mov  ebx, ecx
    mov  esi, [rel g_state]
    ; leaving DEAD = respawn
    cmp  ebx, ST_PLAYING
    jne  .no_respawn
    cmp  esi, ST_DEAD
    jne  .no_respawn
    cmp  dword [rel g_player + PLAYER.dead], 0
    je   .no_respawn
    call player_respawn
.no_respawn:
    cmp  ebx, esi
    je   .same
    mov  [rel g_prev_state], esi
.same:
    mov  [rel g_state], ebx
    cmp  ebx, ST_QUIT
    je   .ret
    ; captured only while PLAYING and never in automated runs
    xor  ecx, ecx
    cmp  ebx, ST_PLAYING
    jne  .cap
    cmp  dword [rel g_run_mode], 0
    sete cl
.cap:
    call platform_set_mouse_capture
    cmp  ebx, ST_PLAYING
    jne  .menus
    mov  eax, [rel g_player + PLAYER.dead]
    mov  [rel s_prev_dead], eax
.menus:
    cmp  ebx, 31
    ja   .mood
    mov  eax, MENU_STATES
    bt   eax, ebx
    jnc  .mood
    mov  ecx, ebx
    call menus_enter
.mood:
    call update_mood
.ret:
    ENDP

; is_new=0 with a missing/broken level.dat: refuse and return 0. falling back
; to a fresh world would write a new level.dat (seed 0 from the world list)
; over the only copy and splice new terrain into the old chunk files.
; is_new=1 refuses if a level.dat is already there.
PROC game_start_world, 272
    mov  rsi, rcx
    mov  r12, rdx
    mov  r13d, r8d
    mov  r14d, r9d
    xor  eax, eax
    test rsi, rsi
    jz   .ret
    mov  rcx, rsi
    call world_name_ok  ; also rejects "" and anything outside saves\
    test eax, eax
    jnz  .name_ok
    lea  rcx, [rel s_bad_world]
    mov  rdx, rsi
    call log_printf
    xor  eax, eax
    jmp  .ret
.name_ok:
    test r14d, r14d
    jz   .not_taken
    mov  rcx, rsi
    call save_world_exists
    test eax, eax
    jz   .not_taken
    lea  rcx, [rel s_new_taken]
    mov  rdx, rsi
    call log_printf
    xor  eax, eax
    jmp  .ret
.not_taken:
    cmp  dword [rel g_world_active], 0  ; save the old one first
    je   .fresh
    call save_world
.fresh:
    lea  rcx, [rel g_world_name]
    mov  rdx, rsi
    mov  r8d, 64
    call str_ncopy
    lea  rsi, [rel g_world_name]
    mov  [rel g_seed], r12
    mov  [rel g_gamemode], r13d
    mov  qword [rel g_world_time], 0
    mov  dword [rel g_time_of_day], 1000

    call world_clear
    call entity_clear
    call particles_clear
    call ticks_clear
    call blockent_clear
    call player_reset
    test r14d, r14d
    jnz  .seeded
    call save_load_level  ; overrides seed, time, player, inventory
    test eax, eax
    jnz  .seeded
    ; refuse. world state is already cleared and the empty name makes every
    ; later save_world a no-op
    lea  rcx, [rel s_load_fail]
    mov  rdx, rsi
    call log_printf
    lea  rcx, [rel s_load_fail_ui]
    mov  rdx, rsi
    call game_notice
    mov  byte [rel g_world_name], 0
    mov  dword [rel g_world_active], 0
    xor  eax, eax
    jmp  .ret
.seeded:
    mov  rcx, [rel g_seed]
    call noise_set_seed
    mov  rcx, [rel g_seed]
    mov  rax, 0x9E3779B97F4A7C15
    xor  rcx, rax
    call rng_seed

    test r14d, r14d
    jz   .dirs
    lea  rcx, [rel s_spawn]
    call worldgen_find_spawn
    mov  ecx, [rel s_spawn+0]
    mov  edx, [rel s_spawn+8]
    call worldgen_height_at
    inc  eax
    cvtsi2ss xmm1, eax
    cvtsi2ss xmm0, dword [rel s_spawn+0]
    addss xmm0, [rel f_half]
    cvtsi2ss xmm2, dword [rel s_spawn+8]
    addss xmm2, [rel f_half]
    movss [rel g_player + PLAYER.x], xmm0
    movss [rel g_player + PLAYER.y], xmm1
    movss [rel g_player + PLAYER.z], xmm2
    movss [rel g_player + PLAYER.spawn_x], xmm0
    movss [rel g_player + PLAYER.spawn_y], xmm1
    movss [rel g_player + PLAYER.spawn_z], xmm2
    mov  dword [rel g_time_of_day], 1000
    mov  qword [rel g_world_time], 0

.dirs:
    lea  rcx, [rel s_saves]
    call dir_create
    lea  rcx, LOC(0)
    lea  rdx, [rel s_save_dir]
    mov  r8, rsi
    call str_format
    lea  rcx, LOC(0)
    call dir_create
    lea  rcx, LOC(0)
    lea  rdx, [rel s_chunk_dir]
    mov  r8, rsi
    call str_format
    lea  rcx, LOC(0)
    call dir_create
    test r14d, r14d  ; clear leftovers of a crashed never-saved world
    jz   .active
    lea  rcx, LOC(0)
    call delete_files_in
    test eax, eax
    jz   .active
    lea  rcx, [rel s_stale_chunks]
    mov  edx, eax
    mov  r8, rsi
    call log_printf
.active:

    mov  dword [rel g_world_active], 1
    cmp  dword [rel s_chunkmgr_on], 0
    jne  .mgr_ok
    call chunkmgr_init
    mov  dword [rel s_chunkmgr_on], 1
.mgr_ok:
    mov  [rel s_new_world], r14d
    mov  dword [rel s_tick_acc], 0
    mov  dword [rel s_prev_dead], 0
    call time_ms
    mov  [rel s_load_ms], eax

    lea  rcx, [rel s_start_fmt]
    lea  rdx, [rel s_loaded]
    lea  rax, [rel s_new]
    test r14d, r14d
    cmovnz rdx, rax
    mov  r8, rsi
    mov  r9, [rel g_seed]
    lea  rax, [rel s_survival]
    lea  r10, [rel s_creative]
    cmp  dword [rel g_gamemode], GM_CREATIVE
    cmove rax, r10
    mov  [rsp+32], rax
    call log_printf

    mov  ecx, ST_LOADING
    call game_set_state
    mov  eax, 1
.ret:
    ENDP

PROC game_exit_world, 0
    cmp  dword [rel g_world_active], 0
    je   .title
    cmp  dword [rel g_state], ST_INVENTORY
    jne  .save
    call screens_close  ; give back crafting grid / cursor items
.save:
    cmp  dword [rel g_net_hosting], 0
    je   .nonet
    call net_stop  ; kicks java players while their entities still exist
.nonet:
    call save_world
    call world_clear
    call entity_clear
    call particles_clear
    mov  dword [rel g_world_active], 0
    lea  rcx, [rel s_exit_world]
    lea  rdx, [rel g_world_name]
    call log_printf
.title:
    mov  ecx, ST_TITLE
    call game_set_state
    ENDP

PROC game_shutdown, 0
    lea  rcx, [rel s_shutdown]
    call log_write
    ; automated run closed early (alt+f4, quit from menu) must not look like a
    ; pass to whatever CI script started it
    cmp  dword [rel g_run_mode], 0
    je   .not_auto
    cmp  dword [rel s_auto_phase], AUTO_DONE
    je   .not_auto
    mov  dword [rel game_exit_code], 1
    mov  dword [rel s_auto_phase], AUTO_DONE
    lea  rcx, [rel s_auto_abort]
    call log_write
.not_auto:
    cmp  dword [rel g_net_hosting], 0
    je   .nonet
    call net_stop
.nonet:
    cmp  dword [rel g_world_active], 0
    je   .no_world
    cmp  dword [rel g_state], ST_INVENTORY
    jne  .save
    call screens_close
.save:
    call save_world
.no_world:
    cmp  dword [rel s_chunkmgr_on], 0
    je   .cfg
    call chunkmgr_shutdown
    mov  dword [rel s_chunkmgr_on], 0
.cfg:
    call config_save
    call audio_shutdown
    xor  ecx, ecx
    call platform_set_mouse_capture
    ENDP

PROC game_tick, 0
    inc  qword [rel g_world_time]
    inc  qword [rel g_tick_count]
    mov  eax, [rel g_time_of_day]
    inc  eax
    xor  ecx, ecx
    cmp  eax, DAY_LENGTH
    cmovae eax, ecx
    mov  [rel g_time_of_day], eax
    mov  ecx, [rel g_world_time]
    call texgen_animate
    call player_tick
    call entity_tick_all
    call mobs_spawn_tick
    call ticks_tick
    call blockent_tick
    call weather_tick
    call particles_ambient_tick
    call music_tick
    call save_autosave_tick
    ; every 100 ticks
    mov  rax, [rel g_world_time]
    xor  edx, edx
    mov  ecx, 100
    div  rcx
    test edx, edx
    jnz  .ret
    call update_mood
.ret:
    ENDP

; pausing freezes the world (single player) but streaming and meshing keep going
PROC game_frame, 32
    movss LOC(0), xmm0

    mov  eax, [rel g_window_focused]
    mov  ecx, [rel s_prev_focus]
    mov  [rel s_prev_focus], eax
    cmp  dword [rel g_run_mode], 0
    jne  .auto_input
    test ecx, ecx
    jz   .focus_done
    test eax, eax
    jnz  .focus_done
    cmp  dword [rel g_state], ST_PLAYING
    jne  .focus_done
    mov  ecx, ST_PAUSED
    call game_set_state
    jmp  .focus_done
.auto_input:
    call mask_input
    cmp  dword [rel g_run_mode], 3
    jne  .focus_done
    call script_input
.focus_done:

    call is_simulating
    mov  r12d, eax

    test r12d, r12d
    jz   .no_ticks
    movss xmm0, [rel s_tick_acc]
    addss xmm0, LOC(0)
    minss xmm0, [rel f_max_acc]
    movss [rel s_tick_acc], xmm0
.tick_loop:
    movss xmm0, [rel s_tick_acc]
    comiss xmm0, [rel f_tick]
    jb   .ticks_done
    subss xmm0, [rel f_tick]
    movss [rel s_tick_acc], xmm0
    call game_tick
    jmp  .tick_loop
.ticks_done:
    movss xmm0, [rel s_tick_acc]
    divss xmm0, [rel f_tick]
    minss xmm0, [rel f_one]
    xorps xmm1, xmm1
    maxss xmm0, xmm1
    movss [rel g_partial_tick], xmm0
.no_ticks:

    cmp  dword [rel g_world_active], 0
    je   .no_world
    test r12d, r12d
    jz   .no_player
    movss xmm0, LOC(0)
    call player_update
.no_player:
    cmp  dword [rel g_run_mode], 0
    je   .no_auto
    call auto_update  ; scripted camera wins over the player
.no_auto:
    call chunkmgr_update
    call render_update_meshes
    test r12d, r12d
    jz   .no_particles
    movss xmm0, LOC(0)
    call particles_update
.no_particles:
    call sky_update
    jmp  .world_done
.no_world:
    cmp  dword [rel g_run_mode], 0
    je   .world_done
    call auto_update
.world_done:
    test r12d, r12d
    jnz  .music_done
    call music_tick  ; menus keep the music going
.music_done:

    ; java bridge: sockets every frame. its 20 hz tick keeps going while
    ; paused, java clients would time out otherwise
    cmp  dword [rel g_net_hosting], 0
    je   .net_done
    call net_update
    cmp  dword [rel g_world_active], 0
    je   .net_done
    movss xmm0, [rel s_net_acc]
    addss xmm0, LOC(0)
    minss xmm0, [rel f_max_acc]
    movss [rel s_net_acc], xmm0
.net_tick:
    movss xmm0, [rel s_net_acc]
    comiss xmm0, [rel f_tick]
    jb   .net_done
    subss xmm0, [rel f_tick]
    movss [rel s_net_acc], xmm0
    call mcplay_tick
    jmp  .net_tick
.net_done:

    cmp  dword [rel g_world_active], 0
    je   .death_done
    mov  eax, [rel g_player + PLAYER.dead]
    mov  ecx, [rel s_prev_dead]
    mov  [rel s_prev_dead], eax
    test eax, eax
    jz   .death_done
    test ecx, ecx
    jnz  .death_done
    mov  ecx, [rel g_state]
    cmp  ecx, 31
    ja   .death_done
    mov  edx, LIVE_STATES
    bt   edx, ecx
    jnc  .death_done
    lea  rcx, [rel s_death]
    call log_write
    cmp  dword [rel g_state], ST_INVENTORY
    jne  .to_dead
    call screens_close
.to_dead:
    mov  ecx, ST_DEAD
    call game_set_state
.death_done:

    cmp  dword [rel g_state], ST_LOADING
    jne  .loading_done
    cmp  dword [rel g_world_active], 0
    je   .loading_done
    call chunkmgr_spawn_ready
    test eax, eax
    jz   .loading_done
    cmp  dword [rel s_new_world], 0
    je   .spawned
    call player_spawn
    mov  dword [rel s_new_world], 0
    ; write level.dat right away so a new world exists on disk even if the game
    ; gets killed before the first autosave, and chunk files always match a seed
    call save_world
.spawned:
    call game_autohost
    call time_ms
    sub  eax, [rel s_load_ms]
    lea  rcx, [rel s_ready_fmt]
    mov  edx, eax
    call log_printf
    mov  ecx, ST_PLAYING
    call game_set_state
.loading_done:

    cmp  dword [rel g_state], ST_QUIT
    je   .ret

    ; not while minimised
    cmp  dword [rel g_screen_w], 0
    jle  .no_render
    cmp  dword [rel g_screen_h], 0
    jle  .no_render
    call game_render

    ; F2: read back before the swap
    cmp  dword [rel s_shot_request], 0
    je   .no_shot
    mov  dword [rel s_shot_request], 0
    xor  ecx, ecx
    call screenshot_save
    test eax, eax
    jz   .no_shot
    call announce_screenshot
.no_shot:
    cmp  dword [rel g_run_mode], 0
    je   .no_render
    call auto_after_render
.no_render:
    mov  dword [rel s_swallow_char], 0
.ret:
    ENDP
; --host PORT: open the world to java clients once the spawn area is there
FUNC game_autohost, 0
    mov  ecx, [rel main_cmd_host]
    test ecx, ecx
    jz   .r
    cmp  dword [rel g_net_hosting], 0
    jne  .r
    call net_init
    mov  ecx, [rel main_cmd_host]
    call net_host
.r:
    ENDP

FUNC announce_screenshot, 320
    lea  rcx, LOC(0)
    lea  rdx, [rel s_shot_chat]
    lea  r8, [rel platform_last_shot]
    call str_format
    lea  rcx, LOC(0)
    mov  edx, 0xFFFFFF55
    call chat_add
    ENDP

; has to match save.asm's own (private) check so we never build a path it rejects.
; win32 silently strips trailing '.' and ' ' off path components, so "a." is
; "a" and "..." lands in saves or its parent. leaf
align 16
world_name_ok:
    test rcx, rcx
    jz   .bad
    xor  r8d, r8d
.scan:
    movzx edx, byte [rcx+r8]
    test edx, edx
    jz   .end
    cmp  edx, 32
    jb   .bad
    lea  r9, [rel s_bad_chars]
.bc:
    movzx eax, byte [r9]
    test eax, eax
    jz   .char_ok
    cmp  edx, eax
    je   .bad
    inc  r9
    jmp  .bc
.char_ok:
    inc  r8d
    cmp  r8d, 63
    ja   .bad
    jmp  .scan
.end:
    test r8d, r8d
    jz   .bad
    movzx edx, byte [rcx+r8-1]
    cmp  edx, '.'
    je   .bad
    cmp  edx, ' '
    je   .bad
    mov  eax, 1
    ret
.bad:
    xor  eax, eax
    ret

; plain files only, subdirs stay
%define DF_PAT   0
%define DF_FD    320                    ; WIN32_FIND_DATAA is 320 bytes
%define DF_FILE  656
%define WFD_ATTR 0
%define WFD_NAME 44                     ; cFileName[260]
FUNC delete_files_in, 1008
    mov  rbx, rcx
    xor  r13d, r13d
    lea  rcx, LOC(DF_PAT)
    lea  rdx, [rel s_glob_fmt]
    mov  r8, rbx
    call str_format
    lea  rcx, LOC(DF_PAT)
    lea  rdx, LOC(DF_FD)
    call FindFirstFileA
    cmp  rax, INVALID_HANDLE_VALUE
    je   .done
    mov  r12, rax
.entry:
    test dword LOC(DF_FD+WFD_ATTR), FILE_ATTRIBUTE_DIRECTORY
    jnz  .next  ; also skips . and ..
    lea  rcx, LOC(DF_FILE)
    lea  rdx, [rel s_path_fmt]
    mov  r8, rbx
    lea  r9, LOC(DF_FD+WFD_NAME)
    call str_format
    lea  rcx, LOC(DF_FILE)
    call DeleteFileA
    test eax, eax
    jz   .next
    inc  r13d
.next:
    mov  rcx, r12
    lea  rdx, LOC(DF_FD)
    call FindNextFileA
    test eax, eax
    jnz  .entry
    mov  rcx, r12
    call FindClose
.done:
    mov  eax, r13d
    ENDP

; menus don't draw chat, so load errors go under the world list instead
FUNC game_notice, 0
    mov  r8, rdx
    mov  rdx, rcx
    lea  rcx, [rel s_notice]  ; 63-char name + fmt fits
    call str_format
    call time_seconds
    addsd xmm0, [rel d_notice_secs]
    movsd [rel s_notice_until], xmm0
    ENDP

; drawn in the gap between the list panel and the buttons (g_ui_h - 52)
FUNC draw_notice, 0
    cmp  byte [rel s_notice], 0
    je   .ret
    call time_seconds
    comisd xmm0, [rel s_notice_until]
    jae  .ret
    lea  rcx, [rel s_notice]
    call ui_text_width
    mov  ecx, [rel g_ui_w]
    sub  ecx, eax
    sar  ecx, 1
    mov  eax, 2
    cmp  ecx, eax  ; long name: keep the start visible
    cmovl ecx, eax
    mov  edx, [rel g_ui_h]
    sub  edx, 63
    lea  r8, [rel s_notice]
    mov  r9d, 0xFFFF5555
    call ui_text_shadow
.ret:
    ENDP

PROC game_render, 0
    cmp  dword [rel g_world_active], 0
    je   .clear
    cmp  dword [rel g_state], ST_LOADING
    je   .clear
    call render_set_camera
    call render_world
    jmp  .ui
.clear:
    mov  eax, __float32__(0.055)
    movd xmm0, eax
    mov  eax, __float32__(0.065)
    movd xmm1, eax
    mov  eax, __float32__(0.085)
    movd xmm2, eax
    mov  eax, __float32__(1.0)
    movd xmm3, eax
    call glClearColor
    mov  ecx, GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT
    call glClear
.ui:
    call ui_begin
    cmp  dword [rel g_world_active], 0
    je   .screens
    mov  ecx, [rel g_state]
    cmp  ecx, 31
    ja   .screens
    mov  eax, HUD_STATES
    bt   eax, ecx
    jnc  .screens
    cmp  ecx, ST_PLAYING  ; F1 hides the HUD
    jne  .hud
    cmp  dword [rel g_hide_hud], 0
    jne  .screens
.hud:
    call hud_render
.screens:
    cmp  dword [rel g_state], ST_INVENTORY
    jne  .chat
    call screens_render
.chat:
    cmp  dword [rel g_state], ST_CHAT
    jne  .menus
    call console_render
.menus:
    call menus_render
    cmp  dword [rel g_state], ST_WORLDSELECT
    jne  .done
    call draw_notice
.done:
    call ui_end
    ENDP

PROC game_on_key, 0
    test edx, edx
    jz   .ret  ; releases are polled via g_keys
    cmp  dword [rel g_run_mode], 0
    je   .live
    cmp  dword [rel s_injecting], 0  ; automated: only scripted keys get through
    je   .ret
.live:
    movzx ebx, cl
    lea  rax, [rel g_keys_pressed]
    movzx esi, byte [rax+rbx]  ; 1 = first press, not autorepeat
    cmp  ebx, VK_F11
    jne  .fkeys
    test esi, esi
    jz   .ret
    call platform_toggle_fullscreen
    jmp  .ret
    ; F1-F3 work in any state (screenshot a menu etc). first press only, autorepeat
    ; would just toggle them back and forth
.fkeys:
    cmp  ebx, VK_F2
    jne  .f1f3
    test esi, esi
    jz   .ret
    mov  dword [rel s_shot_request], 1
    jmp  .ret
.f1f3:
    cmp  ebx, VK_F1
    je   .f1f3_world
    cmp  ebx, VK_F3
    jne  .route
.f1f3_world:
    cmp  dword [rel g_world_active], 0
    je   .route
    test esi, esi
    jz   .ret
    lea  rax, [rel g_hide_hud]
    lea  rcx, [rel g_show_debug]
    cmp  ebx, VK_F3
    cmove rax, rcx
    xor  dword [rax], 1
    jmp  .ret
.route:
    mov  eax, [rel g_state]
    cmp  eax, ST_PLAYING
    je   .playing
    cmp  eax, ST_INVENTORY
    je   .inventory
    cmp  eax, ST_CHAT
    je   .chat
    cmp  eax, ST_PAUSED
    je   .paused
    cmp  eax, ST_QUIT
    je   .ret
    mov  ecx, ebx
    call menus_on_key
    jmp  .ret
.inventory:
    mov  ecx, ebx
    call screens_on_key
    jmp  .ret
.chat:
    mov  ecx, ebx
    call console_on_key
    jmp  .ret
.paused:
    cmp  ebx, VK_ESCAPE
    jne  .pause_menu
    test esi, esi
    jz   .ret
    mov  ecx, ST_PLAYING
    call game_set_state
    jmp  .ret
.pause_menu:
    mov  ecx, ebx
    call menus_on_key
    jmp  .ret

.playing:
    lea  eax, [rbx-'1']
    cmp  eax, 8
    ja   .not_digit
    mov  [rel g_player + PLAYER.selected], eax
    jmp  .ret
.not_digit:
    cmp  ebx, 'Q'  ; ctrl = whole stack
    jne  .toggles
    lea  rax, [rel g_keys]
    movzx ecx, byte [rax+VK_CONTROL]
    call player_drop_held
    jmp  .ret
.toggles:
    test esi, esi
    jz   .ret  ; nothing below wants autorepeat
    cmp  ebx, VK_ESCAPE
    jne  .k_e
    mov  ecx, ST_PAUSED
    call game_set_state
    jmp  .ret
.k_e:
    cmp  ebx, 'E'
    jne  .k_t
    mov  dword [rel s_swallow_char], 1
    mov  ecx, SCR_PLAYER
    mov  eax, SCR_CREATIVE
    cmp  dword [rel g_gamemode], GM_CREATIVE
    cmove ecx, eax
    xor  edx, edx
    xor  r8d, r8d
    xor  r9d, r9d
    call screens_open
    jmp  .ret
.k_t:
    xor  edi, edi  ; char the console starts with
    cmp  ebx, 'T'
    je   .open_chat
    mov  edi, '/'
    cmp  ebx, VK_OEM_2
    jne  .k_f1
.open_chat:
    mov  dword [rel s_swallow_char], 1
    mov  ecx, ST_CHAT
    call game_set_state
    mov  ecx, edi
    call console_open
    jmp  .ret
.k_f1:
.k_f5:
    cmp  ebx, VK_F5
    jne  .ret
    mov  eax, [rel g_view_mode]
    inc  eax
    xor  ecx, ecx
    cmp  eax, 3
    cmovae eax, ecx
    mov  [rel g_view_mode], eax
.ret:
    ENDP

; eat the 't' or '/' that opened chat
PROC game_on_char, 0
    cmp  dword [rel s_swallow_char], 0
    je   .ret
    mov  dword [rel s_swallow_char], 0
    mov  eax, [rel g_char_count]
    test eax, eax
    jz   .ret
    ; only if it really is the last queued char, a full queue doesn't store it
    ; and we'd eat something else
    lea  rdx, [rel g_char_queue]
    cmp  [rdx+rax-1], cl
    jne  .ret
    dec  eax
    mov  [rel g_char_count], eax
.ret:
    ENDP

PROC game_on_mouse_button, 0
    cmp  dword [rel g_run_mode], 0
    je   .live
    cmp  dword [rel s_injecting], 0
    je   .ret
.live:
    mov  ebx, ecx
    mov  esi, edx
    mov  eax, [rel g_state]
    cmp  eax, ST_INVENTORY
    je   .inventory
    cmp  eax, ST_PLAYING
    jne  .ret
    cmp  dword [rel g_run_mode], 0  ; automated: never captured, click goes
    jne  .ret  ; straight to the player
    ; click into the window recaptures and gets eaten
    test esi, esi
    jz   .ret
    cmp  dword [rel g_mouse_captured], 0
    jne  .ret
    mov  ecx, 1
    call platform_set_mouse_capture
    cmp  dword [rel g_mouse_captured], 0
    je   .ret
    mov  eax, ebx
    not  eax
    and  [rel g_mouse_pressed], eax
    and  [rel g_mouse_buttons], eax
    jmp  .ret
.inventory:
    mov  ecx, ebx
    mov  edx, esi
    call screens_on_mouse
.ret:
    ENDP

; 9 slots, wraps
PROC game_on_wheel, 0
    cmp  dword [rel g_run_mode], 0
    je   .live
    cmp  dword [rel s_injecting], 0
    je   .ret
.live:
    mov  eax, [rel g_state]
    cmp  eax, ST_INVENTORY
    je   .inventory
    cmp  eax, ST_PLAYING
    jne  .ret
    mov  eax, [rel g_player + PLAYER.selected]
    sub  eax, ecx  ; wheel away = slot to the left
    cdq
    mov  ecx, HOTBAR_SLOTS
    idiv ecx
    test edx, edx
    jns  .pos
    add  edx, HOTBAR_SLOTS
.pos:
    mov  [rel g_player + PLAYER.selected], edx
    jmp  .ret
.inventory:
    call screens_on_wheel
.ret:
    ENDP

PROC game_on_resize, 0
    test ecx, ecx
    jz   .ret
    test edx, edx
    jz   .ret
    cmp  dword [rel g_mouse_captured], 0
    je   .ret
    mov  ecx, 1
    call platform_set_mouse_capture
.ret:
    ENDP

FUNC auto_update, 32
    cmp  dword [rel g_run_mode], 3  ; scripts do this in script_input
    je   .ret
    call time_seconds
    movsd LOC(0), xmm0
    mov  eax, [rel s_auto_phase]
    cmp  eax, AUTO_LOADING
    je   .loading
    cmp  eax, AUTO_RUNNING
    je   .running
    jmp  .ret

.loading:
    cmp  dword [rel g_state], ST_PLAYING
    je   .start_running
    movsd xmm0, LOC(0)
    subsd xmm0, [rel s_auto_t0]
    comisd xmm0, [rel d_load_timeout]
    jb   .ret
    lea  rcx, [rel s_auto_timeout]
    call log_write
    mov  dword [rel game_exit_code], 2
    mov  dword [rel s_auto_phase], AUTO_DONE
    mov  dword [rel g_state], ST_QUIT
    jmp  .ret
.start_running:
    movsd xmm0, LOC(0)
    subsd xmm0, [rel s_auto_t0]
    cvtsd2ss xmm0, xmm0
    movd edx, xmm0
    movsd xmm0, LOC(0)
    movsd [rel s_auto_t0], xmm0
    movsd [rel s_bench_sec_t0], xmm0
    mov  eax, [rel g_player + PLAYER.x]
    mov  [rel s_auto_base+0], eax
    mov  r8d, eax
    mov  eax, [rel g_player + PLAYER.y]
    mov  [rel s_auto_base+4], eax
    mov  r9d, eax
    mov  eax, [rel g_player + PLAYER.z]
    mov  [rel s_auto_base+8], eax
    mov  [rsp+32], rax
    lea  rcx, [rel s_auto_ready]
    call log_printf
    mov  dword [rel s_auto_phase], AUTO_RUNNING
    mov  dword [rel s_auto_shots], 0
    mov  dword [rel s_auto_shot_fail], 0
    mov  dword [rel s_auto_next_log], 1
    mov  dword [rel s_bench_frames], 0
    mov  dword [rel s_bench_sec_frames], 0
    mov  dword [rel s_bench_min], 0x7FFFFFFF
    ; fall through so the camera is placed this frame already

.running:
    movsd xmm0, LOC(0)
    subsd xmm0, [rel s_auto_t0]
    cvtsd2ss xmm5, xmm0
    xorps xmm0, xmm0
    movss [rel g_player + PLAYER.vx], xmm0
    movss [rel g_player + PLAYER.vy], xmm0
    movss [rel g_player + PLAYER.vz], xmm0
    mov  dword [rel g_player + PLAYER.flying], 1
    mov  dword [rel g_player + PLAYER.on_ground], 0
    mov  dword [rel g_player + PLAYER.dead], 0
    cmp  dword [rel g_run_mode], 2
    je   .bench_pose
    ; pose = index of the next screenshot
    mov  eax, [rel s_auto_shots]
    cmp  eax, SELFTEST_SHOTS
    jbe  .pose_idx
    mov  eax, SELFTEST_SHOTS
.pose_idx:
    shl  eax, 4
    lea  rcx, [rel selftest_poses]
    add  rcx, rax
    movss xmm0, [rcx+0]
    cmp  dword [rel s_auto_shots], SELFTEST_SHOTS
    jb   .no_spin
    ; after the last shot: yaw = 30 + (t-10)*20
    movss xmm1, xmm5
    mov  eax, __float32__(10.0)
    movd xmm2, eax
    subss xmm1, xmm2
    mulss xmm1, [rel f_spin]
    addss xmm0, xmm1
.no_spin:
    movss [rel g_player + PLAYER.yaw], xmm0
    movss xmm0, [rcx+4]
    movss [rel g_player + PLAYER.pitch], xmm0
    mov  eax, [rel s_auto_base+0]
    mov  [rel g_player + PLAYER.x], eax
    mov  eax, [rel s_auto_base+8]
    mov  [rel g_player + PLAYER.z], eax
    movss xmm0, [rel s_auto_base+4]
    addss xmm0, [rcx+8]
    movss [rel g_player + PLAYER.y], xmm0
    mov  eax, [rcx+12]
    mov  [rel g_time_of_day], eax
    jmp  .ret
.bench_pose:
    ; bench: north (-z), noon
    mov  eax, [rel s_auto_base+0]
    mov  [rel g_player + PLAYER.x], eax
    mov  eax, [rel f_bench_y]
    mov  [rel g_player + PLAYER.y], eax
    movss xmm0, [rel s_auto_base+8]
    movss xmm1, xmm5
    mulss xmm1, [rel f_bench_speed]
    subss xmm0, xmm1
    movss [rel g_player + PLAYER.z], xmm0
    mov  dword [rel g_player + PLAYER.yaw], 0
    mov  eax, [rel f_bench_pitch]
    mov  [rel g_player + PLAYER.pitch], eax
    mov  dword [rel g_time_of_day], 6000
.ret:
    ENDP

FUNC auto_after_render, 288
    cmp  dword [rel g_run_mode], 3
    jne  .not_script
    call script_after_render
    jmp  .ret
.not_script:
    cmp  dword [rel s_auto_phase], AUTO_RUNNING
    jne  .ret
    call time_seconds
    movsd LOC(0), xmm0
    subsd xmm0, [rel s_auto_t0]
    movsd LOC(8), xmm0
    cmp  dword [rel g_run_mode], 2
    je   .bench

    mov  ebx, [rel s_auto_shots]
    cmp  ebx, SELFTEST_SHOTS
    jae  .stats
    lea  eax, [rbx+1]
    cvtsi2sd xmm1, eax
    mulsd xmm1, [rel d_two]
    movsd xmm0, LOC(8)
    comisd xmm0, xmm1
    jb   .stats
    inc  ebx
    mov  [rel s_auto_shots], ebx
    lea  rcx, LOC(32)
    lea  rdx, [rel s_shot_name]
    mov  r8d, ebx
    call str_format
    lea  rcx, LOC(32)
    call screenshot_save
    lea  r9, [rel s_shot_ok]
    test eax, eax
    jnz  .shot_logged
    inc  dword [rel s_auto_shot_fail]
    lea  r9, [rel s_shot_bad]
.shot_logged:
    lea  rcx, [rel s_auto_shot]
    mov  edx, ebx
    lea  r8, LOC(32)
    call log_printf

.stats:
    cvtsi2sd xmm1, dword [rel s_auto_next_log]
    movsd xmm0, LOC(8)
    comisd xmm0, xmm1
    jb   .end_check
    mov  edx, [rel s_auto_next_log]
    inc  dword [rel s_auto_next_log]
    lea  rcx, [rel s_auto_stats]
    mov  r8d, [rel g_fps]
    mov  r9d, [rel g_chunk_count]
    mov  eax, [rel g_stat_sections_drawn]
    mov  [rsp+32], rax
    mov  eax, [rel g_stat_vertices]
    mov  [rsp+40], rax
    mov  eax, [rel g_stat_meshes_built]
    mov  [rsp+48], rax
    mov  eax, [rel g_entity_count]
    mov  [rsp+56], rax
    mov  eax, [rel g_particle_count]
    mov  [rsp+64], rax
    call log_printf
.end_check:
    movsd xmm0, LOC(8)
    comisd xmm0, [rel d_selftest_end]
    jb   .ret
    mov  edx, [rel s_auto_shot_fail]
    test edx, edx
    jz   .pass
    lea  rcx, [rel s_auto_fail]
    call log_printf
    mov  dword [rel game_exit_code], 1
    jmp  .quit
.pass:
    lea  rcx, [rel s_auto_pass]
    mov  rdx, [rel g_frame_count]
    mov  r8d, [rel s_auto_shots]
    call log_printf
    mov  dword [rel game_exit_code], 0
.quit:
    mov  dword [rel s_auto_phase], AUTO_DONE
    mov  dword [rel g_state], ST_QUIT
    jmp  .ret

.bench:
    inc  dword [rel s_bench_frames]
    inc  dword [rel s_bench_sec_frames]
    movsd xmm0, LOC(0)
    subsd xmm0, [rel s_bench_sec_t0]
    comisd xmm0, [rel d_one]
    jb   .bench_end
    cvtsi2sd xmm1, dword [rel s_bench_sec_frames]
    divsd xmm1, xmm0
    cvtsd2si eax, xmm1
    cmp  eax, [rel s_bench_min]
    jge  .not_min
    mov  [rel s_bench_min], eax
.not_min:
    mov  dword [rel s_bench_sec_frames], 0
    movsd xmm0, LOC(0)
    movsd [rel s_bench_sec_t0], xmm0
    mov  r8d, eax
    movsd xmm0, LOC(8)
    cvttsd2si edx, xmm0
    lea  rcx, [rel s_bench_sec]
    mov  r9d, [rel g_chunk_count]
    mov  eax, [rel g_stat_sections_drawn]
    mov  [rsp+32], rax
    mov  eax, [rel g_stat_vertices]
    mov  [rsp+40], rax
    call log_printf
.bench_end:
    movsd xmm0, LOC(8)
    comisd xmm0, [rel d_bench_end]
    jb   .ret
    cvtsi2sd xmm1, dword [rel s_bench_frames]
    divsd xmm1, xmm0
    cvtsd2ss xmm1, xmm1
    movd edx, xmm1
    mov  r8d, [rel s_bench_min]
    cmp  r8d, 0x7FFFFFFF
    jne  .min_ok
    xor  r8d, r8d
.min_ok:
    mov  r9d, [rel s_bench_frames]
    cvtsd2ss xmm0, xmm0
    movd eax, xmm0
    mov  [rsp+32], rax
    lea  rcx, [rel s_bench_done]
    call log_printf
    mov  dword [rel game_exit_code], 0
    mov  dword [rel s_auto_phase], AUTO_DONE
    mov  dword [rel g_state], ST_QUIT
.ret:
    ENDP

; --script runner. the file is read into buffer A plus a copy B that gets
; tokenised in place, every line is validated up front and each timed line
; becomes one ACT record (A keeps the readable text for the log).
;
; ordering is the fiddly bit. a line waits for the next frame if its key or
; button still has a release pending, if it's timed after a tap/click from this
; frame, if it's a 'key' after a 'type' (text is eaten at render time, keys
; right away), or a 'type' right after the key that opened chat. 'shot' ends
; the batch.
;
; exit: 0 ok, 1 shot failed / closed early, 2 spawn not ready in 90 s,
; 3 no GL window, 4 hard timeout (300 s), 5 bad script
%define SCR_MAX_ACTIONS 4096 ; v1: game scratch #13
%define ACT_SIZE        64 ; v1: game scratch #14
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (game:14)
%define ACT_OP          0 ; v1: game scratch #15
%define ACT_T           4 ; v1: game scratch #16
    ; FIXME: negative world x/z needs sar 4, not shr 4 (game:16)
%define ACT_I0          8 ; v1: game scratch #17
%define ACT_I1          12 ; v1: game scratch #18
    ; note: rcx = state ptr, rdx = index, r8d = flags (game:18)
%define ACT_I2          16 ; v1: game scratch #19
%define ACT_I3          20 ; v1: game scratch #20
    ; TODO: verify 16-byte rsp alignment before inner call (game:20)
%define ACT_F0          24 ; v1: game scratch #21
%define ACT_F1          28 ; v1: game scratch #22
    ; temp: spill r12/r13 across helper call until reg alloc pass (game:22)
%define ACT_F2          32 ; v1: game scratch #23
%define ACT_LINE        36 ; v1: game scratch #24
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (game:24)
%define ACT_STR         40 ; v1: game scratch #25
%define ACT_TEXT        48 ; v1: game scratch #26
    ; TODO: clamp index before table lookup on malformed input (game:26)

%define OP_CMD          0 ; v1: game scratch #28
    ; TODO: hoist invariant pointer load out of .loop (game:28)
%define OP_POS          1 ; v1: game scratch #29
%define OP_LOOK         2 ; v1: game scratch #30
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (game:30)
%define OP_TURN         3 ; v1: game scratch #31
%define OP_KEY          4 ; v1: game scratch #32
    ; FIXME: negative world x/z needs sar 4, not shr 4 (game:32)
%define OP_TYPE         5 ; v1: game scratch #33
%define OP_MOUSE        6 ; v1: game scratch #34
    ; note: rcx = state ptr, rdx = index, r8d = flags (game:34)
%define OP_CLICK        7 ; v1: game scratch #35
%define OP_HOLD         8 ; v1: game scratch #36
    ; TODO: verify 16-byte rsp alignment before inner call (game:36)
%define OP_WHEEL        9 ; v1: game scratch #37
%define OP_SHOT         10 ; v1: game scratch #38
    ; temp: spill r12/r13 across helper call until reg alloc pass (game:38)
%define OP_FRAMES       11 ; v1: game scratch #39
%define OP_HIDEHUD      12 ; v1: game scratch #40
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (game:40)
%define OP_WAIT         13 ; v1: game scratch #41
%define OP_QUIT         14 ; v1: game scratch #42
    ; TODO: clamp index before table lookup on malformed input (game:42)
%define OP_COUNT        15 ; v1: game scratch #43

%define KEY_DOWN        0 ; v1: game scratch #45
%define KEY_UP          1 ; v1: game scratch #46
    ; TODO: hoist invariant pointer load out of .loop (game:46)
%define KEY_TAP         2 ; v1: game scratch #47

%define SCR_PATH_MAX    200 ; v1: game scratch #49

section .rdata ; v1: game scratch #51
align 8 ; v1: game scratch #52
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (game:52)
scr_op_names: ; v1: game scratch #53
    dq n_cmd, n_pos, n_look, n_turn, n_key, n_type, n_mouse, n_click ; v1: game scratch #54
    ; FIXME: negative world x/z needs sar 4, not shr 4 (game:54)
    dq n_hold, n_wheel, n_shot, n_frames, n_hidehud, n_wait, n_quit
scr_key_names:                          ; letters/digits/F1..F12 are parsed, not listed
    dq kn_space, VK_SPACE
    dq kn_shift, VK_SHIFT
    dq kn_ctrl, VK_CONTROL
    dq kn_control, VK_CONTROL
    dq kn_alt, VK_MENU
    dq kn_esc, VK_ESCAPE
    dq kn_escape, VK_ESCAPE
    dq kn_enter, VK_RETURN
    dq kn_return, VK_RETURN
    dq kn_tab, VK_TAB
    dq kn_back, VK_BACK
    dq kn_backspace, VK_BACK
    dq kn_delete, VK_DELETE
    dq kn_home, VK_HOME
    dq kn_end, VK_END
    dq kn_pgup, VK_PRIOR
    dq kn_pgdn, VK_NEXT
    dq kn_up, VK_UP
    dq kn_down, VK_DOWN
    dq kn_left, VK_LEFT
    dq kn_right, VK_RIGHT
    dq kn_slash, VK_OEM_2
    dq 0, 0

n_cmd:          db "cmd", 0
n_pos:          db "pos", 0
n_look:         db "look", 0
n_turn:         db "turn", 0
n_key:          db "key", 0
n_type:         db "type", 0
n_mouse:        db "mouse", 0
n_click:        db "click", 0
n_hold:         db "hold", 0
n_wheel:        db "wheel", 0
n_shot:         db "shot", 0
n_frames:       db "frames", 0
n_hidehud:      db "hidehud", 0
n_wait:         db "wait", 0
n_quit:         db "quit", 0
n_title:        db "title", 0
n_world:        db "world", 0
n_keep:         db "keep", 0
n_survival:     db "survival", 0
n_creative:     db "creative", 0
n_down:         db "down", 0
n_up:           db "up", 0
n_tap:          db "tap", 0
n_on:           db "on", 0
n_off:          db "off", 0
n_left:         db "left", 0
n_right:        db "right", 0
n_middle:       db "middle", 0
kn_space:       db "SPACE", 0
kn_shift:       db "SHIFT", 0
kn_ctrl:        db "CTRL", 0
kn_control:     db "CONTROL", 0
kn_alt:         db "ALT", 0
kn_esc:         db "ESC", 0
kn_escape:      db "ESCAPE", 0
kn_enter:       db "ENTER", 0
kn_return:      db "RETURN", 0
kn_tab:         db "TAB", 0
kn_back:        db "BACK", 0
kn_backspace:   db "BACKSPACE", 0
kn_delete:      db "DELETE", 0
kn_home:        db "HOME", 0
kn_end:         db "END", 0
kn_pgup:        db "PGUP", 0
kn_pgdn:        db "PGDN", 0
kn_up:          db "UP", 0
kn_down:        db "DOWN", 0
kn_left:        db "LEFT", 0
kn_right:       db "RIGHT", 0
kn_slash:       db "SLASH", 0

s_scr_open:     db "script: running '%s' (%d bytes)", 0
s_scr_noread:   db "script: ERROR cannot read the script file '%s'", 0
s_scr_empty:    db "script: ERROR no setup line ('world <name> <seed> <survival|creative> [keep]' or 'title')", 0
s_scr_e_setup:  db "script: ERROR line %d: the first directive must be 'world <name> <seed> <survival|creative> [keep]' or 'title'", 0
s_scr_e_name:   db "script: ERROR line %d: bad world name '%s' (1-63 letters, digits, '-', '_', '.')", 0
s_scr_e_mode:   db "script: ERROR line %d: game mode must be survival or creative, not '%s'", 0
s_scr_e_time:   db "script: ERROR line %d: '%s' is not a time in seconds", 0
s_scr_e_order:  db "script: ERROR line %d: time %.2f is earlier than the line before (times must not decrease)", 0
s_scr_e_nodir:  db "script: ERROR line %d: a time must be followed by a directive", 0
s_scr_e_unknown: db "script: ERROR line %d: unknown directive '%s'", 0
s_scr_e_missing: db "script: ERROR line %d: '%s' needs more arguments", 0
s_scr_e_number: db "script: ERROR line %d: '%s' is not a number", 0
s_scr_e_value:  db "script: ERROR line %d: bad value '%s'", 0
s_scr_e_extra:  db "script: ERROR line %d: too many arguments for '%s'", 0
s_scr_e_many:   db "script: ERROR line %d: too many actions (at most 4096)", 0
s_scr_parsed:   db "script: %d actions, script ends at t=%.2f s", 0
s_scr_setup_world: db "script: setup world '%s' seed %l %s%s", 0
s_scr_keep_txt: db " (keep existing save)", 0
s_scr_nothing:  db 0
s_scr_setup_title: db "script: setup title screen - timeline started", 0
s_scr_ready:    db "script: spawn area ready after %.1f s at %.1f %.1f %.1f - timeline started", 0
s_scr_load_to:  db "script: FAIL - spawn area not ready after 90 s (exit code 2)", 0
s_scr_timeout:  db "script: FAIL - hard timeout of 300 s reached (exit code 4)", 0
s_scr_exec:     db "script: t=%.2f %s", 0
s_scr_shot:     db "script: screenshot %s %s", 0
s_scr_frames_fmt: db "%s_%04d.bmp", 0
s_scr_frames_done: db "script: frames %s_0001.bmp .. %s_%04d.bmp written", 0
s_scr_end:      db "script: end of script reached", 0
s_scr_shot_fail_exit: db "script: FAIL - %d screenshot(s) could not be written (exit code 1)", 0
s_scr_exit:     db "script: exit code %d (%l frames, %d screenshots, %d failed)", 0
align 4
f_pitch_lo:     dd -89.9
f_pitch_hi:     dd 89.9
f_rep_delay:    dd 0.5                  ; windows default
f_rep_rate:     dd 0.0333333            ; ~30/s
align 8
d_script_timeout: dq 300.0

section .bss
alignb 8
s_scr_buf_a:    resq 1                  ; lines NUL-terminated, for the log
s_scr_buf_b:    resq 1                  ; same text, tokenised in place
s_scr_world:    resq 1
s_scr_seed:     resq 1
s_scr_start:    resq 1
s_type_ptr:     resq 1
s_shot_path:    resq 1
s_frames_prefix: resq 1
s_injecting:    resd 1                  ; 1 while scripted events go to the hooks
s_typed_frame:  resd 1
s_scr_setup:    resd 1                  ; 1 title, 2 world
s_scr_mode:     resd 1
s_scr_keep:     resd 1
s_scr_count:    resd 1
s_scr_next:     resd 1
s_scr_last_t:   resd 1
s_scr_end_t:    resd 1
s_scr_t:        resd 1
s_scr_t_on:     resd 1
s_tap_pending:  resd 1
s_tap_t:        resd 1                  ; float
s_rep_vk:       resd 1                  ; 0 = none
s_rep_next:     resd 1
s_scr_btn:      resd 1
s_rel_btn:      resd 1
s_scr_mx:       resd 1
s_scr_my:       resd 1
s_hold_on:      resd 4                  ; index = bsf MB_*
s_hold_end:     resd 4
s_turn_on:      resd 1
s_turn_t0:      resd 1
s_turn_dur:     resd 1
s_turn_dyaw:    resd 1
s_turn_dpitch:  resd 1
s_turn_done:    resd 1
s_frames_every: resd 1
s_frames_left:  resd 1
s_frames_ctr:   resd 1
s_frames_idx:   resd 1
s_scr_shots:    resd 1
s_scr_shot_fail: resd 1
s_scr_keys:     resb 256
s_rel_keys:     resb 256
alignb 16
s_scr_actions:  resb SCR_MAX_ACTIONS*ACT_SIZE

section .text

align 16
scr_skip_ws:
    mov  rax, rcx
.lp:
    cmp  byte [rax], ' '
    je   .adv
    cmp  byte [rax], 9
    jne  .done
.adv:
    inc  rax
    jmp  .lp
.done:
    ret

; scr_tok -> rax token (NUL-terminated in place) or 0, rdx = cursor after. leaf
align 16
scr_tok:
.sk:
    movzx eax, byte [rcx]
    cmp  al, ' '
    je   .adv
    cmp  al, 9
    jne  .start
.adv:
    inc  rcx
    jmp  .sk
.start:
    test al, al
    jz   .none
    mov  rax, rcx
.lp:
    movzx edx, byte [rcx]
    test dl, dl
    jz   .end0
    cmp  dl, ' '
    je   .cut
    cmp  dl, 9
    je   .cut
    inc  rcx
    jmp  .lp
.cut:
    mov  byte [rcx], 0
    lea  rdx, [rcx+1]
    ret
    ; v1 temporary guard (game #18)
    xor     r11d, r11d ; clear v1 slot 18
    ; v1 temporary guard (game #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (game #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (game #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (game #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (game #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (game #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (game #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (game #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (game #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (game #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (game #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (game #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (game #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (game #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (game #48)
    xor     r11d, r11d ; clear v1 slot 48
