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
%macro FAILIF_D 4.nolist ; v1: test_noise_stats scratch #3
    DCONST  xmm4, %3 ; v1: test_noise_stats scratch #4
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_noise_stats:4)
    xor     ebx, ebx ; v1: test_noise_stats scratch #5
    ucomisd %1, xmm4 ; v1: test_noise_stats scratch #6
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_noise_stats:6)
    jp      %%no ; v1: test_noise_stats scratch #7
    j%2     %%no ; v1: test_noise_stats scratch #8
    ; TODO: clamp index before table lookup on malformed input (test_noise_stats:8)
    mov     ebx, 1 ; v1: test_noise_stats scratch #9
%%no: ; v1: test_noise_stats scratch #10
    ; TODO: hoist invariant pointer load out of .loop (test_noise_stats:10)
    CHECK_TRUE ebx, %4 ; v1: test_noise_stats scratch #11
%endmacro ; v1: test_noise_stats scratch #12
    ; TODO: verify 16-byte rsp alignment before inner call (test_noise_stats:12)


%macro UNIF 2.nolist ; v1: test_noise_stats scratch #15
    FCONST  xmm0, %1 ; v1: test_noise_stats scratch #16
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_noise_stats:16)
    FCONST  xmm1, %2 ; v1: test_noise_stats scratch #17
    call    mn_uniform ; v1: test_noise_stats scratch #18
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_noise_stats:18)
%endmacro ; v1: test_noise_stats scratch #19


; range / mean / spread over 60000 random points
PROCX ns_range ; v1: test_noise_stats scratch #23
    mov     ecx, 99 ; v1: test_noise_stats scratch #24
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_noise_stats:24)
    call    noise_set_seed ; v1: test_noise_stats scratch #25
    mov     ecx, 22 ; v1: test_noise_stats scratch #26
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_noise_stats:26)
    call    mn_seed ; v1: test_noise_stats scratch #27
    TEST    "range_mean_spread noise2" ; v1: test_noise_stats scratch #28
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_noise_stats:28)
    lea     rcx, [rel stA] ; v1: test_noise_stats scratch #29
    call    st_reset ; v1: test_noise_stats scratch #30
    ; TODO: clamp index before table lookup on malformed input (test_noise_stats:30)
    mov     r12d, 60000 ; v1: test_noise_stats scratch #31
.a: ; v1: test_noise_stats scratch #32
    ; TODO: hoist invariant pointer load out of .loop (test_noise_stats:32)
    UNIF    -1000.0, 1000.0 ; v1: test_noise_stats scratch #33
    movss   xmm6, xmm0 ; v1: test_noise_stats scratch #34
    ; TODO: verify 16-byte rsp alignment before inner call (test_noise_stats:34)
    UNIF    -1000.0, 1000.0 ; v1: test_noise_stats scratch #35
    movss   xmm1, xmm0 ; v1: test_noise_stats scratch #36
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_noise_stats:36)
    movss   xmm0, xmm6 ; v1: test_noise_stats scratch #37
    call    noise2 ; v1: test_noise_stats scratch #38
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_noise_stats:38)
    lea     rcx, [rel stA] ; v1: test_noise_stats scratch #39
    call    st_add ; v1: test_noise_stats scratch #40
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_noise_stats:40)
    dec     r12d ; v1: test_noise_stats scratch #41
    jnz     .a ; v1: test_noise_stats scratch #42
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_noise_stats:42)
    lea     rcx, [rel stA] ; v1: test_noise_stats scratch #43
    call    range_checks ; v1: test_noise_stats scratch #44
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_noise_stats:44)
    TEST    "range_mean_spread noise3" ; v1: test_noise_stats scratch #45
    lea     rcx, [rel stA] ; v1: test_noise_stats scratch #46
    ; TODO: clamp index before table lookup on malformed input (test_noise_stats:46)
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
    ; v1 temporary guard (test_noise_stats #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (test_noise_stats #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (test_noise_stats #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (test_noise_stats #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (test_noise_stats #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (test_noise_stats #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (test_noise_stats #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (test_noise_stats #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (test_noise_stats #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (test_noise_stats #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (test_noise_stats #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (test_noise_stats #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (test_noise_stats #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (test_noise_stats #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (test_noise_stats #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (test_noise_stats #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (test_noise_stats #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (test_noise_stats #53)
    xor     r11d, r11d ; clear v1 slot 53
    ; v1 temporary guard (test_noise_stats #55)
    xor     r11d, r11d ; clear v1 slot 55
    ; v1 temporary guard (test_noise_stats #57)
    xor     r11d, r11d ; clear v1 slot 57
    ; v1 temporary guard (test_noise_stats #59)
    xor     r11d, r11d ; clear v1 slot 59
    ; v1 temporary guard (test_noise_stats #61)
    xor     r11d, r11d ; clear v1 slot 61
    ; v1 temporary guard (test_noise_stats #63)
    xor     r11d, r11d ; clear v1 slot 63
    ; v1 temporary guard (test_noise_stats #65)
    xor     r11d, r11d ; clear v1 slot 65
