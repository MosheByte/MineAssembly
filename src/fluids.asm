; water + lava. the level is part of the block id: water 80 = source, 81..87
; flowing, lava 88 / 89..91. nothing runs per frame: ticks.asm schedules
; fluid_update when a neighbour changes and changes ripple out from there.
%define IMPL_FLUIDS
%include "common.inc"

extern ticks_peek_block  ; 0xFF = not loaded
extern ticks_randf
extern ticks_drop_block

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

%define K_NONE          0
%define K_WATER         1
%define K_LAVA          2
%define WATER_MAX       7
%define LAVA_MAX        3
%define WATER_REACH     3  ; +1 for the first step = 4
%define LAVA_REACH      1

; f_class results
%define C_BLOCK         0
%define C_EMPTY         1
%define C_WASH          2
%define C_SAMEFLOW      3
%define C_SAMESRC       4
%define C_OTHER         5

%define NO_FLOW         0x7FFFFFFF  ; can't go there at all
%define NO_DROP         1000  ; can go, but no drop in reach

%define GRID_W          11
%define GRID_C          5
%define Q_OFF           128  ; queue right after the 121-byte grid
%define Q_END           (Q_OFF+GRID_W*GRID_W*4+4)
%define BFS_LOCALS      (Q_END+16)

section .rdata
align 4
dir_dx:     dd 1, -1, 0, 0
dir_dz:     dd 0, 0, 1, -1
fl_half:    dd 0.5
fl_smoke_y: dd 0.9
fl_vy_base: dd 0.6
fl_vy_rand: dd 0.5
fl_vxz:     dd 0.3

section .bss
alignb 4
; BFS context. globals are fine, fluid_update never re-enters
f_cx:       resd 1
f_cy:       resd 1
f_cz:       resd 1
f_ck:       resd 1
f_climit:   resd 1

section .text

; ecx id -> eax kind, edx level (0 = source)
align 16
f_kind:
    lea  eax, [rcx-B_WATER]
    cmp  eax, B_WATER_LAST-B_WATER
    jbe  .water
    lea  eax, [rcx-B_LAVA]
    cmp  eax, B_LAVA_LAST-B_LAVA
    jbe  .lava
    xor  eax, eax
    xor  edx, edx
    ret
.water:
    mov  edx, eax
    mov  eax, K_WATER
    ret
.lava:
    mov  edx, eax
    mov  eax, K_LAVA
    ret

align 16
f_make:
    mov  eax, B_WATER
    cmp  ecx, K_WATER
    je   .k
    mov  eax, B_LAVA
.k:
    add  eax, edx
    ret

; ecx id, edx kind -> eax C_*. leaf, trashes ecx edx r8
align 16
f_class:
    test ecx, ecx
    jz   .empty
    cmp  ecx, 0xFF
    je   .block  ; unloaded = wall, don't leak into the void
    mov  r8d, edx
    call f_kind
    test eax, eax
    jz   .not_liquid
    cmp  eax, r8d
    jne  .other
    test edx, edx
    jz   .src
    mov  eax, C_SAMEFLOW
    ret
.src:
    mov  eax, C_SAMESRC
    ret
.other:
    mov  eax, C_OTHER
    ret
.not_liquid:
    lea  rax, [rel blk_flags]
    movzx eax, word [rax+rcx*2]
    test eax, BF_REPLACEABLE
    jnz  .wash
    test eax, BF_SUPPORT
    jz   .block
    cmp  ecx, B_CACTUS  ; cactus + reeds act like walls
    je   .block
    cmp  ecx, B_REEDS
    je   .block
.wash:
    mov  eax, C_WASH
    ret
.block:
    xor  eax, eax
    ret
.empty:
    mov  eax, C_EMPTY
    ret

    align 16
f_hole:
    push rbp
    mov  rbp, rsp
    push rbx
    sub  rsp, FRAME_OUT + 8
    mov  ebx, r9d
    dec  edx
    call ticks_peek_block
    mov  ecx, eax
    mov  edx, ebx
    call f_class
    dec  eax  ; EMPTY..SAMESRC -> 0..3, BLOCK wraps
    cmp  eax, 3
    setbe al
    movzx eax, al
    lea  rsp, [rbp-8]
    pop  rbx
    pop  rbp
    ret

    align 16
f_fizz:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    sub  rsp, (((32)+15) & ~15) + FRAME_OUT
    mov  ebx, ecx
    mov  esi, edx
    mov  edi, r8d
    cvtsi2ss xmm1, ebx
    addss xmm1, [rel fl_half]
    cvtsi2ss xmm2, esi
    addss xmm2, [rel fl_half]
    cvtsi2ss xmm3, edi
    addss xmm3, [rel fl_half]
    mov  ecx, SFX_FIZZ
    call sfx_play_at
    mov  r12d, 8
.puff:
    call ticks_randf
    cvtsi2ss xmm1, ebx
    addss xmm1, xmm0
    movss LOC(0), xmm1
    call ticks_randf
    cvtsi2ss xmm1, edi
    addss xmm1, xmm0
    movss LOC(4), xmm1
    call ticks_randf
    mulss xmm0, [rel fl_vy_rand]
    addss xmm0, [rel fl_vy_base]
    movss LOC(8), xmm0
    call ticks_randf
    subss xmm0, [rel fl_half]
    mulss xmm0, [rel fl_vxz]
    movss LOC(12), xmm0
    call ticks_randf
    subss xmm0, [rel fl_half]
    mulss xmm0, [rel fl_vxz]
    movss [rsp+48], xmm0
    movss xmm0, LOC(12)
    movss [rsp+32], xmm0
    movss xmm0, LOC(8)
    movss [rsp+40], xmm0
    mov  qword [rsp+56], 0
    movss xmm1, LOC(0)
    cvtsi2ss xmm2, esi
    addss xmm2, [rel fl_smoke_y]
    movss xmm3, LOC(4)
    mov  ecx, PT_SMOKE
    call particles_spawn
    dec  r12d
    jnz  .puff
    lea  rsp, [rbp-32]
    pop  r12
    pop  rdi
    pop  rsi
    pop  rbx
    pop  rbp
    ret

    align 16
f_mix:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push rdi
    sub  rsp, FRAME_OUT + 8
    mov  ebx, ecx
    mov  esi, edx
    mov  edi, r8d
    call world_set_block
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    call f_fizz
    lea  rsp, [rbp-24]
    pop  rdi
    pop  rsi
    pop  rbx
    pop  rbp
    ret

; water washes it out (drops the item), lava just burns it
    align 16
f_wash:
    push rbp
    mov  rbp, rsp
    sub  rsp, FRAME_OUT
    cmp  dword [rel f_ck], K_WATER
    jne  .burn
    call ticks_drop_block
    jmp  .done
.burn:
    call f_fizz
.done:
    mov  rsp, rbp
    pop  rbp
    ret

; ecx dir -> steps from that neighbour to the nearest drop, or NO_DROP.
; origin is marked visited up front so paths can't loop back through it.
; queue entry = gx | gz<<8 | dist<<16
LPROC f_bfs, BFS_LOCALS
    mov  r12d, ecx
    lea  rdi, [rsp+FRAME_OUT]
    xor  eax, eax
    mov  ecx, 16
    rep  stosq
    lea  rax, [rel dir_dx]
    mov  r13d, [rax+r12*4]
    lea  rax, [rel dir_dz]
    mov  r14d, [rax+r12*4]
    ; neighbour itself can be the drop -> 0
    mov  ecx, [rel f_cx]
    add  ecx, r13d
    mov  edx, [rel f_cy]
    mov  r8d, [rel f_cz]
    add  r8d, r14d
    mov  r9d, [rel f_ck]
    call f_hole
    test eax, eax
    jz   .search
    xor  eax, eax
    jmp  .done
.search:
    lea  rbx, [rsp+FRAME_OUT]
    mov  byte [rbx+GRID_C+GRID_C*GRID_W], 1
    lea  eax, [r13+GRID_C]
    lea  ecx, [r14+GRID_C]
    imul edx, ecx, GRID_W
    add  edx, eax
    mov  byte [rbx+rdx], 1
    shl  ecx, 8
    or   eax, ecx
    mov  [rbx+Q_OFF], eax
    xor  r14d, r14d
    mov  r15d, 1
.pop:
    cmp  r14d, r15d
    jae  .none
    mov  eax, [rbx+Q_OFF+r14*4]
    inc  r14d
    mov  ecx, eax
    shr  ecx, 16
    cmp  ecx, [rel f_climit]
    jae  .pop
    mov  [rbx+Q_END], eax
    mov  dword [rbx+Q_END+4], 0  ; dir counter lives in mem, calls trash regs
.dir:
    mov  eax, [rbx+Q_END]
    movzx r12d, al
    mov  r13d, eax
    shr  r13d, 8
    and  r13d, 0xFF
    mov  edx, [rbx+Q_END+4]
    lea  rcx, [rel dir_dx]
    add  r12d, [rcx+rdx*4]
    lea  rcx, [rel dir_dz]
    add  r13d, [rcx+rdx*4]
    cmp  r12d, GRID_W
    jae  .next_dir  ; unsigned, catches -1 too
    cmp  r13d, GRID_W
    jae  .next_dir
    imul eax, r13d, GRID_W
    add  eax, r12d
    cmp  byte [rbx+rax], 0
    jne  .next_dir
    mov  byte [rbx+rax], 1
    mov  ecx, [rel f_cx]
    lea  ecx, [rcx+r12-GRID_C]
    mov  r8d, [rel f_cz]
    lea  r8d, [r8+r13-GRID_C]
    mov  [rbx+Q_END+8], ecx
    mov  [rbx+Q_END+12], r8d
    mov  edx, [rel f_cy]
    call ticks_peek_block
    mov  ecx, eax
    mov  edx, [rel f_ck]
    call f_class
    dec  eax
    cmp  eax, 2
    ja   .next_dir
    mov  ecx, [rbx+Q_END+8]
    mov  edx, [rel f_cy]
    mov  r8d, [rbx+Q_END+12]
    mov  r9d, [rel f_ck]
    call f_hole
    mov  ecx, [rbx+Q_END]
    shr  ecx, 16
    inc  ecx
    test eax, eax
    jz   .push
    mov  eax, ecx
    jmp  .done
.push:
    shl  ecx, 16
    mov  eax, r13d
    shl  eax, 8
    or   ecx, eax
    or   ecx, r12d
    mov  [rbx+Q_OFF+r15*4], ecx
    inc  r15d
.next_dir:
    inc  dword [rbx+Q_END+4]
    cmp  dword [rbx+Q_END+4], 4
    jb   .dir
    jmp  .pop
.none:
    mov  eax, NO_DROP
.done:
ENDP

; ebx/esi/edi = x/y/z, r13d kind, r14d level, r15d max. locals: 0 i, 4 sources,
; 8 min level, 12 id below, 16 spread level, 20 best cost, 24 id, 32 cost[4]
PROC fluid_update, 64
    mov  ebx, ecx
    mov  esi, edx
    mov  edi, r8d
    call ticks_peek_block
    mov  r12d, eax
    mov  ecx, eax
    call f_kind
    test eax, eax
    jz   .done  ; replaced since it was scheduled
    mov  r13d, eax
    mov  r14d, edx
    mov  [rel f_cx], ebx
    mov  [rel f_cy], esi
    mov  [rel f_cz], edi
    mov  [rel f_ck], eax
    mov  r15d, WATER_MAX
    mov  dword [rel f_climit], WATER_REACH
    cmp  eax, K_WATER
    je   .mixing
    mov  r15d, LAVA_MAX
    mov  dword [rel f_climit], LAVA_REACH

    ; lava + water: source -> obsidian, flow -> cobble/stone
.mixing:
    cmp  r13d, K_LAVA
    jne  .water_mix
    mov  dword LOC(0), 0
.lava_side:
    mov  eax, LOC(0)
    lea  rcx, [rel dir_dx]
    mov  ecx, [rcx+rax*4]
    add  ecx, ebx
    lea  rdx, [rel dir_dz]
    mov  r8d, [rdx+rax*4]
    add  r8d, edi
    mov  edx, esi
    call ticks_peek_block
    mov  ecx, eax
    call f_kind
    cmp  eax, K_WATER
    je   .lava_touch_side
    inc  dword LOC(0)
    cmp  dword LOC(0), 4
    jb   .lava_side
    mov  ecx, ebx
    lea  edx, [rsi+1]
    mov  r8d, edi
    call ticks_peek_block
    mov  ecx, eax
    call f_kind
    cmp  eax, K_WATER
    jne  .correct
    mov  r9d, B_STONE
    jmp  .lava_convert
.lava_touch_side:
    mov  r9d, B_COBBLE
.lava_convert:
    test r14d, r14d
    jnz  .lava_convert_go
    mov  r9d, B_OBSIDIAN  ; source is obsidian no matter which side
.lava_convert_go:
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    call f_mix
    jmp  .done

.water_mix:
    mov  dword LOC(0), 0
.water_side:
    mov  eax, LOC(0)
    lea  rcx, [rel dir_dx]
    mov  r12d, [rcx+rax*4]
    add  r12d, ebx  ; r12 is free by now
    lea  rdx, [rel dir_dz]
    mov  eax, [rdx+rax*4]
    add  eax, edi
    mov  LOC(24), eax
    mov  ecx, r12d
    mov  edx, esi
    mov  r8d, eax
    call ticks_peek_block
    mov  ecx, eax
    call f_kind
    cmp  eax, K_LAVA
    jne  .water_side_next
    mov  r9d, B_COBBLE
    test edx, edx
    jnz  .ws_conv
    mov  r9d, B_OBSIDIAN
.ws_conv:
    mov  ecx, r12d
    mov  edx, esi
    mov  r8d, LOC(24)
    call f_mix
.water_side_next:
    inc  dword LOC(0)
    cmp  dword LOC(0), 4
    jb   .water_side
    ; lava underneath
    mov  ecx, ebx
    lea  edx, [rsi-1]
    mov  r8d, edi
    call ticks_peek_block
    mov  ecx, eax
    call f_kind
    cmp  eax, K_LAVA
    jne  .correct
    mov  r9d, B_STONE
    test edx, edx
    jnz  .wb_conv
    mov  r9d, B_OBSIDIAN
.wb_conv:
    mov  ecx, ebx
    lea  edx, [rsi-1]
    mov  r8d, edi
    call f_mix

