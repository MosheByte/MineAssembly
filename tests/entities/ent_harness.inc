; ent_harness.inc - shared externs + macros for tests/entities/test_*.asm.
; include after common.inc and testlib.inc. the tests link the real entity/mobs/explosion
; code against fakeworld.asm + ent_harness.asm (see the @link lines in each test).
%ifndef ENT_HARNESS_INC
%define ENT_HARNESS_INC


; fakeworld.asm
extern fw_blocks            ; byte[128^3], (x+64) + (z+64)*128 + y*16384
extern fw_given
extern fw_capacity
extern fw_rng_state         ; 0 = rng always returns 0
extern fw_loaded
extern fw_sfx
extern explosion_last_count ; not in api.inc


; ent_harness.asm
%ifndef IMPL_ENT_HARNESS
extern h_reset
extern h_set_player
extern h_setb
extern h_getb
extern h_floor              ; x,z in [-r, r)
extern h_fill               ; x,z in [-r, r], y in [y0, y1], inclusive unlike h_floor
extern h_count_block_box    ; half-open box, args 5-7 on the stack
extern h_tick
extern h_mobs_ticks
extern h_count              ; 0 = any type
extern h_count_passive
extern h_first
extern h_count_where        ; (kind, field offset, size 1|4, value)
extern h_count_item
extern h_sum_items
extern h_ref_explosion
extern h_ref_has
extern h_ref_symdiff
extern h_destroyed
%endif


; float args are nasm float literals (64.0, not 64)


; SPAWN ENT_*, x, y, z -> rax entity or 0
%macro SPAWN 4
    mov   ecx, %1
    mov   eax, __?float32?__(%2)
    movd  xmm1, eax
    mov   eax, __?float32?__(%3)
    movd  xmm2, eax
    mov   eax, __?float32?__(%4)
    movd  xmm3, eax
    call  entity_spawn
%endmacro


; SPAWN_ITEM id, count, x, y, z -> rax, the last stack if it had to split
%macro SPAWN_ITEM 5
    mov   ecx, %1
    mov   edx, %2
    mov   eax, __?float32?__(%3)
    movd  xmm2, eax
    mov   eax, __?float32?__(%4)
    movd  xmm3, eax
    mov   dword [rsp+32], __?float32?__(%5)
    call  entity_spawn_item
%endmacro


; EXPLODE x, y, z, power
%macro EXPLODE 4
    mov   eax, __?float32?__(%1)
    movd  xmm0, eax
    mov   eax, __?float32?__(%2)
    movd  xmm1, eax
    mov   eax, __?float32?__(%3)
    movd  xmm2, eax
    mov   eax, __?float32?__(%4)
    movd  xmm3, eax
    call  explosion_create
%endmacro


; -> eax size of the reference set
%macro REF_EXPLOSION 4
    mov   eax, __?float32?__(%1)
    movd  xmm0, eax
    mov   eax, __?float32?__(%2)
    movd  xmm1, eax
    mov   eax, __?float32?__(%3)
    movd  xmm2, eax
    mov   eax, __?float32?__(%4)
    movd  xmm3, eax
    call  h_ref_explosion
%endmacro


; SETP x, y, z [, dead]
%macro SETP 3-4 0
    mov   eax, __?float32?__(%1)
    movd  xmm0, eax
    mov   eax, __?float32?__(%2)
    movd  xmm1, eax
    mov   eax, __?float32?__(%3)
    movd  xmm2, eax
    mov   r9d, %4
    call  h_set_player
%endmacro


; SETB x, y, z, block / GETB x, y, z -> eax
%macro SETB 4
    mov   ecx, %1
    mov   edx, %2
    mov   r8d, %3
    mov   r9d, %4
    call  h_setb
%endmacro
%macro GETB 3
    mov   ecx, %1
    mov   edx, %2
    mov   r8d, %3
    call  h_getb
%endmacro


; n x entity_tick_all / n x mobs_spawn_tick
%macro TICK 1
    mov   ecx, %1
    call  h_tick
%endmacro
%macro MOBTICKS 1
    mov   ecx, %1
    call  h_mobs_ticks
%endmacro


; COUNT kind -> eax, 0 counts everything
%macro COUNT 1
    mov   ecx, %1
    call  h_count
%endmacro


; all of these go through CHECK_TRUE so they count like any other check


; CHECK_CMP a, cc, b, "msg". cc picks signed/unsigned (g l ge le a b ne e)
%macro CHECK_CMP 4
    mov   eax, %1
    cmp   eax, %3
    mov   ecx, 0
    set%2 cl
    CHECK_TRUE ecx, %4
%endmacro

; float vs literal. comiss sets CF/ZF on NaN so seta/setae fail it, which is what we want
%macro CHECK_FGT 3
    movss xmm0, %1
    mov   eax, __?float32?__(%2)
    movd  xmm1, eax
    xor   ecx, ecx
    comiss xmm0, xmm1
    seta  cl
    CHECK_TRUE ecx, %3
%endmacro
%macro CHECK_FGE 3
    movss xmm0, %1
    mov   eax, __?float32?__(%2)
    movd  xmm1, eax
    xor   ecx, ecx
    comiss xmm0, xmm1
    setae cl
    CHECK_TRUE ecx, %3
%endmacro
%macro CHECK_FLT 3
    movss xmm0, %1
    mov   eax, __?float32?__(%2)
    movd  xmm1, eax
    xor   ecx, ecx
    comiss xmm1, xmm0
    seta  cl
    CHECK_TRUE ecx, %3
%endmacro
%macro CHECK_FLE 3
    movss xmm0, %1
    mov   eax, __?float32?__(%2)
    movd  xmm1, eax
    xor   ecx, ecx
    comiss xmm1, xmm0
    setae cl
    CHECK_TRUE ecx, %3
%endmacro


%macro CHECK_FLAG 3
    movzx eax, byte %1
    and   eax, %2
    CHECK_TRUE eax, %3
%endmacro
%macro CHECK_NOFLAG 3
    movzx eax, byte %1
    xor   ecx, ecx
    test  eax, %2
    setz  cl
    CHECK_TRUE ecx, %3
%endmacro

; exponent all ones = inf/nan
%macro CHECK_FINITE 2
    mov   eax, %1
    and   eax, 0x7F800000
    xor   ecx, ecx
    cmp   eax, 0x7F800000
    setne cl
    CHECK_TRUE ecx, %2
%endmacro

; tolerances for CHECK_NEAR, N decimal places
%define PLACES3 0.0005
%define PLACES4 0.00005
%define PLACES5 0.000005
%define PLACES7 0.00000005

%endif
