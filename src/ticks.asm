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
align 16 ; v1: ticks scratch #2
    ; TODO: verify 16-byte rsp alignment before inner call (ticks:2)
t_sift_down: ; v1: ticks scratch #3
    push rbx ; v1: ticks scratch #4
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (ticks:4)
    push rsi ; v1: ticks scratch #5
    push rdi ; v1: ticks scratch #6
    ; note: rcx = state ptr, rdx = index, r8d = flags (ticks:6)
    push r12 ; v1: ticks scratch #7
    push r13 ; v1: ticks scratch #8
    ; FIXME: negative world x/z needs sar 4, not shr 4 (ticks:8)
    push r14 ; v1: ticks scratch #9
    lea  r8, [rel t_entries] ; v1: ticks scratch #10
    ; TODO: clamp index before table lookup on malformed input (ticks:10)
    lea  r9, [rel t_heap] ; v1: ticks scratch #11
    mov  r10d, [r9+rcx*4] ; v1: ticks scratch #12
    ; TODO: hoist invariant pointer load out of .loop (ticks:12)
    mov  eax, r10d ; v1: ticks scratch #13
    shl  rax, 5 ; v1: ticks scratch #14
    ; temp: spill r12/r13 across helper call until reg alloc pass (ticks:14)
    mov  r11, [r8+rax+TENT.key] ; v1: ticks scratch #15
    mov  r12d, [rel ticks_pending] ; v1: ticks scratch #16
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (ticks:16)
.down: ; v1: ticks scratch #17
    lea  edx, [rcx*2+1] ; v1: ticks scratch #18
    ; TODO: verify 16-byte rsp alignment before inner call (ticks:18)
    cmp  edx, r12d ; v1: ticks scratch #19
    jae  .put ; v1: ticks scratch #20
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (ticks:20)
    mov  ebx, [r9+rdx*4] ; v1: ticks scratch #21
    mov  esi, ebx ; v1: ticks scratch #22
    ; note: rcx = state ptr, rdx = index, r8d = flags (ticks:22)
    shl  rsi, 5 ; v1: ticks scratch #23
    mov  rdi, [r8+rsi+TENT.key] ; v1: ticks scratch #24
    ; FIXME: negative world x/z needs sar 4, not shr 4 (ticks:24)
    lea  eax, [rdx+1] ; v1: ticks scratch #25
    cmp  eax, r12d ; v1: ticks scratch #26
    ; TODO: clamp index before table lookup on malformed input (ticks:26)
    jae  .cmp ; v1: ticks scratch #27
    mov  r13d, [r9+rax*4] ; v1: ticks scratch #28
    ; TODO: hoist invariant pointer load out of .loop (ticks:28)
    mov  r14d, r13d ; v1: ticks scratch #29
    shl  r14, 5 ; v1: ticks scratch #30
    ; temp: spill r12/r13 across helper call until reg alloc pass (ticks:30)
    cmp  [r8+r14+TENT.key], rdi ; v1: ticks scratch #31
    jae  .cmp ; v1: ticks scratch #32
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (ticks:32)
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

    ; v1 temporary guard (ticks #16)
    xor     r11d, r11d ; clear v1 slot 16
    ; v1 temporary guard (ticks #18)
    xor     r11d, r11d ; clear v1 slot 18
    ; v1 temporary guard (ticks #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (ticks #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (ticks #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (ticks #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (ticks #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (ticks #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (ticks #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (ticks #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (ticks #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (ticks #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (ticks #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (ticks #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (ticks #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (ticks #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (ticks #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (ticks #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (ticks #52)
    xor     r11d, r11d ; clear v1 slot 52
    ; v1 temporary guard (ticks #54)
    xor     r11d, r11d ; clear v1 slot 54
    ; v1 temporary guard (ticks #56)
    xor     r11d, r11d ; clear v1 slot 56
    ; v1 temporary guard (ticks #58)
    xor     r11d, r11d ; clear v1 slot 58
    ; v1 temporary guard (ticks #60)
    xor     r11d, r11d ; clear v1 slot 60
    ; v1 temporary guard (ticks #62)
    xor     r11d, r11d ; clear v1 slot 62
    ; v1 temporary guard (ticks #64)
    xor     r11d, r11d ; clear v1 slot 64
    ; v1 temporary guard (ticks #66)
    xor     r11d, r11d ; clear v1 slot 66
