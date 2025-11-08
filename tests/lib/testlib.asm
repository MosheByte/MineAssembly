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

hexdig:     db "0123456789ABCDEF"
s_nan:      db "nan", 0
s_inf:      db "inf", 0
s_null:     db "(null)", 0
s_nl:       db 10, 0
align 8
c_2p63:     dq 9223372036854775808.0
c_1e18:     dq 1.0e18
c_ten:      dq 10.0
align 16
c_absmask:  dq 0x7FFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF   ; andpd operand: must be 16-aligned
c_2m24:     dd 0x33800000  ; 2^-24
align 8
pow10_d:
%assign i 0
%assign p 1
%rep 18
    dq __?float64?__(%[p].0)
%assign i i+1
%assign p p*10
%endrep
pow10_q:
%assign p 1
%rep 18
    dq p
%assign p p*10
%endrep

section .text

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

; fmt_double: xmm0, edx decimals (0..17). rounds half to even like printf.
; values >= 2^63 get their ~17 real digits and then zeros.
fmt_double:
    movq r10, xmm0
    test r10, r10
    jns  .pos
    PUTC '-'
.pos:
    btr  r10, 63
    mov  rax, 0x7FF0000000000000
    mov  rcx, r10
    and  rcx, rax
    cmp  rcx, rax
    jne  .finite
    mov  rcx, r10
    shl  rcx, 12                        ; mantissa != 0 -> NaN
    lea  rcx, [rel s_inf]
    jz   .special
    lea  rcx, [rel s_nan]
.special:
    jmp  fmt_str
.finite:
    movq xmm0, r10
    mov  r9d, edx
    test r9d, r9d
    jns  .dpos
    xor  r9d, r9d
.dpos:
    cmp  r9d, 17
    jbe  .dok
    mov  r9d, 17
.dok:
    ucomisd xmm0, [rel c_2p63]
    jae  .large
    test r9d, r9d
    jnz  .frac
    cvtsd2si rax, xmm0                  ; MXCSR nearest-even (2^63 edge -> 0x8000.. = 2^63, right)
    jmp  fmt_u64
.frac:
    ; exact digits: F = frac * 2^128 as 128-bit fixed point, then F*10 per digit,
    ; the leftover decides rounding.
    push rbx
    push rsi
    sub  rsp, 32
    cvttsd2si r8, xmm0
    cvtsi2sd xmm1, r8
    subsd xmm0, xmm1                    ; f in [0,1), exact
    movq rax, xmm0
    xor  ebx, ebx                       ; F hi
    xor  esi, esi                       ; F lo
    test rax, rax
    jz   .fx_done
    mov  rcx, rax
    shr  rcx, 52
    mov  r10, 0x000FFFFFFFFFFFFF
    and  rax, r10
    test ecx, ecx
    jz   .denorm
    bts  rax, 52
    jmp  .shift
.denorm:
    mov  ecx, 1
.shift:
    sub  ecx, 947                       ; f = m*2^(e-1075) -> F = m << (e-947)
    js   .shr
    mov  rsi, rax
    cmp  ecx, 64
    jb   .shl
    mov  rbx, rsi
    xor  esi, esi
    sub  ecx, 64
    shl  rbx, cl
    jmp  .fx_done
.shl:
    shld rbx, rsi, cl
    shl  rsi, cl
    jmp  .fx_done
.shr:
    neg  ecx
    cmp  ecx, 63
    ja   .fx_done                       ; below 2^-128: F = 0
    shr  rax, cl
    mov  rsi, rax
.fx_done:
    mov  r10d, 10
    xor  ecx, ecx
.dg:
    cmp  ecx, r9d
    jae  .dg_done
    mov  rax, rsi
    mul  r10
    mov  rsi, rax
    mov  rax, rbx
    mov  rbx, rdx
    mul  r10
    add  rax, rbx
    adc  rdx, 0
    mov  rbx, rax
    add  dl, '0'
    mov  [rsp+rcx], dl
    inc  ecx
    jmp  .dg
.dg_done:
    mov  rax, 0x8000000000000000        ; remainder vs one half
    cmp  rbx, rax
    ja   .up
    jb   .noup
    test rsi, rsi
    jnz  .up
    test byte [rsp+r9-1], 1             ; exact tie: round to even ('0'=0x30 even)
    jz   .noup
.up:
    lea  rcx, [r9-1]
.inc:
    cmp  byte [rsp+rcx], '9'
    jne  .incd
    mov  byte [rsp+rcx], '0'
    dec  rcx
    jns  .inc
    inc  r8
    jmp  .noup
.incd:
    inc  byte [rsp+rcx]
.noup:
    mov  rsi, r9
    mov  rax, r8
    call fmt_u64
    PUTC '.'
    xor  ebx, ebx
.em:
    cmp  rbx, rsi
    jae  .emd
    mov  al, [rsp+rbx]
    PUTC al
    inc  rbx
    jmp  .em
.emd:
    add  rsp, 32
    pop  rsi
    pop  rbx
    ret
.large:
    xor  r8d, r8d
.lg:
    ucomisd xmm0, [rel c_1e18]
    jb   .lgdone
    divsd xmm0, [rel c_ten]
    inc  r8d
    jmp  .lg
.lgdone:
    cvtsd2si rax, xmm0
    push r8
    push r9
    call fmt_u64
    pop  r9
    pop  r8
.zeros:
    test r8d, r8d
    jz   .zdone
    PUTC '0'
    dec  r8d
    jmp  .zeros
.zdone:
    test r9d, r9d
    jz   .ret
    PUTC '.'
.fz:
    PUTC '0'
    dec  r9d
    jnz  .fz
.ret:
    ret

; tl_write: one WriteFile, stdout handle fetched lazily
PROC tl_write, 16
    mov  rsi, rcx
    mov  rdi, rdx
    test rdi, rdi
    jz   .done
    mov  rax, [rel tl_stdout]
    test rax, rax
    jnz  .have
    mov  ecx, STD_OUTPUT_HANDLE
    call GetStdHandle
    mov  [rel tl_stdout], rax
.have:
    test rax, rax
    jz   .done
    cmp  rax, -1
    je   .done
    mov  rcx, rax
    mov  rdx, rsi
    mov  r8d, edi
    lea  r9, LOC(0)
    mov  qword [rsp+32], 0
    call WriteFile
.done:
ENDP

; macro because the buffer is in the caller's frame
%macro BUF_WRITE 0
    lea  rcx, LOC(0)
    mov  rdx, rdi
    sub  rdx, rcx
    call tl_write
%endmacro

PROC t_print
    test rcx, rcx
    jnz  .ok
    lea  rcx, [rel s_null]
.ok:
    mov  rsi, rcx
    xor  edx, edx
.len:
    cmp  byte [rsi+rdx], 0
    je   .w
    inc  rdx
    jmp  .len
.w:
    mov  rcx, rsi
    call tl_write
ENDP

PROC t_newline
    lea  rcx, [rel s_nl]
    mov  edx, 1
    call tl_write
ENDP

PROC t_print_int, 64
    lea  rdi, LOC(0)
    lea  r11, LOC(63)
    mov  rax, rcx
    call fmt_i64
    BUF_WRITE
ENDP

PROC t_print_hex, 64
    lea  rdi, LOC(0)
    lea  r11, LOC(63)
    mov  rax, rcx
    call fmt_hex
    BUF_WRITE
ENDP

PROC t_print_float, 64
    cvtss2sd xmm0, xmm0
    lea  rdi, LOC(0)
    lea  r11, LOC(63)
    call fmt_double
    BUF_WRITE
ENDP
