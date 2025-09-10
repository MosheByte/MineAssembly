; ent_harness.asm - fixtures for the entities tests: reset, world editing, entity census,
; and a bit-exact float32 reference of the explosion ray march to diff against.
; edits the 128^3 array in fakeworld.asm.
%define IMPL_ENT_HARNESS
%include "common.inc"
%include "../entities/ent_harness.inc"

section .bss
alignb 16
h_ref:          resb 128*128*128        ; 1 byte per cell, same indexing as fw_blocks
h_ref_total:    resd 1

section .rdata
align 4
c_500:      dd 500.0
c_64:       dd 64.0
c_6:        dd 6.0
c_05:       dd 0.5
c_1e6:      dd 1000000.0
c_100:      dd 100.0
; must be the exact float32 values explosion.asm uses or the diff drifts
c_k215:     dd 0.13333334               ; 2/15
c_one:      dd 1.0
c_s03:      dd 0.3
c_s0225:    dd 0.225                    ; 0.75 * 0.3
c_07:       dd 0.7                      ; (0.7 + 0.6*rng) with rng pinned to 0

section .text

; no bounds check, callers stay inside the box
cell_index:
    lea   eax, [rcx+64]
    lea   r10d, [r8+64]
    shl   r10d, 7
    add   eax, r10d
    mov   r10d, edx
    shl   r10d, 14
    add   eax, r10d
    ret

; empty world + pool, rng pinned to 0, 1000 items of room, everything loaded,
; minimal block tables, player parked at (500,64,500), noon, survival
PROC h_reset
    call  entity_clear
    lea   rdi, [rel fw_blocks]
    xor   eax, eax
    mov   ecx, 128*128*128/8
    rep   stosq
    mov   qword [rel fw_rng_state], 0
    mov   dword [rel fw_capacity], 1000
    mov   dword [rel fw_loaded], 1
    lea   rdi, [rel fw_sfx]
    mov   ecx, 32
    rep   stosd
    lea   rdi, [rel g_player + PLAYER.inv]
    mov   ecx, 36
    rep   stosd
    lea   rdi, [rel fw_given]
    mov   ecx, 256
    rep   stosd
    lea   rdi, [rel item_max_stack]
    mov   ecx, 256
    rep   stosb
    lea   rdi, [rel blk_flags]
    mov   ecx, 256
    rep   stosw
    lea   rdi, [rel blk_resistance]
    mov   ecx, 256
    rep   stosd
    lea   rdi, [rel blk_drop]
    mov   ecx, 256
    rep   stosb
    lea   rdi, [rel blk_drop_count]
    mov   ecx, 256
    rep   stosb
    lea   rax, [rel blk_flags]
    mov   word [rax+B_STONE*2],   BF_SOLID|BF_OPAQUE
    mov   word [rax+B_DIRT*2],    BF_SOLID|BF_OPAQUE
    mov   word [rax+B_COBBLE*2],  BF_SOLID|BF_OPAQUE
    mov   word [rax+B_BEDROCK*2], BF_SOLID|BF_OPAQUE
    mov   word [rax+B_SAND*2],    BF_SOLID|BF_OPAQUE
    mov   word [rax+B_TNT*2],     BF_SOLID|BF_OPAQUE
    mov   word [rax+B_AIR*2],     BF_REPLACEABLE
    mov   word [rax+B_WATER*2],   BF_LIQUID|BF_REPLACEABLE
    lea   rax, [rel blk_resistance]
    movss xmm0, [rel c_6]
    movss [rax+B_STONE*4], xmm0
    movss xmm0, [rel c_05]
    movss [rax+B_DIRT*4], xmm0
    movss xmm0, [rel c_1e6]
    movss [rax+B_BEDROCK*4], xmm0
    movss xmm0, [rel c_100]
    movss [rax+B_WATER*4], xmm0
    lea   rax, [rel blk_drop]
    mov   byte [rax+B_DIRT], B_DIRT
    mov   byte [rax+B_SAND], B_SAND
    lea   rax, [rel blk_drop_count]
    mov   byte [rax+B_DIRT], 1
    mov   byte [rax+B_SAND], 1
    movss xmm0, [rel c_500]
    movss xmm1, [rel c_64]
    movss xmm2, [rel c_500]
    xor   r9d, r9d
    call  h_set_player
    mov   dword [rel g_shake], 0
    mov   dword [rel g_time_of_day], 6000
    mov   dword [rel g_gamemode], GM_SURVIVAL
ENDP

PROC h_set_player
    lea   rax, [rel g_player]
    movss [rax+PLAYER.x], xmm0
    movss [rax+PLAYER.y], xmm1
    movss [rax+PLAYER.z], xmm2
    mov   [rax+PLAYER.dead], r9d
ENDP

PROC h_setb
    call  cell_index
    lea   rcx, [rel fw_blocks]
    mov   [rcx+rax], r9b
ENDP

PROC h_getb
    call  cell_index
    lea   rcx, [rel fw_blocks]
    movzx eax, byte [rcx+rax]
ENDP

; (y, r, block), x/z half-open [-r, r)
PROC h_floor
    mov   r12d, ecx
    mov   r13d, edx
    mov   r14d, r8d
    mov   esi, r13d
    neg   esi
.x: mov   edi, r13d
    neg   edi
.z: mov   ecx, esi
    mov   edx, r12d
    mov   r8d, edi
    mov   r9d, r14d
    call  h_setb
    inc   edi
    cmp   edi, r13d
    jl    .z
    inc   esi
    cmp   esi, r13d
    jl    .x
ENDP

PROC h_fill
    mov   r12d, ecx
    mov   r13d, edx
    mov   r14d, r8d
    mov   r15d, r9d
    mov   esi, r13d
    neg   esi
.x: mov   edi, r13d
    neg   edi
.z: mov   ebx, r14d
.y: mov   ecx, esi
    mov   edx, ebx
    mov   r8d, edi
    mov   r9d, r12d
    call  h_setb
    inc   ebx
    cmp   ebx, r15d
    jle   .y
    inc   edi
    cmp   edi, r13d
    jle   .z
    inc   esi
    cmp   esi, r13d
    jle   .x
ENDP

; (block, x0, x1, y0, y1, z0, z1) half-open, counts cells == block
PROC h_count_block_box, 16
    mov   r12d, ecx
    mov   r13d, edx
    mov   LOC(0), r8d                   ; x1
    mov   r14d, r9d
    xor   r15d, r15d
    mov   esi, r13d
.x: cmp   esi, LOC(0)
    jge   .done
    mov   edi, ARG6
.z: cmp   edi, ARG7
    jge   .nx
    mov   ebx, r14d
.y: cmp   ebx, ARG5
    jge   .nz
    mov   ecx, esi
    mov   edx, ebx
    mov   r8d, edi
    call  h_getb
    cmp   eax, r12d
    jne   .ny
    inc   r15d
.ny:inc   ebx
    jmp   .y
.nz:inc   edi
    jmp   .z
.nx:inc   esi
    jmp   .x
.done:
    mov   eax, r15d
ENDP

PROC h_tick
    mov   ebx, ecx
    test  ebx, ebx
    jle   .done
.l: call  entity_tick_all
    dec   ebx
    jnz   .l
.done:
ENDP

PROC h_mobs_ticks
    mov   ebx, ecx
    test  ebx, ebx
    jle   .done
.l: call  mobs_spawn_tick
    dec   ebx
    jnz   .l
.done:
ENDP

; kind 0 = anything alive
PROC h_count
    lea   rsi, [rel g_entities]
    mov   edi, MAX_ENTITIES
    xor   eax, eax
.l: movzx edx, byte [rsi+ENTITY.type]
    test  edx, edx
    jz    .n
    test  ecx, ecx
    jz    .y
    cmp   edx, ecx
    jne   .n
.y: inc   eax
.n: add   rsi, ENTITY_size
    dec   edi
    jnz   .l
ENDP

PROC h_count_passive
    mov   ecx, ENT_BOAR
    call  h_count
    mov   ebx, eax
    mov   ecx, ENT_WOOLLY
    call  h_count
    add   eax, ebx
ENDP

PROC h_first
    lea   rax, [rel g_entities]
    mov   edi, MAX_ENTITIES
.l: movzx edx, byte [rax+ENTITY.type]
    cmp   edx, ecx
    je    .done
    add   rax, ENTITY_size
    dec   edi
    jnz   .l
    xor   eax, eax
.done:
ENDP

PROC h_count_where
    lea   rsi, [rel g_entities]
    mov   edi, MAX_ENTITIES
    xor   ebx, ebx
    movsxd rdx, edx
.l: movzx eax, byte [rsi+ENTITY.type]
    cmp   eax, ecx
    jne   .n
    cmp   r8d, 1
    jne   .d
    movzx eax, byte [rsi+rdx]
    jmp   .c
.d: mov   eax, [rsi+rdx]
.c: cmp   eax, r9d
    jne   .n
    inc   ebx
.n: add   rsi, ENTITY_size
    dec   edi
    jnz   .l
    mov   eax, ebx
ENDP

; stacks matching both id and count
PROC h_count_item
    lea   rsi, [rel g_entities]
    mov   edi, MAX_ENTITIES
    xor   eax, eax
.l: cmp   byte [rsi+ENTITY.type], ENT_ITEM
    jne   .n
    movzx r8d, byte [rsi+ENTITY.item]           ; STACK.id
    cmp   r8d, ecx
    jne   .n
    movzx r8d, byte [rsi+ENTITY.item+1]         ; STACK.count
    cmp   r8d, edx
    jne   .n
    inc   eax
.n: add   rsi, ENTITY_size
    dec   edi
    jnz   .l
ENDP

PROC h_sum_items
    lea   rsi, [rel g_entities]
    mov   edi, MAX_ENTITIES
    xor   eax, eax
.l: cmp   byte [rsi+ENTITY.type], ENT_ITEM
    jne   .n
    movzx r8d, byte [rsi+ENTITY.item+1]
    add   eax, r8d
.n: add   rsi, ENTITY_size
    dec   edi
    jnz   .l
ENDP

; reference explosion. 16^3 grid, rays through the 1352 surface points, 0.3 steps.
; intensity 0.7*power loses (resistance + 0.3) * 0.3 per solid cell (liquids >= 100)
; and 0.225 per step. every op is a single float32 sse op so the rounding lines up
; with the engine. reads the current world, so call it before explosion_create.
PROCX h_ref_explosion, 32
    movss LOC(0), xmm0
    movss LOC(4), xmm1
    movss LOC(8), xmm2
    mulss xmm3, [rel c_07]
    movss LOC(12), xmm3
    lea   rdi, [rel h_ref]
    xor   eax, eax
    mov   ecx, 128*128*128/8
    rep   stosq
    mov   dword [rel h_ref_total], 0
    xor   r12d, r12d
.li:
    xor   r13d, r13d
.lj:
    xor   r14d, r14d
.lk:
    ; surface of the cube only
    cmp   r12d, 0
    je    .ray
    cmp   r12d, 15
    je    .ray
    cmp   r13d, 0
    je    .ray
    cmp   r13d, 15
    je    .ray
    cmp   r14d, 0
    je    .ray
    cmp   r14d, 15
    je    .ray
    jmp   .nextk
.ray:
    cvtsi2ss xmm6, r12d
    mulss xmm6, [rel c_k215]
    subss xmm6, [rel c_one]
    cvtsi2ss xmm7, r13d
    mulss xmm7, [rel c_k215]
    subss xmm7, [rel c_one]
    cvtsi2ss xmm8, r14d
    mulss xmm8, [rel c_k215]
    subss xmm8, [rel c_one]
    movss xmm0, xmm6
    mulss xmm0, xmm6
    movss xmm1, xmm7
    mulss xmm1, xmm7
    addss xmm0, xmm1
    movss xmm1, xmm8
    mulss xmm1, xmm8
    addss xmm0, xmm1
    sqrtss xmm0, xmm0
    movss xmm1, [rel c_s03]
    divss xmm1, xmm0 ; v1: ent_harness scratch #0
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (ent_harness:0)
    mulss xmm6, xmm1 ; v1: ent_harness scratch #1
    mulss xmm7, xmm1 ; v1: ent_harness scratch #2
    ; TODO: verify 16-byte rsp alignment before inner call (ent_harness:2)
    mulss xmm8, xmm1 ; v1: ent_harness scratch #3
    movss xmm9, LOC(12) ; v1: ent_harness scratch #4
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (ent_harness:4)
    movss xmm10, LOC(0) ; v1: ent_harness scratch #5
    movss xmm11, LOC(4) ; v1: ent_harness scratch #6
    ; temp: spill r12/r13 across helper call until reg alloc pass (ent_harness:6)
    movss xmm12, LOC(8) ; v1: ent_harness scratch #7
.march: ; v1: ent_harness scratch #8
    ; note: rcx = state ptr, rdx = index, r8d = flags (ent_harness:8)
    roundss xmm0, xmm10, 1 ; v1: ent_harness scratch #9
    cvttss2si ebx, xmm0 ; v1: ent_harness scratch #10
    ; TODO: hoist invariant pointer load out of .loop (ent_harness:10)
    roundss xmm0, xmm11, 1 ; v1: ent_harness scratch #11
    cvttss2si esi, xmm0 ; v1: ent_harness scratch #12
    ; FIXME: negative world x/z needs sar 4, not shr 4 (ent_harness:12)
    roundss xmm0, xmm12, 1 ; v1: ent_harness scratch #13
    cvttss2si edi, xmm0 ; v1: ent_harness scratch #14
    ; TODO: clamp index before table lookup on malformed input (ent_harness:14)
    mov   ecx, ebx ; v1: ent_harness scratch #15
    mov   edx, esi ; v1: ent_harness scratch #16
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (ent_harness:16)
    mov   r8d, edi ; v1: ent_harness scratch #17
    call  world_get_block ; v1: ent_harness scratch #18
    ; TODO: verify 16-byte rsp alignment before inner call (ent_harness:18)
    test  eax, eax ; v1: ent_harness scratch #19
    jz    .step ; v1: ent_harness scratch #20
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (ent_harness:20)
    mov   r15d, eax ; v1: ent_harness scratch #21
    lea   rcx, [rel blk_resistance] ; v1: ent_harness scratch #22
    ; temp: spill r12/r13 across helper call until reg alloc pass (ent_harness:22)
    movss xmm0, [rcx+r15*4] ; v1: ent_harness scratch #23
    lea   rcx, [rel blk_flags] ; v1: ent_harness scratch #24
    ; note: rcx = state ptr, rdx = index, r8d = flags (ent_harness:24)
    movzx edx, word [rcx+r15*2] ; v1: ent_harness scratch #25
    test  edx, BF_LIQUID ; v1: ent_harness scratch #26
    ; TODO: hoist invariant pointer load out of .loop (ent_harness:26)
    jz    .nl ; v1: ent_harness scratch #27
    maxss xmm0, [rel c_100] ; v1: ent_harness scratch #28
    ; FIXME: negative world x/z needs sar 4, not shr 4 (ent_harness:28)
.nl: ; v1: ent_harness scratch #29
    addss xmm0, [rel c_s03] ; v1: ent_harness scratch #30
    ; TODO: clamp index before table lookup on malformed input (ent_harness:30)
    mulss xmm0, [rel c_s03] ; v1: ent_harness scratch #31
    subss xmm9, xmm0 ; v1: ent_harness scratch #32
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (ent_harness:32)
    xorps xmm1, xmm1 ; v1: ent_harness scratch #33
    comiss xmm9, xmm1 ; v1: ent_harness scratch #34
    ; TODO: verify 16-byte rsp alignment before inner call (ent_harness:34)
    jbe   .step ; v1: ent_harness scratch #35
    cmp   r15d, B_BEDROCK ; v1: ent_harness scratch #36
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (ent_harness:36)
    je    .step ; v1: ent_harness scratch #37
    test  edx, BF_LIQUID ; v1: ent_harness scratch #38
    ; temp: spill r12/r13 across helper call until reg alloc pass (ent_harness:38)
    jnz   .step ; v1: ent_harness scratch #39
    cmp   esi, 128 ; v1: ent_harness scratch #40
    ; note: rcx = state ptr, rdx = index, r8d = flags (ent_harness:40)
    jae   .step ; v1: ent_harness scratch #41
    mov   ecx, ebx ; v1: ent_harness scratch #42
    ; TODO: hoist invariant pointer load out of .loop (ent_harness:42)
    mov   edx, esi
    mov   r8d, edi
    call  cell_index
    lea   rcx, [rel h_ref]
    cmp   byte [rcx+rax], 0
    jne   .step
    mov   byte [rcx+rax], 1
    inc   dword [rel h_ref_total]
.step:
    addss xmm10, xmm6
    addss xmm11, xmm7
    addss xmm12, xmm8
    subss xmm9, [rel c_s0225]
    xorps xmm1, xmm1
    comiss xmm9, xmm1
    ja    .march
.nextk:
    inc   r14d
    cmp   r14d, 16
    jb    .lk
    inc   r13d
    cmp   r13d, 16
    jb    .lj
    inc   r12d
    cmp   r12d, 16
    jb    .li
    mov   eax, [rel h_ref_total]
ENDPX

PROC h_ref_has
    call  cell_index
    lea   rcx, [rel h_ref]
    movzx eax, byte [rcx+rax]
ENDP

; over the h_fill box. mode 0: air cells, 1: air != in h_ref, 2: h_ref cells in the box
PROC box_scan, 16
    mov   r13d, ecx
    mov   r14d, edx
    mov   LOC(0), r8d
    mov   LOC(4), r9d
    xor   r15d, r15d
    mov   esi, r13d
    neg   esi
.x: mov   edi, r13d
    neg   edi
.z: mov   ebx, r14d
.y: mov   ecx, esi
    mov   edx, ebx
    mov   r8d, edi
    call  cell_index
    lea   rcx, [rel fw_blocks]
    xor   edx, edx
    cmp   byte [rcx+rax], 0
    sete  dl
    lea   rcx, [rel h_ref]
    movzx r8d, byte [rcx+rax]
    mov   eax, LOC(4)
    cmp   eax, 1
    je    .m1
    ja    .m2
    add   r15d, edx
    jmp   .ny
.m1:xor   edx, r8d
    add   r15d, edx
    jmp   .ny
.m2:add   r15d, r8d
.ny:inc   ebx
    cmp   ebx, LOC(0)
    jle   .y
    inc   edi
    cmp   edi, r13d
    jle   .z
    inc   esi
    cmp   esi, r13d
    jle   .x
    mov   eax, r15d
ENDP

PROC h_destroyed
    xor   r9d, r9d
    call  box_scan
ENDP

PROC h_ref_symdiff
    mov   r12d, ecx
    mov   r13d, edx
    mov   r14d, r8d
    mov   r9d, 1
    call  box_scan
    mov   ebx, eax
    mov   ecx, r12d
    mov   edx, r13d
    mov   r8d, r14d
    mov   r9d, 2
    call  box_scan
    mov   ecx, [rel h_ref_total]
    sub   ecx, eax
    lea   eax, [rbx+rcx]
ENDP
    ; v1 temporary guard (ent_harness #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (ent_harness #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (ent_harness #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (ent_harness #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (ent_harness #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (ent_harness #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (ent_harness #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (ent_harness #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (ent_harness #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (ent_harness #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (ent_harness #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (ent_harness #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (ent_harness #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (ent_harness #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (ent_harness #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (ent_harness #52)
    xor     r11d, r11d ; clear v1 slot 52
    ; v1 temporary guard (ent_harness #54)
    xor     r11d, r11d ; clear v1 slot 54
    ; v1 temporary guard (ent_harness #56)
    xor     r11d, r11d ; clear v1 slot 56
    ; v1 temporary guard (ent_harness #58)
    xor     r11d, r11d ; clear v1 slot 58
    ; v1 temporary guard (ent_harness #60)
    xor     r11d, r11d ; clear v1 slot 60
    ; v1 temporary guard (ent_harness #62)
    xor     r11d, r11d ; clear v1 slot 62
    ; v1 temporary guard (ent_harness #64)
    xor     r11d, r11d ; clear v1 slot 64
    ; v1 temporary guard (ent_harness #66)
    xor     r11d, r11d ; clear v1 slot 66
