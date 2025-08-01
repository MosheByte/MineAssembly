%define IMPL_UI
%include "common.inc"

extern GlobalLock, GlobalUnlock

%define VB_MAX          16384
%define VSTRIDE         20  ; x,y,u,v floats + rgba bytes
%define CF_TEXT         1

%define QX0 0
%define QY0 4
%define QX1 8
%define QY1 12
%define QU0 16
%define QV0 20
%define QU1 24
%define QV1 28
%define QC0 32  ; TL TR BR BL, already GL byte order
%define QC1 36
%define QC2 40
%define QC3 44

global ui_qp, ui_emit_q, ui_flush, ui_bind_tex, ui_reserve, ui_put_vert
global ui_argb_gl, ui_col_scale, ui_tile_uv, ui_char_width, ui_text_ex
global ui_text_centered_ex, ui_rect_hgrad, ui_clipboard_get, ui_itoa
global ui_focus, ui_time, ui_press_x, ui_press_y, ui_palette, ui_active_slider
global ui_text_dims
global ui_tb_caret, ui_tb_owner, ui_edit_keys, ui_edit_nkeys, ui_max_scale

section .rdata
align 16
f_one:          dd 1.0
f_inv16:        dd 0.0625
f_eps:          dd 0.00048828125  ; 1/2048, keeps UVs off the tile edges
f_tw:           dd 0.0615234375
f_white_u:      dd 0.90625  ; centre of T_WHITE (tile 110)
f_white_v:      dd 0.40625
f_m1:           dd -1.0
f_two:          dd 2.0
f_m2:           dd -2.0
f_255:          dd 255.0
f_13:           dd 13.0
f_half:         dd 0.5

; text palette, roughly EGA but warmer
align 4
ui_palette:
    dd 0x000000
    dd 0x2A40B4
    dd 0x2E9E44
    dd 0x2A9C9C
    dd 0xB02C2C
    dd 0x9A3CB0
    dd 0xF0A830
    dd 0xB8B8BC
    dd 0x5C5C62
    dd 0x6C8CFF
    dd 0x70F070
    dd 0x6CF0F0
    dd 0xFF6464
    dd 0xFF74E0
    dd 0xFFF070
    dd 0xFFFFFF

; inventory has no biome, so fixed tints per TINT_*
tint_cols:
    dd 0xFFFFFFFF
    dd 0xFF7CBF5A
    dd 0xFF5AAE34
    dd 0xFF5F9A62
    dd 0xFF82A858
    dd 0xFF4078E0

; iso cube: 3 faces x 4 verts (x, y, u sel, v sel)
; half width 6.5, rhombus half height 6.5*tan30, vertical edge 6.5/cos30
align 16
iso_tab:
; GL_QUADS wants perimeter order
    dd 8.0,  0.5,   0.0, 0.0
    dd 14.5, 4.25,  1.0, 0.0
    dd 8.0,  8.0,   1.0, 1.0
    dd 1.5,  4.25,  0.0, 1.0
    dd 1.5,  4.25,  0.0, 0.0
    dd 8.0,  8.0,   1.0, 0.0
    dd 8.0,  15.5,  1.0, 1.0
    dd 1.5,  11.75, 0.0, 1.0
    dd 8.0,  8.0,   0.0, 0.0
    dd 14.5, 4.25,  1.0, 0.0
    dd 14.5, 11.75, 1.0, 1.0
    dd 8.0,  15.5,  0.0, 1.0
iso_face:   db FACE_PY, FACE_PZ, FACE_PX, 0
align 4
iso_shade:  dd 256, 205, 156  ; /256

s_caret:    db "_", 0

section .bss
alignb 16
ui_vbuf:            resb VB_MAX*VSTRIDE
ui_qp:              resd 12
ui_ortho:           resd 16
ui_vcount:          resd 1
ui_cur_tex:         resd 1
ui_focus:           resd 1
ui_time:            resd 1
ui_press_x:         resd 1  ; UI px
ui_press_y:         resd 1
ui_active_slider:   resq 1
ui_numbuf:          resb 32
ui_fmtbuf:          resb 256
ui_tb_vis:          resb 256
ui_tb_tmp:          resb 256
ui_tb_caret:        resd 1
ui_tb_owner:        resd 1
ui_edit_keys:       resb 16  ; queued by menus_on_key
ui_edit_nkeys:      resd 1
ui_max_scale:       resd 1

section .text

; 0xAARRGGBB -> R,G,B,A bytes for glColorPointer. alpha 0 -> FF
LEAF ui_argb_gl
    mov  eax, ecx
    test eax, 0xFF000000
    jnz  .a
    or   eax, 0xFF000000
.a: mov  edx, eax
    and  eax, 0xFF00FF00
    mov  ecx, edx
    shr  ecx, 16
    and  ecx, 0xFF
    or   eax, ecx
    and  edx, 0xFF
    shl  edx, 16
    or   eax, edx
    ret

; rgb *= k/256, clamped
LEAF ui_col_scale
    mov  r8d, ecx
    and  r8d, 0xFF000000
    xor  r9d, r9d
    mov  r10d, 3
    mov  r11d, ecx
    xor  ecx, ecx
.ch:
    mov  eax, r11d
    shr  eax, cl
    and  eax, 0xFF
    imul eax, edx
    shr  eax, 8
    cmp  eax, 255
    jbe  .ok
    mov  eax, 255
.ok:
    shl  eax, cl
    or   r9d, eax
    add  ecx, 8
    dec  r10d
    jnz  .ch
    mov  eax, r9d
    or   eax, r8d
    ret

; edx != 0 -> 25% shadow colour
LEAF ui_col_conv
    test ecx, 0xFF000000
    jnz  .a
    or   ecx, 0xFF000000
.a: test edx, edx
    jz   .nd
    mov  eax, ecx
    and  eax, 0xFF000000
    shr  ecx, 2
    and  ecx, 0x003F3F3F
    or   ecx, eax
.nd:
    jmp  ui_argb_gl

; call before touching GL state yourself
PROC ui_flush
    mov  eax, [rel ui_vcount]
    test eax, eax
    jz   .done
    lea  rbx, [rel ui_vbuf]
    mov  ecx, 2
    mov  edx, GL_FLOAT
    mov  r8d, VSTRIDE
    mov  r9, rbx
    call glVertexPointer
    mov  ecx, 2
    mov  edx, GL_FLOAT
    mov  r8d, VSTRIDE
    lea  r9, [rbx+8]
    call glTexCoordPointer
    mov  ecx, 4
    mov  edx, GL_UNSIGNED_BYTE
    mov  r8d, VSTRIDE
    lea  r9, [rbx+16]
    call glColorPointer
    mov  ecx, GL_QUADS
    xor  edx, edx
    mov  r8d, [rel ui_vcount]
    call glDrawArrays
    mov  dword [rel ui_vcount], 0
.done:
ENDP

PROC ui_bind_tex
    cmp  ecx, [rel ui_cur_tex]
    je   .done
    mov  ebx, ecx
    call ui_flush
    mov  [rel ui_cur_tex], ebx
    mov  ecx, GL_TEXTURE_2D
    mov  edx, ebx
    call glBindTexture
.done:
ENDP

LEAF ui_reserve
    mov  eax, [rel ui_vcount]
    add  eax, ecx
    cmp  eax, VB_MAX
    jbe  .ok
    sub  rsp, 40
    call ui_flush
    add  rsp, 40
.ok:
    ret

; no bounds check, ui_reserve first
LEAF ui_put_vert
    mov  eax, [rel ui_vcount]
    imul edx, eax, VSTRIDE
    lea  r8, [rel ui_vbuf]
    add  r8, rdx
    movss [r8+0], xmm0
    movss [r8+4], xmm1
    movss [r8+8], xmm2
    movss [r8+12], xmm3
    mov  [r8+16], ecx
    inc  eax
    mov  [rel ui_vcount], eax
    ret

LEAF ui_emit_q
    mov  eax, [rel ui_vcount]
    cmp  eax, VB_MAX-4
    jbe  .room
    sub  rsp, 40
    call ui_flush
    add  rsp, 40
    mov  eax, [rel ui_vcount]
.room:
    imul edx, eax, VSTRIDE
    lea  r8, [rel ui_vbuf]
    add  r8, rdx
    lea  r9, [rel ui_qp]
    mov  edx, [r9+QX0]
    mov  [r8+0], edx
    mov  edx, [r9+QY0]
    mov  [r8+4], edx
    mov  edx, [r9+QU0]
    mov  [r8+8], edx
    mov  edx, [r9+QV0]
    mov  [r8+12], edx
    mov  edx, [r9+QC0]
    mov  [r8+16], edx
    mov  edx, [r9+QX1]
    mov  [r8+20], edx
    mov  edx, [r9+QY0]
    mov  [r8+24], edx
    mov  edx, [r9+QU1]
    mov  [r8+28], edx
    mov  edx, [r9+QV0]
    mov  [r8+32], edx
    mov  edx, [r9+QC1]
    mov  [r8+36], edx
    mov  edx, [r9+QX1]
    mov  [r8+40], edx
    mov  edx, [r9+QY1]
    mov  [r8+44], edx
    mov  edx, [r9+QU1]
    mov  [r8+48], edx
    mov  edx, [r9+QV1]
    mov  [r8+52], edx
    mov  edx, [r9+QC2]
    mov  [r8+56], edx
    mov  edx, [r9+QX0]
    mov  [r8+60], edx
    mov  edx, [r9+QY1]
    mov  [r8+64], edx
    mov  edx, [r9+QU0]
    mov  [r8+68], edx
    mov  edx, [r9+QV1]
    mov  [r8+72], edx
    mov  edx, [r9+QC3]
    mov  [r8+76], edx
    add  eax, 4
    mov  [rel ui_vcount], eax
    ret

; pulled in a bit so nearest sampling can't bleed in from the next tile
LEAF ui_tile_uv
    lea  r8, [rel ui_qp]
    mov  eax, ecx
    and  eax, 15
    cvtsi2ss xmm0, eax
    mulss xmm0, [rel f_inv16]
    addss xmm0, [rel f_eps]
    movss [r8+QU0], xmm0
    addss xmm0, [rel f_tw]
    movss [r8+QU1], xmm0
    mov  eax, ecx
    shr  eax, 4
    and  eax, 15
    cvtsi2ss xmm0, eax
    mulss xmm0, [rel f_inv16]
    addss xmm0, [rel f_eps]
    movss [r8+QV0], xmm0
    addss xmm0, [rel f_tw]
    movss [r8+QV1], xmm0
    ret

LEAF ui_set_xywh
    lea  r10, [rel ui_qp]
    cvtsi2ss xmm0, ecx
    movss [r10+QX0], xmm0
    add  ecx, r8d
    cvtsi2ss xmm0, ecx
    movss [r10+QX1], xmm0
    cvtsi2ss xmm0, edx
    movss [r10+QY0], xmm0
    add  edx, r9d
    cvtsi2ss xmm0, edx
    movss [r10+QY1], xmm0
    ret

PROC ui_init
    xor  eax, eax
    mov  [rel ui_focus], eax
    mov  [rel ui_vcount], eax
    mov  [rel ui_cur_tex], eax
    mov  [rel ui_active_slider], rax
    mov  dword [rel ui_press_x], -1000
    mov  dword [rel ui_press_y], -1000
ENDP

PROC ui_begin, 16
    mov  r12d, [rel g_screen_w]
    mov  r13d, [rel g_screen_h]
    cmp  r12d, 1
    jge  .w_ok
    mov  r12d, 1
.w_ok:
    cmp  r13d, 1
    jge  .h_ok
    mov  r13d, 1
.h_ok:
    mov  ebx, 4  ; biggest scale that still leaves 320x240
.am:
    cmp  ebx, 1
    jle  .am_done
    mov  eax, r12d
    xor  edx, edx
    div  ebx
    cmp  eax, 320
    jb   .am_dec
    mov  eax, r13d
    xor  edx, edx
    div  ebx
    cmp  eax, 240
    jb   .am_dec
    jmp  .am_done
.am_dec:
    dec  ebx
    jmp  .am
.am_done:
    mov  [rel ui_max_scale], ebx  ; settings offers 1..this
    lea  rax, [rel g_settings]
    mov  ecx, [rax+SETTINGS.gui_scale]
    cmp  ecx, 1
    jl   .scale_set  ; 0 = auto
    cmp  ecx, ebx
    jg   .scale_set
    mov  ebx, ecx
.scale_set:
    mov  [rel g_ui_scale], ebx
    mov  eax, r12d
    xor  edx, edx
    div  ebx
    mov  [rel g_ui_w], eax
    mov  eax, r13d
    xor  edx, edx
    div  ebx
    mov  [rel g_ui_h], eax
    mov  eax, [rel g_mouse_x]
    cdq
    idiv ebx
    mov  [rel g_ui_mx], eax
    mov  eax, [rel g_mouse_y]
    cdq
    idiv ebx
    mov  [rel g_ui_my], eax
    movsd xmm0, [rel g_time_total]
    cvtsd2ss xmm0, xmm0
    movss [rel ui_time], xmm0
    test dword [rel g_mouse_pressed], MB_LEFT
    jz   .no_press
    mov  eax, [rel g_ui_mx]
    mov  [rel ui_press_x], eax
    mov  eax, [rel g_ui_my]
    mov  [rel ui_press_y], eax
.no_press:
; a slider grabbed on a screen that's not drawn anymore would stay grabbed
; forever, so drop it once the button's up. the slider handles the release frame
    test dword [rel g_mouse_buttons], MB_LEFT
    jnz  .grab_ok
    test dword [rel g_mouse_released], MB_LEFT
    jnz  .grab_ok
    test dword [rel g_mouse_pressed], MB_LEFT
    jnz  .grab_ok
    mov  qword [rel ui_active_slider], 0
.grab_ok:
; x' = 2x*s/w - 1, y' = 1 - 2y*s/h
    lea  rdi, [rel ui_ortho]
    xor  eax, eax
    mov  ecx, 16
.zm:
    mov  [rdi+rcx*4-4], eax
    loop .zm
    cvtsi2ss xmm0, ebx
    cvtsi2ss xmm1, r12d
    movss xmm2, xmm0
    mulss xmm2, [rel f_two]
    divss xmm2, xmm1
    movss [rdi+0], xmm2
    cvtsi2ss xmm1, r13d
    movss xmm2, xmm0
    mulss xmm2, [rel f_m2]
    divss xmm2, xmm1
    movss [rdi+20], xmm2
    mov  eax, __float32__(-1.0)
    mov  [rdi+40], eax
    mov  [rdi+48], eax
    mov  eax, __float32__(1.0)
    mov  [rdi+52], eax
    mov  [rdi+60], eax
; those entry points may not have loaded
    mov  rax, [rel pglUseProgram]
    test rax, rax
    jz   .no_prog
    xor  ecx, ecx
    call rax
.no_prog:
    mov  rax, [rel pglBindBuffer]
    test rax, rax
    jz   .no_vbo
    mov  ecx, GL_ARRAY_BUFFER
    xor  edx, edx
    call rax
.no_vbo:
    mov  rax, [rel pglActiveTexture]
    test rax, rax
    jz   .no_at
    mov  ecx, GL_TEXTURE0
    call rax
.no_at:
    xor  ecx, ecx
    xor  edx, edx
    mov  r8d, r12d
    mov  r9d, r13d
    call glViewport
    mov  ecx, GL_PROJECTION
    call glMatrixMode
    lea  rcx, [rel ui_ortho]
    call glLoadMatrixf
    mov  ecx, GL_MODELVIEW
    call glMatrixMode
    call glLoadIdentity
    mov  ecx, GL_DEPTH_TEST
    call glDisable
    xor  ecx, ecx
    call glDepthMask
    mov  ecx, GL_CULL_FACE
    call glDisable
    mov  ecx, GL_ALPHA_TEST
    call glDisable
    mov  ecx, GL_FOG
    call glDisable
    mov  ecx, GL_BLEND
    call glEnable
    mov  ecx, GL_SRC_ALPHA
    mov  edx, GL_ONE_MINUS_SRC_ALPHA
    call glBlendFunc
    mov  ecx, GL_TEXTURE_2D
    call glEnable
    mov  ecx, GL_TEXTURE_ENV
    mov  edx, GL_TEXTURE_ENV_MODE
    mov  r8d, GL_MODULATE
    call glTexEnvi
    mov  ecx, GL_VERTEX_ARRAY
    call glEnableClientState
    mov  ecx, GL_TEXTURE_COORD_ARRAY
    call glEnableClientState
    mov  ecx, GL_COLOR_ARRAY
    call glEnableClientState
    mov  ecx, GL_TEXTURE_2D
    mov  edx, [rel g_tex_atlas]
    call glBindTexture
    mov  eax, [rel g_tex_atlas]
    mov  [rel ui_cur_tex], eax
    mov  dword [rel ui_vcount], 0
ENDP

PROC ui_end
    call ui_flush
    mov  ecx, GL_VERTEX_ARRAY
    call glDisableClientState
    mov  ecx, GL_TEXTURE_COORD_ARRAY
    call glDisableClientState
    mov  ecx, GL_COLOR_ARRAY
    call glDisableClientState
    movss xmm0, [rel f_one]
    movss xmm1, xmm0
    movss xmm2, xmm0
    movss xmm3, xmm0
    call glColor4f
    mov  ecx, GL_TEXTURE_2D
    mov  edx, [rel g_tex_atlas]
    call glBindTexture
    mov  eax, [rel g_tex_atlas]
    mov  [rel ui_cur_tex], eax
    mov  ecx, GL_DEPTH_TEST
    call glEnable
    mov  ecx, 1
    call glDepthMask
    mov  ecx, GL_LEQUAL
    call glDepthFunc
    mov  ecx, GL_SRC_ALPHA
    mov  edx, GL_ONE_MINUS_SRC_ALPHA
    call glBlendFunc
    mov  ecx, GL_BLEND
    call glDisable
    mov  ecx, GL_BACK
    call glCullFace
    mov  ecx, GL_CULL_FACE
    call glEnable
    mov  ecx, GL_PROJECTION
    call glMatrixMode
    lea  rcx, [rel g_mat_proj]
    call glLoadMatrixf
    mov  ecx, GL_MODELVIEW
    call glMatrixMode
    lea  rcx, [rel g_mat_view]
    call glLoadMatrixf
ENDP

PROC ui_rect
    mov  eax, ARG5
    mov  [rsp+32], rax
    mov  [rsp+40], rax
    call ui_rect_grad
ENDP

PROC ui_rect_grad
    test r8d, r8d
    jle  .done
    test r9d, r9d
    jle  .done
    mov  ebx, ecx
    mov  esi, edx
    mov  edi, r8d
    mov  r12d, r9d
    mov  ecx, [rel g_tex_atlas]
    call ui_bind_tex
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    mov  r9d, r12d
    call ui_set_xywh
    lea  r13, [rel ui_qp]
    movss xmm0, [rel f_white_u]
    movss [r13+QU0], xmm0
    movss [r13+QU1], xmm0
    movss xmm0, [rel f_white_v]
    movss [r13+QV0], xmm0
    movss [r13+QV1], xmm0
    mov  ecx, ARG5
    call ui_argb_gl
    mov  [r13+QC0], eax
    mov  [r13+QC1], eax
    mov  ecx, ARG6
    call ui_argb_gl
    mov  [r13+QC2], eax
    mov  [r13+QC3], eax
    call ui_emit_q
.done:
ENDP

; left -> right gradient
PROC ui_rect_hgrad
    test r8d, r8d
    jle  .done
    test r9d, r9d
    jle  .done
    mov  ebx, ecx
    mov  esi, edx
    mov  edi, r8d
    mov  r12d, r9d
    mov  ecx, [rel g_tex_atlas]
    call ui_bind_tex
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    mov  r9d, r12d
    call ui_set_xywh
    lea  r13, [rel ui_qp]
    movss xmm0, [rel f_white_u]
    movss [r13+QU0], xmm0
    movss [r13+QU1], xmm0
    movss xmm0, [rel f_white_v]
    movss [r13+QV0], xmm0
    movss [r13+QV1], xmm0
    mov  ecx, ARG5
    call ui_argb_gl
    mov  [r13+QC0], eax
    mov  [r13+QC3], eax
    mov  ecx, ARG6
    call ui_argb_gl
    mov  [r13+QC1], eax
    mov  [r13+QC2], eax
    call ui_emit_q
.done:
ENDP

; same macros as hud.asm
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

; standard panel: dark outline with cut corners, grey body, 2px bevels
PROC ui_frame, 16
    mov  ebx, ecx
    mov  esi, edx
    mov  edi, r8d
    mov  r12d, r9d
    cmp  edi, 8
    jl   .done
    cmp  r12d, 8
    jl   .done
    lea  r13d, [rbx+1]
    lea  r14d, [rdi-2]
    RECT r13d, esi, r14d, 1, 0xFF101014
    lea  eax, [rsi+r12-1]
    mov  LOC(0), eax
    RECT r13d, LOC(0), r14d, 1, 0xFF101014
    lea  r15d, [rsi+1]
    lea  eax, [r12-2]
    mov  LOC(4), eax
    RECT ebx, r15d, 1, LOC(4), 0xFF101014
    lea  eax, [rbx+rdi-1]
    mov  LOC(8), eax
    RECT LOC(8), r15d, 1, LOC(4), 0xFF101014
    RECTG r13d, r15d, r14d, LOC(4), 0xFFCBCDD3, 0xFFBDBFC6
    lea  eax, [rdi-4]
    mov  LOC(8), eax
    RECT r13d, r15d, LOC(8), 2, 0xFFF6F7FA
    lea  eax, [rsi+3]
    mov  LOC(0), eax
    lea  eax, [r12-6]
    mov  LOC(4), eax
    RECT r13d, LOC(0), 2, LOC(4), 0xFFF6F7FA
    lea  eax, [rbx+3]
    mov  LOC(0), eax
    lea  eax, [rsi+r12-3]
    mov  LOC(4), eax
    lea  eax, [rdi-4]
    mov  LOC(8), eax
    RECT LOC(0), LOC(4), LOC(8), 2, 0xFF585B66
    lea  eax, [rbx+rdi-3]
    mov  LOC(0), eax
    lea  eax, [rsi+3]
    mov  LOC(4), eax
    lea  eax, [r12-5]
    mov  LOC(8), eax
    RECT LOC(0), LOC(4), 2, LOC(8), 0xFF585B66
.done:
ENDP

LEAF ui_char_width
    and  ecx, 0xFF
    cmp  ecx, 128
    jb   .ok
    mov  ecx, '?'
.ok:
    lea  rax, [rel g_font_widths]
    movzx eax, byte [rax+rcx]
    test eax, eax
    jnz  .r
    mov  eax, 6  ; font not built yet
    cmp  ecx, ' '
    jne  .r
    mov  eax, 4
.r: ret

; -> 0..15, 16 for r (reset), -1 junk
LEAF ui_hexval
    mov  eax, ecx
    sub  eax, '0'
    cmp  eax, 9
    jbe  .r
    mov  eax, ecx
    or   eax, 0x20
    cmp  eax, 'r'
    je   .reset
    sub  eax, 'a'
    cmp  eax, 5
    ja   .bad
    add  eax, 10
.r: ret
.reset:
    mov  eax, 16
    ret
.bad:
    mov  eax, -1
    ret

PROC ui_text_dims
    mov  rsi, rcx
    xor  ebx, ebx
    xor  edi, edi
    mov  r12d, 1
    test rsi, rsi
    jz   .end
.lp:
    movzx ecx, byte [rsi]
    inc  rsi
    test ecx, ecx
    jz   .end
    cmp  ecx, 10
    je   .nl
    cmp  ecx, 12
    je   .code
    call ui_char_width
    add  ebx, eax
    jmp  .lp
.code:
    cmp  byte [rsi], 0
    je   .end
    inc  rsi
    jmp  .lp
.nl:
    cmp  ebx, edi
    cmovg edi, ebx
    xor  ebx, ebx
    inc  r12d
    jmp  .lp
.end:
    cmp  ebx, edi
    cmovg edi, ebx
    mov  eax, edi
    mov  edx, r12d
ENDP

PROC ui_text_width
    call ui_text_dims
ENDP

; ARG6 = dim (shadow pass). '\f' + hex digit picks a palette colour, '\f' 'r' resets
PROC ui_text_pass, 32
    mov  r14d, ecx
    mov  ebx, ecx
    mov  r12d, edx
    mov  rsi, r8
    mov  r13d, ARG5
    cmp  r13d, 1
    jge  .sc
    mov  r13d, 1
.sc:
    mov  eax, r9d
    test eax, 0xFF000000
    jnz  .ha
    or   eax, 0xFF000000
.ha:
    mov  LOC(0), eax
    xor  r15d, r15d
    test rsi, rsi
    jz   .end
    mov  ecx, eax
    mov  edx, ARG6
    call ui_col_conv
    mov  edi, eax
    mov  ecx, [rel g_tex_font]
    call ui_bind_tex
.loop:
    movzx eax, byte [rsi]
    inc  rsi
    test eax, eax
    jz   .end
    cmp  eax, 10
    je   .nl
    cmp  eax, 12
    je   .code
    cmp  eax, 128
    jb   .ok
    mov  eax, '?'
.ok:
    mov  LOC(4), eax
    cmp  eax, 32
    jbe  .adv
    lea  rdx, [rel ui_qp]
    cvtsi2ss xmm0, ebx
    movss [rdx+QX0], xmm0
    cvtsi2ss xmm1, r12d
    movss [rdx+QY0], xmm1
    mov  ecx, r13d
    shl  ecx, 3
    cvtsi2ss xmm2, ecx
    addss xmm0, xmm2
    addss xmm1, xmm2
    movss [rdx+QX1], xmm0
    movss [rdx+QY1], xmm1
    mov  ecx, eax
    and  ecx, 15
    cvtsi2ss xmm0, ecx
    mulss xmm0, [rel f_inv16]
    movss [rdx+QU0], xmm0
    addss xmm0, [rel f_inv16]
    movss [rdx+QU1], xmm0
    mov  ecx, eax
    shr  ecx, 4
    cvtsi2ss xmm0, ecx
    mulss xmm0, [rel f_inv16]
    movss [rdx+QV0], xmm0
    addss xmm0, [rel f_inv16]
    movss [rdx+QV1], xmm0
    mov  [rdx+QC0], edi
    mov  [rdx+QC1], edi
    mov  [rdx+QC2], edi
    mov  [rdx+QC3], edi
    call ui_emit_q
.adv:
    mov  ecx, LOC(4)
    call ui_char_width
    imul eax, r13d
    add  ebx, eax
    jmp  .loop
.nl:
    mov  eax, ebx
    sub  eax, r14d
    cmp  eax, r15d
    cmovg r15d, eax
    mov  ebx, r14d
    lea  eax, [r13+r13*8]
    add  r12d, eax
    jmp  .loop
.code:
    movzx ecx, byte [rsi]
    test ecx, ecx
    jz   .end
    inc  rsi
    call ui_hexval
    test eax, eax
    js   .loop
    mov  ecx, LOC(0)
    cmp  eax, 16
    je   .setc
    lea  rdx, [rel ui_palette]
    mov  edx, [rdx+rax*4]
    and  ecx, 0xFF000000
    or   ecx, edx
.setc:
    mov  edx, ARG6
    call ui_col_conv
    mov  edi, eax
    jmp  .loop
.end:
    mov  eax, ebx
    sub  eax, r14d
    cmp  eax, r15d
    cmovl eax, r15d
ENDP

PROC ui_text_ex, 16
    mov  ebx, ecx
    mov  esi, edx
    mov  rdi, r8
    mov  r12d, r9d
    mov  r13d, ARG5
    cmp  r13d, 1
    jge  .s
    mov  r13d, 1
.s:
    cmp  dword ARG6, 0
    je   .main
    lea  ecx, [rbx+r13]
    lea  edx, [rsi+r13]
    mov  r8, rdi
    mov  r9d, r12d
    mov  [rsp+32], r13
    mov  qword [rsp+40], 1
    call ui_text_pass
.main:
    mov  ecx, ebx
    mov  edx, esi
    mov  r8, rdi
    mov  r9d, r12d
    mov  [rsp+32], r13
    mov  qword [rsp+40], 0
    call ui_text_pass
ENDP

PROC ui_text
    mov  qword [rsp+32], 1
    mov  qword [rsp+40], 0
    call ui_text_ex
ENDP

PROC ui_text_shadow
    mov  qword [rsp+32], 1
    mov  qword [rsp+40], 1
    call ui_text_ex
ENDP

PROC ui_text_scaled
    mov  eax, ARG5
    mov  [rsp+32], rax
    mov  qword [rsp+40], 0
    call ui_text_ex
ENDP

; always shadowed
PROC ui_text_centered_ex
    mov  ebx, ecx
    mov  esi, edx
    mov  rdi, r8
    mov  r12d, r9d
    mov  r13d, ARG5
    cmp  r13d, 1
    jge  .s
    mov  r13d, 1
.s:
    mov  rcx, rdi
    call ui_text_dims
    imul eax, r13d
    mov  r14d, eax
    shr  eax, 1
    mov  ecx, ebx
    sub  ecx, eax
    mov  edx, esi
    mov  r8, rdi
    mov  r9d, r12d
    mov  [rsp+32], r13
    mov  qword [rsp+40], 1
    call ui_text_ex
    mov  eax, r14d
ENDP

PROC ui_text_centered
    mov  qword [rsp+32], 1
    call ui_text_centered_ex
ENDP

; out needs ~21 bytes
LEAF ui_itoa
    push rdi
    mov  r8, rdx
    mov  eax, ecx
    mov  r9d, 0
    test eax, eax
    jns  .pos
    neg  eax
    mov  r9d, 1
.pos:
    lea  rdi, [rdx+20]
    mov  byte [rdi], 0
    mov  ecx, 10
.dl:
    xor  edx, edx
    div  ecx
    add  dl, '0'
    dec  rdi
    mov  [rdi], dl
    test eax, eax
    jnz  .dl
    test r9d, r9d
    jz   .cp
    dec  rdi
    mov  byte [rdi], '-'
.cp:  ; built backwards from out+20, slide to the front
    mov  rax, r8
.cl:
    mov  dl, [rdi]
    mov  [r8], dl
    inc  rdi
    inc  r8
    test dl, dl
    jnz  .cl
    pop  rdi
    ret

PROC ui_tile
    mov  ebx, ecx
    mov  esi, edx
    mov  edi, r8d
    mov  r12d, r9d
    mov  ecx, [rel g_tex_atlas]
    call ui_bind_tex
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    mov  r9d, edi
    call ui_set_xywh
    mov  ecx, r12d
    call ui_tile_uv
    mov  ecx, ARG5
    call ui_argb_gl
    lea  rdx, [rel ui_qp]
    mov  [rdx+QC0], eax
    mov  [rdx+QC1], eax
    mov  [rdx+QC2], eax
    mov  [rdx+QC3], eax
    call ui_emit_q
ENDP

PROC ui_item_icon, 16
    movzx r12d, r8b
    test r12d, r12d
    jz   .done
    mov  ebx, ecx
    mov  esi, edx
    cmp  r12d, 128
    jb   .block
    lea  rax, [rel item_icon]
    movzx r9d, byte [rax+r12]
    cmp  r9d, 0xFF
    jne  .flat
    mov  r9d, T_WHITE
.flat:
    mov  dword [rsp+32], 0xFFFFFFFF
.flat_tint:
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, 16
    call ui_tile
    jmp  .done
.block:
    lea  rax, [rel blk_tint]
    movzx r14d, byte [rax+r12]
    xor  r13d, r13d
    not  r13d
    cmp  r14d, TINT_WATER
    ja   .tint_ok
    lea  rax, [rel tint_cols]
    mov  r13d, [rax+r14*4]
.tint_ok:
; torch, flowers, saplings etc. use a flat icon from item_icon (0xFF = none)
    lea  rax, [rel item_icon]
    movzx r9d, byte [rax+r12]
    cmp  r9d, 0xFF
    je   .model
    mov  [rsp+32], r13
    jmp  .flat_tint
.model:
    lea  rax, [rel blk_model]
    movzx eax, byte [rax+r12]
    cmp  eax, MODEL_CROSS
    je   .sprite
    cmp  eax, MODEL_TORCH
    je   .sprite
    cmp  eax, MODEL_LANTERN
    je   .sprite
    mov  ecx, [rel g_tex_atlas]
    call ui_bind_tex
    mov  ecx, 12
    call ui_reserve
    xor  edi, edi
.face:
    lea  rax, [rel iso_face]
    movzx eax, byte [rax+rdi]
    imul ecx, r12d, 6
    add  ecx, eax
    lea  rax, [rel blk_tex]
    movzx ecx, byte [rax+rcx]
    call ui_tile_uv
    mov  ecx, r13d
    test edi, edi
    jz   .tinted
    cmp  r14d, TINT_GRASS  ; grass: top face only
    jne  .tinted
    mov  ecx, 0xFFFFFFFF
.tinted:
    lea  rax, [rel iso_shade]
    mov  edx, [rax+rdi*4]
    call ui_col_scale
    mov  ecx, eax
    call ui_argb_gl
    mov  r15d, eax
    mov  dword LOC(0), 0
.vert:
    mov  eax, edi
    shl  eax, 2
    add  eax, LOC(0)
    shl  eax, 4
    lea  rdx, [rel iso_tab]
    add  rdx, rax
    cvtsi2ss xmm0, ebx
    addss xmm0, [rdx]
    cvtsi2ss xmm1, esi
    addss xmm1, [rdx+4]
    movss xmm2, [rdx+8]
    mulss xmm2, [rel f_tw]
    addss xmm2, [rel ui_qp+QU0]
    movss xmm3, [rdx+12]
    mulss xmm3, [rel f_tw]
    addss xmm3, [rel ui_qp+QV0]
    mov  ecx, r15d
    call ui_put_vert
    inc  dword LOC(0)
    cmp  dword LOC(0), 4
    jb   .vert
    inc  edi
    cmp  edi, 3
    jb   .face
    jmp  .done
.sprite:
    imul ecx, r12d, 6
    add  ecx, FACE_PX
    lea  rax, [rel blk_tex]
    movzx r9d, byte [rax+rcx]
    mov  [rsp+32], r13
    jmp  .flat_tint
.done:
ENDP

PROC ui_item_stack, 48
    test r8, r8
    jz   .done
    movzx r12d, byte [r8+STACK.id]
    test r12d, r12d
    jz   .done
    mov  ebx, ecx
    mov  esi, edx
    movzx r13d, byte [r8+STACK.count]
    movzx r14d, word [r8+STACK.damage]
    mov  r8d, r12d
    call ui_item_icon
    lea  rax, [rel item_durability]
    movzx r15d, word [rax+r12*2]
    test r15d, r15d
    jz   .count
    test r14d, r14d
    jz   .count
    lea  edi, [rbx+2]
    lea  eax, [rsi+13]
    mov  LOC(0), eax
    RECT edi, LOC(0), 13, 2, 0xFF000000
    mov  eax, r15d
    sub  eax, r14d
    jg   .pos
    xor  eax, eax
.pos:
    cvtsi2ss xmm0, eax
    cvtsi2ss xmm1, r15d
    divss xmm0, xmm1
    movss xmm1, xmm0
    mulss xmm1, [rel f_13]
    addss xmm1, [rel f_half]
    cvttss2si eax, xmm1
    mov  LOC(4), eax
; red -> yellow -> green
    movss xmm1, xmm0
    mulss xmm1, [rel f_255]
    cvttss2si eax, xmm1
    mov  ecx, 255
    sub  ecx, eax
    shl  ecx, 16
    shl  eax, 8
    or   eax, ecx
    or   eax, 0xFF000000
    mov  LOC(8), eax
    RECT edi, LOC(0), LOC(4), 1, LOC(8)
.count:
    cmp  r13d, 1
    jbe  .done
    mov  ecx, r13d
    lea  rdx, [rel ui_numbuf]
    call ui_itoa
    lea  rcx, [rel ui_numbuf]
    call ui_text_dims
    lea  ecx, [rbx+17]
    sub  ecx, eax
    lea  edx, [rsi+9]
    lea  r8, [rel ui_numbuf]
    mov  r9d, 0xFFFFFFFF
    call ui_text_shadow
.done:
ENDP

LEAF ui_mouse_in
    xor  eax, eax
    mov  r10d, [rel g_ui_mx]
    cmp  r10d, ecx
    jl   .no
    add  ecx, r8d
    cmp  r10d, ecx
    jge  .no
    mov  r10d, [rel g_ui_my]
    cmp  r10d, edx
    jl   .no
    add  edx, r9d
    cmp  r10d, edx
    jge  .no
    mov  eax, 1
.no:
    ret

; did the last press start inside the rect
LEAF ui_press_in
    xor  eax, eax
    mov  r10d, [rel ui_press_x]
    cmp  r10d, ecx
    jl   .no
    add  ecx, r8d
    cmp  r10d, ecx
    jge  .no
    mov  r10d, [rel ui_press_y]
    cmp  r10d, edx
    jl   .no
    add  edx, r9d
    cmp  r10d, edx
    jge  .no
    mov  eax, 1
.no:
    ret

; click = press and release both inside, so dragging off cancels it
PROC ui_button, 48
    mov  ebx, ecx
    mov  esi, edx
    mov  edi, r8d
    mov  r12d, r9d
    xor  r15d, r15d
    xor  r14d, r14d
    cmp  dword ARG6, 0
    je   .draw
    call ui_mouse_in  ; args still in ecx/edx/r8d/r9d
    mov  r14d, eax
    test eax, eax
    jz   .draw
    test dword [rel g_mouse_released], MB_LEFT
    jz   .draw
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    mov  r9d, r12d
    call ui_press_in
    test eax, eax
    jz   .draw
    mov  r15d, 1
    mov  ecx, SFX_CLICK
    movss xmm1, [rel f_one]
    movss xmm2, [rel f_one]
    call sfx_play
.draw:
; LOC 0..20: border, top, bottom, highlight, shade, text
    cmp  dword ARG6, 0
    je   .disabled
    test r14d, r14d
    jnz  .hover
    mov  dword LOC(0), 0xFF0C0C10
    mov  dword LOC(4), 0xFF7D8290
    mov  dword LOC(8), 0xFF5A5F6C
    mov  dword LOC(12), 0xFFA8ADBA
    mov  dword LOC(16), 0xFF3C3F48
    mov  dword LOC(20), 0xFFE8E8E8
    jmp  .paint
.hover:
    mov  dword LOC(0), 0xFFFFFFFF
    mov  dword LOC(4), 0xFF8496CC
    mov  dword LOC(8), 0xFF5C6CA4
    mov  dword LOC(12), 0xFFB8C6F0
    mov  dword LOC(16), 0xFF3A4470
    mov  dword LOC(20), 0xFFFFFFA0
    jmp  .paint
.disabled:
    mov  dword LOC(0), 0xFF0C0C10
    mov  dword LOC(4), 0xFF4A4A4E
    mov  dword LOC(8), 0xFF3C3C40
    mov  dword LOC(12), 0xFF58585C
    mov  dword LOC(16), 0xFF2E2E32
    mov  dword LOC(20), 0xFF9A9A9A
.paint:
    RECT ebx, esi, edi, r12d, LOC(0)
    lea  eax, [rbx+1]
    mov  LOC(24), eax
    lea  eax, [rsi+1]
    mov  LOC(28), eax
    lea  eax, [rdi-2]
    mov  LOC(32), eax
    lea  eax, [r12-2]
    mov  LOC(36), eax
    RECTG LOC(24), LOC(28), LOC(32), LOC(36), LOC(4), LOC(8)
    RECT LOC(24), LOC(28), LOC(32), 1, LOC(12)
    lea  eax, [r12-3]
    mov  LOC(36), eax
    RECT LOC(24), LOC(28), 1, LOC(36), LOC(12)
    lea  eax, [rsi+r12-2]
    mov  LOC(28), eax
    RECT LOC(24), LOC(28), LOC(32), 1, LOC(16)
    lea  eax, [rbx+rdi-2]
    mov  LOC(24), eax
    lea  eax, [rsi+2]
    mov  LOC(28), eax
    RECT LOC(24), LOC(28), 1, LOC(36), LOC(16)
    mov  r13, ARG5
    test r13, r13
    jz   .ret
    mov  ecx, edi
    shr  ecx, 1
    add  ecx, ebx
    mov  edx, r12d
    sub  edx, 7
    sar  edx, 1
    add  edx, esi
    mov  r8, r13
    mov  r9d, LOC(20)
    mov  qword [rsp+32], 1
    call ui_text_centered_ex
.ret:
    mov  eax, r15d
ENDP

; does fmt want an int? lets slider labels use %d or %f
LEAF ui_fmt_is_int
    xor  eax, eax
    test rcx, rcx
    jz   .r
.lp:
    movzx edx, byte [rcx]
    inc  rcx
    test edx, edx
    jz   .r
    cmp  edx, '%'
    jne  .lp
.spec:
    movzx edx, byte [rcx]
    inc  rcx
    test edx, edx
    jz   .r
    cmp  edx, '%'
    je   .lp
    cmp  edx, 'd'
    je   .int
    cmp  edx, 'i'
    je   .int
    cmp  edx, 'u'
    je   .int
    cmp  edx, 'f'
    je   .r
    jmp  .spec
.int:
    mov  eax, 1
.r: ret

; r9 float* value, ARG5/ARG6 min/max as float bits, ARG7 label fmt
; keeps dragging while the button is held even off the widget
PROCX ui_slider, 48
    mov  ebx, ecx
    mov  esi, edx
    mov  edi, r8d
    mov  r12, r9
    xor  r15d, r15d
    movd xmm6, ARG5
    movd xmm7, ARG6
    cmp  edi, 16
    jge  .wok
    mov  edi, 16
.wok:
    mov  r8d, edi
    mov  r9d, 20
    call ui_mouse_in
    mov  r14d, eax
    test dword [rel g_mouse_pressed], MB_LEFT
    jz   .nopress
    test r14d, r14d
    jz   .nopress
    mov  [rel ui_active_slider], r12
.nopress:
    cmp  [rel ui_active_slider], r12
    jne  .draw
    mov  r14d, 1
; press+release in the same frame should still move the knob
    test dword [rel g_mouse_buttons], MB_LEFT
    jnz  .track
    test dword [rel g_mouse_pressed], MB_LEFT
    jz   .release
.track:
; t = clamp((mx - x - 4) / (w - 8), 0, 1)
    mov  eax, [rel g_ui_mx]
    sub  eax, ebx
    sub  eax, 4
    cvtsi2ss xmm0, eax
    lea  eax, [rdi-8]
    cvtsi2ss xmm1, eax
    divss xmm0, xmm1
    xorps xmm1, xmm1
    maxss xmm0, xmm1
    minss xmm0, [rel f_one]
    movss xmm1, xmm7
    subss xmm1, xmm6
    mulss xmm0, xmm1
    addss xmm0, xmm6
    test r12, r12
    jz   .tracked
    ucomiss xmm0, [r12]
    je   .tracked
    movss [r12], xmm0
    mov  r15d, 1
.tracked:
    test dword [rel g_mouse_buttons], MB_LEFT
    jnz  .draw
.release:
    mov  qword [rel ui_active_slider], 0
    mov  ecx, SFX_CLICK
    movss xmm1, [rel f_one]
    movss xmm2, [rel f_one]
    call sfx_play
.draw:
    xorps xmm8, xmm8
    test r12, r12
    jz   .tz
    movss xmm8, [r12]
.tz:
    subss xmm8, xmm6
    movss xmm1, xmm7
    subss xmm1, xmm6
    xorps xmm2, xmm2
    ucomiss xmm1, xmm2
    je   .t0
    divss xmm8, xmm1
    jmp  .tc
.t0:
    xorps xmm8, xmm8
.tc:
    xorps xmm1, xmm1
    maxss xmm8, xmm1
    minss xmm8, [rel f_one]
    RECT ebx, esi, edi, 20, 0xFF0C0C10
    lea  eax, [rbx+1]
    mov  LOC(0), eax
    lea  eax, [rsi+1]
    mov  LOC(4), eax
    lea  eax, [rdi-2]
    mov  LOC(8), eax
    RECTG LOC(0), LOC(4), LOC(8), 18, 0xFF24262C, 0xFF363940
; fill runs along the bottom so it stays under the label
    lea  eax, [rdi-8]
    cvtsi2ss xmm0, eax
    mulss xmm0, xmm8
    cvttss2si r13d, xmm0
    lea  eax, [rsi+16]
    mov  LOC(4), eax
    lea  eax, [r13+3]
    mov  LOC(8), eax
    RECT LOC(0), LOC(4), LOC(8), 2, 0xFF5C7CC8
    lea  eax, [rbx+r13]
    mov  LOC(0), eax
    mov  ecx, 0xFF0C0C10
    mov  edx, 0xFFFFFFFF
    test r14d, r14d
    cmovnz ecx, edx
    mov  LOC(12), ecx
    RECT LOC(0), esi, 8, 20, LOC(12)
    inc  dword LOC(0)
    lea  eax, [rsi+1]
    mov  LOC(4), eax
    mov  ecx, 0xFF8C91A0
    mov  edx, 0xFF9AA8DA
    test r14d, r14d
    cmovnz ecx, edx
    mov  LOC(16), ecx
    mov  ecx, 0xFF5A5F6C
    mov  edx, 0xFF5C6CA4
    test r14d, r14d
    cmovnz ecx, edx
    mov  LOC(20), ecx
    RECTG LOC(0), LOC(4), 6, 18, LOC(16), LOC(20)
    RECT LOC(0), LOC(4), 6, 1, 0x60FFFFFF
    mov  r13, ARG7
    test r13, r13
    jz   .ret
    mov  rcx, r13
    call ui_fmt_is_int
    xor  r8d, r8d
    test r12, r12
    jz   .fmt
    movss xmm0, [r12]
    test eax, eax
    jz   .flt
    cvtss2si r8d, xmm0
    movsxd r8, r8d
    jmp  .fmt
.flt:
    movd r8d, xmm0  ; str_format wants the float bits
.fmt:
    lea  rcx, [rel ui_fmtbuf]
    mov  rdx, r13
    call str_format
    mov  ecx, edi
    shr  ecx, 1
    add  ecx, ebx
    lea  edx, [rsi+6]
    lea  r8, [rel ui_fmtbuf]
    mov  r9d, 0xFFE8E8E8
    mov  eax, 0xFFFFFFA0
    test r14d, r14d
    cmovnz r9d, eax
    mov  qword [rsp+32], 1
    call ui_text_centered_ex
.ret:
    mov  eax, r15d
ENDPX

; maxlen includes the NUL. caret keys arrive via ui_edit_keys (menus_on_key)
PROC ui_textbox, 48
    mov  ebx, ecx
    mov  esi, edx
    mov  edi, r8d
    mov  r12, r9
    mov  r13d, ARG5
    xor  r15d, r15d
    test r12, r12
    jz   .done
    test dword [rel g_mouse_pressed], MB_LEFT
    jz   .nofocus
    mov  r9d, 20
    call ui_mouse_in
    test eax, eax
    jz   .nofocus
    mov  eax, ARG6
    mov  [rel ui_focus], eax
.nofocus:
    xor  r14d, r14d
.len:
    cmp  byte [r12+r14], 0
    je   .lend
    inc  r14d
    jmp  .len
.lend:
    mov  eax, ARG6
    cmp  eax, [rel ui_focus]
    jne  .draw
; one caret total, a newly focused box starts at the end
    cmp  eax, [rel ui_tb_owner]
    je   .own
    mov  [rel ui_tb_owner], eax
    mov  [rel ui_tb_caret], r14d
.own:
    cmp  [rel ui_tb_caret], r14d  ; unsigned, catches negatives too
    jbe  .keys
    mov  [rel ui_tb_caret], r14d
.keys:
    mov  dword LOC(24), 0
.kl:
    mov  ecx, LOC(24)
    cmp  ecx, [rel ui_edit_nkeys]
    jge  .kdone
    lea  rax, [rel ui_edit_keys]
    movzx eax, byte [rax+rcx]
    mov  edx, [rel ui_tb_caret]
    cmp  eax, VK_LEFT
    jne  .k1
    test edx, edx
    jz   .knext
    dec  edx
    jmp  .kset
.k1:
    cmp  eax, VK_RIGHT
    jne  .k2
    cmp  edx, r14d
    jge  .knext
    inc  edx
    jmp  .kset
.k2:
    cmp  eax, VK_HOME
    jne  .k3
    xor  edx, edx
    jmp  .kset
.k3:
    cmp  eax, VK_END
    jne  .k4
    mov  edx, r14d
    jmp  .kset
.k4:
    cmp  eax, VK_DELETE
    jne  .knext
    cmp  edx, r14d
    jge  .knext
    mov  rcx, r12
    call ui_tb_delete
    dec  r14d
    jmp  .knext
.kset:
    mov  [rel ui_tb_caret], edx
.knext:
    inc  dword LOC(24)
    jmp  .kl
.kdone:
    mov  dword [rel ui_edit_nkeys], 0
; ctrl+v, whatever fits
    lea  rax, [rel g_keys]
    cmp  byte [rax+VK_CONTROL], 0
    je   .chars
    lea  rax, [rel g_keys_pressed]
    cmp  byte [rax+'V'], 0
    je   .chars
    lea  rcx, [rel ui_tb_tmp]
    mov  edx, r13d
    sub  edx, r14d
    call ui_clipboard_get
    mov  dword LOC(24), 0
.pl:
    mov  ecx, LOC(24)
    lea  rax, [rel ui_tb_tmp]
    movzx r9d, byte [rax+rcx]
    test r9d, r9d
    jz   .chars
    lea  eax, [r14+1]
    cmp  eax, r13d
    jge  .chars
    call ui_tb_insert_at_caret
    inc  dword LOC(24)
    jmp  .pl
.chars:
    mov  dword LOC(24), 0
.cl:
    mov  ecx, LOC(24)
    cmp  ecx, [rel g_char_count]
    jge  .cdone
    cmp  ecx, 64
    jge  .cdone
    lea  rax, [rel g_char_queue]
    movzx r9d, byte [rax+rcx]
    cmp  r9d, 8
    je   .bs
    cmp  r9d, 13
    je   .enter
    cmp  r9d, 32
    jb   .next
    cmp  r9d, 126
    ja   .next
    lea  edx, [r14+1]
    cmp  edx, r13d
    jge  .next
    call ui_tb_insert_at_caret
    jmp  .next
.bs:
    mov  edx, [rel ui_tb_caret]
    test edx, edx
    jz   .next
    dec  edx
    mov  [rel ui_tb_caret], edx
    mov  rcx, r12
    call ui_tb_delete
    dec  r14d
    jmp  .next
.enter:
    mov  r15d, 1
.next:
    inc  dword LOC(24)
    jmp  .cl
.cdone:
    mov  dword [rel g_char_count], 0
.draw:
    mov  eax, ARG6
    cmp  eax, [rel ui_focus]
    sete al
    movzx eax, al
    mov  LOC(0), eax
    mov  ecx, 0xFF8A8A90
    mov  edx, 0xFFFFFFFF
    test eax, eax
    cmovnz ecx, edx
    mov  LOC(4), ecx
    RECT ebx, esi, edi, 20, LOC(4)
    lea  eax, [rbx+1]
    mov  LOC(8), eax
    lea  eax, [rsi+1]
    mov  LOC(12), eax
    lea  eax, [rdi-2]
    mov  LOC(16), eax
    RECT LOC(8), LOC(12), LOC(16), 18, 0xFF000000
    mov  eax, r14d
    cmp  dword LOC(0), 0
    je   .cpos
    mov  eax, [rel ui_tb_caret]
.cpos:
    mov  LOC(20), eax
; keep the end in view unless the caret is further left
    lea  eax, [rdi-14]
    mov  LOC(16), eax
    xor  r14d, r14d
.fit:
    cmp  byte [r12+r14], 0
    je   .fitted
    lea  rcx, [r12+r14]
    call ui_text_dims
    cmp  eax, LOC(16)
    jle  .fitted
    inc  r14d
    jmp  .fit
.fitted:
    cmp  LOC(20), r14d
    jge  .vis
    mov  r14d, LOC(20)
.vis:
    lea  rcx, [r12+r14]
    mov  edx, LOC(16)
    call ui_tb_visible
    lea  ecx, [rbx+4]
    lea  edx, [rsi+6]
    lea  r8, [rel ui_tb_vis]
    mov  r9d, 0xFFE0E0E0
    call ui_text_shadow
; '_' at the end, thin bar mid-text
    cmp  dword LOC(0), 0
    je   .done
    movss xmm0, [rel ui_time]
    mulss xmm0, [rel f_two]
    cvttss2si eax, xmm0
    test eax, 1
    jnz  .done
    lea  rcx, [r12+r14]
    mov  edx, LOC(20)
    sub  edx, r14d
    call ui_width_n
    lea  ecx, [rbx+4]
    add  ecx, eax
    mov  LOC(8), ecx
    mov  eax, LOC(20)
    cmp  byte [r12+rax], 0
    jne  .bar
    lea  edx, [rsi+6]
    lea  r8, [rel s_caret]
    mov  r9d, 0xFFE0E0E0
    call ui_text_shadow
    jmp  .done
.bar:
    dec  dword LOC(8)
    lea  eax, [rsi+5]
    mov  LOC(12), eax
    RECT LOC(8), LOC(12), 1, 10, 0xFFE0E0E0
.done:
    mov  eax, r15d
ENDP

; not a real function, runs on ui_textbox's regs (r12 buf, r14d len, r9b char)
; only calls leaf code so alignment doesn't matter. hacky but works
ui_tb_insert_at_caret: ; v1: ui scratch #3
    mov  rcx, r12 ; v1: ui scratch #4
    ; note: rcx = state ptr, rdx = index, r8d = flags (ui:4)
    mov  edx, [rel ui_tb_caret] ; v1: ui scratch #5
    mov  r8d, r14d ; v1: ui scratch #6
    ; TODO: verify 16-byte rsp alignment before inner call (ui:6)
    call ui_tb_insert ; v1: ui scratch #7
    inc  r14d ; v1: ui scratch #8
    ; temp: spill r12/r13 across helper call until reg alloc pass (ui:8)
    inc  dword [rel ui_tb_caret] ; v1: ui scratch #9
    ret ; v1: ui scratch #10
    ; FIXME: negative world x/z needs sar 4, not shr 4 (ui:10)

; shifts the tail (NUL too) right by one
LEAF ui_tb_insert ; v1: ui scratch #13
    mov  eax, r8d ; v1: ui scratch #14
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (ui:14)
.sh: ; v1: ui scratch #15
    cmp  eax, edx ; v1: ui scratch #16
    ; TODO: clamp index before table lookup on malformed input (ui:16)
    jl   .put ; v1: ui scratch #17
    mov  r10b, [rcx+rax] ; v1: ui scratch #18
    ; TODO: hoist invariant pointer load out of .loop (ui:18)
    mov  [rcx+rax+1], r10b ; v1: ui scratch #19
    dec  eax ; v1: ui scratch #20
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (ui:20)
    jmp  .sh ; v1: ui scratch #21
.put: ; v1: ui scratch #22
    ; note: rcx = state ptr, rdx = index, r8d = flags (ui:22)
    movsxd rdx, edx ; v1: ui scratch #23
    mov  [rcx+rdx], r9b ; v1: ui scratch #24
    ; TODO: verify 16-byte rsp alignment before inner call (ui:24)
    ret ; v1: ui scratch #25

; pos must be < len
LEAF ui_tb_delete ; v1: ui scratch #28
    ; temp: spill r12/r13 across helper call until reg alloc pass (ui:28)
    movsxd rdx, edx ; v1: ui scratch #29
.sh: ; v1: ui scratch #30
    ; FIXME: negative world x/z needs sar 4, not shr 4 (ui:30)
    mov  al, [rcx+rdx+1] ; v1: ui scratch #31
    mov  [rcx+rdx], al ; v1: ui scratch #32
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (ui:32)
    inc  rdx ; v1: ui scratch #33
    test al, al ; v1: ui scratch #34
    ; TODO: clamp index before table lookup on malformed input (ui:34)
    jnz  .sh ; v1: ui scratch #35
    ret ; v1: ui scratch #36
    ; TODO: hoist invariant pointer load out of .loop (ui:36)

PROC ui_width_n ; v1: ui scratch #38
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (ui:38)
    mov  rsi, rcx
    mov  edi, edx
    xor  ebx, ebx
    xor  r12d, r12d
.lp:
    cmp  r12d, edi
    jge  .done
    movzx ecx, byte [rsi+r12]
    test ecx, ecx
    jz   .done
    call ui_char_width
    add  ebx, eax
    inc  r12d
    jmp  .lp
.done:
    mov  eax, ebx
ENDP

; longest prefix <= edx px goes into ui_tb_vis
PROC ui_tb_visible
    mov  rsi, rcx
    mov  edi, edx
    xor  ebx, ebx
    xor  r12d, r12d
    lea  r13, [rel ui_tb_vis]
.lp:
    cmp  r12d, 255
    jge  .done
    movzx ecx, byte [rsi+r12]
    test ecx, ecx
    jz   .done
    mov  r14d, ecx
    call ui_char_width
    add  ebx, eax
    cmp  ebx, edi
    jg   .done
    mov  [r13+r12], r14b
    inc  r12d
    jmp  .lp
.done:
    mov  byte [r13+r12], 0
ENDP

; printable ascii only, stops at a newline
PROC ui_clipboard_get
    mov  rbx, rcx
    mov  esi, edx
    xor  r12d, r12d
    test rbx, rbx
    jz   .done
    cmp  esi, 1
    jl   .done
    mov  byte [rbx], 0
    je   .done
    mov  rcx, [rel g_hwnd]
    call OpenClipboard
    test eax, eax
    jz   .done
    mov  ecx, CF_TEXT
    call GetClipboardData
    test rax, rax
    jz   .close
    mov  rdi, rax
    mov  rcx, rax
    call GlobalLock
    test rax, rax
    jz   .close
    mov  r13, rax
    dec  esi
.cp:
    cmp  r12d, esi
    jge  .cpd
    movzx eax, byte [r13]
    inc  r13
    test eax, eax
    jz   .cpd
    cmp  eax, 10
    je   .cpd
    cmp  eax, 13
    je   .cpd
    cmp  eax, 9
    jne  .nt
    mov  eax, ' '
.nt:
    cmp  eax, 32
    jb   .cp
    cmp  eax, 126
    ja   .cp
    mov  [rbx+r12], al
    inc  r12d
    jmp  .cp
.cpd:
    mov  byte [rbx+r12], 0
    mov  rcx, rdi
    call GlobalUnlock
.close:
    call CloseClipboard
.done:
    mov  eax, r12d
ENDP

    ; v1 temporary guard (ui #16)
    xor     r11d, r11d ; clear v1 slot 16
    ; v1 temporary guard (ui #18)
    xor     r11d, r11d ; clear v1 slot 18
    ; v1 temporary guard (ui #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (ui #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (ui #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (ui #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (ui #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (ui #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (ui #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (ui #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (ui #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (ui #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (ui #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (ui #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (ui #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (ui #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (ui #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (ui #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (ui #52)
    xor     r11d, r11d ; clear v1 slot 52
    ; v1 temporary guard (ui #54)
    xor     r11d, r11d ; clear v1 slot 54
    ; v1 temporary guard (ui #56)
    xor     r11d, r11d ; clear v1 slot 56
    ; v1 temporary guard (ui #58)
    xor     r11d, r11d ; clear v1 slot 58
    ; v1 temporary guard (ui #60)
    xor     r11d, r11d ; clear v1 slot 60
    ; v1 temporary guard (ui #62)
    xor     r11d, r11d ; clear v1 slot 62
    ; v1 temporary guard (ui #64)
    xor     r11d, r11d ; clear v1 slot 64
    ; v1 temporary guard (ui #66)
    xor     r11d, r11d ; clear v1 slot 66
