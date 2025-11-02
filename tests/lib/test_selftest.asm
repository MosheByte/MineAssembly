; test_selftest.asm - pokes every testlib function, failure paths included.
; the deliberate failures get taken back off the count so this still exits 0,
; their FAIL lines say (expected).

; @timeout 30


%include "common.inc"
%include "testlib.inc"

extern t_fmt_double  ; not in testlib.inc
extern DeleteFileA

; for checks that have to fail: wants eax == 0 and exactly one new failure,
; then takes it back off t_failures
;   EXPECT_FAIL_BEGIN  /  <check macro>  /  EXPECT_FAIL_END "what"
%macro EXPECT_FAIL_BEGIN 0.nolist
    mov  r12d, [rel t_failures]
%endmacro
%macro EXPECT_FAIL_END 1.nolist
    mov  r13d, eax
    mov  r14d, [rel t_failures]
    mov  [rel t_failures], r12d
    sub  r14d, r12d
    CHECK_EQ32 r13d, 0, %1
    CHECK_EQ32 r14d, 1, %1
%endmacro

; FMTCHK double_literal, decimals, "expected"
%macro FMTCHK 3.nolist
    mov  rax, __?float64?__(%1)
    movq xmm1, rax
    lea  rcx, LOC(0)
    mov  r8d, %2
    call t_fmt_double
    lea  rbx, LOC(0)
    CHECK_STR rbx, %3, %3
%endmacro

section .data
align 8
abi_args:   dq 1, 2, 3, 4
            dq 2                        ; nstack
            dq 100, 200, 0, 0, 0, 0, 0, 0
blob_a:     db 1, 2, 3, 4, 5, 6, 7, 8
blob_b:     db 1, 2, 3, 4, 5, 9, 7, 8
bmp_px:     db 10,20,30,255, 40,50,60,255, 70,80,90,255
            db 1,2,3,0, 4,5,6,0, 7,8,9,0
; golden 3x2 24-bit BMP
bmp_gold:   db 0x42,0x4D,0x4E,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x36,0x00,0x00,0x00,0x28,0x00
            db 0x00,0x00,0x03,0x00,0x00,0x00,0x02,0x00,0x00,0x00,0x01,0x00,0x18,0x00,0x00,0x00
            db 0x00,0x00,0x18,0x00,0x00,0x00,0x13,0x0B,0x00,0x00,0x13,0x0B,0x00,0x00,0x00,0x00
            db 0x00,0x00,0x00,0x00,0x00,0x00,0x03,0x02,0x01,0x06,0x05,0x04,0x09,0x08,0x07,0x00
            db 0x00,0x00,0x1E,0x14,0x0A,0x3C,0x32,0x28,0x5A,0x50,0x46,0x00,0x00,0x00
bmp_name:   db "selftest.bmp", 0

section .text

; abi checker victims
PROC abi_good                           ; returns a1+a2+a3+a4+stack0+stack1
    lea  rax, [rcx+rdx]
    add  rax, r8
    add  rax, r9
    add  rax, ARG5
    add  rax, ARG6
ENDP

LEAF abi_xmm                            ; rax = xmm1 bits, xmm0 left = a1
    movq rax, xmm1
    ret

LEAF abi_bad
    xor  ebx, ebx
    xorps xmm7, xmm7
    ret

LEAF abi_badmany
    xor  r15d, r15d
    mov  rdi, rsp
    pcmpeqb xmm15, xmm15
    ret

LEAF abi_rsp                            ; returns with rsp 8 too high
    pop  r10
    add  rsp, 8
    jmp  r10

LEAF abi_align                          ; rax = (rsp+8) & 15, 0 when caller aligned
    lea  rax, [rsp+8]
    and  eax, 15
    ret

PROC test_main, 512

    TEST "printing"
    PRINT "print_int: "
    mov  rcx, -123
    call t_print_int
    PRINT " "
    mov  rcx, 0x8000000000000000
    call t_print_int
    PRINT "  print_hex: "
    mov  rcx, 0xDEADBEEF
    call t_print_hex
    PRINT " "
    xor  ecx, ecx
    call t_print_hex
    PRINT "  print_float(1/3,4): "
    FCONST xmm0, 0.33333333
    mov  edx, 4
    call t_print_float
    PRINT "  print_double(-2.5e-3,6): "
    mov  rax, __?float64?__(-2.5e-3)
    movq xmm0, rax
    mov  edx, 6
    call t_print_double
    call t_newline
    xor  ecx, ecx
    call t_print
    call t_newline


    TEST "float formatting"
    FMTCHK 3.14159, 2, "3.14"
    FMTCHK 0.125, 2, "0.12"
    FMTCHK 0.375, 2, "0.38"
    FMTCHK 2.5, 0, "2"
    FMTCHK 3.5, 0, "4"
    FMTCHK -0.0001, 2, "-0.00"
    FMTCHK 0.9999, 3, "1.000"
    FMTCHK 1.0e20, 1, "100000000000000000000.0"
    FMTCHK 123456.789, 3, "123456.789"
    FMTCHK 1.005, 2, "1.00"
    FMTCHK -7.25, 1, "-7.2"
    FMTCHK 0.1, 17, "0.10000000000000001"
    FMTCHK 42.0, 0, "42"
    FMTCHK 1.5, -3, "2"
    FMTCHK 0.0, 3, "0.000"
    FMTCHK __?Infinity?__, 2, "inf"
    FMTCHK -__?Infinity?__, 2, "-inf"
    FMTCHK __?QNaN?__, 2, "nan"


    TEST "passing checks"
    CHECK_TRUE 1, "check_true"
    mov  rbx, 0x123456789
    CHECK_EQ rbx, 0x123456789, "check_eq"
    mov  esi, -5
    CHECK_EQ32 esi, -5, "check_eq32"
    FCONST xmm0, 1.0
    CHECK_NEAR xmm0, 1.00001, 0.0001, "check_near"
    FCONST xmm0, 2.0
    FCONST xmm1, 2.5
    CHECK_NEAR_X xmm0, xmm1, 0.5, "check_near_x (diff == tol)"
    lea  rbx, [rel blob_a]
    CHECK_MEM rbx, rbx, 8, "check_mem"
    lea  rbx, [rel bmp_name]
    CHECK_STR rbx, "selftest.bmp", "check_str"
    mov  rax, __?float64?__(1.0e-12)
    movq xmm0, rax
    pxor xmm1, xmm1
    mov  rax, __?float64?__(1.0e-11)
    movq xmm2, rax
    lea  r9, [rel bmp_name]
    lea  rax, [rel bmp_name]
    mov  [rsp+32], rax
    mov  qword [rsp+40], __?LINE?__
    call t_check_near_d
    CHECK_EQ32 eax, 1, "check_near_d returns 1"


    TEST "failure paths (expected)"
    EXPECT_FAIL_BEGIN
    CHECK_EQ -1, 7, "(expected) eq64 mismatch"
    EXPECT_FAIL_END "eq64 fail path"
    EXPECT_FAIL_BEGIN
    FCONST xmm0, 1.0
    CHECK_NEAR xmm0, 1.5, 0.25, "(expected) near mismatch"
    EXPECT_FAIL_END "near fail path"
    EXPECT_FAIL_BEGIN
    mov  eax, 0x7FC00000                ; NaN never passes
    movd xmm0, eax
    CHECK_NEAR xmm0, 0.0, 1000.0, "(expected) near NaN"
    EXPECT_FAIL_END "near NaN fail path"
    EXPECT_FAIL_BEGIN
    lea  rbx, [rel blob_a]
    lea  rsi, [rel blob_b]
    CHECK_MEM rbx, rsi, 8, "(expected) mem mismatch at byte 5"
    EXPECT_FAIL_END "mem fail path"
    EXPECT_FAIL_BEGIN
    lea  rbx, [rel bmp_name]
    CHECK_STR rbx, "selftest.bm", "(expected) str mismatch"
    EXPECT_FAIL_END "str fail path"
    EXPECT_FAIL_BEGIN
    CHECK_STR 0, "x", "(expected) str null"
    EXPECT_FAIL_END "str null fail path"
    EXPECT_FAIL_BEGIN
    mov  rax, __?float64?__(1.0)
    movq xmm0, rax
    mov  rax, __?float64?__(1.1)
    movq xmm1, rax
    mov  rax, __?float64?__(0.01)
    movq xmm2, rax
    lea  r9, [rel bmp_name]
    lea  rax, [rel bmp_name]
    mov  [rsp+32], rax
    mov  qword [rsp+40], __?LINE?__
    call t_check_near_d
    EXPECT_FAIL_END "near_d fail path"
    EXPECT_FAIL_BEGIN
    CHECK_TRUE 0, "(expected) check_true(0)"
    mov  eax, 0
    EXPECT_FAIL_END "check_true fail path"
    ; direct t_fail + detail
    mov  r12d, [rel t_failures]
    PRINT "(next FAIL line is expected)"
    call t_newline
    lea  rcx, [rel bmp_name]
    lea  rdx, [rel bmp_name]
    mov  r8d, 42
    call t_fail
    lea  rcx, [rel bmp_name]
    call t_fail_detail
    mov  r14d, [rel t_failures]
    mov  [rel t_failures], r12d
    sub  r14d, r12d
    CHECK_EQ32 r14d, 1, "t_fail counts"


    TEST "rng"
    mov  ecx, 1
    call t_rng_seed
    call t_rng_next
    mov  rbx, 0x47e4ce4b896cdd1d
    CHECK_EQ rax, rbx, "xorshift64* #1"
    call t_rng_next
    mov  rbx, 0xabcfa6a8e079651d
    CHECK_EQ rax, rbx, "xorshift64* #2"
    call t_rng_next
    mov  rbx, 0xb9d10d8feb731f57
    CHECK_EQ rax, rbx, "xorshift64* #3"
    xor  ebx, ebx
    mov  esi, 10000
.rf:
    call t_rng_float
    xorps xmm1, xmm1
    comiss xmm0, xmm1
    jb   .rbad
    mov  eax, 0x3F800000
    movd xmm1, eax
    comiss xmm0, xmm1
    jb   .rok
.rbad:
    inc  ebx
.rok:
    dec  esi
    jnz  .rf
    CHECK_EQ32 ebx, 0, "rng_float in [0,1)"


    TEST "alloc"
    mov  ecx, 100000
    call t_alloc
    mov  rbx, rax
    CHECK_TRUE ebx, "t_alloc non-null"
    mov  eax, [rbx+99996]
    or   eax, [rbx]
    CHECK_EQ32 eax, 0, "t_alloc zeroed"
    mov  dword [rbx+50000], 0x11223344
    CHECK_EQ32 [rbx+50000], 0x11223344, "t_alloc writable"


    TEST "time"
    call t_time_ms
    mov  rbx, rax
    mov  ecx, 30
    call Sleep
    call t_time_ms
    sub  rax, rbx
    mov  rsi, rax
    cmp  rsi, 20
    setae al
    cmp  rsi, 2000
    setb cl
    and  al, cl
    movzx eax, al
    CHECK_TRUE eax, "Sleep(30) measured within [20,2000) ms"


    TEST "bmp"
    lea  rcx, [rel bmp_name]
    lea  rdx, [rel bmp_px]
    mov  r8d, 3
    mov  r9d, 2
    call t_write_bmp
    CHECK_EQ32 eax, 1, "t_write_bmp ok"
    lea  rcx, [rel bmp_name]
    mov  edx, 0x80000000                ; GENERIC_READ
    mov  r8d, 1
    xor  r9d, r9d
    mov  qword [rsp+32], 3              ; OPEN_EXISTING
    mov  qword [rsp+40], 0x80
    mov  qword [rsp+48], 0
    call CreateFileA
    mov  rbx, rax
    mov  rcx, rax
    lea  rdx, LOC(0)
    mov  r8d, 200
    lea  r9, LOC(256)
    mov  qword LOC(256), 0
    mov  qword [rsp+32], 0
    call ReadFile
    mov  rcx, rbx
    call CloseHandle
    CHECK_EQ32 LOC(256), 78, "bmp file size"
    lea  rbx, LOC(0)
    lea  rsi, [rel bmp_gold]
    CHECK_MEM rbx, rsi, 78, "bmp bytes == golden"
    lea  rcx, [rel bmp_name]
    call DeleteFileA
    xor  ecx, ecx
    lea  rdx, [rel bmp_px]
    mov  r8d, 0
    mov  r9d, 2
    call t_write_bmp
    CHECK_EQ32 eax, 0, "t_write_bmp rejects w=0"


    TEST "abi checker"
    lea  rcx, [rel abi_good]
    lea  rdx, [rel abi_args]
    call t_abi_call
    mov  ebx, ecx
    CHECK_EQ rax, 310, "args + stack args passed"
    CHECK_EQ32 ebx, 0, "clean function -> mask 0"
    lea  rcx, [rel abi_xmm]
    lea  rdx, [rel abi_args]
    call t_abi_call
    mov  ebx, ecx
    movq rsi, xmm0
    CHECK_EQ rax, 2, "xmm1 = a2 bits"
    CHECK_EQ rsi, 1, "xmm0 returned = a1 bits"
    CHECK_EQ32 ebx, 0, "leaf -> mask 0"
    lea  rcx, [rel abi_bad]
    lea  rdx, [rel abi_args]
    call t_abi_call
    mov  ebx, ecx
    CHECK_EQ32 ebx, 0x201, "rbx+xmm7 clobber detected"
    lea  rcx, [rel abi_badmany]
    lea  rdx, [rel abi_args]
    call t_abi_call
    mov  ebx, ecx
    CHECK_EQ32 ebx, 0x20088, "r15+rdi+xmm15 clobber detected"
    lea  rcx, [rel abi_rsp]
    lea  rdx, [rel abi_args]
    call t_abi_call
    mov  ebx, ecx
    CHECK_EQ32 ebx, 0x80000000, "rsp change detected"
    lea  rcx, [rel abi_align]
    lea  rdx, [rel abi_args]
    call t_abi_call
    CHECK_EQ rax, 0, "callee sees aligned stack"
    mov  ecx, 0x80000201
    lea  rdx, LOC(0)
    call t_abi_mask_name
    lea  rbx, LOC(0)
    CHECK_STR rbx, "rbx xmm7 rsp", "mask name"
    mov  ecx, 0x3FFFF
    lea  rdx, LOC(0)
    call t_abi_mask_name
    lea  rbx, LOC(0)
    CHECK_STR rbx, "rbx rbp rsi rdi r12 r13 r14 r15 xmm6 xmm7 xmm8 xmm9 xmm10 xmm11 xmm12 xmm13 xmm14 xmm15", "mask name all"
    xor  ecx, ecx
    lea  rdx, LOC(0)
    call t_abi_mask_name
    lea  rbx, LOC(0)
    CHECK_STR rbx, "", "mask name empty"
ENDP
