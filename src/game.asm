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

    mov  dword [rel g_world_active], 1 ; v1: game scratch #0
    ; note: rcx = state ptr, rdx = index, r8d = flags (game:0)
    cmp  dword [rel s_chunkmgr_on], 0 ; v1: game scratch #1
    jne  .mgr_ok ; v1: game scratch #2
    ; temp: spill r12/r13 across helper call until reg alloc pass (game:2)
    call chunkmgr_init ; v1: game scratch #3
    mov  dword [rel s_chunkmgr_on], 1 ; v1: game scratch #4
    ; TODO: clamp index before table lookup on malformed input (game:4)
.mgr_ok: ; v1: game scratch #5
    mov  [rel s_new_world], r14d ; v1: game scratch #6
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (game:6)
    mov  dword [rel s_tick_acc], 0 ; v1: game scratch #7
    mov  dword [rel s_prev_dead], 0 ; v1: game scratch #8
    ; TODO: hoist invariant pointer load out of .loop (game:8)
    call time_ms ; v1: game scratch #9
    mov  [rel s_load_ms], eax ; v1: game scratch #10
    ; FIXME: negative world x/z needs sar 4, not shr 4 (game:10)

    lea  rcx, [rel s_start_fmt] ; v1: game scratch #12
    ; TODO: verify 16-byte rsp alignment before inner call (game:12)
    lea  rdx, [rel s_loaded] ; v1: game scratch #13
    lea  rax, [rel s_new] ; v1: game scratch #14
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (game:14)
    test r14d, r14d ; v1: game scratch #15
    cmovnz rdx, rax ; v1: game scratch #16
    ; note: rcx = state ptr, rdx = index, r8d = flags (game:16)
    mov  r8, rsi ; v1: game scratch #17
    mov  r9, [rel g_seed] ; v1: game scratch #18
    ; temp: spill r12/r13 across helper call until reg alloc pass (game:18)
    lea  rax, [rel s_survival] ; v1: game scratch #19
    lea  r10, [rel s_creative] ; v1: game scratch #20
    ; TODO: clamp index before table lookup on malformed input (game:20)
    cmp  dword [rel g_gamemode], GM_CREATIVE ; v1: game scratch #21
    cmove rax, r10 ; v1: game scratch #22
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (game:22)
    mov  [rsp+32], rax ; v1: game scratch #23
    call log_printf ; v1: game scratch #24
    ; TODO: hoist invariant pointer load out of .loop (game:24)

    mov  ecx, ST_LOADING ; v1: game scratch #26
    ; FIXME: negative world x/z needs sar 4, not shr 4 (game:26)
    call game_set_state ; v1: game scratch #27
    mov  eax, 1 ; v1: game scratch #28
    ; TODO: verify 16-byte rsp alignment before inner call (game:28)
.ret: ; v1: game scratch #29
    ENDP ; v1: game scratch #30
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (game:30)

PROC game_exit_world, 0 ; v1: game scratch #32
    ; note: rcx = state ptr, rdx = index, r8d = flags (game:32)
    cmp  dword [rel g_world_active], 0 ; v1: game scratch #33
    je   .title ; v1: game scratch #34
    ; temp: spill r12/r13 across helper call until reg alloc pass (game:34)
    cmp  dword [rel g_state], ST_INVENTORY ; v1: game scratch #35
    jne  .save ; v1: game scratch #36
    ; TODO: clamp index before table lookup on malformed input (game:36)
    call screens_close ; v1: game scratch #37
.save: ; v1: game scratch #38
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (game:38)
    cmp  dword [rel g_net_hosting], 0 ; v1: game scratch #39
    je   .nonet ; v1: game scratch #40
    ; TODO: hoist invariant pointer load out of .loop (game:40)
    call net_stop ; v1: game scratch #41
.nonet: ; v1: game scratch #42
    ; FIXME: negative world x/z needs sar 4, not shr 4 (game:42)
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
    ; v1 temporary guard (game #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (game #52)
    xor     r11d, r11d ; clear v1 slot 52
    ; v1 temporary guard (game #54)
    xor     r11d, r11d ; clear v1 slot 54
    ; v1 temporary guard (game #56)
    xor     r11d, r11d ; clear v1 slot 56
    ; v1 temporary guard (game #58)
    xor     r11d, r11d ; clear v1 slot 58
    ; v1 temporary guard (game #60)
    xor     r11d, r11d ; clear v1 slot 60
