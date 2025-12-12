%define IMPL_HUD
%include "common.inc"

extern ui_flush, ui_text_ex, ui_text_centered_ex, ui_rect_hgrad, ui_text_dims
extern ui_time
extern GlobalMemoryStatusEx
extern platform_last_shot

%define GL_ONE_MINUS_DST_COLOR  0x0307

global hud_screenshot_req
%define DBG_ROWS    32
global hud_dbg_yl  ; console.asm keeps chat below the F3 text
global hud_dbg_yr, hud_dbg_lx

; saves 7 lines of movs per rect
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
%macro RECTH 6
    mov  eax, %6
    mov  [rsp+40], eax
    mov  eax, %5
    mov  [rsp+32], eax
    mov  r9d, %4
    mov  r8d, %3
    mov  edx, %2
    mov  ecx, %1
    call ui_rect_hgrad
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

section .rdata
align 4
f_tenth:    dd 0.1
f_one:      dd 1.0
f_two:      dd 2.0
f_half:     dd 0.5
f_beat:     dd 5.5  ; rad/s
f_sixth:    dd 0.16666667
f_pulse:    dd 0.55
f_min_vig:  dd 0.02
f_vig_a:    dd 150.0
f_255:      dd 255.0
f_360:      dd 360.0
f_45:       dd 45.0
f_90:       dd 90.0
f_m100:     dd -100.0
f_tag_y:    dd 2.1  ; above the head
f_tag_d2:   dd 4096.0  ; 64 blocks
f_tag_w:    dd 0.05

s_title:    db "MineAssembly v1.0 (pure x86-64 asm)", 0
fmt_fps:    db "%d fps  |  %d meshes built  |  vsync %s", 0
fmt_xyz:    db "XYZ: %f / %f / %f", 0
fmt_block:  db "Block: %d %d %d", 0
fmt_chunk:  db "Chunk: %d %d %d in %d %d", 0
fmt_facing: db "Facing: %s (%.1f / %.1f)", 0
fmt_biome:  db "Biome: %s", 0
fmt_light:  db "Light: %d sky, %d block  (daylight %.2f)", 0
fmt_time:   db "Time: day %l, %02d:%02d  (tick %d)", 0
fmt_chunks: db "Chunks: %d loaded, %d generated", 0
fmt_render: db "Render: %d sections, %d vertices, distance %d", 0
fmt_ents:   db "Entities: %d   Particles: %d", 0
fmt_seed:   db "Seed: %l", 0
fmt_weather: db "Weather: %s  (rain %.2f, thunder %.2f)", 0
fmt_mode:   db "Mode: %s%s  |  camera %d", 0
fmt_stats:  db "Health %d  Food %d  Saturation %.1f  Air %d", 0
fmt_cpu:    db "x86-64 NASM  |  Win64  |  %d CPU threads", 0
fmt_mem:    db "System memory: %d%% of %u MB in use", 0
fmt_disp:   db "Display: %dx%d  (GUI scale %d)", 0
fmt_str:    db "%s", 0
fmt_gl:     db "OpenGL %s", 0
fmt_tgt:    db "Targeted block: %d, %d, %d", 0
fmt_tname:  db "%s  (id %d)", 0
fmt_tface:  db "Face: %s, %.2f blocks away", 0
fmt_fpsonly: db "%d fps", 0
s_empty:    db 0
s_on:       db "on", 0
s_off:      db "off", 0
s_unknown:  db "?", 0
s_survival: db "Survival", 0
s_creative: db "Creative", 0
s_flying:   db ", flying", 0
s_shot_ok:  db "Saved screenshot as %s", 0  ; same text as F2 in game.asm
s_shot_bad: db 0x0C, "c", "Could not save the screenshot.", 0
s_north:    db "north (towards -Z)", 0
s_east:     db "east (towards +X)", 0
s_south:    db "south (towards +Z)", 0
s_west:     db "west (towards -X)", 0
s_w_clear:  db "clear", 0
s_w_rain:   db "rain", 0
s_w_thunder: db "thunderstorm", 0
s_f_px:     db "east", 0
s_f_nx:     db "west", 0
s_f_py:     db "top", 0
s_f_ny:     db "bottom", 0
s_f_pz:     db "south", 0
s_f_nz:     db "north", 0
align 8
facing_names:   dq s_north, s_east, s_south, s_west
weather_names:  dq s_w_clear, s_w_rain, s_w_thunder
face_names:     dq s_f_px, s_f_nx, s_f_py, s_f_ny, s_f_pz, s_f_nz

section .bss
alignb 8
hud_gl_vendor:      resq 1
hud_gl_renderer:    resq 1
hud_gl_version:     resq 1
hud_memst:          resb 64
hud_buf:            resb 320
hud_screenshot_req: resd 1
hud_gl_cached:      resd 1
hud_cpus:           resd 1
hud_name_init:      resd 1
hud_last_sel:       resd 1
hud_last_id:        resd 1
hud_name_time:      resd 1
hud_dbg_yl:         resd 1
hud_dbg_yr:         resd 1
hud_dbg_lx:         resd DBG_ROWS

section .text

PROC hud_render
    cmp  dword [rel g_hide_hud], 0
    jne  .hidden
    call hud_vignette
    call hud_name_tags
    call hud_crosshair
    call hud_hotbar
    cmp  dword [rel g_gamemode], GM_SURVIVAL
    jne  .nosurv
    mov  ecx, 0xFFFFFFFF
    call hud_hearts
    call hud_hurt_flash
    call hud_food
    call hud_air
.nosurv:
    call hud_item_name
    cmp  dword [rel g_show_debug], 0
    je   .nodebug
    call hud_debug
    jmp  .shot
.nodebug:
    call hud_fps
.shot:
    call hud_screenshot
    call chat_render_feed
    jmp  .done
.hidden:  ; F1: only the damage flash
    call hud_vignette
    call hud_screenshot
.done:
ENDP

; -> -1/0/1, hashed on the tick so the shake changes per tick, not per frame
LEAF hud_jitter
    imul eax, ecx, 0x9E3779B1
    imul edx, edx, 0x7F4A7C15
    add  eax, edx
    mov  edx, [rel g_tick_count]
    imul edx, edx, 0x85EBCA6B
    xor  eax, edx
    mov  edx, eax
    shr  edx, 15
    xor  eax, edx
    imul eax, eax, 0x2C1B3C6D
    mov  edx, eax
    shr  edx, 12
    xor  eax, edx
    xor  edx, edx
    mov  ecx, 3
    div  ecx
    lea  eax, [rdx-1]
    ret

PROCX hud_vignette, 32
    lea  rbx, [rel g_player]
    mov  eax, [rbx+PLAYER.hurt_time]
    cvtsi2ss xmm6, eax
    mulss xmm6, [rel f_tenth]  ; 10 ticks of red after a hit
    minss xmm6, [rel f_one]
    xorps xmm0, xmm0
    maxss xmm6, xmm0
    cmp  dword [rel g_gamemode], GM_SURVIVAL
    jne  .comb
    mov  r12d, [rbx+PLAYER.health]
    test r12d, r12d
    jle  .comb
    cmp  r12d, 6
    jg   .comb
; heartbeat when hp <= 6
    movss xmm0, [rel ui_time]
    mulss xmm0, [rel f_beat]
    call math_sin
    mulss xmm0, [rel f_half]
    addss xmm0, [rel f_half]
    mov  eax, 7
    sub  eax, r12d
    cvtsi2ss xmm1, eax
    mulss xmm1, [rel f_sixth]
    mulss xmm0, xmm1
    mulss xmm0, [rel f_pulse]
    maxss xmm6, xmm0
.comb:
    ucomiss xmm6, [rel f_min_vig]
    jb   .done
    mulss xmm6, [rel f_vig_a]
    cvttss2si eax, xmm6
    shl  eax, 24
    or   eax, 0x00B01010
    mov  r15d, eax
    mov  r14d, 0x01B01010  ; alpha 1, 0 would be opaque
    mov  ebx, [rel g_ui_w]
    mov  esi, [rel g_ui_h]
    mov  eax, esi
    xor  edx, edx
    mov  ecx, 3
    div  ecx
    mov  edi, eax
    mov  r12d, ebx
    shr  r12d, 2
    RECTG 0, 0, ebx, edi, r15d, r14d
    mov  eax, esi
    sub  eax, edi
    mov  r13d, eax
    RECTG 0, r13d, ebx, edi, r14d, r15d
    RECTH 0, 0, r12d, esi, r15d, r14d
    mov  r13d, ebx
    sub  r13d, r12d
    RECTH r13d, 0, r12d, esi, r14d, r15d
.done:
ENDPX

PROC hud_crosshair
    cmp  dword [rel g_view_mode], 0
    jne  .done
    mov  eax, [rel g_state]
    cmp  eax, ST_PLAYING
    je   .draw
    cmp  eax, ST_CHAT
    jne  .done
.draw:
    call ui_flush
    mov  ecx, GL_ONE_MINUS_DST_COLOR
    mov  edx, GL_ZERO
    call glBlendFunc
    mov  ebx, [rel g_ui_w]
    shr  ebx, 1
    mov  esi, [rel g_ui_h]
    shr  esi, 1
    lea  r12d, [rbx-4]
    RECT r12d, esi, 9, 1, 0xFFFFFFFF
    lea  r12d, [rsi-4]
    RECT ebx, r12d, 1, 4, 0xFFFFFFFF
    lea  r12d, [rsi+1]
    RECT ebx, r12d, 1, 4, 0xFFFFFFFF
    call ui_flush
    mov  ecx, GL_SRC_ALPHA
    mov  edx, GL_ONE_MINUS_SRC_ALPHA
    call glBlendFunc
.done:
ENDP

PROC hud_hotbar
    mov  ebx, [rel g_ui_w]
    shr  ebx, 1
    sub  ebx, 91
    mov  esi, [rel g_ui_h]
    sub  esi, 22
    RECT ebx, esi, 182, 22, 0xB0101014
    lea  r13d, [rsi+1]
    xor  edi, edi
.slots:
    imul r12d, edi, 20
    lea  r12d, [rbx+r12+1]
    TILE r12d, r13d, 20, T_SLOT, 0xFFFFFFFF
    inc  edi
    cmp  edi, HOTBAR_SLOTS
    jb   .slots
    lea  rax, [rel g_player]
    mov  eax, [rax+PLAYER.selected]
    cmp  eax, 8
    jbe  .selok
    xor  eax, eax
.selok:
    imul r12d, eax, 20
    lea  r12d, [rbx+r12-1]
    lea  r13d, [rsi-1]
    TILE r12d, r13d, 24, T_SLOT_SELECTED, 0xFFFFFFFF
    xor  edi, edi
.items:
    imul ecx, edi, 20
    lea  ecx, [rbx+rcx+3]
    lea  edx, [rsi+3]
    lea  r8, [rel g_player]
    lea  r8, [r8+PLAYER.inv+rdi*4]
    call ui_item_stack
    inc  edi
    cmp  edi, HOTBAR_SLOTS
    jb   .items
ENDP

; tint param is just so hud_hurt_flash can redraw these white
PROC hud_hearts, 16
    mov  r15d, ecx
    mov  ebx, [rel g_ui_w]
    shr  ebx, 1
    sub  ebx, 91
    mov  esi, [rel g_ui_h]
    sub  esi, 32
    lea  rax, [rel g_player]
    mov  r12d, [rax+PLAYER.health]
    test r12d, r12d
    jns  .hp
    xor  r12d, r12d
.hp:
    xor  edi, edi
.lp:
    lea  r13d, [rbx+rdi*8]
    mov  r14d, esi
    cmp  r12d, 4
    jg   .still
    mov  ecx, edi
    xor  edx, edx
    call hud_jitter
    add  r14d, eax
.still:
    TILE r13d, r14d, 9, T_HEART_EMPTY, r15d
    lea  eax, [rdi*2+2]
    cmp  r12d, eax
    jge  .full
    dec  eax
    cmp  r12d, eax
    jne  .next
    TILE r13d, r14d, 9, T_HEART_HALF, r15d
    jmp  .next
.full:
    TILE r13d, r14d, 9, T_HEART_FULL, r15d
.next:
    inc  edi
    cmp  edi, 10
    jb   .lp
ENDP

; white blink after a hit. lazy: draw the hearts again additive on top
PROC hud_hurt_flash
    lea  rax, [rel g_player]
    mov  eax, [rax+PLAYER.hurt_time]
    test eax, eax
    jle  .done
    test eax, 2
    jz   .done
    call ui_flush
    mov  ecx, GL_SRC_ALPHA
    mov  edx, GL_ONE
    call glBlendFunc
    mov  ecx, 0xA0FFFFFF
    call hud_hearts
    call ui_flush
    mov  ecx, GL_SRC_ALPHA
    mov  edx, GL_ONE_MINUS_SRC_ALPHA
    call glBlendFunc
.done:
ENDP

PROC hud_food, 16
    mov  ebx, [rel g_ui_w]
    shr  ebx, 1
    add  ebx, 91-9
    mov  esi, [rel g_ui_h]
    sub  esi, 32
    lea  rax, [rel g_player]
    mov  r12d, [rax+PLAYER.hunger]
    xor  r15d, r15d
    xorps xmm0, xmm0
    ucomiss xmm0, [rax+PLAYER.saturation]
    jb   .nosat
    mov  r15d, 1  ; no saturation -> shaky
.nosat:
    xor  edi, edi
.lp:
    mov  r13d, edi
    shl  r13d, 3
    neg  r13d
    add  r13d, ebx
    mov  r14d, esi
    test r15d, r15d
    jz   .still
    mov  ecx, edi
    mov  edx, 1
    call hud_jitter
    add  r14d, eax
.still:
    TILE r13d, r14d, 9, T_FOOD_EMPTY, 0xFFFFFFFF
    lea  eax, [rdi*2+2]
    cmp  r12d, eax
    jge  .full
    dec  eax
    cmp  r12d, eax
    jne  .next
    TILE r13d, r14d, 9, T_FOOD_HALF, 0xFFFFFFFF
    jmp  .next
.full:
    TILE r13d, r14d, 9, T_FOOD_FULL, 0xFFFFFFFF
.next:
    inc  edi
    cmp  edi, 10
    jb   .lp
ENDP

; full = ceil((air-2)*10/300), total = ceil(air*10/300), extra one is the popping bubble
PROC hud_air, 16
    lea  rax, [rel g_player]
    mov  r12d, [rax+PLAYER.air]
    cmp  dword [rax+PLAYER.eye_in_water], 0
    jne  .show
    cmp  r12d, 300
    jge  .done
.show:
    test r12d, r12d
    jns  .a0
    xor  r12d, r12d
.a0:
    cmp  r12d, 300
    jle  .a1
    mov  r12d, 300
.a1:
    lea  eax, [r12-2]
    xor  r13d, r13d
    test eax, eax
    jle  .f0
    imul eax, eax, 10
    add  eax, 299
    xor  edx, edx
    mov  ecx, 300
    div  ecx
    mov  r13d, eax
.f0:
    imul eax, r12d, 10
    add  eax, 299
    xor  edx, edx
    mov  ecx, 300
    div  ecx
    mov  r14d, eax
    mov  ebx, [rel g_ui_w]
    shr  ebx, 1
    add  ebx, 91-9
    mov  esi, [rel g_ui_h]
    sub  esi, 42
    xor  edi, edi
.lp:
    cmp  edi, r14d
    jge  .done
    mov  r15d, edi
    shl  r15d, 3
    neg  r15d
    add  r15d, ebx
    mov  eax, T_BUBBLE
    mov  ecx, T_BUBBLE_POP
    cmp  edi, r13d
    cmovge eax, ecx
    mov  LOC(0), eax
    TILE r15d, esi, 9, LOC(0), 0xFFFFFFFF
    inc  edi
    jmp  .lp
.done:
ENDP

; held item name, fades out 2s after the selection changes
PROC hud_item_name, 16 ; v1: hud scratch #2
    ; TODO: verify 16-byte rsp alignment before inner call (hud:2)
    lea  rbx, [rel g_player] ; v1: hud scratch #3
    mov  esi, [rbx+PLAYER.selected] ; v1: hud scratch #4
    ; note: rcx = state ptr, rdx = index, r8d = flags (hud:4)
    cmp  esi, 8 ; v1: hud scratch #5
    jbe  .s ; v1: hud scratch #6
    ; TODO: clamp index before table lookup on malformed input (hud:6)
    xor  esi, esi ; v1: hud scratch #7
.s: ; v1: hud scratch #8
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (hud:8)
    movzx edi, byte [rbx+PLAYER.inv+rsi*4] ; v1: hud scratch #9
    cmp  dword [rel hud_name_init], 0 ; v1: hud scratch #10
    ; FIXME: negative world x/z needs sar 4, not shr 4 (hud:10)
    jne  .inited ; v1: hud scratch #11
    mov  dword [rel hud_name_init], 1 ; v1: hud scratch #12
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (hud:12)
    mov  [rel hud_last_sel], esi ; v1: hud scratch #13
    mov  [rel hud_last_id], edi ; v1: hud scratch #14
    ; temp: spill r12/r13 across helper call until reg alloc pass (hud:14)
    mov  eax, [rel f_m100] ; v1: hud scratch #15
    mov  [rel hud_name_time], eax ; v1: hud scratch #16
    ; TODO: hoist invariant pointer load out of .loop (hud:16)
.inited: ; v1: hud scratch #17
    cmp  esi, [rel hud_last_sel] ; v1: hud scratch #18
    ; TODO: verify 16-byte rsp alignment before inner call (hud:18)
    jne  .changed ; v1: hud scratch #19
    cmp  edi, [rel hud_last_id] ; v1: hud scratch #20
    ; note: rcx = state ptr, rdx = index, r8d = flags (hud:20)
    je   .show ; v1: hud scratch #21
.changed: ; v1: hud scratch #22
    ; TODO: clamp index before table lookup on malformed input (hud:22)
    mov  [rel hud_last_sel], esi ; v1: hud scratch #23
    mov  [rel hud_last_id], edi ; v1: hud scratch #24
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (hud:24)
    mov  eax, [rel ui_time] ; v1: hud scratch #25
    mov  [rel hud_name_time], eax ; v1: hud scratch #26
    ; FIXME: negative world x/z needs sar 4, not shr 4 (hud:26)
.show: ; v1: hud scratch #27
    test edi, edi ; v1: hud scratch #28
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (hud:28)
    jz   .done ; v1: hud scratch #29
    movss xmm0, [rel ui_time] ; v1: hud scratch #30
    ; temp: spill r12/r13 across helper call until reg alloc pass (hud:30)
    subss xmm0, [rel hud_name_time] ; v1: hud scratch #31
    movss xmm1, [rel f_two] ; v1: hud scratch #32
    ; TODO: hoist invariant pointer load out of .loop (hud:32)
    subss xmm1, xmm0 ; v1: hud scratch #33
    xorps xmm2, xmm2 ; v1: hud scratch #34
    ; TODO: verify 16-byte rsp alignment before inner call (hud:34)
    ucomiss xmm1, xmm2 ; v1: hud scratch #35
    jbe  .done ; v1: hud scratch #36
    ; note: rcx = state ptr, rdx = index, r8d = flags (hud:36)
    addss xmm1, xmm1 ; v1: hud scratch #37
    minss xmm1, [rel f_one] ; v1: hud scratch #38
    ; TODO: clamp index before table lookup on malformed input (hud:38)
    mulss xmm1, [rel f_255] ; v1: hud scratch #39
    cvttss2si eax, xmm1 ; v1: hud scratch #40
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (hud:40)
    cmp  eax, 8 ; v1: hud scratch #41
    jl   .done ; v1: hud scratch #42
    ; FIXME: negative world x/z needs sar 4, not shr 4 (hud:42)
    shl  eax, 24 ; v1: hud scratch #43
    or   eax, 0x00FFFFFF ; v1: hud scratch #44
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (hud:44)
    mov  r12d, eax ; v1: hud scratch #45
    lea  rax, [rel item_name]
    mov  r8, [rax+rdi*8]
    test r8, r8
    jz   .done
    mov  edx, [rel g_ui_h]
    sub  edx, 38
    cmp  dword [rel g_gamemode], GM_SURVIVAL
    jne  .y
    sub  edx, 12
    cmp  dword [rbx+PLAYER.eye_in_water], 0
    je   .y
    sub  edx, 10
.y:
    mov  ecx, [rel g_ui_w]
    shr  ecx, 1
    mov  r9d, r12d
    mov  qword [rsp+32], 1
    call ui_text_centered_ex
.done:
ENDP

; java players' names over their heads. projected by hand and drawn in the
; hud pass, so like vanilla they show through walls
PROC hud_name_tags, 32
    cmp  dword [rel g_net_hosting], 0
    je   .done
    lea  rbx, [rel g_entities]
    xor  r12d, r12d
.l:
    cmp  byte [rbx+ENTITY.type], ENT_REMOTE
    jne  .n
    lea  rax, [rel g_cam_pos]
    movss xmm4, [rel g_partial_tick]
    movss xmm0, [rbx+ENTITY.x]
    subss xmm0, [rbx+ENTITY.prev_x]
    mulss xmm0, xmm4
    addss xmm0, [rbx+ENTITY.prev_x]
    subss xmm0, [rax]
    movss xmm1, [rbx+ENTITY.y]
    subss xmm1, [rbx+ENTITY.prev_y]
    mulss xmm1, xmm4
    addss xmm1, [rbx+ENTITY.prev_y]
    addss xmm1, [rel f_tag_y]
    subss xmm1, [rax+4]
    movss xmm2, [rbx+ENTITY.z]
    subss xmm2, [rbx+ENTITY.prev_z]
    mulss xmm2, xmm4
    addss xmm2, [rbx+ENTITY.prev_z]
    subss xmm2, [rax+8]
    movaps xmm3, xmm0
    mulss xmm3, xmm0
    movaps xmm4, xmm1
    mulss xmm4, xmm1
    addss xmm3, xmm4
    movaps xmm4, xmm2
    mulss xmm4, xmm2
    addss xmm3, xmm4
    comiss xmm3, [rel f_tag_d2]
    ja   .n
    ; column major: clip = m * (x y z 1)
    lea  rax, [rel g_mat_viewproj]
    movss xmm3, [rax+12]
    mulss xmm3, xmm0
    movss xmm4, [rax+28]
    mulss xmm4, xmm1
    addss xmm3, xmm4
    movss xmm4, [rax+44]
    mulss xmm4, xmm2
    addss xmm3, xmm4
    addss xmm3, [rax+60]                ; w
    comiss xmm3, [rel f_tag_w]
    jb   .n                             ; behind us
    movss xmm4, [rax]
    mulss xmm4, xmm0
    movss xmm5, [rax+16]
    mulss xmm5, xmm1
    addss xmm4, xmm5
    movss xmm5, [rax+32]
    mulss xmm5, xmm2
    addss xmm4, xmm5
    addss xmm4, [rax+48]
    divss xmm4, xmm3
    mulss xmm4, [rel f_half]
    addss xmm4, [rel f_half]
    cvtsi2ss xmm5, dword [rel g_ui_w]
    mulss xmm4, xmm5
    cvttss2si r13d, xmm4                ; screen x
    movss xmm4, [rax+4]
    mulss xmm4, xmm0
    movss xmm5, [rax+20]
    mulss xmm5, xmm1
    addss xmm4, xmm5
    movss xmm5, [rax+36]
    mulss xmm5, xmm2
    addss xmm4, xmm5
    addss xmm4, [rax+52]
    divss xmm4, xmm3
    mulss xmm4, [rel f_half]
    movss xmm5, [rel f_half]
    subss xmm5, xmm4
    cvtsi2ss xmm4, dword [rel g_ui_h]
    mulss xmm5, xmm4
    cvttss2si r14d, xmm5                ; screen y
    movzx ecx, byte [rbx+ENTITY.variant]
    ; v1 temporary guard (hud #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (hud #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (hud #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (hud #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (hud #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (hud #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (hud #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (hud #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (hud #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (hud #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (hud #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (hud #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (hud #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (hud #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (hud #50)
    xor     r11d, r11d ; clear v1 slot 50
