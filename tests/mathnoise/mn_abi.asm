; mn_abi.asm - fills the context for abi_check.asm like a hostile but legal caller:
; garbage in int32 upper halves, spare xmm lanes and the unused reg of each position,
; NaN in every xmm slot that isn't a float arg. violations count into mn_abi_viol.
%define IMPL_MN_ABI
%include "common.inc"
%include "../mathnoise/mn_test.inc"

extern abi_call
global mn_ctx, mn_abi_viol

%define GARB32      0xDEADBEEF
%define BAD_INT     0xBADC0FFEE0DDF00D

section .rdata
align 16
xmm_garbage:    dd 0x7FC00000, 0x7FC00000, -3.0e7, 123.0   ; unused float slot
str_viol:       db "      ABI violation, mask bits (0-7 rbx..r15, 8-17 xmm6-15, 18 rsp, 19 frame, 20 mxcsr, 21 DF): ", 0
str_fn:         db "  fn at ", 0

section .bss
alignb 16
mn_ctx:         resb 176
mn_abi_viol:    resd 1

section .text

LEAF mn_ctx_reset
    lea     rcx, [rel mn_ctx]
    xor     eax, eax
    mov     [rcx], rax
    mov     [rcx+8], rax
    mov     [rcx+16], rax
    mov     [rcx+24], rax
    movdqa  xmm0, [rel xmm_garbage]
    movdqu  [rcx+32], xmm0
    movdqu  [rcx+48], xmm0
    movdqu  [rcx+64], xmm0
    movdqu  [rcx+80], xmm0
    mov     [rcx+96], rax
    mov     [rcx+104], rax
    mov     [rcx+112], rax
    mov     [rcx+120], rax
    ret

; pos < 4 -> ctx+pos*8, else ctx+96+(pos-4)*8
%macro INT_SLOT 0.nolist  ; ecx pos -> rax
    lea     rax, [rel mn_ctx]
    cmp     ecx, 4
    jb      %%reg
    add     rax, 96-32
%%reg:
    lea     rax, [rax+rcx*8]
%endmacro

LEAF mn_ctx_i32
    INT_SLOT
    mov     r8d, GARB32
    shl     r8, 32
    mov     edx, edx
    or      rdx, r8
    mov     [rax], rdx
    ret

LEAF mn_ctx_q
    INT_SLOT
    mov     [rax], rdx
    ret

LEAF mn_ctx_f
    cmp     ecx, 4
    jae     .stack
    lea     rax, [rel mn_ctx]
    mov     rdx, BAD_INT
    mov     [rax+rcx*8], rdx
    shl     ecx, 4
    movdqa  xmm0, [rel xmm_garbage]
    movss   xmm0, xmm1                  ; value in lane 0, garbage in 1..3
    movdqu  [rax+rcx+32], xmm0
    ret
.stack:
    INT_SLOT
    movd    edx, xmm1
    mov     r8d, GARB32
    shl     r8, 32
    or      rdx, r8
    mov     [rax], rdx
    ret

PROC mn_acall
    mov     rbx, rcx
    lea     rdx, [rel mn_ctx]
    call    abi_call
    mov     esi, eax
    test    eax, eax
    jz      .ok
    inc     dword [rel mn_abi_viol]
    lea     rcx, [rel str_viol]
    call    t_print
    mov     ecx, esi
    call    t_print_hex
    lea     rcx, [rel str_fn]
    call    t_print
    mov     rcx, rbx
    call    t_print_hex
    call    t_newline
.ok:
    lea     rcx, [rel mn_ctx]
    mov     rdx, [rcx+128]
    movss   xmm0, [rcx+136]
    movss   xmm1, [rcx+152]
    mov     eax, esi
ENDP
