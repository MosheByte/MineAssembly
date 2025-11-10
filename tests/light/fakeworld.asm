; fake chunk storage for the light tests: a fixed 7x7 grid of slots, cx/cz -3..3.
; world_get_chunk only hands out a slot whose CHUNK.state != 0, so lightlib decides
; which chunks exist
bits 64
default rel
%include "structs.inc"

%define FW_R    3
%define FW_DIM  (2*FW_R + 1)

section .bss
global fw_pool, fw_misaligned
alignb 64
fw_pool: resb FW_DIM*FW_DIM*CHUNK_BYTES
fw_misaligned: resd 1

section .text
; counts calls made with a misaligned stack in fw_misaligned (want rsp % 16 == 8 here)
global world_get_chunk
world_get_chunk:
    mov  rax, rsp
    and  eax, 15
    cmp  eax, 8
    je   .aligned
    inc  dword [rel fw_misaligned]
.aligned:
    add  ecx, FW_R
    add  edx, FW_R
    cmp  ecx, FW_DIM
    jae  .none
    cmp  edx, FW_DIM
    jae  .none
    imul edx, edx, FW_DIM
    add  ecx, edx
    imul rcx, rcx, CHUNK_BYTES
    lea  rax, [rel fw_pool]
    add  rax, rcx
    cmp  dword [rax + CHUNK.state], 0
    je   .none
    ret
.none:
    xor  eax, eax
    ret

; distinct junk per register
%define SENT(k) (0x5A5A000000000000 | ((k) * 0x0101010101))

; calls fn(a1..a4) with junk in every non-volatile. eax = what fn trashed, bits 0..7
; rbx rbp rsi rdi r12-r15, bits 8..17 xmm6-15
global abi_probe
abi_probe:
    push rbx
    push rbp
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15  ; rsp % 16 == 8 now
    sub  rsp, 200  ; 32 shadow + 160 xmm + 8 fn -> aligned
    movdqu [rsp+32],  xmm6
    movdqu [rsp+48],  xmm7
    movdqu [rsp+64],  xmm8
    movdqu [rsp+80],  xmm9
    movdqu [rsp+96],  xmm10
    movdqu [rsp+112], xmm11
    movdqu [rsp+128], xmm12
    movdqu [rsp+144], xmm13
    movdqu [rsp+160], xmm14
    movdqu [rsp+176], xmm15
    mov  [rsp+192], rcx
    mov  rcx, rdx  ; full 64 bits, may be a pointer
    mov  rdx, r8
    mov  r8, r9
    mov  r9, [rsp+200+64+40]  ; a4: past our frame + 8 pushes + ret + shadow
%assign k 6
%rep 10
    mov  rax, SENT(k)
    movq xmm %+ k, rax
  %assign k k+1
%endrep
    mov  rbx, SENT(20)
    mov  rbp, SENT(21)
    mov  rsi, SENT(22)
    mov  rdi, SENT(23)
    mov  r12, SENT(24)
    mov  r13, SENT(25)
    mov  r14, SENT(26)
    mov  r15, SENT(27)
    call [rsp+192]
    xor  r10d, r10d
    mov  rax, SENT(20)
    cmp  rbx, rax
    je   .b1
    or   r10d, 1
.b1:
    mov  rax, SENT(21)
    cmp  rbp, rax
    je   .b2
    or   r10d, 2
.b2:
    mov  rax, SENT(22)
    cmp  rsi, rax
    je   .b3
    or   r10d, 4
.b3:
    mov  rax, SENT(23)
    cmp  rdi, rax
    je   .b4
    or   r10d, 8
.b4:
    mov  rax, SENT(24)
    cmp  r12, rax
    je   .b5
    or   r10d, 16
.b5:
    mov  rax, SENT(25)
    cmp  r13, rax
    je   .b6
    or   r10d, 32
.b6:
    mov  rax, SENT(26)
    cmp  r14, rax
    je   .b7
    or   r10d, 64
.b7:
    mov  rax, SENT(27)
    cmp  r15, rax
    je   .b8
    or   r10d, 128
.b8:
%assign k 6
%rep 10
    movq rax, xmm %+ k
    mov  r11, SENT(k)
    cmp  rax, r11
    je   .ok_ %+ k
    or   r10d, 1 << (k + 2)
.ok_ %+ k:
  %assign k k+1
%endrep
    mov  eax, r10d
    movdqu xmm6,  [rsp+32]
    movdqu xmm7,  [rsp+48]
    movdqu xmm8,  [rsp+64]
    movdqu xmm9,  [rsp+80]
    movdqu xmm10, [rsp+96]
    movdqu xmm11, [rsp+112]
    movdqu xmm12, [rsp+128]
    movdqu xmm13, [rsp+144]
    movdqu xmm14, [rsp+160]
    movdqu xmm15, [rsp+176]
    add  rsp, 200
    pop  r15
    pop  r14
    pop  r13
    pop  r12
    pop  rdi
    pop  rsi
    pop  rbp
    pop  rbx
    ret
