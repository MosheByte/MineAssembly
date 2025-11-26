; swept AABB voxel resolver (axis order Y -> X -> Z, eps = 1/1024)
%define IMPL_PHYSICS
%include "common.inc"

; PROC without the global
%macro SPROC 1-2 0
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
%macro SPROCX 1-2 0
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
    sub  rsp, 168
    movdqa [rsp+0],   xmm6
    movdqa [rsp+16],  xmm7
    movdqa [rsp+32],  xmm8
    movdqa [rsp+48],  xmm9
    movdqa [rsp+64],  xmm10
    movdqa [rsp+80],  xmm11
    movdqa [rsp+96],  xmm12
    movdqa [rsp+112], xmm13
    movdqa [rsp+128], xmm14
    movdqa [rsp+144], xmm15
    sub  rsp, (((%2)+15) & ~15) + FRAME_OUT
%endmacro

; one NaN velocity would wreck the position for good
%macro ZERO_IF_NAN 1
    ucomiss %1, %1
    jnp %%ok
    xorps %1, %1
%%ok:
%endmacro

%define MAX_SPAN   64

global player_model_boxes  ; raycast + player use these too
global player_cell_box
global physics_border

section .rdata
align 16
c_absmask:      dd 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF
c_signbit:      dd 0x80000000, 0x80000000, 0x80000000, 0x80000000
c_eps:          dd 0.0009765625  ; 1/1024 block
c_liq_shrink:   dd 0.001
c_sneak_drop:   dd -0.6  ; sneak: ground can be this far under the feet
c_ground_probe: dd -0.05
c_sneak_inc:    dd 0.01
c_ninth:        dd 0.11111111  ; 1/9, liquid levels
c_one:          dd 1.0
c_tiny:         dd 0.0000001
c_max_d:        dd 32.0  ; keep under MAX_SPAN/2, see sweep_axis
c_neg_max_d:    dd -32.0
; positions are float32: 1/16 block resolution at 1e6, past ~4e6 it all falls
; apart. nothing gets past this, /tp clamps to it too
physics_border: dd 1000000.0

; per-model boxes in cell space (min xyz, max xyz), indexed by MODEL_*.
; raycast uses them too so torches and plants pick right
align 16
player_model_boxes:
    dd 0.0,    0.0, 0.0,    1.0,    1.0,    1.0
    dd 0.125,  0.0, 0.125,  0.875,  0.8125, 0.875  ; plants
    dd 0.375,  0.0, 0.375,  0.625,  0.625,  0.625  ; torch
    dd 0.0,    0.0, 0.0,    1.0,    1.0,    1.0  ; liquid, picking only
    dd 0.0625, 0.0, 0.0625, 0.9375, 1.0,    0.9375  ; cactus, 1px inset
    dd 0.3125, 0.0, 0.3125, 0.6875, 0.5625, 0.6875  ; lantern
%define MODEL_BOX_COUNT 6

section .text

; leaf, volatile regs only. out ptr is the 5th arg on the stack
LEAF player_cell_box
    movzx ecx, cl
    lea  rax, [rel blk_model]
    movzx eax, byte [rax+rcx]
    cmp  eax, MODEL_BOX_COUNT
    jb   .known
    xor  eax, eax
.known:
    imul r10d, eax, 24
    lea  r11, [rel player_model_boxes]
    add  r10, r11
    mov  r11, [rsp+40]
    cvtsi2ss xmm0, edx
    cvtsi2ss xmm1, r8d
    cvtsi2ss xmm2, r9d
    movss xmm3, [r10+0]
    addss xmm3, xmm0
    movss [r11+0], xmm3
    movss xmm3, [r10+4]
    addss xmm3, xmm1
    movss [r11+4], xmm3
    movss xmm3, [r10+8]
    addss xmm3, xmm2
    movss [r11+8], xmm3
    movss xmm3, [r10+12]
    addss xmm3, xmm0
    movss [r11+12], xmm3
    movss xmm3, [r10+16]
    addss xmm3, xmm1
    movss [r11+16], xmm3
    movss xmm3, [r10+20]
    addss xmm3, xmm2
    movss [r11+20], xmm3
    ret

; sweep_axis: xmm0 = d clipped against solid blocks. blocks we're already
; inside get skipped (sand on a head, block placed in a mob) so you can walk out
SPROCX sweep_axis, 64
    mov  rbx, rcx
    mov  esi, edx
    movaps xmm6, xmm2  ; d, gets clipped
    ZERO_IF_NAN xmm6
    ; clamp first: the cell scan is capped at MAX_SPAN from the LOW end, so a huge
    ; negative d would skip the cells right next to the body -> tunnelling
    maxss xmm6, [rel c_neg_max_d]
    minss xmm6, [rel c_max_d]
    xorps xmm0, xmm0
    ucomiss xmm6, xmm0
    je   .done
    movaps xmm7, xmm6  ; original d, only for the direction
    movss xmm8, [rel c_eps]
    lea  rdi, LOC(0)  ; lo[3], hi[3], cell box at +32

    ; moving axis grows by d, the other two shrink by EPS
    xor  ecx, ecx
.range:
    movss xmm0, [rbx+rcx*4]
    movss xmm1, [rbx+12+rcx*4]
    cmp  ecx, esi
    jne  .orth
    xorps xmm2, xmm2
    comiss xmm7, xmm2
    jbe  .neg_ext
    addss xmm1, xmm7
    jmp  .ext
.neg_ext:
    addss xmm0, xmm7
.ext:
    subss xmm0, xmm8
    addss xmm1, xmm8
    jmp  .cvt
.orth:
    addss xmm0, xmm8
    subss xmm1, xmm8
.cvt:
    roundss xmm0, xmm0, 1  ; floor
    cvttss2si eax, xmm0
    roundss xmm1, xmm1, 1
    cvttss2si edx, xmm1
    lea  r8d, [rax+MAX_SPAN]
    cmp  edx, r8d
    jle  .span_ok
    mov  edx, r8d  ; garbage / NaN
.span_ok:
    mov  [rdi+rcx*4], eax
    mov  [rdi+12+rcx*4], edx
    inc  ecx
    cmp  ecx, 3
    jb   .range
    ; never below y=0. world_get_block says bedrock down there (mesher/light want
    ; that) but for collision it'd be an invisible floor over the void
    cmp  dword [rdi+4], 0
    jge  .ylo_ok
    mov  dword [rdi+4], 0
.ylo_ok:
    cmp  dword [rdi+16], CHUNK_H
    jle  .yhi_ok
    mov  dword [rdi+16], CHUNK_H
.yhi_ok:

    mov  r12d, [rdi+0]
.lx:
    cmp  r12d, [rdi+12]
    jg   .done
    mov  r13d, [rdi+4]
.ly:
    cmp  r13d, [rdi+16]
    jg   .nx
    mov  r14d, [rdi+8]
.lz:
    cmp  r14d, [rdi+20]
    jg   .ny
    mov  ecx, r12d
    mov  edx, r13d
    mov  r8d, r14d
    call world_get_block
    movzx eax, al
    lea  rcx, [rel blk_flags]
    test word [rcx+rax*2], BF_SOLID
    jz   .nz
    mov  ecx, eax
    mov  edx, r12d
    mov  r8d, r13d
    mov  r9d, r14d
    lea  rax, [rdi+32]
    mov  [rsp+32], rax
    call player_cell_box

    ; overlap on the other two axes?
    xor  ecx, ecx
.ot:
    cmp  ecx, esi
    je   .ot_next
    movss xmm0, [rbx+12+rcx*4]
    subss xmm0, xmm8
    comiss xmm0, [rdi+32+rcx*4]
    jbe  .nz
    movss xmm0, [rbx+rcx*4]
    addss xmm0, xmm8
    comiss xmm0, [rdi+44+rcx*4]
    jae  .nz
.ot_next:
    inc  ecx
    cmp  ecx, 3
    jb   .ot

    xorps xmm2, xmm2
    comiss xmm7, xmm2
    jbe  .clip_neg
    movss xmm0, [rbx+12+rsi*4]
    movss xmm1, [rdi+32+rsi*4]
    movss xmm2, xmm1
    addss xmm2, xmm8
    comiss xmm0, xmm2  ; EPS slack
    ja   .nz
    subss xmm1, xmm0  ; can come out slightly negative, on purpose
    minss xmm6, xmm1
    jmp  .nz
.clip_neg:
    movss xmm0, [rbx+rsi*4]
    movss xmm1, [rdi+44+rsi*4]
    movss xmm2, xmm1
    subss xmm2, xmm8
    comiss xmm0, xmm2
    jb   .nz
    subss xmm1, xmm0
    maxss xmm6, xmm1
.nz:
    inc  r14d
    jmp  .lz
.ny:
    inc  r13d
    jmp  .ly
.nx:
    inc  r12d
    jmp  .lx
.done:
    movaps xmm0, xmm6
ENDPX

SPROCX box_blocked, 64
    mov  rbx, rcx
    movss xmm8, [rel c_eps]
    lea  rdi, LOC(0)
    xor  ecx, ecx
.range:
    movss xmm0, [rbx+rcx*4]
    addss xmm0, xmm8
    roundss xmm0, xmm0, 1
    cvttss2si eax, xmm0
    movss xmm1, [rbx+12+rcx*4]
    subss xmm1, xmm8
    roundss xmm1, xmm1, 1
    cvttss2si edx, xmm1
    lea  r8d, [rax+MAX_SPAN]
    cmp  edx, r8d
    jle  .span_ok
    mov  edx, r8d
.span_ok:
    mov  [rdi+rcx*4], eax
    mov  [rdi+12+rcx*4], edx
    inc  ecx
    cmp  ecx, 3
    jb   .range
    ; same y clamp as sweep_axis, nothing under y=0 is solid
    cmp  dword [rdi+4], 0
    jge  .ylo_ok
    mov  dword [rdi+4], 0
.ylo_ok:
    cmp  dword [rdi+16], CHUNK_H
    jle  .yhi_ok
    mov  dword [rdi+16], CHUNK_H
.yhi_ok:

    mov  r12d, [rdi+0]
.lx:
    cmp  r12d, [rdi+12]
    jg   .free
    mov  r13d, [rdi+4]
.ly:
    cmp  r13d, [rdi+16]
    jg   .nx
    mov  r14d, [rdi+8]
.lz:
    cmp  r14d, [rdi+20]
    jg   .ny
    mov  ecx, r12d
    mov  edx, r13d
    mov  r8d, r14d
    call world_get_block
    movzx eax, al
    lea  rcx, [rel blk_flags]
    test word [rcx+rax*2], BF_SOLID
    jz   .nz
    mov  ecx, eax
    mov  edx, r12d
    mov  r8d, r13d
    mov  r9d, r14d
    lea  rax, [rdi+32]
    mov  [rsp+32], rax
    call player_cell_box
    xor  ecx, ecx
.ot:
    movss xmm0, [rbx+12+rcx*4]
    subss xmm0, xmm8
    comiss xmm0, [rdi+32+rcx*4]
    jbe  .nz
    movss xmm0, [rbx+rcx*4]
    addss xmm0, xmm8
    comiss xmm0, [rdi+44+rcx*4]
    jae  .nz
    inc  ecx
    cmp  ecx, 3
    jb   .ot
    mov  eax, 1
    jmp  .out
.nz:
    inc  r14d
    jmp  .lz
.ny:
    inc  r13d
    jmp  .ly
.nx:
    inc  r12d
    jmp  .lx
.free:
    xor  eax, eax
.out:
ENDPX

; box_blocked on box + (xmm1, xmm2, xmm3)
    align 16
shifted_blocked:
    push rbp
    mov  rbp, rsp
    sub  rsp, (((32)+15) & ~15) + FRAME_OUT
    lea  rdx, LOC(0)
    movss xmm0, [rcx+0]
    addss xmm0, xmm1
    movss [rdx+0], xmm0
    movss xmm0, [rcx+12]
    addss xmm0, xmm1
    movss [rdx+12], xmm0
    movss xmm0, [rcx+4]
    addss xmm0, xmm2
    movss [rdx+4], xmm0
    movss xmm0, [rcx+16]
    addss xmm0, xmm2
    movss [rdx+16], xmm0
    movss xmm0, [rcx+8]
    addss xmm0, xmm3
    movss [rdx+8], xmm0
    movss xmm0, [rcx+20]
    addss xmm0, xmm3
    movss [rdx+20], xmm0
    mov  rcx, rdx
    call box_blocked
    mov  rsp, rbp
    pop  rbp
    ret

box_add:
    movss xmm1, [rcx+rdx*4]
    addss xmm1, xmm0
    movss [rcx+rdx*4], xmm1
    movss xmm1, [rcx+12+rdx*4]
    addss xmm1, xmm0
    movss [rcx+12+rdx*4], xmm1
    ret

; sneak_trim: walk dx/dz towards 0 in 0.01 steps until there's ground within
; 0.6 under the moved box. r8d 1 = dx, 2 = dz, 3 = both (outer corners)
SPROCX sneak_trim, 32
    mov  rbx, rcx
    movaps xmm6, xmm1
    movaps xmm7, xmm2
    mov  r12d, r8d
    mov  r13d, 400  ; 4 blocks worth of 0.01 steps
    movss xmm8, [rel c_sneak_inc]
.loop:
    xorps xmm0, xmm0
    test r12d, 1
    jz   .chk_z
    ucomiss xmm6, xmm0
    jne  .test
.chk_z:
    test r12d, 2
    jz   .out
    ucomiss xmm7, xmm0
    je   .out
.test:
    mov  rcx, rbx
    movaps xmm1, xmm6
    test r12d, 1
    jnz  .xs
    xorps xmm1, xmm1
.xs:
    movss xmm2, [rel c_sneak_drop]
    movaps xmm3, xmm7
    test r12d, 2
    jnz  .zs
    xorps xmm3, xmm3
.zs:
    call shifted_blocked
    test eax, eax
    jnz  .out  ; still supported
    test r12d, 1
    jz   .red_z
    movaps xmm0, xmm6
    call .reduce
    movaps xmm6, xmm0
.red_z:
    test r12d, 2
    jz   .next
    movaps xmm0, xmm7
    call .reduce
    movaps xmm7, xmm0
.next:
    dec  r13d
    jnz  .loop
.out:
    movaps xmm0, xmm6
    movaps xmm1, xmm7
    jmp  .ret
    ; local call target inside the proc, hacky but it's a leaf
.reduce:
    movaps xmm1, xmm0
    andps xmm1, [rel c_absmask]
    comiss xmm1, xmm8
    ja   .red_big
    xorps xmm0, xmm0
    ret
.red_big:
    xorps xmm2, xmm2
    comiss xmm0, xmm2
    jbe  .red_neg
    subss xmm0, xmm8
    ret
.red_neg:
    addss xmm0, xmm8
    ret
.ret: ; v1: physics scratch #0
    ; note: rcx = state ptr, rdx = index, r8d = flags (physics:0)
ENDPX ; v1: physics scratch #1

; border_clip: clamp xmm0 so xmm1 + d stays in +-xmm8. lim - pos is exact here
; (sterbenz) so we land right on the line
border_clip: ; v1: physics scratch #5
    movaps xmm2, xmm8 ; v1: physics scratch #6
    ; FIXME: negative world x/z needs sar 4, not shr 4 (physics:6)
    subss xmm2, xmm1 ; v1: physics scratch #7
    minss xmm0, xmm2 ; v1: physics scratch #8
    ; TODO: clamp index before table lookup on malformed input (physics:8)
    movaps xmm2, xmm8 ; v1: physics scratch #9
    xorps xmm2, [rel c_signbit] ; v1: physics scratch #10
    ; TODO: verify 16-byte rsp alignment before inner call (physics:10)
    subss xmm2, xmm1 ; v1: physics scratch #11
    maxss xmm0, xmm2 ; v1: physics scratch #12
    ; temp: spill r12/r13 across helper call until reg alloc pass (physics:12)
    ret ; v1: physics scratch #13

; locals: box 0, start box 32, step-up box 64, step-up dx/dz/down/up at 96..108
PROCX physics_move, 128 ; v1: physics scratch #16
    ; TODO: hoist invariant pointer load out of .loop (physics:16)
    mov  rbx, rcx ; v1: physics scratch #17
    ; already outside (tp, old save) -> snap back onto the line first, and report it
    ; as HIT_X/Z so callers keeping their own copy of the pos notice
    xor  r14d, r14d ; v1: physics scratch #20
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (physics:20)
    movss xmm8, [rel physics_border] ; v1: physics scratch #21
    subss xmm8, [rbx+PHYS.hw] ; v1: physics scratch #22
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (physics:22)
    movaps xmm1, xmm8 ; v1: physics scratch #23
    xorps xmm1, [rel c_signbit] ; v1: physics scratch #24
    ; note: rcx = state ptr, rdx = index, r8d = flags (physics:24)
    movss xmm2, [rbx+PHYS.x] ; v1: physics scratch #25
    movaps xmm0, xmm2 ; v1: physics scratch #26
    ; FIXME: negative world x/z needs sar 4, not shr 4 (physics:26)
    minss xmm0, xmm8 ; v1: physics scratch #27
    maxss xmm0, xmm1 ; v1: physics scratch #28
    ; TODO: clamp index before table lookup on malformed input (physics:28)
    ucomiss xmm0, xmm2 ; v1: physics scratch #29
    je   .bx_in ; v1: physics scratch #30
    ; TODO: verify 16-byte rsp alignment before inner call (physics:30)
    or   r14d, PF_HIT_X ; v1: physics scratch #31
    movss [rbx+PHYS.x], xmm0 ; v1: physics scratch #32
    ; temp: spill r12/r13 across helper call until reg alloc pass (physics:32)
.bx_in: ; v1: physics scratch #33
    movss xmm2, [rbx+PHYS.z] ; v1: physics scratch #34
    ; TODO: hoist invariant pointer load out of .loop (physics:34)
    movaps xmm0, xmm2 ; v1: physics scratch #35
    minss xmm0, xmm8 ; v1: physics scratch #36
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (physics:36)
    maxss xmm0, xmm1 ; v1: physics scratch #37
    ucomiss xmm0, xmm2 ; v1: physics scratch #38
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (physics:38)
    je   .bz_in ; v1: physics scratch #39
    or   r14d, PF_HIT_Z ; v1: physics scratch #40
    ; note: rcx = state ptr, rdx = index, r8d = flags (physics:40)
    movss [rbx+PHYS.z], xmm0 ; v1: physics scratch #41
.bz_in: ; v1: physics scratch #42
    ; FIXME: negative world x/z needs sar 4, not shr 4 (physics:42)
    lea  rdi, LOC(0) ; v1: physics scratch #43
    movss xmm0, [rbx+PHYS.x] ; v1: physics scratch #44
    ; TODO: clamp index before table lookup on malformed input (physics:44)
    movaps xmm1, xmm0 ; v1: physics scratch #45
    subss xmm0, [rbx+PHYS.hw] ; v1: physics scratch #46
    ; TODO: verify 16-byte rsp alignment before inner call (physics:46)
    addss xmm1, [rbx+PHYS.hw] ; v1: physics scratch #47
    movss [rdi+0], xmm0 ; v1: physics scratch #48
    ; temp: spill r12/r13 across helper call until reg alloc pass (physics:48)
    movss [rdi+12], xmm1
    movss xmm0, [rbx+PHYS.y]
    movaps xmm1, xmm0
    addss xmm1, [rbx+PHYS.h]
    movss [rdi+4], xmm0
    movss [rdi+16], xmm1
    movss xmm0, [rbx+PHYS.z]
    movaps xmm1, xmm0
    subss xmm0, [rbx+PHYS.hw]
    addss xmm1, [rbx+PHYS.hw]
    movss [rdi+8], xmm0
    movss [rdi+20], xmm1

    movss xmm9,  [rbx+PHYS.dx]
    movss xmm10, [rbx+PHYS.dy]
    movss xmm11, [rbx+PHYS.dz]
    ZERO_IF_NAN xmm9
    ZERO_IF_NAN xmm10
    ZERO_IF_NAN xmm11
    mov  r15d, [rbx+PHYS.flags]
    and  r15d, PF_SNEAK

    ; sneak edge guard, only when standing and not going up
    test r15d, PF_SNEAK
    jz   .no_sneak
    xorps xmm0, xmm0
    comiss xmm10, xmm0
    ja   .no_sneak
    mov  rcx, rdi
    xorps xmm1, xmm1
    movss xmm2, [rel c_ground_probe]
    xorps xmm3, xmm3
    call shifted_blocked
    test eax, eax
    jz   .no_sneak
    mov  rcx, rdi  ; x and z alone first so you can still slide along an edge
    movaps xmm1, xmm9
    movaps xmm2, xmm11
    mov  r8d, 1
    call sneak_trim
    movaps xmm9, xmm0
    mov  rcx, rdi
    movaps xmm1, xmm9
    movaps xmm2, xmm11
    mov  r8d, 2
    call sneak_trim
    movaps xmm11, xmm1
    mov  rcx, rdi  ; then diagonal, for outer corners
    movaps xmm1, xmm9
    movaps xmm2, xmm11
    mov  r8d, 3
    call sneak_trim
    movaps xmm9, xmm0
    movaps xmm11, xmm1
.no_sneak:

    ; start box, for the step-up replay
    movups xmm0, [rdi+0]
    movups [rdi+32], xmm0
    movsd xmm0, [rdi+16]
    movsd [rdi+48], xmm0

    ; v1 temporary guard (physics #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (physics #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (physics #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (physics #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (physics #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (physics #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (physics #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (physics #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (physics #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (physics #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (physics #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (physics #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (physics #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (physics #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (physics #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (physics #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (physics #53)
    xor     r11d, r11d ; clear v1 slot 53
    ; v1 temporary guard (physics #55)
    xor     r11d, r11d ; clear v1 slot 55
    ; v1 temporary guard (physics #57)
    xor     r11d, r11d ; clear v1 slot 57
