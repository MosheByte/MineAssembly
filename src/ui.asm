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
