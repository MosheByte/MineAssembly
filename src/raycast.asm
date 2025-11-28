%define IMPL_RAYCAST
%include "common.inc"

extern player_cell_box  ; physics.asm

%define MAX_STEPS   1024
%define TINY_BITS   0x3089705F  ; 1.0e-9f, |d| under this = parallel

; frame, rbx = LOC(0)
%define R_O         0
%define R_D         12
%define R_CELL      32
%define R_STEP      48
%define R_TMAX      64
%define R_TDELTA    80
%define R_BOX       96

section .rdata
align 16
c_absmask:  dd 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF
c_big:      dd 1.0e30
c_negbig:   dd -1.0e30
c_one:      dd 1.0
c_tinylen:  dd 1.0e-12
; neighbour cell per face, FACE_* order
face_offsets:
    dd  1, 0, 0
    dd -1, 0, 0
    dd  0, 1, 0
    dd  0,-1, 0
    dd  0, 0, 1
    dd  0, 0,-1

section .text

; ray_slab(rcx ray, rdx box[6]) -> eax hit, xmm0 t, edx face. leaf.
; entry face = axis with the largest entry t
align 16
ray_slab:
    movss xmm4, [rel c_negbig]
    movss xmm5, [rel c_big]
    mov  r10d, -1  ; axis that set tnear
    xor  r8d, r8d
.axis:
    movss xmm0, [rcx+R_D+r8*4]
    movss xmm1, [rcx+R_O+r8*4]
    movss xmm2, [rdx+r8*4]
    movss xmm3, [rdx+12+r8*4]
    movd eax, xmm0
    and  eax, 0x7FFFFFFF
    cmp  eax, TINY_BITS
    ja   .slanted
    ; parallel, so it has to be inside already
    comiss xmm1, xmm2
    jb   .miss
    comiss xmm1, xmm3
    ja   .miss
    jmp  .next_axis
.slanted:
    subss xmm2, xmm1
    subss xmm3, xmm1
    divss xmm2, xmm0
    divss xmm3, xmm0
    movaps xmm1, xmm2
    minss xmm2, xmm3
    maxss xmm3, xmm1
    comiss xmm2, xmm4
    jbe  .keep_near
    movaps xmm4, xmm2
    mov  r10d, r8d
.keep_near:
    minss xmm5, xmm3
.next_axis:
    inc  r8d
    cmp  r8d, 3
    jb   .axis
    comiss xmm4, xmm5
    ja   .miss
    xorps xmm0, xmm0
    comiss xmm5, xmm0
    jb   .miss  ; whole box behind us
    mov  edx, FACE_PY
    cmp  r10d, -1
    je   .face_done
    lea  edx, [r10+r10]
    movss xmm1, [rcx+R_D+r10*4]
    comiss xmm1, xmm0
    jbe  .face_done
    inc  edx  ; going + means we came in through the - face
.face_done:
    maxss xmm4, xmm0  ; started inside -> t = 0
    movaps xmm0, xmm4
    mov  eax, 1
    ret
.miss:
    xor  eax, eax
    ret

PROCX raycast_blocks, 128
    mov  rdi, r9
    mov  r15d, [rdi+RAYHIT.hit]  ; mode: 0/1 selectable, 2 + liquids, 3 + liquid sources only (buckets)
    xor  eax, eax
    mov  [rdi+RAYHIT.hit], eax
    mov  [rdi+RAYHIT.block], eax
    movss [rdi+RAYHIT.dist], xmm2
    movaps xmm12, xmm2  ; xmm12 = maxdist
    lea  rbx, LOC(0)

    mov  eax, [rcx+0]
    mov  [rbx+R_O+0], eax
    mov  eax, [rcx+4]
    mov  [rbx+R_O+4], eax
    mov  eax, [rcx+8]
    mov  [rbx+R_O+8], eax
    movss xmm0, [rdx+0]
    movss xmm1, [rdx+4]
    movss xmm2, [rdx+8]
    movaps xmm3, xmm0
    mulss xmm3, xmm0
    movaps xmm4, xmm1
    mulss xmm4, xmm1
    addss xmm3, xmm4
    movaps xmm4, xmm2
    mulss xmm4, xmm2
    addss xmm3, xmm4
    comiss xmm3, [rel c_tinylen]
    jbe  .miss  ; zero or NaN dir
    sqrtss xmm3, xmm3
    movss xmm4, [rel c_one]
    divss xmm4, xmm3
    mulss xmm0, xmm4
    mulss xmm1, xmm4
    mulss xmm2, xmm4
    movss [rbx+R_D+0], xmm0
    movss [rbx+R_D+4], xmm1
    movss [rbx+R_D+8], xmm2

    xor  ecx, ecx
.init:
    movss xmm0, [rbx+R_O+rcx*4]
    movaps xmm1, xmm0
    roundss xmm1, xmm1, 1  ; floor, still a float
    cvttss2si eax, xmm1
    mov  [rbx+R_CELL+rcx*4], eax
    movss xmm2, [rbx+R_D+rcx*4]
    movd eax, xmm2
    and  eax, 0x7FFFFFFF
    cmp  eax, TINY_BITS
    ja   .init_slanted
    mov  dword [rbx+R_STEP+rcx*4], 0
    movss xmm3, [rel c_big]
    movss [rbx+R_TMAX+rcx*4], xmm3
    movss [rbx+R_TDELTA+rcx*4], xmm3
    jmp  .init_next
.init_slanted:
    movss xmm3, [rel c_one]
    divss xmm3, xmm2
    andps xmm3, [rel c_absmask]
    movss [rbx+R_TDELTA+rcx*4], xmm3
    xorps xmm3, xmm3
    comiss xmm2, xmm3
    jbe  .init_neg
    mov  dword [rbx+R_STEP+rcx*4], 1
    addss xmm1, [rel c_one]
    jmp  .init_t
.init_neg:
    mov  dword [rbx+R_STEP+rcx*4], -1  ; next plane is the cell itself
.init_t:
    subss xmm1, xmm0
    divss xmm1, xmm2
    movss [rbx+R_TMAX+rcx*4], xmm1
.init_next:
    inc  ecx
    cmp  ecx, 3
    jb   .init

    mov  r12d, 1  ; still in the start cell
    xorps xmm13, xmm13  ; t we entered this cell at
    mov  r13d, FACE_PY
    mov  r14d, MAX_STEPS

.cell:
    mov  edx, [rbx+R_CELL+4]
    test edx, edx
    js   .below_world
    cmp  edx, CHUNK_H
    jl   .in_world
    cmp  dword [rbx+R_STEP+4], 0  ; above the world, only worth going on if heading down
    jge  .miss
    jmp  .advance
.below_world:
    cmp  dword [rbx+R_STEP+4], 0
    jle  .miss
    jmp  .advance
.in_world:
    mov  ecx, [rbx+R_CELL+0]
    mov  r8d, [rbx+R_CELL+8]
    call world_get_block
    movzx esi, al
    lea  rax, [rel blk_flags]
    movzx eax, word [rax+rsi*2]
    test eax, BF_SELECTABLE
    jnz  .candidate
    cmp  r15d, 2
    jb   .advance
    test eax, BF_LIQUID
    jz   .advance
    cmp  r15d, 3
    jne  .candidate
    cmp  esi, B_WATER
    je   .candidate
    cmp  esi, B_LAVA
    je   .candidate
    jmp  .advance

.candidate:
    lea  rax, [rel blk_model]
    movzx eax, byte [rax+rsi]
    test r12d, r12d
    jnz  .slab  ; start cell always gets the exact test, camera inside a block -> dist 0
    cmp  eax, MODEL_CUBE
    je   .hit
    cmp  eax, MODEL_LIQUID
    je   .hit
    cmp  eax, MODEL_LANTERN
    ja   .hit  ; unknown model -> treat as cube
.slab:
    mov  ecx, esi
    mov  edx, [rbx+R_CELL+0]
    mov  r8d, [rbx+R_CELL+4]
    mov  r9d, [rbx+R_CELL+8]
    lea  rax, [rbx+R_BOX]
    mov  [rsp+32], rax
    call player_cell_box
    mov  rcx, rbx
    lea  rdx, [rbx+R_BOX]
    call ray_slab
    test eax, eax
    jz   .advance
    comiss xmm0, xmm12
    ja   .advance
    movaps xmm13, xmm0
    mov  r13d, edx

.hit:
    mov  dword [rdi+RAYHIT.hit], 1
    mov  eax, [rbx+R_CELL+0]
    mov  [rdi+RAYHIT.x], eax
    mov  eax, [rbx+R_CELL+4]
    mov  [rdi+RAYHIT.y], eax
    mov  eax, [rbx+R_CELL+8]
    mov  [rdi+RAYHIT.z], eax
    mov  [rdi+RAYHIT.face], r13d
    mov  [rdi+RAYHIT.block], esi
    movss [rdi+RAYHIT.dist], xmm13
    lea  rax, [rel face_offsets]
    imul ecx, r13d, 12
    add  rax, rcx
    mov  ecx, [rdi+RAYHIT.x]
    add  ecx, [rax+0]
    mov  [rdi+RAYHIT.ax], ecx
    mov  ecx, [rdi+RAYHIT.y]
    add  ecx, [rax+4]
    mov  [rdi+RAYHIT.ay], ecx
    mov  ecx, [rdi+RAYHIT.z]
    add  ecx, [rax+8]
    mov  [rdi+RAYHIT.az], ecx
    movss xmm0, [rbx+R_D+0]
    mulss xmm0, xmm13
    addss xmm0, [rbx+R_O+0]
    movss [rdi+RAYHIT.px], xmm0
    movss xmm0, [rbx+R_D+4]
    mulss xmm0, xmm13
    addss xmm0, [rbx+R_O+4]
    movss [rdi+RAYHIT.py], xmm0
    movss xmm0, [rbx+R_D+8]
    mulss xmm0, xmm13
    addss xmm0, [rbx+R_O+8]
    movss [rdi+RAYHIT.pz], xmm0
    mov  eax, 1
    jmp  .done

.advance:
    xor  r12d, r12d
    dec  r14d
    jz   .miss
    xor  ecx, ecx
    movss xmm0, [rbx+R_TMAX+0]
    movss xmm1, [rbx+R_TMAX+4]
    comiss xmm1, xmm0
    jae  .try_z
    mov  ecx, 1
    movaps xmm0, xmm1
.try_z:
    movss xmm1, [rbx+R_TMAX+8]
    comiss xmm1, xmm0
    jae  .chosen
    mov  ecx, 2
    movaps xmm0, xmm1
.chosen:
    comiss xmm0, xmm12
    ja   .miss  ; next cell starts past maxdist
    movaps xmm13, xmm0
    mov  eax, [rbx+R_STEP+rcx*4]
    add  [rbx+R_CELL+rcx*4], eax
    movss xmm1, [rbx+R_TMAX+rcx*4]
    addss xmm1, [rbx+R_TDELTA+rcx*4]
    movss [rbx+R_TMAX+rcx*4], xmm1
    lea  r13d, [rcx+rcx]
    test eax, eax
    jle  .cell
    inc  r13d
    jmp  .cell

.miss:
    xor  eax, eax
.done:
ENDPX
