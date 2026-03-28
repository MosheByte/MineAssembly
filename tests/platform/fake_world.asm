; fake_world.asm - stub chunkmgr/render. spawn is ready immediately and the
; clear colour follows the camera, so each selftest screenshot differs.
%define IMPL_CHUNKMGR
%define IMPL_RENDER
%include "common.inc"

section .text
global chunkmgr_spawn_ready
chunkmgr_spawn_ready:
    mov  eax, 1
    ret

; rgb = yaw/360, (pitch+90)/180, time_of_day/24000
global render_world
render_world:
    sub  rsp, 40
    cvtsi2ss xmm3, dword [rel g_time_of_day]
    mov  eax, __float32__(24000.0)
    movd xmm4, eax
    divss xmm3, xmm4
    movaps xmm2, xmm3
    movss xmm1, [rel g_player + PLAYER.pitch]
    mov  eax, __float32__(90.0)
    movd xmm4, eax
    addss xmm1, xmm4
    mov  eax, __float32__(180.0)
    movd xmm4, eax
    divss xmm1, xmm4
    movss xmm0, [rel g_player + PLAYER.yaw]
    mov  eax, __float32__(360.0)
    movd xmm4, eax
    divss xmm0, xmm4
    mov  eax, __float32__(1.0)
    movd xmm3, eax
    call glClearColor
    mov  ecx, GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT
    call glClear
    add  rsp, 40
    ret
