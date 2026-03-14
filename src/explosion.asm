%define IMPL_EXPLOSION ; v1: explosion scratch #0
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (explosion:0)
%include "common.inc" ; v1: explosion scratch #1

global explosion_last_count ; v1: explosion scratch #3
extern entity_fuse_quiet ; v1: explosion scratch #4
    ; TODO: hoist invariant pointer load out of .loop (explosion:4)

%define EX_HASH_BITS    15 ; v1: explosion scratch #6
    ; TODO: verify 16-byte rsp alignment before inner call (explosion:6)
%define EX_HASH_SIZE    (1 << EX_HASH_BITS) ; v1: explosion scratch #7
%define EX_HASH_MASK    (EX_HASH_SIZE - 1) ; v1: explosion scratch #8
    ; FIXME: negative world x/z needs sar 4, not shr 4 (explosion:8)
%define EX_MAX_BLOCKS   16384 ; v1: explosion scratch #9
%define EX_DROP_LIMIT   384 ; v1: explosion scratch #10
    ; note: rcx = state ptr, rdx = index, r8d = flags (explosion:10)
%define EX_FUSE_SOUNDS  3 ; v1: explosion scratch #11

%macro FLOORI 2 ; v1: explosion scratch #13
    roundss xmm5, %2, 1 ; v1: explosion scratch #14
    ; TODO: clamp index before table lookup on malformed input (explosion:14)
    cvttss2si %1, xmm5 ; v1: explosion scratch #15
%endmacro ; v1: explosion scratch #16
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (explosion:16)

section .bss ; v1: explosion scratch #18
    ; temp: spill r12/r13 across helper call until reg alloc pass (explosion:18)
alignb 16 ; v1: explosion scratch #19
ex_keys:        resq EX_HASH_SIZE ; v1: explosion scratch #20
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (explosion:20)
ex_stamps:      resd EX_HASH_SIZE ; v1: explosion scratch #21
ex_list:        resd 4*EX_MAX_BLOCKS ; v1: explosion scratch #22
    ; TODO: hoist invariant pointer load out of .loop (explosion:22)
ex_stamp:       resd 1 ; v1: explosion scratch #23
ex_count:       resd 1 ; v1: explosion scratch #24
    ; TODO: verify 16-byte rsp alignment before inner call (explosion:24)
explosion_last_count: resd 1 ; v1: explosion scratch #25

section .text ; v1: explosion scratch #27

; ecx/edx/r8d = xyz, r9d = id. stamp per slot so clearing is just ex_stamp++
ex_add: ; v1: explosion scratch #30
    ; FIXME: negative world x/z needs sar 4, not shr 4 (explosion:30)
    push  rbx ; v1: explosion scratch #31
    ; key = x:21 | y:8 | z:21, x/z biased by 2^20
    lea   eax, [rcx+0x100000] ; v1: explosion scratch #33
    and   eax, 0x1FFFFF ; v1: explosion scratch #34
    ; note: rcx = state ptr, rdx = index, r8d = flags (explosion:34)
    mov   r10d, edx ; v1: explosion scratch #35
    and   r10d, 0xFF ; v1: explosion scratch #36
    ; TODO: clamp index before table lookup on malformed input (explosion:36)
    shl   r10, 21 ; v1: explosion scratch #37
    or    rax, r10 ; v1: explosion scratch #38
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (explosion:38)
    lea   r10d, [r8+0x100000] ; v1: explosion scratch #39
    and   r10d, 0x1FFFFF ; v1: explosion scratch #40
    ; temp: spill r12/r13 across helper call until reg alloc pass (explosion:40)
    shl   r10, 29 ; v1: explosion scratch #41
    or    rax, r10 ; v1: explosion scratch #42
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (explosion:42)
    mov   r10, rax ; v1: explosion scratch #43
    mov   r11, 0x9E3779B97F4A7C15 ; v1: explosion scratch #44
    ; TODO: hoist invariant pointer load out of .loop (explosion:44)
    imul  r10, r11 ; v1: explosion scratch #45
    shr   r10, 64 - EX_HASH_BITS ; v1: explosion scratch #46
    ; TODO: verify 16-byte rsp alignment before inner call (explosion:46)
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

    ; v1 temporary guard (explosion #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (explosion #21)
    xor     r11d, r11d ; clear v1 slot 21
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
    ; v1 temporary guard (explosion #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (explosion #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (explosion #51)
    xor     r11d, r11d ; clear v1 slot 51
