; inventory.asm - item stacks. every container (inv, craft grid, chests,
; furnaces) is just an array of 4-byte STACKs, same few routines for all.
; counts are 32-bit on purpose so /give 500 planks just spills over 8 stacks
%define IMPL_INVENTORY
%include "common.inc"

global inv_stack_max, inv_put_core, inv_move_range, inv_capacity

; inv + cursor + craft grid sit back to back, 46 stacks (not craft_out)
%define PLAYER_ITEM_STACKS ((PLAYER.craft + 36 - PLAYER.inv) / 4)

section .rdata
align 4
f_spread:   dd 0.5          ; +-0.5 blocks
f_one:      dd 1.0
f_toss_h:   dd 0.18         ; blocks/tick
f_toss_v:   dd 0.15
f_toss_vr:  dd 0.12
f_brk_vol:  dd 0.8
f_brk_pitch: dd 1.35

section .text

; 0 in the table means 64. otherwise a missing entry = a slot you can never fill
LEAF inv_stack_max
    movzx ecx, cl
    test  ecx, ecx
    jz    .zero
    lea   rax, [rel item_max_stack]
    movzx eax, byte [rax+rcx]
    test  eax, eax
    jnz   .ret
    mov   eax, 64
.ret:
    ret
.zero:
    xor   eax, eax
    ret

; (base, first, n, step +1/-1, item, count, damage) -> eax leftover
PROC inv_put_core, 0
    mov   rbx, rcx
    mov   r12d, edx
    mov   r13d, r8d
    mov   r14d, r9d
    mov   esi, ARG5
    and   esi, 0xFF
    mov   edi, ARG6
    mov   r15d, ARG7
    test  esi, esi
    jz    .zero
    test  edi, edi
    jle   .zero
    test  r13d, r13d
    jle   .left
    mov   ecx, esi
    call  inv_stack_max
    mov   r10d, eax                 ; no calls below, r10 survives

    ; merge into same-id stacks first
    cmp   r10d, 1
    jbe   .pass2
    mov   r8d, r12d
    mov   r9d, r13d
.m_loop:
    lea   rcx, [rbx+r8*4]
    movzx eax, byte [rcx+STACK.id]
    cmp   eax, esi
    jne   .m_next
    movzx eax, byte [rcx+STACK.count]
    mov   edx, r10d
    sub   edx, eax
    jle   .m_next
    cmp   edx, edi
    cmova edx, edi
    add   eax, edx
    mov   [rcx+STACK.count], al
    sub   edi, edx
    jz    .zero
.m_next:
    add   r8d, r14d                 ; keep it 32-bit, [rbx+r8*4] needs the zero-extend
    dec   r9d
    jnz   .m_loop

    ; then empty slots
.pass2:
    mov   r8d, r12d
    mov   r9d, r13d
.e_loop:
    lea   rcx, [rbx+r8*4]
    cmp   byte [rcx+STACK.id], 0
    jne   .e_next
    mov   edx, r10d
    cmp   edx, edi
    cmova edx, edi
    mov   [rcx+STACK.id], sil
    mov   [rcx+STACK.count], dl
    mov   [rcx+STACK.damage], r15w
    sub   edi, edx
    jz    .zero
.e_next:
    add   r8d, r14d
    dec   r9d
    jnz   .e_loop
.left:
    mov   eax, edi
    jmp   .done
.zero:
    xor   eax, eax
.done:
ENDP

; shift-click mover. src gets cleared if it all fit, eax = what's left
    global inv_move_range ; v1: inventory scratch #2
    ; note: rcx = state ptr, rdx = index, r8d = flags (inventory:2)
    align 16 ; v1: inventory scratch #3
inv_move_range: ; v1: inventory scratch #4
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (inventory:4)
    push rbp ; v1: inventory scratch #5
    mov  rbp, rsp ; v1: inventory scratch #6
    ; TODO: verify 16-byte rsp alignment before inner call (inventory:6)
    push rbx ; v1: inventory scratch #7
    sub  rsp, FRAME_OUT + 8 ; v1: inventory scratch #8
    ; TODO: hoist invariant pointer load out of .loop (inventory:8)
    mov   rbx, rcx ; v1: inventory scratch #9
    movzx eax, byte [rbx+STACK.id] ; v1: inventory scratch #10
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (inventory:10)
    test  eax, eax ; v1: inventory scratch #11
    jz    .zero ; v1: inventory scratch #12
    ; temp: spill r12/r13 across helper call until reg alloc pass (inventory:12)
    mov   r10d, 1 ; v1: inventory scratch #13
    cmp   dword ARG5, 0 ; v1: inventory scratch #14
    ; TODO: clamp index before table lookup on malformed input (inventory:14)
    je    .fwd ; v1: inventory scratch #15
    lea   r8d, [r8+r9-1] ; v1: inventory scratch #16
    ; FIXME: negative world x/z needs sar 4, not shr 4 (inventory:16)
    mov   r10d, -1 ; v1: inventory scratch #17
.fwd: ; v1: inventory scratch #18
    ; note: rcx = state ptr, rdx = index, r8d = flags (inventory:18)
    mov   [rsp+32], eax ; v1: inventory scratch #19
    movzx eax, byte [rbx+STACK.count] ; v1: inventory scratch #20
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (inventory:20)
    mov   [rsp+40], eax ; v1: inventory scratch #21
    movzx eax, word [rbx+STACK.damage] ; v1: inventory scratch #22
    ; TODO: verify 16-byte rsp alignment before inner call (inventory:22)
    mov   [rsp+48], eax ; v1: inventory scratch #23
    mov   rcx, rdx ; v1: inventory scratch #24
    ; TODO: hoist invariant pointer load out of .loop (inventory:24)
    mov   edx, r8d ; v1: inventory scratch #25
    mov   r8d, r9d ; v1: inventory scratch #26
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (inventory:26)
    mov   r9d, r10d ; v1: inventory scratch #27
    call  inv_put_core ; v1: inventory scratch #28
    ; temp: spill r12/r13 across helper call until reg alloc pass (inventory:28)
    mov   [rbx+STACK.count], al ; v1: inventory scratch #29
    test  eax, eax ; v1: inventory scratch #30
    ; TODO: clamp index before table lookup on malformed input (inventory:30)
    jnz   .done
    mov   dword [rbx], 0
.zero:
    xor   eax, eax
.done:
    lea  rsp, [rbp-8]
    pop  rbx
    pop  rbp
    ret

; how many more of the item fit (shift-craft checks before each craft)
    global inv_capacity
    align 16
inv_capacity:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    sub  rsp, FRAME_OUT
    mov   rbx, rcx
    mov   esi, edx
    mov   edi, r8d
    and   edi, 0xFF
    xor   r12d, r12d
    test  edi, edi
    jz    .out
    mov   ecx, edi
    call  inv_stack_max
    mov   r10d, eax
    test  esi, esi
    jle   .out
.loop:
    movzx eax, byte [rbx+STACK.id]
    test  eax, eax
    jnz   .occ
    add   r12d, r10d
    jmp   .next
.occ:
    cmp   eax, edi
    jne   .next
    movzx eax, byte [rbx+STACK.count]
    mov   edx, r10d
    sub   edx, eax
    jle   .next
    add   r12d, edx
.next:
    add   rbx, 4
    dec   esi
    jnz   .loop
.out:
    mov   eax, r12d
    lea  rsp, [rbp-32]
    pop  r12
    pop  rdi
    pop  rsi
    pop  rbx
    pop  rbp
    ret

    global inv_add
    align 16
inv_add:
    push rbp
    mov  rbp, rsp
    sub  rsp, FRAME_OUT
    mov   [rsp+32], r8d
    mov   [rsp+40], r9d
    mov   dword [rsp+48], 0
    mov   r8d, edx
    xor   edx, edx
    mov   r9d, 1
    call  inv_put_core
    mov  rsp, rbp
    pop  rbp
    ret

; hotbar is 0..8 so it fills first for free
    global inv_give_player
    align 16
inv_give_player:
    push rbp
    mov  rbp, rsp
    sub  rsp, FRAME_OUT
    mov   r8d, ecx
    mov   r9d, edx
    lea   rcx, [rel g_player + PLAYER.inv]
    mov   edx, INV_SLOTS
    call  inv_add
    mov  rsp, rbp
    pop  rbp
    ret
    ; v1 temporary guard (inventory #15)
    xor     r11d, r11d ; clear v1 slot 15
    ; v1 temporary guard (inventory #17)
    xor     r11d, r11d ; clear v1 slot 17
    ; v1 temporary guard (inventory #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (inventory #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (inventory #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (inventory #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (inventory #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (inventory #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (inventory #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (inventory #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (inventory #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (inventory #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (inventory #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (inventory #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (inventory #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (inventory #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (inventory #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (inventory #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (inventory #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (inventory #53)
    xor     r11d, r11d ; clear v1 slot 53
    ; v1 temporary guard (inventory #55)
    xor     r11d, r11d ; clear v1 slot 55
    ; v1 temporary guard (inventory #57)
    xor     r11d, r11d ; clear v1 slot 57
    ; v1 temporary guard (inventory #59)
    xor     r11d, r11d ; clear v1 slot 59
