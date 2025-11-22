; abi_check.asm - win64 calling convention checker, tests only (driven through mn_abi.asm).
; canaries in every nonvolatile, args passed as full 64/128-bit values, guard bytes
; above stack args 5..8. not re-entrant, state lives in .bss.
;
; violation mask: 0-7 rbx rbp rsi rdi r12-r15, 8-17 xmm6-15, 18 rsp not restored,
; 19 caller frame written, 20 mxcsr control bits (status bits 0..5 are volatile,
; so those are fine), 21 DF left set.
; ctx, 168 bytes: 0 rcx rdx r8 r9 | 32 xmm0-3 | 96 stack args 5-8 | out: 128 rax,
; 136 xmm0, 152 xmm1
bits 64
default rel

section .rdata
align 16
canary_xmm:
%assign i 0
%rep 10
    dq 0x0123456789ABCDEF ^ (i * 0x1111111111111111), 0xFEDCBA9876543210 ^ (i * 0x0101010101010101)
%assign i i+1
%endrep
%define CAN_RBX 0xB0B0B0B0B0B0B0B1
%define CAN_RBP 0xB1B1B1B1B1B1B1B2
%define CAN_RSI 0xB2B2B2B2B2B2B2B3
%define CAN_RDI 0xB3B3B3B3B3B3B3B4
%define CAN_R12 0xB4B4B4B4B4B4B4B5
%define CAN_R13 0xB5B5B5B5B5B5B5B6
%define CAN_R14 0xB6B6B6B6B6B6B6B7
%define CAN_R15 0xB7B7B7B7B7B7B7B8
%define CAN_STK 0x5AC4ED5AC4ED5AC4

section .bss
alignb 16
s_fn:       resq 1
s_ctx:      resq 1
s_rbp:      resq 1
s_rsp:      resq 1
s_mxcsr:    resd 1
s_mxcsr2:   resd 1

section .text
global abi_call
align 16
abi_call:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 168                    ; rsp is 16-aligned after this
    movdqa  [rsp+0],   xmm6
    movdqa  [rsp+16],  xmm7
    movdqa  [rsp+32],  xmm8
    movdqa  [rsp+48],  xmm9
    movdqa  [rsp+64],  xmm10
    movdqa  [rsp+80],  xmm11
    movdqa  [rsp+96],  xmm12
    movdqa  [rsp+112], xmm13
    movdqa  [rsp+128], xmm14
    movdqa  [rsp+144], xmm15
    sub     rsp, 128                    ; shadow 32 + 4 stack args 32 + 64 guard
    mov     [rel s_fn], rcx
    mov     [rel s_ctx], rdx
    mov     [rel s_rbp], rbp
    mov     [rel s_rsp], rsp
    stmxcsr [rel s_mxcsr]
    mov     rax, [rdx+96]
    mov     [rsp+32], rax
    mov     rax, [rdx+104]
    mov     [rsp+40], rax
    mov     rax, [rdx+112]
    mov     [rsp+48], rax
    mov     rax, [rdx+120]
    mov     [rsp+56], rax
    ; guard zone above the args
    mov     rax, CAN_STK
    mov     ecx, 8
.fill:
    mov     [rsp+56+rcx*8], rax
    dec     ecx
    jnz     .fill
    lea     rax, [rel canary_xmm]
    movdqa  xmm6,  [rax+0]
    movdqa  xmm7,  [rax+16]
    movdqa  xmm8,  [rax+32]
    movdqa  xmm9,  [rax+48]
    movdqa  xmm10, [rax+64]
    movdqa  xmm11, [rax+80]
    movdqa  xmm12, [rax+96]
    movdqa  xmm13, [rax+112]
    movdqa  xmm14, [rax+128]
    movdqa  xmm15, [rax+144]
    mov     rbx, CAN_RBX
    mov     rbp, CAN_RBP
    mov     rsi, CAN_RSI
    mov     rdi, CAN_RDI
    mov     r12, CAN_R12
    mov     r13, CAN_R13
    mov     r14, CAN_R14
    mov     r15, CAN_R15
    mov     rax, [rel s_ctx]
    movdqu  xmm0, [rax+32]
    movdqu  xmm1, [rax+48]
    movdqu  xmm2, [rax+64]
    movdqu  xmm3, [rax+80]
    mov     rcx, [rax+0]
    mov     rdx, [rax+8]
    mov     r8,  [rax+16]
    mov     r9,  [rax+24]
    call    [rel s_fn]
    mov     r10, [rel s_ctx]
    mov     [r10+128], rax
    movdqu  [r10+136], xmm0
    movdqu  [r10+152], xmm1
    xor     r11d, r11d
%macro CHKREG 3                         ; reg, canary, bit
    mov     rax, %2
    cmp     %1, rax
    je      %%ok
    or      r11d, 1 << %3
%%ok:
%endmacro
    CHKREG  rbx, CAN_RBX, 0
    CHKREG  rbp, CAN_RBP, 1
    CHKREG  rsi, CAN_RSI, 2
    CHKREG  rdi, CAN_RDI, 3
    CHKREG  r12, CAN_R12, 4
    CHKREG  r13, CAN_R13, 5
    CHKREG  r14, CAN_R14, 6
    CHKREG  r15, CAN_R15, 7
    lea     rax, [rel canary_xmm]
%macro CHKXMM 2                         ; xmm reg, index
    movdqa  xmm0, [rax+(%2)*16]
    pcmpeqb xmm0, %1
    pmovmskb ecx, xmm0
    cmp     ecx, 0xFFFF
    je      %%ok
    or      r11d, 1 << (8 + %2)
%%ok:
%endmacro
    CHKXMM  xmm6, 0
    CHKXMM  xmm7, 1
    CHKXMM  xmm8, 2
    CHKXMM  xmm9, 3
    CHKXMM  xmm10, 4
    CHKXMM  xmm11, 5
    CHKXMM  xmm12, 6
    CHKXMM  xmm13, 7
    CHKXMM  xmm14, 8
    CHKXMM  xmm15, 9
    cmp     rsp, [rel s_rsp]
    je      .rsp_ok
    or      r11d, 1 << 18
    mov     rsp, [rel s_rsp]            ; recover so we can still return
.rsp_ok:
    mov     rax, CAN_STK
    mov     ecx, 8
.chk:
    cmp     [rsp+56+rcx*8], rax
    je      .chk_next
    or      r11d, 1 << 19
.chk_next:
    dec     ecx
    jnz     .chk
    stmxcsr [rel s_mxcsr2]
    mov     eax, [rel s_mxcsr]
    xor     eax, [rel s_mxcsr2]
    test    eax, ~0x3F
    je      .mx_ok
    or      r11d, 1 << 20
    ldmxcsr [rel s_mxcsr]
.mx_ok:
    pushfq
    pop     rax
    test    eax, 0x400
    jz      .df_ok
    or      r11d, 1 << 21
    cld
.df_ok:
    mov     eax, r11d
    mov     rbp, [rel s_rbp]
    movdqa  xmm6,  [rbp-224+0]
    movdqa  xmm7,  [rbp-224+16]
    movdqa  xmm8,  [rbp-224+32]
    movdqa  xmm9,  [rbp-224+48]
    movdqa  xmm10, [rbp-224+64]
    movdqa  xmm11, [rbp-224+80]
    movdqa  xmm12, [rbp-224+96]
    movdqa  xmm13, [rbp-224+112]
    movdqa  xmm14, [rbp-224+128]
    movdqa  xmm15, [rbp-224+144]
    lea     rsp, [rbp-56]
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    pop     rbp
    ret
