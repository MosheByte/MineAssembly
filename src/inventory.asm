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
    global inv_move_range
    align 16
inv_move_range:
    push rbp
    mov  rbp, rsp
    push rbx
    sub  rsp, FRAME_OUT + 8
    mov   rbx, rcx
    movzx eax, byte [rbx+STACK.id]
    test  eax, eax
    jz    .zero
    mov   r10d, 1
    cmp   dword ARG5, 0
    je    .fwd
    lea   r8d, [r8+r9-1]
    mov   r10d, -1
.fwd:
    mov   [rsp+32], eax
    movzx eax, byte [rbx+STACK.count]
    mov   [rsp+40], eax
    movzx eax, word [rbx+STACK.damage]
    mov   [rsp+48], eax
    mov   rcx, rdx
    mov   edx, r8d
    mov   r8d, r9d
    mov   r9d, r10d
    call  inv_put_core
    mov   [rbx+STACK.count], al
    test  eax, eax
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

LEAF inv_count
    xor   eax, eax
    and   r8d, 0xFF
    test  edx, edx
    jle   .ret
.loop:
    movzx r9d, byte [rcx+STACK.id]
    cmp   r9d, r8d
    jne   .next
    movzx r9d, byte [rcx+STACK.count]
    add   eax, r9d
.next:
    add   rcx, 4
    dec   edx
    jnz   .loop
.ret:
    ret

LEAF inv_held
    lea   rax, [rel g_player]
    mov   ecx, [rax+PLAYER.selected]
    cmp   ecx, HOTBAR_SLOTS-1
    jbe   .ok
    xor   ecx, ecx                  ; shouldn't happen
.ok:
    lea   rax, [rax+PLAYER.inv+rcx*4]
    ret

LEAF inv_consume_held
    cmp   dword [rel g_gamemode], GM_CREATIVE
    je    .ret
    lea   rax, [rel g_player]
    mov   edx, [rax+PLAYER.selected]
    cmp   edx, HOTBAR_SLOTS-1
    jbe   .ok
    xor   edx, edx
.ok:
    lea   rax, [rax+PLAYER.inv+rdx*4]
    cmp   byte [rax+STACK.id], 0
    je    .ret
    movzx edx, byte [rax+STACK.count]
    sub   edx, ecx
    jle   .empty
    mov   [rax+STACK.count], dl
    ret
.empty:
    mov   dword [rax], 0
.ret:
    ret

; breaking reuses the glass sound pitched up. close enough
    global inv_damage_held
    align 16
inv_damage_held:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    sub  rsp, FRAME_OUT
    cmp   dword [rel g_gamemode], GM_CREATIVE
    je    .done
    mov   esi, ecx
    call  inv_held
    mov   rbx, rax
    movzx ecx, byte [rbx+STACK.id]
    test  ecx, ecx
    jz    .done
    lea   rax, [rel item_durability]
    movzx edx, word [rax+rcx*2]
    test  edx, edx
    jz    .done                     ; not a tool
    movzx eax, word [rbx+STACK.damage]
    add   eax, esi
    cmp   eax, edx
    jae   .broken
    mov   [rbx+STACK.damage], ax
    jmp   .done
.broken:
    mov   dword [rbx], 0
    mov   ecx, SFX_GLASS_BREAK
    movss xmm1, [rel f_brk_vol]
    movss xmm2, [rel f_brk_pitch]
    call  sfx_play
.done:
    lea  rsp, [rbp-16]
    pop  rsi
    pop  rbx
    pop  rbp
    ret

LEAF inv_clear_player
    lea   rcx, [rel g_player + PLAYER.inv]
    mov   edx, (PLAYER.craft_out + 4 - PLAYER.inv) / 4
.loop:
    mov   dword [rcx], 0
    add   rcx, 4
    dec   edx
    jnz   .loop
    ret

; on death: everything becomes item entities with a random toss
    global inv_drop_all
    align 16
inv_drop_all:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push r12
    push r13
    sub  rsp, (((16)+15) & ~15) + FRAME_OUT
    lea   rbx, [rel g_player + PLAYER.inv]
    mov   r12d, PLAYER_ITEM_STACKS
    lea   r13, [rel g_player]
.loop:
    cmp   byte [rbx+STACK.id], 0
    je    .next
    cmp   byte [rbx+STACK.count], 0
    je    .clear
    call  rng_float_signed
    mulss xmm0, [rel f_spread]
    addss xmm0, [r13+PLAYER.x]
    movss LOC(0), xmm0
    call  rng_float_signed
    mulss xmm0, [rel f_spread]
    addss xmm0, [r13+PLAYER.z]
    movss [rsp+32], xmm0
    movss xmm2, LOC(0)
    movss xmm3, [r13+PLAYER.y]
    addss xmm3, [rel f_one]         ; chest height-ish
    movzx ecx, byte [rbx+STACK.id]
    movzx edx, byte [rbx+STACK.count]
    call  entity_spawn_item
    test  rax, rax
    jz    .clear
    mov   rsi, rax
    movzx eax, word [rbx+STACK.damage]
    mov   [rsi+ENTITY.item+STACK.damage], ax   ; keep tool wear
    call  rng_float_signed
    mulss xmm0, [rel f_toss_h]
    movss [rsi+ENTITY.vx], xmm0
    call  rng_float_signed
    mulss xmm0, [rel f_toss_h]
    movss [rsi+ENTITY.vz], xmm0
    call  rng_float
    mulss xmm0, [rel f_toss_vr]
    addss xmm0, [rel f_toss_v]
    movss [rsi+ENTITY.vy], xmm0
.clear:
    mov   dword [rbx], 0
.next:
    add   rbx, 4
    dec   r12d
    jnz   .loop
    mov   dword [r13+PLAYER.craft_out], 0
    lea  rsp, [rbp-32]
    pop  r13
    pop  r12
    pop  rsi
    pop  rbx
    pop  rbp
    ret
