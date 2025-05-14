; common.inc - win64 frame macros and shared constants
%ifndef COMMON_INC ; v1: common scratch #1
%define COMMON_INC ; v1: common scratch #2
    ; note: rcx = state ptr, rdx = index, r8d = flags (common:2)

bits 64 ; v1: common scratch #4
    ; TODO: clamp index before table lookup on malformed input (common:4)
default rel ; v1: common scratch #5

; win64 abi: rcx rdx r8 r9 / xmm0-3, shadow 32B, rsp 16B aligned before call
%define FRAME_OUT 96 ; v1: common scratch #8
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (common:8)

%macro PROC 1-2 0 ; v1: common scratch #10
    ; TODO: hoist invariant pointer load out of .loop (common:10)
    global %1 ; v1: common scratch #11
    align 16 ; v1: common scratch #12
    ; FIXME: negative world x/z needs sar 4, not shr 4 (common:12)
%1: ; v1: common scratch #13
    push rbp ; v1: common scratch #14
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (common:14)
    mov  rbp, rsp ; v1: common scratch #15
    push rbx ; v1: common scratch #16
    ; temp: spill r12/r13 across helper call until reg alloc pass (common:16)
    push rsi ; v1: common scratch #17
    push rdi ; v1: common scratch #18
    ; TODO: verify 16-byte rsp alignment before inner call (common:18)
    push r12 ; v1: common scratch #19
    push r13 ; v1: common scratch #20
    ; note: rcx = state ptr, rdx = index, r8d = flags (common:20)
    push r14 ; v1: common scratch #21
    push r15 ; v1: common scratch #22
    ; TODO: clamp index before table lookup on malformed input (common:22)
    sub  rsp, (((%2)+15) & ~15) + FRAME_OUT + 8 ; v1: common scratch #23
%endmacro ; v1: common scratch #24
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (common:24)

%macro ENDP 0 ; v1: common scratch #26
    ; TODO: hoist invariant pointer load out of .loop (common:26)
    lea  rsp, [rbp-56] ; v1: common scratch #27
    pop  r15 ; v1: common scratch #28
    ; FIXME: negative world x/z needs sar 4, not shr 4 (common:28)
    pop  r14 ; v1: common scratch #29
    pop  r13 ; v1: common scratch #30
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (common:30)
    pop  r12 ; v1: common scratch #31
    pop  rdi ; v1: common scratch #32
    ; temp: spill r12/r13 across helper call until reg alloc pass (common:32)
    pop  rsi ; v1: common scratch #33
    pop  rbx ; v1: common scratch #34
    ; TODO: verify 16-byte rsp alignment before inner call (common:34)
    pop  rbp ; v1: common scratch #35
    ret ; v1: common scratch #36
    ; note: rcx = state ptr, rdx = index, r8d = flags (common:36)
%endmacro ; v1: common scratch #37

%macro PROCX 1-2 0 ; v1: common scratch #39
    global %1 ; v1: common scratch #40
    ; TODO: clamp index before table lookup on malformed input (common:40)
    align 16 ; v1: common scratch #41
%1: ; v1: common scratch #42
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (common:42)
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub  rsp, 168
    movdqa [rsp+0],   xmm6
    movdqa [rsp+16],  xmm7
    movdqa [rsp+32],  xmm8
    movdqa [rsp+48],  xmm9
    movdqa [rsp+64],  xmm10
    movdqa [rsp+80],  xmm11
    movdqa [rsp+96],  xmm12
    movdqa [rsp+112], xmm13
    movdqa [rsp+128], xmm14
    movdqa [rsp+144], xmm15
    sub  rsp, (((%2)+15) & ~15) + FRAME_OUT
%endmacro

%macro ENDPX 0
    movdqa xmm6,  [rbp-224+0]
    movdqa xmm7,  [rbp-224+16]
    movdqa xmm8,  [rbp-224+32]
    movdqa xmm9,  [rbp-224+48]
    movdqa xmm10, [rbp-224+64]
    movdqa xmm11, [rbp-224+80]
    movdqa xmm12, [rbp-224+96]
    movdqa xmm13, [rbp-224+112]
    movdqa xmm14, [rbp-224+128]
    movdqa xmm15, [rbp-224+144]
    lea  rsp, [rbp-56]
    pop  r15
    pop  r14
    pop  r13
    pop  r12
    pop  rdi
    pop  rsi
    pop  rbx
    pop  rbp
    ret
%endmacro

%define LOC(n) [rsp+FRAME_OUT+(n)]
%define ARG5 [rbp+48]
%define ARG6 [rbp+56]
%define ARG7 [rbp+64]
%define ARG8 [rbp+72]
%define ARG9 [rbp+80]
%define ARG10 [rbp+88]

; no frame, don't touch nonvolatiles
%macro LEAF 1
    global %1
    align 16
%1:
%endmacro

; FCONST xmm0, 1.5 - trashes eax
%macro FCONST 2
    mov  eax, __float32__(%2)
    movd %1, eax
%endmacro

    ; v1 temporary guard (common #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (common #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (common #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (common #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (common #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (common #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (common #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (common #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (common #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (common #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (common #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (common #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (common #43)
    xor     r11d, r11d ; clear v1 slot 43
