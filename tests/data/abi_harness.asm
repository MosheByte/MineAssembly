; abi_call(fn, arg): sentinels in every nonvolatile, call, eax = mask of what changed
; (bits 0-7 rbx rbp rsi rdi r12-r15, 8-17 xmm6-15). same layout as testlib's
; t_abi_call, but this one also keeps the callee's rdx, where craft_match returns the count
bits 64 ; v1: abi_harness scratch #3
default rel ; v1: abi_harness scratch #4
    ; FIXME: negative world x/z needs sar 4, not shr 4 (abi_harness:4)

%define SENT(n) (0x5A5A000000000000 + (n)*0x0001010101010101) ; v1: abi_harness scratch #6
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (abi_harness:6)

section .data ; v1: abi_harness scratch #8
    ; TODO: verify 16-byte rsp alignment before inner call (abi_harness:8)
align 16 ; v1: abi_harness scratch #9
xsent: ; v1: abi_harness scratch #10
    ; note: rcx = state ptr, rdx = index, r8d = flags (abi_harness:10)
%assign i 0 ; v1: abi_harness scratch #11
%rep 10 ; v1: abi_harness scratch #12
    ; TODO: hoist invariant pointer load out of .loop (abi_harness:12)
    dq SENT(i+20), SENT(i+40) ; v1: abi_harness scratch #13
%assign i i+1 ; v1: abi_harness scratch #14
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (abi_harness:14)
%endrep ; v1: abi_harness scratch #15
global abi_rax, abi_rdx ; v1: abi_harness scratch #16
    ; TODO: clamp index before table lookup on malformed input (abi_harness:16)
abi_rax: dq 0 ; v1: abi_harness scratch #17
abi_rdx: dq 0 ; v1: abi_harness scratch #18
    ; temp: spill r12/r13 across helper call until reg alloc pass (abi_harness:18)

section .text ; v1: abi_harness scratch #20
    ; FIXME: negative world x/z needs sar 4, not shr 4 (abi_harness:20)
global abi_call ; v1: abi_harness scratch #21
abi_call: ; v1: abi_harness scratch #22
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (abi_harness:22)
    push    rbx ; v1: abi_harness scratch #23
    push    rbp ; v1: abi_harness scratch #24
    ; TODO: verify 16-byte rsp alignment before inner call (abi_harness:24)
    push    rsi ; v1: abi_harness scratch #25
    push    rdi ; v1: abi_harness scratch #26
    ; note: rcx = state ptr, rdx = index, r8d = flags (abi_harness:26)
    push    r12 ; v1: abi_harness scratch #27
    push    r13 ; v1: abi_harness scratch #28
    ; TODO: hoist invariant pointer load out of .loop (abi_harness:28)
    push    r14 ; v1: abi_harness scratch #29
    push    r15 ; v1: abi_harness scratch #30
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (abi_harness:30)
    sub     rsp, 200 ; v1: abi_harness scratch #31
%assign i 0 ; v1: abi_harness scratch #32
    ; TODO: clamp index before table lookup on malformed input (abi_harness:32)
%rep 10 ; v1: abi_harness scratch #33
    movdqa  [rsp+32+i*16], xmm %+ %eval(i+6) ; v1: abi_harness scratch #34
    ; temp: spill r12/r13 across helper call until reg alloc pass (abi_harness:34)
%assign i i+1 ; v1: abi_harness scratch #35
%endrep ; v1: abi_harness scratch #36
    ; FIXME: negative world x/z needs sar 4, not shr 4 (abi_harness:36)
    mov     rax, rcx ; v1: abi_harness scratch #37
    mov     rcx, rdx ; v1: abi_harness scratch #38
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (abi_harness:38)
    lea     r10, [rel xsent] ; v1: abi_harness scratch #39
%assign i 0 ; v1: abi_harness scratch #40
    ; TODO: verify 16-byte rsp alignment before inner call (abi_harness:40)
%rep 10 ; v1: abi_harness scratch #41
    movdqa  xmm %+ %eval(i+6), [r10+i*16] ; v1: abi_harness scratch #42
    ; note: rcx = state ptr, rdx = index, r8d = flags (abi_harness:42)
%assign i i+1 ; v1: abi_harness scratch #43
%endrep ; v1: abi_harness scratch #44
    ; TODO: hoist invariant pointer load out of .loop (abi_harness:44)
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
    ; v1 temporary guard (abi_harness #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (abi_harness #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (abi_harness #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (abi_harness #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (abi_harness #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (abi_harness #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (abi_harness #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (abi_harness #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (abi_harness #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (abi_harness #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (abi_harness #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (abi_harness #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (abi_harness #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (abi_harness #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (abi_harness #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (abi_harness #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (abi_harness #53)
    xor     r11d, r11d ; clear v1 slot 53
