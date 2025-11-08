; testlib.inc - the test framework. a test is tests/<module>/test_*.asm with a
; PROC test_main; testlib.asm has `start`, exit code = failed checks.
; header directives in the first 40 lines: @link, @timeout, @gpu, @preview
%ifndef TESTLIB_INC
%define TESTLIB_INC

%ifndef IMPL_TESTLIB
; these only trash rax/rcx/rdx/r8-r11/xmm0-5
extern t_print              ; (rcx zstr)
extern t_print_int          ; (rcx int64)
extern t_print_hex          ; (rcx u64)
extern t_print_float        ; (xmm0 float, edx decimals)
extern t_print_double       ; (xmm0 double, edx decimals)
extern t_newline
extern t_begin              ; (rcx group name)
extern t_pass
extern t_fail               ; (rcx msg, rdx file, r8d line)
extern t_fail_detail        ; (rcx zstr) extra line under the last failure
extern t_check_eq64         ; (rcx got, rdx want, r8 msg, r9 file, ARG5 line) -> eax 1 ok
extern t_check_near         ; (xmm0 got, xmm1 want, xmm2 tol, r9 msg, ARG5 file, ARG6 line)
extern t_check_near_d       ; same, doubles
extern t_check_mem          ; (rcx a, rdx b, r8 len, r9 msg, ARG5 file, ARG6 line)
extern t_check_str          ; (rcx got, rdx want, r8 msg, r9 file, ARG5 line)
extern t_failures
extern t_checks
extern t_rng_seed           ; own xorshift64*, doesn't touch the game's rng
extern t_rng_next
extern t_rng_float          ; [0,1)
extern t_alloc              ; zeroed, never freed
extern t_write_bmp          ; (rcx path, rdx rgba top row first, r8d w, r9d h)
extern t_time_ms
extern t_abi_call           ; (rcx fn, rdx args) -> rax, xmm0, ecx clobber mask
                            ; args: a1..a4 (also in xmm0-3 as raw bits), nstack, stack[0..7]
                            ; mask: bit0 rbx 1 rbp 2 rsi 3 rdi 4-7 r12-r15, 8-17 xmm6-15, 31 rsp
extern t_abi_mask_name      ; (ecx mask, rdx buf >= 128)
%endif

; with NASM 3, .nolist makes __?FILE?__/__?LINE?__ in these macros point at the
; caller's line instead of this file. wrapper macros in tests need it too.
%macro TEST 1.nolist
    section .rdata
    %%n: db %1, 0
    section .text
    lea  rcx, [rel %%n]
    call t_begin
%endmacro

%macro _T_STRS 1.nolist
    section .rdata
    %%m: db %1, 0
    %%f: db __?FILE?__, 0
    section .text
    %define _T_MSG %%m
    %define _T_FILE %%f
%endmacro

; passes when nonzero
%macro CHECK_TRUE 2.nolist
    section .rdata
    %%m: db %2, 0
    %%f: db __?FILE?__, 0
    section .text
    mov  eax, %1
    test eax, eax
    jz   %%bad
    call t_pass
    jmp  %%ok
%%bad:
    lea  rcx, [rel %%m]
    lea  rdx, [rel %%f]
    mov  r8d, __?LINE?__
    call t_fail
%%ok:
%endmacro

%macro CHECK_EQ 3.nolist
    section .rdata
    %%m: db %3, 0
    %%f: db __?FILE?__, 0
    section .text
    mov  rcx, %1
    mov  rdx, %2
    lea  r8,  [rel %%m]
    lea  r9,  [rel %%f]
    mov  qword [rsp+32], __?LINE?__
    call t_check_eq64
%endmacro

; 32-bit, both sides sign extended
%macro CHECK_EQ32 3.nolist
    section .rdata
    %%m: db %3, 0
    %%f: db __?FILE?__, 0
    section .text
    mov   eax, %1
    movsxd rcx, eax
    mov   eax, %2
    movsxd rdx, eax
    lea   r8,  [rel %%m]
    lea   r9,  [rel %%f]
    mov   qword [rsp+32], __?LINE?__
    call  t_check_eq64
%endmacro

; CHECK_NEAR xmm, want literal, tol literal, "msg" (floats)
%macro CHECK_NEAR 4.nolist
    section .rdata
    %%m: db %4, 0
    %%f: db __?FILE?__, 0
    section .text
    movss xmm0, %1
    mov   eax, __?float32?__(%2)
    movd  xmm1, eax
    mov   eax, __?float32?__(%3)
    movd  xmm2, eax
    lea   r9,  [rel %%m]
    lea   rax, [rel %%f]
    mov   [rsp+32], rax
    mov   qword [rsp+40], __?LINE?__
    call  t_check_near
%endmacro

; want in a register
%macro CHECK_NEAR_X 4.nolist
    section .rdata
    %%m: db %4, 0
    %%f: db __?FILE?__, 0
    section .text
    movss xmm0, %1
    movss xmm1, %2
    mov   eax, __?float32?__(%3)
    movd  xmm2, eax
    lea   r9,  [rel %%m]
    lea   rax, [rel %%f]
    mov   [rsp+32], rax
    mov   qword [rsp+40], __?LINE?__
    call  t_check_near
%endmacro

%macro CHECK_MEM 4.nolist
    section .rdata
    %%m: db %4, 0
    %%f: db __?FILE?__, 0
    section .text
    mov   rcx, %1
    mov   rdx, %2
    mov   r8,  %3
    lea   r9,  [rel %%m]
    lea   rax, [rel %%f]
    mov   [rsp+32], rax
    mov   qword [rsp+40], __?LINE?__
    call  t_check_mem
%endmacro

%macro CHECK_STR 3.nolist
    section .rdata
    %%w: db %2, 0
    %%m: db %3, 0
    %%f: db __?FILE?__, 0
    section .text
    mov   rcx, %1
    lea   rdx, [rel %%w]
    lea   r8,  [rel %%m]
    lea   r9,  [rel %%f]
    mov   qword [rsp+32], __?LINE?__
    call  t_check_str
%endmacro

; no newline
%macro PRINT 1.nolist
    section .rdata
    %%s: db %1, 0
    section .text
    lea  rcx, [rel %%s]
    call t_print
%endmacro

%endif
