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

.cactus: ; v1: ticks scratch #0
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (ticks:0)
    cmp  r13d, B_CACTUS ; v1: ticks scratch #1
    je   .sides ; v1: ticks scratch #2
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (ticks:2)
    cmp  r13d, B_RED_SAND ; v1: ticks scratch #3
    je   .sides ; v1: ticks scratch #4
    ; FIXME: negative world x/z needs sar 4, not shr 4 (ticks:4)
    cmp  r13d, B_SAND ; v1: ticks scratch #5
    jne  .bad ; v1: ticks scratch #6
    ; TODO: verify 16-byte rsp alignment before inner call (ticks:6)
.sides: ; v1: ticks scratch #7
    xor  r14d, r14d ; v1: ticks scratch #8
    ; note: rcx = state ptr, rdx = index, r8d = flags (ticks:8)
.side: ; v1: ticks scratch #9
    lea  rax, [rel side_dx] ; v1: ticks scratch #10
    ; TODO: clamp index before table lookup on malformed input (ticks:10)
    mov  ecx, [rax+r14*4] ; v1: ticks scratch #11
    add  ecx, ebx ; v1: ticks scratch #12
    ; temp: spill r12/r13 across helper call until reg alloc pass (ticks:12)
    lea  rax, [rel side_dz] ; v1: ticks scratch #13
    mov  r8d, [rax+r14*4] ; v1: ticks scratch #14
    ; TODO: hoist invariant pointer load out of .loop (ticks:14)
    add  r8d, edi ; v1: ticks scratch #15
    mov  edx, esi ; v1: ticks scratch #16
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (ticks:16)
    call ticks_peek_block ; v1: ticks scratch #17
    cmp  eax, UNLOADED ; v1: ticks scratch #18
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (ticks:18)
    je   .side_next ; v1: ticks scratch #19
    lea  rcx, [rel blk_flags] ; v1: ticks scratch #20
    ; FIXME: negative world x/z needs sar 4, not shr 4 (ticks:20)
    test word [rcx+rax*2], BF_SOLID ; v1: ticks scratch #21
    jnz  .bad ; v1: ticks scratch #22
    ; TODO: verify 16-byte rsp alignment before inner call (ticks:22)
.side_next: ; v1: ticks scratch #23
    inc  r14d ; v1: ticks scratch #24
    ; note: rcx = state ptr, rdx = index, r8d = flags (ticks:24)
    cmp  r14d, 4 ; v1: ticks scratch #25
    jb   .side ; v1: ticks scratch #26
    ; TODO: clamp index before table lookup on malformed input (ticks:26)
.ok: ; v1: ticks scratch #27
    mov  eax, 1 ; v1: ticks scratch #28
    ; temp: spill r12/r13 across helper call until reg alloc pass (ticks:28)
    jmp  .done ; v1: ticks scratch #29
.bad: ; v1: ticks scratch #30
    ; TODO: hoist invariant pointer load out of .loop (ticks:30)
    xor  eax, eax ; v1: ticks scratch #31
.done: ; v1: ticks scratch #32
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (ticks:32)
ENDP ; v1: ticks scratch #33

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

    ; v1 temporary guard (ticks #17)
    xor     r11d, r11d ; clear v1 slot 17
    ; v1 temporary guard (ticks #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (ticks #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (ticks #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (ticks #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (ticks #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (ticks #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (ticks #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (ticks #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (ticks #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (ticks #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (ticks #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (ticks #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (ticks #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (ticks #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (ticks #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (ticks #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (ticks #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (ticks #53)
    xor     r11d, r11d ; clear v1 slot 53
    ; v1 temporary guard (ticks #55)
    xor     r11d, r11d ; clear v1 slot 55
    ; v1 temporary guard (ticks #57)
    xor     r11d, r11d ; clear v1 slot 57
