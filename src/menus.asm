%define IMPL_MENUS
%include "common.inc"
%include "net.inc"                      ; NET_DEFAULT_PORT, MAX_NET_CONNS

extern ui_flush, ui_text_ex, ui_text_centered_ex, ui_text_dims, ui_time, ui_focus
extern ui_max_scale, ui_edit_keys, ui_edit_nkeys, ui_tb_owner
extern ui_qp, ui_emit_q, ui_bind_tex, ui_argb_gl, ui_set_xywh, ui_col_scale
extern con_host_port, con_unhost, con_host_err
extern FileTimeToLocalFileTime, FileTimeToSystemTime

; exported so the ui tests can poke at them
global menu_name, menu_seed, menu_folder, menu_world_count, menu_sel, menu_worlds
global menu_winfo, menu_wl_info, menu_wl_date

%define LOGO_COLS       66
%define MAX_WORLDS      64
%define FOLDER_MAX      24
%define ROW_H           28              ; world list row, two lines of text
%define LIST_W          320             ; world list width when the window has room
%define WL_INFO_LEN     64
%define WL_DATE_LEN     24
; level.dat header info per world, filled by save_list_worlds (handed back in
; rdx). save.asm has the same defines
%define WI_SEED         0
%define WI_FTIME        8
%define WI_WTIME        16
%define WI_MODE         24
%define WI_OK           28
%define WI_NAME         32
%define WI_SIZE         64
%define C_HOST_ERR      0xFFFF6A6A
; /kill's death cause, one past DMG_SUN. console.asm has the same define
%define DMG_COMMAND     10
%define NUM_SPLASH      26
%define NUM_TIPS        14

; ui_qp field offsets, must match ui.asm
%define QU0 16
%define QV0 20
%define QU1 24
%define QV1 28
%define QC0 32
%define QC1 36
%define QC2 40
%define QC3 44

; wrappers so the call sites aren't 8 movs each
%macro RECT 5
    mov  eax, %5
    mov  [rsp+32], eax
    mov  r9d, %4
    mov  r8d, %3
    mov  edx, %2
    mov  ecx, %1
    call ui_rect
%endmacro
%macro RECTG 6
    mov  eax, %6
    mov  [rsp+40], eax
    mov  eax, %5
    mov  [rsp+32], eax
    mov  r9d, %4
    mov  r8d, %3
    mov  edx, %2
    mov  ecx, %1
    call ui_rect_grad
%endmacro
%macro TILE 5
    mov  eax, %5
    mov  [rsp+32], eax
    mov  r9d, %4
    mov  r8d, %3
    mov  edx, %2
    mov  ecx, %1
    call ui_tile
%endmacro
%macro BTN 6
    mov  eax, %6
    mov  [rsp+40], rax
    lea  rax, [rel %5]
    mov  [rsp+32], rax
    mov  r9d, %4
    mov  r8d, %3
    mov  edx, %2
    mov  ecx, %1
    call ui_button
%endmacro
%macro BTNP 6
    mov  r10, %5                        ; label first, callers often pass it in rax
    mov  [rsp+32], r10
    mov  eax, %6
    mov  [rsp+40], rax
    mov  r9d, %4
    mov  r8d, %3
    mov  edx, %2
    mov  ecx, %1
    call ui_button
%endmacro
%macro CTEXT 4
    mov  qword [rsp+32], 1
    mov  r9d, %4
    lea  r8, [rel %3]
    mov  edx, %2
    mov  ecx, %1
    call ui_text_centered_ex
%endmacro
%macro CTEXTP 4
    mov  qword [rsp+32], 1
    mov  r9d, %4
    mov  r8, %3
    mov  edx, %2
    mov  ecx, %1
    call ui_text_centered_ex
%endmacro
%macro TEXT 4
    mov  qword [rsp+40], 1
    mov  qword [rsp+32], 1
    mov  r9d, %4
    lea  r8, [rel %3]
    mov  edx, %2
    mov  ecx, %1
    call ui_text_ex
%endmacro
%macro TEXTP 4
    mov  qword [rsp+40], 1
    mov  qword [rsp+32], 1
    mov  r9d, %4
    mov  r8, %3
    mov  edx, %2
    mov  ecx, %1
    call ui_text_ex
%endmacro
%macro SLIDER 7                         ; x, y, w, float var, min, max, fmt symbol
    lea  rax, [rel %7]
    mov  [rsp+48], rax
    mov  dword [rsp+40], __float32__(%6)
    mov  dword [rsp+32], __float32__(%5)
    lea  r9, [rel %4]
    mov  r8d, %3
    mov  edx, %2
    mov  ecx, %1
    call ui_slider
%endmacro
%macro CYCLE 6                          ; x, y, prefix sym, settings field, count, names table
    lea  rax, [rel %6]
    mov  [rsp+40], rax
    mov  qword [rsp+32], %5
    lea  r9, [rel g_settings]
    add  r9, %4
    lea  r8, [rel %3]
    mov  edx, %2
    mov  ecx, %1
    call menu_cycle
%endmacro

section .rdata
align 16
f_abs_mask: dd 0x7FFFFFFF, 0, 0, 0
f_one:      dd 1.0
f_half:     dd 0.5
f_two:      dd 2.0
f_hundred:  dd 100.0
f_cent:     dd 0.01
f_sens_k:   dd 0.0015                   ; 100% sens = 0.15 deg per mouse count
f_tau:      dd 6.2831853
f_tenth:    dd 0.1
f_1_8:      dd 1.8
f_max_sc:   dd 2.0
f_32:       dd 32.0
f_m20:      dd -20.0
f_zero:     dd 0.0
f_dbl:      dd 0.4
f_bg_vx:    dd 6.0
f_bg_vy:    dd 11.0
f_sweep_v:  dd 14.0
f_sweep_p:  dd 150.0
f_sweep_o:  dd 20.0
f_four:     dd 4.0
f_sweep_a:  dd 22.5
f_dots:     dd 2.5
f_hop:      dd 5.0
f_hop_ph:   dd 0.9
f_hop_h:    dd 8.0
f_tip_t:    dd 0.2                      ; 1/5s
f_inv64:    dd 0.015625                 ; 4 texels in the 256px atlas
f_inv16:    dd 0.0625
f_tiny:     dd 0.0001
f_2s:       dd 2.0

; logo letters: width, 5 rows (high bit = leftmost), then 0=MINE / 1=ASSEMBLY
logo_letters:
    db 5, 0x11,0x1B,0x15,0x11,0x11, 0, 0      ; M
    db 3, 0x07,0x02,0x02,0x02,0x07, 0, 0      ; I
    db 5, 0x11,0x19,0x15,0x13,0x11, 0, 0      ; N
    db 4, 0x0F,0x08,0x0E,0x08,0x0F, 0, 0      ; E
    db 5, 0x0E,0x11,0x1F,0x11,0x11, 1, 0      ; A
    db 5, 0x0F,0x10,0x0E,0x01,0x1E, 1, 0      ; S
    db 5, 0x0F,0x10,0x0E,0x01,0x1E, 1, 0      ; S
    db 4, 0x0F,0x08,0x0E,0x08,0x0F, 1, 0      ; E
    db 5, 0x11,0x1B,0x15,0x11,0x11, 1, 0      ; M
    db 5, 0x1E,0x11,0x1E,0x11,0x1E, 1, 0      ; B
    db 4, 0x08,0x08,0x08,0x08,0x0F, 1, 0      ; L
    db 5, 0x11,0x0A,0x04,0x04,0x04, 1, 0      ; Y
%define LOGO_LETTERS 12

s_subtitle:     db "PURE  x86-64  ASSEMBLY  EDITION", 0
s_singleplayer: db "Singleplayer", 0
s_settings_btn: db "Settings...", 0
s_quit:         db "Quit Game", 0
s_version:      db "MineAssembly 1.0 - x86-64 assembly", 0
s_mojang:       db "Not affiliated with Mojang", 0
s_selworld:     db "Select World", 0
s_noworlds:     db "No worlds yet - create one!", 0
s_play:         db "Play Selected World", 0
s_create_new:   db "Create New World", 0
s_delete:       db "Delete", 0
s_really:       db 0x0C, "c", "Click again to delete", 0
s_back:         db "Back", 0
s_cw_title:     db "Create New World", 0
s_lbl_name:     db "World Name", 0
s_lbl_seed:     db "Seed for the World Generator", 0
s_seed_hint:    db "Leave blank for a random seed", 0
fmt_saved_in:   db "Will be saved in: saves\%s", 0
fmt_gamemode:   db "Game Mode: %s", 0
s_survival:     db "Survival", 0
s_creative:     db "Creative", 0
s_desc_surv:    db "Gather, craft and survive the night.", 0
s_desc_crea:    db "Unlimited blocks, free flight, no damage.", 0
s_cancel:       db "Cancel", 0
s_new_world:    db "New World", 0
s_world_def:    db "World", 0
fmt_unique:     db "%s (%d)", 0
s_generating:   db "Generating world", 0
s_dots:         db "...", 0
fmt_worldname:  db 0x0C, "7", "%s", 0
fmt_percent:    db "%d%%", 0
fmt_chunkinfo:  db "%d chunks generated  |  %d loaded", 0
s_game_menu:    db "Game Menu", 0
s_back_game:    db "Back to Game", 0
s_save_quit:    db "Save and Quit to Title", 0
fmt_host_open:  db "Open to Java Edition (port %d)", 0
fmt_host_stop:  db "Stop hosting (port %d)", 0
fmt_host_count: db "%d of %d java players online", 0
s_host_hint:    db "Lets Java Edition 26.1 players join", 0
fmt_wl_info:    db "%s, day %l, seed %l", 0
fmt_wl_date:    db "%d-%02d-%02d %02d:%02d", 0
s_wl_bad:       db "level.dat looks damaged", 0
fmt_pauseinfo:  db 0x0C, "7", "World ", 0x0C, "f", "%s", 0x0C, "7", "   Day ", 0x0C, "f", "%l", 0x0C, "7", "   Seed ", 0x0C, "f", "%l", 0
s_settings:     db "Settings", 0
fmt_rd:         db "Render Distance: %d chunks", 0
fmt_fov:        db "FOV: %d", 0
fmt_sens:       db "Sensitivity: %d%%", 0
fmt_music:      db "Music: %d%%", 0
fmt_sound:      db "Sound: %d%%", 0
fmt_cycle:      db "%s: %s", 0
s_gui_scale:    db "GUI Scale", 0
s_fullscreen:   db "Fullscreen", 0
s_invert:       db "Invert Mouse", 0
s_smooth:       db "Smooth Lighting", 0
s_clouds:       db "Clouds", 0
s_leaves:       db "Fancy Leaves", 0
s_bob:          db "View Bobbing", 0
s_particles:    db "Particles", 0
s_vsync:        db "VSync", 0
s_showfps:      db "Show FPS", 0
s_done:         db "Done", 0
s_off:          db "OFF", 0
s_on:           db "ON", 0
s_c_off:        db "Off", 0
s_c_fast:       db "Fast", 0
s_c_fancy:      db "Fancy", 0
s_p_min:        db "Minimal", 0
s_p_dec:        db "Decreased", 0
s_p_all:        db "All", 0
s_g_auto:       db "Auto", 0
s_g_1:          db "1", 0
s_g_2:          db "2", 0
s_g_3:          db "3", 0
s_g_4:          db "4", 0
s_died:         db "You died!", 0
s_respawn:      db "Respawn", 0
s_title_screen: db "Title Screen", 0
s_d0:           db "Something got you.", 0
s_d1:           db "You hit the ground too hard.", 0
s_d2:           db "You tried to swim in lava.", 0
s_d3:           db "You ran out of air.", 0
s_d4:           db "You were slain by a shambler.", 0
s_d5:           db "You were blown up.", 0
s_d6:           db "You starved to death.", 0
s_d7:           db "You fell out of the world.", 0
s_d8:           db "You were struck down.", 0
s_d9:           db "You burned to a crisp.", 0
s_d10:          db "You were killed.", 0           ; DMG_COMMAND (/kill)

; splash lines. yes I had fun with these
sp0:  db "100% assembly!", 0
sp1:  db "No C was harmed!", 0
sp2:  db "mov eax, fun", 0
sp3:  db "Zero assets!", 0
sp4:  db "Ring 3 sandbox!", 0
sp5:  db "Now with SIMD!", 0
sp6:  db "Hand-rolled since 2026!", 0
sp7:  db "xor eax, eax", 0
sp8:  db "Every pixel computed!", 0
sp9:  db "No garbage collector!", 0
sp10: db "Stack aligned to 16!", 0
sp11: db "Push, pop, play!", 0
sp12: db "Registers are friends!", 0
sp13: db "Bytes all the way down!", 0
sp14: db "jmp right in!", 0
sp15: db "Win64 ABI compliant!", 0
sp16: db "Also try NASM!", 0
sp17: db "Made of opcodes!", 0
sp18: db "Procedurally generated!", 0
sp19: db "cpuid says hi!", 0
sp20: db "Infinite* worlds!", 0
sp21: db "Now 0% interpreted!", 0
sp22: db "lea is not a typo!", 0
sp23: db "Shadow space included!", 0
sp24: db "Synthesized music!", 0
sp25: db "ret 0", 0

tp0:  db 0x0C, "e", "Tip: ", 0x0C, "f", "Press F3 for the debug overlay.", 0
tp1:  db 0x0C, "e", "Tip: ", 0x0C, "f", "Press T or / to chat - try /help.", 0
tp2:  db 0x0C, "e", "Tip: ", 0x0C, "f", "Double-tap space in creative to fly.", 0
tp3:  db 0x0C, "e", "Tip: ", 0x0C, "f", "Torches keep the shamblers away.", 0
tp4:  db 0x0C, "e", "Fact: ", 0x0C, "f", "Every texture here is generated by asm.", 0
tp5:  db 0x0C, "e", "Tip: ", 0x0C, "f", "F5 cycles the camera view.", 0
tp6:  db 0x0C, "e", "Tip: ", 0x0C, "f", "F2 saves a screenshot.", 0
tp7:  db 0x0C, "e", "Tip: ", 0x0C, "f", "Smelt ores in a furnace for ingots.", 0
tp8:  db 0x0C, "e", "Fact: ", 0x0C, "f", "There is no C runtime in this game.", 0
tp9:  db 0x0C, "e", "Fact: ", 0x0C, "f", "The music is composed live by a synth.", 0
tp10: db 0x0C, "e", "Tip: ", 0x0C, "f", "Use /time set night to see the stars.", 0
tp11: db 0x0C, "e", "Tip: ", 0x0C, "f", "Glowcrystals light up caves.", 0
tp12: db 0x0C, "e", "Fact: ", 0x0C, "f", "Chunks are generated on worker threads.", 0
tp13: db 0x0C, "e", "Tip: ", 0x0C, "f", "Sprint by double-tapping W.", 0

align 8
splash_tab: dq sp0,sp1,sp2,sp3,sp4,sp5,sp6,sp7,sp8,sp9,sp10,sp11,sp12,sp13
            dq sp14,sp15,sp16,sp17,sp18,sp19,sp20,sp21,sp22,sp23,sp24,sp25
tip_tab:    dq tp0,tp1,tp2,tp3,tp4,tp5,tp6,tp7,tp8,tp9,tp10,tp11,tp12,tp13
death_tab:  dq s_d0,s_d1,s_d2,s_d3,s_d4,s_d5,s_d6,s_d7,s_d8,s_d9,s_d10
names_onoff:    dq s_off, s_on
names_clouds:   dq s_c_off, s_c_fast, s_c_fancy
names_particles: dq s_p_min, s_p_dec, s_p_all
names_gui:      dq s_g_auto, s_g_1, s_g_2, s_g_3, s_g_4
names_mode:     dq s_survival, s_creative

section .bss
alignb 16
menu_worlds:        resb 32*MAX_WORLDS
menu_winfo:         resb WI_SIZE*MAX_WORLDS  ; cached on entering the screen
menu_wl_info:       resb WL_INFO_LEN*MAX_WORLDS ; "Survival, day 3, seed 42"
menu_wl_date:       resb WL_DATE_LEN*MAX_WORLDS ; last played, local time
menu_name:          resb 32
menu_seed:          resb 32
menu_name_cache:    resb 32
menu_folder_base:   resb 32
menu_folder:        resb 64
menu_lbl:           resb 128
menu_fname:         resb 64
menu_buf:           resb 256
menu_tmp:           resd 8
menu_last_state:    resd 1
menu_enter_key:     resd 1
menu_enter_t:       resd 1
menu_splash_idx:    resd 1
menu_tip_base:      resd 1
menu_world_count:   resd 1
menu_sel:           resd 1
menu_scroll:        resd 1
menu_sel_moved:     resd 1
menu_confirm:       resd 1
menu_last_click:    resd 1
menu_mode:          resd 1
menu_cache_valid:   resd 1
menu_settings_ret:  resd 1
menu_inited:        resd 1
menu_lx:            resd 1              ; splash anchors on these
menu_ly:            resd 1
menu_lc:            resd 1
menu_host_failed:   resd 1              ; show con_host_err under the host button

section .text

PROC menus_render
    cmp  dword [rel menu_inited], 0
    jne  .ini
    mov  dword [rel menu_inited], 1
    mov  dword [rel menu_last_state], -1
.ini:
    mov  eax, [rel g_state]
    cmp  eax, [rel menu_last_state]
    je   .same
    mov  ecx, eax
    call menus_enter
.same:
    mov  eax, [rel g_state]
    cmp  eax, ST_TITLE
    je   .title
    cmp  eax, ST_WORLDSELECT
    je   .ws
    cmp  eax, ST_CREATEWORLD
    je   .cw
    cmp  eax, ST_LOADING
    je   .load
    cmp  eax, ST_PAUSED
    je   .pause
    cmp  eax, ST_SETTINGS
    je   .set
    cmp  eax, ST_DEAD
    je   .dead
    jmp  .done
.title: call menu_title
    jmp  .done
.ws:    call menu_worldselect
    jmp  .done
.cw:    call menu_create
    jmp  .done
.load:  call menu_loading
    jmp  .done
.pause: call menu_pause
    jmp  .done
.set:   call menu_settings
    jmp  .done
.dead:  call menu_dead
.done:
    mov  dword [rel menu_enter_key], 0
    mov  dword [rel ui_edit_nkeys], 0   ; drop caret keys nobody consumed
ENDP

PROC menus_enter
    mov  dword [rel menu_inited], 1
    mov  [rel menu_last_state], ecx
    mov  ebx, ecx
    mov  dword [rel menu_enter_key], 0
    mov  dword [rel ui_focus], 0
    mov  dword [rel ui_tb_owner], 0
    movsd xmm0, [rel g_time_total]
    cvtsd2ss xmm0, xmm0
    movss [rel menu_enter_t], xmm0
    cmp  ebx, ST_TITLE
    je   .title
    cmp  ebx, ST_WORLDSELECT
    je   .ws
    cmp  ebx, ST_CREATEWORLD
    je   .cw
    cmp  ebx, ST_SETTINGS
    je   .set
    cmp  ebx, ST_LOADING
    je   .load
    cmp  ebx, ST_PAUSED
    je   .pause
    jmp  .done
.pause:
    mov  dword [rel menu_host_failed], 0
    jmp  .done
.title:
    call menu_random
    xor  edx, edx
    mov  ecx, NUM_SPLASH
    div  rcx
    mov  [rel menu_splash_idx], edx
    jmp  .done
.ws:
    call menu_refresh_worlds
    jmp  .done
.cw:
    lea  rdi, [rel menu_name]
    lea  rsi, [rel s_new_world]
    mov  ecx, 10
    rep  movsb
    mov  byte [rel menu_seed], 0
    mov  dword [rel menu_mode], GM_SURVIVAL
    mov  dword [rel menu_cache_valid], 0
    mov  dword [rel ui_focus], 1
    jmp  .done
.set:
    mov  eax, ST_TITLE
    mov  ecx, ST_PAUSED
    cmp  dword [rel g_world_active], 0
    cmovne eax, ecx
    mov  [rel menu_settings_ret], eax
    jmp  .done
.load:
    call menu_random
    xor  edx, edx
    mov  ecx, NUM_TIPS
    div  rcx
    mov  [rel menu_tip_base], edx
.done:
ENDP

PROC menus_on_key
    movzx ebx, cl
    mov  esi, [rel g_state]
    ; caret keys get queued, ui_textbox replays them next frame. autorepeat ok here
    cmp  dword [rel ui_focus], 0
    je   .nocaret
    cmp  ebx, VK_LEFT
    je   .caret
    cmp  ebx, VK_RIGHT
    je   .caret
    cmp  ebx, VK_HOME
    je   .caret
    cmp  ebx, VK_END
    je   .caret
    cmp  ebx, VK_DELETE
    jne  .nocaret
.caret:
    mov  eax, [rel ui_edit_nkeys]
    cmp  eax, 16
    jae  .done
    lea  rcx, [rel ui_edit_keys]
    mov  [rcx+rax], bl
    inc  eax
    mov  [rel ui_edit_nkeys], eax
    jmp  .done
.nocaret:
    ; game_on_key forwards autorepeat. fine for arrows, but holding Esc
    ; would fly through create -> select -> title in one go
    cmp  ebx, VK_UP
    je   .repeat_ok
    cmp  ebx, VK_DOWN
    je   .repeat_ok
    lea  rax, [rel g_keys_pressed]
    cmp  byte [rax+rbx], 0
    je   .done
.repeat_ok:
    cmp  ebx, VK_RETURN
    jne  .noenter
    mov  dword [rel menu_enter_key], 1
    jmp  .done
.noenter:
    cmp  ebx, VK_ESCAPE
    jne  .noesc
    cmp  esi, ST_PAUSED
    jne  .e1
    mov  ecx, ST_PLAYING
    call game_set_state
    jmp  .done
.e1:
    cmp  esi, ST_SETTINGS
    jne  .e2
    call config_save
    mov  ecx, [rel menu_settings_ret]
    call game_set_state
    jmp  .done
.e2:
    cmp  esi, ST_WORLDSELECT
    jne  .e3
    mov  ecx, ST_TITLE
    call game_set_state
    jmp  .done
.e3:
    cmp  esi, ST_CREATEWORLD
    jne  .done
    mov  ecx, ST_WORLDSELECT
    call game_set_state
    jmp  .done
.noesc:
    cmp  ebx, VK_TAB
    jne  .notab
    cmp  esi, ST_CREATEWORLD
    jne  .done
    mov  eax, 2
    mov  ecx, 1
    cmp  dword [rel ui_focus], 1
    cmove ecx, eax
    mov  [rel ui_focus], ecx
    jmp  .done
.notab:
    cmp  esi, ST_WORLDSELECT
    jne  .done
    mov  eax, [rel menu_sel]
    cmp  ebx, VK_UP
    jne  .nup
    dec  eax
    jmp  .move
.nup:
    cmp  ebx, VK_DOWN
    jne  .done
    inc  eax
.move:
    mov  ecx, [rel menu_world_count]
    test ecx, ecx
    jz   .done
    test eax, eax
    jns  .m0
    xor  eax, eax
.m0:
    cmp  eax, ecx
    jl   .m1
    lea  eax, [rcx-1]
.m1:
    mov  [rel menu_sel], eax
    mov  dword [rel menu_confirm], 0
    mov  dword [rel menu_sel_moved], 1
.done:
ENDP

; splitmix64 finalizer on top, the raw tsc low bits are useless for % n
PROC menu_random
    rdtsc
    shl  rdx, 32
    or   rax, rdx
    mov  rbx, rax
    call time_ms
    shl  rax, 17
    xor  rbx, rax
    call rng_next
    xor  rax, rbx
    mov  rcx, 0x9E3779B97F4A7C15
    add  rax, rcx
    mov  rcx, rax
    shr  rcx, 30
    xor  rax, rcx
    mov  rcx, 0xBF58476D1CE4E5B9
    imul rax, rcx
    mov  rcx, rax
    shr  rcx, 27
    xor  rax, rcx
    mov  rcx, 0x94D049BB133111EB
    imul rax, rcx
    mov  rcx, rax
    shr  rcx, 31
    xor  rax, rcx
ENDP

; mostly stone, ores rare. diamond is 1/256
LEAF menu_pick_tile
    imul eax, ecx, 0x27D4EB2F
    imul edx, edx, 0x165667B1
    xor  eax, edx
    mov  edx, eax
    shr  edx, 15
    xor  eax, edx
    imul eax, eax, 0x85EBCA77
    mov  edx, eax
    shr  edx, 13
    xor  eax, edx
    and  eax, 255
    cmp  eax, 6
    jb   .coal
    cmp  eax, 9
    jb   .iron
    cmp  eax, 10
    jb   .gold
    cmp  eax, 11
    jb   .diamond
    cmp  eax, 34
    jb   .cobble
    cmp  eax, 48
    jb   .gravel
    cmp  eax, 62
    jb   .dirt
    cmp  eax, 66
    jb   .mossy
    mov  eax, T_STONE
    ret
.coal:   mov eax, T_COAL_ORE
    ret
.iron:   mov eax, T_IRON_ORE
    ret
.gold:   mov eax, T_GOLD_ORE
    ret
.diamond: mov eax, T_DIAMOND_ORE
    ret
.cobble: mov eax, T_COBBLE
    ret
.gravel: mov eax, T_GRAVEL
    ret
.dirt:   mov eax, T_DIRT
    ret
.mossy:  mov eax, T_MOSSY_COBBLE
    ret

; ecx=1 forces the rock wall. in-game it's just a dark overlay
PROC menu_background, 32
    test ecx, ecx
    jnz  .anim
    cmp  dword [rel g_world_active], 0
    je   .anim
    mov  ebx, [rel g_ui_w]
    mov  esi, [rel g_ui_h]
    RECTG 0, 0, ebx, esi, 0x90101018, 0xC0101018
    jmp  .done
.anim:
    movss xmm0, [rel ui_time]
    mulss xmm0, [rel f_bg_vx]
    cvttss2si eax, xmm0
    mov  ecx, eax
    sar  ecx, 5
    mov  LOC(0), ecx
    and  eax, 31
    mov  LOC(4), eax
    movss xmm0, [rel ui_time]
    mulss xmm0, [rel f_bg_vy]
    cvttss2si eax, xmm0
    mov  ecx, eax
    sar  ecx, 5
    mov  LOC(8), ecx
    and  eax, 31
    mov  LOC(12), eax
    mov  r14d, [rel g_ui_w]
    shr  r14d, 5
    add  r14d, 2                        ; +2 or the edges show a gap
    mov  r15d, [rel g_ui_h]
    shr  r15d, 5
    add  r15d, 2
    xor  esi, esi
.row:
    xor  edi, edi
.col:
    lea  ecx, [rdi]
    add  ecx, LOC(0)
    lea  edx, [rsi]
    add  edx, LOC(8)
    call menu_pick_tile
    mov  LOC(16), eax
    mov  r12d, edi
    shl  r12d, 5
    sub  r12d, LOC(4)
    mov  r13d, esi
    shl  r13d, 5
    sub  r13d, LOC(12)
    TILE r12d, r13d, 32, LOC(16), 0xFF44444C
    inc  edi
    cmp  edi, r14d
    jb   .col
    inc  esi
    cmp  esi, r15d
    jb   .row
    mov  ebx, [rel g_ui_w]
    mov  esi, [rel g_ui_h]
    mov  eax, esi
    xor  edx, edx
    mov  ecx, 3
    div  ecx
    mov  edi, eax
    RECTG 0, 0, ebx, edi, 0xD0000000, 0x01000000
    mov  r12d, esi
    sub  r12d, edi
    RECTG 0, r12d, ebx, edi, 0x01000000, 0xD0000000
.done:
ENDP

; out of range = 0, the bevel pass relies on that
LEAF menu_logo_bit
    xor  eax, eax
    test ecx, ecx
    js   .r
    test edx, edx
    js   .r
    cmp  edx, 5
    jge  .r
    movzx r8d, byte [rbx]
    cmp  ecx, r8d
    jge  .r
    movzx r9d, byte [rbx+rdx+1]
    sub  r8d, ecx
    dec  r8d                            ; bit index = width-1-col
    bt   r9d, r8d
    setc al
.r: ret

; letters are 5-row bitmaps, every set bit is a little block. 4 passes:
; extrusion, stone face, bevels, then a shine sweeping across
PROCX menu_logo, 64
    mov  eax, [rel g_ui_w]
    sub  eax, 24
    xor  edx, edx
    mov  ecx, LOGO_COLS
    div  ecx
    cmp  eax, 2
    jge  .c1
    mov  eax, 2
.c1:
    cmp  eax, 8
    jle  .c2
    mov  eax, 8
.c2:
    mov  r12d, eax                      ; c = cell px
    imul eax, eax, LOGO_COLS
    mov  r13d, [rel g_ui_w]
    sub  r13d, eax
    sar  r13d, 1
    mov  r14d, [rel g_ui_h]
    shr  r14d, 2
    imul eax, r12d, 5
    sub  r14d, eax
    sub  r14d, 12
    cmp  r14d, 6
    jge  .y0
    mov  r14d, 6
.y0:
    mov  [rel menu_lx], r13d
    mov  [rel menu_ly], r14d
    mov  [rel menu_lc], r12d
    mov  eax, r12d
    xor  edx, edx
    mov  ecx, 3
    div  ecx
    cmp  eax, 1
    jge  .d0
    mov  eax, 1
.d0:
    mov  r15d, eax                      ; extrusion depth
    ; sweep centre in cells along the diagonal, wraps every f_sweep_p
    movss xmm6, [rel ui_time]
    mulss xmm6, [rel f_sweep_v]
    movss xmm0, xmm6
    divss xmm0, [rel f_sweep_p]
    roundss xmm0, xmm0, 1
    mulss xmm0, [rel f_sweep_p]
    subss xmm6, xmm0
    subss xmm6, [rel f_sweep_o]

    mov  dword LOC(0), 0                ; pass 0..3
.pass:
    lea  rbx, [rel logo_letters]
    mov  dword LOC(4), 0
    mov  dword LOC(8), 0
.letter:
    mov  dword LOC(12), 0
.row:
    mov  dword LOC(16), 0
.col:
    mov  ecx, LOC(16)
    mov  edx, LOC(12)
    call menu_logo_bit
    test eax, eax
    jz   .next
    mov  eax, LOC(8)
    add  eax, LOC(16)
    mov  LOC(36), eax                   ; gx
    imul eax, r12d
    add  eax, r13d
    mov  LOC(20), eax
    mov  eax, LOC(12)
    imul eax, r12d
    add  eax, r14d
    mov  LOC(24), eax
    mov  eax, LOC(0)
    cmp  eax, 1
    jb   .p_extrude
    je   .p_face
    cmp  eax, 2
    je   .p_bevel
    jmp  .p_shine
.p_extrude:
    mov  esi, r15d
.ex:
    ; closer layers lighter. +8 on blue so it isn't dead grey
    lea  eax, [rsi-1]
    imul eax, eax, 0x1C
    xor  edx, edx
    div  r15d
    mov  ecx, 0x34
    sub  ecx, eax
    mov  eax, ecx
    shl  eax, 8
    or   eax, ecx
    shl  eax, 8
    lea  ecx, [rcx+8]
    or   eax, ecx
    or   eax, 0xFF000000
    mov  LOC(28), eax
    mov  edi, LOC(20)
    add  edi, esi
    mov  eax, LOC(24)
    add  eax, esi
    mov  LOC(32), eax
    RECT edi, LOC(32), r12d, r12d, LOC(28)
    dec  esi
    jnz  .ex
    jmp  .next
    ; 4x4 texel window picked by (gx&3, row&3) so the stone flows across
    ; the whole word. f_tiny keeps the uvs off the neighbouring atlas tile
.p_face:
    mov  ecx, [rel g_tex_atlas]
    call ui_bind_tex
    mov  ecx, LOC(20)
    mov  edx, LOC(24)
    mov  r8d, r12d
    mov  r9d, r12d
    call ui_set_xywh
    lea  rdi, [rel ui_qp]
    mov  eax, LOC(36)
    and  eax, 3
    cvtsi2ss xmm0, eax
    mulss xmm0, [rel f_inv64]
    mov  eax, T_STONE & 15
    cvtsi2ss xmm1, eax
    mulss xmm1, [rel f_inv16]
    addss xmm0, xmm1
    addss xmm0, [rel f_tiny]
    movss [rdi+QU0], xmm0
    addss xmm0, [rel f_inv64]
    subss xmm0, [rel f_tiny]
    subss xmm0, [rel f_tiny]
    movss [rdi+QU1], xmm0
    mov  eax, LOC(12)
    and  eax, 3
    cvtsi2ss xmm0, eax
    mulss xmm0, [rel f_inv64]
    mov  eax, T_STONE >> 4
    cvtsi2ss xmm1, eax
    mulss xmm1, [rel f_inv16]
    addss xmm0, xmm1
    addss xmm0, [rel f_tiny]
    movss [rdi+QV0], xmm0
    addss xmm0, [rel f_inv64]
    subss xmm0, [rel f_tiny]
    subss xmm0, [rel f_tiny]
    movss [rdi+QV1], xmm0
    ; ASSEMBLY gets a cold blue tint, bottom edge a bit darker
    mov  ecx, 0xFFFFFFFF
    mov  edx, 0xFFB8CCFF
    cmp  byte [rbx+6], 0
    cmovne ecx, edx
    mov  LOC(28), ecx
    call ui_argb_gl
    mov  [rdi+QC0], eax
    mov  [rdi+QC1], eax
    mov  ecx, LOC(28)
    mov  edx, 0xD0
    call ui_col_scale
    mov  ecx, eax
    call ui_argb_gl
    mov  [rdi+QC2], eax
    mov  [rdi+QC3], eax
    call ui_emit_q
    jmp  .next
.p_bevel:
    mov  ecx, LOC(16)
    mov  edx, LOC(12)
    dec  edx
    call menu_logo_bit
    test eax, eax
    jnz  .b1
    RECT LOC(20), LOC(24), r12d, 1, 0x80FFFFFF
.b1:
    mov  ecx, LOC(16)
    dec  ecx
    mov  edx, LOC(12)
    call menu_logo_bit
    test eax, eax
    jnz  .b2
    RECT LOC(20), LOC(24), 1, r12d, 0x50FFFFFF
.b2:
    mov  ecx, LOC(16)
    mov  edx, LOC(12)
    inc  edx
    call menu_logo_bit
    test eax, eax
    jnz  .b3
    mov  eax, LOC(24)
    add  eax, r12d
    dec  eax
    mov  LOC(32), eax
    RECT LOC(20), LOC(32), r12d, 1, 0x70000000
.b3:
    mov  ecx, LOC(16)
    inc  ecx
    mov  edx, LOC(12)
    call menu_logo_bit
    test eax, eax
    jnz  .next
    mov  eax, LOC(20)
    add  eax, r12d
    dec  eax
    mov  LOC(32), eax
    RECT LOC(32), LOC(24), 1, r12d, 0x50000000
    jmp  .next
    ; alpha = (4 - |gx-row - centre|) * 22.5
.p_shine:
    mov  eax, LOC(36)
    sub  eax, LOC(12)
    cvtsi2ss xmm0, eax
    subss xmm0, xmm6
    andps xmm0, [rel f_abs_mask]
    movss xmm1, [rel f_four]
    subss xmm1, xmm0
    xorps xmm2, xmm2
    ucomiss xmm1, xmm2
    jbe  .next
    mulss xmm1, [rel f_sweep_a]
    cvttss2si eax, xmm1
    shl  eax, 24
    or   eax, 0x00FFFFFF
    mov  LOC(28), eax
    RECT LOC(20), LOC(24), r12d, r12d, LOC(28)
.next:
    inc  dword LOC(16)
    movzx eax, byte [rbx]
    cmp  LOC(16), eax
    jb   .col
    inc  dword LOC(12)
    cmp  dword LOC(12), 5
    jb   .row
    movzx eax, byte [rbx]
    inc  eax
    add  LOC(8), eax
    add  rbx, 8
    inc  dword LOC(4)
    cmp  dword LOC(4), LOGO_LETTERS
    jb   .letter
    inc  dword LOC(0)
    cmp  dword LOC(0), 4
    jb   .pass
    mov  ecx, [rel g_ui_w]
    shr  ecx, 1
    imul edx, r12d, 5
    add  edx, r14d
    add  edx, r15d
    add  edx, 5
    mov  LOC(0), edx
    CTEXT ecx, LOC(0), s_subtitle, 0xFFF0B040
ENDPX

; the yellow splash text. tilted -20 deg and pulsing, done with the GL
; matrix stack since the ui batcher can't rotate
PROCX menu_splash, 32
    mov  eax, [rel menu_splash_idx]
    cmp  eax, NUM_SPLASH
    jb   .ok
    xor  eax, eax
.ok:
    lea  rcx, [rel splash_tab]
    mov  rsi, [rcx+rax*8]
    mov  rcx, rsi
    call ui_text_dims
    mov  ebx, eax
    ; s = (1.8 - |sin(2 pi t)|*0.1) * 100 / (w+32). long lines shrink, max 2x
    movss xmm0, [rel ui_time]
    mulss xmm0, [rel f_tau]
    call math_sin
    andps xmm0, [rel f_abs_mask]
    mulss xmm0, [rel f_tenth]
    movss xmm6, [rel f_1_8]
    subss xmm6, xmm0
    mulss xmm6, [rel f_hundred]
    lea  eax, [rbx+32]
    cvtsi2ss xmm0, eax
    divss xmm6, xmm0
    minss xmm6, [rel f_max_sc]
    mov  eax, [rel menu_lc]
    imul ecx, eax, LOGO_COLS-3
    add  ecx, [rel menu_lx]
    cvtsi2ss xmm7, ecx
    ; keep it on screen
    lea  ecx, [rbx+12]
    cvtsi2ss xmm0, ecx
    mulss xmm0, [rel f_half]
    mulss xmm0, xmm6
    cvtsi2ss xmm1, dword [rel g_ui_w]
    subss xmm1, xmm0
    minss xmm7, xmm1
    imul edx, eax, 6
    add  edx, [rel menu_ly]
    add  edx, 4
    cvtsi2ss xmm8, edx
    call ui_flush
    call glPushMatrix
    movss xmm0, xmm7
    movss xmm1, xmm8
    xorps xmm2, xmm2
    call glTranslatef
    movss xmm0, [rel f_m20]
    xorps xmm1, xmm1
    xorps xmm2, xmm2
    movss xmm3, [rel f_one]
    call glRotatef
    movss xmm0, xmm6
    movss xmm1, xmm6
    movss xmm2, [rel f_one]
    call glScalef
    mov  ecx, ebx
    shr  ecx, 1
    neg  ecx
    mov  edx, -4
    mov  r8, rsi
    mov  r9d, 0xFFFFFF00
    mov  qword [rsp+32], 1
    mov  qword [rsp+40], 1
    call ui_text_ex
    call ui_flush
    call glPopMatrix
ENDPX

PROC menu_title, 32
    xor  ecx, ecx
    call menu_background
    call menu_logo
    call menu_splash
    mov  ebx, [rel g_ui_w]
    shr  ebx, 1
    lea  edi, [rbx-100]
    mov  esi, [rel g_ui_h]
    shr  esi, 2
    add  esi, 48
    BTN  edi, esi, 200, 20, s_singleplayer, 1
    or   eax, [rel menu_enter_key]
    jz   .b2
    mov  ecx, ST_WORLDSELECT
    call game_set_state
    jmp  .foot
.b2:
    add  esi, 24
    BTN  edi, esi, 200, 20, s_settings_btn, 1
    test eax, eax
    jz   .b3
    mov  dword [rel menu_settings_ret], ST_TITLE
    mov  ecx, ST_SETTINGS
    call game_set_state
    jmp  .foot
.b3:
    add  esi, 24
    BTN  edi, esi, 200, 20, s_quit, 1
    test eax, eax
    jz   .foot
    mov  ecx, ST_QUIT
    call game_set_state
.foot:
    mov  esi, [rel g_ui_h]
    sub  esi, 10
    TEXT 2, esi, s_version, 0xFFB4B4B4
    lea  rcx, [rel s_mojang]
    call ui_text_dims
    mov  edi, [rel g_ui_w]
    sub  edi, eax
    sub  edi, 2
    TEXT edi, esi, s_mojang, 0xFF8C8C8C
ENDP

PROC menu_refresh_worlds
    lea  rcx, [rel menu_worlds]
    mov  edx, MAX_WORLDS
    call save_list_worlds
    mov  r12, rdx                       ; header info, see save_list_worlds
    test eax, eax
    jns  .p
    xor  eax, eax
.p:
    cmp  eax, MAX_WORLDS
    jle  .q
    mov  eax, MAX_WORLDS
.q:
    mov  [rel menu_world_count], eax
    mov  ebx, eax
    ; cache the info + its text now, the list is redrawn every frame
    lea  rdi, [rel menu_winfo]
    xor  eax, eax
    mov  ecx, WI_SIZE*MAX_WORLDS
    rep  stosb
    lea  rdi, [rel menu_wl_info]
    mov  ecx, WL_INFO_LEN*MAX_WORLDS
    rep  stosb
    lea  rdi, [rel menu_wl_date]
    mov  ecx, WL_DATE_LEN*MAX_WORLDS
    rep  stosb
    test ebx, ebx
    jz   .cached
    test r12, r12
    jz   .cached
    mov  rsi, r12
    lea  rdi, [rel menu_winfo]
    imul ecx, ebx, WI_SIZE
    rep  movsb
    xor  esi, esi
.text:
    mov  ecx, esi
    call menu_world_text
    inc  esi
    cmp  esi, ebx
    jb   .text
.cached:
    mov  ecx, -1
    test ebx, ebx
    jz   .s
    xor  ecx, ecx
.s:
    mov  [rel menu_sel], ecx
    mov  dword [rel menu_scroll], 0
    mov  dword [rel menu_confirm], 0
    mov  dword [rel menu_sel_moved], 0
    mov  dword [rel menu_last_click], 0xC2C80000   ; -100.0f, no phantom double click
ENDP

PROC menu_world_text, 32
    mov  ebx, ecx
    imul eax, ebx, WI_SIZE
    lea  r12, [rel menu_winfo]
    add  r12, rax
    imul eax, ebx, WL_INFO_LEN
    lea  rdi, [rel menu_wl_info]
    add  rdi, rax
    cmp  dword [r12+WI_OK], 0
    je   .bad
    mov  rax, [r12+WI_WTIME]
    xor  edx, edx
    mov  ecx, DAY_LENGTH
    div  rcx
    inc  rax
    mov  r9, rax
    mov  eax, [r12+WI_MODE]
    and  eax, 1
    lea  rcx, [rel names_mode]
    mov  r8, [rcx+rax*8]
    mov  rax, [r12+WI_SEED]
    mov  [rsp+32], rax
    mov  rcx, rdi
    lea  rdx, [rel fmt_wl_info]
    call str_format
    jmp  .date
.bad:
    mov  rcx, rdi
    lea  rdx, [rel s_wl_bad]
    call str_copy
.date:
    cmp  qword [r12+WI_FTIME], 0
    je   .done
    lea  rcx, [r12+WI_FTIME]
    lea  rdx, LOC(0)
    call FileTimeToLocalFileTime
    test eax, eax
    jz   .done
    lea  rcx, LOC(0)
    lea  rdx, LOC(8)                    ; SYSTEMTIME
    call FileTimeToSystemTime
    test eax, eax
    jz   .done
    imul eax, ebx, WL_DATE_LEN
    lea  rcx, [rel menu_wl_date]
    add  rcx, rax
    lea  rdx, [rel fmt_wl_date]
    movzx r8d, word LOC(8)              ; year
    movzx r9d, word LOC(10)             ; month
    movzx eax, word LOC(14)             ; day
    mov  [rsp+32], rax
    movzx eax, word LOC(16)             ; hour
    mov  [rsp+40], rax
    movzx eax, word LOC(18)             ; minute
    mov  [rsp+48], rax
    call str_format
.done:
ENDP

; locals: 0 tmp, 4 double click, 8 row y, 12 hover, 16..24 rect xy / text y, 28 list w,
; 32 delete label, 40 world name, 48 info line, 56 date
PROCX menu_worldselect, 64
    xor  ecx, ecx
    call menu_background
    mov  ebx, [rel g_ui_w]
    shr  ebx, 1
    CTEXT ebx, 12, s_selworld, 0xFFFFFFFF
    mov  eax, [rel g_ui_w]
    sub  eax, 16
    cmp  eax, LIST_W
    jle  .lw
    mov  eax, LIST_W
.lw:
    and  eax, ~1
    mov  LOC(28), eax
    shr  eax, 1
    mov  r12d, ebx
    sub  r12d, eax
    mov  r13d, 28
    mov  r14d, [rel g_ui_h]
    sub  r14d, 28+64
    cmp  r14d, ROW_H+4
    jge  .lh
    mov  r14d, ROW_H+4
.lh:
    lea  eax, [r14-4]
    xor  edx, edx
    mov  ecx, ROW_H
    div  ecx
    mov  r15d, eax
    RECT r12d, r13d, LOC(28), r14d, 0x90000000
    RECT r12d, r13d, LOC(28), 1, 0x40FFFFFF
    lea  eax, [r13+r14-1]
    mov  LOC(0), eax
    RECT r12d, LOC(0), LOC(28), 1, 0x40FFFFFF
    mov  ecx, r12d
    mov  edx, r13d
    mov  r8d, LOC(28)
    mov  r9d, r14d
    call ui_mouse_in
    test eax, eax
    jz   .nowheel
    mov  eax, [rel g_wheel]
    sub  [rel menu_scroll], eax
.nowheel:
    ; arrows moved the selection, scroll it into view
    cmp  dword [rel menu_sel_moved], 0
    je   .clamp
    mov  dword [rel menu_sel_moved], 0
    mov  eax, [rel menu_sel]
    cmp  eax, [rel menu_scroll]
    jge  .sv1
    mov  [rel menu_scroll], eax
.sv1:
    mov  ecx, [rel menu_scroll]
    add  ecx, r15d
    cmp  eax, ecx
    jl   .clamp
    sub  eax, r15d
    inc  eax
    mov  [rel menu_scroll], eax
.clamp:
    mov  eax, [rel menu_world_count]
    sub  eax, r15d
    jns  .c0
    xor  eax, eax ; v1: menus scratch #0
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (menus:0)
.c0: ; v1: menus scratch #1
    cmp  [rel menu_scroll], eax ; v1: menus scratch #2
    ; FIXME: negative world x/z needs sar 4, not shr 4 (menus:2)
    jle  .c1 ; v1: menus scratch #3
    mov  [rel menu_scroll], eax ; v1: menus scratch #4
    ; TODO: verify 16-byte rsp alignment before inner call (menus:4)
.c1: ; v1: menus scratch #5
    cmp  dword [rel menu_scroll], 0 ; v1: menus scratch #6
    ; TODO: hoist invariant pointer load out of .loop (menus:6)
    jge  .c2 ; v1: menus scratch #7
    mov  dword [rel menu_scroll], 0 ; v1: menus scratch #8
    ; TODO: clamp index before table lookup on malformed input (menus:8)
.c2: ; v1: menus scratch #9
    mov  dword LOC(4), 0 ; v1: menus scratch #10
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (menus:10)
    xor  esi, esi ; v1: menus scratch #11
.entry: ; v1: menus scratch #12
    ; temp: spill r12/r13 across helper call until reg alloc pass (menus:12)
    cmp  esi, r15d ; v1: menus scratch #13
    jge  .entries_done ; v1: menus scratch #14
    ; note: rcx = state ptr, rdx = index, r8d = flags (menus:14)
    mov  edi, [rel menu_scroll] ; v1: menus scratch #15
    add  edi, esi ; v1: menus scratch #16
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (menus:16)
    cmp  edi, [rel menu_world_count] ; v1: menus scratch #17
    jge  .entries_done ; v1: menus scratch #18
    ; FIXME: negative world x/z needs sar 4, not shr 4 (menus:18)
    imul eax, esi, ROW_H ; v1: menus scratch #19
    lea  eax, [r13+rax+2] ; v1: menus scratch #20
    ; TODO: verify 16-byte rsp alignment before inner call (menus:20)
    mov  LOC(8), eax ; v1: menus scratch #21
    lea  ecx, [r12+2] ; v1: menus scratch #22
    ; TODO: hoist invariant pointer load out of .loop (menus:22)
    mov  edx, eax ; v1: menus scratch #23
    mov  r8d, LOC(28) ; v1: menus scratch #24
    ; TODO: clamp index before table lookup on malformed input (menus:24)
    sub  r8d, 4 ; v1: menus scratch #25
    mov  r9d, ROW_H ; v1: menus scratch #26
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (menus:26)
    call ui_mouse_in ; v1: menus scratch #27
    mov  LOC(12), eax ; v1: menus scratch #28
    ; temp: spill r12/r13 across helper call until reg alloc pass (menus:28)
    lea  eax, [r12+2] ; v1: menus scratch #29
    mov  LOC(16), eax ; v1: menus scratch #30
    ; note: rcx = state ptr, rdx = index, r8d = flags (menus:30)
    mov  eax, LOC(28) ; v1: menus scratch #31
    sub  eax, 4
    mov  LOC(0), eax
    cmp  edi, [rel menu_sel]
    jne  .nosel
    RECT LOC(16), LOC(8), LOC(0), ROW_H, 0xFFA0A0A8
    lea  eax, [r12+3]
    mov  LOC(20), eax
    mov  eax, LOC(8)
    inc  eax
    mov  LOC(24), eax
    sub  dword LOC(0), 2
    RECT LOC(20), LOC(24), LOC(0), ROW_H-2, 0xFF101014
    jmp  .drawn
.nosel:
    cmp  dword LOC(12), 0
    je   .drawn
    RECT LOC(16), LOC(8), LOC(0), ROW_H, 0x30FFFFFF
.drawn:
    lea  ecx, [r12+6]
    mov  edx, LOC(8)
    add  edx, 6
    mov  r8d, B_GRASS
    call ui_item_icon
    ; the typed name from level.dat, the folder if there's none
    mov  eax, edi
    shl  eax, 5
    lea  rcx, [rel menu_worlds]
    add  rcx, rax
    imul eax, edi, WI_SIZE
    lea  rdx, [rel menu_winfo+WI_NAME]
    add  rdx, rax
    cmp  byte [rdx], 0
    cmovne rcx, rdx
    mov  LOC(40), rcx
    imul eax, edi, WL_INFO_LEN
    lea  rcx, [rel menu_wl_info]
    add  rcx, rax
    mov  LOC(48), rcx
    imul eax, edi, WL_DATE_LEN
    lea  rcx, [rel menu_wl_date]
    add  rcx, rax
    mov  LOC(56), rcx
    mov  eax, LOC(8)
    add  eax, 4
    mov  LOC(20), eax
    add  eax, 11
    mov  LOC(24), eax
    lea  eax, [r12+28]
    TEXTP eax, LOC(20), LOC(40), 0xFFFFFFFF
    ; last played, right aligned on the name line
    mov  rcx, LOC(56)
    cmp  byte [rcx], 0
    je   .nodate
    call ui_text_width
    mov  ecx, r12d
    add  ecx, LOC(28)
    sub  ecx, 6
    sub  ecx, eax
    TEXTP ecx, LOC(20), LOC(56), 0xFF909090
.nodate:
    imul eax, edi, WI_SIZE
    lea  rcx, [rel menu_winfo]
    mov  r9d, 0xFFA0A0A0
    mov  r8d, 0xFFD87070
    cmp  dword [rcx+rax+WI_OK], 0
    cmove r9d, r8d
    lea  eax, [r12+28]
    TEXTP eax, LOC(24), LOC(48), r9d
    mov  eax, edi
    shl  eax, 5
    lea  rcx, [rel menu_worlds]
    add  rcx, rax
    mov  rdx, LOC(40)
    mov  r8, LOC(48)
    mov  r9d, r12d
    mov  eax, LOC(28)
    mov  [rsp+32], rax
    mov  eax, LOC(24)
    mov  [rsp+40], rax
    call menu_folder_hint
    cmp  dword LOC(12), 0
    je   .nextentry
    test dword [rel g_mouse_pressed], MB_LEFT
    jz   .nextentry
    cmp  edi, [rel menu_sel]
    jne  .select
    movss xmm0, [rel ui_time]
    subss xmm0, [rel menu_last_click]
    ucomiss xmm0, [rel f_dbl]
    jae  .select
    mov  dword LOC(4), 1
.select:
    mov  [rel menu_sel], edi
    mov  eax, [rel ui_time]
    mov  [rel menu_last_click], eax
    mov  dword [rel menu_confirm], 0
.nextentry:
    inc  esi
    jmp  .entry
.entries_done:
    cmp  dword [rel menu_world_count], 0
    jne  .haveworlds
    mov  eax, r14d
    shr  eax, 1
    add  eax, r13d
    sub  eax, 4
    mov  LOC(0), eax
    CTEXT ebx, LOC(0), s_noworlds, 0xFFA0A0A0
.haveworlds:
    ; r15d = selection valid (enables Play/Delete)
    xor  r15d, r15d
    mov  eax, [rel menu_sel]
    test eax, eax
    js   .v
    cmp  eax, [rel menu_world_count]
    jge  .v
    mov  r15d, 1
.v:
    mov  esi, [rel g_ui_h]
    sub  esi, 52
    lea  edi, [rbx-154]
    BTN  edi, esi, 150, 20, s_play, r15d
    or   eax, LOC(4)
    mov  ecx, [rel menu_enter_key]
    and  ecx, r15d
    or   eax, ecx
    and  eax, r15d
    jz   .b2
    mov  eax, [rel menu_sel]
    shl  eax, 5
    lea  rcx, [rel menu_worlds]
    add  rcx, rax
    xor  edx, edx
    mov  r8d, GM_SURVIVAL
    xor  r9d, r9d
    call game_start_world
    jmp  .done
.b2:
    lea  edi, [rbx+4]
    BTN  edi, esi, 150, 20, s_create_new, 1
    test eax, eax
    jz   .b3
    mov  ecx, ST_CREATEWORLD
    call game_set_state
    jmp  .done
.b3:
    add  esi, 24
    lea  edi, [rbx-154]
    ; v1 temporary guard (menus #16)
    xor     r11d, r11d ; clear v1 slot 16
    ; v1 temporary guard (menus #18)
    xor     r11d, r11d ; clear v1 slot 18
    ; v1 temporary guard (menus #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (menus #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (menus #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (menus #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (menus #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (menus #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (menus #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (menus #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (menus #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (menus #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (menus #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (menus #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (menus #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (menus #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (menus #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (menus #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (menus #52)
    xor     r11d, r11d ; clear v1 slot 52
    ; v1 temporary guard (menus #54)
    xor     r11d, r11d ; clear v1 slot 54
