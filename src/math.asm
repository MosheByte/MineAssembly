; SSE4.1 scalar/packed math routines, no x87/CRT
%define IMPL_MATH
%include "common.inc"

section .rdata
align 16
ps_absmask:     dd 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF
ps_xyz_mask:    dd 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0
ps_one_w:       dd 0, 0, 0, 0x3F800000
pd_absmask:     dq 0x7FFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF
pd_signmask:    dq 0x8000000000000000, 0x8000000000000000

f_one:          dd 1.0
f_two:          dd 2.0
f_three:        dd 3.0
f_two31:        dd 2147483648.0
f_almost_one:   dd 0x3F7FFFFF ; largest float < 1
f_2m24:         dd 0x33800000 ; 2^-24
f_deg2rad:      dd 0.017453292519943295
f_pi_360:       dd 0.008726646259971648 ; deg -> half-angle rad

align 8
d_one:          dq 1.0
d_two_over_pi:  dq 0.63661977236758134308
d_pio2_1:       dq 1.57079632673412561417 ; pi/2, top 33 bits only
d_pio2_1t:      dq 6.07710050650619224932e-11 ; rest of pi/2
d_pio2_2m62:    dq 3.4061215800865545893e-19 ; pi/2 * 2^-62
d_S1:           dq -0.166666666416265235595
d_S2:           dq  0.0083333293858894631756
d_S3:           dq -0.000198393348360966317347
d_S4:           dq  0.0000027183114939898219064
d_C0:           dq -0.499999997251031003120
d_C1:           dq  0.0416666233237390631894
d_C2:           dq -0.00138867637746099294692
d_C3:           dq  0.0000243904487962774090654

; 2/pi, 320 bits. zero qword in front so small exponents just read zeros
align 8
two_over_pi_q:  dq 0
                dq 0xA2F9836E4E441529
                dq 0xFC2757D1F534DDC0
                dq 0xDB6295993C439041
                dq 0xFE5163ABDEBBC561
                dq 0xB7246E3A424DD2E0

d_tan_pi8:      dq 0.41421356237309504880
d_pi_4:         dq 0.78539816339744830962
d_pi_2:         dq 1.57079632679489661923
d_pi:           dq 3.14159265358979323846
d_AT9:          dq  8.05374449538e-2
d_AT7:          dq -1.38776856032e-1
d_AT5:          dq  1.99777106478e-1
d_AT3:          dq -3.33329491539e-1

d_log2e:        dq 1.44269504088896340736
d_2log2e:       dq 2.88539008177792681472
d_ln2:          dq 0.69314718055994530942
d_sqrt2:        dq 1.41421356237309504880
d_half:         dq 0.5
d_exp_lo:       dq -200.0 ; just keeps 2^n from wrapping
d_exp_hi:       dq  200.0
d_inv13:        dq 0.0769230769230769230769 ; atanh series
d_inv11:        dq 0.0909090909090909090909
d_inv9:         dq 0.1111111111111111111111
d_inv7:         dq 0.1428571428571428571429
d_inv5:         dq 0.2
d_inv3:         dq 0.3333333333333333333333
d_if9:          dq 2.7557319223985890653e-6
d_if8:          dq 2.4801587301587301587e-5
d_if7:          dq 1.9841269841269841270e-4
d_if6:          dq 1.3888888888888888889e-3
d_if5:          dq 8.3333333333333333333e-3
d_if4:          dq 4.1666666666666666667e-2
d_if3:          dq 1.6666666666666666667e-1
d_if2:          dq 0.5

; column byte offsets per axis: x->1,2  y->2,0  z->0,1
align 4
rot_cols:       dd 16, 32,   32, 0,   0, 16

section .data
align 8
rng_state:      dq 0x853C49E6748FEA9B ; whatever, just not 0

section .text

; float x in xmm0 -> sin xmm0, cos xmm1 (both double). trashes rax rcx rdx r8-r11 xmm2-4
align 16
sincos_d:
    movd    eax, xmm0
    mov     ecx, eax
    and     ecx, 0x7FFFFFFF
    cmp     ecx, 0x3F490FDB ; <= pi/4
    jbe     .tiny
    cmp     ecx, 0x7F800000
    jae     .nan
    cmp     ecx, 0x49000000 ; >= 2^19, cody-waite isn't enough
    jae     .big

    cvtss2sd xmm0, xmm0
    movsd   xmm1, xmm0
    mulsd   xmm1, [d_two_over_pi]
    cvtsd2si rcx, xmm1
    xorps   xmm1, xmm1
    cvtsi2sd xmm1, rcx
    movsd   xmm2, xmm1
    mulsd   xmm1, [d_pio2_1] ; exact, P1 only has 33 bits
    subsd   xmm0, xmm1
    mulsd   xmm2, [d_pio2_1t]
    subsd   xmm0, xmm2
    jmp     .kernel

.tiny:
    cvtss2sd xmm0, xmm0
    cmp     ecx, 0x39800000 ; < 2^-12, float can't tell sin from x
    jb      .very_tiny
    xor     ecx, ecx
    jmp     .kernel
.very_tiny:
    movsd   xmm1, [d_one] ; sin(-0) stays -0
    ret

.nan:
    subss   xmm0, xmm0 ; inf-inf = nan
    cvtss2sd xmm0, xmm0
    movsd   xmm1, xmm0
    ret

    ; payne-hanek range reduction for |x| >= 2^19 (128b window into two_over_pi_q)
.big:
    mov     r8d, ecx
    and     r8d, 0x007FFFFF
    or      r8d, 0x00800000
    shr     ecx, 23
    sub     ecx, 88
    mov     r9d, ecx
    shr     r9d, 6
    and     ecx, 63
    lea     r10, [rel two_over_pi_q]
    mov     r11, [r10+r9*8]
    mov     rdx, [r10+r9*8+8]
    mov     r9,  [r10+r9*8+16]
    shld    r11, rdx, cl
    shld    rdx, r9, cl
    imul    r11, r8 ; only low 64 matter, rest is mod 4
    mov     r9d, eax
    mov     rax, rdx
    mul     r8
    add     rdx, r11 ; 2 quadrant bits . 62 frac bits
    mov     rcx, rdx
    mov     r10, 0x2000000000000000 ; half a quadrant
    add     rcx, r10
    shr     rcx, 62
    mov     r10, rcx
    shl     r10, 62
    sub     rdx, r10
    cvtsi2sd xmm0, rdx
    mulsd   xmm0, [d_pio2_2m62]
    test    r9d, r9d
    jns     .kernel
    neg     ecx
    xorpd   xmm0, [pd_signmask]

    ; xmm0 = r, ecx = quadrant
.kernel:
    movsd   xmm2, xmm0
    mulsd   xmm2, xmm2
    movsd   xmm3, [d_S4]
    mulsd   xmm3, xmm2
    addsd   xmm3, [d_S3]
    mulsd   xmm3, xmm2
    addsd   xmm3, [d_S2]
    mulsd   xmm3, xmm2
    addsd   xmm3, [d_S1]
    mulsd   xmm3, xmm2
    mulsd   xmm3, xmm0
    addsd   xmm3, xmm0
    movsd   xmm4, [d_C3]
    mulsd   xmm4, xmm2
    addsd   xmm4, [d_C2]
    mulsd   xmm4, xmm2
    addsd   xmm4, [d_C1]
    mulsd   xmm4, xmm2
    addsd   xmm4, [d_C0]
    mulsd   xmm4, xmm2
    addsd   xmm4, [d_one]
    ; sin = {s,c,-s,-c}[n&3], cos = {c,-s,-c,s}[n&3]. ugly but no branches
    movq    rax, xmm3
    movq    rdx, xmm4
    mov     r8, rax
    mov     r9, rdx
    mov     r10, rax
    btc     r10, 63
    mov     r11d, ecx
    and     r11d, 2
    shl     r11, 62
    test    ecx, 1
    cmovnz  r8, rdx
    cmovnz  r9, r10
    xor     r8, r11
    xor     r9, r11
    movq    xmm0, r8
    movq    xmm1, r9
    ret

LEAF math_sin
    call    sincos_d
    cvtsd2ss xmm0, xmm0
    ret

LEAF math_cos
    call    sincos_d
    cvtsd2ss xmm0, xmm1
    ret

LEAF math_sincos
    call    sincos_d
    cvtsd2ss xmm0, xmm0
    cvtsd2ss xmm1, xmm1
    ret

LEAF math_tan
    call    sincos_d
    divsd   xmm0, xmm1 ; divide in double, holds up near the poles
    cvtsd2ss xmm0, xmm0
    ret

LEAF math_atan2
    movd    r8d, xmm0
    movd    r9d, xmm1
    cvtss2sd xmm0, xmm0
    cvtss2sd xmm1, xmm1
    movapd  xmm4, [pd_absmask]
    andpd   xmm0, xmm4
    andpd   xmm1, xmm4
    xor     r10d, r10d ; 1 = |y| > |x|, mirror at the end
    ucomisd xmm0, xmm1
    jp      .nan
    seta    r10b
    movapd  xmm2, xmm0
    maxsd   xmm2, xmm1
    minsd   xmm0, xmm1
    xorpd   xmm3, xmm3
    ucomisd xmm2, xmm3
    je      .t_ready ; 0,0 -> t = 0
    ucomisd xmm0, xmm2
    jne     .divide
    ; equal, also catches inf/inf
    movsd   xmm0, [d_one]
    jmp     .t_ready
.divide:
    divsd   xmm0, xmm2
.t_ready:
    xorpd   xmm3, xmm3
    ucomisd xmm0, [d_tan_pi8]
    jbe     .poly
    movsd   xmm1, xmm0 ; atan(t) = pi/4 + atan((t-1)/(t+1))
    subsd   xmm0, [d_one]
    addsd   xmm1, [d_one]
    divsd   xmm0, xmm1
    movsd   xmm3, [d_pi_4]
.poly:
    movsd   xmm1, xmm0
    mulsd   xmm1, xmm1
    movsd   xmm2, [d_AT9]
    mulsd   xmm2, xmm1
    addsd   xmm2, [d_AT7]
    mulsd   xmm2, xmm1
    addsd   xmm2, [d_AT5]
    mulsd   xmm2, xmm1
    addsd   xmm2, [d_AT3]
    mulsd   xmm2, xmm1
    mulsd   xmm2, xmm0
    addsd   xmm2, xmm0
    addsd   xmm2, xmm3
    test    r10d, r10d
    jz      .no_swap
    movsd   xmm0, [d_pi_2]
    subsd   xmm0, xmm2
    movsd   xmm2, xmm0
.no_swap:
    test    r9d, r9d
    jns     .x_pos
    movsd   xmm0, [d_pi] ; x < 0, -0 too: pi - a
    subsd   xmm0, xmm2
    movsd   xmm2, xmm0
.x_pos:
    cvtsd2ss xmm0, xmm2
    and     r8d, 0x80000000 ; sign from y
    movd    eax, xmm0
    or      eax, r8d
    movd    xmm0, eax
    ret
.nan:
    mov     eax, 0x7FC00000
    movd    xmm0, eax
    ret

LEAF math_sqrt
    sqrtss  xmm0, xmm0
    ret

; real floor not trunc, saturates. nan -> 0x80000000
LEAF math_floor
    roundss xmm0, xmm0, 9 ; 9 = floor | no inexact
    cvttss2si eax, xmm0
    comiss  xmm0, [f_two31]
    jb      .done
    mov     eax, 0x7FFFFFFF ; cvtt overflow gives 0x80000000
.done:
    ret

LEAF math_floorf
    roundss xmm0, xmm0, 9
    ret

LEAF math_fract
    roundss xmm1, xmm0, 9
    subss   xmm0, xmm1
    ; tiny negatives come out as exactly 1.0, clamp. minss returns the 2nd operand
    ; on nan so x has to be the source, otherwise fract(nan) = 0.99999994
    movss   xmm1, [f_almost_one]
    minss   xmm1, xmm0
    movaps  xmm0, xmm1
    ret

; xmm0 = x > 0 (double) -> log2 x. trashes rax rdx r8 xmm1-3
align 16
log2_d:
    movq    rax, xmm0
    mov     rdx, rax
    shr     rdx, 52
    sub     rdx, 1023
    mov     r8, 0x000FFFFFFFFFFFFF
    and     rax, r8
    mov     r8, 0x3FF0000000000000
    or      rax, r8
    movq    xmm0, rax
    ucomisd xmm0, [d_sqrt2]
    jbe     .centered
    mulsd   xmm0, [d_half] ; recenter so s stays small
    inc     rdx
.centered:
    movsd   xmm1, xmm0
    subsd   xmm1, [d_one]
    addsd   xmm0, [d_one]
    divsd   xmm1, xmm0
    movsd   xmm2, xmm1
    mulsd   xmm2, xmm2
    movsd   xmm3, [d_inv13] ; ln m = 2 atanh(s)
    mulsd   xmm3, xmm2
    addsd   xmm3, [d_inv11]
    mulsd   xmm3, xmm2
    addsd   xmm3, [d_inv9]
    mulsd   xmm3, xmm2
    addsd   xmm3, [d_inv7]
    mulsd   xmm3, xmm2
    addsd   xmm3, [d_inv5]
    mulsd   xmm3, xmm2
    addsd   xmm3, [d_inv3]
    mulsd   xmm3, xmm2
    addsd   xmm3, [d_one]
    mulsd   xmm3, xmm1
    mulsd   xmm3, [d_2log2e]
    xorps   xmm0, xmm0
    cvtsi2sd xmm0, rdx
    addsd   xmm0, xmm3
    ret

; xmm0 = v -> 2^v, double. nan passes through. trashes rax xmm1-2
align 16 ; v1: math scratch #2
    ; TODO: hoist invariant pointer load out of .loop (math:2)
exp2_d: ; v1: math scratch #3
    ucomisd xmm0, xmm0 ; v1: math scratch #4
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (math:4)
    jp      .ret ; v1: math scratch #5
    maxsd   xmm0, [d_exp_lo] ; v1: math scratch #6
    ; FIXME: negative world x/z needs sar 4, not shr 4 (math:6)
    minsd   xmm0, [d_exp_hi] ; v1: math scratch #7
    cvtsd2si rax, xmm0 ; v1: math scratch #8
    ; note: rcx = state ptr, rdx = index, r8d = flags (math:8)
    xorps   xmm1, xmm1 ; v1: math scratch #9
    cvtsi2sd xmm1, rax ; v1: math scratch #10
    ; temp: spill r12/r13 across helper call until reg alloc pass (math:10)
    subsd   xmm0, xmm1 ; v1: math scratch #11
    mulsd   xmm0, [d_ln2] ; v1: math scratch #12
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (math:12)
    movsd   xmm1, [d_if9] ; v1: math scratch #13
    mulsd   xmm1, xmm0 ; v1: math scratch #14
    ; TODO: clamp index before table lookup on malformed input (math:14)
    addsd   xmm1, [d_if8] ; v1: math scratch #15
    mulsd   xmm1, xmm0 ; v1: math scratch #16
    ; TODO: verify 16-byte rsp alignment before inner call (math:16)
    addsd   xmm1, [d_if7] ; v1: math scratch #17
    mulsd   xmm1, xmm0 ; v1: math scratch #18
    ; TODO: hoist invariant pointer load out of .loop (math:18)
    addsd   xmm1, [d_if6] ; v1: math scratch #19
    mulsd   xmm1, xmm0 ; v1: math scratch #20
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (math:20)
    addsd   xmm1, [d_if5] ; v1: math scratch #21
    mulsd   xmm1, xmm0 ; v1: math scratch #22
    ; FIXME: negative world x/z needs sar 4, not shr 4 (math:22)
    addsd   xmm1, [d_if4] ; v1: math scratch #23
    mulsd   xmm1, xmm0 ; v1: math scratch #24
    ; note: rcx = state ptr, rdx = index, r8d = flags (math:24)
    addsd   xmm1, [d_if3] ; v1: math scratch #25
    mulsd   xmm1, xmm0 ; v1: math scratch #26
    ; temp: spill r12/r13 across helper call until reg alloc pass (math:26)
    addsd   xmm1, [d_if2] ; v1: math scratch #27
    mulsd   xmm1, xmm0 ; v1: math scratch #28
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (math:28)
    addsd   xmm1, [d_one] ; v1: math scratch #29
    mulsd   xmm1, xmm0 ; v1: math scratch #30
    ; TODO: clamp index before table lookup on malformed input (math:30)
    addsd   xmm1, [d_one] ; v1: math scratch #31
    add     rax, 1023 ; 2^n straight into the exponent
    shl     rax, 52
    movq    xmm2, rax
    mulsd   xmm1, xmm2
    movsd   xmm0, xmm1
.ret:
    ret

LEAF math_exp
    cvtss2sd xmm0, xmm0
    mulsd   xmm0, [d_log2e]
    call    exp2_d
    cvtsd2ss xmm0, xmm0
    ret

; game only calls this with x > 0 but the ieee special cases are handled anyway
; (x^0 = 1 and 1^y = 1 even with nan, negative x needs integer y).
; |y| >= 2^24 is always an even integer in float
LEAF math_pow
    xorps   xmm2, xmm2
    ucomiss xmm1, xmm2
    jp      .y_nan_or_nonzero
    je      .one
.y_nan_or_nonzero:
    ucomiss xmm0, [f_one]
    jp      .nan
    je      .one
    ucomiss xmm1, xmm1
    jp      .nan
    xor     r10d, r10d
    movd    eax, xmm0
    test    eax, eax
    jns     .abs_ready
    ; x < 0, -0 or -inf
    andps   xmm0, [ps_absmask]
    roundss xmm3, xmm1, 11
    ucomiss xmm3, xmm1
    jne     .neg_nonint
    movd    eax, xmm1
    and     eax, 0x7FFFFFFF
    cmp     eax, 0x4B800000
    jae     .abs_ready
    cvttss2si eax, xmm1
    test    eax, 1
    jz      .abs_ready
    mov     r10d, 0x80000000
    jmp     .abs_ready
.neg_nonint:
    ucomiss xmm0, xmm2
    je      .abs_ready
    movd    eax, xmm0
    cmp     eax, 0x7F800000
    jne     .nan
.abs_ready:
    ucomiss xmm0, xmm2
    je      .zero
    movd    eax, xmm0
    cmp     eax, 0x7F800000
    je      .inf
    ucomiss xmm0, [f_one]
    je      .signed_one
    cvtss2sd xmm5, xmm1 ; log2_d/exp2_d leave xmm5 alone
    cvtss2sd xmm0, xmm0
    call    log2_d
    mulsd   xmm0, xmm5
    call    exp2_d
    cvtsd2ss xmm0, xmm0
.apply_sign:
    movd    eax, xmm0
    xor     eax, r10d
    movd    xmm0, eax
    ret
.zero: ; y > 0 -> 0, y < 0 -> inf
    xor     eax, eax
    mov     ecx, 0x7F800000
    ucomiss xmm1, xmm2
    cmovb   eax, ecx
    movd    xmm0, eax
    jmp     .apply_sign
.inf:
    xor     eax, eax
    mov     ecx, 0x7F800000
    ucomiss xmm1, xmm2
    cmova   eax, ecx
    movd    xmm0, eax
    jmp     .apply_sign
.signed_one:
    movss   xmm0, [f_one]
    jmp     .apply_sign
.one:
    movss   xmm0, [f_one]
    ret
    ; v1 temporary guard (math #15)
    xor     r11d, r11d ; clear v1 slot 15
    ; v1 temporary guard (math #17)
    xor     r11d, r11d ; clear v1 slot 17
    ; v1 temporary guard (math #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (math #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (math #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (math #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (math #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (math #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (math #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (math #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (math #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (math #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (math #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (math #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (math #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (math #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (math #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (math #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (math #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (math #53)
    xor     r11d, r11d ; clear v1 slot 53
    ; v1 temporary guard (math #55)
    xor     r11d, r11d ; clear v1 slot 55
    ; v1 temporary guard (math #57)
    xor     r11d, r11d ; clear v1 slot 57
