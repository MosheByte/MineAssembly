; test_raycast.asm - voxel DDA in raycast.asm vs a dumb reference on purpose:
; float64 slab test against every block box near the ray, nearest wins (ref_cast).
;
; @link src/physics.asm src/raycast.asm tests/player/fakeworld.asm tests/player/ptest.asm
; @timeout 180
%include "common.inc"
%include "testlib.inc"
%include "../player/ptest.inc"

section .rdata
align 8
; min xyz, max xyz per MODEL_*, should agree with player_cell_box
model_boxes:
    dq 0.0, 0.0, 0.0, 1.0, 1.0, 1.0                     ; MODEL_CUBE
    dq 0.125, 0.0, 0.125, 0.875, 0.8125, 0.875          ; MODEL_CROSS
    dq 0.375, 0.0, 0.375, 0.625, 0.625, 0.625           ; MODEL_TORCH
    dq 0.0, 0.0, 0.0, 1.0, 1.0, 1.0                     ; MODEL_LIQUID
    dq 0.0625, 0.0, 0.0625, 0.9375, 1.0, 0.9375         ; MODEL_CACTUS
    dq 0.3125, 0.0, 0.3125, 0.6875, 0.5625, 0.6875      ; MODEL_LANTERN
face_ofs:   dd 1,0,0, -1,0,0, 0,1,0, 0,-1,0, 0,0,1, 0,0,-1
; dir, face we expect to hit
axis_dirs:
    dd 1.0, 0.0, 0.0, FACE_NX
    dd -1.0, 0.0, 0.0, FACE_PX
    dd 0.0, 1.0, 0.0, FACE_NY
    dd 0.0, -1.0, 0.0, FACE_PY
    dd 0.0, 0.0, 1.0, FACE_NZ
    dd 0.0, 0.0, -1.0, FACE_PZ
palette:    db T_STONE, T_STONE, T_DIRT, T_TORCH, T_TALL_GRASS, T_CACTUS, T_LANTERN, T_WATER
modes:      dd 0, 0, 2, 3
maxds:      dd 4.5, 6.0, 12.0
align 8
d_big:      dq 1e30
d_tiny:     dq 1e-12
d_mabs:     dq 0x7FFFFFFFFFFFFFFF
d_one:      dq 1.0
d_two_pi:   dq 6.283185307179586

section .bss
alignb 16
ray_o:      resd 3
ray_d:      resd 3
hitout:      resb RAYHIT_size
ref_t:      resq 1                  ; double
ref_face:   resd 1
ref_cell:   resd 3
ref_block:  resd 1
rf_o:       resq 3                  ; doubles from here
rf_d:       resq 3                  ; normalised
rf_box:     resq 6
rf_maxd:    resq 1
rf_mode:    resd 1
rf_lo:      resd 3
rf_hi:      resd 3

section .text

%macro SETO 3.nolist
    SETF [rel ray_o], %1
    SETF [rel ray_o+4], %2
    SETF [rel ray_o+8], %3
%endmacro
%macro SETD 3.nolist
    SETF [rel ray_d], %1
    SETF [rel ray_d+4], %2
    SETF [rel ray_d+8], %3
%endmacro
%macro CAST 2.nolist
    FCONST xmm0, %1
    mov  ecx, %2
    call do_cast
%endmacro
; RCHECK x,y,z,face,dist,block   block -1 = don't care
%macro RCHECK 6.nolist
    mov  ecx, %1
    mov  edx, %2
    mov  r8d, %3
    mov  r9d, %4
    mov  dword [rsp+32], __?float32?__(%5)
    mov  dword [rsp+40], %6
    call rc_check
%endmacro

; also makes sure the return value agrees with out.hit, every cast
PROC do_cast, 0
    lea  r9, [rel hitout]
    mov  [r9+RAYHIT.hit], ecx
    movss xmm2, xmm0
    lea  rcx, [rel ray_o]
    lea  rdx, [rel ray_d]
    call raycast_blocks
    mov  ebx, eax
    mov  ecx, [rel hitout+RAYHIT.hit]
    cmp  eax, ecx
    je   .ok
    ICHK ebx, OP_EQ, [rel hitout+RAYHIT.hit], "raycast_blocks return == out.hit"
.ok:
    mov  eax, ebx
ENDP

PROC rc_check, 0
    mov  r12d, ecx
    mov  r13d, edx
    mov  r14d, r8d
    mov  r15d, r9d
    ICHK [rel hitout+RAYHIT.hit], OP_EQ, 1, "hit"
    ICHK [rel hitout+RAYHIT.x], OP_EQ, r12d, "cell x"
    ICHK [rel hitout+RAYHIT.y], OP_EQ, r13d, "cell y"
    ICHK [rel hitout+RAYHIT.z], OP_EQ, r14d, "cell z"
    ICHK [rel hitout+RAYHIT.face], OP_EQ, r15d, "face"
    lea  rbx, [rel face_ofs]
    lea  rsi, [r15+r15*2]
    mov  edi, [rbx+rsi*4]
    add  edi, r12d
    ICHK [rel hitout+RAYHIT.ax], OP_EQ, edi, "adjacent x"
    mov  edi, [rbx+rsi*4+4]
    add  edi, r13d
    ICHK [rel hitout+RAYHIT.ay], OP_EQ, edi, "adjacent y"
    mov  edi, [rbx+rsi*4+8]
    add  edi, r14d
    ICHK [rel hitout+RAYHIT.az], OP_EQ, edi, "adjacent z"
    movss xmm1, ARG5
    CHECK_NEAR_X [rel hitout+RAYHIT.dist], xmm1, 0.00005, "distance"
    cmp  dword ARG6, -1
    je   .done
    mov  edi, ARG6
    ICHK [rel hitout+RAYHIT.block], OP_EQ, edi, "block id"
.done:
ENDP

; plain slab test of rf_o/rf_d vs rf_box -> eax hit, xmm0 t (>= 0), edx face
PROC slab, 0
    lea  rsi, [rel rf_o]
    lea  rdi, [rel rf_d]
    lea  rbx, [rel rf_box]
    movsd xmm4, [rel d_big]
    movapd xmm5, xmm4                   ; tf
    xorpd xmm0, xmm0
    subsd xmm0, xmm4                    ; tn
    mov  r12d, -1                       ; entry axis
    xor  r13d, r13d
.axis:
    movsd xmm1, [rdi+r13*8]
    movapd xmm2, xmm1
    andpd xmm2, [rel d_mabs]
    comisd xmm2, [rel d_tiny]
    jae  .slope
    movsd xmm2, [rsi+r13*8]             ; parallel: o must be inside [lo, hi]
    comisd xmm2, [rbx+r13*8]
    jb   .miss
    comisd xmm2, [rbx+r13*8+24]
    ja   .miss
    jmp  .next
.slope:
    movsd xmm2, [rbx+r13*8]
    subsd xmm2, [rsi+r13*8]
    divsd xmm2, xmm1
    movsd xmm3, [rbx+r13*8+24]
    subsd xmm3, [rsi+r13*8]
    divsd xmm3, xmm1
    movapd xmm1, xmm2
    minsd xmm1, xmm3
    maxsd xmm2, xmm3
    comisd xmm1, xmm0
    jbe  .nolo
    movapd xmm0, xmm1
    mov  r12d, r13d
.nolo:
    minsd xmm5, xmm2
.next:
    inc  r13d
    cmp  r13d, 3
    jb   .axis
    comisd xmm0, xmm5
    ja   .miss
    xorpd xmm1, xmm1
    comisd xmm5, xmm1                   ; box is behind us
    jb   .miss
    mov  edx, FACE_PY
    test r12d, r12d
    js   .face_done
    lea  edx, [r12+r12]
    movsd xmm2, [rdi+r12*8]
    comisd xmm2, xmm1                   ; going + means we came in the low face
    jbe  .face_done
    inc  edx
.face_done:
    maxsd xmm0, xmm1                    ; started inside -> t 0
    mov  eax, 1
    jmp  .done
.miss:
    xor  eax, eax
.done:
ENDP

; floor, not truncate -> eax
%macro DFLOOR 1.nolist
    cvttsd2si eax, %1
    cvtsi2sd xmm3, eax
    comisd xmm3, %1
    jbe  %%ok
    dec  eax
%%ok:
%endmacro

PROC ref_cast, 32
    mov  [rel rf_mode], ecx
    cvtss2sd xmm0, xmm0
    movsd [rel rf_maxd], xmm0
    lea  rsi, [rel ray_d]
    lea  rdi, [rel rf_d]
    xorpd xmm1, xmm1
    xor  ecx, ecx
.n1:
    cvtss2sd xmm2, [rsi+rcx*4]
    movsd [rdi+rcx*8], xmm2
    mulsd xmm2, xmm2
    addsd xmm1, xmm2
    inc  ecx
    cmp  ecx, 3
    jb   .n1
    sqrtsd xmm1, xmm1
    xor  ecx, ecx
.n2:
    movsd xmm2, [rdi+rcx*8]
    divsd xmm2, xmm1
    movsd [rdi+rcx*8], xmm2
    lea  rax, [rel ray_o]
    cvtss2sd xmm2, [rax+rcx*4]
    lea  rax, [rel rf_o]
    movsd [rax+rcx*8], xmm2
    inc  ecx
    cmp  ecx, 3
    jb   .n2
    xor  ebx, ebx
.rng:
    lea  rax, [rel rf_o]
    movsd xmm0, [rax+rbx*8]
    lea  rax, [rel rf_d]
    movsd xmm1, [rax+rbx*8]
    mulsd xmm1, [rel rf_maxd]
    addsd xmm1, xmm0
    movapd xmm2, xmm0
    minsd xmm2, xmm1
    maxsd xmm0, xmm1
    DFLOOR xmm2
    dec  eax
    lea  rcx, [rel rf_lo]
    mov  [rcx+rbx*4], eax
    DFLOOR xmm0
    inc  eax
    lea  rcx, [rel rf_hi]
    mov  [rcx+rbx*4], eax
    inc  ebx
    cmp  ebx, 3
    jb   .rng
    ; y to 0..127
    mov  eax, [rel rf_lo+4]
    xor  ecx, ecx
    test eax, eax
    cmovs eax, ecx
    mov  [rel rf_lo+4], eax
    mov  eax, [rel rf_hi+4]
    mov  ecx, 127
    cmp  eax, ecx
    cmovg eax, ecx
    mov  [rel rf_hi+4], eax
    mov  dword LOC(0), 0                ; found
    mov  r12d, [rel rf_lo]
.lx:
    cmp  r12d, [rel rf_hi]
    jg   .end
    mov  r13d, [rel rf_lo+4]
.ly:
    cmp  r13d, [rel rf_hi+4]
    jg   .nx
    mov  r14d, [rel rf_lo+8]
.lz:
    cmp  r14d, [rel rf_hi+8]
    jg   .ny
    mov  ecx, r12d
    mov  edx, r13d
    mov  r8d, r14d
    call fw_get
    mov  r15d, eax
    lea  rcx, [rel blk_flags]
    movzx edx, word [rcx+r15*2]
    test edx, BF_SELECTABLE
    jnz  .ok
    cmp  dword [rel rf_mode], 2
    jl   .nz
    test edx, BF_LIQUID
    jz   .nz
    cmp  dword [rel rf_mode], 2
    je   .ok
    cmp  r15d, T_WATER                  ; mode 3: sources only
    je   .ok
    cmp  r15d, T_LAVA
    jne  .nz
.ok:
    lea  rcx, [rel blk_model]
    movzx eax, byte [rcx+r15]
    imul eax, eax, 48
    lea  rcx, [rel model_boxes]
    add  rcx, rax
    lea  rdx, [rel rf_box]
    cvtsi2sd xmm0, r12d
    cvtsi2sd xmm1, r13d
    cvtsi2sd xmm2, r14d
    movsd xmm3, [rcx]
    addsd xmm3, xmm0
    movsd [rdx], xmm3
    movsd xmm3, [rcx+8]
    addsd xmm3, xmm1
    movsd [rdx+8], xmm3
    movsd xmm3, [rcx+16]
    addsd xmm3, xmm2
    movsd [rdx+16], xmm3
    movsd xmm3, [rcx+24]
    addsd xmm3, xmm0
    movsd [rdx+24], xmm3
    movsd xmm3, [rcx+32]
    addsd xmm3, xmm1
    movsd [rdx+32], xmm3
    movsd xmm3, [rcx+40]
    addsd xmm3, xmm2
    movsd [rdx+40], xmm3
    call slab
    test eax, eax
    jz   .nz
    comisd xmm0, [rel rf_maxd]
    ja   .nz
    cmp  dword LOC(0), 0
    je   .take
    comisd xmm0, [rel ref_t]
    jae  .nz
.take:
    mov  dword LOC(0), 1
    movsd [rel ref_t], xmm0
    mov  [rel ref_face], edx
    mov  [rel ref_cell], r12d
    mov  [rel ref_cell+4], r13d
    mov  [rel ref_cell+8], r14d
    mov  [rel ref_block], r15d
.nz:
    inc  r14d
    jmp  .lz
.ny:
    inc  r13d
    jmp  .ly
.nx:
    inc  r12d
    jmp  .lx
.end:
    mov  eax, LOC(0)
ENDP

PROC test_main, 0
    call fw_setup_blocks
    call rc_straight_down
    call rc_axis_directions
    call rc_miss_and_reach
    call rc_unnormalised
    call rc_negative_coordinates
    call rc_torch_is_thin
    call rc_liquid_modes
    call rc_inside_block
    call rc_outside_world_band
    call rc_random_against_reference
ENDP

PROC rc_straight_down, 0
    TEST "raycast: straight down"
    call fw_clear
    SETB 3, 10, -4, T_STONE
    SETO 3.5, 12.62, -3.5
    SETD 0.0, -1.0, 0.0
    CAST 6.0, 0
    RCHECK 3, 10, -4, FACE_PY, 1.62, T_STONE
    CHECK_NEAR [rel hitout+RAYHIT.py], 11.0, 0.00005, "hit point y"
ENDP

PROC rc_axis_directions, 0
    TEST "raycast: axis directions"
    call fw_clear
    SETB 0, 20, 0, T_STONE
    lea  rbx, [rel axis_dirs]
    mov  r12d, 6
.l:
    ; start 3 back from the block centre
    FCONST xmm3, 3.0
    movss xmm0, [rbx]
    movss [rel ray_d], xmm0
    mulss xmm0, xmm3
    FCONST xmm1, 0.5
    subss xmm1, xmm0
    movss [rel ray_o], xmm1
    movss xmm0, [rbx+4]
    movss [rel ray_d+4], xmm0
    mulss xmm0, xmm3
    FCONST xmm1, 20.5
    subss xmm1, xmm0
    movss [rel ray_o+4], xmm1
    movss xmm0, [rbx+8]
    movss [rel ray_d+8], xmm0
    mulss xmm0, xmm3
    FCONST xmm1, 0.5
    subss xmm1, xmm0
    movss [rel ray_o+8], xmm1
    CAST 6.0, 0
    mov  r9d, [rbx+12]
    xor  ecx, ecx
    mov  edx, 20
    xor  r8d, r8d
    mov  dword [rsp+32], __?float32?__(2.5)
    mov  dword [rsp+40], -1
    call rc_check
    add  rbx, 16
    dec  r12d
    jnz  .l
ENDP

PROC rc_miss_and_reach, 0
    TEST "raycast: miss and reach"
    call fw_clear
    SETB 0, 10, 5, T_STONE
    SETO 0.5, 10.5, 0.5
    SETD 0.0, 0.0, 1.0
    CAST 4.0, 0
    ICHK [rel hitout+RAYHIT.hit], OP_EQ, 0, "block 4.5 away is out of reach 4"
    CAST 4.6, 0
    RCHECK 0, 10, 5, FACE_NZ, 4.5, -1
    SETD 0.0, 0.0, -1.0
    CAST 6.0, 0
    ICHK [rel hitout+RAYHIT.hit], OP_EQ, 0, "miss: hit"
    ICHK [rel hitout+RAYHIT.block], OP_EQ, 0, "miss: block"
    CHECK_NEAR [rel hitout+RAYHIT.dist], 6.0, 0.00000005, "miss: dist = maxd"
ENDP

PROC rc_unnormalised, 0
    TEST "raycast: unnormalised direction"
    call fw_clear
    SETB 0, 10, 5, T_STONE
    SETO 0.5, 10.5, 0.5
    SETD 0.0, 0.0, 7.0
    CAST 6.0, 0
    RCHECK 0, 10, 5, FACE_NZ, 4.5, -1
    SETD 0.0, 0.0, 0.0
    CAST 6.0, 0
    ICHK [rel hitout+RAYHIT.hit], OP_EQ, 0, "zero direction never hits"
ENDP

PROC rc_negative_coordinates, 0
    TEST "raycast: negative coordinates"
    call fw_clear
    SETB -5, 3, -9, T_DIRT
    SETO -1.3, 4.6, -2.2
    SETD -3.2, -1.1, -6.3               ; aims at the block centre
    CAST 20.0, 0
    ICHK [rel hitout+RAYHIT.x], OP_EQ, -5, "cell x"
    ICHK [rel hitout+RAYHIT.y], OP_EQ, 3, "cell y"
    ICHK [rel hitout+RAYHIT.z], OP_EQ, -9, "cell z"
    FCONST xmm0, 20.0
    xor  ecx, ecx
    call ref_cast
    ICHK eax, OP_EQ, 1, "reference finds the block"
    ICHK [rel hitout+RAYHIT.face], OP_EQ, [rel ref_face], "face == reference"
    cvtsd2ss xmm1, [rel ref_t]
    CHECK_NEAR_X [rel hitout+RAYHIT.dist], xmm1, 0.0005, "dist == reference"
ENDP

PROC rc_torch_is_thin, 0
    TEST "raycast: torch is thin"
    call fw_clear
    SETB 0, 10, 0, T_TORCH
    SETB 0, 10, -1, T_STONE
    SETO 0.15, 10.3, 2.5                ; misses the stick, hits the wall
    SETD 0.0, 0.0, -1.0
    CAST 6.0, 0
    RCHECK 0, 10, -1, FACE_PZ, 2.5, T_STONE
    SETO 0.5, 10.3, 2.5                 ; +Z face is at z=0.625
    CAST 6.0, 0
    RCHECK 0, 10, 0, FACE_PZ, 1.875, T_TORCH
    SETO 0.5, 12.0, 0.5                 ; top at 10.625
    SETD 0.0, -1.0, 0.0
    CAST 6.0, 0
    RCHECK 0, 10, 0, FACE_PY, 1.375, T_TORCH
ENDP

PROC rc_liquid_modes, 0
    TEST "raycast: liquid modes"
    call fw_clear
    SETB 0, 10, 0, T_WATER_FLOW
    SETB 0, 9, 0, T_WATER
    SETB 0, 8, 0, T_STONE
    SETO 0.5, 12.5, 0.5
    SETD 0.0, -1.0, 0.0
    CAST 6.0, 0
    RCHECK 0, 8, 0, FACE_PY, 3.5, T_STONE
    CAST 6.0, 2
    RCHECK 0, 10, 0, FACE_PY, 1.5, T_WATER_FLOW
    CAST 6.0, 3
    RCHECK 0, 9, 0, FACE_PY, 2.5, T_WATER
ENDP

PROC rc_inside_block, 0
    TEST "raycast: inside block"
    call fw_clear
    SETB 0, 10, 0, T_STONE
    SETO 0.5, 10.5, 0.5
    SETD 0.3, -0.2, 0.9
    CAST 6.0, 0
    ICHK [rel hitout+RAYHIT.hit], OP_EQ, 1, "hit"
    ICHK [rel hitout+RAYHIT.x], OP_EQ, 0, "x"
    ICHK [rel hitout+RAYHIT.y], OP_EQ, 10, "y"
    ICHK [rel hitout+RAYHIT.z], OP_EQ, 0, "z"
    FCHK [rel hitout+RAYHIT.dist], OP_EQ, 0.0, "dist 0"
ENDP

PROC rc_outside_world_band, 0
    TEST "raycast: outside world band"
    call fw_clear
    SETO 0.5, 2.0, 0.5
    SETD 0.0, -1.0, 0.0
    CAST 6.0, 0
    ICHK [rel hitout+RAYHIT.hit], OP_EQ, 0, "no bedrock below 0"
    SETO 0.5, 130.0, 0.5
    SETD 0.0, 1.0, 0.0
    CAST 6.0, 0
    ICHK [rel hitout+RAYHIT.hit], OP_EQ, 0, "nothing above the world"
ENDP

; 4000 random rays, 900 random blocks. edge/corner ties make exact compares
; flaky so cells only have to match most of the time (> 1000)
%define RL_MODE  0
%define RL_MAXD  4
%define RL_TH    8
%define RL_PH    16
%define RL_TMP   24
PROCX rc_random_against_reference, 64
    TEST "raycast: random against reference"
    call fw_clear
    mov  ecx, 99
    call t_rng_seed
    mov  r12d, 900
.blk:
    mov  ecx, -10
    mov  edx, 9
    call pt_rand_int
    mov  ebx, eax
    xor  ecx, ecx
    mov  edx, 19
    call pt_rand_int
    mov  esi, eax
    mov  ecx, -10
    mov  edx, 9
    call pt_rand_int
    mov  edi, eax
    xor  ecx, ecx
    mov  edx, 7
    call pt_rand_int
    lea  rcx, [rel palette]
    movzx r9d, byte [rcx+rax]
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    call fw_set
    dec  r12d
    jnz  .blk

    xor  r12d, r12d
    xor  r13d, r13d                     ; exact cell matches
.ray:
    mov  rax, __?float64?__(-9.0)
    movq xmm0, rax
    mov  rax, __?float64?__(9.0)
    movq xmm1, rax
    call pt_rand_uniform
    cvtsd2ss xmm0, xmm0
    movss [rel ray_o], xmm0
    mov  rax, __?float64?__(0.5)
    movq xmm0, rax
    mov  rax, __?float64?__(19.0)
    movq xmm1, rax
    call pt_rand_uniform
    cvtsd2ss xmm0, xmm0
    movss [rel ray_o+4], xmm0
    mov  rax, __?float64?__(-9.0)
    movq xmm0, rax
    mov  rax, __?float64?__(9.0)
    movq xmm1, rax
    call pt_rand_uniform
    cvtsd2ss xmm0, xmm0
    movss [rel ray_o+8], xmm0
    ; yaw th in [0, 2pi), pitch ph in [-1.5, 1.5]
    xorpd xmm0, xmm0
    movsd xmm1, [rel d_two_pi]
    call pt_rand_uniform
    movsd LOC(RL_TH), xmm0
    mov  rax, __?float64?__(-1.5)
    movq xmm0, rax
    mov  rax, __?float64?__(1.5)
    movq xmm1, rax
    call pt_rand_uniform
    movsd LOC(RL_PH), xmm0
    ; d = (cos ph sin th, sin ph, -cos ph cos th), x87 because sse has no sin
    fld  qword LOC(RL_PH)
    fsincos
    fld  qword LOC(RL_TH)
    fsincos                             ; cos th, sin th, cos ph, sin ph
    fmul st0, st2
    fchs
    fstp dword [rel ray_d+8]
    fmul st0, st1
    fstp dword [rel ray_d]
    fstp st0
    fstp dword [rel ray_d+4]
    ; 15% of rays get some components zeroed, axis/planar rays are the DDA edge cases
    call t_rng_float
    FCONST xmm1, 0.15
    comiss xmm0, xmm1
    jae  .dir_ok
    xor  ebx, ebx
.zc:
    call t_rng_float
    FCONST xmm1, 0.5
    comiss xmm0, xmm1
    jae  .keep
    lea  rax, [rel ray_d]
    mov  dword [rax+rbx*4], 0
.keep:
    inc  ebx
    cmp  ebx, 3
    jb   .zc
    mov  eax, [rel ray_d]
    or   eax, [rel ray_d+4]
    or   eax, [rel ray_d+8]
    and  eax, 0x7FFFFFFF                ; -0.0 too
    jz   .next                          ; all zero, skip it
.dir_ok:
    xor  ecx, ecx
    mov  edx, 3
    call pt_rand_int
    lea  rcx, [rel modes]
    mov  eax, [rcx+rax*4]
    mov  LOC(RL_MODE), eax
    xor  ecx, ecx
    mov  edx, 2
    call pt_rand_int
    lea  rcx, [rel maxds]
    mov  eax, [rcx+rax*4]
    mov  LOC(RL_MAXD), eax

    movss xmm0, LOC(RL_MAXD)
    mov  ecx, LOC(RL_MODE)
    call do_cast
    movss xmm0, LOC(RL_MAXD)
    mov  ecx, LOC(RL_MODE)
    call ref_cast
    mov  ebx, eax
    movss xmm7, LOC(RL_MAXD)
    FCONST xmm1, 0.001
    subss xmm7, xmm1                    ; anything past this is a reach-limit coin flip
    test ebx, ebx
    jnz  .have_ref
    cmp  dword [rel hitout+RAYHIT.hit], 0
    je   .next
    FCHKX [rel hitout+RAYHIT.dist], OP_GT, xmm7, "hit without reference only at the reach limit"
    jmp  .next
.have_ref:
    cvtsd2ss xmm8, [rel ref_t]
    cmp  dword [rel hitout+RAYHIT.hit], 0
    jne  .both
    FCHKX xmm8, OP_GT, xmm7, "missed a reference block only at the reach limit"
    jmp  .next
.both:
    movss xmm0, [rel hitout+RAYHIT.dist]
    subss xmm0, xmm8
    andps xmm0, [rel f_abs]
    FCHK xmm0, OP_LE, 0.002, "dist == reference within 2e-3"
    ; different cell = edge/corner tie, nothing else to compare
    mov  eax, [rel hitout+RAYHIT.x]
    cmp  eax, [rel ref_cell]
    jne  .next
    mov  eax, [rel hitout+RAYHIT.y]
    cmp  eax, [rel ref_cell+4]
    jne  .next
    mov  eax, [rel hitout+RAYHIT.z]
    cmp  eax, [rel ref_cell+8]
    jne  .next
    inc  r13d
    ; face is only well defined away from edges and on full cubes
    movss xmm0, [rel hitout+RAYHIT.dist]
    andps xmm0, [rel f_abs]
    FCONST xmm1, 0.0001
    comiss xmm0, xmm1
    jbe  .block
    xor  ebx, ebx                       ; near-integer coords, 2+ = on an edge
    xor  esi, esi
.fx:
    lea  rax, [rel hitout+RAYHIT.px]
    cvtss2sd xmm0, [rax+rsi*4]
    cvtsd2si rax, xmm0
    cvtsi2sd xmm1, rax
    subsd xmm0, xmm1
    andpd xmm0, [rel d_mabs]
    mov  rax, __?float64?__(0.002)
    movq xmm1, rax
    comisd xmm0, xmm1
    jae  .fx_no
    inc  ebx
.fx_no:
    inc  esi
    cmp  esi, 3
    jb   .fx
    cmp  ebx, 1
    ja   .block
    mov  eax, [rel ref_block]
    lea  rcx, [rel blk_model]
    movzx eax, byte [rcx+rax]
    cmp  eax, MODEL_CUBE
    je   .face
    cmp  eax, MODEL_LIQUID
    jne  .block
.face:
    ICHK [rel hitout+RAYHIT.face], OP_EQ, [rel ref_face], "face == reference"
.block:
    ICHK [rel hitout+RAYHIT.block], OP_EQ, [rel ref_block], "block == reference"
    ; hit point has to be o + dn*dist
    xor  esi, esi
.pt:
    lea  rax, [rel ray_o]
    cvtss2sd xmm0, [rax+rsi*4]
    lea  rax, [rel rf_d]
    movsd xmm1, [rax+rsi*8]
    cvtss2sd xmm2, [rel hitout+RAYHIT.dist]
    mulsd xmm1, xmm2
    addsd xmm0, xmm1
    lea  rax, [rel hitout+RAYHIT.px]
    cvtss2sd xmm1, [rax+rsi*4]
    subsd xmm1, xmm0
    andpd xmm1, [rel d_mabs]
    cvtsd2ss xmm0, xmm1
    FCHK xmm0, OP_LE, 0.001, "hit point on the ray"
    inc  esi
    cmp  esi, 3
    jb   .pt
.next:
    inc  r12d
    cmp  r12d, 4000
    jb   .ray
    ICHK r13d, OP_GT, 1000, "rays compared cell-exactly"
ENDPX

section .rdata
align 16
f_abs: dd 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF

