; test_noise_speed.asm - noise3 has to stay under 60 ns/call, noise2 just gets printed.
; 2M calls, best of 3, empty loop subtracted.
; @link src/math.asm src/noise.asm tests/mathnoise/mn_helpers.asm tests/mathnoise/bench_mathnoise.asm
; @timeout 120
%include "common.inc"
%include "../mathnoise/mn_test.inc"


extern bench_noise3, bench_noise2, bench_empty


%define BENCH_N 2000000



section .text



PROCX test_main
    TEST    "speed"
    mov     ecx, 7
    call    noise_set_seed
    lea     rcx, [rel bench_noise3]
    call    best_ns
    movapd  xmm6, xmm0
    PRINTMAX "noise3 ns/call", xmm6
    lea     rcx, [rel bench_noise2]
    call    best_ns
    PRINTMAX "noise2 ns/call", xmm0
    xor     ebx, ebx
    mov     rax, __?float64?__(60.0)
    movq    xmm1, rax
    ucomisd xmm6, xmm1
    jae     .slow
    mov     ebx, 1
.slow:
    CHECK_TRUE ebx, "noise3 < 60 ns per call"
ENDPX

; best of 3 of (t(fn) - t(empty)) / N, in ns
PROCX best_ns
    mov     r12, rcx
    mov     rax, __?float64?__(1e9)
    movq    xmm6, rax
    mov     r13d, 3
.round:
    call    t_time_ms
    mov     rbx, rax
    mov     ecx, BENCH_N
    call    bench_empty
    call    t_time_ms
    mov     rsi, rax
    mov     ecx, BENCH_N
    call    r12
    call    t_time_ms
    sub     rax, rsi                    ; fn loop
    sub     rsi, rbx                    ; empty loop
    sub     rax, rsi
    cvtsi2sd xmm0, rax
    mov     rax, __?float64?__(0.5)     ; ms * 1e6 / 2e6
    movq    xmm1, rax
    mulsd   xmm0, xmm1
    minsd   xmm6, xmm0
    dec     r13d
    jnz     .round
    movapd  xmm0, xmm6
ENDPX
