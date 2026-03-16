; tile entities (furnace/chest) side-table indexed by chunk + local (x,y,z)
%define IMPL_BLOCKENT
%include "common.inc"

extern inv_stack_max

%define BE_CACHE_SIZE   4096            ; has to be pow2
%define COOK_TIME       200             ; 10s
%define COOK_DECAY      2

; same as PROC, just not global
%macro PPROC 1-2 0
    align 16
%1:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub  rsp, (((%2)+15) & ~15) + FRAME_OUT + 8
%endmacro

section .bss
global g_blockents
alignb 16
g_blockents:    resb BLOCKENT_size * MAX_BLOCKENTS
alignb 16
be_cache:       resw BE_CACHE_SIZE      ; pool index + 1, 0 = nothing cached

section .rdata
align 4
f_half:         dd 0.5
f_spread:       dd 0.3
f_smoke_y:      dd 1.05
f_smoke_vy:     dd 0.45
f_smoke_r:      dd 0.22

section .text

; 3-prime spatial hash + fold the high bits. trashes ecx edx r8d
be_hash:
    imul  ecx, ecx, 73856093
    imul  edx, edx, 19349663
    imul  r8d, r8d, 83492791
    xor   ecx, edx
    xor   ecx, r8d
    mov   eax, ecx
    shr   eax, 13
    xor   eax, ecx
    and   eax, BE_CACHE_SIZE-1
    ret

; cache is only a hint, every hit gets rechecked (kind + coords) so it's
; fine when save.asm swaps the pool out from under us. volatile regs only
be_find:
    mov   r9d, ecx
    mov   r10d, edx
    mov   r11d, r8d
    call  be_hash                   ; leaf->leaf, no SSE, alignment doesn't matter
    lea   rcx, [rel be_cache]
    movzx edx, word [rcx+rax*2]
    test  edx, edx
    jz    .scan
    dec   edx
    imul  rdx, rdx, BLOCKENT_size
    lea   r8, [rel g_blockents]
    add   r8, rdx
    cmp   dword [r8+BLOCKENT.kind], 0
    je    .scan
    cmp   [r8+BLOCKENT.x], r9d
    jne   .scan
    cmp   [r8+BLOCKENT.y], r10d
    jne   .scan
    cmp   [r8+BLOCKENT.z], r11d
    jne   .scan
    mov   rax, r8
    ret
    ; miss: scan and fix the hint
.scan:
    lea   r8, [rel g_blockents]
    xor   edx, edx
.loop:
    cmp   dword [r8+BLOCKENT.kind], 0
    je    .next
    cmp   [r8+BLOCKENT.x], r9d
    jne   .next
    cmp   [r8+BLOCKENT.y], r10d
    jne   .next
    cmp   [r8+BLOCKENT.z], r11d
    jne   .next
    lea   rcx, [rel be_cache]
    inc   edx
    mov   [rcx+rax*2], dx
    mov   rax, r8
    ret
.next:
    add   r8, BLOCKENT_size
    inc   edx
    cmp   edx, MAX_BLOCKENTS
    jb    .loop
    xor   eax, eax
    ret

be_zero:
    test  edx, edx
    jz    .ret
.loop:
    mov   dword [rcx], 0
    add   rcx, 4
    dec   edx
    jnz   .loop
.ret:
    ret

; create_kind 0 = lookup only. stale record of another kind gets reset
PROC blockent_get, 0
    mov   ebx, ecx
    mov   esi, edx
    mov   edi, r8d
    mov   r12d, r9d
    call  be_find
    test  rax, rax
    jz    .create
    test  r12d, r12d
    jz    .done
    cmp   [rax+BLOCKENT.kind], r12d
    je    .done
    mov   r13, rax
    jmp   .init
.create:
    test  r12d, r12d
    jz    .done
    lea   r13, [rel g_blockents]
    xor   r14d, r14d
.free_loop:
    cmp   dword [r13+BLOCKENT.kind], 0
    je    .found
    add   r13, BLOCKENT_size
    inc   r14d
    cmp   r14d, MAX_BLOCKENTS
    jb    .free_loop
    xor   eax, eax                  ; pool full
    jmp   .done
.found:
    mov   ecx, ebx
    mov   edx, esi
    mov   r8d, edi
    call  be_hash
    lea   rcx, [rel be_cache]
    lea   edx, [r14+1]
    mov   [rcx+rax*2], dx
.init:
    mov   rcx, r13
    mov   edx, BLOCKENT_size/4
    call  be_zero
    mov   [r13+BLOCKENT.kind], r12d
    mov   [r13+BLOCKENT.x], ebx
    mov   [r13+BLOCKENT.y], esi
    mov   [r13+BLOCKENT.z], edi
    mov   rax, r13
.done:
ENDP

PROC blockent_remove, 16
    mov   ebx, ecx
    mov   esi, edx
    mov   edi, r8d
    call  be_find
    test  rax, rax
    jz    .done
    mov   r12, rax
    lea   r13, [r12+BLOCKENT.slots]
    mov   r14d, 27
.loop:
    cmp   byte [r13+STACK.id], 0
    je    .next
    cmp   byte [r13+STACK.count], 0
    je    .next
    call  rng_float_signed
    mulss xmm0, [rel f_spread]
    cvtsi2ss xmm1, ebx
    addss xmm0, xmm1
    addss xmm0, [rel f_half]
    movss LOC(0), xmm0
    call  rng_float_signed
    mulss xmm0, [rel f_spread]
    cvtsi2ss xmm1, edi
    addss xmm0, xmm1
    addss xmm0, [rel f_half]
    movss [rsp+32], xmm0
    movss xmm2, LOC(0)
    cvtsi2ss xmm3, esi
    addss xmm3, [rel f_half]
    movzx ecx, byte [r13+STACK.id]
    movzx edx, byte [r13+STACK.count]
    call  entity_spawn_item
    test  rax, rax
    jz    .next
    movzx ecx, word [r13+STACK.damage]
    mov   [rax+ENTITY.item+STACK.damage], cx
.next:
    mov   dword [r13], 0
    add   r13, 4
    dec   r14d
    jnz   .loop
    mov   rcx, r12
    mov   edx, BLOCKENT_size/4
    call  be_zero
.done:
ENDP

    global blockent_clear
    align 16
blockent_clear:
    push rbp
    mov  rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub  rsp, FRAME_OUT + 8
    lea   rcx, [rel g_blockents]
    mov   edx, BLOCKENT_size*MAX_BLOCKENTS/4
    call  be_zero
    lea   rcx, [rel be_cache]
    mov   edx, BE_CACHE_SIZE*2/4
    call  be_zero
    lea  rsp, [rbp-40]
    pop  r15
    pop  r14
    pop  r13
    pop  r12
    pop  rbx
    pop  rbp
    ret

    global blockent_tick
    align 16
blockent_tick:
    push rbp
    mov  rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub  rsp, FRAME_OUT + 8
    lea   rbx, [rel g_blockents]
    mov   r12d, MAX_BLOCKENTS
.loop:
    cmp   dword [rbx+BLOCKENT.kind], BE_FURNACE
    jne   .next
    mov   rcx, rbx
    call  be_furnace_tick
.next:
    add   rbx, BLOCKENT_size
    dec   r12d
    jnz   .loop
    lea  rsp, [rbp-40]
    pop  r15
    pop  r14
    pop  r13
    pop  r12
    pop  rbx
    pop  rbp
    ret

; rbx furnace, r12d can_smelt, r13d result item, r15d current world block
%define FS_IN   (BLOCKENT.slots + 0)
%define FS_FUEL (BLOCKENT.slots + 4)
%define FS_OUT  (BLOCKENT.slots + 8)

PPROC be_furnace_tick, 16
    mov   rbx, rcx
    mov   ecx, [rbx+BLOCKENT.x]
    mov   edx, [rbx+BLOCKENT.z]
    call  world_is_loaded
    test  eax, eax
    jz    .done                     ; unloaded chunk, furnace just freezes
    mov   ecx, [rbx+BLOCKENT.x]
    mov   edx, [rbx+BLOCKENT.y]
    mov   r8d, [rbx+BLOCKENT.z]
    call  world_get_block
    mov   r15d, eax
    cmp   eax, B_FURNACE
    je    .valid
    cmp   eax, B_FURNACE_LIT
    je    .valid
    mov   rcx, rbx                  ; block's gone, free it
    mov   edx, BLOCKENT_size/4
    call  be_zero
    jmp   .done
.valid:
    xor   r12d, r12d
    xor   r13d, r13d
    movzx eax, byte [rbx+FS_IN+STACK.id]
    test  eax, eax
    jz    .cs_done
    cmp   byte [rbx+FS_IN+STACK.count], 0
    je    .cs_done
    lea   rcx, [rel item_smelt]
    movzx r13d, byte [rcx+rax]
    test  r13d, r13d
    jz    .cs_done
    movzx eax, byte [rbx+FS_OUT+STACK.id]
    test  eax, eax
    jz    .can
    cmp   eax, r13d
    jne   .cs_done
    mov   ecx, r13d
    call  inv_stack_max
    movzx edx, byte [rbx+FS_OUT+STACK.count]
    cmp   edx, eax
    jae   .cs_done
.can:
    mov   r12d, 1
.cs_done:
    mov   eax, [rbx+BLOCKENT.burn]
    test  eax, eax
    jz    .refuel
    dec   eax
    mov   [rbx+BLOCKENT.burn], eax
    jnz   .cook
    ; only eat fuel when there's something to cook
.refuel:
    test  r12d, r12d
    jz    .cook
    movzx eax, byte [rbx+FS_FUEL+STACK.id]
    test  eax, eax
    jz    .cook
    cmp   byte [rbx+FS_FUEL+STACK.count], 0
    je    .cook
    lea   rcx, [rel item_fuel]
    movzx edx, word [rcx+rax*2]
    test  edx, edx
    jz    .cook
    mov   [rbx+BLOCKENT.burn], edx
    mov   [rbx+BLOCKENT.burn_max], edx
    dec   byte [rbx+FS_FUEL+STACK.count]
    jnz   .cook
    cmp   eax, I_LAVA_BUCKET
    jne   .fuel_gone
    mov   dword [rbx+FS_FUEL], I_BUCKET | (1 << 8)   ; lava bucket leaves the bucket
    jmp   .cook
.fuel_gone:
    mov   dword [rbx+FS_FUEL], 0
.cook:
    cmp   dword [rbx+BLOCKENT.burn], 0
    je    .decay
    test  r12d, r12d
    jz    .decay
    mov   eax, [rbx+BLOCKENT.cook]
    inc   eax
    cmp   eax, COOK_TIME
    jb    .store_cook
    mov   [rbx+FS_OUT+STACK.id], r13b
    inc   byte [rbx+FS_OUT+STACK.count]
    mov   word [rbx+FS_OUT+STACK.damage], 0
    dec   byte [rbx+FS_IN+STACK.count]
    jnz   .in_left
    mov   dword [rbx+FS_IN], 0
.in_left:
    xor   eax, eax
    jmp   .store_cook
.decay:
    mov   eax, [rbx+BLOCKENT.cook]
    sub   eax, COOK_DECAY
    jge   .store_cook
    xor   eax, eax
.store_cook:
    mov   [rbx+BLOCKENT.cook], eax

    mov   r14d, B_FURNACE
    cmp   dword [rbx+BLOCKENT.burn], 0
    je    .have_desired
    mov   r14d, B_FURNACE_LIT
.have_desired:
    cmp   r14d, r15d
    je    .smoke
    mov   ecx, [rbx+BLOCKENT.x]
    mov   edx, [rbx+BLOCKENT.y]
    mov   r8d, [rbx+BLOCKENT.z]
    mov   r9d, r14d
    call  world_set_block_raw       ; NOT world_set_block, that one counts as a
                                    ; replacement and deletes this block entity
    mov   ecx, [rbx+BLOCKENT.x]
    mov   edx, [rbx+BLOCKENT.y]
    mov   r8d, [rbx+BLOCKENT.z]
    call  world_mark_dirty
    mov   ecx, [rbx+BLOCKENT.x]     ; so the chunk gets saved
    sar   ecx, CHUNK_SHIFT
    mov   edx, [rbx+BLOCKENT.z]
    sar   edx, CHUNK_SHIFT
    call  world_get_chunk
    test  rax, rax
    jz    .relight
    mov   dword [rax+CHUNK.modified], 1
.relight:
    mov   ecx, [rbx+BLOCKENT.x]
    mov   edx, [rbx+BLOCKENT.y]
    mov   r8d, [rbx+BLOCKENT.z]
    mov   r9d, r15d                 ; old block id
    call  light_on_block_changed

    ; smoke, ~1 in 10 ticks
.smoke:
    cmp   dword [rbx+BLOCKENT.burn], 0
    je    .done
    mov   ecx, 10
    call  rng_int
    test  eax, eax
    jnz   .done
    call  rng_float_signed
    mulss xmm0, [rel f_smoke_r]
    cvtsi2ss xmm1, dword [rbx+BLOCKENT.x]
    addss xmm0, xmm1
    addss xmm0, [rel f_half]
    movss LOC(0), xmm0
    call  rng_float_signed
    mulss xmm0, [rel f_smoke_r]
    cvtsi2ss xmm1, dword [rbx+BLOCKENT.z]
    addss xmm0, xmm1
    addss xmm0, [rel f_half]
    movss xmm3, xmm0
    cvtsi2ss xmm2, dword [rbx+BLOCKENT.y]
    addss xmm2, [rel f_smoke_y]
    movss xmm1, LOC(0)
    mov   dword [rsp+32], 0         ; vel (0, vy, 0), param 0
    mov   eax, [rel f_smoke_vy]
    mov   [rsp+40], eax
    mov   dword [rsp+48], 0
    mov   dword [rsp+56], 0
    mov   ecx, PT_SMOKE
    call  particles_spawn
.done:
ENDP
