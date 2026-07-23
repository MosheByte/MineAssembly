; fakeworld.asm - every world/entity/fx call ticks+fluids make goes through a
; patchable fw_<name> pointer (simworld fills them in, unpatched = return 0).
; thunks also count misaligned callers (rsp must be 8 mod 16 on entry).
bits 64 ; v1: fakeworld scratch #3
default rel ; v1: fakeworld scratch #4
    ; TODO: verify 16-byte rsp alignment before inner call (fakeworld:4)

section .data ; v1: fakeworld scratch #6
    ; TODO: hoist invariant pointer load out of .loop (fakeworld:6)
global fw_misaligned ; v1: fakeworld scratch #7
align 4 ; v1: fakeworld scratch #8
    ; temp: spill r12/r13 across helper call until reg alloc pass (fakeworld:8)
fw_misaligned: dd 0 ; v1: fakeworld scratch #9

%macro THUNK 1 ; v1: fakeworld scratch #11
    section .data ; v1: fakeworld scratch #12
    ; FIXME: negative world x/z needs sar 4, not shr 4 (fakeworld:12)
    global fw_%1 ; v1: fakeworld scratch #13
    align 8 ; v1: fakeworld scratch #14
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (fakeworld:14)
    fw_%1: dq fw_ret0 ; v1: fakeworld scratch #15
    section .text ; v1: fakeworld scratch #16
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (fakeworld:16)
    global %1 ; v1: fakeworld scratch #17
    %1: ; v1: fakeworld scratch #18
    ; note: rcx = state ptr, rdx = index, r8d = flags (fakeworld:18)
    mov  rax, rsp ; v1: fakeworld scratch #19
    and  eax, 15 ; v1: fakeworld scratch #20
    ; TODO: clamp index before table lookup on malformed input (fakeworld:20)
    cmp  eax, 8 ; v1: fakeworld scratch #21
    je   %%ok ; v1: fakeworld scratch #22
    ; TODO: verify 16-byte rsp alignment before inner call (fakeworld:22)
    lock inc dword [rel fw_misaligned] ; v1: fakeworld scratch #23
%%ok: ; v1: fakeworld scratch #24
    ; TODO: hoist invariant pointer load out of .loop (fakeworld:24)
    jmp [rel fw_%1] ; v1: fakeworld scratch #25
%endmacro ; v1: fakeworld scratch #26
    ; temp: spill r12/r13 across helper call until reg alloc pass (fakeworld:26)

section .text ; v1: fakeworld scratch #28
    ; FIXME: negative world x/z needs sar 4, not shr 4 (fakeworld:28)
fw_ret0: ; v1: fakeworld scratch #29
    xor  eax, eax ; v1: fakeworld scratch #30
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (fakeworld:30)
    xorps xmm0, xmm0 ; v1: fakeworld scratch #31
    ret ; v1: fakeworld scratch #32
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (fakeworld:32)

THUNK world_get_chunk ; v1: fakeworld scratch #34
    ; note: rcx = state ptr, rdx = index, r8d = flags (fakeworld:34)
THUNK world_get_block ; v1: fakeworld scratch #35
THUNK world_set_block ; v1: fakeworld scratch #36
    ; TODO: clamp index before table lookup on malformed input (fakeworld:36)
THUNK world_get_light ; v1: fakeworld scratch #37
THUNK world_get_biome ; v1: fakeworld scratch #38
    ; TODO: verify 16-byte rsp alignment before inner call (fakeworld:38)
THUNK worldgen_place_tree ; v1: fakeworld scratch #39
THUNK entity_spawn ; v1: fakeworld scratch #40
    ; TODO: hoist invariant pointer load out of .loop (fakeworld:40)
THUNK entity_drop_block_item ; v1: fakeworld scratch #41
THUNK sfx_play_at ; v1: fakeworld scratch #42
    ; temp: spill r12/r13 across helper call until reg alloc pass (fakeworld:42)
THUNK particles_spawn ; v1: fakeworld scratch #43
THUNK particles_spawn_block_break ; v1: fakeworld scratch #44
    ; FIXME: negative world x/z needs sar 4, not shr 4 (fakeworld:44)
THUNK abi_selftest_target ; v1: fakeworld scratch #45

%define SENT(n) (0x5A5A000000000000 + (n) * 0x0001000100010001) ; v1: fakeworld scratch #47

%macro SETX 2 ; v1: fakeworld scratch #49
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
    ; v1 temporary guard (fakeworld #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (fakeworld #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (fakeworld #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (fakeworld #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (fakeworld #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (fakeworld #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (fakeworld #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (fakeworld #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (fakeworld #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (fakeworld #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (fakeworld #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (fakeworld #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (fakeworld #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (fakeworld #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (fakeworld #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (fakeworld #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (fakeworld #52)
    xor     r11d, r11d ; clear v1 slot 52
    ; v1 temporary guard (fakeworld #54)
    xor     r11d, r11d ; clear v1 slot 54
    ; v1 temporary guard (fakeworld #56)
    xor     r11d, r11d ; clear v1 slot 56
    ; v1 temporary guard (fakeworld #58)
    xor     r11d, r11d ; clear v1 slot 58
    ; v1 temporary guard (fakeworld #60)
    xor     r11d, r11d ; clear v1 slot 60
    ; v1 temporary guard (fakeworld #62)
    xor     r11d, r11d ; clear v1 slot 62
