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
PROC hud_item_name, 16
    lea  rbx, [rel g_player]
    mov  esi, [rbx+PLAYER.selected]
    cmp  esi, 8
    jbe  .s
    xor  esi, esi
.s:
    movzx edi, byte [rbx+PLAYER.inv+rsi*4]
    cmp  dword [rel hud_name_init], 0
    jne  .inited
    mov  dword [rel hud_name_init], 1
    mov  [rel hud_last_sel], esi
    mov  [rel hud_last_id], edi
    mov  eax, [rel f_m100]
    mov  [rel hud_name_time], eax
.inited:
    cmp  esi, [rel hud_last_sel]
    jne  .changed
    cmp  edi, [rel hud_last_id]
    je   .show
.changed:
    mov  [rel hud_last_sel], esi
    mov  [rel hud_last_id], edi
    mov  eax, [rel ui_time]
    mov  [rel hud_name_time], eax
.show:
    test edi, edi
    jz   .done
    movss xmm0, [rel ui_time]
    subss xmm0, [rel hud_name_time]
    movss xmm1, [rel f_two]
    subss xmm1, xmm0
    xorps xmm2, xmm2
    ucomiss xmm1, xmm2
    jbe  .done
    addss xmm1, xmm1  ; last 0.5s
    minss xmm1, [rel f_one]
    mulss xmm1, [rel f_255]
    cvttss2si eax, xmm1
    cmp  eax, 8
    jl   .done
    shl  eax, 24
    or   eax, 0x00FFFFFF
    mov  r12d, eax
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
    call net_conn_name
    test rax, rax
    jz   .n
    mov  rsi, rax
    mov  rcx, rsi
    call ui_text_width
    mov  r8d, eax
    add  r8d, 4
    mov  ecx, r8d
    shr  ecx, 1
    neg  ecx
    add  ecx, r13d
    lea  edx, [r14-10]
    mov  r9d, 11
    mov  dword [rsp+32], 0x60000000
    call ui_rect
    mov  ecx, r13d
    lea  edx, [r14-8]
    mov  r8, rsi
    mov  r9d, 0xFFFFFFFF
    call ui_text_centered
.n:
    add  rbx, ENTITY_size
    inc  r12d
    cmp  r12d, MAX_ENTITIES
    jb   .l
.done:
ENDP

PROC hud_fps
    lea  rax, [rel g_settings]
    cmp  dword [rax+SETTINGS.show_fps], 0
    je   .done
    lea  rcx, [rel hud_buf]
    lea  rdx, [rel fmt_fpsonly]
    mov  r8d, [rel g_fps]
    call str_format
    mov  ecx, 2
    mov  edx, 2
    lea  r8, [rel hud_buf]
    mov  r9d, 0xFFE0E0E0
    mov  qword [rsp+32], 1
    mov  qword [rsp+40], 1
    call ui_text_ex
.done:
ENDP

; chat isn't drawn yet at this point so it stays out of the shot
PROC hud_screenshot
    cmp  dword [rel hud_screenshot_req], 0
    je   .done
    mov  dword [rel hud_screenshot_req], 0
    call ui_flush
    xor  ecx, ecx
    call screenshot_save
    test eax, eax
    jnz  .ok
    lea  rcx, [rel s_shot_bad]
    mov  edx, 0xFFFFFFFF
    call chat_add
    jmp  .done
.ok:
    lea  rcx, [rel hud_buf]
    lea  rdx, [rel s_shot_ok]
    lea  r8, [rel platform_last_shot]
    call str_format
    lea  rcx, [rel hud_buf]
    mov  edx, 0xFFFFFF55
    call chat_add
.done:
ENDP

; rcx fmt, edx side (0 left, 1 right), r8/r9/ARG5..ARG8 = up to 6 format args
PROC hud_dbg, 16
    mov  esi, edx
    mov  rax, ARG5
    mov  [rsp+32], rax
    mov  rax, ARG6
    mov  [rsp+40], rax
    mov  rax, ARG7
    mov  [rsp+48], rax
    mov  rax, ARG8
    mov  [rsp+56], rax
    mov  rdx, rcx
    lea  rcx, [rel hud_buf]
    call str_format
    lea  rcx, [rel hud_buf]
    call ui_text_dims
    mov  edi, eax
    mov  ebx, 2
    mov  r12d, [rel hud_dbg_yl]
    test esi, esi
    jz   .left
    mov  ebx, [rel g_ui_w]
    sub  ebx, edi
    sub  ebx, 2
    mov  r12d, [rel hud_dbg_yr]
; right line would overlap the left column (long fps line, narrow window)?
; push it down a row until it fits
.fit:
    lea  eax, [r12-2]
    xor  edx, edx
    mov  ecx, 9
    div  ecx
    cmp  eax, DBG_ROWS
    jae  .side
    lea  rcx, [rel hud_dbg_lx]
    mov  ecx, [rcx+rax*4]
    add  ecx, 6
    cmp  ecx, ebx
    jle  .side
    add  r12d, 9
    jmp  .fit
.left:
; 0 if the line is empty
    lea  eax, [r12-2]
    xor  edx, edx
    mov  ecx, 9
    div  ecx
    cmp  eax, DBG_ROWS
    jae  .side
    lea  ecx, [rbx+rdi]
    test edi, edi
    cmovz ecx, edi
    lea  rdx, [rel hud_dbg_lx]
    mov  [rdx+rax*4], ecx
.side:
    test edi, edi
    jz   .adv
    lea  r13d, [rbx-1]
    lea  r14d, [r12-1]
    lea  r15d, [rdi+1]
    RECT r13d, r14d, r15d, 9, 0x90505050
    mov  ecx, ebx
    mov  edx, r12d
    lea  r8, [rel hud_buf]
    mov  r9d, 0xFFE0E0E0
    call ui_text
.adv:
    add  r12d, 9
    test esi, esi
    jnz  .r
    mov  [rel hud_dbg_yl], r12d
    jmp  .done
.r:
    mov  [rel hud_dbg_yr], r12d
.done:
ENDP

; pass 0 for unused args
%macro DBG 6
    mov  r10, %6
    mov  [rsp+40], r10
    mov  r10, %5
    mov  [rsp+32], r10
    mov  r9, %4
    mov  r8, %3
    mov  edx, %2
    lea  rcx, [rel %1]
    call hud_dbg
%endmacro

PROCX hud_debug, 64
    mov  dword [rel hud_dbg_yl], 2
    mov  dword [rel hud_dbg_yr], 2
    lea  rdi, [rel hud_dbg_lx]
    xor  eax, eax
    mov  ecx, DBG_ROWS
    rep  stosd
; never changes, only ask once
    cmp  dword [rel hud_gl_cached], 0
    jne  .cached
    mov  dword [rel hud_gl_cached], 1
    mov  ecx, GL_VENDOR
    call glGetString
    lea  rdx, [rel s_unknown]
    test rax, rax
    cmovz rax, rdx
    mov  [rel hud_gl_vendor], rax
    mov  ecx, GL_RENDERER
    call glGetString
    lea  rdx, [rel s_unknown]
    test rax, rax
    cmovz rax, rdx
    mov  [rel hud_gl_renderer], rax
    mov  ecx, GL_VERSION
    call glGetString
    lea  rdx, [rel s_unknown]
    test rax, rax
    cmovz rax, rdx
    mov  [rel hud_gl_version], rax
    call cpu_count
    mov  [rel hud_cpus], eax
.cached:
    lea  rbx, [rel g_player]
; floor, not truncate, or negatives are off by one
    movss xmm0, [rbx+PLAYER.x]
    roundss xmm0, xmm0, 1
    cvttss2si r12d, xmm0
    movss xmm0, [rbx+PLAYER.y]
    roundss xmm0, xmm0, 1
    cvttss2si r13d, xmm0
    movss xmm0, [rbx+PLAYER.z]
    roundss xmm0, xmm0, 1
    cvttss2si r14d, xmm0

    DBG  s_title, 0, 0, 0, 0, 0
    lea  rax, [rel g_settings]
    lea  rcx, [rel s_on]
    lea  rdx, [rel s_off]
    cmp  dword [rax+SETTINGS.vsync], 0
    cmove rcx, rdx
    mov  r15, rcx
    mov  eax, [rel g_fps]
    mov  ecx, [rel g_stat_meshes_built]
    DBG  fmt_fps, 0, rax, rcx, r15, 0
    mov  eax, [rbx+PLAYER.x]
    mov  ecx, [rbx+PLAYER.y]
    mov  edx, [rbx+PLAYER.z]
    mov  r15, rdx
    DBG  fmt_xyz, 0, rax, rcx, r15, 0
    movsxd rax, r12d
    movsxd rcx, r13d
    movsxd r15, r14d
    DBG  fmt_block, 0, rax, rcx, r15, 0
    mov  eax, r12d
    sar  eax, 4
    movsxd rax, eax
    mov  [rsp+40], rax
    mov  eax, r14d
    sar  eax, 4
    movsxd rax, eax
    mov  [rsp+48], rax
    mov  eax, r14d
    and  eax, 15
    mov  [rsp+32], rax
    movsxd r9, r13d
    mov  eax, r12d
    and  eax, 15
    mov  r8, rax
    xor  edx, edx
    lea  rcx, [rel fmt_chunk]
    call hud_dbg
; quadrant = floor((yaw+45)/90) & 3
    movss xmm0, [rbx+PLAYER.yaw]
    movss xmm1, xmm0
    divss xmm1, [rel f_360]
    roundss xmm1, xmm1, 1
    mulss xmm1, [rel f_360]
    subss xmm0, xmm1
    movss xmm6, xmm0
    addss xmm0, [rel f_45]
    divss xmm0, [rel f_90]
    roundss xmm0, xmm0, 1
    cvttss2si eax, xmm0
    and  eax, 3
    lea  rcx, [rel facing_names]
    mov  r8, [rcx+rax*8]
    movd eax, xmm6
    mov  r9, rax
    mov  eax, [rbx+PLAYER.pitch]
    mov  r15, rax
    DBG  fmt_facing, 0, r8, r9, r15, 0
    mov  ecx, r12d
    mov  edx, r14d
    call world_get_biome
    lea  r8, [rel s_unknown]
    cmp  eax, BIOME_COUNT
    jae  .bn
    lea  rcx, [rel biome_name]
    mov  rcx, [rcx+rax*8]
    test rcx, rcx
    jz   .bn
    mov  r8, rcx
.bn:
    DBG  fmt_biome, 0, r8, 0, 0, 0
; sky<<4 | block
    mov  ecx, r12d
    mov  edx, r13d
    mov  r8d, r14d
    call world_get_light
    mov  ecx, eax
    shr  ecx, 4
    and  ecx, 15
    and  eax, 15
    mov  r15, rax
    mov  eax, [rel g_daylight]
    mov  rdx, rax
    DBG  fmt_light, 0, rcx, r15, rdx, 0
; tick 0 is 06:00
    mov  eax, [rel g_time_of_day]
    xor  edx, edx
    mov  ecx, 1000
    div  ecx
    add  eax, 6
    mov  r15d, edx
    xor  edx, edx
    mov  ecx, 24
    div  ecx
    mov  r9d, edx
    imul eax, r15d, 60
    xor  edx, edx
    mov  ecx, 1000
    div  ecx
    mov  r15d, eax
    mov  rax, [rel g_world_time]
    xor  edx, edx
    mov  ecx, DAY_LENGTH
    div  rcx
    inc  rax
    mov  r8, rax
    mov  eax, [rel g_time_of_day]
    mov  [rsp+40], rax
    mov  [rsp+32], r15
    xor  edx, edx
    lea  rcx, [rel fmt_time]
    call hud_dbg
    mov  eax, [rel g_chunk_count]
    mov  ecx, [rel g_stat_chunks_generated]
    DBG  fmt_chunks, 0, rax, rcx, 0, 0
    mov  eax, [rel g_stat_sections_drawn]
    mov  ecx, [rel g_stat_vertices]
    lea  rdx, [rel g_settings]
    mov  edx, [rdx+SETTINGS.render_dist]
    mov  r15, rdx
    DBG  fmt_render, 0, rax, rcx, r15, 0
    mov  eax, [rel g_entity_count]
    mov  ecx, [rel g_particle_count]
    DBG  fmt_ents, 0, rax, rcx, 0, 0
    mov  rax, [rel g_seed]
    DBG  fmt_seed, 0, rax, 0, 0, 0
    mov  eax, [rel g_weather]
    cmp  eax, 2
    jbe  .wok
    xor  eax, eax
.wok:
    lea  rcx, [rel weather_names]
    mov  r8, [rcx+rax*8]
    mov  eax, [rel g_rain]
    mov  r9, rax
    mov  eax, [rel g_thunder]
    mov  r15, rax
    DBG  fmt_weather, 0, r8, r9, r15, 0
    lea  r8, [rel s_survival]
    lea  rax, [rel s_creative]
    cmp  dword [rel g_gamemode], GM_CREATIVE
    cmove r8, rax
    lea  r9, [rel s_empty]
    lea  rax, [rel s_flying]
    cmp  dword [rbx+PLAYER.flying], 0
    cmovne r9, rax
    mov  eax, [rel g_view_mode]
    mov  r15, rax
    DBG  fmt_mode, 0, r8, r9, r15, 0
    mov  eax, [rbx+PLAYER.health]
    mov  ecx, [rbx+PLAYER.hunger]
    mov  edx, [rbx+PLAYER.saturation]
    mov  r15, rdx
    mov  edx, [rbx+PLAYER.air]
    mov  rsi, rdx
    DBG  fmt_stats, 0, rax, rcx, r15, rsi

    mov  eax, [rel hud_cpus]
    DBG  fmt_cpu, 1, rax, 0, 0, 0
    lea  rcx, [rel hud_memst]
    mov  dword [rcx], 64  ; dwLength
    call GlobalMemoryStatusEx
    lea  rcx, [rel hud_memst]
    mov  eax, [rcx+4]
    mov  rcx, [rcx+8]  ; ullTotalPhys, [rcx+4] is the load %
    shr  rcx, 20
    DBG  fmt_mem, 1, rax, rcx, 0, 0
    mov  eax, [rel g_screen_w]
    mov  ecx, [rel g_screen_h]
    mov  edx, [rel g_ui_scale]
    mov  r15, rdx
    DBG  fmt_disp, 1, rax, rcx, r15, 0
    mov  rax, [rel hud_gl_vendor]
    DBG  fmt_str, 1, rax, 0, 0, 0
    mov  rax, [rel hud_gl_renderer]
    DBG  fmt_str, 1, rax, 0, 0, 0
    mov  rax, [rel hud_gl_version]
    DBG  fmt_gl, 1, rax, 0, 0, 0
    lea  rax, [rel g_hit]
    cmp  dword [rax+RAYHIT.hit], 0
    je   .done
    DBG  s_empty, 1, 0, 0, 0, 0
    lea  rsi, [rel g_hit]
    movsxd rax, dword [rsi+RAYHIT.x]
    movsxd rcx, dword [rsi+RAYHIT.y]
    movsxd r15, dword [rsi+RAYHIT.z]
    DBG  fmt_tgt, 1, rax, rcx, r15, 0
    mov  eax, [rsi+RAYHIT.block]
    and  eax, 0xFF
    mov  r15, rax
    lea  rcx, [rel blk_name]
    mov  r8, [rcx+rax*8]
    lea  rcx, [rel s_unknown]
    test r8, r8
    cmovz r8, rcx
    DBG  fmt_tname, 1, r8, r15, 0, 0
    mov  eax, [rsi+RAYHIT.face]
    cmp  eax, 5
    jbe  .fok
    xor  eax, eax
.fok:
    lea  rcx, [rel face_names]
    mov  r8, [rcx+rax*8]
    mov  eax, [rsi+RAYHIT.dist]
    mov  r9, rax
    DBG  fmt_tface, 1, r8, r9, 0, 0
.done:
ENDPX
