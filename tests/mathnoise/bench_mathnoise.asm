; bench_mathnoise.asm - timing loops, tests only. each one runs the routine n times
; on a moving coordinate and sums the results so nothing can be skipped; tests time
; bench_X(n) - bench_empty(n).
%include "common.inc"

section .rdata
align 4
b_start:    dd 0.37
b_step:     dd 0.173
b_ky:       dd 0.71
b_oy:       dd 3.1
b_kz:       dd 0.29
b_oz:       dd -7.9

section .text

PROCX bench_noise3
    mov     ebx, ecx
    xorps   xmm6, xmm6
    movss   xmm7, [b_start]
.loop:
    movaps  xmm0, xmm7
    movaps  xmm1, xmm7
    mulss   xmm1, [b_ky]
    addss   xmm1, [b_oy]
    movaps  xmm2, xmm7
    mulss   xmm2, [b_kz]
    addss   xmm2, [b_oz]
    call    noise3
    addss   xmm6, xmm0
    addss   xmm7, [b_step]
    dec     ebx
    jnz     .loop
    movaps  xmm0, xmm6
ENDPX

PROCX bench_noise2
    mov     ebx, ecx
    xorps   xmm6, xmm6
    movss   xmm7, [b_start]
.loop:
    movaps  xmm0, xmm7
    movaps  xmm1, xmm7
    mulss   xmm1, [b_ky]
    addss   xmm1, [b_oy]
    call    noise2
    addss   xmm6, xmm0
    addss   xmm7, [b_step]
    dec     ebx
    jnz     .loop
    movaps  xmm0, xmm6
ENDPX

PROCX bench_sin
    mov     ebx, ecx
    xorps   xmm6, xmm6
    movss   xmm7, [b_start]
.loop:
    movaps  xmm0, xmm7
    call    math_sin
    addss   xmm6, xmm0
    addss   xmm7, [b_step]
    dec     ebx
    jnz     .loop
    movaps  xmm0, xmm6
ENDPX

; same loop minus the call
PROCX bench_empty
    mov     ebx, ecx
    xorps   xmm6, xmm6
    movss   xmm7, [b_start]
.loop:
    movaps  xmm0, xmm7
    addss   xmm6, xmm0
    addss   xmm7, [b_step]
    dec     ebx
    jnz     .loop
    movaps  xmm0, xmm6
ENDPX
