; test_trig.asm - sin/cos/sincos/tan/atan2 vs the x87 refs in mn_helpers.asm. huge args
; go all the way to FLT_MAX since ref_sincos reduces exactly. sincos has to match
; math_sin/math_cos bit for bit.
; @link src/math.asm tests/mathnoise/mn_helpers.asm
; @timeout 120
%include "common.inc"
%include "../mathnoise/mn_test.inc"



section .rdata
align 8

; (y bits, x bits, expected atan2 double)
atan2_special:
    dd 0x00000000, 0x3F800000
    dq 0x0000000000000000               ; atan2(0, 1)      = 0
    dd 0x3F800000, 0x00000000
    dq 0x3FF921FB54442D18               ; atan2(1, 0)      = pi/2
    dd 0x00000000, 0xBF800000
    dq 0x400921FB54442D18               ; atan2(0, -1)     = pi
    dd 0xBF800000, 0x00000000
    dq 0xBFF921FB54442D18               ; atan2(-1, 0)     = -pi/2
    dd 0x3F800000, 0x3F800000
    dq 0x3FE921FB54442D18               ; atan2(1, 1)      = pi/4
    dd 0xBF800000, 0xBF800000
    dq 0xC002D97C7F3321D2               ; atan2(-1, -1)    = -3pi/4
    dd 0x00000000, 0x00000000
    dq 0x0000000000000000               ; atan2(0, 0)      = 0
    dd 0x80000000, 0x00000000
    dq 0x8000000000000000               ; atan2(-0, 0)     = -0
    dd 0x00000000, 0x80000000
    dq 0x400921FB54442D18               ; atan2(0, -0)     = pi
    dd 0x80000000, 0x80000000
    dq 0xC00921FB54442D18               ; atan2(-0, -0)    = -pi
    dd 0x40A00000, 0x7F800000
    dq 0x0000000000000000               ; atan2(5, inf)    = 0
    dd 0x7F800000, 0x40A00000
    dq 0x3FF921FB54442D18               ; atan2(inf, 5)    = pi/2
    dd 0x7F800000, 0x7F800000
    dq 0x3FE921FB54442D18               ; atan2(inf, inf)  = pi/4
    dd 0xFF800000, 0xFF800000
    dq 0xC002D97C7F3321D2               ; atan2(-inf,-inf) = -3pi/4
    dd 0x40400000, 0xFF800000
    dq 0x400921FB54442D18               ; atan2(3, -inf)   = pi
ATAN2_SPECIAL_N equ 15



; extra sin/cos inputs: 0, -0, f32(pi/4), f32(-pi/4), f32(pi), 1e5, -1e5
trig_special:
    dd 0x00000000, 0x80000000, 0x3F490FDB, 0xBF490FDB, 0x40490FDB, 100000.0, -100000.0
TRIG_SPECIAL_N equ 7



section .bss
alignb 8
worst:      resq 1



section .text



PROCX test_main
    call    trig_accuracy
    call    trig_huge
    call    trig_sincos
    call    trig_special_cases
    call    trig_tan
    call    trig_atan2
ENDPX


; tracks the worst error in [worst], notes anything >= 2e-6
PROCX chk_sincos
    movss   xmm6, xmm0
    call    math_sin
    movss   xmm7, xmm0
    movss   xmm0, xmm6
    call    math_cos
    movss   xmm8, xmm0
    movss   xmm0, xmm6
    call    ref_sincos
    cvtss2sd xmm9, xmm7
    subsd   xmm9, xmm0
    ABSD    xmm9
    cvtss2sd xmm10, xmm8
    subsd   xmm10, xmm1
    ABSD    xmm10
    movsd   xmm2, [rel worst]
    maxsd   xmm2, xmm9
    maxsd   xmm2, xmm10
    movsd   [rel worst], xmm2
    JNLT    xmm9, 2e-6, .bad
    JNLT    xmm10, 2e-6, .bad
    jmp     .done
.bad:
    cvtss2sd xmm0, xmm6
    movapd  xmm1, xmm9
    movapd  xmm2, xmm10
    NOTE    "sin/cos x, err_sin, err_cos"
.done:
ENDPX



PROCX trig_accuracy
    TEST    "sin_cos_accuracy"
    call    mn_bad_reset
    mov     qword [rel worst], 0
    mov     ecx, 1
    call    mn_seed
    mov     ebx, 30000
.a:
    FCONST  xmm0, -1e5
    FCONST  xmm1, 1e5
    call    mn_uniform
    call    chk_sincos
    dec     ebx
    jnz     .a
    mov     ebx, 20000
.b:
    FCONST  xmm0, -7.0
    FCONST  xmm1, 7.0
    call    mn_uniform
    call    chk_sincos
    dec     ebx
    jnz     .b
    mov     ebx, 5000
.c:
    FCONST  xmm0, -8.0
    FCONST  xmm1, 0.0
    call    mn_logspread
    call    chk_sincos
    dec     ebx
    jnz     .c
    ; k*pi/2 + d for k = -2000, -1993, ... while k < 2000, and d = 0, 1e-4, -1e-4
    mov     ebx, -2000
.k:
    cvtsi2sd xmm6, ebx
    DCONST  xmm0, 3.141592653589793
    mulsd   xmm6, xmm0
    DCONST  xmm0, 2.0
    divsd   xmm6, xmm0
    cvtsd2ss xmm0, xmm6
    call    chk_sincos
    DCONST  xmm0, 1e-4
    addsd   xmm0, xmm6
    cvtsd2ss xmm0, xmm0
    call    chk_sincos
    DCONST  xmm0, -1e-4
    addsd   xmm0, xmm6
    cvtsd2ss xmm0, xmm0
    call    chk_sincos
    add     ebx, 7
    cmp     ebx, 2000
    jl      .k
    xor     ebx, ebx
.s:
    lea     rax, [rel trig_special]
    movss   xmm0, [rax+rbx*4]
    call    chk_sincos
    inc     ebx
    cmp     ebx, TRIG_SPECIAL_N
    jb      .s
    CHECK_BAD "sin/cos abs error < 2e-6 for |x| <= 1e5"
    PRINTMAX "sin/cos max abs err over |x|<1e5", [rel worst]
ENDPX


PROCX trig_huge
    TEST    "sin_cos_huge_arguments"
    call    mn_bad_reset
    mov     qword [rel worst], 0
    mov     ecx, 2
    call    mn_seed
    mov     ebx, 20000
.a:
    FCONST  xmm0, 5.8
    FCONST  xmm1, 38.0
    call    mn_logspread
    call    chk_sincos
    dec     ebx
    jnz     .a
    mov     ebx, 19                     ; 2^19 .. 2^127
.p:
    lea     eax, [rbx+127]
    shl     eax, 23
    movd    xmm0, eax
    call    chk_sincos
    inc     ebx
    cmp     ebx, 128
    jb      .p
    FBITS   xmm0, 0x7F7FFFFF            ; FLT_MAX
    call    chk_sincos
    FBITS   xmm0, 0xFF7FFFFF            ; -FLT_MAX
    call    chk_sincos
    CHECK_BAD "sin/cos abs error < 2e-6 for 6e5 < |x| < 3.4e38 (Payne-Hanek)"
    PRINTMAX "sin/cos max abs err for huge |x|", [rel worst]
ENDPX


PROCX trig_sincos
    TEST    "sincos_matches_sin_cos"
    call    mn_bad_reset
    mov     ecx, 3
    call    mn_seed
    mov     ebx, 2000
.l:
    FCONST  xmm0, -1000.0
    FCONST  xmm1, 1000.0
    call    mn_uniform
    movss   xmm6, xmm0
    call    math_sincos
    movss   xmm7, xmm0
    movss   xmm8, xmm1
    movss   xmm0, xmm6
    call    math_sin
    movd    eax, xmm0
    movd    ecx, xmm7
    cmp     eax, ecx
    jne     .bad
    movss   xmm0, xmm6
    call    math_cos
    movd    eax, xmm0
    movd    ecx, xmm8
    cmp     eax, ecx
    je      .next
.bad:
    cvtss2sd xmm0, xmm6
    cvtss2sd xmm1, xmm7
    cvtss2sd xmm2, xmm8
    NOTE    "sincos x, sin, cos"
.next:
    dec     ebx
    jnz     .l
    CHECK_BAD "math_sincos xmm0/xmm1 bit-identical to math_sin/math_cos"
ENDPX


PROCX trig_special_cases
    TEST    "sin_cos_special"
    FBITS   xmm0, 0x7F800000
    call    math_sin
    CHECK_NAN xmm0, "sin(inf) is NaN"
    FBITS   xmm0, 0xFF800000
    call    math_cos
    CHECK_NAN xmm0, "cos(-inf) is NaN"
    FBITS   xmm0, 0x7FC00000
    call    math_sin
    CHECK_NAN xmm0, "sin(NaN) is NaN"
    FBITS   xmm0, 0x7FC00000
    call    math_cos
    CHECK_NAN xmm0, "cos(NaN) is NaN"
    xorps   xmm0, xmm0
    call    math_sin
    CHECK_FEQ xmm0, 0.0, "sin(0) == 0"
    xorps   xmm0, xmm0
    call    math_cos
    CHECK_FEQ xmm0, 1.0, "cos(0) == 1"
    FBITS   xmm0, 0x80000000
    call    math_sin
    movd    eax, xmm0
    shr     eax, 31
    CHECK_EQ32 eax, 1, "sin(-0) keeps the sign of zero"
ENDPX


PROCX trig_tan
    TEST    "tan"
    call    mn_bad_reset
    mov     ecx, 4
    call    mn_seed
    mov     ebx, 20000
.l:
    FCONST  xmm0, -50.0
    FCONST  xmm1, 50.0
    call    mn_uniform
    movss   xmm6, xmm0
    call    ref_sincos
    movapd  xmm7, xmm1
    ABSD    xmm7
    JNLT    xmm7, 1e-3, .ok  ; near a pole -> skip
    jmp     .next
.ok:
    movss   xmm0, xmm6
    call    ref_tan
    movapd  xmm8, xmm0
    movss   xmm0, xmm6
    call    math_tan
    cvtss2sd xmm9, xmm0
    subsd   xmm9, xmm8
    ABSD    xmm9
    movapd  xmm10, xmm8
    ABSD    xmm10
    DCONST  xmm0, 1.0
    maxsd   xmm10, xmm0
    DCONST  xmm0, 2e-6
    mulsd   xmm10, xmm0
    divsd   xmm10, xmm7  ; 2e-6*max(1,|tan|)/|cos|
    ucomisd xmm10, xmm9
    jp      .bad
    jae     .next
.bad:
    cvtss2sd xmm0, xmm6
    movapd  xmm1, xmm8
    movapd  xmm2, xmm9
    NOTE    "tan x, ref, err"
.next:
    dec     ebx
    jnz     .l
    CHECK_BAD "tan error <= 2e-6*max(1,|tan|)/|cos| (|cos| >= 1e-3)"
ENDPX


PROCX trig_atan2
    TEST    "atan2_all_quadrants"
    call    mn_bad_reset
    mov     qword [rel worst], 0
    mov     ecx, 5
    call    mn_seed
    mov     ebx, 40000
.l:
    FCONST  xmm0, -6.0
    FCONST  xmm1, 6.0
    call    mn_logspread
    movss   xmm6, xmm0
    FCONST  xmm0, -6.0
    FCONST  xmm1, 6.0
    call    mn_logspread
    movss   xmm7, xmm0
    movss   xmm0, xmm6
    movss   xmm1, xmm7
    call    math_atan2
    cvtss2sd xmm8, xmm0
    movss   xmm0, xmm6
    movss   xmm1, xmm7
    call    ref_atan2
    subsd   xmm8, xmm0
    ABSD    xmm8
    movsd   xmm0, [rel worst]
    maxsd   xmm0, xmm8
    movsd   [rel worst], xmm0
    JNLT    xmm8, 1e-5, .bad
    jmp     .next
.bad:
    cvtss2sd xmm0, xmm6
    cvtss2sd xmm1, xmm7
    movapd  xmm2, xmm8
    NOTE    "atan2 y, x, err"
.next:
    dec     ebx
    jnz     .l
    CHECK_BAD "atan2 abs error < 1e-5 over 1e-6 < |y|,|x| < 1e6"
    ; IEEE special cases
    call    mn_bad_reset
    xor     ebx, ebx
.s:
    lea     rsi, [rel atan2_special]
    imul    eax, ebx, 16
    add     rsi, rax
    movss   xmm0, [rsi]
    movss   xmm1, [rsi+4]
    call    math_atan2
    movss   xmm6, xmm0
    cvtss2sd xmm7, xmm0
    subsd   xmm7, [rsi+8]
    ABSD    xmm7
    JNLT    xmm7, 1e-6, .sbad
    movd    eax, xmm6
    shr     eax, 31
    mov     rcx, [rsi+8]
    shr     rcx, 63
    cmp     eax, ecx
    je      .snext
.sbad:
    cvtss2sd xmm0, [rsi]
    cvtss2sd xmm1, [rsi+4]
    cvtss2sd xmm2, xmm6
    NOTE    "atan2 special y, x, got"
.snext:
    inc     ebx
    cmp     ebx, ATAN2_SPECIAL_N
    jb      .s
    CHECK_BAD "atan2 axes / diagonals / signed zeros / infinities follow IEEE"
    FBITS   xmm0, 0x7FC00000
    FCONST  xmm1, 1.0
    call    math_atan2
    CHECK_NAN xmm0, "atan2(NaN, 1) is NaN"
    PRINTMAX "atan2 max abs err", [rel worst]
ENDPX
