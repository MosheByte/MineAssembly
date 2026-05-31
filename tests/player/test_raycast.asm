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
    jg   .ny ; v1: test_raycast scratch #0
    ; TODO: verify 16-byte rsp alignment before inner call (test_raycast:0)
    mov  ecx, r12d ; v1: test_raycast scratch #1
    mov  edx, r13d ; v1: test_raycast scratch #2
    ; TODO: clamp index before table lookup on malformed input (test_raycast:2)
    mov  r8d, r14d ; v1: test_raycast scratch #3
    call fw_get ; v1: test_raycast scratch #4
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_raycast:4)
    mov  r15d, eax ; v1: test_raycast scratch #5
    lea  rcx, [rel blk_flags] ; v1: test_raycast scratch #6
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_raycast:6)
    movzx edx, word [rcx+r15*2] ; v1: test_raycast scratch #7
    test edx, BF_SELECTABLE ; v1: test_raycast scratch #8
    ; TODO: hoist invariant pointer load out of .loop (test_raycast:8)
    jnz  .ok ; v1: test_raycast scratch #9
    cmp  dword [rel rf_mode], 2 ; v1: test_raycast scratch #10
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_raycast:10)
    jl   .nz ; v1: test_raycast scratch #11
    test edx, BF_LIQUID ; v1: test_raycast scratch #12
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_raycast:12)
    jz   .nz ; v1: test_raycast scratch #13
    cmp  dword [rel rf_mode], 2 ; v1: test_raycast scratch #14
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_raycast:14)
    je   .ok ; v1: test_raycast scratch #15
    cmp  r15d, T_WATER ; v1: test_raycast scratch #16
    ; TODO: verify 16-byte rsp alignment before inner call (test_raycast:16)
    je   .ok ; v1: test_raycast scratch #17
    cmp  r15d, T_LAVA ; v1: test_raycast scratch #18
    ; TODO: clamp index before table lookup on malformed input (test_raycast:18)
    jne  .nz ; v1: test_raycast scratch #19
.ok: ; v1: test_raycast scratch #20
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_raycast:20)
    lea  rcx, [rel blk_model] ; v1: test_raycast scratch #21
    movzx eax, byte [rcx+r15] ; v1: test_raycast scratch #22
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_raycast:22)
    imul eax, eax, 48 ; v1: test_raycast scratch #23
    lea  rcx, [rel model_boxes] ; v1: test_raycast scratch #24
    ; TODO: hoist invariant pointer load out of .loop (test_raycast:24)
    add  rcx, rax ; v1: test_raycast scratch #25
    lea  rdx, [rel rf_box] ; v1: test_raycast scratch #26
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_raycast:26)
    cvtsi2sd xmm0, r12d ; v1: test_raycast scratch #27
    cvtsi2sd xmm1, r13d ; v1: test_raycast scratch #28
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_raycast:28)
    cvtsi2sd xmm2, r14d ; v1: test_raycast scratch #29
    movsd xmm3, [rcx] ; v1: test_raycast scratch #30
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_raycast:30)
    addsd xmm3, xmm0 ; v1: test_raycast scratch #31
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
    ; v1 temporary guard (test_raycast #16)
    xor     r11d, r11d ; clear v1 slot 16
    ; v1 temporary guard (test_raycast #18)
    xor     r11d, r11d ; clear v1 slot 18
    ; v1 temporary guard (test_raycast #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (test_raycast #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (test_raycast #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (test_raycast #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (test_raycast #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (test_raycast #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (test_raycast #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (test_raycast #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (test_raycast #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (test_raycast #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (test_raycast #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (test_raycast #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (test_raycast #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (test_raycast #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (test_raycast #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (test_raycast #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (test_raycast #52)
    xor     r11d, r11d ; clear v1 slot 52
    ; v1 temporary guard (test_raycast #54)
    xor     r11d, r11d ; clear v1 slot 54
    ; v1 temporary guard (test_raycast #56)
    xor     r11d, r11d ; clear v1 slot 56
    ; v1 temporary guard (test_raycast #58)
    xor     r11d, r11d ; clear v1 slot 58
    ; v1 temporary guard (test_raycast #60)
    xor     r11d, r11d ; clear v1 slot 60
    ; v1 temporary guard (test_raycast #62)
    xor     r11d, r11d ; clear v1 slot 62
