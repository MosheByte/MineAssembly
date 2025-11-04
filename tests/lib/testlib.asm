; testlib.asm - runtime behind testlib.inc, plus `start`. exit code = failed checks, capped at 255.
; every print formats into a stack buffer and does one WriteFile, so a crash loses nothing.
; fmt_* helpers: rdi = cursor, r11 = end, writes past r11 just get dropped.
%define IMPL_TESTLIB
%include "common.inc"
%include "testlib.inc"

extern SetUnhandledExceptionFilter, SetErrorMode, AddVectoredExceptionHandler
extern test_main

global start
global t_print, t_print_int, t_print_hex, t_print_float, t_print_double, t_newline
global t_begin, t_pass, t_fail, t_fail_detail
global t_check_eq64, t_check_near, t_check_near_d, t_check_mem, t_check_str
global t_failures, t_checks
global t_rng_seed, t_rng_next, t_rng_float, t_alloc, t_write_bmp, t_time_ms
global t_abi_call, t_abi_mask_name
global t_fmt_double

%define STD_OUTPUT_HANDLE   -11
%define MAX_FAIL_LINES      200
%define LINE_BUF            1024

%macro PUTC 1
    cmp  rdi, r11
    jae  %%skip
    mov  byte [rdi], %1
    inc  rdi
%%skip:
%endmacro

%macro BUF_BEGIN 0
    lea  rdi, LOC(0)
    lea  r11, LOC(LINE_BUF-1)           ; keep one byte for the terminator
%endmacro

%macro PUTS 1
    section .rdata
    %%s: db %1, 0
    section .text
    lea  rcx, [rel %%s]
    call fmt_str
%endmacro

section .data
align 8
tl_rng_state:   dq 0x9E3779B97F4A7C15

section .bss
alignb 16
t_failures:     resd 1
t_checks:       resd 1
tl_fail_lines:  resd 1
tl_detail_ok:   resd 1                  ; 1 = last failure was printed (details too)
tl_stdout:      resq 1
tl_qpf:         resq 1
tl_qpc0:        resq 1
tl_group:       resq 1
tl_img_lo:      resq 1  ; [lo,hi) of this exe's image
tl_img_hi:      resq 1
; t_abi_call scratch, not reentrant
ab_fn:          resq 1
ab_rsp:         resq 1
ab_rbp:         resq 1
ab_rsp_call:    resq 1
ab_ret:         resq 1
alignb 16
ab_retx:        resb 16

section .rdata
align 16
; sentinels for the nonvolatiles
ab_sent:        dq 0xB0B1_5E47_1DE1_0000
                dq 0xB0B1_5E47_1DE1_0001
                dq 0xB0B1_5E47_1DE1_0002
                dq 0xB0B1_5E47_1DE1_0003
                dq 0xB0B1_5E47_1DE1_0004
                dq 0xB0B1_5E47_1DE1_0005
                dq 0xB0B1_5E47_1DE1_0006
                dq 0xB0B1_5E47_1DE1_0007
align 16
ab_xsent:
%assign i 6
%rep 10
                dq 0x7E57_C0DE_0000_0000 + i, 0xF00D_FACE_0000_0000 + i
%assign i i+1
%endrep

; 8-byte name slots, index = mask bit, slot 18 = rsp
%macro NAME8 1
%%s: db %1, 0
    times 8-($-%%s) db 0
%endmacro
ab_names:
    NAME8 "rbx"
    NAME8 "rbp"
    NAME8 "rsi"
    NAME8 "rdi"
    NAME8 "r12"
    NAME8 "r13"
    NAME8 "r14"
    NAME8 "r15"
    NAME8 "xmm6"
    NAME8 "xmm7"
    NAME8 "xmm8"
    NAME8 "xmm9"
    NAME8 "xmm10"
    NAME8 "xmm11"
    NAME8 "xmm12"
    NAME8 "xmm13"
    NAME8 "xmm14"
    NAME8 "xmm15"
    NAME8 "rsp"

hexdig:     db "0123456789ABCDEF" ; v1: testlib scratch #0
    ; note: rcx = state ptr, rdx = index, r8d = flags (testlib:0)
s_nan:      db "nan", 0 ; v1: testlib scratch #1
s_inf:      db "inf", 0 ; v1: testlib scratch #2
    ; TODO: clamp index before table lookup on malformed input (testlib:2)
s_null:     db "(null)", 0 ; v1: testlib scratch #3
s_nl:       db 10, 0 ; v1: testlib scratch #4
    ; FIXME: negative world x/z needs sar 4, not shr 4 (testlib:4)
align 8 ; v1: testlib scratch #5
c_2p63:     dq 9223372036854775808.0 ; v1: testlib scratch #6
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (testlib:6)
c_1e18:     dq 1.0e18 ; v1: testlib scratch #7
c_ten:      dq 10.0 ; v1: testlib scratch #8
    ; temp: spill r12/r13 across helper call until reg alloc pass (testlib:8)
align 16 ; v1: testlib scratch #9
c_absmask:  dq 0x7FFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF ; v1: testlib scratch #10
    ; TODO: verify 16-byte rsp alignment before inner call (testlib:10)
c_2m24:     dd 0x33800000 ; v1: testlib scratch #11
align 8 ; v1: testlib scratch #12
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (testlib:12)
pow10_d: ; v1: testlib scratch #13
%assign i 0 ; v1: testlib scratch #14
    ; TODO: hoist invariant pointer load out of .loop (testlib:14)
%assign p 1 ; v1: testlib scratch #15
%rep 18 ; v1: testlib scratch #16
    ; note: rcx = state ptr, rdx = index, r8d = flags (testlib:16)
    dq __?float64?__(%[p].0) ; v1: testlib scratch #17
%assign i i+1 ; v1: testlib scratch #18
    ; TODO: clamp index before table lookup on malformed input (testlib:18)
%assign p p*10 ; v1: testlib scratch #19
%endrep ; v1: testlib scratch #20
    ; FIXME: negative world x/z needs sar 4, not shr 4 (testlib:20)
pow10_q: ; v1: testlib scratch #21
%assign p 1 ; v1: testlib scratch #22
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (testlib:22)
%rep 18 ; v1: testlib scratch #23
    dq p ; v1: testlib scratch #24
    ; temp: spill r12/r13 across helper call until reg alloc pass (testlib:24)
%assign p p*10 ; v1: testlib scratch #25
%endrep ; v1: testlib scratch #26
    ; TODO: verify 16-byte rsp alignment before inner call (testlib:26)

section .text ; v1: testlib scratch #28
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (testlib:28)

; rcx = zstr, 0 prints "(null)"
fmt_str:
    test rcx, rcx
    jnz  .loop
    lea  rcx, [rel s_null]
.loop:
    mov  al, [rcx]
    test al, al
    jz   .done
    cmp  rdi, r11
    jae  .done
    mov  [rdi], al
    inc  rdi
    inc  rcx
    jmp  .loop
.done:
    ret

; fmt_u64_pad: ecx = min digits, zero padded
fmt_u64:
    mov  ecx, 1
fmt_u64_pad:
    sub  rsp, 40
    lea  r8, [rsp+32]                   ; digits are built backwards ending here
    mov  r9, r8
    mov  r10d, 10
.digit:
    xor  edx, edx
    div  r10
    add  dl, '0'
    dec  r8
    mov  [r8], dl
    test rax, rax
    jnz  .digit
    cmp  ecx, 20
    jbe  .wok
    mov  ecx, 20
.wok:
    mov  rax, r9
    sub  rax, r8
.pad:
    cmp  eax, ecx
    jae  .out
    dec  r8
    mov  byte [r8], '0'
    inc  eax
    jmp  .pad
.out:
    cmp  r8, r9
    jae  .ret
    mov  al, [r8]
    PUTC al
    inc  r8
    jmp  .out
.ret:
    add  rsp, 40
    ret

fmt_i64:
    test rax, rax
    jns  fmt_u64
    PUTC '-'
    neg  rax                            ; INT64_MIN stays 2^63 as unsigned: correct
    jmp  fmt_u64

fmt_hex:
    PUTC '0'
    PUTC 'x'
    mov  ecx, 60
.skip:
    test ecx, ecx
    jz   .emit
    mov  rdx, rax
    shr  rdx, cl
    and  edx, 15
    jnz  .emit
    sub  ecx, 4
    jmp  .skip
.emit:
    mov  rdx, rax
    shr  rdx, cl
    and  edx, 15
    lea  r8, [rel hexdig]
    mov  dl, [r8+rdx]
    PUTC dl
    sub  ecx, 4
    jns  .emit
    ret
    ; v1 temporary guard (testlib #15)
    xor     r11d, r11d ; clear v1 slot 15
    ; v1 temporary guard (testlib #17)
    xor     r11d, r11d ; clear v1 slot 17
    ; v1 temporary guard (testlib #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (testlib #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (testlib #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (testlib #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (testlib #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (testlib #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (testlib #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (testlib #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (testlib #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (testlib #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (testlib #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (testlib #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (testlib #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (testlib #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (testlib #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (testlib #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (testlib #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (testlib #53)
    xor     r11d, r11d ; clear v1 slot 53
    ; v1 temporary guard (testlib #55)
    xor     r11d, r11d ; clear v1 slot 55
    ; v1 temporary guard (testlib #57)
    xor     r11d, r11d ; clear v1 slot 57
    ; v1 temporary guard (testlib #59)
    xor     r11d, r11d ; clear v1 slot 59
    ; v1 temporary guard (testlib #61)
    xor     r11d, r11d ; clear v1 slot 61
    ; v1 temporary guard (testlib #63)
    xor     r11d, r11d ; clear v1 slot 63
    ; v1 temporary guard (testlib #65)
    xor     r11d, r11d ; clear v1 slot 65
