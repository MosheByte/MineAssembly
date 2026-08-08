; renders every hud/menus/console screen offscreen (hidden window, 1280x720 FBO) and
; dumps ui_*.bmp plus a couple of x2 crops into the test's build folder. fails on GL
; errors or a screen where < 0.5 % of the pixels moved off the clear colour.
; @link src/ui.asm src/hud.asm src/menus.asm src/console.asm src/util.asm
; @link src/items.asm src/blocks.asm src/gl.asm src/font.asm src/math.asm
; @link src/noise.asm src/texgen.asm tests/ui/ui_stubs.asm
; @gpu
; @preview
; @timeout 120
%include "common.inc"
%include "testlib.inc"

extern menus_render, hud_render, console_render, console_open, console_execute
extern chat_add, con_insert, menu_worlds, menu_world_count, menu_sel
extern font_init, texgen_init, ui_init

%define SW          1280
%define SH          720

%define GL_FRAMEBUFFER          0x8D40
%define GL_RENDERBUFFER         0x8D41
%define GL_RGBA8                0x8058
%define GL_DEPTH_COMPONENT24    0x81A6
%define GL_COLOR_ATTACHMENT0    0x8CE0
%define GL_DEPTH_ATTACHMENT     0x8D00

; double g_time_total, then the clear colour (4 floats)
%macro FPARAM 5
    dq %1
    dd %2, %3, %4, %5
%endmacro

%macro STRP 2
    section .rdata
    %%s: db %2, 0
    section .text
    lea  %1, [rel %%s]
%endmacro

%macro FRAME 3
    STRP rcx, %1
    lea  rdx, [rel %2]
    lea  r8,  [rel %3]
    call frame
%endmacro

%macro SETD 2
    mov  dword [rel %1], %2
%endmacro

section .rdata
align 8
fp_menu:    FPARAM 3.3, 0.35, 0.55, 0.85, 1.0
fp_hud:     FPARAM 4.0, 0.45, 0.65, 0.95, 1.0
fp_chat:    FPARAM 5.0, 0.45, 0.65, 0.95, 1.0
fp_dead:    FPARAM 9.0, 0.45, 0.65, 0.95, 1.0
fp_icons:   FPARAM 3.3, 0.2, 0.2, 0.25, 1.0
ident:      dd 1.0,0,0,0, 0,1.0,0,0, 0,0,1.0,0, 0,0,0,1.0
wnd_class:  db "STATIC", 0
wnd_title:  db "ui", 0
n_genfb:    db "glGenFramebuffers", 0
n_bindfb:   db "glBindFramebuffer", 0
n_genrb:    db "glGenRenderbuffers", 0
n_bindrb:   db "glBindRenderbuffer", 0
n_rbstore:  db "glRenderbufferStorage", 0
n_fbrb:     db "glFramebufferRenderbuffer", 0
; save_list_worlds is a stub, so the world list gets these
w_names:    db "Survival Island", 0, "Creative Build", 0, "Seed 1337", 0, "My Castle", 0, 0
; (id, count) pairs. slot 5 (142) gets durability 120 later
inv_items:  db 1,64, 2,12, 9,5, 10,30, 34,16, 142,1, 133,3, 29,1, 0,0
s_welcome:  db 12, "eWelcome to MineAssembly!", 12, "f Type ", 12, "e/help", 12, "f for commands.", 0
s_brag:     db "<Player> this whole game is written in x86-64 assembly, every single byte of it", 0
s_tip:      db 12, "bDiamond Pickaxe", 10, 12, "7Durability 1441 / 1561", 0
s_bmp_pfx:  db "ui_", 0
s_bmp_ext:  db ".bmp", 0

section .bss
alignb 16
pv_pfd:     resb 40
pv_hwnd:    resq 1
pv_hdc:     resq 1
pv_hrc:     resq 1
p_genfb:    resq 1
p_bindfb:   resq 1
p_genrb:    resq 1
p_bindrb:   resq 1
p_rbstore:  resq 1
p_fbrb:     resq 1
fb_ids:     resd 4
pv_raw:     resq 1                      ; bottom row first
pv_img:     resq 1
pv_crop:    resq 1
hud_copy:   resq 1
path_buf:   resb 128

section .text

PROC gl_open
    xor  ecx, ecx
    lea  rdx, [rel wnd_class]
    lea  r8,  [rel wnd_title]
    mov  r9d, WS_POPUP                  ; never shown
    mov  qword [rsp+32], 0
    mov  qword [rsp+40], 0
    mov  qword [rsp+48], 64
    mov  qword [rsp+56], 64
    mov  qword [rsp+64], 0
    mov  qword [rsp+72], 0
    mov  qword [rsp+80], 0
    mov  qword [rsp+88], 0
    call CreateWindowExA
    test rax, rax
    jz   .fail
    mov  [rel pv_hwnd], rax
    mov  rcx, rax
    call GetDC
    mov  [rel pv_hdc], rax
    lea  rdi, [rel pv_pfd]
    xor  eax, eax
    mov  ecx, 40
    rep  stosb
    lea  rdi, [rel pv_pfd]
    mov  word [rdi+0], 40
    mov  word [rdi+2], 1
    mov  dword [rdi+4], PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER
    mov  byte [rdi+8], PFD_TYPE_RGBA
    mov  byte [rdi+9], 32
    mov  byte [rdi+23], 24
    mov  rcx, [rel pv_hdc]
    mov  rdx, rdi
    call ChoosePixelFormat
    test eax, eax
    jz   .destroy
    mov  rcx, [rel pv_hdc]
    mov  edx, eax
    lea  r8, [rel pv_pfd]
    call SetPixelFormat
    test eax, eax
    jz   .destroy
    mov  rcx, [rel pv_hdc]
    call wglCreateContext
    test rax, rax
    jz   .destroy
    mov  [rel pv_hrc], rax
    mov  rcx, [rel pv_hdc]
    mov  rdx, rax
    call wglMakeCurrent
    test eax, eax
    jz   .delete
    mov  eax, 1
    jmp  .done
.delete:
    mov  rcx, [rel pv_hrc]
    call wglDeleteContext
.destroy:
    mov  rcx, [rel pv_hwnd]
    mov  rdx, [rel pv_hdc]
    call ReleaseDC
    mov  rcx, [rel pv_hwnd]
    call DestroyWindow
.fail:
    xor  eax, eax
.done:
ENDP

PROC gl_close
    xor  ecx, ecx
    xor  edx, edx
    call wglMakeCurrent
    mov  rcx, [rel pv_hrc]
    call wglDeleteContext
    mov  rcx, [rel pv_hwnd]
    mov  rdx, [rel pv_hdc]
    call ReleaseDC
    mov  rcx, [rel pv_hwnd]
    call DestroyWindow
ENDP

PROC getproc
    mov  rbx, rdx
    call wglGetProcAddress
    mov  [rbx], rax
    xor  eax, eax
    cmp  qword [rbx], 0
    setne al
ENDP

; SWxSH RGBA8 + DEPTH24, left bound
PROC fbo_create
    mov  esi, 1
    %macro GP 2
        lea  rcx, [rel %1]
        lea  rdx, [rel %2]
        call getproc
        and  esi, eax
    %endmacro
    GP n_genfb, p_genfb
    GP n_bindfb, p_bindfb
    GP n_genrb, p_genrb
    GP n_bindrb, p_bindrb
    GP n_rbstore, p_rbstore
    GP n_fbrb, p_fbrb
    test esi, esi
    jz   .done
    mov  ecx, 1
    lea  rdx, [rel fb_ids]
    call [rel p_genfb]
    mov  ecx, GL_FRAMEBUFFER
    mov  edx, [rel fb_ids]
    call [rel p_bindfb]
    mov  ecx, 1
    lea  rdx, [rel fb_ids+4]
    call [rel p_genrb]
    mov  ecx, GL_RENDERBUFFER
    mov  edx, [rel fb_ids+4]
    call [rel p_bindrb]
    mov  ecx, GL_RENDERBUFFER
    mov  edx, GL_RGBA8
    mov  r8d, SW
    mov  r9d, SH
    call [rel p_rbstore]
    mov  ecx, GL_FRAMEBUFFER
    mov  edx, GL_COLOR_ATTACHMENT0
    mov  r8d, GL_RENDERBUFFER
    mov  r9d, [rel fb_ids+4]
    call [rel p_fbrb]
    mov  ecx, 1
    lea  rdx, [rel fb_ids+8]
    call [rel p_genrb]
    mov  ecx, GL_RENDERBUFFER
    mov  edx, [rel fb_ids+8]
    call [rel p_bindrb]
    mov  ecx, GL_RENDERBUFFER
    mov  edx, GL_DEPTH_COMPONENT24
    mov  r8d, SW
    mov  r9d, SH
    call [rel p_rbstore]
    mov  ecx, GL_FRAMEBUFFER
    mov  edx, GL_DEPTH_ATTACHMENT
    mov  r8d, GL_RENDERBUFFER
    mov  r9d, [rel fb_ids+8]
    call [rel p_fbrb]
    call glGetError
    xor  esi, esi
    test eax, eax
    setz sil
.done:
    mov  eax, esi
ENDP

PROC frame, 32
    mov  r12, rcx
    mov  r13, rdx
    mov  r14, r8
    mov  rax, [r14]
    mov  [rel g_time_total], rax
    movss xmm0, [r14+8]
    movss xmm1, [r14+12]
    movss xmm2, [r14+16]
    movss xmm3, [r14+20]
    call glClearColor
    mov  ecx, 0x4100                    ; COLOR | DEPTH
    call glClear
    call ui_begin
    call r13
    call ui_end
    call glGetError
    mov  r15d, eax
    xor  ecx, ecx
    xor  edx, edx
    mov  r8d, SW
    mov  r9d, SH
    mov  qword [rsp+32], GL_RGBA
    mov  qword [rsp+40], GL_UNSIGNED_BYTE
    mov  rax, [rel pv_raw]
    mov  [rsp+48], rax
    call glReadPixels
    ; flip into pv_img. alpha is never displayed so force it opaque
    mov  rsi, [rel pv_raw]
    mov  rdi, [rel pv_img]
    xor  ebx, ebx
.row:
    mov  eax, SH-1
    sub  eax, ebx
    imul eax, eax, SW*4
    lea  r8, [rsi+rax]
    mov  eax, ebx
    imul eax, eax, SW*4
    lea  r9, [rdi+rax]
    xor  ecx, ecx
.px:
    mov  eax, [r8+rcx*4]
    or   eax, 0xFF000000
    mov  [r9+rcx*4], eax
    inc  ecx
    cmp  ecx, SW
    jl   .px
    inc  ebx
    cmp  ebx, SH
    jl   .row
    lea  rcx, [rel path_buf]
    lea  rdx, [rel s_bmp_pfx]
    call pv_strcpy
    mov  rcx, rax
    mov  rdx, r12
    call pv_strcpy
    mov  rcx, rax
    lea  rdx, [rel s_bmp_ext]
    call pv_strcpy
    lea  rcx, [rel path_buf]
    mov  rdx, [rel pv_img]
    mov  r8d, SW
    mov  r9d, SH
    call t_write_bmp
    mov  ebx, eax
    PRINT "  "
    lea  rcx, [rel path_buf]
    call t_print
    PRINT "  glGetError="
    mov  ecx, r15d
    call t_print_hex
    call t_newline
    CHECK_TRUE ebx, "bmp written"
    CHECK_EQ32 r15d, 0, "no GL error during the frame"
    mov  rcx, [rel pv_img]
    mov  rdx, r14
    call count_changed
    mov  ebx, eax
    xor  eax, eax
    cmp  ebx, SW*SH/200
    setae al
    CHECK_TRUE eax, "the screen drew something"
ENDP

; pixels with any channel more than 8 off the clear colour
PROC count_changed, 16
    xor  ebx, ebx
.cc:
    movss xmm0, [rdx+8+rbx*4]
    mov  eax, __?float32?__(255.0)
    movd xmm1, eax
    mulss xmm0, xmm1
    cvtss2si eax, xmm0
    mov  LOC(rbx), al
    inc  ebx
    cmp  ebx, 3
    jl   .cc
    xor  r12d, r12d
    xor  esi, esi
.lp:
    xor  ebx, ebx
    xor  r8d, r8d
    lea  r9, [rcx+rsi*4]
.ch:
    movzx eax, byte [r9+rbx]
    movzx edx, byte LOC(rbx)
    sub  eax, edx
    mov  edx, eax
    neg  edx
    cmovs edx, eax                      ; |diff|
    cmp  edx, 8
    jle  .same
    mov  r8d, 1
.same:
    inc  ebx
    cmp  ebx, 3
    jl   .ch
    add  r12d, r8d
    inc  esi
    cmp  esi, SW*SH
    jl   .lp
    mov  eax, r12d
ENDP

; -> rax at the NUL, so calls chain
LEAF pv_strcpy
.l: mov  al, [rdx]
    mov  [rcx], al
    test al, al
    jz   .e
    inc  rcx
    inc  rdx
    jmp  .l
.e: mov  rax, rcx
    ret

; crop_zoom(rcx src rgba SWxSH top first, edx x0, r8d y0, r9d x1, ARG5 y1,
;           ARG6 scale, ARG7 path): cut [x0,x1) x [y0,y1), blow it up by pixel replication
PROC crop_zoom
    mov  rsi, rcx
    mov  r12d, edx
    mov  r13d, r8d
    mov  r14d, r9d
    sub  r14d, r12d
    mov  r15d, ARG5
    sub  r15d, r13d
    mov  ebx, ARG6
    mov  rdi, [rel pv_crop]
    xor  r8d, r8d
.oy:
    mov  eax, r14d
    imul eax, ebx
    mov  r10d, eax
    mov  eax, r15d
    imul eax, ebx
    cmp  r8d, eax
    jge  .save
    mov  eax, r8d
    xor  edx, edx
    div  ebx
    add  eax, r13d
    imul eax, eax, SW
    add  eax, r12d
    lea  r11, [rsi+rax*4]               ; src row at x0
    xor  r9d, r9d
.ox:
    mov  eax, r9d
    xor  edx, edx
    div  ebx
    mov  eax, [r11+rax*4]
    mov  [rdi], eax
    add  rdi, 4
    inc  r9d
    cmp  r9d, r10d
    jl   .ox
    inc  r8d
    jmp  .oy
.save:
    mov  rcx, ARG7
    mov  rdx, [rel pv_crop]
    mov  r8d, r14d
    imul r8d, ebx
    mov  r9d, r15d
    imul r9d, ebx
    call t_write_bmp
ENDP

PROC draw_chat
    call hud_render
    call console_render
ENDP

PROC draw_pause
    call hud_render
    call menus_render
ENDP

PROC draw_icons
    mov  ecx, 10
    mov  edx, 10
    mov  r8d, 300
    mov  r9d, 200
    call ui_frame
    mov  r12d, 18
    mov  r13d, 18
    mov  ebx, 1                         ; ids 1..71, 80..91, 128..159
.lp:
    mov  ecx, r12d
    mov  edx, r13d
    mov  r8d, ebx
    call ui_item_icon
    add  r12d, 18
    cmp  r12d, 290
    jle  .next
    mov  r12d, 18
    add  r13d, 18
.next:
    inc  ebx
    cmp  ebx, 72
    jne  .n2
    mov  ebx, 80
.n2:
    cmp  ebx, 92
    jne  .n3
    mov  ebx, 128
.n3:
    cmp  ebx, 160
    jl   .lp
    lea  rcx, [rel s_tip]
    call ui_tooltip
ENDP

PROC test_main, 32
    TEST "ui preview setup"
    call gl_open
    mov  ebx, eax
    CHECK_TRUE ebx, "hidden window + GL context"
    test ebx, ebx
    jz   .done
    call fbo_create
    mov  ebx, eax
    CHECK_TRUE ebx, "framebuffer object"
    test ebx, ebx
    jz   .close
    mov  ecx, SW*SH*4
    call t_alloc
    mov  [rel pv_raw], rax
    mov  ecx, SW*SH*4
    call t_alloc
    mov  [rel pv_img], rax
    mov  ecx, SW*SH*4
    call t_alloc
    mov  [rel hud_copy], rax
    mov  ecx, SW*SH*4*4
    call t_alloc
    mov  [rel pv_crop], rax

    call gl_load_functions
    mov  ebx, eax
    PRINT "gl_load_functions: "
    mov  ecx, ebx
    call t_print_int
    call t_newline
    CHECK_TRUE ebx, "gl_load_functions"
    call font_init
    call texgen_init
    PRINT "atlas tex "
    mov  ecx, [rel g_tex_atlas]
    call t_print_int
    PRINT " font tex "
    mov  ecx, [rel g_tex_font]
    call t_print_int
    call t_newline
    call ui_init
    SETD g_screen_w, SW
    SETD g_screen_h, SH
    SETD g_mouse_x, 640
    SETD g_mouse_y, 330
    ; identity matrices so ui_end has something sane to restore
    lea  rsi, [rel ident]
    lea  rdi, [rel g_mat_proj]
    mov  ecx, 16
    rep  movsd
    lea  rsi, [rel ident]
    lea  rdi, [rel g_mat_view]
    mov  ecx, 16
    rep  movsd

    TEST "menu screens"
    SETD g_world_active, 0
    SETD g_state, ST_TITLE
    FRAME "title", menus_render, fp_menu
    SETD g_state, ST_WORLDSELECT
    FRAME "worldselect", menus_render, fp_menu
    lea  rsi, [rel w_names]
    lea  rbx, [rel menu_worlds]
    xor  r12d, r12d
.wn:
    cmp  byte [rsi], 0
    je   .wn_done
    mov  rcx, rbx
    mov  rdx, rsi
    call pv_strcpy
    sub  rax, rbx
    lea  rsi, [rsi+rax+1]
    add  rbx, 32
    inc  r12d
    jmp  .wn
.wn_done:
    mov  [rel menu_world_count], r12d
    SETD menu_sel, 1
    SETD g_mouse_x, 640
    SETD g_mouse_y, 215
    FRAME "worldselect_list", menus_render, fp_menu
    SETD g_mouse_y, 330
    SETD g_state, ST_CREATEWORLD
    FRAME "createworld", menus_render, fp_menu
    SETD g_state, ST_LOADING
    FRAME "loading", menus_render, fp_menu
    SETD g_state, ST_SETTINGS
    FRAME "settings", menus_render, fp_menu

    TEST "in-game screens"
    SETD g_world_active, 1
    SETD g_gamemode, 0
    lea  rsi, [rel inv_items]
    lea  rdi, [rel g_player+PLAYER.inv]
    xor  ecx, ecx
.inv:
    movzx eax, byte [rsi+rcx*2]
    mov  [rdi+rcx*4], al
    movzx edx, byte [rsi+rcx*2+1]
    mov  [rdi+rcx*4+1], dl
    xor  edx, edx
    cmp  eax, 142
    jne  .dur
    mov  edx, 120
.dur:
    mov  [rdi+rcx*4+2], dx
    inc  ecx
    cmp  ecx, 9
    jl   .inv
    SETD g_player+PLAYER.health, 7      ; 3.5 hearts
    SETD g_player+PLAYER.hunger, 13
    SETD g_player+PLAYER.saturation, 0  ; 0.0: hunger bar jitter
    SETD g_player+PLAYER.air, 180
    SETD g_player+PLAYER.eye_in_water, 1
    SETD g_player+PLAYER.selected, 2
    SETD g_player+PLAYER.hurt_time, 6
    SETD g_player+PLAYER.x, __?float32?__(12.5)
    SETD g_player+PLAYER.y, __?float32?__(70.0)
    SETD g_player+PLAYER.z, __?float32?__(-8.25)
    lea  rcx, [rel s_welcome]
    mov  edx, 0xFFFFFFFF
    call chat_add
    STRP rcx, "/time set noon"
    call console_execute
    STRP rcx, "/give diamond 3"
    call console_execute
    lea  rcx, [rel s_brag]
    mov  edx, 0xFFFFFFFF
    call chat_add
    SETD g_state, ST_PLAYING
    FRAME "hud", hud_render, fp_hud
    mov  rsi, [rel pv_img]              ; keep it for the hotbar crop
    mov  rdi, [rel hud_copy]
    mov  ecx, SW*SH
    rep  movsd
    SETD g_show_debug, 1
    FRAME "hud_debug", hud_render, fp_hud
    SETD g_show_debug, 0
    SETD g_state, ST_CHAT
    xor  ecx, ecx
    call console_open
    mov  ecx, '/'
    call con_insert
    mov  ecx, 't'
    call con_insert
    mov  ecx, 'i'
    call con_insert
    FRAME "chat", draw_chat, fp_chat
    SETD g_state, ST_PAUSED
    FRAME "pause", draw_pause, fp_chat
    SETD g_player+PLAYER.health, 0
    SETD g_player+PLAYER.last_damage_src, 4
    SETD g_state, ST_DEAD
    FRAME "dead", draw_pause, fp_dead

    TEST "icons"
    SETD g_mouse_x, 900
    SETD g_mouse_y, 300
    FRAME "icons", draw_icons, fp_icons

    TEST "crops"
    mov  rcx, [rel hud_copy]            ; hotbar strip at the bottom centre
    mov  edx, 380
    mov  r8d, 600
    mov  r9d, 900
    mov  qword [rsp+32], 720
    mov  qword [rsp+40], 2
    STRP rax, "ui_hud_hotbar_x2.bmp"
    mov  [rsp+48], rax
    call crop_zoom
    CHECK_TRUE eax, "hotbar crop written"
    mov  rcx, [rel pv_img]              ; the icon panel (top-left)
    xor  edx, edx
    xor  r8d, r8d
    mov  r9d, 640
    mov  qword [rsp+32], 400
    mov  qword [rsp+40], 2
    STRP rax, "ui_icons_panel_x2.bmp"
    mov  [rsp+48], rax
    call crop_zoom
    CHECK_TRUE eax, "icon panel crop written"
.close:
    call gl_close
.done:
ENDP
