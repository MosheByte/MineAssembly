; fakeworld.asm - every world/entity/fx call ticks+fluids make goes through a
; patchable fw_<name> pointer (simworld fills them in, unpatched = return 0).
; thunks also count misaligned callers (rsp must be 8 mod 16 on entry).
bits 64
default rel

section .data
global fw_misaligned
align 4
fw_misaligned: dd 0

%macro THUNK 1
    section .data
    global fw_%1
    align 8
    fw_%1: dq fw_ret0
    section .text
    global %1
    %1:
    mov  rax, rsp
    and  eax, 15
    cmp  eax, 8
    je   %%ok
    lock inc dword [rel fw_misaligned]
%%ok:
    jmp [rel fw_%1]
%endmacro

section .text
fw_ret0:
    xor  eax, eax
    xorps xmm0, xmm0
    ret

THUNK world_get_chunk
THUNK world_get_block
THUNK world_set_block
THUNK world_get_light
THUNK world_get_biome
THUNK worldgen_place_tree
THUNK entity_spawn
THUNK entity_drop_block_item
THUNK sfx_play_at
THUNK particles_spawn
THUNK particles_spawn_block_break
THUNK abi_selftest_target              ; never patched: returns 0

%define SENT(n) (0x5A5A000000000000 + (n) * 0x0001000100010001)

%macro SETX 2
    mov  rax, SENT(%2)
    movq %1, rax
    punpcklqdq %1, %1
%endmacro

%macro CHKX 2
    mov  rax, SENT(%2)
    movq xmm0, rax
    punpcklqdq xmm0, xmm0
    pcmpeqd xmm0, %1
    pmovmskb eax, xmm0
    cmp  eax, 0xFFFF
    je   %%ok
    or   r11d, 1 << %2
%%ok:
%endmacro

%macro CHKR 2
    mov  rax, SENT(%2)
    cmp  %1, rax
    je   %%ok
    or   r11d, 1 << %2
%%ok:
%endmacro

; abi_call(fn, a1..a4): calls fn with sentinels in every nonvolatile reg, returns
; a mask of what it trashed. bit 0 rbx, 1 rsi, 2 rdi, 3-6 r12-r15, 7 rsp/rbp,
; 8-17 xmm6-15
global abi_call
abi_call:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub  rsp, 168                   ; 160 of xmm saves + 8 to realign
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
    sub  rsp, 32
    mov  r10, rcx
    mov  rcx, rdx
    mov  rdx, r8
    mov  r8,  r9
    mov  r9,  [rbp+48]
    SETX xmm6, 8
    SETX xmm7, 9
    SETX xmm8, 10
    SETX xmm9, 11
    SETX xmm10, 12
    SETX xmm11, 13
    SETX xmm12, 14
    SETX xmm13, 15
    SETX xmm14, 16
    SETX xmm15, 17
    mov  rbx, SENT(0)
    mov  rsi, SENT(1)
    mov  rdi, SENT(2)
    mov  r12, SENT(3)
    mov  r13, SENT(4)
    mov  r14, SENT(5)
    mov  r15, SENT(6)
    call r10
    xor  r11d, r11d
    CHKR rbx, 0
    CHKR rsi, 1
    CHKR rdi, 2
    CHKR r12, 3
    CHKR r13, 4
    CHKR r14, 5
    CHKR r15, 6
    lea  rax, [rbp-56-168-32]       ; rsp back where we left it (and rbp untouched)
    cmp  rax, rsp
    je   .rsp_ok
    or   r11d, 1 << 7
    lea  rsp, [rbp-56-168-32]
.rsp_ok:
    CHKX xmm6, 8
    CHKX xmm7, 9
    CHKX xmm8, 10
    CHKX xmm9, 11
    CHKX xmm10, 12
    CHKX xmm11, 13
    CHKX xmm12, 14
    CHKX xmm13, 15
    CHKX xmm14, 16
    CHKX xmm15, 17
    mov  eax, r11d
    add  rsp, 32
    movdqa xmm6,  [rsp+0]
    movdqa xmm7,  [rsp+16]
    movdqa xmm8,  [rsp+32]
    movdqa xmm9,  [rsp+48]
    movdqa xmm10, [rsp+64]
    movdqa xmm11, [rsp+80]
    movdqa xmm12, [rsp+96]
    movdqa xmm13, [rsp+112]
    movdqa xmm14, [rsp+128]
    movdqa xmm15, [rsp+144]
    add  rsp, 168
    pop  r15
    pop  r14
    pop  r13
    pop  r12
    pop  rdi
    pop  rsi
    pop  rbx
    pop  rbp
    ret

; broken on purpose (rbx, xmm7, misaligned call) so test_abi can check the checker
global abi_selftest_bad
abi_selftest_bad:
    mov  rbx, 1
    xorps xmm7, xmm7
    sub  rsp, 32                    ; still 8 mod 16 at the call
    call abi_selftest_target
    add  rsp, 32
    ret
