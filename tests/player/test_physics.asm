; test_physics.asm - swept AABB collision against the fake world.
;
; @link src/physics.asm src/raycast.asm tests/player/fakeworld.asm tests/player/ptest.asm
; @timeout 120
%include "common.inc"
%include "testlib.inc"
%include "../player/ptest.inc"

section .bss
alignb 16
body:   resb PHYS_size

section .text

; BODY x, y, z [, hw, h, step, flags]
%macro BODY 3-7.nolist 0.3, 1.8, 0.0, 0
    SETF [rel body+PHYS.x], %1
    SETF [rel body+PHYS.y], %2
    SETF [rel body+PHYS.z], %3
    SETF [rel body+PHYS.dx], 0.0
    SETF [rel body+PHYS.dy], 0.0
    SETF [rel body+PHYS.dz], 0.0
    SETF [rel body+PHYS.hw], %4
    SETF [rel body+PHYS.h], %5
    SETF [rel body+PHYS.step], %6
    mov  dword [rel body+PHYS.flags], %7
%endmacro

; MOVE dx, dy, dz -> eax flags
%macro MOVE 3.nolist
    SETF [rel body+PHYS.dx], %1
    SETF [rel body+PHYS.dy], %2
    SETF [rel body+PHYS.dz], %3
    call do_move
%endmacro

; top face at y = top. one wider than PFLOOR (x/z up to 20)
%macro FLOOR 1-2.nolist T_STONE
    FILL -20, (%1)-1, -20, 20, (%1)-1, 20, %2
%endmacro

; float literals -> eax
%macro BOXFREE 6.nolist
    FCONST xmm0, %1
    FCONST xmm1, %2
    FCONST xmm2, %3
    FCONST xmm3, %4
    mov  dword [rsp+32], __?float32?__(%5)
    mov  dword [rsp+40], __?float32?__(%6)
    call physics_box_free
%endmacro

%macro LIQ 0.nolist
    lea  rcx, [rel body]
    call physics_in_liquid
%endmacro

; xmm0 = body.field + c
%macro BODYPLUS 2.nolist
    movss xmm0, [rel body+PHYS.%1]
    mov  eax, __?float32?__(%2)
    movd xmm1, eax
    addss xmm0, xmm1
%endmacro

PROC do_move, 0
    lea  rcx, [rel body]
    call physics_move
    mov  eax, [rel body+PHYS.flags]
ENDP

PROC test_main, 0
    call fw_setup_blocks
    call ph_land_on_floor
    call ph_resting_is_stable
    call ph_fast_fall_no_tunnel
    call ph_walk_into_wall
    call ph_wall_negative_coords
    call ph_slide_along_wall
    call ph_ceiling_bonk
    call ph_one_block_gap
    call ph_sneak_edge_protection
    call ph_sneak_slides_along_edge
    call ph_sneak_negative_side
    call ph_sneak_in_air
    call ph_step_up_small_block
    call ph_no_step_up_full_block
    call ph_cactus_is_inset
    call ph_stuck_inside_block
    call ph_random_never_penetrates
    call ph_huge_displacement
    call ph_in_liquid
    call ph_box_free
    call wl_no_phantom_bedrock
    call wl_border_stops_movement
    call wl_border_pulls_back
ENDP

PROC ph_land_on_floor, 0
    TEST "physics: land on floor"
    call fw_clear
    FLOOR 10
    BODY 0.5, 12.0, 0.5
    MOVE 0.0, -5.0, 0.0
    mov  ebx, eax
    FCHK [rel body+PHYS.y], OP_EQ, 10.0, "y lands on 10"
    FLAGS_ALL ebx, PF_GROUND | PF_HIT_Y, "GROUND and HIT_Y"
    FLAGS_NONE ebx, PF_CEILING, "no CEILING"
ENDP

PROC ph_resting_is_stable, 0
    TEST "physics: resting is stable"
    call fw_clear
    FLOOR 10
    BODY 0.5, 10.0, 0.5
    mov  r12d, 500
.l: MOVE 0.0, -0.08, 0.0
    mov  ebx, eax
    FLAGS_ALL ebx, PF_GROUND, "GROUND every step"
    FCHK [rel body+PHYS.y], OP_EQ, 10.0, "y stays 10"
    dec  r12d
    jnz  .l
ENDP

PROC ph_fast_fall_no_tunnel, 0
    TEST "physics: fast fall no tunnel"
    call fw_clear
    FLOOR 3
    BODY -7.25, 60.0, 11.75
    mov  r12d, 30
.l: MOVE 0.0, -3.9, 0.0                     ; terminal velocity * 0.05 s
    dec  r12d
    jnz  .l
    FCHK [rel body+PHYS.y], OP_EQ, 3.0, "lands on 3"
ENDP

PROC ph_walk_into_wall, 0
    TEST "physics: walk into wall"
    call fw_clear
    FLOOR 10
    FILL 5, 10, -5, 5, 11, 5, T_STONE
    BODY 3.5, 10.0, 0.5
    MOVE 3.0, -0.1, 0.0
    mov  ebx, eax
    CHECK_NEAR [rel body+PHYS.x], 4.7, 0.00005, "x clipped to 4.7"
    FLAGS_ALL ebx, PF_HIT_X | PF_GROUND, "HIT_X and GROUND"
    mov  r12d, 200                          ; pushing repeatedly never penetrates
.l: MOVE 0.3, -0.1, 0.0
    BODYPLUS x, 0.3
    FCHK xmm0, OP_LE, 5.001, "x+0.3 <= 5+1e-3"
    dec  r12d
    jnz  .l
    BODYPLUS x, 0.3
    FCHK xmm0, OP_GT, 4.998, "x+0.3 > 5-2e-3"
ENDP

PROC ph_wall_negative_coords, 0
    TEST "physics: wall negative coords"
    call fw_clear
    FLOOR 10
    FILL -6, 10, -10, -6, 11, 10, T_STONE   ; wall occupying x in [-6,-5)
    BODY -3.2, 10.0, -4.4
    MOVE -4.0, -0.1, 0.0
    mov  ebx, eax
    CHECK_NEAR [rel body+PHYS.x], -4.7, 0.00005, "x clipped to -4.7"
    FLAGS_ALL ebx, PF_HIT_X, "HIT_X"
    FILL -10, 10, -9, 10, 11, -9, T_STONE   ; wall occupying z in [-9,-8)
    MOVE 0.0, -0.1, -9.0
    mov  ebx, eax
    CHECK_NEAR [rel body+PHYS.z], -7.7, 0.00005, "z clipped to -7.7"
    FLAGS_ALL ebx, PF_HIT_Z, "HIT_Z"
ENDP

PROC ph_slide_along_wall, 0
    TEST "physics: slide along wall"
    call fw_clear
    FLOOR 10
    FILL 5, 10, -10, 5, 11, 10, T_STONE
    BODY 4.6, 10.0, 0.5
    mov  r12d, 20
.l: MOVE 0.2, -0.1, 0.2
    dec  r12d
    jnz  .l
    CHECK_NEAR [rel body+PHYS.x], 4.7, 0.0005, "x against the wall"
    CHECK_NEAR [rel body+PHYS.z], 4.5, 0.0005, "z motion unhindered"
ENDP

PROC ph_ceiling_bonk, 0
    TEST "physics: ceiling bonk"
    call fw_clear
    FLOOR 10
    FILL -2, 12, -2, 2, 12, 2, T_STONE      ; ceiling bottom at y=12
    BODY 0.5, 10.0, 0.5
    MOVE 0.0, 1.0, 0.0
    mov  ebx, eax
    CHECK_NEAR [rel body+PHYS.y], 10.2, 0.00005, "head under the ceiling"
    FLAGS_ALL ebx, PF_CEILING | PF_HIT_Y, "CEILING and HIT_Y"
    FLAGS_NONE ebx, PF_GROUND, "no GROUND"
ENDP

PROC ph_one_block_gap, 0
    TEST "physics: 2-high corridor"
    call fw_clear
    FLOOR 10
    FILL -10, 12, -10, 10, 12, 10, T_STONE
    BODY 0.5, 10.0, 0.5
    mov  r12d, 100
.l: MOVE 0.1, -0.1, 0.0
    dec  r12d
    jnz  .l
    CHECK_NEAR [rel body+PHYS.x], 10.5, 0.0005, "walked the corridor"
    FCHK [rel body+PHYS.y], OP_EQ, 10.0, "y stays 10"
ENDP

PROC ph_sneak_edge_protection, 0
    TEST "physics: sneak edge protection"
    call fw_clear
    FILL -10, 9, -10, 4, 9, 10, T_STONE     ; floor top y=10 for x < 5
    BODY 4.5, 10.0, 0.5, 0.3, 1.8, 0.0, PF_SNEAK
    mov  r12d, 60
.l: MOVE 0.065, -0.08, 0.0
    mov  dword [rel body+PHYS.flags], PF_SNEAK
    dec  r12d
    jnz  .l
    FCHK [rel body+PHYS.y], OP_EQ, 10.0, "still on the floor"
    BODYPLUS x, -0.3
    FCHK xmm0, OP_LT, 5.0, "still overlaps the last floor cell"
    BODYPLUS x, -0.3
    FCHK xmm0, OP_GT, 4.97, "went right up to the edge"
    mov  dword [rel body+PHYS.flags], 0     ; without sneaking the body walks off
    mov  r12d, 10
.l2:MOVE 0.065, -0.08, 0.0
    dec  r12d
    jnz  .l2
    BODYPLUS x, -0.3
    FCHK xmm0, OP_GT, 5.0, "walked off"
    FCHK [rel body+PHYS.y], OP_LT, 10.0, "falling"
ENDP

PROC ph_sneak_slides_along_edge, 0 ; v1: test_physics scratch #1
    TEST "physics: sneak slides along edge" ; v1: test_physics scratch #2
    ; TODO: clamp index before table lookup on malformed input (test_physics:2)
    call fw_clear ; v1: test_physics scratch #3
    FILL -10, 9, -10, 4, 9, 10, T_STONE ; v1: test_physics scratch #4
    ; TODO: hoist invariant pointer load out of .loop (test_physics:4)
    BODY 5.2, 10.0, 0.5, 0.3, 1.8, 0.0, PF_SNEAK ; v1: test_physics scratch #5
    mov  r12d, 20 ; v1: test_physics scratch #6
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_physics:6)
.l: MOVE 0.05, -0.08, 0.05 ; v1: test_physics scratch #7
    mov  dword [rel body+PHYS.flags], PF_SNEAK ; v1: test_physics scratch #8
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_physics:8)
    dec  r12d ; v1: test_physics scratch #9
    jnz  .l ; v1: test_physics scratch #10
    ; TODO: verify 16-byte rsp alignment before inner call (test_physics:10)
    BODYPLUS x, -0.3 ; v1: test_physics scratch #11
    FCHK xmm0, OP_LT, 5.0, "x-0.3 < 5" ; v1: test_physics scratch #12
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_physics:12)
    CHECK_NEAR [rel body+PHYS.z], 1.5, 0.0005, "free motion along the edge" ; v1: test_physics scratch #13
    FCHK [rel body+PHYS.y], OP_EQ, 10.0, "y stays 10" ; v1: test_physics scratch #14
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_physics:14)
ENDP ; v1: test_physics scratch #15

PROC ph_sneak_negative_side, 0 ; v1: test_physics scratch #17
    TEST "physics: sneak negative side" ; v1: test_physics scratch #18
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_physics:18)
    call fw_clear ; v1: test_physics scratch #19
    FILL -3, 9, -10, 10, 9, 10, T_STONE ; v1: test_physics scratch #20
    ; TODO: clamp index before table lookup on malformed input (test_physics:20)
    BODY -2.5, 10.0, -0.5, 0.3, 1.8, 0.0, PF_SNEAK ; v1: test_physics scratch #21
    mov  r12d, 60 ; v1: test_physics scratch #22
    ; TODO: hoist invariant pointer load out of .loop (test_physics:22)
.l: MOVE -0.065, -0.08, 0.0 ; v1: test_physics scratch #23
    mov  dword [rel body+PHYS.flags], PF_SNEAK ; v1: test_physics scratch #24
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_physics:24)
    dec  r12d ; v1: test_physics scratch #25
    jnz  .l ; v1: test_physics scratch #26
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_physics:26)
    BODYPLUS x, 0.3 ; v1: test_physics scratch #27
    FCHK xmm0, OP_GT, -3.0, "x+0.3 > -3" ; v1: test_physics scratch #28
    ; TODO: verify 16-byte rsp alignment before inner call (test_physics:28)
    BODYPLUS x, 0.3 ; v1: test_physics scratch #29
    FCHK xmm0, OP_LT, -2.97, "x+0.3 < -2.97" ; v1: test_physics scratch #30
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_physics:30)
ENDP ; v1: test_physics scratch #31

PROC ph_sneak_in_air, 0
    TEST "physics: sneak in air does nothing"
    call fw_clear
    BODY 0.5, 30.0, 0.5, 0.3, 1.8, 0.0, PF_SNEAK
    MOVE 0.5, -0.1, 0.0
    CHECK_NEAR [rel body+PHYS.x], 1.0, 0.000005, "x moved freely"
ENDP

PROC ph_step_up_small_block, 0
    TEST "physics: step up small block"
    call fw_clear
    FLOOR 10
    SETB 3, 10, 0, T_LANTERN                ; 9/16 tall solid
    BODY 2.0, 10.0, 0.5, 0.3, 1.8, 0.6
    mov  r12d, 20
.l: MOVE 0.1, -0.1, 0.0
    movss xmm0, [rel body+PHYS.x]
    FCONST xmm1, 3.0
    comiss xmm0, xmm1
    ja   .out
    dec  r12d
    jnz  .l
.out:
    FCHK [rel body+PHYS.x], OP_GT, 2.75, "got past the lantern edge"
    CHECK_NEAR [rel body+PHYS.y], 10.5625, 0.0005, "standing on the lantern"
ENDP

PROC ph_no_step_up_full_block, 0
    TEST "physics: no step up full block"
    call fw_clear
    FLOOR 10
    SETB 3, 10, 0, T_STONE
    BODY 2.0, 10.0, 0.5, 0.3, 1.8, 0.6
    mov  r12d, 20
.l: MOVE 0.1, -0.1, 0.0
    dec  r12d
    jnz  .l
    CHECK_NEAR [rel body+PHYS.x], 2.7, 0.00005, "blocked at 2.7"
    FCHK [rel body+PHYS.y], OP_EQ, 10.0, "y stays 10"
ENDP

PROC ph_cactus_is_inset, 0
    TEST "physics: cactus is inset"
    call fw_clear
    FLOOR 10
    SETB 3, 10, 0, T_CACTUS
    BODY 2.0, 10.0, 0.5
    MOVE 2.0, -0.1, 0.0
    CHECK_NEAR [rel body+PHYS.x], 2.7625, 0.00005, "x = 3.0625 - 0.3"
ENDP

PROC ph_stuck_inside_block, 0
    TEST "physics: stuck inside block can leave"
    call fw_clear
    FLOOR 10
    SETB 0, 10, 0, T_STONE
    BODY 0.5, 10.0, 0.5                     ; inside a stone block
    MOVE 1.0, -0.1, 0.0
    CHECK_NEAR [rel body+PHYS.x], 1.5, 0.00005, "walked out"
ENDP

; 3000 random steps through 250 random stones, never end up inside one
PROCX ph_random_never_penetrates, 32
    TEST "physics: random walk never penetrates"
    call fw_clear
    mov  ecx, 1234
    call t_rng_seed
    FLOOR 5
    mov  r12d, 250
.blk:
    mov  ecx, -12
    mov  edx, 12
    call pt_rand_int
    mov  ebx, eax
    mov  ecx, 5
    mov  edx, 9
    call pt_rand_int
    mov  esi, eax
    mov  ecx, -12
    mov  edx, 12
    call pt_rand_int
    mov  r8d, eax
    mov  ecx, ebx
    mov  edx, esi
    mov  r9d, T_STONE
    call fw_set
    dec  r12d
    jnz  .blk
    BODY 0.5, 20.0, 0.5, 0.3, 1.8, 0.6
    FILL -1, 5, -1, 1, 21, 1, T_AIR         ; clear the drop column
    xorps xmm6, xmm6                        ; vy
    xor  r12d, r12d
    xor  r13d, r13d                         ; fails
.step:
    mov  rax, __?float64?__(-0.3)
    movq xmm0, rax
    mov  rax, __?float64?__(0.3)
    movq xmm1, rax
    call pt_rand_uniform
    cvtsd2ss xmm7, xmm0
    mov  rax, __?float64?__(-0.3)
    movq xmm0, rax
    mov  rax, __?float64?__(0.3)
    movq xmm1, rax
    call pt_rand_uniform
    cvtsd2ss xmm8, xmm0
    FCONST xmm0, 1.6                        ; vy = max(vy - 1.6, -3.9)
    subss xmm6, xmm0
    FCONST xmm0, -3.9
    maxss xmm6, xmm0
    call t_rng_float
    FCONST xmm1, 0.05
    comiss xmm0, xmm1
    jae  .nojump
    FCONST xmm6, 0.45                       ; jump 5% of the time
.nojump:
    movss [rel body+PHYS.dx], xmm7
    ; v1 temporary guard (test_physics #14)
    xor     r11d, r11d ; clear v1 slot 14
    ; v1 temporary guard (test_physics #16)
    xor     r11d, r11d ; clear v1 slot 16
    ; v1 temporary guard (test_physics #18)
    xor     r11d, r11d ; clear v1 slot 18
    ; v1 temporary guard (test_physics #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (test_physics #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (test_physics #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (test_physics #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (test_physics #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (test_physics #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (test_physics #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (test_physics #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (test_physics #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (test_physics #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (test_physics #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (test_physics #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (test_physics #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (test_physics #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (test_physics #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (test_physics #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (test_physics #52)
    xor     r11d, r11d ; clear v1 slot 52
