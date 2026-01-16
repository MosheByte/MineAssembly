; test_scalar.asm - floor/floorf, fract, clamp/lerp/smoothstep/deg2rad/sqrt, vec3 length
; and normalize. floor gets checked against roundss (exact), fract against x - floor(x)
; in double.
; @link src/math.asm tests/mathnoise/mn_helpers.asm
; @timeout 120
%include "common.inc"
%include "../mathnoise/mn_test.inc"



section .rdata
align 4
floor_edges:
    dd 0.0, -0.0, -0.5, 0.5, -1.0, 1.0, -1.0000001, -0.9999999
    dd 1073741824.0, -2147483648.0, -1e-30, 8388607.5, -8388607.5
    dd 16777216.0, -16777216.0, 2147483520.0         ; last = 2^31 - 128
FLOOR_EDGES_N equ 16

; smoothstep cases (e0, e1, x)
smooth_cases:
    dd 0.0, 1.0, 0.5
    dd 0.0, 1.0, -1.0
    dd 0.0, 1.0, 2.0
    dd 2.0, 4.0, 3.5
    dd 4.0, 2.0, 3.5
SMOOTH_N equ 5



section .bss
alignb 16
vec:        resd 4


section .text


PROCX test_main
    call    sc_floor
    call    sc_fract
    call    sc_misc
    call    sc_vec3
ENDPX


; math_floor / math_floorf vs roundss floor
PROCX chk_floor
    movss   xmm6, xmm0
    roundss xmm7, xmm0, 9  ; exact
    cvttss2si r12d, xmm7  ; all inputs fit in int32
    call    math_floor
    cmp     eax, r12d
    jne     .bad
    movss   xmm0, xmm6
    call    math_floorf
    movss   xmm8, xmm0
    movss   xmm1, xmm7
    call    mn_feq
    test    eax, eax
    jnz     .done
.bad:
    cvtss2sd xmm0, xmm6
    cvtss2sd xmm1, xmm7
    cvtss2sd xmm2, xmm8
    NOTE    "floor x, want, floorf"
.done:
ENDPX


PROCX sc_floor
    TEST    "floor"
    call    mn_bad_reset
    mov     ecx, 8
    call    mn_seed
    mov     ebx, 20000
.a:
    FCONST  xmm0, -1e6
    FCONST  xmm1, 1e6
    call    mn_uniform
    call    chk_floor
    dec     ebx
    jnz     .a
    mov     ebx, 20000
.b:
    FCONST  xmm0, -3.0
    FCONST  xmm1, 3.0
    call    mn_uniform
    call    chk_floor
    dec     ebx
    jnz     .b
    xor     ebx, ebx
.e:
    lea     rax, [rel floor_edges]
    movss   xmm0, [rax+rbx*4]
    call    chk_floor
    inc     ebx
    cmp     ebx, FLOOR_EDGES_N
    jb      .e
    CHECK_BAD "math_floor / math_floorf == floor(x) incl. edges"
    ; saturation outside int32
    FCONST  xmm0, 3e9
    call    math_floor
    CHECK_EQ32 eax, 2147483647, "floor(3e9) saturates to INT_MAX"
    FCONST  xmm0, -3e9
    call    math_floor
    CHECK_EQ32 eax, -2147483648, "floor(-3e9) saturates to INT_MIN"
    FCONST  xmm0, 1e30
    call    math_floorf
    CHECK_FEQ xmm0, 1e30, "floorf(1e30) == 1e30"
    FCONST  xmm0, -1e30
    call    math_floorf
    CHECK_FEQ xmm0, -1e30, "floorf(-1e30) == -1e30"
ENDPX


PROCX sc_fract
    TEST    "fract"
    call    mn_bad_reset
    mov     ecx, 9
    call    mn_seed
    mov     ebx, 20000
.l:
    FCONST  xmm0, -1e4
    FCONST  xmm1, 1e4
    call    mn_uniform
    movss   xmm6, xmm0
    call    math_fract
    cvtss2sd xmm7, xmm0
    xorpd   xmm0, xmm0
    ucomisd xmm7, xmm0
    jp      .bad
    jb      .bad                        ; f >= 0
    DCONST  xmm0, 1.0
    ucomisd xmm7, xmm0
    jae     .bad                        ; f < 1
    cvtss2sd xmm8, xmm6
    roundsd xmm9, xmm8, 9
    movapd  xmm10, xmm8
    subsd   xmm10, xmm9
    movapd  xmm0, xmm7
    subsd   xmm0, xmm10
    ABSD    xmm0
    ABSD    xmm8
    DCONST  xmm1, 1.0
    maxsd   xmm8, xmm1
    DCONST  xmm1, 1e-6
    mulsd   xmm8, xmm1                  ; 1e-6 * max(1, |x|)
    ucomisd xmm0, xmm8
    jb      .next
.bad:
    cvtss2sd xmm0, xmm6
    movapd  xmm1, xmm7
    movapd  xmm2, xmm10
    NOTE    "fract x, got, want"
.next:
    dec     ebx
    jnz     .l
    CHECK_BAD "fract in [0,1) and == x - floor(x)"
    FCONST  xmm0, -1e-9
    call    math_fract
    movss   xmm6, xmm0
    xor     ebx, ebx
    xorps   xmm1, xmm1
    comiss  xmm6, xmm1
    jb      .r
    FCONST  xmm1, 1.0
    comiss  xmm6, xmm1
    jae     .r
    mov     ebx, 1
.r:
    CHECK_TRUE ebx, "0 <= fract(-1e-9) < 1 (must not round to 1.0)"
    FCONST  xmm0, -0.25
    call    math_fract
    CHECK_FEQ xmm0, 0.75, "fract(-0.25) == 0.75"
ENDPX

; CALL3F fn, a, b, c   -> xmm0 = fn(a, b, c) with float literals
%macro CALL3F 4.nolist
    FCONST  xmm0, %2
    FCONST  xmm1, %3
    FCONST  xmm2, %4
    call    %1
%endmacro


PROCX sc_misc
    TEST    "clamp_lerp_smoothstep_deg"
    CALL3F  math_clamp, 5.0, 0.0, 1.0
    CHECK_FEQ xmm0, 1.0, "clamp(5,0,1) == 1"
    CALL3F  math_clamp, -5.0, 0.0, 1.0
    CHECK_FEQ xmm0, 0.0, "clamp(-5,0,1) == 0"
    CALL3F  math_clamp, 0.25, 0.0, 1.0
    CHECK_FEQ xmm0, 0.25, "clamp(0.25,0,1) == 0.25"
    CALL3F  math_lerp, 2.0, 6.0, 0.25
    CHECK_FEQ xmm0, 3.0, "lerp(2,6,0.25) == 3"
    CALL3F  math_lerp, 2.0, 6.0, 0.0
    CHECK_FEQ xmm0, 2.0, "lerp(2,6,0) == 2"
    CALL3F  math_lerp, 2.0, 6.0, 1.0
    CHECK_FEQ xmm0, 6.0, "lerp(2,6,1) == 6"
    ; smoothstep vs t*t*(3-2t), t = clamp((x-e0)/(e1-e0), 0, 1)
    call    mn_bad_reset
    xor     ebx, ebx
.s:
    imul    eax, ebx, 12
    lea     rsi, [rel smooth_cases]
    add     rsi, rax
    cvtss2sd xmm6, [rsi]
    cvtss2sd xmm7, [rsi+4]
    cvtss2sd xmm8, [rsi+8]
    movapd  xmm9, xmm8
    subsd   xmm9, xmm6
    movapd  xmm0, xmm7
    subsd   xmm0, xmm6
    divsd   xmm9, xmm0
    xorpd   xmm0, xmm0
    maxsd   xmm9, xmm0
    DCONST  xmm0, 1.0
    minsd   xmm9, xmm0
    movapd  xmm10, xmm9
    addsd   xmm10, xmm10
    DCONST  xmm0, 3.0
    subsd   xmm0, xmm10
    mulsd   xmm0, xmm9
    mulsd   xmm0, xmm9
    movapd  xmm10, xmm0
    movss   xmm0, [rsi]
    movss   xmm1, [rsi+4]
    movss   xmm2, [rsi+8]
    call    math_smoothstep
    cvtss2sd xmm0, xmm0
    movapd  xmm11, xmm0
    movapd  xmm1, xmm10
    DCONST  xmm2, 1e-6
    call    mn_near_d
    test    eax, eax
    jnz     .sn
    movapd  xmm0, xmm8
    movapd  xmm1, xmm11
    movapd  xmm2, xmm10
    NOTE    "smoothstep x, got, want"
.sn:
    inc     ebx
    cmp     ebx, SMOOTH_N
    jb      .s
    CHECK_BAD "smoothstep == t*t*(3-2t) (incl. reversed edges)"
    CALL3F  math_smoothstep, 1.0, 1.0, 0.5
    CHECK_FEQ xmm0, 0.0, "smoothstep(1,1,0.5) == 0 (degenerate edges)"
    CALL3F  math_smoothstep, 1.0, 1.0, 1.5
    CHECK_FEQ xmm0, 1.0, "smoothstep(1,1,1.5) == 1 (degenerate edges)"
    FCONST  xmm0, 180.0
    call    math_deg2rad
    cvtss2sd xmm0, xmm0
    DCONST  xmm1, 3.141592653589793
    DCONST  xmm2, 1e-6
    call    mn_near_d
    CHECK_TRUE eax, "deg2rad(180) ~ pi"
    FCONST  xmm0, 16.0
    call    math_sqrt
    CHECK_FEQ xmm0, 4.0, "sqrt(16) == 4"
ENDPX

; NEAR_COMP idx, want_double, "msg"   |vec[idx] - want| < 1e-7
%macro NEAR_COMP 3.nolist
    lea     rax, [rel vec]
    cvtss2sd xmm0, [rax+(%1)*4]
    DCONST  xmm1, %2
    DCONST  xmm2, 1e-7
    call    mn_near_d
    CHECK_TRUE eax, %3
%endmacro


PROCX sc_vec3
    TEST    "vec3"
    lea     rcx, [rel vec]
    mov     dword [rcx], __?float32?__(3.0)
    mov     dword [rcx+4], __?float32?__(4.0)
    mov     dword [rcx+8], __?float32?__(12.0)
    call    vec3_length
    CHECK_FEQ xmm0, 13.0, "|(3,4,12)| == 13"
    lea     rcx, [rel vec]
    call    vec3_normalize
    NEAR_COMP 0, 0.23076923076923078, "normalize x == 3/13"
    NEAR_COMP 1, 0.3076923076923077, "normalize y == 4/13"
    NEAR_COMP 2, 0.9230769230769231, "normalize z == 12/13"
    lea     rcx, [rel vec]
    xor     eax, eax
    mov     [rcx], rax
    mov     [rcx+8], rax
    call    vec3_normalize              ; must not produce NaN
    lea     rax, [rel vec]
    mov     ecx, [rax]
    or      ecx, [rax+4]
    or      ecx, [rax+8]
    and     ecx, 0x7FFFFFFF             ; +-0 allowed
    CHECK_EQ32 ecx, 0, "normalize(0,0,0) stays (0,0,0)"
ENDPX
