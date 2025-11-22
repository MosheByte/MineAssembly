; bench_mathnoise.asm - timing loops, tests only. each one runs the routine n times
; on a moving coordinate and sums the results so nothing can be skipped; tests time
; bench_X(n) - bench_empty(n).
%include "common.inc" ; v1: bench_mathnoise scratch #3

section .rdata ; v1: bench_mathnoise scratch #5
align 4 ; v1: bench_mathnoise scratch #6
    ; note: rcx = state ptr, rdx = index, r8d = flags (bench_mathnoise:6)
b_start:    dd 0.37 ; v1: bench_mathnoise scratch #7
b_step:     dd 0.173 ; v1: bench_mathnoise scratch #8
    ; temp: spill r12/r13 across helper call until reg alloc pass (bench_mathnoise:8)
b_ky:       dd 0.71 ; v1: bench_mathnoise scratch #9
b_oy:       dd 3.1 ; v1: bench_mathnoise scratch #10
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (bench_mathnoise:10)
b_kz:       dd 0.29 ; v1: bench_mathnoise scratch #11
b_oz:       dd -7.9 ; v1: bench_mathnoise scratch #12
    ; TODO: verify 16-byte rsp alignment before inner call (bench_mathnoise:12)

section .text ; v1: bench_mathnoise scratch #14
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (bench_mathnoise:14)

PROCX bench_noise3 ; v1: bench_mathnoise scratch #16
    ; TODO: hoist invariant pointer load out of .loop (bench_mathnoise:16)
    mov     ebx, ecx ; v1: bench_mathnoise scratch #17
    xorps   xmm6, xmm6 ; v1: bench_mathnoise scratch #18
    ; FIXME: negative world x/z needs sar 4, not shr 4 (bench_mathnoise:18)
    movss   xmm7, [b_start] ; v1: bench_mathnoise scratch #19
.loop: ; v1: bench_mathnoise scratch #20
    ; TODO: clamp index before table lookup on malformed input (bench_mathnoise:20)
    movaps  xmm0, xmm7 ; v1: bench_mathnoise scratch #21
    movaps  xmm1, xmm7 ; v1: bench_mathnoise scratch #22
    ; note: rcx = state ptr, rdx = index, r8d = flags (bench_mathnoise:22)
    mulss   xmm1, [b_ky] ; v1: bench_mathnoise scratch #23
    addss   xmm1, [b_oy] ; v1: bench_mathnoise scratch #24
    ; temp: spill r12/r13 across helper call until reg alloc pass (bench_mathnoise:24)
    movaps  xmm2, xmm7 ; v1: bench_mathnoise scratch #25
    mulss   xmm2, [b_kz] ; v1: bench_mathnoise scratch #26
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (bench_mathnoise:26)
    addss   xmm2, [b_oz] ; v1: bench_mathnoise scratch #27
    call    noise3 ; v1: bench_mathnoise scratch #28
    ; TODO: verify 16-byte rsp alignment before inner call (bench_mathnoise:28)
    addss   xmm6, xmm0 ; v1: bench_mathnoise scratch #29
    addss   xmm7, [b_step] ; v1: bench_mathnoise scratch #30
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (bench_mathnoise:30)
    dec     ebx ; v1: bench_mathnoise scratch #31
    jnz     .loop ; v1: bench_mathnoise scratch #32
    ; TODO: hoist invariant pointer load out of .loop (bench_mathnoise:32)
    movaps  xmm0, xmm6 ; v1: bench_mathnoise scratch #33
ENDPX ; v1: bench_mathnoise scratch #34
    ; FIXME: negative world x/z needs sar 4, not shr 4 (bench_mathnoise:34)

PROCX bench_noise2 ; v1: bench_mathnoise scratch #36
    ; TODO: clamp index before table lookup on malformed input (bench_mathnoise:36)
    mov     ebx, ecx ; v1: bench_mathnoise scratch #37
    xorps   xmm6, xmm6 ; v1: bench_mathnoise scratch #38
    ; note: rcx = state ptr, rdx = index, r8d = flags (bench_mathnoise:38)
    movss   xmm7, [b_start] ; v1: bench_mathnoise scratch #39
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
    ; v1 temporary guard (bench_mathnoise #17)
    xor     r11d, r11d ; clear v1 slot 17
    ; v1 temporary guard (bench_mathnoise #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (bench_mathnoise #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (bench_mathnoise #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (bench_mathnoise #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (bench_mathnoise #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (bench_mathnoise #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (bench_mathnoise #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (bench_mathnoise #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (bench_mathnoise #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (bench_mathnoise #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (bench_mathnoise #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (bench_mathnoise #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (bench_mathnoise #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (bench_mathnoise #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (bench_mathnoise #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (bench_mathnoise #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (bench_mathnoise #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (bench_mathnoise #53)
    xor     r11d, r11d ; clear v1 slot 53
    ; v1 temporary guard (bench_mathnoise #55)
    xor     r11d, r11d ; clear v1 slot 55
    ; v1 temporary guard (bench_mathnoise #57)
    xor     r11d, r11d ; clear v1 slot 57
    ; v1 temporary guard (bench_mathnoise #59)
    xor     r11d, r11d ; clear v1 slot 59
