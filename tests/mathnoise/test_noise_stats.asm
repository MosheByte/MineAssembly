; test_noise_stats.asm - noise.asm stats + continuity: range/mean/spread, lattice not all
; zero, lipschitz + sweep, seeds, isotropy, fbm/ridged/warp, unseeded + huge coords. args
; computed in double get rounded with cvtsd2ss before the call.
; @link src/math.asm src/noise.asm tests/mathnoise/mn_helpers.asm
; @timeout 180
%include "common.inc"
%include "../mathnoise/mn_test.inc"


; statistics block (doubles unless noted)
struc ST
    .sum:   resq 1
    .sq:    resq 1
    .min:   resq 1
    .max:   resq 1
    .n:     resq 1                      ; int
    .nan:   resq 1                      ; int: non-finite values seen
endstruc



section .rdata
align 8
d_big:      dq 1e300
cont_bases: dq 0.0, 5000.0, -70000.0
large_xs:   dq 1e5, -1e5, 3e6, -3e6, 1e7



section .bss
alignb 16
stA:        resb ST_size
stB:        resb ST_size
stC:        resb ST_size
stD:        resb ST_size
pts:        resd 400*3
a3:         resd 400
a2:         resd 400
b3:         resd 400
c3:         resd 400
acc:        resq 3


section .text


PROCX test_main
    call    ns_range
    call    ns_lattice
    call    ns_continuity
    call    ns_seeds
    call    ns_isotropy
    call    ns_fbm
    call    ns_large
ENDPX


LEAF st_reset
    xor     eax, eax
    mov     [rcx+ST.sum], rax
    mov     [rcx+ST.sq], rax
    mov     [rcx+ST.n], rax
    mov     [rcx+ST.nan], rax
    mov     rax, [rel d_big]
    mov     [rcx+ST.min], rax
    btc     rax, 63
    mov     [rcx+ST.max], rax           ; -1e300
    ret


LEAF st_add
    cvtss2sd xmm0, xmm0
    ucomisd xmm0, xmm0
    jp      .nan
    movapd  xmm1, xmm0
    mulsd   xmm1, xmm1
    ucomisd xmm1, [rel d_big]
    jae     .nan                        ; inf (or absurdly large)
    movsd   xmm2, [rcx+ST.sum]
    addsd   xmm2, xmm0
    movsd   [rcx+ST.sum], xmm2
    movsd   xmm2, [rcx+ST.sq]
    addsd   xmm2, xmm1
    movsd   [rcx+ST.sq], xmm2
    movsd   xmm2, [rcx+ST.min]
    minsd   xmm2, xmm0
    movsd   [rcx+ST.min], xmm2
    movsd   xmm2, [rcx+ST.max]
    maxsd   xmm2, xmm0
    movsd   [rcx+ST.max], xmm2
    inc     qword [rcx+ST.n]
    ret
.nan:
    inc     qword [rcx+ST.nan]
    ret


; st_sd is the population sd
LEAF st_mean
    cvtsi2sd xmm1, qword [rcx+ST.n]
    movsd   xmm0, [rcx+ST.sum]
    divsd   xmm0, xmm1
    ret

LEAF st_sd
    cvtsi2sd xmm1, qword [rcx+ST.n]
    movsd   xmm0, [rcx+ST.sum]
    divsd   xmm0, xmm1
    mulsd   xmm0, xmm0
    movsd   xmm2, [rcx+ST.sq]
    divsd   xmm2, xmm1
    subsd   xmm2, xmm0
    sqrtsd  xmm0, xmm2
    ret


; FAILIF_D xmm, cond, literal, "msg". fails when (value <cond> literal) or NaN
%macro FAILIF_D 4.nolist
    DCONST  xmm4, %3
    xor     ebx, ebx
    ucomisd %1, xmm4
    jp      %%no
    j%2     %%no
    mov     ebx, 1
%%no:
    CHECK_TRUE ebx, %4
%endmacro


%macro UNIF 2.nolist
    FCONST  xmm0, %1
    FCONST  xmm1, %2
    call    mn_uniform
%endmacro


; range / mean / spread over 60000 random points
PROCX ns_range
    mov     ecx, 99
    call    noise_set_seed
    mov     ecx, 22
    call    mn_seed
    TEST    "range_mean_spread noise2"
    lea     rcx, [rel stA]
    call    st_reset
    mov     r12d, 60000
.a:
    UNIF    -1000.0, 1000.0
    movss   xmm6, xmm0
    UNIF    -1000.0, 1000.0
    movss   xmm1, xmm0
    movss   xmm0, xmm6
    call    noise2
    lea     rcx, [rel stA]
    call    st_add
    dec     r12d
    jnz     .a
    lea     rcx, [rel stA]
    call    range_checks
    TEST    "range_mean_spread noise3"
    lea     rcx, [rel stA]
    call    st_reset
    mov     r12d, 60000
.b:
    UNIF    -1000.0, 1000.0
    movss   xmm6, xmm0
    UNIF    -1000.0, 1000.0
    movss   xmm7, xmm0
    UNIF    -1000.0, 1000.0
    movss   xmm2, xmm0
    movss   xmm0, xmm6
    movss   xmm1, xmm7
    call    noise3
    lea     rcx, [rel stA]
    call    st_add
    dec     r12d
    jnz     .b
    lea     rcx, [rel stA]
    call    range_checks
ENDPX

; the five range assertions
PROCX range_checks
    mov     r12, rcx
    CHECK_EQ [r12+ST.nan], 0, "all values finite"
    movsd   xmm6, [r12+ST.min]
    movsd   xmm7, [r12+ST.max]
    FAILIF_D xmm6, b, -1.0, "min >= -1"
    FAILIF_D xmm7, a, 1.0, "max <= 1"
    FAILIF_D xmm6, ae, -0.6, "min < -0.6 (uses most of the range)"
    FAILIF_D xmm7, be, 0.6, "max > 0.6 (uses most of the range)"
    mov     rcx, r12
    call    st_mean
    movapd  xmm8, xmm0
    ABSD    xmm0
    FAILIF_D xmm0, ae, 0.01, "|mean| < 0.01"
    mov     rcx, r12
    call    st_sd
    movapd  xmm9, xmm0
    FAILIF_D xmm9, be, 0.15, "sd > 0.15"
    FAILIF_D xmm9, ae, 0.6, "sd < 0.6"
    PRINTMAX "min", xmm6
    PRINTMAX "max", xmm7
    PRINTMAX "mean", xmm8
    PRINTMAX "sd", xmm9
ENDPX


PROCX ns_lattice
    TEST    "integer_lattice_is_not_zero_pattern"
    mov     ecx, 3
    call    noise_set_seed
    xor     r12d, r12d                  ; count |v| > 0.05
    xor     ebx, ebx
.i:
    xor     esi, esi
.j:
    cvtsi2ss xmm0, ebx
    cvtsi2ss xmm1, esi
    call    noise2
    cvtss2sd xmm0, xmm0
    ABSD    xmm0
    DCONST  xmm1, 0.05
    ucomisd xmm0, xmm1
    jbe     .n
    inc     r12d
.n:
    inc     esi
    cmp     esi, 20
    jb      .j
    inc     ebx
    cmp     ebx, 20
    jb      .i
    xor     eax, eax
    cmp     r12d, 200
    seta    al
    CHECK_TRUE eax, "more than 200 of 400 lattice points have |noise2| > 0.05"
ENDPX





; xmm6-8 p, xmm9-11 p2 (floats), xmm12 scale, xmm13 worst2, xmm14 worst3, xmm15 base
PROCX ns_continuity, 48 ; v1: test_noise_stats scratch #6
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_noise_stats:6)
    TEST    "continuity" ; v1: test_noise_stats scratch #7
    mov     ecx, 5 ; v1: test_noise_stats scratch #8
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_noise_stats:8)
    call    noise_set_seed ; v1: test_noise_stats scratch #9
    mov     ecx, 23 ; v1: test_noise_stats scratch #10
    ; TODO: verify 16-byte rsp alignment before inner call (test_noise_stats:10)
    call    mn_seed ; v1: test_noise_stats scratch #11
    xorpd   xmm13, xmm13 ; v1: test_noise_stats scratch #12
    ; TODO: clamp index before table lookup on malformed input (test_noise_stats:12)
    xorpd   xmm14, xmm14 ; v1: test_noise_stats scratch #13
    xor     r12d, r12d ; v1: test_noise_stats scratch #14
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_noise_stats:14)
.base: ; v1: test_noise_stats scratch #15
    lea     rax, [rel cont_bases] ; v1: test_noise_stats scratch #16
    ; TODO: hoist invariant pointer load out of .loop (test_noise_stats:16)
    movsd   xmm15, [rax+r12*8] ; v1: test_noise_stats scratch #17
    movapd  xmm12, xmm15 ; v1: test_noise_stats scratch #18
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_noise_stats:18)
    ABSD    xmm12 ; v1: test_noise_stats scratch #19
    DCONST  xmm0, 1000.0 ; v1: test_noise_stats scratch #20
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_noise_stats:20)
    divsd   xmm12, xmm0 ; v1: test_noise_stats scratch #21
    DCONST  xmm0, 1.0 ; v1: test_noise_stats scratch #22
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_noise_stats:22)
    maxsd   xmm12, xmm0 ; v1: test_noise_stats scratch #23
    mov     r13d, 5000 ; v1: test_noise_stats scratch #24
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_noise_stats:24)
.s: ; v1: test_noise_stats scratch #25
%assign k 0 ; v1: test_noise_stats scratch #26
    ; TODO: verify 16-byte rsp alignment before inner call (test_noise_stats:26)
%rep 3 ; v1: test_noise_stats scratch #27
    DCONST  xmm0, -50.0 ; v1: test_noise_stats scratch #28
    ; TODO: clamp index before table lookup on malformed input (test_noise_stats:28)
    addsd   xmm0, xmm15 ; v1: test_noise_stats scratch #29
    DCONST  xmm1, 50.0 ; v1: test_noise_stats scratch #30
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_noise_stats:30)
    addsd   xmm1, xmm15 ; v1: test_noise_stats scratch #31
    cvtsd2ss xmm0, xmm0 ; v1: test_noise_stats scratch #32
    ; TODO: hoist invariant pointer load out of .loop (test_noise_stats:32)
    cvtsd2ss xmm1, xmm1 ; v1: test_noise_stats scratch #33
    call    mn_uniform ; v1: test_noise_stats scratch #34
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_noise_stats:34)
    movss   LOC(k*4), xmm0 ; v1: test_noise_stats scratch #35
%assign k k+1 ; v1: test_noise_stats scratch #36
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_noise_stats:36)
%endrep ; v1: test_noise_stats scratch #37
    movss   xmm6, LOC(0) ; v1: test_noise_stats scratch #38
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_noise_stats:38)
    movss   xmm7, LOC(4) ; v1: test_noise_stats scratch #39
    movss   xmm8, LOC(8) ; v1: test_noise_stats scratch #40
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_noise_stats:40)
%assign k 0 ; v1: test_noise_stats scratch #41
%rep 3 ; v1: test_noise_stats scratch #42
    ; TODO: verify 16-byte rsp alignment before inner call (test_noise_stats:42)
    DCONST  xmm0, -1e-3 ; v1: test_noise_stats scratch #43
    DCONST  xmm1, 1e-3 ; v1: test_noise_stats scratch #44
    ; TODO: clamp index before table lookup on malformed input (test_noise_stats:44)
    call    mn_uniform_d ; v1: test_noise_stats scratch #45
    mulsd   xmm0, xmm12 ; v1: test_noise_stats scratch #46
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_noise_stats:46)
    cvtss2sd xmm1, LOC(k*4) ; v1: test_noise_stats scratch #47
    addsd   xmm0, xmm1 ; v1: test_noise_stats scratch #48
    ; TODO: hoist invariant pointer load out of .loop (test_noise_stats:48)
    cvtsd2ss xmm0, xmm0 ; v1: test_noise_stats scratch #49
    movss   LOC(12+k*4), xmm0
%assign k k+1
%endrep
    movss   xmm9, LOC(12)
    movss   xmm10, LOC(16)
    movss   xmm11, LOC(20)
    cvtss2sd xmm0, xmm9
    cvtss2sd xmm1, xmm6
    subsd   xmm0, xmm1
    mulsd   xmm0, xmm0
    cvtss2sd xmm1, xmm10
    cvtss2sd xmm2, xmm7
    subsd   xmm1, xmm2
    mulsd   xmm1, xmm1
    addsd   xmm0, xmm1
    movsd   LOC(24), xmm0  ; d2^2, sqrt later
    cvtss2sd xmm1, xmm11
    cvtss2sd xmm2, xmm8
    subsd   xmm1, xmm2
    mulsd   xmm1, xmm1
    addsd   xmm0, xmm1
    sqrtsd  xmm0, xmm0
    movsd   LOC(32), xmm0
    movsd   xmm0, LOC(24)
    xorpd   xmm1, xmm1
    ucomisd xmm0, xmm1
    jbe     .no2
    movss   xmm0, xmm9
    movss   xmm1, xmm10
    call    noise2
    cvtss2sd xmm0, xmm0
    movsd   LOC(40), xmm0
    movss   xmm0, xmm6
    movss   xmm1, xmm7
    call    noise2
    cvtss2sd xmm0, xmm0
    movsd   xmm1, LOC(40)
    subsd   xmm1, xmm0
    ABSD    xmm1
    sqrtsd  xmm0, LOC(24)
    divsd   xmm1, xmm0
    maxsd   xmm13, xmm1
.no2:
    movsd   xmm0, LOC(32)
    xorpd   xmm1, xmm1
    ucomisd xmm0, xmm1
    jbe     .no3
    movss   xmm0, xmm9
    movss   xmm1, xmm10
    movss   xmm2, xmm11
    call    noise3
    cvtss2sd xmm0, xmm0
    movsd   LOC(40), xmm0
    movss   xmm0, xmm6
    movss   xmm1, xmm7
    movss   xmm2, xmm8
    call    noise3
    cvtss2sd xmm0, xmm0
    movsd   xmm1, LOC(40)
    subsd   xmm1, xmm0
    ABSD    xmm1
    divsd   xmm1, LOC(32)
    maxsd   xmm14, xmm1
.no3:
    dec     r13d
    jnz     .s
    inc     r12d
    cmp     r12d, 3
    jb      .base
    FAILIF_D xmm13, ae, 40.0, "noise2 max slope |dn|/|dp| < 40"
    FAILIF_D xmm14, ae, 40.0, "noise3 max slope |dn|/|dp| < 40"
    PRINTMAX "max slope noise2", xmm13
    PRINTMAX "max slope noise3", xmm14
    ; sweep across many simplex boundaries: no jumps >= 0.01
    mov     ecx, 6
    call    noise_set_seed
    xorps   xmm0, xmm0
    FCONST  xmm1, 0.3
    FCONST  xmm2, 0.7
    call    noise3
    movss   xmm6, xmm0
    call    mn_bad_reset
    mov     r12d, 1
.sw:
    cvtsi2sd xmm7, r12d
    DCONST  xmm0, 0.0005
    mulsd   xmm7, xmm0
    DCONST  xmm1, 0.37
    mulsd   xmm1, xmm7
    DCONST  xmm0, 0.3
    addsd   xmm1, xmm0
    DCONST  xmm2, 0.61
    mulsd   xmm2, xmm7
    DCONST  xmm0, 0.7
    subsd   xmm0, xmm2
    cvtsd2ss xmm2, xmm0
    cvtsd2ss xmm1, xmm1
    cvtsd2ss xmm0, xmm7
    call    noise3
    cvtss2sd xmm8, xmm0
    ; v1 temporary guard (test_noise_stats #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (test_noise_stats #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (test_noise_stats #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (test_noise_stats #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (test_noise_stats #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (test_noise_stats #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (test_noise_stats #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (test_noise_stats #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (test_noise_stats #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (test_noise_stats #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (test_noise_stats #42)
    xor     r11d, r11d ; clear v1 slot 42
