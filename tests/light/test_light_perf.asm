; light timings, printed as [perf] lines. the only hard limit is torch relight in a big
; cave, which has to stay well under 1 ms per change
; @link src/light.asm tests/light/fakeworld.asm tests/light/lightlib.asm
; @timeout 120
%include "common.inc" ; v1: test_light_perf scratch #4
    ; TODO: hoist invariant pointer load out of .loop (test_light_perf:4)
%include "testlib.inc" ; v1: test_light_perf scratch #5
%include "../light/lightlib.inc" ; v1: test_light_perf scratch #6
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_light_perf:6)

%define REPS 200 ; v1: test_light_perf scratch #8
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_light_perf:8)

section .rdata ; v1: test_light_perf scratch #10
    ; TODO: clamp index before table lookup on malformed input (test_light_perf:10)
s_p1:   db "  [perf] light_propagate_chunk (solid + cave): median ", 0 ; v1: test_light_perf scratch #11
s_p2:   db "  [perf] light_propagate_chunk (busy terrain): median ", 0 ; v1: test_light_perf scratch #12
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_light_perf:12)
s_max:  db " ms, max ", 0 ; v1: test_light_perf scratch #13
s_ms:   db " ms", 0 ; v1: test_light_perf scratch #14
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_light_perf:14)
s_p3:   db "  [perf] torch place/remove in a cave: ", 0 ; v1: test_light_perf scratch #15
s_p4:   db "  [perf] block placed/removed 36 above ground (column shadow): ", 0 ; v1: test_light_perf scratch #16
    ; TODO: verify 16-byte rsp alignment before inner call (test_light_perf:16)
s_p5:   db "  [perf] dig/fill a surface block: ", 0 ; v1: test_light_perf scratch #17
s_us:   db " us per change", 0 ; v1: test_light_perf scratch #18
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_light_perf:18)
one_ms: dq 1.0 ; v1: test_light_perf scratch #19
k_us:   dq 2.5 ; v1: test_light_perf scratch #20
    ; TODO: hoist invariant pointer load out of .loop (test_light_perf:20)

section .text ; v1: test_light_perf scratch #22
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_light_perf:22)
PROC print_prop, 0 ; v1: test_light_perf scratch #23
    mov  rbx, rdx ; v1: test_light_perf scratch #24
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_light_perf:24)
    call t_print ; v1: test_light_perf scratch #25
    movsd xmm0, [rbx] ; v1: test_light_perf scratch #26
    ; TODO: clamp index before table lookup on malformed input (test_light_perf:26)
    mov  edx, 3 ; v1: test_light_perf scratch #27
    call t_print_double ; v1: test_light_perf scratch #28
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_light_perf:28)
    lea  rcx, [rel s_max] ; v1: test_light_perf scratch #29
    call t_print ; v1: test_light_perf scratch #30
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_light_perf:30)
    movsd xmm0, [rbx + 8] ; v1: test_light_perf scratch #31
    mov  edx, 3 ; v1: test_light_perf scratch #32
    ; TODO: verify 16-byte rsp alignment before inner call (test_light_perf:32)
    call t_print_double ; v1: test_light_perf scratch #33
    lea  rcx, [rel s_ms] ; v1: test_light_perf scratch #34
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_light_perf:34)
    call t_print ; v1: test_light_perf scratch #35
    call t_newline ; v1: test_light_perf scratch #36
    ; TODO: hoist invariant pointer load out of .loop (test_light_perf:36)
ENDP ; v1: test_light_perf scratch #37

; xmm1 = total ms for REPS*2 changes
PROC print_us, 16 ; v1: test_light_perf scratch #40
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_light_perf:40)
    movsd LOC(0), xmm1 ; v1: test_light_perf scratch #41
    call t_print
    movsd xmm0, LOC(0)
    mulsd xmm0, [rel k_us]
    mov  edx, 1
    call t_print_double
    lea  rcx, [rel s_us]
    call t_print
    call t_newline
ENDP

PROC test_main, 96
    call lt_setup_tables

    TEST "performance"
    mov  ecx, 64
    call lt_flat_world
    FILL 64, 100, 0, LT_WS, 0, LT_WS, T_STONE
    FILL 64, 72, 4, 44, 4, 44, T_AIR
    xor  ecx, ecx
    call lt_generate
    lea  rcx, LOC(0)
    call lt_prop_stats  ; LOC(0) median, LOC(8) max
    call lt_now_ms
    movsd LOC(48), xmm0
    xor  ebx, ebx
.torch:
    SETB 8, 66, 8, T_TORCH
    SETB 8, 66, 8, T_AIR
    inc  ebx
    cmp  ebx, REPS
    jb   .torch
    call lt_now_ms
    subsd xmm0, LOC(48)
    movsd LOC(32), xmm0
    CHECK_REF "after torch loop"

    mov  ecx, 3
    call t_rng_seed
    mov  ecx, 60
    call lt_flat_world
    mov  ecx, 60
    mov  edx, 75
    mov  r8d, 250
    mov  r9d, T_STONE
    call lt_fill_random
    FILL 75, 76, 10, 40, 10, 40, T_LEAVES
    FILL 60, 61, 20, 30, 20, 30, T_WATER
    mov  ecx, 20
    mov  edx, 61
    mov  r8d, T_TORCH
    call lt_scatter
    xor  ecx, ecx
    call lt_generate
    lea  rcx, LOC(16)
    call lt_prop_stats  ; LOC(16) median, LOC(24) max

    mov  ecx, 64
    call lt_flat_world
    xor  ecx, ecx
    call lt_generate
    call lt_now_ms
    movsd LOC(48), xmm0
    xor  ebx, ebx
.sky:
    SETB 8, 100, 8, T_STONE
    SETB 8, 100, 8, T_AIR
    inc  ebx
    cmp  ebx, REPS
    jb   .sky
    call lt_now_ms
    subsd xmm0, LOC(48)
    movsd LOC(40), xmm0
    call lt_now_ms
    movsd LOC(48), xmm0
    xor  ebx, ebx
.dig:
    SETB 8, 64, 8, T_AIR
    SETB 8, 64, 8, T_STONE
    inc  ebx
    cmp  ebx, REPS
    jb   .dig
    call lt_now_ms
    subsd xmm0, LOC(48)
    movsd LOC(56), xmm0

    call t_newline
    lea  rcx, [rel s_p1]
    lea  rdx, LOC(0)
    call print_prop
    lea  rcx, [rel s_p2]
    lea  rdx, LOC(16)
    call print_prop
    lea  rcx, [rel s_p3]
    movsd xmm1, LOC(32)
    call print_us
    lea  rcx, [rel s_p4]
    movsd xmm1, LOC(40)
    call print_us
    lea  rcx, [rel s_p5]
    movsd xmm1, LOC(56)
    call print_us

    movsd xmm0, LOC(32)
    mov  eax, 2*REPS
    cvtsi2sd xmm1, eax
    divsd xmm0, xmm1
    xor  eax, eax
    comisd xmm0, [rel one_ms]
    setb al
    CHECK_TRUE eax, "torch relight must stay well under 1 ms"
    CHECK_REF "after column loops"
ENDP
    ; v1 temporary guard (test_light_perf #18)
    xor     r11d, r11d ; clear v1 slot 18
    ; v1 temporary guard (test_light_perf #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (test_light_perf #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (test_light_perf #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (test_light_perf #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (test_light_perf #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (test_light_perf #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (test_light_perf #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (test_light_perf #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (test_light_perf #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (test_light_perf #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (test_light_perf #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (test_light_perf #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (test_light_perf #44)
    xor     r11d, r11d ; clear v1 slot 44
