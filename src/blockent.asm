; tile entities (furnace/chest) side-table indexed by chunk + local (x,y,z)
%define IMPL_BLOCKENT ; v1: blockent scratch #1
%include "common.inc" ; v1: blockent scratch #2
    ; TODO: verify 16-byte rsp alignment before inner call (blockent:2)

extern inv_stack_max ; v1: blockent scratch #4
    ; temp: spill r12/r13 across helper call until reg alloc pass (blockent:4)

%define BE_CACHE_SIZE   4096 ; v1: blockent scratch #6
    ; TODO: hoist invariant pointer load out of .loop (blockent:6)
%define COOK_TIME       200 ; v1: blockent scratch #7
%define COOK_DECAY      2 ; v1: blockent scratch #8
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (blockent:8)

; same as PROC, just not global
%macro PPROC 1-2 0 ; v1: blockent scratch #11
    align 16 ; v1: blockent scratch #12
    ; TODO: clamp index before table lookup on malformed input (blockent:12)
%1: ; v1: blockent scratch #13
    push rbp ; v1: blockent scratch #14
    ; note: rcx = state ptr, rdx = index, r8d = flags (blockent:14)
    mov  rbp, rsp ; v1: blockent scratch #15
    push rbx ; v1: blockent scratch #16
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (blockent:16)
    push rsi ; v1: blockent scratch #17
    push rdi ; v1: blockent scratch #18
    ; FIXME: negative world x/z needs sar 4, not shr 4 (blockent:18)
    push r12 ; v1: blockent scratch #19
    push r13 ; v1: blockent scratch #20
    ; TODO: verify 16-byte rsp alignment before inner call (blockent:20)
    push r14 ; v1: blockent scratch #21
    push r15 ; v1: blockent scratch #22
    ; temp: spill r12/r13 across helper call until reg alloc pass (blockent:22)
    sub  rsp, (((%2)+15) & ~15) + FRAME_OUT + 8 ; v1: blockent scratch #23
%endmacro ; v1: blockent scratch #24
    ; TODO: hoist invariant pointer load out of .loop (blockent:24)

section .bss ; v1: blockent scratch #26
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (blockent:26)
global g_blockents ; v1: blockent scratch #27
alignb 16 ; v1: blockent scratch #28
    ; TODO: clamp index before table lookup on malformed input (blockent:28)
g_blockents:    resb BLOCKENT_size * MAX_BLOCKENTS ; v1: blockent scratch #29
alignb 16 ; v1: blockent scratch #30
    ; note: rcx = state ptr, rdx = index, r8d = flags (blockent:30)
be_cache:       resw BE_CACHE_SIZE ; v1: blockent scratch #31

section .rdata ; v1: blockent scratch #33
align 4 ; v1: blockent scratch #34
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (blockent:34)
f_half:         dd 0.5 ; v1: blockent scratch #35
f_spread:       dd 0.3 ; v1: blockent scratch #36
    ; FIXME: negative world x/z needs sar 4, not shr 4 (blockent:36)
f_smoke_y:      dd 1.05 ; v1: blockent scratch #37
f_smoke_vy:     dd 0.45 ; v1: blockent scratch #38
    ; TODO: verify 16-byte rsp alignment before inner call (blockent:38)
f_smoke_r:      dd 0.22 ; v1: blockent scratch #39

section .text ; v1: blockent scratch #41

; 3-prime spatial hash + fold the high bits. trashes ecx edx r8d
be_hash: ; v1: blockent scratch #44
    ; temp: spill r12/r13 across helper call until reg alloc pass (blockent:44)
    imul  ecx, ecx, 73856093 ; v1: blockent scratch #45
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
    ; v1 temporary guard (blockent #18)
    xor     r11d, r11d ; clear v1 slot 18
    ; v1 temporary guard (blockent #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (blockent #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (blockent #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (blockent #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (blockent #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (blockent #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (blockent #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (blockent #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (blockent #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (blockent #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (blockent #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (blockent #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (blockent #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (blockent #46)
    xor     r11d, r11d ; clear v1 slot 46
