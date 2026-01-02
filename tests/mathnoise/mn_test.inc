; mn_test.inc - shared externs + macros for the math/noise tests. include after
; common.inc as "../mathnoise/mn_test.inc" (tests\lib is on -I). usual loop shape:
; mn_bad_reset, NOTE on each bad sample, one CHECK_BAD at the end.
%ifndef MN_TEST_INC
%define MN_TEST_INC

%include "testlib.inc"

%ifndef IMPL_MN_HELPERS
extern mn_bad
extern mn_bad_reset
extern mn_bad_note  ; count + print the first 3
extern mn_seed
extern mn_u01d
extern mn_uniform
extern mn_uniform_d
extern mn_logspread  ; +-10^U(lo,hi)
extern mn_randint
extern mn_feq  ; IEEE ==, so +0 == -0
extern mn_same  ; bit-identical or both NaN
extern mn_isnan
extern mn_near_d
extern ref_sincos  ; exact reduction, any finite float
extern ref_sincos_d  ; |x| < 2^19 only
extern ref_tan
extern ref_atan2
extern ref_exp
extern ref_pow
extern ref_pow10
extern ref_sqrt_d
extern ref_murmur
extern ref_splitmix  ; the state the way rng_seed builds it
extern mn_count_unique_u32  ; sorts the array in place
extern mn_f2d
extern mn_close
extern ref_mul_d  ; column-major, dst can't alias
extern ref_rot_d
extern ref_planes_d
extern mn_print_max
%endif

%ifndef IMPL_MN_REFNOISE
extern refn_init
extern refn_noise2
extern refn_noise3
%endif

%ifndef IMPL_MN_ABI
extern abi_call  ; lives in abi_check.asm
extern mn_ctx  ; 168 bytes
extern mn_abi_viol
extern mn_ctx_reset  ; xmm slots get NaN + garbage lanes
extern mn_ctx_i32  ; upper half is garbage
extern mn_ctx_q
extern mn_ctx_f  ; garbage lanes / upper dword
extern mn_acall
%endif

; DCONST xmm0, 1.5
%macro DCONST 2.nolist
    mov  rax, __?float64?__(%2)
    movq %1, rax
%endmacro

%macro FBITS 2.nolist
    mov  eax, %2
    movd %1, eax
%endmacro

; all .nolist so __?LINE?__ in the nested CHECK_* points at the test's line

%macro CHECK_BAD 1.nolist
    CHECK_EQ32 [rel mn_bad], 0, %1
%endmacro

%macro CHECK_FEQ 3.nolist
    movss xmm0, %1
    mov   eax, __?float32?__(%2)
    movd  xmm1, eax
    call  mn_feq
    CHECK_TRUE eax, %3
%endmacro

%macro CHECK_FEQB 3.nolist
    movss xmm0, %1
    mov   eax, %2
    movd  xmm1, eax
    call  mn_feq
    CHECK_TRUE eax, %3
%endmacro

%macro CHECK_NAN 2.nolist
    movss xmm0, %1
    call  mn_isnan
    CHECK_TRUE eax, %2
%endmacro

; xmm0-2 already loaded
%macro NOTE 1.nolist
    section .rdata
    %%s: db %1, 0
    section .text
    lea  rcx, [rel %%s]
    call mn_bad_note
%endmacro

%macro PRINTMAX 2.nolist
    section .rdata
    %%s: db %1, 0
    section .text
    movsd xmm0, %2
    lea  rcx, [rel %%s]
    call mn_print_max
%endmacro

; jumps unless value < literal, NaN jumps too. clobbers rax, xmm5
%macro JNLT 3.nolist
    mov  rax, __?float64?__(%2)
    movq xmm5, rax
    ucomisd %1, xmm5
    jp   %3
    jae  %3
%endmacro

; clobbers rax, xmm5, clears the upper lane
%macro ABSD 1.nolist
    mov  rax, 0x7FFFFFFFFFFFFFFF
    movq xmm5, rax
    andpd %1, xmm5
%endmacro

%macro FMAXD 2.nolist
    maxsd %1, %2
%endmacro

%endif
