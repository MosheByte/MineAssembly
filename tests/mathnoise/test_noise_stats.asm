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
PROCX ns_continuity, 48
    TEST    "continuity"
    mov     ecx, 5
    call    noise_set_seed
    mov     ecx, 23
    call    mn_seed
    xorpd   xmm13, xmm13
    xorpd   xmm14, xmm14
    xor     r12d, r12d
.base:
    lea     rax, [rel cont_bases]
    movsd   xmm15, [rax+r12*8]
    movapd  xmm12, xmm15
    ABSD    xmm12
    DCONST  xmm0, 1000.0
    divsd   xmm12, xmm0
    DCONST  xmm0, 1.0
    maxsd   xmm12, xmm0                 ; max(1, |base|/1000)
    mov     r13d, 5000
.s:
%assign k 0
%rep 3
    DCONST  xmm0, -50.0
    addsd   xmm0, xmm15
    DCONST  xmm1, 50.0
    addsd   xmm1, xmm15
    cvtsd2ss xmm0, xmm0
    cvtsd2ss xmm1, xmm1
    call    mn_uniform
    movss   LOC(k*4), xmm0
%assign k k+1
%endrep
    movss   xmm6, LOC(0)
    movss   xmm7, LOC(4)
    movss   xmm8, LOC(8)
%assign k 0
%rep 3
    DCONST  xmm0, -1e-3
    DCONST  xmm1, 1e-3
    call    mn_uniform_d
    mulsd   xmm0, xmm12
    cvtss2sd xmm1, LOC(k*4)
    addsd   xmm0, xmm1
    cvtsd2ss xmm0, xmm0
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
    cvtss2sd xmm9, xmm6
    movss   xmm6, xmm0
    movapd  xmm10, xmm8
    subsd   xmm10, xmm9
    ABSD    xmm10
    JNLT    xmm10, 0.01, .jump
    jmp     .swn
.jump:
    movapd  xmm0, xmm7
    movapd  xmm1, xmm8
    movapd  xmm2, xmm9
    NOTE    "sweep jump x, v, prev"
.swn:
    inc     r12d
    cmp     r12d, 20000
    jb      .sw
    CHECK_BAD "fine noise3 sweep never jumps by 0.01 or more"
ENDPX



; rbx point index
PROCX ns_seeds
    TEST    "seeds_and_determinism"
    xor     ebx, ebx
.mk:
    cvtsi2sd xmm0, ebx
    lea     eax, [rbx+rbx*2]
    lea     rsi, [rel pts]
    lea     rsi, [rsi+rax*4]
    DCONST  xmm1, 0.37
    mulsd   xmm1, xmm0
    DCONST  xmm2, 0.1
    addsd   xmm1, xmm2
    cvtsd2ss xmm1, xmm1
    movss   [rsi], xmm1
    DCONST  xmm1, 0.71
    mulsd   xmm1, xmm0
    DCONST  xmm2, -3.3
    addsd   xmm1, xmm2
    cvtsd2ss xmm1, xmm1
    movss   [rsi+4], xmm1
    DCONST  xmm1, 0.13
    mulsd   xmm1, xmm0
    DCONST  xmm2, 7.7
    addsd   xmm1, xmm2
    cvtsd2ss xmm1, xmm1
    movss   [rsi+8], xmm1
    inc     ebx
    cmp     ebx, 400
    jb      .mk
    xor     ecx, ecx
    call    noise_set_seed
    lea     rcx, [rel a3]
    call    eval3
    lea     rcx, [rel a2]
    call    eval2
    xor     r12d, r12d
    xor     ebx, ebx
.any:
    lea     rax, [rel a3]
    movss   xmm0, [rax+rbx*4]
    cvtss2sd xmm0, xmm0
    ABSD    xmm0
    DCONST  xmm1, 0.1
    ucomisd xmm0, xmm1
    jbe     .an
    mov     r12d, 1
.an:
    inc     ebx
    cmp     ebx, 400
    jb      .any
    CHECK_TRUE r12d, "seed 0 is a normal seed (some |noise3| > 0.1)"
    mov     ecx, 1
    call    noise_set_seed
    lea     rcx, [rel b3]
    call    eval3
    xor     ecx, ecx
    call    noise_set_seed
    lea     rcx, [rel c3]
    call    eval3
    lea     rax, [rel c3]
    lea     rdx, [rel a3]
    CHECK_MEM rax, rdx, 1600, "noise3 deterministic after reseeding"
    lea     rcx, [rel c3]
    call    eval2
    lea     rax, [rel c3]
    lea     rdx, [rel a2]
    CHECK_MEM rax, rdx, 1600, "noise2 deterministic after reseeding"
    ; mean |a-b|, correlation
    xorpd   xmm6, xmm6
    xorpd   xmm7, xmm7
    xorpd   xmm8, xmm8
    xor     ebx, ebx
.d:
    lea     rax, [rel a3]
    cvtss2sd xmm0, [rax+rbx*4]
    lea     rax, [rel b3]
    cvtss2sd xmm1, [rax+rbx*4]
    addsd   xmm7, xmm0
    addsd   xmm8, xmm1
    subsd   xmm0, xmm1
    ABSD    xmm0
    addsd   xmm6, xmm0
    inc     ebx
    cmp     ebx, 400
    jb      .d
    DCONST  xmm0, 400.0
    divsd   xmm6, xmm0
    divsd   xmm7, xmm0
    divsd   xmm8, xmm0
    FAILIF_D xmm6, be, 0.1, "different seeds give different noise (mean |a-b| > 0.1)"
    xorpd   xmm9, xmm9
    xorpd   xmm10, xmm10
    xorpd   xmm11, xmm11
    xor     ebx, ebx
.c:
    lea     rax, [rel a3]
    cvtss2sd xmm0, [rax+rbx*4]
    subsd   xmm0, xmm7
    lea     rax, [rel b3]
    cvtss2sd xmm1, [rax+rbx*4]
    subsd   xmm1, xmm8
    movapd  xmm2, xmm0
    mulsd   xmm2, xmm1
    addsd   xmm9, xmm2
    mulsd   xmm0, xmm0
    addsd   xmm10, xmm0
    mulsd   xmm1, xmm1
    addsd   xmm11, xmm1
    inc     ebx
    cmp     ebx, 400
    jb      .c
    mulsd   xmm10, xmm11
    sqrtsd  xmm10, xmm10
    divsd   xmm9, xmm10
    PRINTMAX "corr(seed 0, seed 1)", xmm9
    ABSD    xmm9
    FAILIF_D xmm9, ae, 0.2, "|correlation between seeds| < 0.2"
ENDPX



; out[400]: eval3 = noise3 at pts, eval2 = noise2 at pts.xy
PROC eval3
    mov     rdi, rcx
    lea     rsi, [rel pts]
    xor     ebx, ebx
.l:
    movss   xmm0, [rsi]
    movss   xmm1, [rsi+4]
    movss   xmm2, [rsi+8]
    call    noise3
    movss   [rdi+rbx*4], xmm0
    add     rsi, 12
    inc     ebx
    cmp     ebx, 400
    jb      .l
ENDP

PROC eval2
    mov     rdi, rcx
    lea     rsi, [rel pts]
    xor     ebx, ebx
.l:
    movss   xmm0, [rsi]
    movss   xmm1, [rsi+4]
    call    noise2
    movss   [rdi+rbx*4], xmm0
    add     rsi, 12
    inc     ebx
    cmp     ebx, 400
    jb      .l
ENDP


; xmm6 x, xmm7 y (floats), xmm8 n (double)
PROCX ns_isotropy
    TEST    "isotropy"
    mov     ecx, 8
    call    noise_set_seed
    mov     ecx, 24
    call    mn_seed
    lea     rax, [rel acc]
    xor     ecx, ecx
    mov     [rax], rcx
    mov     [rax+8], rcx
    mov     [rax+16], rcx
    mov     r12d, 20000
.l:
    UNIF    -500.0, 500.0
    movss   xmm6, xmm0
    UNIF    -500.0, 500.0
    movss   xmm7, xmm0
    movss   xmm0, xmm6
    movss   xmm1, xmm7
    call    noise2
    cvtss2sd xmm8, xmm0
    cvtss2sd xmm0, xmm6
    DCONST  xmm1, 0.05
    addsd   xmm0, xmm1
    cvtsd2ss xmm0, xmm0
    movss   xmm1, xmm7
    call    noise2
    xor     ebx, ebx
    call    iso_acc
    cvtss2sd xmm1, xmm7
    DCONST  xmm0, 0.05
    addsd   xmm1, xmm0
    cvtsd2ss xmm1, xmm1
    movss   xmm0, xmm6
    call    noise2
    mov     ebx, 1
    call    iso_acc
    cvtss2sd xmm0, xmm6
    cvtss2sd xmm1, xmm7
    DCONST  xmm2, 0.05
    DCONST  xmm3, 0.7071
    mulsd   xmm2, xmm3                  ; h * 0.7071
    addsd   xmm0, xmm2
    addsd   xmm1, xmm2
    cvtsd2ss xmm0, xmm0
    cvtsd2ss xmm1, xmm1
    call    noise2
    mov     ebx, 2
    call    iso_acc
    dec     r12d
    jnz     .l
    lea     rax, [rel acc]
    movsd   xmm0, [rax]
    movapd  xmm1, xmm0
    maxsd   xmm0, [rax+8]
    maxsd   xmm0, [rax+16]
    minsd   xmm1, [rax+8]
    minsd   xmm1, [rax+16]
    divsd   xmm0, xmm1
    movapd  xmm6, xmm0
    FAILIF_D xmm6, ae, 1.15, "directional derivative energy x/y/diagonal within 15%"
    PRINTMAX "isotropy hi/lo", xmm6
ENDPX


; acc[slot] += (sample - n)^2, n in xmm8
LEAF iso_acc
    cvtss2sd xmm0, xmm0
    subsd   xmm0, xmm8
    mulsd   xmm0, xmm0
    lea     rax, [rel acc]
    addsd   xmm0, [rax+rbx*8]
    movsd   [rax+rbx*8], xmm0
    ret


PROCX ns_fbm, 16
    TEST    "fbm_ridged_warp"
    mov     ecx, 11
    call    noise_set_seed
    mov     ecx, 25
    call    mn_seed
    lea     rcx, [rel stA]
    call    st_reset
    lea     rcx, [rel stB]
    call    st_reset
    lea     rcx, [rel stC]
    call    st_reset
    lea     rcx, [rel stD]
    call    st_reset
    mov     r12d, 8000
.l:
    UNIF    -200.0, 200.0
    movss   xmm6, xmm0
    UNIF    -200.0, 200.0
    movss   xmm7, xmm0
    UNIF    -200.0, 200.0
    movss   xmm8, xmm0
    movss   xmm0, xmm6
    movss   xmm1, xmm7
    mov     r8d, 6
    call    fbm2
    lea     rcx, [rel stA]
    call    st_add
    movss   xmm0, xmm6
    movss   xmm1, xmm7
    movss   xmm2, xmm8
    mov     r9d, 5
    call    fbm3
    lea     rcx, [rel stB]
    call    st_add
    movss   xmm0, xmm6
    movss   xmm1, xmm7
    mov     r8d, 5
    call    ridged2
    lea     rcx, [rel stC]
    call    st_add
    movss   xmm0, xmm6
    movss   xmm1, xmm7
    mov     r8d, 4
    call    warp2
    lea     rcx, [rel stD]
    call    st_add
    dec     r12d
    jnz     .l
    lea     r12, [rel stA]
    CHECK_EQ [r12+ST.nan], 0, "fbm2 finite"
    movsd   xmm6, [r12+ST.min]
    FAILIF_D xmm6, b, -1.0, "fbm2 >= -1"
    movsd   xmm6, [r12+ST.max]
    FAILIF_D xmm6, a, 1.0, "fbm2 <= 1"
    mov     rcx, r12
    call    st_mean
    PRINTMAX "fbm2 mean", xmm0
    ABSD    xmm0
    FAILIF_D xmm0, ae, 0.02, "|mean fbm2| < 0.02"
    lea     r12, [rel stB]
    CHECK_EQ [r12+ST.nan], 0, "fbm3 finite"
    movsd   xmm6, [r12+ST.min]
    FAILIF_D xmm6, b, -1.0, "fbm3 >= -1"
    movsd   xmm6, [r12+ST.max]
    FAILIF_D xmm6, a, 1.0, "fbm3 <= 1"
    mov     rcx, r12
    call    st_mean
    PRINTMAX "fbm3 mean", xmm0
    ABSD    xmm0
    FAILIF_D xmm0, ae, 0.02, "|mean fbm3| < 0.02"
    lea     r12, [rel stC]
    CHECK_EQ [r12+ST.nan], 0, "ridged2 finite"
    movsd   xmm6, [r12+ST.min]
    FAILIF_D xmm6, b, 0.0, "ridged2 >= 0"
    movsd   xmm6, [r12+ST.max]
    FAILIF_D xmm6, a, 1.0, "ridged2 <= 1"
    FAILIF_D xmm6, be, 0.6, "ridges get close to 1 (max ridged2 > 0.6)"
    PRINTMAX "ridged2 max", xmm6
    lea     r12, [rel stD]
    CHECK_EQ [r12+ST.nan], 0, "warp2 finite"
    movsd   xmm6, [r12+ST.min]
    FAILIF_D xmm6, b, -1.0, "warp2 >= -1"
    movsd   xmm6, [r12+ST.max]
    FAILIF_D xmm6, a, 1.0, "warp2 <= 1"
    ; 1 octave of fbm == noise at the octave-0 offset
    FCONST  xmm0, 12.5
    FCONST  xmm1, -3.25
    mov     r8d, 1
    call    fbm2
    cvtss2sd xmm6, xmm0
    FCONST  xmm0, 12.5
    FCONST  xmm2, -124.9182
    addss   xmm0, xmm2
    FCONST  xmm1, -3.25
    FCONST  xmm2, 110.9475
    addss   xmm1, xmm2
    call    noise2
    cvtss2sd xmm1, xmm0
    movapd  xmm0, xmm6
    DCONST  xmm2, 1e-6
    call    mn_near_d
    CHECK_TRUE eax, "fbm2(x,y,1) == noise2 at the octave-0 offset"
    mov     r8d, 1
    call    fbm_probe
    movd    r12d, xmm0
    xor     r8d, r8d
    call    fbm_probe
    movd    eax, xmm0

    CHECK_EQ32 eax, r12d, "fbm2 octaves 0 behaves like 1"
    mov     r8d, -5
    call    fbm_probe
    movd    eax, xmm0
    CHECK_EQ32 eax, r12d, "fbm2 octaves -5 behaves like 1"
    mov     r8d, 16
    call    fbm_probe
    movd    r12d, xmm0
    mov     r8d, 99
    call    fbm_probe
    movd    eax, xmm0
    CHECK_EQ32 eax, r12d, "fbm2 octaves 99 behaves like 16"
    FCONST  xmm0, 12.5
    FCONST  xmm1, -3.25
    mov     r8d, 1
    call    ridged2
    movd    r12d, xmm0
    FCONST  xmm0, 12.5
    FCONST  xmm1, -3.25
    xor     r8d, r8d
    call    ridged2
    movd    eax, xmm0
    CHECK_EQ32 eax, r12d, "ridged2 octaves 0 behaves like 1"
    mov     ecx, 2
    call    rough
    movapd  xmm6, xmm0
    mov     ecx, 8
    call    rough
    movapd  xmm7, xmm0
    PRINTMAX "fbm2 roughness 2 octaves", xmm6
    PRINTMAX "fbm2 roughness 8 octaves", xmm7
    DCONST  xmm0, 1.25
    mulsd   xmm0, xmm6
    xor     ebx, ebx
    ucomisd xmm7, xmm0
    jbe     .r
    mov     ebx, 1
.r:

    CHECK_TRUE ebx, "8 octaves rougher than 2 octaves * 1.25"
    ; warp continuity: max jump shrinks ~10x with a 10x finer step
    DCONST  xmm0, 1e-3
    mov     ecx, 3000
    call    max_jump
    movapd  xmm6, xmm0
    DCONST  xmm0, 1e-4
    mov     ecx, 30000
    call    max_jump
    movapd  xmm7, xmm0
    PRINTMAX "warp2 max jump step 1e-3", xmm6
    PRINTMAX "warp2 max jump step 1e-4", xmm7
    FAILIF_D xmm7, ae, 0.06, "warp2 max jump at step 1e-4 < 0.06"
    DCONST  xmm0, 0.3
    mulsd   xmm0, xmm6
    xor     ebx, ebx
    ucomisd xmm7, xmm0
    jae     .w
    mov     ebx, 1
.w:
    CHECK_TRUE ebx, "warp2 max jump shrinks with the step (j2 < 0.3*j1)"
ENDPX


PROC fbm_probe
    FCONST  xmm0, 12.5
    FCONST  xmm1, -3.25
    call    fbm2
ENDP

; sum of |fbm2(x,.5) - fbm2(x+.001,.5)| over x = i*.002, i < 4000
PROCX rough
    mov     r12d, ecx
    xorpd   xmm6, xmm6
    xor     ebx, ebx
.l:
    cvtsi2sd xmm7, ebx
    DCONST  xmm0, 0.002
    mulsd   xmm7, xmm0
    cvtsd2ss xmm0, xmm7
    FCONST  xmm1, 0.5
    mov     r8d, r12d
    call    fbm2
    cvtss2sd xmm8, xmm0
    DCONST  xmm0, 0.001
    addsd   xmm0, xmm7
    cvtsd2ss xmm0, xmm0
    FCONST  xmm1, 0.5
    mov     r8d, r12d
    call    fbm2
    cvtss2sd xmm0, xmm0
    subsd   xmm8, xmm0
    ABSD    xmm8
    addsd   xmm6, xmm8
    inc     ebx
    cmp     ebx, 4000
    jb      .l
    movapd  xmm0, xmm6
ENDPX

; max |warp2(k) - warp2(k-1)|
PROCX max_jump
    movapd  xmm9, xmm0
    mov     r12d, ecx
    xorps   xmm0, xmm0
    xorps   xmm1, xmm1
    mov     r8d, 4
    call    warp2
    cvtss2sd xmm6, xmm0
    xorpd   xmm7, xmm7
    mov     ebx, 1
.l:
    cmp     ebx, r12d
    jae     .done
    cvtsi2sd xmm0, ebx
    mulsd   xmm0, xmm9
    DCONST  xmm1, 0.7
    mulsd   xmm1, xmm0
    cvtsd2ss xmm0, xmm0
    cvtsd2ss xmm1, xmm1
    mov     r8d, 4
    call    warp2
    cvtss2sd xmm0, xmm0
    movapd  xmm1, xmm0
    subsd   xmm1, xmm6
    ABSD    xmm1
    maxsd   xmm7, xmm1
    movapd  xmm6, xmm0
    inc     ebx
    jmp     .l
.done:
    movapd  xmm0, xmm7
ENDPX


PROCX ns_large
    TEST    "unseeded_safe_and_large_coords"
    mov     ecx, 42
    call    noise_set_seed
    call    mn_bad_reset
    xor     ebx, ebx
.l:
    lea     rax, [rel large_xs]
    movsd   xmm6, [rax+rbx*8]
    DCONST  xmm0, 0.25
    addsd   xmm0, xmm6
    DCONST  xmm1, 0.5
    mulsd   xmm1, xmm6
    DCONST  xmm2, 0.5
    addsd   xmm1, xmm2
    xorpd   xmm2, xmm2
    subsd   xmm2, xmm6
    cvtsd2ss xmm0, xmm0
    cvtsd2ss xmm1, xmm1
    cvtsd2ss xmm2, xmm2
    call    noise3
    call    unit_range
    test    eax, eax
    jnz     .n2
    movapd  xmm0, xmm6
    xorpd   xmm1, xmm1
    xorpd   xmm2, xmm2
    NOTE    "noise3 out of [-1,1] at x"
.n2:
    DCONST  xmm1, 0.3
    mulsd   xmm1, xmm6
    cvtsd2ss xmm1, xmm1
    cvtsd2ss xmm0, xmm6
    call    noise2
    call    unit_range
    test    eax, eax
    jnz     .nx
    movapd  xmm0, xmm6
    xorpd   xmm1, xmm1
    xorpd   xmm2, xmm2
    NOTE    "noise2 out of [-1,1] at x"
.nx:
    inc     ebx
    cmp     ebx, 5
    jb      .l
    CHECK_BAD "noise2/noise3 finite and in [-1,1] for |coords| up to 1e7"
ENDPX

; -1 <= v <= 1, NaN fails
LEAF unit_range
    xor     eax, eax
    mov     ecx, __?float32?__(-1.0)
    movd    xmm1, ecx
    ucomiss xmm0, xmm1
    jp      .no
    jb      .no
    mov     ecx, __?float32?__(1.0)
    movd    xmm1, ecx
    ucomiss xmm0, xmm1
    ja      .no
    mov     eax, 1
.no:
    ret
