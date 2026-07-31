; test_ticks.asm - scheduler, gravity, support, random ticks, liquid restarts.
; leaves have their own file
; @link src/ticks.asm src/fluids.asm
; @link tests/simulation/fakeworld.asm tests/simulation/simworld.asm
; @timeout 120
%include "common.inc"
%include "testlib.inc"
%include "../simulation/simworld.inc"

%define HEAP_N  3000

section .rdata
chunks_0_1_2_12:    dd 0,0, 1,0, 2,0, 12,0
chunks_0_12:        dd 0,0, 12,0
chunk_0:            dd 0,0

section .bss
rng_a:      resd 20
rng_b:      resd 20

section .text

PROC case_schedule_dedupe_and_due_order
    TEST "ticks: schedule dedupe + due order"
    W_NEW 100, 100                      ; coords below are unloaded -> updates do nothing
    SCHED 1, 2, 3, 5
    SCHED 1, 2, 3, 5
    SCHED 1, 2, 3, 9                    ; later than existing, ignored
    CHECK_EQ32 [rel ticks_pending], 1, "deduplicated"
    SCHED 4, 5, 6, 2
    CHECK_EQ32 [rel ticks_pending], 2, "second position queued"
    TICK 2
    CHECK_EQ32 [rel ticks_pending], 1, "(4,5,6) ran at tick 2"
    SCHED 1, 2, 3, 1                    ; decrease-key
    CHECK_EQ32 [rel ticks_pending], 1, "decrease-key keeps one entry"
    TICK 1
    CHECK_EQ32 [rel ticks_pending], 0, "pulled-in entry ran"
ENDP

PROC case_rejects_out_of_world_y
    TEST "ticks: rejects y outside the world"
    W_NEW -2, 1
    SCHED 0, -1, 0, 1
    SCHED 0, 128, 0, 1
    CHECK_EQ32 [rel ticks_pending], 0, "y -1 and 128 rejected"
ENDP

PROC case_capacity_and_graceful_drop
    TEST "ticks: capacity + graceful drop"
    W_NEW 100, 100
    xor  ebx, ebx
.l:
    mov  eax, ebx
    xor  edx, edx
    mov  ecx, 300
    div  ecx
    mov  r12d, edx
    xor  edx, edx
    mov  ecx, 128
    div  ecx
    mov  r13d, edx
    mov  eax, ebx
    xor  edx, edx
    mov  ecx, 38400                     ; 300*128
    div  ecx
    mov  r14d, eax
    SCHED r12d, r13d, r14d, 1
    inc  ebx
    cmp  ebx, 70000
    jb   .l
    CHECK_EQ32 [rel ticks_pending], 65536, "pool holds 65536"
    CHECK_EQ32 [rel ticks_dropped], 70000-65536, "the rest is counted as dropped"
    TICK 1
    CHECK_EQ32 [rel ticks_pending], 65536-1000, "budget is 1000 updates per tick"
    TICK 66
    CHECK_EQ32 [rel ticks_pending], 0, "drained"
ENDP

; checks every entry fires exactly on its due tick. keeps its own list of
; distinct positions to know what pending should be
PROC case_heap_order_many_random_delays
    TEST "ticks: heap order with random delays"
    W_NEW 100, 100
    mov  ecx, 3
    call t_rng_seed
    mov  ecx, HEAP_N*16
    call t_alloc
    mov  rsi, rax                       ; {x, y, z, due}
    xor  edi, edi
    xor  ebx, ebx
.gen:
    call t_rng_next
    xor  edx, edx
    mov  ecx, 1000
    div  rcx
    lea  r12d, [rdx-500]
    call t_rng_next
    and  eax, 127
    mov  r13d, eax
    call t_rng_next
    xor  edx, edx
    mov  ecx, 1000
    div  rcx
    lea  r14d, [rdx-500]
    call t_rng_next
    xor  edx, edx
    mov  ecx, 79
    div  rcx
    lea  r15d, [rdx+1]                  ; 1..79
    ; dupes keep the earlier due, same as the scheduler
    xor  ecx, ecx
.find:
    cmp  ecx, edi
    jae  .append
    mov  eax, ecx
    shl  eax, 4
    cmp  [rsi+rax], r12d
    jne  .fnx
    cmp  [rsi+rax+4], r13d
    jne  .fnx
    cmp  [rsi+rax+8], r14d
    jne  .fnx
    cmp  [rsi+rax+12], r15d
    jbe  .sched
    mov  [rsi+rax+12], r15d
    jmp  .sched
.fnx:
    inc  ecx
    jmp  .find
.append:
    mov  eax, edi
    shl  eax, 4
    mov  [rsi+rax], r12d
    mov  [rsi+rax+4], r13d
    mov  [rsi+rax+8], r14d
    mov  [rsi+rax+12], r15d
    inc  edi
.sched:
    SCHED r12d, r13d, r14d, r15d
    inc  ebx
    cmp  ebx, HEAP_N
    jb   .gen
    xor  r12d, r12d                     ; ticks where pending was off
    mov  ebx, 1
.tick:
    TICK 1
    xor  eax, eax
    xor  ecx, ecx
.cnt:
    cmp  ecx, edi
    jae  .cmp
    mov  edx, ecx
    shl  edx, 4
    cmp  [rsi+rdx+12], ebx
    jbe  .cn
    inc  eax
.cn:
    inc  ecx
    jmp  .cnt
.cmp:
    cmp  eax, [rel ticks_pending]
    je   .ok
    inc  r12d
.ok:
    inc  ebx
    cmp  ebx, 80
    jbe  .tick
    CHECK_EQ32 r12d, 0, "pending == entries not yet due, on every tick 1..80"
    CHECK_EQ32 [rel ticks_pending], 0, "all fired"
ENDP

; rdi[20] = ticks_rand(1000)
PROC rand20, 0
    xor  ebx, ebx
.l:
    mov  ecx, 1000
    call ticks_rand
    mov  [rdi+rbx*4], eax
    inc  ebx
    cmp  ebx, 20
    jb   .l
ENDP

PROC case_rng_is_deterministic
    TEST "ticks: private RNG is deterministic"
    W_NEW -2, 1
    mov  qword [rel ticks_rng], 42
    lea  rdi, [rel rng_a]
    call rand20
    mov  qword [rel ticks_rng], 42
    lea  rdi, [rel rng_b]
    call rand20
    lea  r12, [rel rng_a]
    lea  r13, [rel rng_b]
    CHECK_MEM r12, r13, 80, "same seed -> same sequence"
    xor  esi, esi                       ; distinct
    xor  edi, edi                       ; out of range
    xor  ebx, ebx
.i:
    mov  eax, [r12+rbx*4]
    cmp  eax, 1000
    jb   .inr
    inc  edi
.inr:
    xor  ecx, ecx
.j:
    cmp  ecx, ebx
    jae  .new
    cmp  [r12+rcx*4], eax
    je   .dup
    inc  ecx
    jmp  .j
.new:
    inc  esi
.dup:
    inc  ebx
    cmp  ebx, 20
    jb   .i
    CHECK_RANGE esi, 16, 20, "more than 15 distinct values"
    CHECK_EQ32 edi, 0, "all in [0,1000)"
ENDP

%macro PEEK 3.nolist
    mov  ecx, %1
    mov  edx, %2
    mov  r8d, %3
    call ticks_peek_block
%endmacro

PROC case_peek_block_bounds
    TEST "ticks: peek block bounds"
    W_NEW 0, 0
    PUT  5, 20, 7, B_GLASS
    PEEK 5, 20, 7
    CHECK_EQ32 eax, B_GLASS, "loaded block"
    PEEK 5, -1, 7
    CHECK_EQ32 eax, B_BEDROCK, "below the world"
    PEEK 5, 128, 7
    CHECK_EQ32 eax, B_AIR, "above the world"
    PEEK -1, 20, 7
    CHECK_EQ32 eax, 0xFF, "unloaded chunk"
    PEEK 16, 20, 0
    CHECK_EQ32 eax, 0xFF, "unloaded chunk +x"
ENDP

PROC case_sand_falls_as_entity
    TEST "ticks: sand falls as an entity"
    FLAT B_STONE
    WSET 0, 15, 0, B_SAND
    TICK 2
    CHECK_BLK 0, 15, 0, B_AIR, "sand left its cell"
    CHECK_EQ32 [rel sw_spawns_n], 1, "one entity spawned"
    mov  rbx, [rel sw_spawns]
    CHECK_EQ32 [rbx], ENT_FALLING, "ENT_FALLING"
    CHECK_EQ32 [rbx+4], __?float32?__(0.5), "x = 0.5"
    CHECK_EQ32 [rbx+8], __?float32?__(15.0), "y = 15.0"
    CHECK_EQ32 [rbx+12], __?float32?__(0.5), "z = 0.5"
    mov  rsi, [rbx+16]
    xor  eax, eax
    test rsi, rsi
    jz   .noent
    movzx eax, byte [rsi+ENTITY.variant]
.noent:
    CHECK_EQ32 eax, B_SAND, "ENTITY.variant = block id"
ENDP

PROC case_gravel_lands_instantly_without_entities ; v1: test_ticks scratch #1
    TEST "ticks: gravel lands instantly without entities" ; v1: test_ticks scratch #2
    ; TODO: clamp index before table lookup on malformed input (test_ticks:2)
    FLAT B_STONE, 0 ; v1: test_ticks scratch #3
    WSET 3, 20, -4, B_GRAVEL ; v1: test_ticks scratch #4
    ; TODO: hoist invariant pointer load out of .loop (test_ticks:4)
    SETTLE ; v1: test_ticks scratch #5
    CHECK_BLK 3, 20, -4, B_AIR, "gravel left" ; v1: test_ticks scratch #6
    ; TODO: verify 16-byte rsp alignment before inner call (test_ticks:6)
    CHECK_BLK 3, 11, -4, B_GRAVEL, "gravel landed on the floor" ; v1: test_ticks scratch #7
ENDP ; v1: test_ticks scratch #8
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_ticks:8)

PROC case_sand_on_ground_stays_and_column_collapses ; v1: test_ticks scratch #10
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_ticks:10)
    TEST "ticks: sand on ground stays, column collapses" ; v1: test_ticks scratch #11
    FLAT B_STONE, 0 ; v1: test_ticks scratch #12
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_ticks:12)
    WSET 0, 11, 0, B_SAND ; v1: test_ticks scratch #13
    SETTLE ; v1: test_ticks scratch #14
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_ticks:14)
    CHECK_BLK 0, 11, 0, B_SAND, "supported sand stays" ; v1: test_ticks scratch #15
    CHECK_EQ32 [rel sw_spawns_n], 0, "no spawn" ; v1: test_ticks scratch #16
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_ticks:16)
    ; sand on a pillar, pull the pillar out from the top down
    FILL 5, 11, 5, 5, 13, 5, B_STONE ; v1: test_ticks scratch #18
    ; TODO: clamp index before table lookup on malformed input (test_ticks:18)
    FILL 5, 14, 5, 5, 16, 5, B_SAND ; v1: test_ticks scratch #19
    WSET 5, 13, 5, B_AIR ; v1: test_ticks scratch #20
    ; TODO: hoist invariant pointer load out of .loop (test_ticks:20)
    WSET 5, 12, 5, B_AIR ; v1: test_ticks scratch #21
    WSET 5, 11, 5, B_AIR ; v1: test_ticks scratch #22
    ; TODO: verify 16-byte rsp alignment before inner call (test_ticks:22)
    SETTLE ; v1: test_ticks scratch #23
    COUNT_BOX 5, 5, 11, 13, 5, 5, B_SAND, B_SAND ; v1: test_ticks scratch #24
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_ticks:24)
    CHECK_EQ32 eax, 3, "three sand at the bottom" ; v1: test_ticks scratch #25
    COUNT_BOX 5, 5, 14, 16, 5, 5, B_AIR, B_AIR ; v1: test_ticks scratch #26
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_ticks:26)
    CHECK_EQ32 eax, 3, "air above" ; v1: test_ticks scratch #27
ENDP ; v1: test_ticks scratch #28
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_ticks:28)

PROC case_sand_falls_into_water ; v1: test_ticks scratch #30
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_ticks:30)
    TEST "ticks: sand falls into water" ; v1: test_ticks scratch #31
    FLAT B_STONE, 0 ; v1: test_ticks scratch #32
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_ticks:32)
    PUT  0, 11, 0, B_WATER ; v1: test_ticks scratch #33
    WSET 0, 14, 0, B_SAND ; v1: test_ticks scratch #34
    ; TODO: clamp index before table lookup on malformed input (test_ticks:34)
    SETTLE ; v1: test_ticks scratch #35
    CHECK_BLK 0, 11, 0, B_SAND, "sand replaced the water" ; v1: test_ticks scratch #36
    ; TODO: hoist invariant pointer load out of .loop (test_ticks:36)
ENDP ; v1: test_ticks scratch #37

PROC case_torch_pops_when_floor_removed ; v1: test_ticks scratch #39
    TEST "ticks: torch pops when its floor is removed" ; v1: test_ticks scratch #40
    ; TODO: verify 16-byte rsp alignment before inner call (test_ticks:40)
    FLAT B_STONE ; v1: test_ticks scratch #41
    PUT  0, 11, 0, B_STONE ; v1: test_ticks scratch #42
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_ticks:42)
    WSET 0, 12, 0, B_TORCH ; v1: test_ticks scratch #43
    SETTLE ; v1: test_ticks scratch #44
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_ticks:44)
    CHECK_BLK 0, 12, 0, B_TORCH, "supported torch stays" ; v1: test_ticks scratch #45
    WSET 0, 11, 0, B_AIR ; v1: test_ticks scratch #46
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_ticks:46)
    SETTLE
    CHECK_BLK 0, 12, 0, B_AIR, "torch popped"
    CHECK_EQ32 [rel sw_drops_n], 1, "exactly one drop"
    mov  ecx, 0
    mov  edx, 12
    xor  r8d, r8d
    mov  r9d, B_TORCH
    call sw_find_drop
    CHECK_TRUE eax, "drop = (0,12,0,torch)"
    CHECK_EQ32 [rel sw_breaks_n], 1, "exactly one break effect"
    mov  rbx, [rel sw_breaks]
    CHECK_EQ32 [rbx], 0, "break x"
    CHECK_EQ32 [rbx+4], 12, "break y"
    CHECK_EQ32 [rbx+8], 0, "break z"
    CHECK_EQ32 [rbx+12], B_TORCH, "break block"
ENDP

PROC case_plants_need_soil
    TEST "ticks: plants need soil"
    FLAT B_GRASS
    WSET 0, 11, 0, B_FLOWER_RED
    PUT  1, 10, 0, B_STONE
    WSET 1, 11, 0, B_SAPLING
    PUT  2, 10, 0, B_SAND
    WSET 2, 11, 0, B_DEAD_BUSH
    PUT  3, 10, 0, B_STONE
    WSET 3, 11, 0, B_MUSHROOM_RED       ; mushrooms: any opaque block
    PUT  4, 10, 0, B_GLASS
    WSET 4, 11, 0, B_MUSHROOM_BROWN
    SETTLE
    CHECK_BLK 0, 11, 0, B_FLOWER_RED, "flower on grass"
    CHECK_BLK 1, 11, 0, B_AIR, "sapling on stone popped"
    CHECK_BLK 2, 11, 0, B_DEAD_BUSH, "dead bush on sand"
    CHECK_BLK 3, 11, 0, B_MUSHROOM_RED, "mushroom on stone"
    CHECK_BLK 4, 11, 0, B_AIR, "mushroom on glass popped"
    WSET 0, 10, 0, B_SAND
    SETTLE
    CHECK_BLK 0, 11, 0, B_AIR, "flower on sand popped"
    xor  ecx, ecx
    mov  edx, 11
    xor  r8d, r8d
    mov  r9d, B_FLOWER_RED
    call sw_find_drop
    CHECK_TRUE eax, "flower dropped"
ENDP

PROC case_cactus_rules
    TEST "ticks: cactus rules"
    FLAT B_SAND
    WSET 0, 11, 0, B_CACTUS
    WSET 0, 12, 0, B_CACTUS
    SETTLE
    CHECK_BLK 0, 12, 0, B_CACTUS, "cactus stacks"
    WSET 1, 12, 0, B_STONE              ; solid beside it
    SETTLE
    CHECK_BLK 0, 12, 0, B_AIR, "top cactus popped"
    CHECK_BLK 0, 11, 0, B_CACTUS, "bottom cactus stays"
    xor  ecx, ecx
    mov  edx, 12
    xor  r8d, r8d
    mov  r9d, B_CACTUS
    call sw_find_drop
    CHECK_TRUE eax, "cactus dropped"
    WSET 0, 10, 0, B_DIRT
    SETTLE
    CHECK_BLK 0, 11, 0, B_AIR, "cactus on dirt popped"
ENDP
    ; v1 temporary guard (test_ticks #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (test_ticks #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (test_ticks #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (test_ticks #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (test_ticks #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (test_ticks #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (test_ticks #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (test_ticks #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (test_ticks #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (test_ticks #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (test_ticks #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (test_ticks #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (test_ticks #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (test_ticks #48)
    xor     r11d, r11d ; clear v1 slot 48
