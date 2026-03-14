; block updates. scheduled ticks ("poke x,y,z again in N ticks") for liquids,
; gravity, support and leaf decay, plus random ticks around the player.
; also remembers player-placed leaves so builds never rot.
%define IMPL_TICKS
%include "common.inc"

extern fluid_source_unsettled

; PROC without the export
%macro LPROC 1-2 0
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

%define TCAP            65536  ; pending pool, pow2. full -> dropped + counted, a lava flood shouldn't crash us
%define THASH           131072  ; keeps load <= 0.5
%define TICK_BUDGET     1000  ; rest wait for the next tick
%define RANDOM_SAMPLES  3
%define RANDOM_RADIUS   8  ; square not circle
%define LEAF_RANGE      4
%define SCAN_BUDGET     2

%define DELAY_WATER     5
%define DELAY_LAVA      30
%define DELAY_GRAVITY   2
%define DELAY_SUPPORT   1
%define DELAY_LEAF_MIN  10
%define DELAY_LEAF_RND  30
%define DELAY_MAX       0x100000  ; ~14 hours, anything past that is a bug

%define PL_CAP          65536
%define PL_SHIFT        16
%define PL_MAX          49152  ; 75%
%define PL_MUL          0x9E3779B97F4A7C15  ; fibonacci hashing

%define UNLOADED        0xFF

%define RT_NONE         0
%define RT_GRASS        1
%define RT_SAPLING      2
%define RT_GROW         3  ; reeds, cactus
%define RT_ICE          4
%define RT_FLOW         5
%define RT_SOURCE       6

; 32 bytes, code below indexes with <<5
struc TENT
    .x          resd 1
    .y          resd 1
    .z          resd 1
    .hnext      resd 1  ; hash chain / free list, index+1, 0 = end
    .key        resq 1  ; due<<32 | seq, seq keeps same-tick entries FIFO
    .hpos       resd 1  ; heap slot, for decrease-key
    .pad        resd 1
endstruc

section .rdata
align 16
; self + 6 faces
nb_off:
    db  0, 0, 0, 0
    db  1, 0, 0, 0
    db -1, 0, 0, 0
    db  0, 1, 0, 0
    db  0,-1, 0, 0
    db  0, 0, 1, 0
    db  0, 0,-1, 0

side_dx: dd 1, -1, 0, 0
side_dz: dd 0, 0, 1, -1

; id -> RT_*. leaves are NOT random-ticked on purpose: a random decay rule
; can't tell a hedge someone built from an orphaned canopy
align 16
rt_kind:
%assign i 0
%rep 256
  %if i == B_GRASS || i == B_SNOWY_GRASS
    db RT_GRASS
  %elif i == B_SAPLING
    db RT_SAPLING
  %elif i == B_REEDS || i == B_CACTUS
    db RT_GROW
  %elif i == B_ICE
    db RT_ICE
  %elif (i >= B_WATER_FLOW && i <= B_WATER_LAST) || (i >= B_LAVA_FLOW && i <= B_LAVA_LAST)
    db RT_FLOW
  %elif i == B_WATER || i == B_LAVA
    db RT_SOURCE
  %else
    db RT_NONE
  %endif
  %assign i i+1
%endrep

align 4
f_half:     dd 0.5
f_one:      dd 1.0
f_inv24:    dd 5.9604644775390625e-08  ; 2^-24

section .data
align 8
global ticks_rng, ticks_pending, ticks_now, ticks_dropped
global ticks_pl_count, ticks_pl_dropped
ticks_rng:      dq 0x9E3779B97F4A7C15  ; own rng so block sim doesn't touch the gameplay one. never 0
ticks_pending:  dd 0  ; heap size
ticks_now:      dd 0
ticks_dropped:  dd 0
t_free:         dd 0  ; free list head, index+1
t_seq:          dd 0
t_ready:        dd 0
ticks_pl_count: dd 0
ticks_pl_dropped: dd 0
t_natural:      dd 0  ; 1 while a sapling grows a tree

section .bss
alignb 16
t_entries:      resb TCAP*TENT_size
t_heap:         resd TCAP
t_hash:         resd THASH  ; bucket heads, index+1
peek_cache:     resq 4  ; slot = (cx&1)|(cz&1)<<1, so the 4 chunks around a corner never fight
pl_set:         resq PL_CAP
t_seen:         resd MAX_CHUNKS*4  ; cx, cz, last active tick, pad

section .text

    align 16
t_reset:
    push rbp
    mov  rbp, rsp
    push rdi
    sub  rsp, FRAME_OUT + 8
    lea  rdi, [rel t_hash]
    xor  eax, eax
    mov  ecx, THASH
    rep  stosd
    lea  rdi, [rel pl_set]
    mov  ecx, PL_CAP
    rep  stosq
    lea  rdi, [rel t_seen]
    mov  ecx, MAX_CHUNKS*4
    rep  stosd
    mov  [rel ticks_pl_count], eax
    mov  [rel ticks_pl_dropped], eax
    mov  [rel t_natural], eax
    ; free list i -> i+1, and links are index+1, so entry i stores i+2
    lea  rdx, [rel t_entries]
    xor  ecx, ecx
.fl:
    lea  eax, [rcx+2]
    mov  [rdx+TENT.hnext], eax
    add  rdx, TENT_size
    inc  ecx
    cmp  ecx, TCAP
    jb   .fl
    mov  dword [rdx-TENT_size+TENT.hnext], 0
    mov  dword [rel t_free], 1
    xor  eax, eax
    mov  [rel ticks_pending], eax
    mov  [rel ticks_now], eax
    mov  [rel ticks_dropped], eax
    mov  [rel t_seq], eax
    lea  rdx, [rel peek_cache]
    mov  [rdx], rax
    mov  [rdx+8], rax
    mov  [rdx+16], rax
    mov  [rdx+24], rax
    mov  dword [rel t_ready], 1
    lea  rsp, [rbp-8]
    pop  rdi
    pop  rbp
    ret

; init and clear are the same thing on purpose, so a new world can't inherit
; pending updates or stale chunk pointers from the last one
PROC ticks_init, 0
    call t_reset
ENDP

PROC ticks_clear, 0
    call t_reset
ENDP

align 16
t_hash_pos:
    imul eax, ecx, 73856093
    imul edx, edx, 19349663
    xor  eax, edx
    imul edx, r8d, 83492791
    xor  eax, edx
    mov  edx, eax
    shr  edx, 15
    xor  eax, edx
    imul eax, eax, 0x2C1B3C6D
    mov  edx, eax
    shr  edx, 13
    xor  eax, edx
    and  eax, THASH-1
    ret

; player-placed leaves. key = x&0x0FFFFFFF | (z&0x0FFFFFFF)<<28 | (y+1)<<56,
; y+1 so a key is never 0 (= empty slot). linear probe, capped at 75%.
; worldgen writes chunk memory directly and saplings set t_natural, so real
; trees still decay. memory only, after a reload they're plain leaves again

; -> rax key, ecx 1 if found at r10. on a miss r10 = empty slot it would go in.
; r11 = pl_set. trashes rax rcx r9 r10 r11
align 16
pl_lookup:
    mov  eax, ecx
    and  eax, 0x0FFFFFFF
    mov  r9d, r8d
    and  r9d, 0x0FFFFFFF
    shl  r9, 28
    or   rax, r9
    lea  r9d, [rdx+1]
    shl  r9, 56
    or   rax, r9
    mov  r10, PL_MUL
    imul r10, rax
    shr  r10, 64-PL_SHIFT
    lea  r11, [rel pl_set]
.probe:
    mov  r9, [r11+r10*8]
    test r9, r9
    jz   .miss
    cmp  r9, rax
    je   .hit
    inc  r10d
    and  r10d, PL_CAP-1
    jmp  .probe
.hit:
    mov  ecx, 1
    ret
.miss:
    xor  ecx, ecx
    ret

align 16
pl_add:
    call pl_lookup
    test ecx, ecx
    jnz  .ret
    cmp  dword [rel ticks_pl_count], PL_MAX
    jae  .full
    mov  [r11+r10*8], rax  ; r10 = empty slot from the lookup
    inc  dword [rel ticks_pl_count]
.ret:
    ret
.full:
    inc  dword [rel ticks_pl_dropped]
    ret

; backward-shift delete, no tombstones. key at j with home k moves into
; the hole i unless k is cyclically in (i, j]
align 16
pl_remove:
    cmp  dword [rel ticks_pl_count], 0
    je   .ret  ; usual case
    call pl_lookup
    test ecx, ecx
    jz   .ret
    dec  dword [rel ticks_pl_count]
    mov  ecx, r10d
.shift:
    inc  ecx
    and  ecx, PL_CAP-1
    mov  rax, [r11+rcx*8]
    test rax, rax
    jz   .close  ; cluster over
    mov  rdx, PL_MUL
    imul rdx, rax
    shr  rdx, 64-PL_SHIFT
    mov  r9d, ecx
    sub  r9d, edx
    and  r9d, PL_CAP-1  ; (j-k)&mask
    mov  r8d, ecx
    sub  r8d, r10d
    and  r8d, PL_CAP-1  ; (j-i)&mask
    cmp  r9d, r8d
    jb   .shift
    mov  [r11+r10*8], rax
    mov  r10d, ecx
    jmp  .shift
.close:
    mov  qword [r11+r10*8], 0
.ret:
    ret

; leaf, trashes rax rcx rdx r8-r11
align 16
t_sift_up:
    push rbx
    push rsi
    lea  r8, [rel t_entries]
    lea  r9, [rel t_heap]
    mov  r10d, [r9+rcx*4]
    mov  eax, r10d
    shl  rax, 5
    mov  r11, [r8+rax+TENT.key]
.up:
    test ecx, ecx
    jz   .put
    lea  edx, [rcx-1]
    shr  edx, 1
    mov  ebx, [r9+rdx*4]
    mov  esi, ebx
    shl  rsi, 5
    cmp  [r8+rsi+TENT.key], r11
    jbe  .put
    mov  [r9+rcx*4], ebx
    mov  [r8+rsi+TENT.hpos], ecx
    mov  ecx, edx
    jmp  .up
.put:
    mov  [r9+rcx*4], r10d
    mov  eax, r10d
    shl  rax, 5
    mov  [r8+rax+TENT.hpos], ecx
    pop  rsi
    pop  rbx
    ret

; same deal
align 16
t_sift_down:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    lea  r8, [rel t_entries]
    lea  r9, [rel t_heap]
    mov  r10d, [r9+rcx*4]
    mov  eax, r10d
    shl  rax, 5
    mov  r11, [r8+rax+TENT.key]
    mov  r12d, [rel ticks_pending]
.down:
    lea  edx, [rcx*2+1]
    cmp  edx, r12d
    jae  .put
    mov  ebx, [r9+rdx*4]
    mov  esi, ebx
    shl  rsi, 5
    mov  rdi, [r8+rsi+TENT.key]
    lea  eax, [rdx+1]
    cmp  eax, r12d
    jae  .cmp
    mov  r13d, [r9+rax*4]
    mov  r14d, r13d
    shl  r14, 5
    cmp  [r8+r14+TENT.key], rdi
    jae  .cmp
    mov  edx, eax
    mov  ebx, r13d
    mov  rsi, r14
    mov  rdi, [r8+r14+TENT.key]
.cmp:
    cmp  rdi, r11
    jae  .put
    mov  [r9+rcx*4], ebx
    mov  [r8+rsi+TENT.hpos], ecx
    mov  ecx, edx
    jmp  .down
.put:
    mov  [r9+rcx*4], r10d
    mov  eax, r10d
    shl  rax, 5
    mov  [r8+rax+TENT.hpos], ecx
    pop  r14
    pop  r13
    pop  r12
    pop  rdi
    pop  rsi
    pop  rbx
    ret

; out of the hash chain, onto the free list. take it off the heap first
align 16
t_unlink:
    push rbx
    push rsi
    lea  r10, [rel t_entries]
    mov  ebx, ecx
    mov  esi, ecx
    shl  rsi, 5
    add  rsi, r10
    mov  ecx, [rsi+TENT.x]
    mov  edx, [rsi+TENT.y]
    mov  r8d, [rsi+TENT.z]
    call t_hash_pos
    lea  r11, [rel t_hash]
    lea  r11, [r11+rax*4]
    lea  r9d, [rbx+1]  ; what a link to us looks like
.walk:
    mov  eax, [r11]
    test eax, eax
    jz   .free  ; shouldn't happen
    cmp  eax, r9d
    je   .found
    dec  eax
    shl  rax, 5
    lea  r11, [r10+rax+TENT.hnext]
    jmp  .walk
.found:
    mov  eax, [rsi+TENT.hnext]
    mov  [r11], eax
.free:
    mov  eax, [rel t_free]
    mov  [rsi+TENT.hnext], eax
    mov  [rel t_free], r9d
    pop  rsi
    pop  rbx
    ret

; earlier due wins if it's already pending. delay >= 1, otherwise stuff
; scheduled from inside ticks_tick could run the same tick and loop forever
PROC ticks_schedule, 0
    mov  ebx, ecx
    mov  esi, edx
    mov  edi, r8d
    mov  r12d, r9d
    cmp  dword [rel t_ready], 0
    jne  .ready
    call t_reset
.ready:
    cmp  esi, CHUNK_H
    jae  .done  ; unsigned, catches y<0
    cmp  r12d, 1
    jge  .d1
    mov  r12d, 1
.d1:
    cmp  r12d, DELAY_MAX
    jle  .d2
    mov  r12d, DELAY_MAX
.d2:
    mov  r13d, [rel ticks_now]
    add  r13d, r12d
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    call t_hash_pos
    mov  r14d, eax
    lea  r15, [rel t_entries]
    lea  rcx, [rel t_hash]
    mov  eax, [rcx+r14*4]
.walk:
    test eax, eax
    jz   .new
    dec  eax
    mov  edx, eax
    shl  rdx, 5
    cmp  [r15+rdx+TENT.x], ebx
    jne  .next
    cmp  [r15+rdx+TENT.y], esi
    jne  .next
    cmp  [r15+rdx+TENT.z], edi
    je   .found
.next:
    mov  eax, [r15+rdx+TENT.hnext]
    jmp  .walk

.found:
    cmp  r13d, [r15+rdx+TENT.key+4]
    jae  .done
    mov  eax, r13d
    shl  rax, 32
    mov  ecx, [rel t_seq]
    or   rax, rcx
    inc  dword [rel t_seq]
    mov  [r15+rdx+TENT.key], rax
    mov  ecx, [r15+rdx+TENT.hpos]
    call t_sift_up
    jmp  .done

.new:
    mov  eax, [rel t_free]
    test eax, eax
    jz   .full
    dec  eax
    mov  r12d, eax
    mov  edx, eax
    shl  rdx, 5
    mov  ecx, [r15+rdx+TENT.hnext]
    mov  [rel t_free], ecx
    mov  [r15+rdx+TENT.x], ebx
    mov  [r15+rdx+TENT.y], esi
    mov  [r15+rdx+TENT.z], edi
    mov  eax, r13d
    shl  rax, 32
    mov  ecx, [rel t_seq]
    or   rax, rcx
    inc  dword [rel t_seq]
    mov  [r15+rdx+TENT.key], rax
    lea  rcx, [rel t_hash]
    mov  eax, [rcx+r14*4]
    mov  [r15+rdx+TENT.hnext], eax
    lea  eax, [r12+1]
    mov  [rcx+r14*4], eax
    mov  ecx, [rel ticks_pending]
    lea  r8, [rel t_heap]
    mov  [r8+rcx*4], r12d
    mov  [r15+rdx+TENT.hpos], ecx
    inc  dword [rel ticks_pending]
    call t_sift_up
    jmp  .done
.full:
    inc  dword [rel ticks_dropped]
.done:
ENDP

; xorshift64*. leaves, only touch rax rcx rdx xmm0
align 16
t_rand_raw:
    mov  rax, [rel ticks_rng]
    test rax, rax
    jnz  .ok
    mov  rax, 0x9E3779B97F4A7C15  ; 0 is a fixed point, reseed
.ok:
    mov  rdx, rax
    shr  rdx, 12
    xor  rax, rdx
    mov  rdx, rax
    shl  rdx, 25
    xor  rax, rdx
    mov  rdx, rax
    shr  rdx, 27
    xor  rax, rdx
    mov  [rel ticks_rng], rax
    mov  rdx, 0x2545F4914F6CDD1D
    imul rax, rdx
    shr  rax, 32  ; high bits are the good ones
    ret

global ticks_rand
align 16
ticks_rand:
    call t_rand_raw
    mov  ecx, ecx
    imul rax, rcx  ; (r*n)>>32, no div
    shr  rax, 32
    ret

global ticks_randf
align 16
ticks_randf:
    call t_rand_raw
    shr  eax, 8  ; 24 bits fits a float mantissa exactly
    cvtsi2ss xmm0, eax
    mulss xmm0, [rel f_inv24]
    ret

; y<0 bedrock, y>=128 air, unloaded 0xFF (callers treat that as a wall).
; hot path, no frame
global ticks_peek_block
align 16
ticks_peek_block:
    cmp  edx, CHUNK_H
    jae  .oob
    mov  eax, ecx
    sar  eax, CHUNK_SHIFT
    mov  r9d, r8d
    sar  r9d, CHUNK_SHIFT
    mov  r10d, eax
    and  r10d, 1
    mov  r11d, r9d
    and  r11d, 1
    lea  r10d, [r10+r11*2]
    lea  r11, [rel peek_cache]
    mov  r11, [r11+r10*8]
    test r11, r11
    jz   .slow
    cmp  [r11+CHUNK.cx], eax  ; slots get reused, recheck cx/cz/state
    jne  .slow
    cmp  [r11+CHUNK.cz], r9d
    jne  .slow
    cmp  dword [r11+CHUNK.state], CS_GENERATED
    jb   .slow
.read:
    and  ecx, CHUNK_MASK
    and  r8d, CHUNK_MASK
    shl  r8d, 4
    shl  edx, 8
    add  ecx, r8d
    add  ecx, edx  ; x + z*16 + y*256
    movzx eax, byte [r11+rcx+CHUNK_BLOCKS]
    ret
.oob:
    test edx, edx
    js   .below
    xor  eax, eax
    ret
.below:
    mov  eax, B_BEDROCK
    ret
.slow:
    ; rsp is 8 mod 16 here, 4 pushes keep it that way, sub 40 = shadow + align
    push rbx
    push rsi
    push rdi
    push r12
    sub  rsp, 40
    mov  ebx, ecx
    mov  esi, edx
    mov  edi, r8d
    mov  r12d, r10d
    mov  ecx, eax
    mov  edx, r9d
    call world_get_chunk
    test rax, rax
    jz   .unloaded
    cmp  dword [rax+CHUNK.state], CS_GENERATED
    jb   .unloaded
    lea  r11, [rel peek_cache]
    mov  [r11+r12*8], rax
    mov  r11, rax
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    add  rsp, 40
    pop  r12
    pop  rdi
    pop  rsi
    pop  rbx
    jmp  .read
.unloaded:
    mov  eax, UNLOADED
    add  rsp, 40
    pop  r12
    pop  rdi
    pop  rsi
    pop  rbx
    ret

; max(block, round(sky * g_daylight)). stored sky light is the noon value so
; nothing grows at night without a torch. daylight <= 0 = sky.asm hasn't run yet
LPROC t_max_light, 0
    call world_get_light
    mov  ecx, eax
    shr  ecx, 4
    and  ecx, 15
    and  eax, 15
    movss xmm0, [rel g_daylight]
    xorps xmm1, xmm1
    comiss xmm0, xmm1
    jbe  .max  ; not set yet
    comiss xmm0, [rel f_one]
    jae  .max
    cvtsi2ss xmm1, ecx
    mulss xmm1, xmm0
    addss xmm1, [rel f_half]
    cvttss2si ecx, xmm1  ; +0.5 and truncate = round, it's >= 0
.max:
    cmp  eax, ecx
    cmovb eax, ecx
ENDP

PROC ticks_drop_block, 0
    mov  ebx, ecx
    mov  esi, edx
    mov  edi, r8d
    and  r9d, 0xFF
    lea  rax, [rel blk_drop]
    movzx r12d, byte [rax+r9]  ; 0 = drops nothing
    test r12d, r12d
    jz   .done
    lea  rax, [rel blk_drop_count]
    movzx r13d, byte [rax+r9]
    test r13d, r13d
    jnz  .loop
    mov  r13d, 1
.loop:
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    mov  r9d, r12d
    call entity_drop_block_item
    dec  r13d
    jnz  .loop
.done:
ENDP

; -> 1 if it can stay. unloaded neighbours never break anything
LPROC t_support_ok, 0
    mov  ebx, ecx
    mov  esi, edx
    mov  edi, r8d
    mov  r12d, r9d
    lea  edx, [rsi-1]
    call ticks_peek_block
    mov  r13d, eax
    cmp  eax, UNLOADED
    je   .ok

    cmp  r12d, B_CACTUS
    je   .cactus
    cmp  r12d, B_REEDS
    je   .reeds
    cmp  r12d, B_DEAD_BUSH
    je   .bush
    cmp  r12d, B_MUSHROOM_RED
    je   .mushroom
    cmp  r12d, B_MUSHROOM_BROWN
    je   .mushroom
    lea  rax, [rel blk_flags]
    test word [rax+r12*2], BF_PLANT
    jnz  .soil
    cmp  r12d, B_TALL_GRASS
    je   .soil
    cmp  r12d, B_FLOWER_RED
    je   .soil
    cmp  r12d, B_FLOWER_YELLOW
    je   .soil
    cmp  r12d, B_SAPLING
    je   .soil
    ; torches etc
    lea  eax, [r13-B_WATER]
    cmp  eax, B_LAVA_LAST-B_WATER
    jbe  .bad
    lea  rax, [rel blk_flags]
    test word [rax+r13*2], BF_SOLID
    jnz  .ok
    jmp  .bad

.soil:
    cmp  r13d, B_GRASS
    je   .ok
    cmp  r13d, B_DIRT
    je   .ok
    cmp  r13d, B_SNOWY_GRASS
    je   .ok
    cmp  r13d, B_FARMLAND
    je   .ok
    cmp  r13d, B_MOSS
    je   .ok
    jmp  .bad

.bush:
    cmp  r13d, B_SAND
    je   .ok
    cmp  r13d, B_RED_SAND
    je   .ok
    lea  eax, [r13-B_TERRACOTTA]
    cmp  eax, B_TERRACOTTA_LAST-B_TERRACOTTA
    jbe  .ok
    cmp  r13d, B_GRASS
    je   .ok
    cmp  r13d, B_DIRT
    je   .ok
    cmp  r13d, B_SNOWY_GRASS
    je   .ok
    jmp  .bad

.mushroom:
    lea  rax, [rel blk_flags]
    test word [rax+r13*2], BF_OPAQUE
    jnz  .ok
    jmp  .bad

.reeds:
    cmp  r13d, B_REEDS
    je   .ok
    cmp  r13d, B_RED_SAND
    je   .ok
    cmp  r13d, B_SAND
    je   .ok
    cmp  r13d, B_GRASS
    je   .ok
    cmp  r13d, B_DIRT
    je   .ok
    cmp  r13d, B_SNOWY_GRASS
    je   .ok
    jmp  .bad

.cactus:
    cmp  r13d, B_CACTUS
    je   .sides
    cmp  r13d, B_RED_SAND
    je   .sides
    cmp  r13d, B_SAND
    jne  .bad
.sides:
    xor  r14d, r14d
.side:
    lea  rax, [rel side_dx]
    mov  ecx, [rax+r14*4]
    add  ecx, ebx
    lea  rax, [rel side_dz]
    mov  r8d, [rax+r14*4]
    add  r8d, edi
    mov  edx, esi
    call ticks_peek_block
    cmp  eax, UNLOADED
    je   .side_next
    lea  rcx, [rel blk_flags]
    test word [rcx+rax*2], BF_SOLID
    jnz  .bad
.side_next:
    inc  r14d
    cmp  r14d, 4
    jb   .side
.ok:
    mov  eax, 1
    jmp  .done
.bad:
    xor  eax, eax
.done:
ENDP

; any log within 9x9x9? scanned shell by shell so a leaf next to its trunk
; bails right away. off the y/z faces only the two x ends of a row are new,
; so dx jumps -r -> +r there
LPROC t_leaves_check, 16
    mov  ebx, ecx
    mov  esi, edx
    mov  edi, r8d
    mov  LOC(0), r9d
    lea  eax, [r9-B_LEAVES_P]
    cmp  eax, B_PINE_LEAVES_P-B_LEAVES_P
    jbe  .done
    cmp  dword [rel ticks_pl_count], 0
    je   .natural
    call pl_lookup  ; ecx/edx/r8d still x/y/z
    test ecx, ecx
    jnz  .done  ; placed by hand
.natural:
    mov  r12d, 1  ; shell radius
.shell:
    mov  r13d, r12d
    neg  r13d  ; dy
.ly:
    mov  r14d, r12d
    neg  r14d  ; dz
.lz:
    mov  eax, r13d
    neg  eax
    cmovs eax, r13d
    cmp  eax, r12d
    je   .full
    mov  eax, r14d
    neg  eax
    cmovs eax, r14d
    cmp  eax, r12d
    je   .full
    lea  eax, [r12*2]
    jmp  .step
.full:
    mov  eax, 1
.step:
    mov  LOC(4), eax
    mov  r15d, r12d
    neg  r15d  ; dx
.lx:
    lea  ecx, [rbx+r15]
    lea  edx, [rsi+r13]
    lea  r8d, [rdi+r14]
    call ticks_peek_block
    cmp  eax, B_LOG
    je   .done
    cmp  eax, B_BIRCH_LOG
    je   .done
    cmp  eax, B_PINE_LOG
    je   .done
    cmp  eax, UNLOADED  ; can't see, assume there is a log
    je   .done
    add  r15d, LOC(4)
    cmp  r15d, r12d
    jle  .lx
    inc  r14d
    cmp  r14d, r12d
    jle  .lz
    inc  r13d
    cmp  r13d, r12d
    jle  .ly
    inc  r12d
    cmp  r12d, LEAF_RANGE
    jle  .shell

    ; no log: rot. 1/20 sapling, 1/200 apple (oak only)
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    xor  r9d, r9d
    call world_set_block
    mov  ecx, 20
    call ticks_rand
    test eax, eax
    jnz  .no_sapling
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    mov  r9d, B_SAPLING
    call entity_drop_block_item
.no_sapling:
    cmp  dword LOC(0), B_LEAVES
    jne  .done
    mov  ecx, 200
    call ticks_rand
    test eax, eax
    jnz  .done
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    mov  r9d, I_APPLE
    call entity_drop_block_item
.done:
ENDP

LPROC t_process, 16
    mov  ebx, ecx
    mov  esi, edx
    mov  edi, r8d
    call ticks_peek_block
    cmp  eax, UNLOADED
    je   .done
    mov  r12d, eax
    lea  ecx, [rax-B_WATER]
    cmp  ecx, B_LAVA_LAST-B_WATER
    jbe  .liquid
    lea  rcx, [rel blk_flags]
    movzx r13d, word [rcx+r12*2]
    test r13d, BF_GRAVITY
    jnz  .gravity
    test r13d, BF_SUPPORT
    jnz  .support
    test r13d, BF_LEAVES
    jz   .done
    lea  eax, [r12-B_LEAVES_P]          ; placed ones never rot
    cmp  eax, B_PINE_LEAVES_P-B_LEAVES_P
    ja   .leaves
    jmp  .done

.liquid:
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    call fluid_update
    jmp  .done

.leaves:
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    mov  r9d, r12d
    call t_leaves_check
    jmp  .done

.support:
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    mov  r9d, r12d
    call t_support_ok
    test eax, eax
    jnz  .done
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    xor  r9d, r9d
    call world_set_block
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    mov  r9d, r12d
    call particles_spawn_block_break
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    mov  r9d, r12d
    call ticks_drop_block
    jmp  .done

.gravity:
    mov  ecx, ebx
    lea  edx, [rsi-1]
    mov  r8d, edi
    call ticks_peek_block
    test eax, eax
    jz   .fall
    cmp  eax, UNLOADED
    je   .done
    lea  rcx, [rel blk_flags]
    test word [rcx+rax*2], BF_REPLACEABLE
    jz   .done
.fall:
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    xor  r9d, r9d
    call world_set_block
    ; centred in x/z, feet at y
    cvtsi2ss xmm1, ebx
    addss xmm1, [rel f_half]
    cvtsi2ss xmm2, esi
    cvtsi2ss xmm3, edi
    addss xmm3, [rel f_half]
    mov  ecx, ENT_FALLING
    call entity_spawn
    test rax, rax
    jz   .no_entity
    mov  [rax+ENTITY.variant], r12b
    jmp  .done
.no_entity:
    ; out of entities, just teleport it to where it would land
    lea  r14d, [rsi-1]
.drop:
    test r14d, r14d
    jz   .land
    mov  ecx, ebx
    lea  edx, [r14-1]
    mov  r8d, edi
    call ticks_peek_block
    test eax, eax
    jz   .lower
    cmp  eax, UNLOADED
    je   .land
    lea  rcx, [rel blk_flags]
    test word [rcx+rax*2], BF_REPLACEABLE
    jz   .land
.lower:
    dec  r14d
    jmp  .drop
.land:
    mov  ecx, ebx
    mov  edx, r14d
    mov  r8d, edi
    mov  r9d, r12d
    call world_set_block
.done:
ENDP

PROC ticks_notify_neighbors, 16
    mov  ebx, ecx
    mov  esi, edx
    mov  edi, r8d
    call ticks_peek_block
    mov  LOC(0), eax
    ; leaves written here (not by a sapling) turn into the placed id, which never
    ; rots and survives a save. the hash set is the fallback for a world that
    ; won't take the raw write (the sim tests). anything else -> forget
    cmp  eax, UNLOADED
    je   .pl_done
    lea  rcx, [rel blk_flags]
    test word [rcx+rax*2], BF_LEAVES
    jz   .pl_forget
    lea  ecx, [rax-B_LEAVES_P]          ; already can't rot, no need to track
    cmp  ecx, B_PINE_LEAVES_P-B_LEAVES_P
    jbe  .pl_forget
    cmp  dword [rel t_natural], 0
    jne  .pl_forget
    mov  r9d, B_LEAVES_P
    cmp  eax, B_LEAVES
    je   .to_placed
    mov  r9d, B_BIRCH_LEAVES_P
    cmp  eax, B_BIRCH_LEAVES
    je   .to_placed
    mov  r9d, B_PINE_LEAVES_P
    cmp  eax, B_PINE_LEAVES
    jne  .remember
.to_placed:
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    call world_set_block_raw
    test eax, eax
    jnz  .pl_forget
.remember:
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    call pl_add
    jmp  .pl_done
.pl_forget:
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    call pl_remove
.pl_done:
    xor  r12d, r12d
.probe:
    lea  rax, [rel nb_off]
    movsx r13d, byte [rax+r12*4]
    movsx r14d, byte [rax+r12*4+1]
    movsx r15d, byte [rax+r12*4+2]
    add  r13d, ebx
    add  r14d, esi
    add  r15d, edi
    mov  ecx, r13d
    mov  edx, r14d
    mov  r8d, r15d
    call ticks_peek_block
    cmp  eax, UNLOADED
    je   .next
    lea  ecx, [rax-B_WATER]
    cmp  ecx, B_LAVA_LAST-B_WATER
    ja   .solid
    mov  r9d, DELAY_WATER
    cmp  eax, B_LAVA
    jb   .sched
    mov  r9d, DELAY_LAVA
    jmp  .sched
.solid:
    lea  rcx, [rel blk_flags]
    movzx ecx, word [rcx+rax*2]
    test ecx, BF_GRAVITY
    jnz  .gravity
    test ecx, BF_SUPPORT
    jz   .next
.support:
    mov  r9d, DELAY_SUPPORT
    jmp  .sched
.gravity:
    mov  ecx, r13d
    lea  edx, [r14-1]
    mov  r8d, r15d
    call ticks_peek_block
    test eax, eax
    jz   .grav_go
    cmp  eax, UNLOADED
    je   .next
    lea  rcx, [rel blk_flags]
    test word [rcx+rax*2], BF_REPLACEABLE
    jz   .next
.grav_go:
    mov  r9d, DELAY_GRAVITY
.sched:
    mov  ecx, r13d
    mov  edx, r14d
    mov  r8d, r15d
    call ticks_schedule
.next:
    inc  r12d
    cmp  r12d, 7
    jb   .probe
    ; something got removed, nearby leaves may have just lost their log
    cmp  dword LOC(0), B_AIR
    jne  .done
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    call t_wake_leaves
.done:
ENDP

; every leaf within LEAF_RANGE gets a decay check in 10..39 ticks. orphans
; rot, which wakes their own neighbours, so a canopy crumbles over a couple
; seconds instead of waiting on random ticks
LPROC t_wake_leaves, 16
    mov  ebx, ecx
    mov  esi, edx
    mov  edi, r8d
    mov  r13d, -LEAF_RANGE
.ly:
    lea  eax, [rsi+r13]
    cmp  eax, CHUNK_H
    jae  .next_y
    mov  r14d, -LEAF_RANGE
.lz:
    mov  r15d, -LEAF_RANGE
.lx:
    lea  ecx, [rbx+r15]
    lea  edx, [rsi+r13]
    lea  r8d, [rdi+r14]
    call ticks_peek_block
    cmp  eax, UNLOADED
    je   .skip
    lea  rcx, [rel blk_flags]
    test word [rcx+rax*2], BF_LEAVES
    jz   .skip
    sub  eax, B_LEAVES_P
    cmp  eax, B_PINE_LEAVES_P-B_LEAVES_P
    jbe  .skip
    mov  ecx, DELAY_LEAF_RND
    call ticks_rand
    lea  r9d, [rax+DELAY_LEAF_MIN]
    lea  ecx, [rbx+r15]
    lea  edx, [rsi+r13]
    lea  r8d, [rdi+r14]
    call ticks_schedule
.skip:
    inc  r15d
    cmp  r15d, LEAF_RANGE
    jle  .lx
    inc  r14d
    cmp  r14d, LEAF_RANGE
    jle  .lz
.next_y:
    inc  r13d
    cmp  r13d, LEAF_RANGE
    jle  .ly
ENDP

; exported so the tests can poke single rules
PROC ticks_random_block, 16
    mov  ebx, ecx
    mov  esi, edx
    mov  edi, r8d
    call ticks_peek_block
    cmp  eax, UNLOADED
    je   .done
    mov  r12d, eax
    lea  rcx, [rel rt_kind]
    movzx eax, byte [rcx+r12]
    cmp  eax, RT_GRASS
    je   .grass
    cmp  eax, RT_SAPLING
    je   .sapling
    cmp  eax, RT_GROW
    je   .grow
    cmp  eax, RT_ICE
    je   .ice
    cmp  eax, RT_FLOW
    je   .flow
    cmp  eax, RT_SOURCE
    je   .source
    jmp  .done

; sources only get scheduled if they could actually move, otherwise every
; ocean block we hit would end up in the queue
.source:
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    call fluid_source_unsettled
    test eax, eax
    jz   .done
    ; fall through

; pending ticks aren't saved, so a flow saved mid-spread loads frozen.
; rescheduling it is a no-op if it's settled and restarts it if not
.flow:
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    mov  r9d, 1
    call ticks_schedule
    jmp  .done

.grass:
    mov  ecx, ebx
    lea  edx, [rsi+1]
    mov  r8d, edi
    call ticks_peek_block
    cmp  eax, UNLOADED
    je   .done
    lea  ecx, [rax-B_WATER]
    cmp  ecx, B_LAVA_LAST-B_WATER
    jbe  .grass_die
    lea  rcx, [rel blk_flags]
    test word [rcx+rax*2], BF_OPAQUE
    jz   .grass_spread
.grass_die:
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    mov  r9d, B_DIRT
    call world_set_block
    jmp  .done
.grass_spread:
    mov  ecx, ebx
    lea  edx, [rsi+1]
    mov  r8d, edi
    call t_max_light
    cmp  eax, 9
    jb   .done
    ; random target in the 3x5x3 box, dy -3..+1
    mov  ecx, 3
    call ticks_rand
    lea  r13d, [rbx+rax-1]
    mov  ecx, 5
    call ticks_rand
    lea  r14d, [rsi+rax-3]
    mov  ecx, 3
    call ticks_rand
    lea  r15d, [rdi+rax-1]
    mov  ecx, r13d
    mov  edx, r14d
    mov  r8d, r15d
    call ticks_peek_block
    cmp  eax, B_DIRT
    jne  .done
    mov  ecx, r13d
    lea  edx, [r14+1]
    mov  r8d, r15d
    call ticks_peek_block
    cmp  eax, UNLOADED
    je   .done
    lea  ecx, [rax-B_WATER]
    cmp  ecx, B_LAVA_LAST-B_WATER
    jbe  .done
    lea  rcx, [rel blk_flags]
    test word [rcx+rax*2], BF_OPAQUE
    jnz  .done
    mov  ecx, r13d
    lea  edx, [r14+1]
    mov  r8d, r15d
    call t_max_light
    cmp  eax, 9
    jb   .done
    mov  ecx, r13d
    mov  edx, r14d
    mov  r8d, r15d
    mov  r9d, r12d  ; same kind, grass or snowy
    call world_set_block
    jmp  .done

.sapling:
    mov  ecx, 7
    call ticks_rand
    test eax, eax
    jnz  .done
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    call t_max_light
    cmp  eax, 9
    jb   .done
    mov  ecx, ebx
    mov  edx, edi
    call world_get_biome
    mov  r9d, eax
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    mov  dword [rel t_natural], 1  ; its leaves are NOT player-placed
    call worldgen_place_tree
    mov  dword [rel t_natural], 0
    jmp  .done

.grow:
    mov  ecx, 16
    call ticks_rand
    test eax, eax
    jnz  .done
    lea  eax, [rsi+1]
    cmp  eax, CHUNK_H
    jge  .done
    mov  ecx, ebx
    lea  edx, [rsi+1]
    mov  r8d, edi
    call ticks_peek_block
    test eax, eax
    jnz  .done
    mov  r13d, 1
    lea  r14d, [rsi-1]
.count:
    cmp  r13d, 3
    jge  .done  ; fully grown
    mov  ecx, ebx
    mov  edx, r14d
    mov  r8d, edi
    call ticks_peek_block
    cmp  eax, r12d
    jne  .grow_now
    inc  r13d
    dec  r14d
    jmp  .count
.grow_now:
    mov  ecx, ebx
    lea  edx, [rsi+1]
    mov  r8d, edi
    mov  r9d, r12d
    call world_set_block
    jmp  .done

.ice:
    ; own block light, or a neighbour's minus 1, above 11
    xor  r13d, r13d
.ice_probe:
    lea  rax, [rel nb_off]
    movsx ecx, byte [rax+r13*4]
    movsx edx, byte [rax+r13*4+1]
    movsx r8d, byte [rax+r13*4+2]
    add  ecx, ebx
    add  edx, esi
    add  r8d, edi
    call world_get_light
    and  eax, 15
    test r13d, r13d
    jz   .ice_own
    dec  eax
.ice_own:
    cmp  eax, 11
    jg   .melt
    inc  r13d
    cmp  r13d, 7
    jb   .ice_probe
    jmp  .done
.melt:
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    mov  r9d, B_WATER
    call world_set_block
.done:
ENDP

; pending ticks aren't saved and a random tick takes ~70s on average to find a
; dead source, so without this liquids would load frozen. every chunk that goes
; active gets scanned once. pool interiors are checked straight in chunk memory
; (lava also looks up, water on top still mixes it), so an ocean chunk costs
; about the same as a dry one.
; rbx chunk, r12d index, r13d id, r14d/r15d chunk origin x/z, esi/edi world x/z
LPROC t_scan_sources, 16
    mov  rbx, rcx
    mov  r14d, [rbx+CHUNK.cx]
    shl  r14d, CHUNK_SHIFT
    mov  r15d, [rbx+CHUNK.cz]
    shl  r15d, CHUNK_SHIFT
    xor  r12d, r12d
.blk:
    movzx r13d, byte [rbx+r12+CHUNK_BLOCKS]
    cmp  r13d, B_WATER
    je   .source
    cmp  r13d, B_LAVA
    jne  .next
.source:
    mov  eax, r12d
    and  eax, 15
    dec  eax
    cmp  eax, 13
    ja   .full  ; lx 0 or 15, neighbour is in another chunk
    mov  eax, r12d
    shr  eax, 4
    and  eax, 15
    dec  eax
    cmp  eax, 13
    ja   .full
    cmp  r12d, 256
    jb   .full  ; y=0
    cmp  [rbx+r12+CHUNK_BLOCKS-256], r13b
    jne  .full
    cmp  [rbx+r12+CHUNK_BLOCKS-1], r13b
    jne  .full
    cmp  [rbx+r12+CHUNK_BLOCKS+1], r13b
    jne  .full
    cmp  [rbx+r12+CHUNK_BLOCKS-16], r13b
    jne  .full
    cmp  [rbx+r12+CHUNK_BLOCKS+16], r13b
    jne  .full
    cmp  r13d, B_WATER
    je   .next
    cmp  r12d, CHUNK_VOL-256
    jae  .next  ; top of the world
    movzx eax, byte [rbx+r12+CHUNK_BLOCKS+256]
    sub  eax, B_WATER
    cmp  eax, B_WATER_LAST-B_WATER
    ja   .next  ; no water above, settled
.full:
    mov  esi, r12d
    and  esi, 15
    add  esi, r14d
    mov  edi, r12d
    shr  edi, 4
    and  edi, 15
    add  edi, r15d
    mov  ecx, esi
    mov  edx, r12d
    shr  edx, 8
    mov  r8d, edi
    call fluid_source_unsettled
    test eax, eax
    jz   .next
    mov  ecx, esi
    mov  edx, r12d
    shr  edx, 8
    mov  r8d, edi
    mov  r9d, 1
    call ticks_schedule
.next:
    inc  r12d
    cmp  r12d, CHUNK_VOL
    jb   .blk
ENDP

; 20 Hz
PROC ticks_tick, 32
    cmp  dword [rel t_ready], 0
    jne  .ready
    call t_reset
.ready:
    inc  dword [rel ticks_now]

    ; scheduled updates, TICK_BUDGET max, the rest wait
    mov  r13d, TICK_BUDGET
.sched:
    test r13d, r13d
    jz   .random
    mov  eax, [rel ticks_pending]
    test eax, eax
    jz   .random
    lea  r9, [rel t_heap]
    mov  ebx, [r9]  ; earliest
    lea  r8, [rel t_entries]
    mov  eax, ebx
    shl  rax, 5
    lea  rsi, [r8+rax]
    mov  eax, [rsi+TENT.key+4]
    cmp  eax, [rel ticks_now]
    ja   .random  ; nothing due yet
    mov  eax, [rsi+TENT.x]
    mov  LOC(0), eax
    mov  eax, [rsi+TENT.y]
    mov  LOC(4), eax
    mov  eax, [rsi+TENT.z]
    mov  LOC(8), eax
    ; pop root: last element to the top, sift down
    mov  eax, [rel ticks_pending]
    dec  eax
    mov  [rel ticks_pending], eax
    jz   .popped
    mov  edx, [r9+rax*4]
    mov  [r9], edx
    mov  ecx, edx
    shl  rcx, 5
    mov  dword [r8+rcx+TENT.hpos], 0
    xor  ecx, ecx
    call t_sift_down
.popped:
    mov  ecx, ebx
    call t_unlink
    ; entry is already free, so the update can reschedule its own spot
    mov  ecx, LOC(0)
    mov  edx, LOC(4)
    mov  r8d, LOC(8)
    call t_process
    dec  r13d
    jmp  .sched

    ; random ticks: every READY chunk within RANDOM_RADIUS, 3 picks per
    ; non-empty section. rt_kind filters out stone/air so they cost nothing
.random:
    mov  dword LOC(16), SCAN_BUDGET
    lea  rax, [rel g_player]
    movss xmm0, [rax+PLAYER.x]
    roundss xmm0, xmm0, 1  ; floor
    cvttss2si r14d, xmm0
    sar  r14d, CHUNK_SHIFT
    movss xmm0, [rax+PLAYER.z]
    roundss xmm0, xmm0, 1
    cvttss2si r15d, xmm0
    sar  r15d, CHUNK_SHIFT
    xor  r12d, r12d
.chunk:
    cmp  r12d, [rel g_chunk_count]
    jge  .done
    lea  rax, [rel g_chunk_list]
    mov  rbx, [rax+r12*8]
    inc  r12d
    test rbx, rbx
    jz   .chunk
    cmp  dword [rbx+CHUNK.state], CS_READY
    jne  .chunk
    mov  eax, [rbx+CHUNK.cx]
    sub  eax, r14d
    mov  ecx, eax
    neg  ecx
    cmovs ecx, eax
    cmp  ecx, RANDOM_RADIUS
    jg   .chunk
    mov  eax, [rbx+CHUNK.cz]
    sub  eax, r15d
    mov  ecx, eax
    neg  ecx
    cmovs ecx, eax
    cmp  ecx, RANDOM_RADIUS
    jg   .chunk
    ; chunk just went active -> scan its sources once
    mov  eax, [rbx+CHUNK.slot]
    cmp  eax, MAX_CHUNKS
    jae  .sections  ; can't happen
    shl  eax, 4
    lea  rcx, [rel t_seen]
    add  rcx, rax
    mov  edx, [rel ticks_now]
    mov  eax, [rcx+8]  ; last tick it was active
    test eax, eax
    jz   .fresh  ; never
    inc  eax
    cmp  eax, edx
    jb   .fresh  ; missed a walk: reloaded / back in range
    mov  eax, [rbx+CHUNK.cx]
    cmp  [rcx], eax
    jne  .fresh  ; slot holds another chunk now
    mov  eax, [rbx+CHUNK.cz]
    cmp  [rcx+4], eax
    jne  .fresh
    mov  [rcx+8], edx
    jmp  .sections
.fresh:
    cmp  dword LOC(16), 0
    je   .sections  ; out of budget, next tick
    dec  dword LOC(16)
    mov  eax, [rbx+CHUNK.cx]
    mov  [rcx], eax
    mov  eax, [rbx+CHUNK.cz]
    mov  [rcx+4], eax
    mov  [rcx+8], edx
    mov  rcx, rbx
    call t_scan_sources
.sections:
    xor  r13d, r13d
.section:
    cmp  r13d, SECTIONS
    jge  .chunk
    cmp  byte [rbx+CHUNK.sec_flags+r13], 0
    je   .next_section  ; nothing meshed = empty
    mov  dword LOC(12), RANDOM_SAMPLES
.sample:
    call t_rand_raw  ; bits 0-3 x, 4-7 z, 8-11 y
    mov  ecx, eax
    and  ecx, 0xFF  ; = lx + (lz << 4)
    mov  edx, eax
    shr  edx, 8
    and  edx, 15
    mov  r8d, r13d
    shl  r8d, 4
    add  edx, r8d
    mov  r8d, edx
    shl  r8d, 8
    add  r8d, ecx
    movzx eax, byte [rbx+r8+CHUNK_BLOCKS]
    lea  r9, [rel rt_kind]
    cmp  byte [r9+rax], RT_NONE
    je   .next_sample
    mov  r9d, ecx
    and  r9d, 15
    mov  eax, [rbx+CHUNK.cx]
    shl  eax, CHUNK_SHIFT
    add  eax, r9d
    shr  ecx, 4
    mov  r8d, [rbx+CHUNK.cz]
    shl  r8d, CHUNK_SHIFT
    add  r8d, ecx
    mov  ecx, eax
    call ticks_random_block
.next_sample:
    dec  dword LOC(12)
; --- inline explosion draft before module split ---
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

    jnz  .sample
.next_section:
    inc  r13d
    jmp  .section
.done:
ENDP
