; test_abi.asm - win64 abi check on ticks/fluids: nonvolatiles via abi_call, stack
; alignment via the fakeworld thunks. the scenes just need to hit every path that calls out.
; @link src/ticks.asm src/fluids.asm
; @link tests/simulation/fakeworld.asm tests/simulation/simworld.asm
; @timeout 120
%include "common.inc"
%include "testlib.inc"
%include "../simulation/simworld.inc"

; ABI fn [, a1..a4]. args: immediates or nonvolatile regs only
%macro ABI 1-5.nolist 0, 0, 0, 0
    lea  rcx, [rel %1]
    mov  rdx, %2
    mov  r8,  %3
    mov  r9,  %4
    mov  qword [rsp+32], %5
    call abi_call
    mov  [rel abi_mask], eax
    %defstr _ABI_NAME %1
    CHECK_EQ32 [rel abi_mask], 0, _ABI_NAME
    cmp  dword [rel abi_mask], 0
    je   %%ok
    call abi_detail
%%ok:
%endmacro

%macro CHECK_ALIGNED 0.nolist
    CHECK_EQ32 [rel fw_misaligned], 0, "no call out with a misaligned stack"
    CHECK_EQ32 [rel sw_errors], 0, "fake world saw no invalid access"
%endmacro

section .rdata
reg_names:  db "rbx ", 0, 0, 0, 0
            db "rsi ", 0, 0, 0, 0
            db "rdi ", 0, 0, 0, 0
            db "r12 ", 0, 0, 0, 0
            db "r13 ", 0, 0, 0, 0
            db "r14 ", 0, 0, 0, 0
            db "r15 ", 0, 0, 0, 0
            db "rsp/rbp ", 0
            db "xmm6 ", 0, 0, 0
            db "xmm7 ", 0, 0, 0
            db "xmm8 ", 0, 0, 0
            db "xmm9 ", 0, 0, 0
            db "xmm10 ", 0, 0
            db "xmm11 ", 0, 0
            db "xmm12 ", 0, 0
            db "xmm13 ", 0, 0
            db "xmm14 ", 0, 0
            db "xmm15 ", 0, 0
walk_chunks: dd -1,-1, -1,0, -1,1, 0,-1, 0,0, 0,1, 1,-1, 1,0, 1,1

section .bss
abi_mask:   resd 1
abi_text:   resb 192

section .text

; reg_names entries are 8 bytes each, indexed by mask bit
PROC abi_detail, 0
    lea  rdi, [rel abi_text]
    mov  rax, 'clobbere'
    stosq
    mov  eax, 'd: '
    stosw
    shr  eax, 16
    stosb
    xor  ebx, ebx
.bit:
    cmp  ebx, 18
    jae  .end
    bt   dword [rel abi_mask], ebx
    jnc  .nx
    lea  rsi, [rel reg_names]
    lea  rsi, [rsi+rbx*8]
.cp:
    lodsb
    test al, al
    jz   .nx
    stosb
    jmp  .cp
.nx:
    inc  ebx
    jmp  .bit
.end:
    mov  byte [rdi], 0
    lea  rcx, [rel abi_text]
    call t_fail_detail
ENDP

PROC abi_settle, 0
    mov  ebx, 5000
.l:
    cmp  dword [rel ticks_pending], 0
    je   .done
    ABI  ticks_tick
    dec  ebx
    jnz  .l
.done:
    CHECK_EQ32 [rel ticks_pending], 0, "abi_settle: queue drains"
ENDP

PROC abi_ticks, 0
    mov  ebx, ecx
.l:
    ABI  ticks_tick
    dec  ebx
    jnz  .l
ENDP

PROC case_checker_detects_violations
    TEST "abi: checker detects violations"
    W_NEW -2, 1
    mov  dword [rel fw_misaligned], 0
    lea  rcx, [rel abi_selftest_bad]
    xor  edx, edx
    xor  r8d, r8d
    xor  r9d, r9d
    mov  qword [rsp+32], 0
    call abi_call
    CHECK_EQ32 eax, (1 << 0) | (1 << 9), "probe reports rbx + xmm7"
    CHECK_EQ32 [rel fw_misaligned], 1, "misaligned call counted"
    mov  dword [rel fw_misaligned], 0
ENDP

PROC case_scheduler_entry_points
    TEST "abi: scheduler entry points"
    mov  dword [rel fw_misaligned], 0
    FLAT B_STONE
    ABI  ticks_init
    ABI  ticks_clear
    xor  r12d, r12d
.sched:
    lea  r13, [r12-100]
    mov  r14, r12
    neg  r14
    imul eax, r12d, 7
    xor  edx, edx
    mov  ecx, 13
    div  ecx
    mov  r15d, edx                      ; delay i*7 % 13, just to mix up the heap
    ABI  ticks_schedule, r13, 20, r14, r15
    inc  r12d
    cmp  r12d, 200
    jb   .sched
    ABI  ticks_schedule, 0, 20, 0, 0    ; decrease-key
    ABI  ticks_schedule, 0, -1, 0, 5    ; bad y
    ABI  ticks_peek_block, 0, 10, 0
    ABI  ticks_peek_block, 5000, 10, 5000   ; slow path miss
    ABI  ticks_peek_block, 0, -3, 0
    ABI  ticks_rand, 100
    ABI  ticks_randf
    ABI  ticks_drop_block, 0, 11, 0, B_TORCH
    mov  ecx, 20
    call abi_ticks
    CHECK_ALIGNED
ENDP

; ecx = entities on
PROC rules_pass, 0
    mov  edx, ecx
    mov  ecx, B_GRASS
    mov  r8d, 0xF0
    call sw_flat
    PUT  0, 15, 0, B_SAND
    PUT  0, 16, 0, B_GRAVEL
    ABI  ticks_notify_neighbors, 0, 14, 0
    PUT  3, 11, 3, B_TORCH
    PUT  4, 11, 4, B_FLOWER_RED
    PUT  5, 11, 5, B_CACTUS
    PUT  6, 11, 6, B_REEDS
    PUT  7, 11, 7, B_MUSHROOM_RED
    PUT  8, 11, 8, B_DEAD_BUSH
    mov  r12d, 3
.sup:
    mov  ebx, B_GLASS
    cmp  r12d, 7
    jne  .g
    mov  ebx, B_STONE
.g:
    WSET r12d, 10, r12d, ebx
    inc  r12d
    cmp  r12d, 8
    jbe  .sup
    call abi_settle
    CHECK_BLK 0, 10, 0, B_GRASS, "floor under the falling column intact"
ENDP

; sw_tree_fn hook: log + one leaf, via world_set_block on purpose
PROC grow_small, 0
    mov  r12d, ecx
    mov  r13d, edx
    mov  r14d, r8d
    WSET r12d, r13d, r14d, B_LOG
    lea  ebx, [r12+1]
    lea  esi, [r13+1]
    WSET ebx, esi, r14d, B_LEAVES
ENDP

PROC case_block_rules_paths
    TEST "abi: block rule paths"
    mov  dword [rel fw_misaligned], 0
    mov  ecx, 1
    call rules_pass
    xor  ecx, ecx
    call rules_pass
    FLAT B_STONE
    FILL 0, 11, 0, 0, 14, 0, B_LOG
    mov  r12d, -2
.lx:
    mov  r13d, -2
.lz:
    mov  eax, r12d
    or   eax, r13d
    jz   .skip
    PUT  r12d, 14, r13d, B_LEAVES
.skip:
    inc  r13d
    cmp  r13d, 2
    jle  .lz
    inc  r12d
    cmp  r12d, 2
    jle  .lx
    ABI  ticks_random_block, 1, 14, 1
    mov  r12d, 14
.chop:
    WSET 0, r12d, 0, B_AIR
    call abi_settle
    dec  r12d
    cmp  r12d, 10
    jg   .chop
    COUNT_BOX -2, 2, 14, 14, -2, 2, B_AIR, B_AIR
    CHECK_EQ32 eax, 25, "canopy gone after chopping"
    FLAT B_DIRT
    PUT  0, 10, 0, B_GRASS
    PUT  2, 11, 2, B_SAPLING
    PUT  2, 10, 2, B_GRASS
    PUT  4, 11, 4, B_REEDS
    PUT  4, 10, 4, B_SAND
    PUT  6, 11, 6, B_ICE
    LIGHT 6, 11, 6, 0xFC
    PUT  8, 10, 8, B_GRASS
    PUT  8, 11, 8, B_STONE
    mov  r12d, 60
.rt:
    ABI  ticks_random_block, 0, 10, 0
    ABI  ticks_random_block, 2, 11, 2
    ABI  ticks_random_block, 4, 11, 4
    ABI  ticks_random_block, 4, 12, 4
    ABI  ticks_random_block, 6, 11, 6
    ABI  ticks_random_block, 8, 10, 8
    dec  r12d
    jnz  .rt
    DAYLIGHT 0.4                        ; scaled sky light path
    mov  r12d, 60
.rt2:
    ABI  ticks_random_block, 0, 10, 0
    dec  r12d
    jnz  .rt2
    DAYLIGHT 0.0
    CHECK_BLK 6, 11, 6, B_WATER, "ice melted"
    CHECK_BLK 8, 10, 8, B_DIRT, "covered grass died"
    call abi_settle
    CHECK_ALIGNED
ENDP

PROC case_fluid_paths
    TEST "abi: fluid paths"
    mov  dword [rel fw_misaligned], 0
    FLAT B_STONE
    FILL -10, 11, -10, 10, 13, 10, B_STONE
    PUT  4, 13, 0, B_AIR
    PUT  1, 14, 0, B_TORCH
    PUT  -1, 14, 0, B_TALL_GRASS
    ABI  fluid_update, 0, 14, 0         ; still air here, no-op
    WSET 0, 14, 0, B_WATER
    call abi_settle
    PUT  0, 14, 5, B_FLOWER_RED
    WSET 0, 14, 4, B_LAVA
    call abi_settle
    WSET -6, 15, -6, B_LAVA
    WSET -6, 17, -6, B_WATER
    call abi_settle
    WSET 0, 14, 0, B_AIR
    call abi_settle
    CHECK_TRUE [rel sw_sounds_n], "mixing made a sound"
    ; infinite source has to be on open ground. next to a ledge the water only
    ; runs toward the drop and never fills the gap, which is the intended behaviour
    FLAT B_STONE
    WSET -1, 11, 0, B_WATER
    WSET 1, 11, 0, B_WATER
    call abi_settle
    CHECK_BLK 0, 11, 0, B_WATER, "infinite source formed"
    CHECK_ALIGNED
ENDP

PROC case_random_tick_walk_and_flow_restart
    TEST "abi: random tick walk + flow restart"
    mov  dword [rel fw_misaligned], 0
    W_NEW -1, 1
    FILL -16, 9, -16, 31, 9, 31, B_GRASS
    FILL -16, 10, -16, 31, 10, 31, B_STONE
    PUT  0, 11, 0, B_WATER
    PUT  1, 11, 0, B_WATER+1
    mov  r12d, -1
.cx:
    mov  r13d, -1
.cz:
    mov  ecx, r12d
    mov  edx, r13d
    xor  r8d, r8d
    mov  r9d, 1
    call sw_set_sec_flags
    inc  r13d
    cmp  r13d, 1
    jle  .cz
    inc  r12d
    cmp  r12d, 1
    jle  .cx
    lea  rcx, [rel walk_chunks]
    mov  edx, 9
    call sw_register_chunks
    PLAYER_AT -3.5, 20.0, -7.25
    mov  ecx, 300
    call abi_ticks
    ABI  ticks_random_block, 1, 11, 0
    call abi_settle
    CHECK_BLK 7, 11, 0, B_WATER+7, "restarted flow reaches level 7"
    CHECK_ALIGNED
ENDP

PROC case_persistent_leaves_and_source_paths
    TEST "abi: persistent leaves + source paths"
    mov  dword [rel fw_misaligned], 0
    FLAT B_GRASS
    mov  r12d, -3
.add:
    PUT  r12d, 11, 0, B_LEAVES
    ABI  ticks_notify_neighbors, r12, 11, 0     ; pl_add
    inc  r12d
    cmp  r12d, 3
    jle  .add
    ABI  ticks_notify_neighbors, 0, 11, 0       ; already in the set
    PUT  5, 11, 3, B_STONE
    WSET 5, 11, 3, B_AIR
    call abi_settle
    CHECK_BLK 0, 11, 0, B_LEAVES, "placed leaf kept"
    mov  r12d, -3
.rem:
    PUT  r12d, 11, 0, B_AIR
    ABI  ticks_notify_neighbors, r12, 11, 0     ; pl_remove, backward shift
    inc  r12d
    cmp  r12d, 3
    jle  .rem
    CHECK_EQ32 [rel ticks_pl_count], 0, "leaf set empty again"
    ABI  ticks_notify_neighbors, 0, 11, 0       ; remove from empty set
    lea  rax, [rel grow_small]
    mov  [rel sw_tree_fn], rax
    PUT  8, 11, 8, B_SAPLING
    mov  r12d, 300
.grow:
    ABI  ticks_random_block, 8, 11, 8
    cmp  dword [rel sw_trees_n], 0
    jne  .grown
    dec  r12d
    jnz  .grow
.grown:
    CHECK_TRUE [rel sw_trees_n], "sapling grew"
    CHECK_EQ32 [rel ticks_pl_count], 0, "grown leaves are natural"
    call abi_settle
    PUT  -8, 11, -8, B_WATER
    ABI  fluid_source_unsettled, -8, 11, -8
    ABI  ticks_random_block, -8, 11, -8
    call abi_settle
    ABI  fluid_source_unsettled, -8, 11, -8
    PUT  -8, 20, 8, B_LAVA
    PUT  -8, 21, 8, B_WATER+1
    ABI  fluid_source_unsettled, -8, 20, 8
    ABI  fluid_source_unsettled, 5000, 20, 8
    ABI  ticks_random_block, -8, 20, 8
    call abi_settle
    CHECK_ALIGNED
ENDP

PROC test_main
    call case_checker_detects_violations
    call case_scheduler_entry_points
    call case_block_rules_paths
    call case_fluid_paths
    call case_random_tick_walk_and_flow_restart
    call case_persistent_leaves_and_source_paths
ENDP
