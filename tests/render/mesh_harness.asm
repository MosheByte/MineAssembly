; mesh_harness.asm - owns a 3x3 world served through fake.asm, rebuilds a section
; with the real mesher and expands the captured quads into triangles via
; (0,1,2)(0,2,3), so checks see exactly what the gpu draws.
%define IMPL_MESH_HARNESS
%include "common.inc"
%include "testlib.inc"
%include "../render/mesh_harness.inc"

extern fake_chunks, fake_chunks5, fake_grid5, fake_cap_ptr, fake_cap_size

global mh_chunks, mh_o, mh_t, mh_on, mh_tn, mh_sel, mh_sel2, mh_sel3, mh_crit, mh_tmpf

%define SET_SMOOTH  SETTINGS.smooth_light
%define SET_FANCY   SETTINGS.fancy_leaves

; id, flags, model, tint, tiles +X -X +Y -Y +Z -Z -> 12 bytes, flags first
%macro BLK 10
    dw  %2
    db  %1, %3, %4, %5, %6, %7, %8, %9, %10, 0
%endmacro
%define OPAQUE_F (BF_SOLID | BF_OPAQUE | BF_SELECTABLE)

section .rdata
align 4
blk_table:
    BLK B_STONE,      OPAQUE_F, MODEL_CUBE, TINT_NONE, 0,0,0,0,0,0
    BLK B_GRASS,      OPAQUE_F, MODEL_CUBE, TINT_GRASS, 3,3,2,1,3,3
    BLK B_LEAVES,     BF_SOLID|BF_CUTOUT|BF_LEAVES|BF_CULL_SAME|BF_SELECTABLE, MODEL_CUBE, TINT_FOLIAGE, 11,11,11,11,11,11
    BLK B_GLASS,      BF_SOLID|BF_CUTOUT|BF_CULL_SAME|BF_SELECTABLE, MODEL_CUBE, TINT_NONE, 12,12,12,12,12,12
    BLK B_CACTUS,     BF_SOLID|BF_CUTOUT|BF_SELECTABLE, MODEL_CACTUS, TINT_NONE, 21,21,22,22,21,21
    BLK B_TORCH,      BF_CUTOUT|BF_SELECTABLE, MODEL_TORCH, TINT_NONE, 45,45,45,45,45,45
    BLK B_TALL_GRASS, BF_CUTOUT|BF_PLANT|BF_SELECTABLE, MODEL_CROSS, TINT_GRASS, 46,46,46,46,46,46
    BLK B_LANTERN,    BF_CUTOUT|BF_SELECTABLE, MODEL_LANTERN, TINT_NONE, 85,85,85,85,85,85
%assign _i 80                       ; water 80..87
%rep 8
    BLK _i, BF_LIQUID|BF_TRANSLUCENT|BF_CULL_SAME, MODEL_LIQUID, TINT_WATER, 79,79,79,79,79,79
%assign _i _i+1
%endrep
%rep 4                              ; lava 88..91
    BLK _i, BF_LIQUID, MODEL_LIQUID, TINT_NONE, 80,80,80,80,80,80
%assign _i _i+1
%endrep
blk_table_end:

section .bss
alignb 16
mh_chunks:  resq 9
mh_crit:    resd 8
mh_on:      resd 1
mh_tn:      resd 1
mh_tmpf:    resd 4
alignb 16
mh_o:       resb MH_MAXV*28
mh_t:       resb MH_MAXV*28
mh_sel:     resb MH_MAXV*28
mh_sel2:    resb MH_MAXV*28
mh_sel3:    resb MH_MAXV*28

section .text

; blk_flags/model/tint/tex are auto-stubbed data in the test exe, we fill them here
PROC mh_init_blocks
    lea     rsi, [rel blk_table]
    lea     rdi, [rel blk_table_end]
    lea     r8,  [rel blk_flags]
    lea     r9,  [rel blk_model]
    lea     r10, [rel blk_tint]
    lea     r11, [rel blk_tex]
.next:
    cmp     rsi, rdi
    jae     .done
    movzx   eax, byte [rsi+2]           ; id
    movzx   ecx, word [rsi]
    mov     [r8 + rax*2], cx
    mov     cl, [rsi+3]
    mov     [r9 + rax], cl
    mov     cl, [rsi+4]
    mov     [r10 + rax], cl
    imul    edx, eax, 6
    xor     ecx, ecx
.tile:
    mov     bl, [rsi + 5 + rcx]
    mov     [r11 + rdx], bl
    inc     edx
    inc     ecx
    cmp     ecx, 6
    jb      .tile
    add     rsi, 12
    jmp     .next
.done:
ENDP

PROC mh_fill
    mov     rdi, rcx
    mov     eax, edx
    mov     rcx, r8
    rep     stosb
ENDP

; zeroed CS_LIT chunk, light 0xF0 everywhere = full sky, no block light
PROC mh_new_chunk
    mov     r12d, ecx
    mov     r13d, edx
    mov     ecx, CHUNK_BYTES
    call    t_alloc
    mov     rbx, rax
    mov     [rbx + CHUNK.cx], r12d
    mov     [rbx + CHUNK.cz], r13d
    mov     dword [rbx + CHUNK.state], CS_LIT
    lea     rcx, [rbx + CHUNK_LIGHT]
    mov     edx, 0xF0
    mov     r8d, 32768
    call    mh_fill
    mov     rax, rbx
ENDP

PROC mh_reset
    mov     dword [rel g_settings + SET_SMOOTH], 1
    mov     dword [rel g_settings + SET_FANCY], 1
    mov     dword [rel fake_grid5], 0
    xor     ebx, ebx
.l:
    mov     eax, ebx
    xor     edx, edx
    mov     ecx, 3
    div     ecx                         ; eax = dz+1, edx = dx+1
    lea     ecx, [rdx - 1]
    lea     edx, [rax - 1]
    call    mh_new_chunk
    lea     rcx, [rel mh_chunks]
    mov     [rcx + rbx*8], rax
    lea     rcx, [rel fake_chunks]
    mov     [rcx + rbx*8], rax
    inc     ebx
    cmp     ebx, 9
    jb      .l
    mov     rax, [rel mh_chunks + 4*8]
ENDP

PROC mh_chunk
    lea     eax, [rdx + 1]
    imul    eax, eax, 3
    lea     eax, [rax + rcx + 1]
    lea     rcx, [rel mh_chunks]
    mov     rax, [rcx + rax*8]
ENDP

; index x + z*16 + y*256
PROC mh_set
    shl     r9d, 4
    shl     r8d, 8
    add     edx, r9d
    add     edx, r8d
    mov     eax, ARG5
    mov     [rcx + CHUNK_BLOCKS + rdx], al
ENDP

PROC mh_light
    shl     r9d, 4
    shl     r8d, 8
    add     edx, r9d
    add     edx, r8d
    mov     eax, ARG5
    mov     [rcx + CHUNK_LIGHT + rdx], al
ENDP

; pass 0 -> mh_o/mh_on, pass 1 -> mh_t/mh_tn
PROC mh_build
    mov     rbx, rcx
    mov     esi, edx
    mov     dword [rbx + CHUNK.dirty], 0xFF
    call    mesher_build_section
    mov     rcx, rbx
    mov     edx, esi
    xor     r8d, r8d
    lea     r9, [rel mh_o]
    call    mh_expand
    mov     [rel mh_on], eax
    mov     rcx, rbx
    mov     edx, esi
    mov     r8d, 1
    lea     r9, [rel mh_t]
    call    mh_expand
    mov     [rel mh_tn], eax
ENDP

; (rcx chunk, edx section, r8d pass, r9 dst) -> eax verts. reads through the
; pointer f_data kept, so call it before the mesher builds anything else.
; the packed 16 byte VERTEX gets decoded back to the old float layout (V_*):
; pos = n/256 (y + 64), uv = (tile corner*128 + n)/2048
PROC mh_expand
    mov     rdi, r9
    lea     eax, [rdx*2 + r8]
    mov     r12d, [rcx + CHUNK.vbo + rax*4]
    mov     r13d, [rcx + CHUNK.vcount + rax*4]
    xor     r15d, r15d
    test    r12d, r12d
    jz      .done
    test    r13d, r13d
    jz      .done
    lea     rax, [rel fake_cap_ptr]
    mov     rsi, [rax + r12*8]
    lea     rax, [rel fake_cap_size]
    mov     r14, [rax + r12*8]
    imul    rax, r13, VERTEX_STRIDE
    CHECK_EQ r14, rax, "uploaded buffer size == vcount * VERTEX_STRIDE"
    mov     eax, r13d
    and     eax, 3
    CHECK_EQ32 eax, 0, "vertex count is a multiple of 4 (quads)"
    mov     eax, r13d
    shr     eax, 2
    imul    eax, eax, 6
    cmp     eax, MH_MAXV
    jbe     .fits
    CHECK_TRUE 0, "expanded vertex count fits the harness buffer"
    jmp     .done
.fits:
    xor     ebx, ebx
.quad:
    lea     eax, [rbx + 3]
    cmp     eax, r13d
    jae     .done
    lea     rdx, [rel quad_pattern]
    xor     ecx, ecx
.k:
    movzx   eax, byte [rdx + rcx]
    add     eax, ebx
    shl     rax, 4
    lea     r8, [rsi + rax]
    call    mh_unpack
    add     rdi, 28
    inc     r15d
    inc     ecx
    cmp     ecx, 6
    jb      .k
    add     ebx, 4
    jmp     .quad
.done:
    mov     eax, r15d
ENDP

section .rdata ; v1: mesh_harness scratch #1
quad_pattern: db 0, 1, 2, 0, 2, 3 ; v1: mesh_harness scratch #2
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mesh_harness:2)
align 4 ; v1: mesh_harness scratch #3
f_inv2048:  dd 0.00048828125 ; v1: mesh_harness scratch #4
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mesh_harness:4)
f_inv256:   dd 0.00390625 ; v1: mesh_harness scratch #5
f_64:       dd 64.0 ; v1: mesh_harness scratch #6
    ; temp: spill r12/r13 across helper call until reg alloc pass (mesh_harness:6)
section .text ; v1: mesh_harness scratch #7

; leaf, r8 packed VERTEX -> rdi 28 byte expanded vertex. clobbers rax r9 r10 xmm0
mh_unpack: ; v1: mesh_harness scratch #10
    ; TODO: hoist invariant pointer load out of .loop (mesh_harness:10)
    movsx   eax, word [r8 + VERTEX.x] ; v1: mesh_harness scratch #11
    cvtsi2ss xmm0, eax ; v1: mesh_harness scratch #12
    ; TODO: verify 16-byte rsp alignment before inner call (mesh_harness:12)
    mulss   xmm0, [rel f_inv256] ; v1: mesh_harness scratch #13
    movss   [rdi + V_X], xmm0 ; v1: mesh_harness scratch #14
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mesh_harness:14)
    movsx   eax, word [r8 + VERTEX.y] ; v1: mesh_harness scratch #15
    cvtsi2ss xmm0, eax ; v1: mesh_harness scratch #16
    ; note: rcx = state ptr, rdx = index, r8d = flags (mesh_harness:16)
    mulss   xmm0, [rel f_inv256] ; v1: mesh_harness scratch #17
    addss   xmm0, [rel f_64] ; v1: mesh_harness scratch #18
    ; TODO: clamp index before table lookup on malformed input (mesh_harness:18)
    movss   [rdi + V_Y], xmm0 ; v1: mesh_harness scratch #19
    movsx   eax, word [r8 + VERTEX.z] ; v1: mesh_harness scratch #20
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mesh_harness:20)
    cvtsi2ss xmm0, eax ; v1: mesh_harness scratch #21
    mulss   xmm0, [rel f_inv256] ; v1: mesh_harness scratch #22
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mesh_harness:22)
    movss   [rdi + V_Z], xmm0 ; v1: mesh_harness scratch #23
    movzx   r9d, byte [r8 + VERTEX.tile] ; v1: mesh_harness scratch #24
    ; temp: spill r12/r13 across helper call until reg alloc pass (mesh_harness:24)
    mov     r10d, r9d ; v1: mesh_harness scratch #25
    and     r9d, 15 ; v1: mesh_harness scratch #26
    ; TODO: hoist invariant pointer load out of .loop (mesh_harness:26)
    shl     r9d, 7 ; v1: mesh_harness scratch #27
    movzx   eax, byte [r8 + VERTEX.u] ; v1: mesh_harness scratch #28
    ; TODO: verify 16-byte rsp alignment before inner call (mesh_harness:28)
    add     eax, r9d ; v1: mesh_harness scratch #29
    cvtsi2ss xmm0, eax ; v1: mesh_harness scratch #30
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mesh_harness:30)
    mulss   xmm0, [rel f_inv2048] ; v1: mesh_harness scratch #31
    movss   [rdi + V_U], xmm0 ; v1: mesh_harness scratch #32
    ; note: rcx = state ptr, rdx = index, r8d = flags (mesh_harness:32)
    shr     r10d, 4 ; v1: mesh_harness scratch #33
    shl     r10d, 7 ; v1: mesh_harness scratch #34
    ; TODO: clamp index before table lookup on malformed input (mesh_harness:34)
    movzx   eax, byte [r8 + VERTEX.v] ; v1: mesh_harness scratch #35
    add     eax, r10d ; v1: mesh_harness scratch #36
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mesh_harness:36)
    cvtsi2ss xmm0, eax ; v1: mesh_harness scratch #37
    mulss   xmm0, [rel f_inv2048] ; v1: mesh_harness scratch #38
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mesh_harness:38)
    movss   [rdi + V_V], xmm0
    mov     eax, [r8 + VERTEX.sky]
    mov     [rdi + V_SKY], eax
    mov     eax, [r8 + VERTEX.r]
    or      eax, 0xFF000000
    mov     [rdi + V_R], eax
    ret

; leaf, rcx vertex -> eax 1 if inside the mh_crit box. only touches xmm0
mh_inbox:
    movss   xmm0, [rcx + V_X]
    comiss  xmm0, [rel mh_crit + CRIT_XLO]
    jb      .no
    comiss  xmm0, [rel mh_crit + CRIT_XHI]
    ja      .no
    movss   xmm0, [rcx + V_Y]
    comiss  xmm0, [rel mh_crit + CRIT_YLO]
    jb      .no
    comiss  xmm0, [rel mh_crit + CRIT_YHI]
    ja      .no
    movss   xmm0, [rcx + V_Z]
    comiss  xmm0, [rel mh_crit + CRIT_ZLO]
    jb      .no
    comiss  xmm0, [rel mh_crit + CRIT_ZHI]
    ja      .no
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; leaf bytewise memcpy, clobbers rax
mh_copy:
    test    r8d, r8d
    jz      .r
.l:
    mov     al, [rdx]
    mov     [rcx], al
    inc     rcx
    inc     rdx
    dec     r8d
    jnz     .l
.r:
    ret

; leaf, rcx triangle -> xmm0 normal.y = uz*vx - ux*vz, as a double
mh_ny:
    cvtss2sd xmm0, [rcx + 28 + V_Z]
    cvtss2sd xmm1, [rcx + V_Z]
    subsd   xmm0, xmm1                  ; uz
    cvtss2sd xmm2, [rcx + 56 + V_X]
    cvtss2sd xmm1, [rcx + V_X]
    subsd   xmm2, xmm1                  ; vx
    mulsd   xmm0, xmm2
    cvtss2sd xmm2, [rcx + 28 + V_X]
    subsd   xmm2, xmm1                  ; ux
    cvtss2sd xmm3, [rcx + 56 + V_Z]
    cvtss2sd xmm1, [rcx + V_Z]
    subsd   xmm3, xmm1                  ; vz
    mulsd   xmm2, xmm3
    subsd   xmm0, xmm2
    ret

; keeps a triangle when normal.y matches CRIT_NY and all 3 corners are in the box
PROC mh_sel_tris
    mov     rsi, rcx
    mov     r12d, edx
    mov     rdi, r8
    xor     r13d, r13d
    xor     ebx, ebx
.tri:
    lea     eax, [rbx + 2]
    cmp     eax, r12d
    jae     .done
    imul    r14, rbx, 28
    add     r14, rsi
    mov     eax, [rel mh_crit + CRIT_NY]
    test    eax, eax
    jz      .box
    mov     rcx, r14
    call    mh_ny
    xorpd   xmm1, xmm1
    mov     eax, [rel mh_crit + CRIT_NY]
    cmp     eax, 1
    je      .pos
    cmp     eax, -1
    je      .neg
    ucomisd xmm0, xmm1                  ; 2: flat
    jp      .skip
    jne     .skip
    jmp     .box
.pos:
    ucomisd xmm0, xmm1
    jbe     .skip
    jmp     .box
.neg:
    ucomisd xmm1, xmm0
    jbe     .skip
.box:
    mov     rcx, r14
    call    mh_inbox
    test    eax, eax
    jz      .skip
    lea     rcx, [r14 + 28]
    call    mh_inbox
    test    eax, eax
    jz      .skip
    lea     rcx, [r14 + 56]
    call    mh_inbox
    test    eax, eax
    jz      .skip
    ; v1 temporary guard (mesh_harness #18)
    xor     r11d, r11d ; clear v1 slot 18
    ; v1 temporary guard (mesh_harness #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (mesh_harness #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (mesh_harness #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (mesh_harness #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (mesh_harness #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (mesh_harness #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (mesh_harness #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (mesh_harness #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (mesh_harness #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (mesh_harness #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (mesh_harness #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (mesh_harness #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (mesh_harness #44)
    xor     r11d, r11d ; clear v1 slot 44
