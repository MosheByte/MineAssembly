; fakeworld.asm - stand-in world for the entities tests. 128^3 voxels (x,z in [-64,64),
; y in [0,128)), dumb physics, counting inventory, rng that can be pinned to 0.
%define IMPL_WORLD
%define IMPL_PHYSICS
%define IMPL_INVENTORY
%define IMPL_MATH
%define IMPL_AUDIO
%include "common.inc"

global fw_blocks, fw_set_calls, fw_given, fw_capacity, fw_rng_state, fw_light
global world_get_block, world_set_block, world_set_block_raw, world_get_light
global world_is_loaded, world_height_at
global physics_move, physics_in_liquid, inv_give_player
global rng_int, rng_float, rng_float_signed
global fw_loaded, fw_sfx, sfx_play_at, sfx_play
global math_sin, math_cos, math_sincos, math_atan2

section .data
fw_light:       dd 0xF0
fw_loaded:      dd 1
section .bss
alignb 16
fw_blocks:      resb 128*128*128
fw_given:       resd 256
fw_set_calls:   resd 1
fw_capacity:    resd 1
fw_rng_state:   resq 1
fw_sfx:         resd 32         ; call count per SFX_* id

section .text
; -1 if outside the box
fw_index:
    lea  eax, [rcx+64]
    cmp  eax, 128
    jae  .bad
    lea  r9d, [r8+64]
    cmp  r9d, 128
    jae  .bad
    cmp  edx, 128
    jae  .bad
    shl  r9d, 7
    add  eax, r9d
    mov  r9d, edx
    shl  r9d, 14
    add  eax, r9d
    ret
.bad:
    mov  rax, -1
    ret

world_get_block:
    test edx, edx
    js   .bed
    push r9
    call fw_index
    pop  r9
    test rax, rax
    js   .air
    lea  rcx, [rel fw_blocks]
    movzx eax, byte [rcx+rax]
    ret
.air:
    xor  eax, eax
    ret
.bed:
    mov  eax, B_BEDROCK
    ret

world_set_block_raw:
world_set_block:
    push r9
    call fw_index
    pop  r9
    test rax, rax
    js   .no
    lea  rcx, [rel fw_blocks]
    mov  [rcx+rax], r9b
    inc  dword [rel fw_set_calls]
    mov  eax, 1
    ret
.no:
    xor  eax, eax
    ret

world_get_light:
    mov  eax, [rel fw_light]
    ret

world_is_loaded:
    mov  eax, [rel fw_loaded]
    ret

sfx_play:
sfx_play_at:
    cmp  ecx, 32
    jae  .x
    lea  rax, [rel fw_sfx]
    inc  dword [rax+rcx*4]
.x: ret

; highest non-air y, or -1
world_height_at:
    push rbx
    push rsi
    mov  ebx, ecx
    mov  esi, edx
    mov  r10d, 127
.l: mov  ecx, ebx
    mov  edx, r10d
    mov  r8d, esi
    call fw_index
    test rax, rax
    js   .n
    lea  rcx, [rel fw_blocks]
    cmp  byte [rcx+rax], 0
    jne  .f
.n: dec  r10d
    jns  .l
.f: mov  eax, r10d
    pop  rsi
    pop  rbx
    ret

; x/z move freely, only y collides. checks BF_SOLID under the four footprint
; corners, so a mob centred over a 1x1 hole still stands on the rim like a real AABB
physics_move:
    push rbx
    mov  rbx, rcx
    movss xmm0, [rbx+PHYS.x]
    addss xmm0, [rbx+PHYS.dx]
    movss [rbx+PHYS.x], xmm0
    movss xmm0, [rbx+PHYS.z]
    addss xmm0, [rbx+PHYS.dz]
    movss [rbx+PHYS.z], xmm0
    mov  dword [rbx+PHYS.flags], 0
    movss xmm0, [rbx+PHYS.y]
    addss xmm0, [rbx+PHYS.dy]
    xorps xmm1, xmm1
    comiss xmm1, [rbx+PHYS.dy]
    jbe  .store                         ; not falling
    sub  rsp, 48
    movss [rsp+32], xmm0
    mov  dword [rsp+36], 0              ; corner 0..3
.corner:
    mov  eax, [rsp+36]
    movss xmm3, [rbx+PHYS.hw]
    mulss xmm3, [rel f_0999]
    movss xmm2, [rbx+PHYS.x]
    test eax, 1
    jz   .xm
    addss xmm2, xmm3
    jmp  .xd
.xm:
    subss xmm2, xmm3
.xd:
    roundss xmm2, xmm2, 1
    cvttss2si ecx, xmm2
    movss xmm2, [rbx+PHYS.z]
    test eax, 2
    jz   .zm
    addss xmm2, xmm3
    jmp  .zd
.zm:
    subss xmm2, xmm3
.zd:
    roundss xmm2, xmm2, 1
    cvttss2si r8d, xmm2
    movss xmm2, [rsp+32]
    roundss xmm2, xmm2, 1
    cvttss2si edx, xmm2
    call world_get_block
    lea  rcx, [rel blk_flags]
    test word [rcx+rax*2], BF_SOLID
    jnz  .hit
    inc  dword [rsp+36]
    cmp  dword [rsp+36], 4
    jb   .corner
    movss xmm0, [rsp+32]
    add  rsp, 48
    jmp  .store
.hit:
    movss xmm0, [rsp+32]
    add  rsp, 48
    roundss xmm0, xmm0, 1
    addss xmm0, [rel f_one]
    mov  dword [rbx+PHYS.flags], PF_GROUND|PF_HIT_Y
.store:
    movss [rbx+PHYS.y], xmm0
    pop  rbx
    ret

physics_in_liquid:
    xor  eax, eax
    ret

; only counts into fw_given, never touches the real inventory. -> leftover
inv_give_player:
    mov  eax, [rel fw_capacity]
    cmp  eax, edx
    cmova eax, edx
    sub  [rel fw_capacity], eax
    lea  r8, [rel fw_given]
    movzx ecx, cl
    add  [r8+rcx*4], eax
    mov  r9d, edx
    sub  r9d, eax
    mov  eax, r9d
    ret

; x87 trig, precision doesn't matter here. scratch lives in the caller's shadow space
math_sin:
    movss [rsp+8], xmm0
    fld   dword [rsp+8]
    fsin
    fstp  dword [rsp+8]
    movss xmm0, [rsp+8]
    ret
math_cos:
    movss [rsp+8], xmm0
    fld   dword [rsp+8]
    fcos
    fstp  dword [rsp+8]
    movss xmm0, [rsp+8]
    ret
math_sincos:                            ; -> xmm0 sin, xmm1 cos
    movss [rsp+8], xmm0
    fld   dword [rsp+8]
    fsincos                             ; st0 = cos, st1 = sin
    fstp  dword [rsp+8]
    fstp  dword [rsp+16]
    movss xmm1, [rsp+8]
    movss xmm0, [rsp+16]
    ret
math_atan2:                             ; (y, x)
    movss [rsp+8], xmm0
    movss [rsp+16], xmm1
    fld   dword [rsp+8]
    fld   dword [rsp+16]
    fpatan
    fstp  dword [rsp+8]
    movss xmm0, [rsp+8]
    ret

; state 0 sticks at 0 so tests are deterministic, otherwise xorshift64*
fw_next:
    mov  rax, [rel fw_rng_state]
    test rax, rax
    jz   .z
    mov  rdx, rax
    shr  rdx, 12
    xor  rax, rdx
    mov  rdx, rax
    shl  rdx, 25
    xor  rax, rdx
    mov  rdx, rax
    shr  rdx, 27
    xor  rax, rdx
    mov  [rel fw_rng_state], rax
    mov  rdx, 0x2545F4914F6CDD1D
    imul rax, rdx
.z: ret

rng_float:
    call fw_next
    shr  rax, 40                        ; 24 bits
    cvtsi2ss xmm0, eax
    mulss xmm0, [rel f_2m24]
    ret

; pinned rng gives 0, not -1
rng_float_signed:
    call rng_float
    addss xmm0, xmm0
    mov  rax, [rel fw_rng_state]
    test rax, rax
    jz   .z
    subss xmm0, [rel f_one]
.z: ret

rng_int:
    test ecx, ecx
    jle  .z
    push rcx
    call fw_next
    pop  rcx
    shr  rax, 33
    xor  edx, edx
    div  ecx
    mov  eax, edx
    ret
.z: xor  eax, eax
    ret

section .rdata
f_0999:     dd 0.999
f_one:  dd 1.0
f_2m24: dd 0.000000059604645
