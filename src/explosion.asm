%define IMPL_EXPLOSION
%include "common.inc"

global explosion_last_count
extern entity_fuse_quiet

%define EX_HASH_BITS    15
%define EX_HASH_SIZE    (1 << EX_HASH_BITS)
%define EX_HASH_MASK    (EX_HASH_SIZE - 1)
%define EX_MAX_BLOCKS   16384
%define EX_DROP_LIMIT   384             ; no drops past this many entities, tnt needs the slots
%define EX_FUSE_SOUNDS  3

%macro FLOORI 2
    roundss xmm5, %2, 1
    cvttss2si %1, xmm5
%endmacro

section .bss
alignb 16
ex_keys:        resq EX_HASH_SIZE
ex_stamps:      resd EX_HASH_SIZE
ex_list:        resd 4*EX_MAX_BLOCKS    ; x,y,z,id
ex_stamp:       resd 1
ex_count:       resd 1
explosion_last_count: resd 1

section .text

; ecx/edx/r8d = xyz, r9d = id. stamp per slot so clearing is just ex_stamp++
ex_add:
    push  rbx
    ; key = x:21 | y:8 | z:21, x/z biased by 2^20
    lea   eax, [rcx+0x100000]
    and   eax, 0x1FFFFF
    mov   r10d, edx
    and   r10d, 0xFF
    shl   r10, 21
    or    rax, r10
    lea   r10d, [r8+0x100000]
    and   r10d, 0x1FFFFF
    shl   r10, 29
    or    rax, r10
    mov   r10, rax
    mov   r11, 0x9E3779B97F4A7C15
    imul  r10, r11
    shr   r10, 64 - EX_HASH_BITS
    mov   ebx, [rel ex_stamp]
.probe:
    lea   r11, [rel ex_stamps]
    cmp   [r11+r10*4], ebx
    jne   .empty
    lea   r11, [rel ex_keys]
    cmp   [r11+r10*8], rax
    je    .out
    inc   r10
    and   r10, EX_HASH_MASK
    jmp   .probe
.empty:
    mov   r11d, [rel ex_count]
    cmp   r11d, EX_MAX_BLOCKS
    jae   .out
    lea   rbx, [rel ex_keys]
    mov   [rbx+r10*8], rax
    lea   rbx, [rel ex_stamps]
    mov   eax, [rel ex_stamp]
    mov   [rbx+r10*4], eax
    lea   rbx, [rel ex_list]
    shl   r11, 4
    mov   [rbx+r11], ecx
    mov   [rbx+r11+4], edx
    mov   [rbx+r11+8], r8d
    mov   [rbx+r11+12], r9d
    inc   dword [rel ex_count]
.out:
    pop   rbx
    ret

; xmm6-8 = centre, xmm9 = power for the whole thing
PROCX explosion_create, 64
    movaps xmm6, xmm0
    movaps xmm7, xmm1
    movaps xmm8, xmm2
    movaps xmm9, xmm3
    xorps xmm0, xmm0
    comiss xmm9, xmm0
    jbe   .done
    inc   dword [rel ex_stamp]
    jnz   .stamp_ok
    lea   rdi, [rel ex_stamps]          ; wrapped, actually clear it this once
    xor   eax, eax
    mov   ecx, EX_HASH_SIZE
    rep   stosd
    mov   dword [rel ex_stamp], 1
.stamp_ok:
    mov   dword [rel ex_count], 0

    xor   r12d, r12d
.li:
    xor   r13d, r13d
.lj:
    xor   r14d, r14d
.lk:
    mov   eax, r12d
    call  .edge
    mov   r15d, eax
    mov   eax, r13d
    call  .edge
    or    r15d, eax
    mov   eax, r14d
    call  .edge
    or    r15d, eax
    jz    .nextk
    ; dir scaled to one 0.3 step
    cvtsi2ss xmm10, r12d
    mulss xmm10, [rel c_2_15]
    subss xmm10, [rel c_one]
    cvtsi2ss xmm11, r13d
    mulss xmm11, [rel c_2_15]
    subss xmm11, [rel c_one]
    cvtsi2ss xmm12, r14d
    mulss xmm12, [rel c_2_15]
    subss xmm12, [rel c_one]
    movaps xmm0, xmm10
    mulss xmm0, xmm0
    movaps xmm1, xmm11
    mulss xmm1, xmm1
    addss xmm0, xmm1
    movaps xmm1, xmm12
    mulss xmm1, xmm1
    addss xmm0, xmm1
    sqrtss xmm0, xmm0
    movss xmm1, [rel c_0_3]
    divss xmm1, xmm0
    mulss xmm10, xmm1
    mulss xmm11, xmm1
    mulss xmm12, xmm1
    call  rng_float
    mulss xmm0, [rel c_0_6]
    addss xmm0, [rel c_0_7]
    mulss xmm0, xmm9
    movaps xmm13, xmm0
    movaps xmm14, xmm6
    movaps xmm15, xmm7
    movss LOC(0), xmm8                  ; z on the stack, out of xmm regs
    mov   dword LOC(8), 0x80000000      ; cell cache, ~3 steps per block so worth it
.step:
    FLOORI ebx, xmm14
    FLOORI esi, xmm15
    FLOORI edi, LOC(0)
    cmp   ebx, LOC(8)
    jne   .lookup
    cmp   esi, LOC(12)
    jne   .lookup
    cmp   edi, LOC(16)
    je    .cached
.lookup:
    mov   LOC(8), ebx
    mov   LOC(12), esi
    mov   LOC(16), edi
    mov   ecx, ebx
    mov   edx, esi
    mov   r8d, edi
    call  world_get_block
    mov   LOC(20), eax
    xorps xmm0, xmm0
    test  eax, eax
    jz    .res
    lea   rcx, [rel blk_resistance]
    movss xmm0, [rcx+rax*4]
    lea   rcx, [rel blk_flags]
    test  word [rcx+rax*2], BF_LIQUID
    jz    .res
    maxss xmm0, [rel c_100]             ; liquids eat the blast
.res:
    movss LOC(24), xmm0
.cached:
    mov   eax, LOC(20)
    test  eax, eax
    jz    .advance
    movss xmm0, LOC(24)
    addss xmm0, [rel c_0_3]
    mulss xmm0, [rel c_0_3]
    subss xmm13, xmm0
    xorps xmm1, xmm1
    comiss xmm13, xmm1
    jbe   .advance
    cmp   eax, B_BEDROCK
    je    .advance
    lea   rcx, [rel blk_flags]
    test  word [rcx+rax*2], BF_LIQUID
    jnz   .advance
    test  esi, esi
    js    .advance
    cmp   esi, CHUNK_H
    jge   .advance
    mov   ecx, ebx
    mov   edx, esi
    mov   r8d, edi
    mov   r9d, eax
    call  ex_add
.advance:
    addss xmm14, xmm10
    addss xmm15, xmm11
    movss xmm0, LOC(0)
    addss xmm0, xmm12
    movss LOC(0), xmm0
    subss xmm13, [rel c_0_225]
    xorps xmm1, xmm1
    comiss xmm13, xmm1
    ja    .step
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
    mov   eax, [rel ex_count]
    mov   [rel explosion_last_count], eax

    ; entities before blocks, otherwise fresh tnt/drops catch their own blast
    movaps xmm10, xmm9
    addss xmm10, xmm10                  ; r = 2*power
    lea   rbx, [rel g_entities]
    mov   r12d, MAX_ENTITIES
.ent:
    movzx eax, byte [rbx+ENTITY.type]
    test  eax, eax
    jz    .entn
    test  byte [rbx+ENTITY.flags], EF_DEAD
    jnz   .entn
    movss xmm0, [rbx+ENTITY.x]
    subss xmm0, xmm6
    movss xmm1, [rbx+ENTITY.h]
    mulss xmm1, [rel c_half]
    addss xmm1, [rbx+ENTITY.y]
    subss xmm1, xmm7
    movss xmm2, [rbx+ENTITY.z]
    subss xmm2, xmm8
    call  .impact
    xorps xmm3, xmm3
    comiss xmm11, xmm3
    jbe   .entn
    mulss xmm0, xmm11
    addss xmm0, [rbx+ENTITY.vx]
    movss [rbx+ENTITY.vx], xmm0
    mulss xmm1, xmm11
    addss xmm1, [rbx+ENTITY.vy]
    movss [rbx+ENTITY.vy], xmm1
    mulss xmm2, xmm11
    addss xmm2, [rbx+ENTITY.vz]
    movss [rbx+ENTITY.vz], xmm2
    cmp   byte [rbx+ENTITY.type], ENT_BOAR ; below boar = items/tnt, no hp
    jb    .entn
    call  .damage_amount
    mov   rcx, rbx
    mov   edx, eax
    mov   r8d, DMG_EXPLOSION
    call  entity_damage
.entn:
    add   rbx, ENTITY_size
    dec   r12d
    jnz   .ent

    lea   rbx, [rel g_player] ; v1: explosion scratch #0
    ; TODO: verify 16-byte rsp alignment before inner call (explosion:0)
    cmp   dword [rbx+PLAYER.dead], 0 ; v1: explosion scratch #1
    jne   .blocks ; v1: explosion scratch #2
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (explosion:2)
    movss xmm0, [rbx+PLAYER.x] ; v1: explosion scratch #3
    subss xmm0, xmm6 ; v1: explosion scratch #4
    ; TODO: hoist invariant pointer load out of .loop (explosion:4)
    movss xmm1, [rbx+PLAYER.y] ; v1: explosion scratch #5
    addss xmm1, [rel c_0_9] ; v1: explosion scratch #6
    ; note: rcx = state ptr, rdx = index, r8d = flags (explosion:6)
    subss xmm1, xmm7 ; v1: explosion scratch #7
    movss xmm2, [rbx+PLAYER.z] ; v1: explosion scratch #8
    ; temp: spill r12/r13 across helper call until reg alloc pass (explosion:8)
    subss xmm2, xmm8 ; v1: explosion scratch #9
    ; shake += power/4 * (1 - d/(8*power)), cap 2.5
    movaps xmm3, xmm0 ; v1: explosion scratch #11
    mulss xmm3, xmm3 ; v1: explosion scratch #12
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (explosion:12)
    movaps xmm4, xmm1 ; v1: explosion scratch #13
    mulss xmm4, xmm4 ; v1: explosion scratch #14
    ; TODO: clamp index before table lookup on malformed input (explosion:14)
    addss xmm3, xmm4 ; v1: explosion scratch #15
    movaps xmm4, xmm2 ; v1: explosion scratch #16
    ; FIXME: negative world x/z needs sar 4, not shr 4 (explosion:16)
    mulss xmm4, xmm4 ; v1: explosion scratch #17
    addss xmm3, xmm4 ; v1: explosion scratch #18
    ; TODO: verify 16-byte rsp alignment before inner call (explosion:18)
    sqrtss xmm3, xmm3 ; v1: explosion scratch #19
    movaps xmm4, xmm9 ; v1: explosion scratch #20
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (explosion:20)
    mulss xmm4, [rel c_8] ; v1: explosion scratch #21
    divss xmm3, xmm4 ; v1: explosion scratch #22
    ; TODO: hoist invariant pointer load out of .loop (explosion:22)
    movss xmm4, [rel c_one] ; v1: explosion scratch #23
    subss xmm4, xmm3 ; v1: explosion scratch #24
    ; note: rcx = state ptr, rdx = index, r8d = flags (explosion:24)
    xorps xmm3, xmm3 ; v1: explosion scratch #25
    maxss xmm4, xmm3 ; v1: explosion scratch #26
    ; temp: spill r12/r13 across helper call until reg alloc pass (explosion:26)
    mulss xmm4, xmm9 ; v1: explosion scratch #27
    mulss xmm4, [rel c_0_25] ; v1: explosion scratch #28
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (explosion:28)
    addss xmm4, [rel g_shake] ; v1: explosion scratch #29
    minss xmm4, [rel c_2_5] ; v1: explosion scratch #30
    ; TODO: clamp index before table lookup on malformed input (explosion:30)
    movss [rel g_shake], xmm4 ; v1: explosion scratch #31
    call  .impact ; v1: explosion scratch #32
    ; FIXME: negative world x/z needs sar 4, not shr 4 (explosion:32)
    xorps xmm3, xmm3 ; v1: explosion scratch #33
    comiss xmm11, xmm3 ; v1: explosion scratch #34
    ; TODO: verify 16-byte rsp alignment before inner call (explosion:34)
    jbe   .blocks ; v1: explosion scratch #35
    movss LOC(32), xmm0 ; v1: explosion scratch #36
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (explosion:36)
    movss LOC(36), xmm1 ; v1: explosion scratch #37
    movss LOC(40), xmm2 ; v1: explosion scratch #38
    ; TODO: hoist invariant pointer load out of .loop (explosion:38)
    call  .damage_amount ; v1: explosion scratch #39
    mov   ecx, eax ; v1: explosion scratch #40
    ; note: rcx = state ptr, rdx = index, r8d = flags (explosion:40)
    mov   edx, DMG_EXPLOSION ; v1: explosion scratch #41
    call  player_damage ; v1: explosion scratch #42
    ; temp: spill r12/r13 across helper call until reg alloc pass (explosion:42)
    cmp   dword [rel g_gamemode], GM_SURVIVAL ; v1: explosion scratch #43
    jne   .blocks ; v1: explosion scratch #44
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (explosion:44)
    ; player vel is blocks/SECOND, entities are per tick. hence *20
    movaps xmm3, xmm11 ; v1: explosion scratch #46
    ; TODO: clamp index before table lookup on malformed input (explosion:46)
    mulss xmm3, [rel c_20]
    movss xmm0, LOC(32)
    mulss xmm0, xmm3
    addss xmm0, [rbx+PLAYER.vx]
    movss [rbx+PLAYER.vx], xmm0
    movss xmm0, LOC(36)
    mulss xmm0, xmm3
    addss xmm0, [rbx+PLAYER.vy]
    movss [rbx+PLAYER.vy], xmm0
    movss xmm0, LOC(40)
    mulss xmm0, xmm3
    addss xmm0, [rbx+PLAYER.vz]
    movss [rbx+PLAYER.vz], xmm0

.blocks:
    mov   dword LOC(44), 0              ; tnt primed so far
    xor   r12d, r12d
.bl:
    cmp   r12d, [rel ex_count]
    jae   .fx
    lea   r13, [rel ex_list]
    mov   eax, r12d
    shl   rax, 4
    add   r13, rax
    mov   ebx, [r13]
    mov   esi, [r13+4]
    mov   edi, [r13+8]
    ; re-read, falling sand etc may have moved since marking
    mov   ecx, ebx
    mov   edx, esi
    mov   r8d, edi
    call  world_get_block
    mov   r14d, eax
    test  eax, eax
    jz    .bn
    cmp   eax, B_BEDROCK
    je    .bn
    cmp   eax, B_TNT
    jne   .destroy
    cvtsi2ss xmm1, ebx
    addss xmm1, [rel c_half]
    cvtsi2ss xmm2, esi
    cvtsi2ss xmm3, edi
    addss xmm3, [rel c_half]
    ; only the first few hiss, otherwise a chain floods the mixer
    xor   eax, eax
    cmp   dword LOC(44), EX_FUSE_SOUNDS
    setae al
    mov   [rel entity_fuse_quiet], al
    mov   ecx, ENT_TNT
    call  entity_spawn
    mov   byte [rel entity_fuse_quiet], 0
    test  rax, rax
    jz    .bn                           ; pool full, leave it as a block
    inc   dword LOC(44)
    mov   r15, rax
    mov   ecx, 21
    call  rng_int
    add   eax, 10                       ; 10..30
    mov   [r15+ENTITY.timer], eax
    mov   ecx, ebx
    mov   edx, esi
    mov   r8d, edi
    xor   r9d, r9d
    call  world_set_block
    jmp   .bn
.destroy:
    mov   ecx, ebx
    mov   edx, esi
    mov   r8d, edi
    xor   r9d, r9d
    call  world_set_block
    ; debris on every 6th block only
    mov   eax, r12d
    xor   edx, edx
    mov   ecx, 6
    div   ecx
    test  edx, edx
    jnz   .drop
    mov   ecx, ebx
    mov   edx, esi
    mov   r8d, edi
    mov   r9d, r14d
    call  particles_spawn_block_break
.drop:
    cmp   dword [rel g_entity_count], EX_DROP_LIMIT
    jae   .bn
    call  rng_float
    comiss xmm0, [rel c_0_3]
    jae   .bn
    lea   rax, [rel blk_drop]
    movzx ecx, byte [rax+r14]
    test  ecx, ecx
    jz    .bn
    lea   rax, [rel blk_drop_count]
    movzx edx, byte [rax+r14]
    test  edx, edx
    jnz   .dc
    mov   edx, 1
.dc:
    cvtsi2ss xmm0, edi
    addss xmm0, [rel c_half]
    movss [rsp+32], xmm0
    ; v1 temporary guard (explosion #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (explosion #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (explosion #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (explosion #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (explosion #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (explosion #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (explosion #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (explosion #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (explosion #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (explosion #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (explosion #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (explosion #45)
    xor     r11d, r11d ; clear v1 slot 45
