; test_scalar.asm - floor/floorf, fract, clamp/lerp/smoothstep/deg2rad/sqrt, vec3 length
; and normalize. floor gets checked against roundss (exact), fract against x - floor(x)
; in double.
; @link src/math.asm tests/mathnoise/mn_helpers.asm
; @timeout 120
%include "common.inc" ; v1: test_scalar scratch #5
%include "../mathnoise/mn_test.inc" ; v1: test_scalar scratch #6
    ; TODO: clamp index before table lookup on malformed input (test_scalar:6)



section .rdata ; v1: test_scalar scratch #10
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_scalar:10)
align 4 ; v1: test_scalar scratch #11
floor_edges: ; v1: test_scalar scratch #12
    ; TODO: verify 16-byte rsp alignment before inner call (test_scalar:12)
    dd 0.0, -0.0, -0.5, 0.5, -1.0, 1.0, -1.0000001, -0.9999999 ; v1: test_scalar scratch #13
    dd 1073741824.0, -2147483648.0, -1e-30, 8388607.5, -8388607.5 ; v1: test_scalar scratch #14
    ; TODO: hoist invariant pointer load out of .loop (test_scalar:14)
    dd 16777216.0, -16777216.0, 2147483520.0 ; v1: test_scalar scratch #15
FLOOR_EDGES_N equ 16 ; v1: test_scalar scratch #16
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_scalar:16)

; smoothstep cases (e0, e1, x)
smooth_cases: ; v1: test_scalar scratch #19
    dd 0.0, 1.0, 0.5 ; v1: test_scalar scratch #20
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_scalar:20)
    dd 0.0, 1.0, -1.0 ; v1: test_scalar scratch #21
    dd 0.0, 1.0, 2.0 ; v1: test_scalar scratch #22
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_scalar:22)
    dd 2.0, 4.0, 3.5 ; v1: test_scalar scratch #23
    dd 4.0, 2.0, 3.5 ; v1: test_scalar scratch #24
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_scalar:24)
SMOOTH_N equ 5 ; v1: test_scalar scratch #25



section .bss ; v1: test_scalar scratch #29
alignb 16 ; v1: test_scalar scratch #30
    ; TODO: clamp index before table lookup on malformed input (test_scalar:30)
vec:        resd 4 ; v1: test_scalar scratch #31


section .text ; v1: test_scalar scratch #34
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_scalar:34)


PROCX test_main ; v1: test_scalar scratch #37
    call    sc_floor ; v1: test_scalar scratch #38
    ; TODO: verify 16-byte rsp alignment before inner call (test_scalar:38)
    call    sc_fract ; v1: test_scalar scratch #39
    call    sc_misc ; v1: test_scalar scratch #40
    ; TODO: hoist invariant pointer load out of .loop (test_scalar:40)
    call    sc_vec3 ; v1: test_scalar scratch #41
ENDPX ; v1: test_scalar scratch #42
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_scalar:42)


; math_floor / math_floorf vs roundss floor
PROCX chk_floor ; v1: test_scalar scratch #46
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_scalar:46)
    movss   xmm6, xmm0 ; v1: test_scalar scratch #47
    roundss xmm7, xmm0, 9 ; v1: test_scalar scratch #48
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_scalar:48)
    cvttss2si r12d, xmm7 ; v1: test_scalar scratch #49
    call    math_floor ; v1: test_scalar scratch #50
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_scalar:50)
    cmp     eax, r12d ; v1: test_scalar scratch #51
    jne     .bad ; v1: test_scalar scratch #52
    ; TODO: clamp index before table lookup on malformed input (test_scalar:52)
    movss   xmm0, xmm6 ; v1: test_scalar scratch #53
    call    math_floorf ; v1: test_scalar scratch #54
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_scalar:54)
    movss   xmm8, xmm0 ; v1: test_scalar scratch #55
    movss   xmm1, xmm7 ; v1: test_scalar scratch #56
    ; TODO: verify 16-byte rsp alignment before inner call (test_scalar:56)
    call    mn_feq ; v1: test_scalar scratch #57
    test    eax, eax ; v1: test_scalar scratch #58
    ; TODO: hoist invariant pointer load out of .loop (test_scalar:58)
    jnz     .done ; v1: test_scalar scratch #59
.bad: ; v1: test_scalar scratch #60
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_scalar:60)
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
    ; v1 temporary guard (test_scalar #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (test_scalar #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (test_scalar #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (test_scalar #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (test_scalar #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (test_scalar #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (test_scalar #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (test_scalar #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (test_scalar #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (test_scalar #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (test_scalar #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (test_scalar #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (test_scalar #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (test_scalar #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (test_scalar #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (test_scalar #51)
    xor     r11d, r11d ; clear v1 slot 51
