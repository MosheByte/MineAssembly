; test_exppow.asm - math_exp/math_pow vs x87 (rel err < 1e-5), the C99 pow() special
; cases bit-exact, and math_fract on NaN/inf. the pow table is precomputed from
; double-precision pow + the C99 pole/overflow rules, rounded to f32.
; @link src/math.asm tests/mathnoise/mn_helpers.asm
; @timeout 120
%include "common.inc"
%include "../mathnoise/mn_test.inc"



section .rdata
align 4

; x values: 0, -0, 1, -1, 2, -2, 0.5, -0.5, inf, -inf, 3, -3
pow_xs:
    dd 0x00000000, 0x80000000, 0x3F800000, 0xBF800000, 0x40000000, 0xC0000000
    dd 0x3F000000, 0xBF000000, 0x7F800000, 0xFF800000, 0x40400000, 0xC0400000
POW_NX equ 12

; y values: 0, -0, 1, -1, 2, -2, 3, -3, 0.5, -0.5, 2.5, inf, -inf, 1e10, -1e10,
;           7, 2^25, 0.001, -0.001   (inf^0.001 must be inf, not 2^(1024*0.001))
pow_ys:
    dd 0x00000000, 0x80000000, 0x3F800000, 0xBF800000, 0x40000000, 0xC0000000
    dd 0x40400000, 0xC0400000, 0x3F000000, 0xBF000000, 0x40200000, 0x7F800000
    dd 0xFF800000, 0x501502F9, 0xD01502F9, 0x40E00000, 0x4C000000, 0x3A83126F
    dd 0xBA83126F
POW_NY equ 19

; expected f32 bits of pow(x, y): one row per x, one column per y
pow_want:
    dd 0x3F800000, 0x3F800000, 0x00000000, 0x7F800000, 0x00000000, 0x7F800000, 0x00000000, 0x7F800000, 0x00000000, 0x7F800000, 0x00000000, 0x00000000, 0x7F800000, 0x00000000, 0x7F800000, 0x00000000, 0x00000000, 0x00000000, 0x7F800000
    dd 0x3F800000, 0x3F800000, 0x80000000, 0xFF800000, 0x00000000, 0x7F800000, 0x80000000, 0xFF800000, 0x00000000, 0x7F800000, 0x00000000, 0x00000000, 0x7F800000, 0x00000000, 0x7F800000, 0x80000000, 0x00000000, 0x00000000, 0x7F800000
    dd 0x3F800000, 0x3F800000, 0x3F800000, 0x3F800000, 0x3F800000, 0x3F800000, 0x3F800000, 0x3F800000, 0x3F800000, 0x3F800000, 0x3F800000, 0x3F800000, 0x3F800000, 0x3F800000, 0x3F800000, 0x3F800000, 0x3F800000, 0x3F800000, 0x3F800000
    dd 0x3F800000, 0x3F800000, 0xBF800000, 0xBF800000, 0x3F800000, 0x3F800000, 0xBF800000, 0xBF800000, 0x7FC00000, 0x7FC00000, 0x7FC00000, 0x3F800000, 0x3F800000, 0x3F800000, 0x3F800000, 0xBF800000, 0x3F800000, 0x7FC00000, 0x7FC00000
    dd 0x3F800000, 0x3F800000, 0x40000000, 0x3F000000, 0x40800000, 0x3E800000, 0x41000000, 0x3E000000, 0x3FB504F3, 0x3F3504F3, 0x40B504F3, 0x7F800000, 0x00000000, 0x7F800000, 0x00000000, 0x43000000, 0x7F800000, 0x3F8016B9, 0x3F7FD297
    dd 0x3F800000, 0x3F800000, 0xC0000000, 0xBF000000, 0x40800000, 0x3E800000, 0xC1000000, 0xBE000000, 0x7FC00000, 0x7FC00000, 0x7FC00000, 0x7F800000, 0x00000000, 0x7F800000, 0x00000000, 0xC3000000, 0x7F800000, 0x7FC00000, 0x7FC00000
    dd 0x3F800000, 0x3F800000, 0x3F000000, 0x40000000, 0x3E800000, 0x40800000, 0x3E000000, 0x41000000, 0x3F3504F3, 0x3FB504F3, 0x3E3504F3, 0x00000000, 0x7F800000, 0x00000000, 0x7F800000, 0x3C000000, 0x00000000, 0x3F7FD297, 0x3F8016B9
    dd 0x3F800000, 0x3F800000, 0xBF000000, 0xC0000000, 0x3E800000, 0x40800000, 0xBE000000, 0xC1000000, 0x7FC00000, 0x7FC00000, 0x7FC00000, 0x00000000, 0x7F800000, 0x00000000, 0x7F800000, 0xBC000000, 0x00000000, 0x7FC00000, 0x7FC00000
    dd 0x3F800000, 0x3F800000, 0x7F800000, 0x00000000, 0x7F800000, 0x00000000, 0x7F800000, 0x00000000, 0x7F800000, 0x00000000, 0x7F800000, 0x7F800000, 0x00000000, 0x7F800000, 0x00000000, 0x7F800000, 0x7F800000, 0x7F800000, 0x00000000
    dd 0x3F800000, 0x3F800000, 0xFF800000, 0x80000000, 0x7F800000, 0x00000000, 0xFF800000, 0x80000000, 0x7F800000, 0x00000000, 0x7F800000, 0x7F800000, 0x00000000, 0x7F800000, 0x00000000, 0xFF800000, 0x7F800000, 0x7F800000, 0x00000000
    dd 0x3F800000, 0x3F800000, 0x40400000, 0x3EAAAAAB, 0x41100000, 0x3DE38E39, 0x41D80000, 0x3D17B426, 0x3FDDB3D7, 0x3F13CD3A, 0x41796A52, 0x7F800000, 0x00000000, 0x7F800000, 0x00000000, 0x4508B000, 0x7F800000, 0x3F802405, 0x3F7FB80A
    dd 0x3F800000, 0x3F800000, 0xC0400000, 0xBEAAAAAB, 0x41100000, 0x3DE38E39, 0xC1D80000, 0xBD17B426, 0x7FC00000, 0x7FC00000, 0x7FC00000, 0x7F800000, 0x00000000, 0x7F800000, 0x00000000, 0xC508B000, 0x7F800000, 0x7FC00000, 0x7FC00000



section .bss
alignb 8
worst:      resq 1



section .text



PROCX test_main
    call    ep_exp
    call    ep_pow
    call    ep_pow_special
    call    ep_pow_ieee
    call    ep_fract_nan_inf
ENDPX


PROCX ep_exp
    TEST    "exp"
    call    mn_bad_reset
    mov     qword [rel worst], 0
    mov     ecx, 6
    call    mn_seed
    mov     ebx, 20000
.l:
    FCONST  xmm0, -87.0
    FCONST  xmm1, 88.0
    call    mn_uniform
    movss   xmm6, xmm0
    call    math_exp
    cvtss2sd xmm7, xmm0
    cvtss2sd xmm0, xmm6
    call    ref_exp
    movapd  xmm8, xmm0
    subsd   xmm7, xmm8
    ABSD    xmm7
    divsd   xmm7, xmm8
    movsd   xmm0, [rel worst]
    maxsd   xmm0, xmm7
    movsd   [rel worst], xmm0
    JNLT    xmm7, 1e-5, .bad
    jmp     .next
.bad:
    cvtss2sd xmm0, xmm6
    movapd  xmm1, xmm8
    movapd  xmm2, xmm7
    NOTE    "exp x, ref, rel err"
.next:
    dec     ebx
    jnz     .l
    CHECK_BAD "exp relative error < 1e-5 on [-87, 88]"
    xorps   xmm0, xmm0
    call    math_exp
    CHECK_FEQ xmm0, 1.0, "exp(0) == 1"
    FCONST  xmm0, 100.0
    call    math_exp
    CHECK_FEQB xmm0, 0x7F800000, "exp(100) == inf"
    FCONST  xmm0, -200.0
    call    math_exp
    CHECK_FEQ xmm0, 0.0, "exp(-200) == 0"
    FBITS   xmm0, 0xFF800000
    call    math_exp
    CHECK_FEQ xmm0, 0.0, "exp(-inf) == 0"
    FBITS   xmm0, 0x7F800000
    call    math_exp
    CHECK_FEQB xmm0, 0x7F800000, "exp(inf) == inf"
    FBITS   xmm0, 0x7FC00000
    call    math_exp
    CHECK_NAN xmm0, "exp(NaN) is NaN"
    PRINTMAX "exp max rel err", [rel worst]
ENDPX


PROCX ep_pow
    TEST    "pow"
    call    mn_bad_reset
    mov     qword [rel worst], 0
    mov     ecx, 7
    call    mn_seed
    mov     ebx, 30000
.l:
    DCONST  xmm0, -6.0
    DCONST  xmm1, 6.0
    call    mn_uniform_d
    call    ref_pow10
    cvtsd2ss xmm6, xmm0                 ; x = f32(10^U(-6,6))
    FCONST  xmm0, -6.0
    FCONST  xmm1, 6.0
    call    mn_uniform
    movss   xmm7, xmm0
    cvtss2sd xmm0, xmm6
    cvtss2sd xmm1, xmm7
    call    ref_pow
    movapd  xmm8, xmm0
    DCONST  xmm0, 1e-37
    ucomisd xmm8, xmm0
    jbe     .next                       ; out of float range: skipped
    DCONST  xmm0, 3e38
    ucomisd xmm8, xmm0
    jae     .next
    movss   xmm0, xmm6
    movss   xmm1, xmm7
    call    math_pow
    cvtss2sd xmm9, xmm0
    subsd   xmm9, xmm8
    ABSD    xmm9
    divsd   xmm9, xmm8
    movsd   xmm0, [rel worst]
    maxsd   xmm0, xmm9
    movsd   [rel worst], xmm0
    JNLT    xmm9, 1e-5, .bad
    jmp     .next
.bad:
    cvtss2sd xmm0, xmm6
    cvtss2sd xmm1, xmm7
    movapd  xmm2, xmm9
    NOTE    "pow x, y, rel err"
.next:
    dec     ebx
    jnz     .l
    CHECK_BAD "pow relative error < 1e-5"
    PRINTMAX "pow max rel err", [rel worst]
ENDPX

; POWF a, b   -> xmm0 = math_pow(a, b) for float literals
%macro POWF 2.nolist
    FCONST  xmm0, %1
    FCONST  xmm1, %2
    call    math_pow
%endmacro


PROCX ep_pow_special
    TEST    "pow_special"
    POWF    2.0, 10.0
    CHECK_FEQ xmm0, 1024.0, "pow(2, 10) == 1024"
    POWF    2.0, 0.5
    cvtss2sd xmm0, xmm0
    DCONST  xmm1, 1.4142135623730951
    DCONST  xmm2, 1e-6
    call    mn_near_d
    CHECK_TRUE eax, "pow(2, 0.5) ~ sqrt(2)"
    POWF    123.0, 0.0
    CHECK_FEQ xmm0, 1.0, "pow(123, 0) == 1"
    POWF    1.0, 1e30
    CHECK_FEQ xmm0, 1.0, "pow(1, 1e30) == 1"
    POWF    0.0, 2.0
    CHECK_FEQ xmm0, 0.0, "pow(0, 2) == 0"
    POWF    0.0, -1.0
    CHECK_FEQB xmm0, 0x7F800000, "pow(0, -1) == inf"
    POWF    -2.0, 3.0
    CHECK_FEQ xmm0, -8.0, "pow(-2, 3) == -8"
    POWF    -2.0, 2.0
    CHECK_FEQ xmm0, 4.0, "pow(-2, 2) == 4"
    POWF    -2.0, 0.5
    CHECK_NAN xmm0, "pow(-2, 0.5) is NaN"
    POWF    10.0, 50.0
    CHECK_FEQB xmm0, 0x7F800000, "pow(10, 50) == inf"
    POWF    10.0, -50.0
    CHECK_FEQ xmm0, 0.0, "pow(10, -50) == 0"
    FBITS   xmm0, 0x7FC00000
    FCONST  xmm1, 2.0
    call    math_pow
    CHECK_NAN xmm0, "pow(NaN, 2) is NaN"
    FCONST  xmm0, 2.0
    FBITS   xmm1, 0x7FC00000
    call    math_pow
    CHECK_NAN xmm0, "pow(2, NaN) is NaN"
    FBITS   xmm0, 0x7FC00000
    xorps   xmm1, xmm1
    call    math_pow
    CHECK_FEQ xmm0, 1.0, "pow(NaN, 0) == 1"
ENDPX


PROCX ep_pow_ieee
    TEST    "pow_ieee_special_cases"
    call    mn_bad_reset
    xor     esi, esi
.x:
    xor     edi, edi
.y:
    lea     rax, [rel pow_xs]
    movss   xmm6, [rax+rsi*4]
    lea     rax, [rel pow_ys]
    movss   xmm7, [rax+rdi*4]
    movss   xmm0, xmm6
    movss   xmm1, xmm7
    call    math_pow
    movss   xmm8, xmm0
    imul    eax, esi, POW_NY
    add     eax, edi
    lea     rcx, [rel pow_want]
    movss   xmm1, [rcx+rax*4]
    movss   xmm9, xmm1
    call    mn_same
    test    eax, eax
    jnz     .next
    cvtss2sd xmm0, xmm6
    cvtss2sd xmm1, xmm7
    cvtss2sd xmm2, xmm8
    NOTE    "pow x, y, got"
.next:
    inc     edi
    cmp     edi, POW_NY
    jb      .y
    inc     esi
    cmp     esi, POW_NX
    jb      .x
    CHECK_BAD "pow follows C99/IEEE 754 on the 12x19 special-value grid"
ENDPX


PROCX ep_fract_nan_inf
    TEST    "fract_nan_inf"
    FBITS   xmm0, 0x7FC00000
    call    math_fract
    CHECK_NAN xmm0, "fract(NaN) is NaN"
    FBITS   xmm0, 0x7F800000
    call    math_fract
    CHECK_NAN xmm0, "fract(inf) is NaN"
    FBITS   xmm0, 0xFF800000
    call    math_fract
    CHECK_NAN xmm0, "fract(-inf) is NaN"
    FCONST  xmm0, 5.75
    call    math_fract
    CHECK_FEQ xmm0, 0.75, "fract(5.75) == 0.75"
    FCONST  xmm0, -5.75
    call    math_fract
    CHECK_FEQ xmm0, 0.25, "fract(-5.75) == 0.25"
ENDPX
