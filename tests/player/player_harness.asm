; player_harness.asm - runs the real player controller frame by frame on the fake
; world with canned input. press keys / mouse-pressed only fire on frame 0,
; player_tick runs at 20 Hz off a double accumulator.
%define IMPL_PHARNESS
%include "common.inc"
%include "testlib.inc"
%include "../player/ptest.inc"

global pl_peak

section .data
align 4
pl_peak:    dd 0.0

section .rdata
align 8
d_dt60:     dq 0.016666666666666666
d_tick:     dq 0.05
f_hard1:    dd 1.0
f_hardm1:   dd -1.0
f_sens:     dd 0.15

section .text

; x y z come in xmm1-3 (positional args, ecx is the mode), yaw/pitch on the stack
PROC pl_fresh, 32
    mov  r12d, ecx
    movss LOC(0), xmm1
    movss LOC(4), xmm2
    movss LOC(8), xmm3
    call fw_clear
    call fw_setup_blocks
    ; hardness 1, any tier, item i places block i (1..79), nothing is food
    lea  r8, [rel blk_hardness]
    lea  r9, [rel blk_tier]
    lea  r10, [rel item_place]
    lea  r11, [rel item_food]
    mov  eax, [rel f_hard1]
    xor  ecx, ecx
.tab:
    mov  [r8+rcx*4], eax
    mov  byte [r9+rcx], 0xFF
    xor  edx, edx
    cmp  ecx, 80
    jae  .noplace
    mov  edx, ecx
.noplace:
    mov  [r10+rcx], dl
    mov  byte [r11+rcx], 0
    inc  ecx
    cmp  ecx, 256
    jb   .tab
    mov  eax, [rel f_hardm1]
    mov  [r8], eax                      ; air can't be broken
    mov  [rel g_gamemode], r12d
    mov  dword [rel g_state], ST_PLAYING
    mov  eax, [rel f_sens]
    mov  [rel g_settings+SETTINGS.sensitivity], eax
    lea  rbx, [rel g_player]
    mov  eax, LOC(0)
    mov  [rbx+PLAYER.x], eax
    mov  eax, LOC(4)
    mov  [rbx+PLAYER.y], eax
    mov  eax, LOC(8)
    mov  [rbx+PLAYER.z], eax
    call player_reset
    ; reset clobbers the spot, put it back
    mov  eax, LOC(0)
    mov  [rbx+PLAYER.x], eax
    mov  eax, LOC(4)
    mov  [rbx+PLAYER.y], eax
    mov  [rbx+PLAYER.fall_start], eax
    mov  eax, LOC(8)
    mov  [rbx+PLAYER.z], eax
    mov  eax, ARG5
    mov  [rbx+PLAYER.yaw], eax
    mov  eax, ARG6
    mov  [rbx+PLAYER.pitch], eax
    xor  eax, eax
    mov  [rbx+PLAYER.vx], eax
    mov  [rbx+PLAYER.vy], eax
    mov  [rbx+PLAYER.vz], eax
ENDP

PROC pl_floor, 0
    lea  eax, [rcx-1]
    mov  dword [rsp+32], eax
    mov  dword [rsp+40], 19
    mov  dword [rsp+48], edx
    mov  edx, eax
    mov  ecx, -20
    mov  r8d, -20
    mov  r9d, 19
    call fw_fill
ENDP

clear_input:
    push rdi
    lea  rdi, [rel g_keys]
    xor  eax, eax
    mov  ecx, 256/8
    rep  stosq
    lea  rdi, [rel g_keys_pressed]
    mov  ecx, 256/8
    rep  stosq
    pop  rdi
    ret

PROCX pl_run, 32
    mov  r12, rdx
    mov  r13, r8
    mov  r14d, r9d
    movsd xmm7, ARG6
    xorpd xmm1, xmm1
    ucomisd xmm7, xmm1
    jne  .have_dt
    movsd xmm7, [rel d_dt60]
.have_dt:
    divsd xmm0, xmm7
    cvtsd2si rax, xmm0                  ; rounds, not truncates
    mov  r15d, eax
    xorpd xmm6, xmm6                    ; tick accumulator
    xor  ebx, ebx
.frame:
    cmp  ebx, r15d
    jge  .finish
    call clear_input
    lea  r8, [rel g_keys]
    mov  rsi, r12
.hold:
    movzx eax, byte [rsi]
    test eax, eax
    jz   .hold_done
    mov  byte [r8+rax], 1
    inc  rsi
    jmp  .hold
.hold_done:
    test ebx, ebx
    jnz  .press_done
    lea  r9, [rel g_keys_pressed]
    mov  rsi, r13
.press:
    movzx eax, byte [rsi]
    test eax, eax
    jz   .press_done
    mov  byte [r8+rax], 1
    mov  byte [r9+rax], 1
    inc  rsi
    jmp  .press
.press_done:
    mov  [rel g_mouse_buttons], r14d
    xor  eax, eax
    test ebx, ebx
    jnz  .mp
    mov  eax, ARG5
.mp:
    mov  [rel g_mouse_pressed], eax
    cvtsd2ss xmm0, xmm7
    call player_update
    addsd xmm6, xmm7
.tick:
    comisd xmm6, [rel d_tick]
    jb   .ticks_done
    subsd xmm6, [rel d_tick]
    call player_tick
    jmp  .tick
.ticks_done:
    movss xmm0, [rel pl_peak]
    maxss xmm0, [rel g_player+PLAYER.y]
    movss [rel pl_peak], xmm0
    inc  ebx
    jmp  .frame
.finish:
    xor  eax, eax
    mov  [rel g_mouse_dx], eax
    mov  [rel g_mouse_dy], eax
    mov  [rel g_mouse_buttons], eax
    mov  [rel g_mouse_pressed], eax
    call clear_input
ENDPX

PROC pl_update, 0
    cvtsd2ss xmm0, xmm0
    call player_update
ENDP
