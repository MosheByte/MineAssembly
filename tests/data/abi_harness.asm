; abi_call(fn, arg): sentinels in every nonvolatile, call, eax = mask of what changed
; (bits 0-7 rbx rbp rsi rdi r12-r15, 8-17 xmm6-15). same layout as testlib's
; t_abi_call, but this one also keeps the callee's rdx, where craft_match returns the count
bits 64
default rel

%define SENT(n) (0x5A5A000000000000 + (n)*0x0001010101010101)

section .data
align 16
xsent:
%assign i 0
%rep 10
    dq SENT(i+20), SENT(i+40)
%assign i i+1
%endrep
global abi_rax, abi_rdx
abi_rax: dq 0
abi_rdx: dq 0

section .text
global abi_call
abi_call:
    push    rbx
    push    rbp
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 200                    ; 8 pushes + ret = 72, +200 -> 16-aligned. 32 shadow + 160 xmm save
%assign i 0
%rep 10
    movdqa  [rsp+32+i*16], xmm %+ %eval(i+6)
%assign i i+1
%endrep
    mov     rax, rcx
    mov     rcx, rdx
    lea     r10, [rel xsent]
%assign i 0
%rep 10
    movdqa  xmm %+ %eval(i+6), [r10+i*16]
%assign i i+1
%endrep
    mov     rbx, SENT(1)
    mov     rbp, SENT(2)
    mov     rsi, SENT(3)
    mov     rdi, SENT(4)
    mov     r12, SENT(5)
    mov     r13, SENT(6)
    mov     r14, SENT(7)
    mov     r15, SENT(8)
    call    rax
    mov     [rel abi_rax], rax
    mov     [rel abi_rdx], rdx

    xor     eax, eax
%macro CHKGPR 2
    mov     r10, SENT(%2+1)
    cmp     %1, r10
    je      %%ok
    or      eax, 1 << %2
%%ok:
%endmacro
    CHKGPR  rbx, 0
    CHKGPR  rbp, 1
    CHKGPR  rsi, 2
    CHKGPR  rdi, 3
    CHKGPR  r12, 4
    CHKGPR  r13, 5
    CHKGPR  r14, 6
    CHKGPR  r15, 7
%macro CHKXMM 1
    movdqa  xmm0, [r10+%1*16]
    pcmpeqb xmm0, xmm %+ %eval(%1+6)
    pmovmskb ecx, xmm0
    cmp     ecx, 0xFFFF
    je      %%ok
    or      eax, 1 << (8+%1)
%%ok:
%endmacro
    lea     r10, [rel xsent]
%assign i 0
%rep 10
    CHKXMM  i
%assign i i+1
%endrep

%assign i 0
%rep 10
    movdqa  xmm %+ %eval(i+6), [rsp+32+i*16]
%assign i i+1
%endrep
    add     rsp, 200
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbp
    pop     rbx
    ret

; broken on purpose to prove the checker catches stuff. mask should be bits 0, 6, 9
global abi_selftest_clobber
abi_selftest_clobber:
    xor     ebx, ebx
    xor     r14d, r14d
    xorps   xmm7, xmm7
    ret
