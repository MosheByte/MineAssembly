; the packed chunk vertex (issue #3): 16 bytes, raw values as the shader reads
; them (render.asm attrib pointers + vs_src), and the worst-case section that
; overflows a 16-bit index range and grows the job buffer by commits.
; @link src/mesher.asm tests/render/fake.asm tests/render/fake_tasks.asm tests/render/mesh_harness.asm
; @timeout 120
%include "common.inc"
%include "testlib.inc"
%include "../render/mesh_harness.inc"

%define WORST_VERTS (4096*11*4)         ; a section of lanterns, 11 quads each

section .text

PROC test_main
    call    mh_init_blocks
    call    tv_layout
    call    tv_raw_cube
    call    tv_below_64_is_negative
    call    tv_worst_case_section
ENDP

PROC tv_layout
    TEST "vertex: layout the shader expects"
    CHECK_EQ32 VERTEX_size, 16, "16 bytes"
    CHECK_EQ32 VERTEX_STRIDE, 16, "VERTEX_STRIDE"
    CHECK_EQ32 VERTEX.u, 6, "a_uv at 6"
    CHECK_EQ32 VERTEX.r, 8, "a_color at 8"
    CHECK_EQ32 VERTEX.tile, 11, "tile rides in a_color.a"
    CHECK_EQ32 VERTEX.sky, 12, "a_light at 12"
    CHECK_EQ32 VERTEX.flags, 15, "flags = a_light.w"
ENDP

; rcx chunk, edx section, r8d pass -> rax packed buffer, edx vcount
PROC tv_buf
    lea     eax, [rdx*2 + r8]
    mov     edx, [rcx + CHUNK.vcount + rax*4]
    mov     eax, [rcx + CHUNK.vbo + rax*4]
    and     eax, 63
    lea     rcx, [rel fake_cap_ptr]
    mov     rax, [rcx + rax*8]
ENDP

; stone at (5, 70, 5): every corner is a whole block, u/v the inset tile edges
PROC tv_raw_cube
    TEST "vertex: one stone cube, raw"
    call    mh_reset
    mov     rbx, rax
    SETB    rbx, 5, 70, 5, B_STONE
    BUILD   rbx, 4
    mov     rcx, rbx
    mov     edx, 4
    xor     r8d, r8d
    call    tv_buf
    mov     rsi, rax
    mov     r12d, edx
    CHECK_EQ32 r12d, 24, "6 quads x 4"
    xor     r13d, r13d                          ; bad verts
    xor     edi, edi
.v:
    mov     r14, rdi
    shl     r14, 4
    add     r14, rsi
    ; x, z in {5, 6} * 256, y in {70 - 64, 71 - 64} * 256
    movsx   eax, word [r14 + VERTEX.x]
    cmp     eax, 5*256
    je      .x_ok
    cmp     eax, 6*256
    jne     .bad
.x_ok:
    movsx   eax, word [r14 + VERTEX.z]
    cmp     eax, 5*256
    je      .z_ok
    cmp     eax, 6*256
    jne     .bad
.z_ok:
    movsx   eax, word [r14 + VERTEX.y]
    cmp     eax, 6*256
    je      .y_ok
    cmp     eax, 7*256
    jne     .bad
.y_ok:
    ; 1/8 texels: 0 + 1/4 texel inset = 2, 16 - 1/4 = 126
    movzx   eax, byte [r14 + VERTEX.u]
    cmp     eax, 2
    je      .u_ok
    cmp     eax, 126
    jne     .bad
.u_ok:
    movzx   eax, byte [r14 + VERTEX.v]
    cmp     eax, 2
    je      .v_ok
    cmp     eax, 126
    jne     .bad
.v_ok:
    cmp     dword [r14 + VERTEX.r], 0x00FFFFFF  ; white, tile 0 (stone)
    jne     .bad
    jmp     .next
.bad:
    inc     r13d
.next:
    inc     edi
    cmp     edi, r12d
    jb      .v
    CHECK_EQ32 r13d, 0, "corners, uv, tint and tile all exact"
ENDP

PROC tv_below_64_is_negative
    TEST "vertex: positions below y 64"
    call    mh_reset
    mov     rbx, rax
    SETB    rbx, 8, 40, 8, B_TORCH
    BUILD   rbx, 2
    mov     rcx, rbx
    mov     edx, 2
    xor     r8d, r8d
    call    tv_buf
    mov     rsi, rax
    mov     r12d, edx
    CHECK_EQ32 r12d, 24, "torch = 6 quads"
    mov     r13d, 0x7FFF                        ; min y
    mov     r14d, -0x8000                       ; max y
    xor     edi, edi
.v:
    mov     rax, rdi
    shl     rax, 4
    movsx   eax, word [rsi + rax + VERTEX.y]
    cmp     eax, r13d
    cmovl   r13d, eax
    cmp     eax, r14d
    cmovg   r14d, eax
    inc     edi
    cmp     edi, r12d
    jb      .v
    CHECK_EQ32 r13d, (40 - 64)*256, "bottom = (40 - 64) * 256"
    CHECK_EQ32 r14d, (40 - 64)*256 + 160, "top = bottom + 10/16 * 256"
    movsx   eax, word [rsi + VERTEX.x]
    mov     ebx, eax
    xor     ecx, ecx
    cmp     ebx, 8*256 + 112
    sete    cl
    cmp     ebx, 8*256 + 144
    sete    al
    or      cl, al
    movzx   ebx, cl
    CHECK_TRUE ebx, "torch side at 8 + 7/16 or 8 + 9/16, exact"
ENDP

; 4096 lanterns = 180224 verts: more than the 16-bit ibo covers (render draws it
; in batches) and the whole MJ_BUF reserve, committed 128k at a time
PROC tv_worst_case_section
    TEST "vertex: worst-case section"
    call    mh_reset
    mov     rbx, rax
    lea     rcx, [rbx + CHUNK_BLOCKS + 2*4096]
    mov     edx, B_LANTERN
    mov     r8d, 4096
    call    mh_fill
    mov     dword [rbx + CHUNK.dirty], 0xFF
    mov     rcx, rbx
    mov     edx, 2
    call    mesher_build_section
    mov     rcx, rbx
    mov     edx, 2
    xor     r8d, r8d
    call    tv_buf
    mov     rsi, rax
    mov     r12d, edx
    CHECK_EQ32 r12d, WORST_VERTS, "no quad dropped"
    mov     eax, [rbx + CHUNK.vbo + 4*4]
    and     eax, 63
    lea     rcx, [rel fake_cap_size]
    mov     r13, [rcx + rax*8]
    CHECK_EQ r13, WORST_VERTS*VERTEX_STRIDE, "uploaded size"
    ; last vertex still a lantern corner (tile 85), not garbage
    mov     eax, r12d
    dec     eax
    shl     rax, 4
    movzx   r13d, byte [rsi + rax + VERTEX.tile]
    CHECK_EQ32 r13d, 85, "last vertex has the lantern tile"
    ; an empty build trims the commit, then the big one has to grow back
    mov     rcx, rbx
    mov     edx, 3
    call    mesher_build_section
    mov     dword [rbx + CHUNK.dirty], 0xFF
    mov     rcx, rbx
    mov     edx, 2
    call    mesher_build_section
    mov     rcx, rbx
    mov     edx, 2
    xor     r8d, r8d
    call    tv_buf
    mov     r12d, edx
    CHECK_EQ32 r12d, WORST_VERTS, "same again after a trim"
ENDP
