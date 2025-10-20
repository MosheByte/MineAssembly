; 16x16x16 section -> 16B packed vertex streams (opaque/cutout + translucent)
%define IMPL_MESHER
%include "common.inc"

extern cm_task_push

%define PADW        18                  ; idx = (x+1) + (z+1)*18 + (y+1)*324
%define PADA        (18*18)
%define PADV        (18*18*18)
%define PD(dx,dy,dz) ((dx)+(dz)*PADW+(dy)*PADA)

%define BR          4
%define BW          (16 + 2*BR)
%define BC_TAB_XMM  ((BIOME_COUNT*4 + 15) / 16)

; worst case = section full of lanterns, 11 quads each. render draws anything
; past 65536 verts in 16-bit index batches
%define MAXV        (4096*44)
%define MJ_BUF      (MAXV*VERTEX_STRIDE)    ; reserved per pass, committed as it fills
%define MJ_STEP     (128*1024)
%define MJ_KEEP     (1024*1024)             ; more than this committed -> trim after upload

%define MJ_SLOTS    64
%define MJS_FREE    0
%define MJS_QUEUED  1                       ; worker owns it
%define MJS_DONE    2                       ; main owns it, result not uploaded yet

%define MEM_DECOMMIT 0x4000

; stage vertex, floats. x/z chunk local, y absolute. emit_stage packs these
struc SV
    .x          resd 1
    .y          resd 1
    .z          resd 1
    .u          resd 1
    .v          resd 1
    .sky        resb 1          ; light*17
    .blk        resb 1
    .shade      resb 1          ; face shade * AO
    .flags      resb 1          ; bit0 sway, bit1 liquid top
    .r          resb 1
    .g          resb 1
    .b          resb 1
    .a          resb 1
endstruc

; read by the chunk shader
%define VF_WAVE     1
%define VF_LIQUID   2
%define VF_FASTLEAF 4
%define VF_GRASSSIDE 8                  ; grass side: only tint the green fringe

; texels, x0 | y0<<8 | x1<<16 | y1<<24
%define RECT(a,b,c,d) ((a) | ((b)<<8) | ((c)<<16) | ((d)<<24))
%define RECT_FULL   RECT(0,0,16,16)

; ABGR, DEF_* = fallback while a biome table is still empty
%define TINT_PINE_RGBA    0xFF619961
%define TINT_BIRCH_RGBA   0xFF55A780
%define DEF_GRASS_RGBA    0xFF5AC079
%define DEF_FOLIAGE_RGBA  0xFF30AE59
%define DEF_WATER_RGBA    0xFFE4763F

; 32 bytes: pos as 0/1 floats, then padded deltas side1/side2/diag for AO.
; c*0x3F800000 -> 0.0f/1.0f
%macro FCORNER 6
    %assign %%sx ((%4)*2-1)
    %assign %%sy ((%5)*2-1)
    %assign %%sz ((%6)*2-1)
    %if (%1) != 0
        %assign %%a1 PD(%1, %%sy, 0)
        %assign %%a2 PD(%1, 0, %%sz)
        %assign %%a3 PD(%1, %%sy, %%sz)
    %elif (%2) != 0
        %assign %%a1 PD(%%sx, %2, 0)
        %assign %%a2 PD(0, %2, %%sz)
        %assign %%a3 PD(%%sx, %2, %%sz)
    %else
        %assign %%a1 PD(%%sx, 0, %3)
        %assign %%a2 PD(0, %%sy, %3)
        %assign %%a3 PD(%%sx, %%sy, %3)
    %endif
    dd (%4)*0x3F800000, (%5)*0x3F800000, (%6)*0x3F800000
    dd %%a1, %%a2, %%a3, 0, 0
%endmacro

section .rdata
align 16
; corners BL BR TR TL seen from outside (ccw = front), v0 is the top of the tile
face_tab:
    FCORNER  1,0,0,  1,0,1
    FCORNER  1,0,0,  1,0,0
    FCORNER  1,0,0,  1,1,0
    FCORNER  1,0,0,  1,1,1
    FCORNER -1,0,0,  0,0,0
    FCORNER -1,0,0,  0,0,1
    FCORNER -1,0,0,  0,1,1
    FCORNER -1,0,0,  0,1,0
    ; top: -Z is texture up
    FCORNER  0,1,0,  0,1,1
    FCORNER  0,1,0,  1,1,1
    FCORNER  0,1,0,  1,1,0
    FCORNER  0,1,0,  0,1,0
    FCORNER  0,-1,0, 1,0,1
    FCORNER  0,-1,0, 0,0,1
    FCORNER  0,-1,0, 0,0,0
    FCORNER  0,-1,0, 1,0,0
    FCORNER  0,0,1,  0,0,1
    FCORNER  0,0,1,  1,0,1
    FCORNER  0,0,1,  1,1,1
    FCORNER  0,0,1,  0,1,1
    FCORNER  0,0,-1, 1,0,0
    FCORNER  0,0,-1, 0,0,0
    FCORNER  0,0,-1, 0,1,0
    FCORNER  0,0,-1, 1,1,0

face_ndelta:
    dd PD(1,0,0), PD(-1,0,0), PD(0,1,0), PD(0,-1,0), PD(0,0,1), PD(0,0,-1)

; face_edge = local coord where that face's neighbour lands in the padding
face_axis:  db 0, 0, 1, 1, 2, 2
face_edge:  db 15, 0, 15, 0, 15, 0

face_nvec:
    dd  1.0, 0.0, 0.0,   -1.0, 0.0, 0.0
    dd  0.0, 1.0, 0.0,    0.0,-1.0, 0.0
    dd  0.0, 0.0, 1.0,    0.0, 0.0,-1.0

corner_uoff: db 0, 8, 8, 0
corner_voff: db 12, 12, 4, 4

; round(255 * face shade * ao). ao .5/.65/.8/1, X .6, top 1, bottom .5, Z .8
shade_tab:
    db  77,  99, 122, 153
    db  77,  99, 122, 153
    db 128, 166, 204, 255
    db  64,  83, 102, 128
    db 102, 133, 163, 204
    db 102, 133, 163, 204

; bits 1 side1, 2 side2, 4 corner -> ao level
ao_tab: db 3, 2, 2, 0, 2, 1, 1, 0

; ceil(65536/n), saves a div
align 4
recip: dd 0, 65536, 32768, 21846, 16384

; stage corner -> output vertex. row 0 splits on 0-2, row 1 on 1-3,
; row 2 is the same quad flipped (back side)
emit_order:
    db 0, 1, 2, 3
    db 1, 2, 3, 0
    db 0, 3, 2, 1

; ids 80..91. water level k -> (8-k)/9, lava only flows 3 so (8-2k)/9
align 4
liq_h:
    dd 0.888889, 0.777778, 0.666667, 0.555556, 0.444444, 0.333333, 0.222222, 0.111111
    dd 0.888889, 0.666667, 0.444444, 0.222222

; tent weights, x4 lanes
align 16
bc_wvec:
    %assign k 0
    %rep 2*BR+1
    times 4 dd (BR+1) - (k > BR ? k-BR : BR-k)
    %assign k k+1
    %endrep
f_inv625:  dd 0.0016, 0.0016, 0.0016, 0.0016

nb_dx: db -1, 0, 1, -1, 0, 1, -1, 0, 1
nb_dz: db -1,-1,-1,  0, 0, 0,  1, 1, 1

align 16
f_pbias:   dd 0.0, -64.0, 0.0, 0.0             ; stage -> VERTEX: pos *256 (y - 64), u *2048
f_pack:    dd 256.0, 256.0, 256.0, 2048.0
f_uvpack:  dd 2048.0
f_one:     dd 1.0
f_half:    dd 0.5
f_inset:   dd 0.0009765625            ; 1/1024, keeps mips from bleeding
f_texel:   dd 0.00390625
f_tile:    dd 0.0625
f_16th:    dd 0.0625
f_jitter:  dd 0.015625                ; plant offset step, +-0.117 max
f_four:    dd 4.0
f_plant_lo: dd 0.05
f_plant_hi: dd 0.95

box_full:       dd 0.0, 0.0, 0.0, 1.0, 1.0, 1.0
box_torch:      dd 0.4375, 0.0, 0.4375, 0.5625, 0.625, 0.5625
box_lantern:    dd 0.3125, 0.0, 0.3125, 0.6875, 0.4375, 0.6875
box_lantern_cap: dd 0.375, 0.4375, 0.375, 0.625, 0.5625, 0.625

; one section's worth of work. inputs at the top, then the mesher's scratch
struc MJ
    .fn         resq 1          ; cm_task_push calls [job](job), keep it first
    .state      resd 1          ; MJS_*
    .sec        resd 1
    .chunk      resq 1          ; main thread only, 0 = cancelled
    .cx         resd 1
    .cz         resd 1
    .empty      resd 1          ; all air, nothing to run
    .bc_valid   resd 1
    .buf        resq 2          ; per pass, MJ_BUF reserved
    .cur        resq 2
    .end        resq 2          ; committed up to here
    .nb         resq 9          ; main thread only, during the copy
    alignb 16
    .stage      resb 4*SV_size + 16
    .m_uv       resd 4
    .m_cval     resd 4
    .m_hgt      resd 4          ; liquid corner heights [cz*2+cx]
    .m_box      resd 6
    .m_inset    resd 1
    .m_tu0      resd 1          ; tile origin in 1/8 texels
    .m_tv0      resd 1
    .m_tilebits resd 1          ; tile << 24
    .m_sec      resd 1
    .m_id       resd 1
    .m_p        resd 1
    .m_col      resd 1
    .m_lpos     resd 3
    .m_bx       resd 1
    .m_by       resd 1
    .m_bz       resd 1
    .m_wx       resd 1
    .m_wy       resd 1
    .m_wz       resd 1
    .m_pass     resd 1
    .m_vflags   resd 1
    .m_face_flags resd 1
    .m_smooth   resd 1
    .m_fancy    resd 1
    .m_noao     resd 1
    .m_lkind    resd 1          ; 1 water, 2 lava
    .m_own_light resd 1
    .m_center_light resd 1
    alignb 16
    .pad_blk    resb PADV + 64
    .pad_light  resb PADV + 64
    alignb 16
    .pad_biome  resb BW*BW
    alignb 16
    .bc_prev_map resb BW*BW
    .bc_prev_col resb BC_TAB_XMM*16*3
    .bc_pcol    resd 3*BW*BW
    alignb 16
    .bc_hacc    resb 3*BW*16*16 ; horizontal sums [t][pz][x], 4x int32
    .occ        resb 768
    alignb 16
    .col_tab    resd 256*3      ; blurred grass, foliage, water
    alignb 64
endstruc

section .bss
alignb 64
mj_pool:    resb MJ_size * (MJ_SLOTS + 1)   ; the extra one is mesher_build_section's
mj_async:   resd 1                          ; last cm_task_push worked

section .text

; (rcx CHUNK*, edx section) the old synchronous way: copy, mesh, upload, all on
; this thread. the tests use it
PROC mesher_build_section, 0
    mov     r15, rbp                            ; ENDP wants the frame back
    lea     rbp, [rel mj_pool + MJ_size*MJ_SLOTS]
    call    mj_begin
    call    mj_run
    call    mj_upload
    mov     rbp, r15
ENDP

; (rcx CHUNK*, edx section) -> eax 0 pool full, 1 on a worker (or all air),
; 2 meshed right here because there are no workers.
; caller skips sections mesher_busy reports
PROC mesher_submit, 0
    mov     r15, rbp
    mov     r12, rcx
    mov     r13d, edx
    ; free slot, and a finished one for this very section is stale now: drop it
    lea     rbx, [rel mj_pool]
    xor     edi, edi
    xor     esi, esi
.scan:
    mov     eax, [rbx + MJ.state]
    cmp     eax, MJS_DONE
    jne     .nostale
    cmp     [rbx + MJ.chunk], r12
    jne     .next
    cmp     [rbx + MJ.sec], r13d
    jne     .next
    mov     dword [rbx + MJ.state], MJS_FREE
    xor     eax, eax
.nostale:
    test    eax, eax
    jnz     .next
    test    rdi, rdi
    cmovz   rdi, rbx
.next:
    add     rbx, MJ_size
    inc     esi
    cmp     esi, MJ_SLOTS
    jb      .scan
    xor     eax, eax
    test    rdi, rdi
    jz      .done
    mov     rbp, rdi
    mov     rcx, r12
    mov     edx, r13d
    call    mj_begin
    mov     dword [rbp + MJ.state], MJS_DONE
    cmp     dword [rbp + MJ.empty], 0
    jne     .empty
    lea     rax, [rel mesher_task]
    mov     [rbp + MJ.fn], rax
    mov     dword [rbp + MJ.state], MJS_QUEUED
    mov     rcx, rbp
    call    cm_task_push
    mov     [rel mj_async], eax
    test    eax, eax
    jnz     .done
    call    mj_run
    mov     dword [rbp + MJ.state], MJS_DONE
    mov     eax, 2
    jmp     .done
.empty:
    ; costs next to nothing, but without workers it counts like a real one
    mov     eax, [rel mj_async]
    xor     eax, 1
    inc     eax
.done:
    mov     rbp, r15
ENDP

; worker side, rcx = job. publish with xchg: everything the run wrote is
; visible to main before it can see DONE
PROC mesher_task, 0
    mov     r15, rbp
    mov     rbp, rcx
    call    mj_run
    mov     eax, MJS_DONE
    xchg    [rbp + MJ.state], eax
    mov     rbp, r15
ENDP

; rcx CHUNK* -> eax bit per section still on a worker, edx bit per section with
; any job (finished but not uploaded included)
PROC mesher_busy, 0
    xor     eax, eax
    xor     edx, edx
    lea     r8, [rel mj_pool]
    xor     r9d, r9d
.l:
    mov     r10d, [r8 + MJ.state]
    test    r10d, r10d
    jz      .n
    cmp     [r8 + MJ.chunk], rcx
    jne     .n
    mov     r11d, [r8 + MJ.sec]
    bts     edx, r11d
    cmp     r10d, MJS_QUEUED
    jne     .n
    bts     eax, r11d
.n:
    add     r8, MJ_size
    inc     r9d
    cmp     r9d, MJ_SLOTS
    jb      .l
ENDP

; rcx CHUNK* is going away. its jobs keep running but nobody uploads them
PROC mesher_cancel, 0
    lea     r8, [rel mj_pool]
    xor     r9d, r9d
.l:
    cmp     dword [r8 + MJ.state], MJS_FREE
    je      .n
    cmp     [r8 + MJ.chunk], rcx
    jne     .n
    mov     qword [r8 + MJ.chunk], 0
    cmp     dword [r8 + MJ.state], MJS_DONE
    jne     .n
    mov     dword [r8 + MJ.state], MJS_FREE
.n:
    add     r8, MJ_size
    inc     r9d
    cmp     r9d, MJ_SLOTS
    jb      .l
ENDP

; ecx upload budget -> eax uploaded. finished jobs -> vbos. a LIT chunk's first
; mesh goes up in one piece, once nothing of it is dirty or on a worker, so it
; never shows with holes. unless the pool runs low, then whatever is done goes
; up. LIT + clean + no jobs left = READY
PROC mesher_collect, 16
    mov     r15, rbp
    mov     LOC(0), ecx
    xor     r14d, r14d
    lea     rbx, [rel mj_pool]
    xor     ecx, ecx
    xor     esi, esi
.cnt:
    cmp     dword [rbx + MJ.state], MJS_FREE
    jne     .cn
    inc     ecx
.cn:
    add     rbx, MJ_size
    inc     esi
    cmp     esi, MJ_SLOTS
    jb      .cnt
    mov     LOC(4), ecx                         ; free slots

    lea     rbx, [rel mj_pool]
    xor     esi, esi
.l:
    cmp     dword [rbx + MJ.state], MJS_DONE
    jne     .n
    mov     rdi, [rbx + MJ.chunk]
    test    rdi, rdi
    jz      .drop
    cmp     dword [rdi + CHUNK.state], CS_LIT
    jne     .budget
    cmp     dword LOC(4), MJ_SLOTS/4
    jb      .go
    cmp     dword [rdi + CHUNK.dirty], 0
    jne     .n
    mov     rcx, rdi
    call    mesher_busy
    test    eax, eax
    jnz     .n
    jmp     .go
.budget:
    cmp     r14d, LOC(0)
    jge     .n                          ; signed, LIT groups can overdraw it
.go:
    mov     rbp, rbx
    call    mj_upload
    inc     r14d
    mov     dword [rbx + MJ.state], MJS_FREE
    inc     dword LOC(4)
    cmp     dword [rdi + CHUNK.state], CS_LIT
    jne     .n
    cmp     dword [rdi + CHUNK.dirty], 0
    jne     .n
    mov     rcx, rdi
    call    mesher_busy
    test    edx, edx
    jnz     .n
    mov     eax, CS_LIT
    mov     ecx, CS_READY
    lock cmpxchg [rdi + CHUNK.state], ecx
    jmp     .n
.drop:
    mov     dword [rbx + MJ.state], MJS_FREE
    inc     dword LOC(4)
.n:
    add     rbx, MJ_size
    inc     esi
    cmp     esi, MJ_SLOTS
    jb      .l
    mov     eax, r14d
    mov     rbp, r15
ENDP

; main thread, rbp = job, rcx CHUNK*, edx section. snapshot everything the run
; needs. the dirty bit goes first: an edit after this re-sets it and the section
; gets another job once this one is in
mj_begin:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    sub     rsp, 40
    mov     r12, rcx
    mov     r13d, edx
    mov     [rbp + MJ.chunk], rcx
    mov     [rbp + MJ.sec], edx
    mov     [rbp + MJ.m_sec], edx
    mov     eax, [r12 + CHUNK.cx]
    mov     [rbp + MJ.cx], eax
    mov     eax, [r12 + CHUNK.cz]
    mov     [rbp + MJ.cz], eax
    mov     eax, [rel g_settings + SETTINGS.smooth_light]
    mov     [rbp + MJ.m_smooth], eax
    mov     eax, [rel g_settings + SETTINGS.fancy_leaves]
    mov     [rbp + MJ.m_fancy], eax
    call    mj_buffers
    lock btr dword [r12 + CHUNK.dirty], r13d

    ; all air -> nothing to run, the upload frees the old vbos
    mov     dword [rbp + MJ.empty], 1
    mov     eax, r13d
    shl     eax, 12
    lea     rsi, [r12 + CHUNK_BLOCKS + rax]
    pxor    xmm0, xmm0
    xor     ecx, ecx
.scan:
    movdqu  xmm1, [rsi+rcx]
    por     xmm0, xmm1
    movdqu  xmm2, [rsi+rcx+16]
    por     xmm0, xmm2
    add     ecx, 32
    cmp     ecx, 4096
    jb      .scan
    ptest   xmm0, xmm0
    jz      .done
    mov     dword [rbp + MJ.empty], 0

    xor     ebx, ebx
.nb_loop:
    mov     rax, r12
    cmp     ebx, 4
    je      .nb_store
    lea     rdx, [rel nb_dx]
    movsx   ecx, byte [rdx+rbx]
    add     ecx, [r12+CHUNK.cx]
    lea     rdx, [rel nb_dz]
    movsx   edx, byte [rdx+rbx]
    add     edx, [r12+CHUNK.cz]
    call    world_get_chunk
    test    rax, rax
    jz      .nb_store
    cmp     dword [rax+CHUNK.state], CS_GENERATED
    jae     .nb_store
    xor     eax, eax                            ; half-generated, pretend it's not there
.nb_store:
    mov     [rbp + MJ.nb + rbx*8], rax
    inc     ebx
    cmp     ebx, 9
    jb      .nb_loop
    call    fill_padded
    call    fill_biome
.done:
    add     rsp, 40
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; main thread, rbp = job not in flight. first use reserves the vertex space,
; later ones give back what a monster section left committed. cur = start
mj_buffers:
    push    rbx
    push    rsi
    sub     rsp, 40
    mov     rbx, [rbp + MJ.buf]
    test    rbx, rbx
    jnz     .have
    xor     ecx, ecx
    mov     edx, 2*MJ_BUF
    mov     r8d, MEM_RESERVE
    mov     r9d, PAGE_READWRITE
    call    VirtualAlloc
    mov     rbx, rax
    test    rax, rax
    jz      .reset                              ; no space, every quad gets dropped
    mov     [rbp + MJ.buf], rax
    mov     [rbp + MJ.end], rax
    add     rax, MJ_BUF
    mov     [rbp + MJ.buf + 8], rax
    mov     [rbp + MJ.end + 8], rax
    jmp     .reset
.have:
    xor     esi, esi
.trim:
    mov     rbx, [rbp + MJ.buf + rsi*8]
    mov     rdx, [rbp + MJ.end + rsi*8]
    sub     rdx, rbx
    cmp     rdx, MJ_KEEP
    jbe     .tn
    lea     rcx, [rbx + MJ_STEP]
    sub     rdx, MJ_STEP
    mov     r8d, MEM_DECOMMIT
    call    VirtualFree
    lea     rax, [rbx + MJ_STEP]
    mov     [rbp + MJ.end + rsi*8], rax
.tn:
    inc     esi
    cmp     esi, 2
    jb      .trim
.reset:
    mov     rax, [rbp + MJ.buf]
    mov     [rbp + MJ.cur], rax
    mov     rax, [rbp + MJ.buf + 8]
    mov     [rbp + MJ.cur + 8], rax
    add     rsp, 40
    pop     rsi
    pop     rbx
    ret

; any thread, rbp = job. only reads the job and the static block tables
mj_run:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15
    cmp     dword [rbp + MJ.empty], 0
    jne     .done
    mov     r13d, [rbp + MJ.sec]

    ; occ / +256 light-only blocker (lava, sky stored 0) / +512 'filled' for the
    ; leaf test. redone every job since fancy leaves can toggle
    lea     rsi, [rel blk_flags]
    lea     rdi, [rbp + MJ.occ]
    lea     r8, [rel blk_opacity]
    xor     ecx, ecx
.occ_loop:
    movzx   eax, word [rsi+rcx*2]
    xor     edx, edx
    test    eax, BF_OPAQUE
    setnz   dl
    test    eax, BF_LEAVES | BF_OPAQUE
    setnz   byte [rdi+rcx+512]
    test    eax, BF_LEAVES
    jz      .occ_store
    cmp     dword [rbp + MJ.m_fancy], 0
    jne     .occ_store
    mov     edx, 1
.occ_store:
    mov     [rdi+rcx], dl
    xor     eax, eax
    test    edx, edx
    jnz     .occ_lopq_st                        ; occluders never get sampled anyway
    cmp     byte [r8+rcx], 15
    sete    al
.occ_lopq_st:
    mov     [rdi+rcx+256], al
    inc     ecx
    cmp     ecx, 256
    jb      .occ_loop

    call    build_biome_colors

    xor     r14d, r14d                          ; ly
.ly_loop:
    xor     r15d, r15d                          ; lz
.lz_loop:
    imul    esi, r14d, PADA
    imul    eax, r15d, PADW
    lea     esi, [rsi + rax + PADA + PADW + 1]
    xor     ebx, ebx                            ; lx
.lx_loop:
    movzx   edi, byte [rbp + MJ.pad_blk + rsi]
    test    edi, edi
    jz      .lx_next
    call    mesh_block
.lx_next:
    inc     esi
    inc     ebx
    cmp     ebx, 16
    jb      .lx_loop
    inc     r15d
    cmp     r15d, 16
    jb      .lz_loop
    inc     r14d
    cmp     r14d, 16
    jb      .ly_loop
.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; main thread, rbp = job -> its chunk's vbos [sec*2 + pass], sec_flags
mj_upload:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 32
    mov     r12, [rbp + MJ.chunk]
    mov     r13d, [rbp + MJ.sec]
    xor     r14d, r14d                          ; sec_flags
    xor     ebx, ebx
.up_loop:
    mov     rdi, [rbp + MJ.buf + rbx*8]
    mov     rsi, [rbp + MJ.cur + rbx*8]
    sub     rsi, rdi
    lea     r15d, [r13*2 + rbx]                 ; vbo slot = s*2 + pass
    test    rsi, rsi
    jnz     .up_data
    mov     dword [r12 + CHUNK.vcount + r15*4], 0
    cmp     dword [r12 + CHUNK.vbo + r15*4], 0
    je      .up_next
    mov     rax, [rel pglDeleteBuffers]
    test    rax, rax
    jz      .up_next
    mov     ecx, 1
    lea     rdx, [r12 + CHUNK.vbo + r15*4]
    call    rax
    mov     dword [r12 + CHUNK.vbo + r15*4], 0
    jmp     .up_next
.up_data:
    mov     eax, 1
    mov     ecx, ebx
    shl     eax, cl
    or      r14d, eax
    cmp     dword [r12 + CHUNK.vbo + r15*4], 0
    jne     .up_have
    mov     ecx, 1
    lea     rdx, [r12 + CHUNK.vbo + r15*4]
    call    [rel pglGenBuffers]
.up_have:
    mov     ecx, GL_ARRAY_BUFFER
    mov     edx, [r12 + CHUNK.vbo + r15*4]
    call    [rel pglBindBuffer]
    mov     ecx, GL_ARRAY_BUFFER
    mov     rdx, rsi
    mov     r8, rdi
    mov     r9d, GL_STATIC_DRAW
    call    [rel pglBufferData]
    mov     ecx, GL_ARRAY_BUFFER
    xor     edx, edx
    call    [rel pglBindBuffer]
    shr     rsi, 4                              ; VERTEX_STRIDE
    mov     [r12 + CHUNK.vcount + r15*4], esi
.up_next:
    inc     ebx
    cmp     ebx, 2
    jb      .up_loop
    mov     [r12 + CHUNK.sec_flags + r13], r14b
    lock inc dword [rel g_stat_meshes_built]
    add     rsp, 32
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; section + 1 block border -> pad_blk/pad_light. trashes rax rcx rdx r8-r11
fill_padded:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15
    xor     r14d, r14d
.fy:
    mov     eax, [rbp + MJ.m_sec]
    shl     eax, 4
    lea     r13d, [rax + r14 - 1]
    imul    r12d, r14d, PADA
    cmp     r13d, 0
    jl      .below
    cmp     r13d, CHUNK_H
    jge     .above
    xor     r15d, r15d
.fz:
    lea     eax, [r15 - 1]
    mov     ebx, 1
    cmp     eax, 0
    jge     .fz1
    xor     ebx, ebx
    jmp     .fz2
.fz1:
    cmp     eax, 15
    jle     .fz2
    mov     ebx, 2
.fz2:
    and     eax, 15
    shl     eax, 4
    mov     ecx, r13d
    shl     ecx, 8
    add     eax, ecx
    mov     r11d, eax
    imul    edi, r15d, PADW
    add     edi, r12d
    lea     r8, [rbp + MJ.pad_blk]
    lea     r9, [rbp + MJ.pad_light]
    lea     r10, [rbp + MJ.nb]
    imul    ebx, ebx, 3
    mov     rsi, [r10 + rbx*8]
    test    rsi, rsi
    jz      .w_miss
    lea     ecx, [r11 + 15]
    movzx   eax, byte [rsi + CHUNK_BLOCKS + rcx]
    mov     [r8 + rdi], al
    movzx   eax, byte [rsi + CHUNK_LIGHT + rcx]
    mov     [r9 + rdi], al
    jmp     .center
.w_miss:
    mov     byte [r8 + rdi], 0
    mov     byte [r9 + rdi], 0xF0
.center:
    mov     rsi, [r10 + rbx*8 + 8]
    test    rsi, rsi
    jz      .c_miss
    movdqu  xmm0, [rsi + CHUNK_BLOCKS + r11]
    movdqu  [r8 + rdi + 1], xmm0
    movdqu  xmm0, [rsi + CHUNK_LIGHT + r11]
    movdqu  [r9 + rdi + 1], xmm0
    jmp     .east
.c_miss:
    pxor    xmm0, xmm0
    movdqu  [r8 + rdi + 1], xmm0
    mov     eax, 0xF0F0F0F0
    movd    xmm0, eax
    pshufd  xmm0, xmm0, 0
    movdqu  [r9 + rdi + 1], xmm0
.east:
    mov     rsi, [r10 + rbx*8 + 16]
    test    rsi, rsi
    jz      .e_miss
    movzx   eax, byte [rsi + CHUNK_BLOCKS + r11]
    mov     [r8 + rdi + 17], al
    movzx   eax, byte [rsi + CHUNK_LIGHT + r11]
    mov     [r9 + rdi + 17], al
    jmp     .fz_next
.e_miss:
    mov     byte [r8 + rdi + 17], 0
    mov     byte [r9 + rdi + 17], 0xF0
.fz_next:
    inc     r15d
    cmp     r15d, 18
    jb      .fz
    jmp     .fy_next
.below:                                         ; under the world, bedrock + dark
    lea     rdi, [rbp + MJ.pad_blk]
    add     rdi, r12
    mov     al, B_BEDROCK
    mov     ecx, PADA
    rep     stosb
    lea     rdi, [rbp + MJ.pad_light]
    add     rdi, r12
    xor     eax, eax
    mov     ecx, PADA
    rep     stosb
    jmp     .fy_next
.above:                                         ; above the top, open sky
    lea     rdi, [rbp + MJ.pad_blk]
    add     rdi, r12
    xor     eax, eax
    mov     ecx, PADA
    rep     stosb
    lea     rdi, [rbp + MJ.pad_light]
    add     rdi, r12
    mov     al, 0xF0
    mov     ecx, PADA
    rep     stosb
.fy_next:
    inc     r14d
    cmp     r14d, 18
    jb      .fy
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; tint per column -> col_tab. a job slot often gets the next section of the same
; chunk, so if the 24x24 biome map + colour tables match its last one we keep col_tab.
; 9 tap tent (sum 625). a 3x3 box leaves hard diagonal seams between biomes.
; only touches xmm0-3
%macro BC_CMP_TAB 2
    lea     rax, [rel %1]
    %assign %%i 0
    %rep BC_TAB_XMM
    movdqu  xmm0, [rax + %%i*16]
    movdqa  xmm2, [rdi + %2 + %%i*16]
    pxor    xmm2, xmm0
    por     xmm1, xmm2
    movdqa  [rdi + %2 + %%i*16], xmm0
    %assign %%i %%i+1
    %endrep
%endmacro

; fallback if the table entry is still 0
%macro BC_PCOL 3
    lea     r8, [rel %1]
    mov     edx, [r8 + rcx*4]
    mov     r9d, %2
    test    edx, edx
    cmovz   edx, r9d
    mov     [rdi + %3*BW*BW*4 + rbx*4], edx
%endmacro

; main thread: 24x24 biome ids around the chunk -> pad_biome
fill_biome:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15
    lea     r12, [rbp + MJ.nb]
    mov     r13, [r12 + 4*8]
    xor     r15d, r15d
.row:
    lea     eax, [r15 - BR]
    mov     ebx, 1
    mov     ecx, eax
    cmp     eax, 0
    jge     .r1
    xor     ebx, ebx
    xor     ecx, ecx
.r1:
    cmp     eax, 15
    jle     .r2
    mov     ebx, 2
    mov     ecx, 15
.r2:
    and     eax, 15
    shl     eax, 4
    shl     ecx, 4
    lea     r14, [r13 + CHUNK.biome + rcx]      ; fallback row for missing chunks
    imul    edi, r15d, BW
    lea     rsi, [rbp + MJ.pad_biome]
    add     rdi, rsi
    imul    ebx, ebx, 3
    mov     rsi, [r12 + rbx*8]
    test    rsi, rsi
    jz      .w_miss
    mov     ecx, [rsi + CHUNK.biome + rax + 16 - BR]
    jmp     .w_st
.w_miss:
    movzx   ecx, byte [r14]
    imul    ecx, ecx, 0x01010101
.w_st:
    mov     [rdi], ecx
    mov     rsi, [r12 + rbx*8 + 8]
    lea     rcx, [rsi + CHUNK.biome + rax]
    test    rsi, rsi
    cmovz   rcx, r14
    movdqu  xmm0, [rcx]
    movdqu  [rdi + BR], xmm0
    mov     rsi, [r12 + rbx*8 + 16]
    test    rsi, rsi
    jz      .e_miss
    mov     ecx, [rsi + CHUNK.biome + rax]
    jmp     .e_st
.e_miss:
    movzx   ecx, byte [r14 + 15]
    imul    ecx, ecx, 0x01010101
.e_st:
    mov     [rdi + BR + 16], ecx
    inc     r15d
    cmp     r15d, BW
    jb      .row
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; any thread: pad_biome -> col_tab
build_biome_colors:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15
    ; same inputs as this job's last section?
    lea     rsi, [rbp + MJ.pad_biome]
    lea     rdi, [rbp + MJ.bc_prev_map]
    pxor    xmm1, xmm1
    xor     ecx, ecx
.cmp_map:
    movdqa  xmm0, [rsi + rcx]
    movdqa  xmm2, [rdi + rcx]
    pxor    xmm2, xmm0
    por     xmm1, xmm2
    movdqa  [rdi + rcx], xmm0
    add     ecx, 16
    cmp     ecx, BW*BW
    jb      .cmp_map
    lea     rdi, [rbp + MJ.bc_prev_col]
    BC_CMP_TAB biome_grass_color, 0
    BC_CMP_TAB biome_foliage_color, BC_TAB_XMM*16
    BC_CMP_TAB biome_water_color, BC_TAB_XMM*32
    mov     eax, 1
    xchg    eax, [rbp + MJ.bc_valid]
    test    eax, eax
    jz      .compute
    ptest   xmm1, xmm1
    jz      .done                               ; cache hit

.compute:
    lea     rsi, [rbp + MJ.pad_biome]
    lea     rdi, [rbp + MJ.bc_pcol]
    xor     ebx, ebx
.pc:
    movzx   ecx, byte [rsi + rbx]
    cmp     ecx, BIOME_COUNT
    jb      .pc_ok
    xor     ecx, ecx
.pc_ok:
    BC_PCOL biome_grass_color, DEF_GRASS_RGBA, 0
    BC_PCOL biome_foliage_color, DEF_FOLIAGE_RGBA, 1
    BC_PCOL biome_water_color, DEF_WATER_RGBA, 2
    inc     ebx
    cmp     ebx, BW*BW
    jb      .pc

    lea     rsi, [rbp + MJ.bc_pcol]
    lea     rdi, [rbp + MJ.bc_hacc]
    lea     r12, [rel bc_wvec]
    mov     r13d, 3*BW                          ; all 3 planes in one go
.hrow:
    xor     ebx, ebx
.hx:
    lea     rax, [rsi + rbx*4]
    pxor    xmm1, xmm1
    %assign k 0
    %rep 2*BR+1
    pmovzxbd xmm0, [rax + k*4]
    pmulld  xmm0, [r12 + k*16]
    paddd   xmm1, xmm0
    %assign k k+1
    %endrep
    movdqa  [rdi], xmm1
    add     rdi, 16
    inc     ebx
    cmp     ebx, 16
    jb      .hx
    add     rsi, BW*4
    dec     r13d
    jnz     .hrow

    ; vertical + normalise -> col_tab[t*256 + z*16 + x]
    lea     rsi, [rbp + MJ.bc_hacc]
    lea     rdi, [rbp + MJ.col_tab]
    movaps  xmm3, [rel f_inv625]
    xor     r13d, r13d
.vt:
    xor     r14d, r14d
.vz:
    imul    eax, r13d, BW
    add     eax, r14d
    shl     eax, 8
    lea     rax, [rsi + rax]
    xor     ebx, ebx
.vx:
    pxor    xmm1, xmm1
    %assign k 0
    %rep 2*BR+1
    movdqa  xmm0, [rax + k*256]
    pmulld  xmm0, [r12 + k*16]
    paddd   xmm1, xmm0
    %assign k k+1
    %endrep
    cvtdq2ps xmm1, xmm1
    mulps   xmm1, xmm3
    cvtps2dq xmm1, xmm1
    packusdw xmm1, xmm1
    packuswb xmm1, xmm1
    movd    ecx, xmm1
    or      ecx, 0xFF000000
    mov     [rdi], ecx
    add     rdi, 4
    add     rax, 16
    inc     ebx
    cmp     ebx, 16
    jb      .vx
    inc     r14d
    cmp     r14d, 16
    jb      .vz
    inc     r13d
    cmp     r13d, 3
    jb      .vt
.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; ebx lx, r14d ly, r15d lz, esi padded idx, edi id. keeps non-volatiles
mesh_block:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15
    push    rbp
    sub     rsp, 8
    mov     [rbp + MJ.m_id], edi
    mov     [rbp + MJ.m_p], esi
    mov     [rbp + MJ.m_lpos], ebx
    mov     [rbp + MJ.m_lpos + 4], r14d
    mov     [rbp + MJ.m_lpos + 8], r15d
    mov     eax, r15d
    shl     eax, 4
    add     eax, ebx
    mov     [rbp + MJ.m_col], eax
    cvtsi2ss xmm0, ebx
    movss   [rbp + MJ.m_bx], xmm0
    mov     eax, r13d
    shl     eax, 4
    add     eax, r14d
    mov     [rbp + MJ.m_wy], eax
    cvtsi2ss xmm0, eax
    movss   [rbp + MJ.m_by], xmm0
    cvtsi2ss xmm0, r15d
    movss   [rbp + MJ.m_bz], xmm0
    mov     eax, [rbp + MJ.cx]
    shl     eax, 4
    add     eax, ebx
    mov     [rbp + MJ.m_wx], eax
    mov     eax, [rbp + MJ.cz]
    shl     eax, 4
    add     eax, r15d
    mov     [rbp + MJ.m_wz], eax
    lea     rax, [rbp + MJ.pad_light]
    movzx   eax, byte [rax + rsi]
    mov     [rbp + MJ.m_own_light], eax
    lea     rax, [rel blk_flags]
    movzx   r12d, word [rax + rdi*2]
    xor     eax, eax
    test    r12d, BF_TRANSLUCENT
    setnz   al
    mov     [rbp + MJ.m_pass], eax
    xor     eax, eax
    test    r12d, BF_LEAVES
    jz      .nl
    mov     eax, VF_WAVE
    cmp     dword [rbp + MJ.m_fancy], 0
    jne     .nl
    or      eax, VF_FASTLEAF
.nl:
    mov     [rbp + MJ.m_vflags], eax
    mov     dword [rbp + MJ.m_noao], 0
    lea     rax, [rel blk_model]
    movzx   eax, byte [rax + rdi]
    cmp     eax, MODEL_CROSS
    je      .cross
    cmp     eax, MODEL_TORCH
    je      .torch
    cmp     eax, MODEL_LIQUID
    je      .liquid
    cmp     eax, MODEL_CACTUS
    je      .cactus
    cmp     eax, MODEL_LANTERN
    je      .lantern
    call    mesh_cube
    jmp     .done
.cross:
    call    mesh_cross
    jmp     .done
.torch:
    call    mesh_torch
    jmp     .done
.liquid:
    call    mesh_liquid
    jmp     .done
.cactus:
    call    mesh_cactus
    jmp     .done
.lantern:
    call    mesh_lantern
.done:
    add     rsp, 8
    pop     rbp
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; ecx face -> eax 1 if hidden. not for liquids, trashes rax rdx r8-r11.
; fancy leaves keep leaf-leaf faces, except between two buried leaves (nobody
; sees those). can't tell across the section edge, so those get drawn
face_hidden:
    mov     edx, [rbp + MJ.m_p]
    lea     rax, [rel face_ndelta]
    add     edx, [rax + rcx*4]
    lea     rax, [rbp + MJ.pad_blk]
    movzx   r9d, byte [rax + rdx]
    lea     rax, [rbp + MJ.occ]
    cmp     byte [rax + r9], 0
    jne     .hidden
    lea     rax, [rel blk_flags]
    movzx   r8d, word [rax + r9*2]
    test    r8d, BF_LEAVES
    jz      .not_leaves
    mov     r10d, [rbp + MJ.m_id]
    test    word [rax + r10*2], BF_LEAVES
    jnz     .leaf_pair
.not_leaves:
    cmp     r9d, [rbp + MJ.m_id]
    jne     .visible
    test    r8d, BF_CULL_SAME
    jz      .visible
.hidden:
    mov     eax, 1
    ret
.visible:
    xor     eax, eax
    ret
.leaf_pair:
    lea     rax, [rel face_axis]
    movzx   r8d, byte [rax + rcx]
    lea     rax, [rel face_edge]
    movzx   r9d, byte [rax + rcx]
    lea     rax, [rbp + MJ.m_lpos]
    cmp     [rax + r8*4], r9d
    je      .visible
    ; both buried?
    lea     r10, [rbp + MJ.pad_blk]
    lea     r11, [rbp + MJ.occ + 512]
    mov     r8d, [rbp + MJ.m_p]
%macro ENCL_CHECK 2
    movzx   eax, byte [r10 + %1 + (%2)]
    cmp     byte [r11 + rax], 0
    je      .visible
%endmacro
    ENCL_CHECK r8, 1
    ENCL_CHECK r8, -1
    ENCL_CHECK r8, PADW
    ENCL_CHECK r8, -PADW
    ENCL_CHECK r8, PADA
    ENCL_CHECK r8, -PADA
    ENCL_CHECK rdx, 1
    ENCL_CHECK rdx, -1
    ENCL_CHECK rdx, PADW
    ENCL_CHECK rdx, -PADW
    ENCL_CHECK rdx, PADA
    ENCL_CHECK rdx, -PADA
    mov     eax, 1
    ret

mesh_cube:
    push    rbx
    sub     rsp, 16
    xor     ebx, ebx
.f:
    mov     ecx, ebx
    call    face_hidden
    test    eax, eax
    jnz     .skip
    mov     ecx, ebx
    call    cube_face
.skip:
    inc     ebx
    cmp     ebx, 6
    jb      .f
    add     rsp, 16
    pop     rbx
    ret

cube_face:
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 8
    mov     r12d, ecx
    mov     eax, [rbp + MJ.m_id]
    lea     eax, [rax + rax*2]
    lea     eax, [r12 + rax*2]
    lea     rdx, [rel blk_tex]
    movzx   ecx, byte [rdx + rax]
    mov     edx, RECT_FULL
    call    set_tile_rect
    mov     ecx, r12d
    call    face_tint
    mov     r14d, eax
    or      edx, [rbp + MJ.m_vflags]
    mov     [rbp + MJ.m_face_flags], edx
    lea     r13, [rel face_tab]
    mov     eax, r12d
    shl     eax, 7
    add     r13, rax
    lea     rbx, [rbp + MJ.stage]
    xor     ecx, ecx
.c:
    movss   xmm0, [r13 + 0]
    addss   xmm0, [rbp + MJ.m_bx]
    movss   [rbx + SV.x], xmm0
    movss   xmm0, [r13 + 4]
    addss   xmm0, [rbp + MJ.m_by]
    movss   [rbx + SV.y], xmm0
    movss   xmm0, [r13 + 8]
    addss   xmm0, [rbp + MJ.m_bz]
    movss   [rbx + SV.z], xmm0
    call    stage_uv_std
    mov     [rbx + SV.r], r14d
    mov     eax, [rbp + MJ.m_face_flags]
    mov     [rbx + SV.flags], al
    add     rbx, SV_size
    add     r13, 32
    inc     ecx
    cmp     ecx, 4
    jb      .c
    mov     ecx, r12d
    call    compute_face_light
    call    pick_diagonal
    mov     ecx, eax
    call    emit_stage
    add     rsp, 8
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; rbx stage vertex, ecx corner. ecx survives
stage_uv_std:
    lea     rax, [rel corner_uoff]
    movzx   edx, byte [rax + rcx]
    lea     rax, [rbp + MJ.m_uv]
    movss   xmm0, [rax + rdx]
    movss   [rbx + SV.u], xmm0
    lea     rdx, [rel corner_voff]
    movzx   edx, byte [rdx + rcx]
    movss   xmm0, [rax + rdx]
    movss   [rbx + SV.v], xmm0
    ret

; eax = 1 -> split on 1-3. brighter diagonal wins, otherwise AO looks skewed
pick_diagonal:
    lea     rdx, [rbp + MJ.m_cval]
    mov     eax, [rdx]
    add     eax, [rdx + 8]
    mov     ecx, [rdx + 4]
    add     ecx, [rdx + 12]
    cmp     eax, ecx
    setl    al
    movzx   eax, al
    ret

; ecx tile, edx rect -> m_uv as atlas floats, plus the tile for emit_stage
set_tile_rect:
    mov     eax, ecx
    and     eax, 15
    shl     eax, 4
    mov     r8d, ecx
    shr     r8d, 4
    and     r8d, 15
    shl     r8d, 4
    mov     r9d, ecx
    shl     r9d, 24
    mov     [rbp + MJ.m_tilebits], r9d
    lea     r9d, [rax*8]
    mov     [rbp + MJ.m_tu0], r9d
    lea     r9d, [r8*8]
    mov     [rbp + MJ.m_tv0], r9d
    movss   xmm3, [rel f_texel]
    movss   xmm4, [rel f_inset]
    lea     r9, [rbp + MJ.m_uv]
    movzx   r10d, dl
    add     r10d, eax
    cvtsi2ss xmm0, r10d
    mulss   xmm0, xmm3
    addss   xmm0, xmm4
    movss   [r9 + 0], xmm0
    mov     r10d, edx
    shr     r10d, 8
    and     r10d, 255
    add     r10d, r8d
    cvtsi2ss xmm0, r10d
    mulss   xmm0, xmm3
    addss   xmm0, xmm4
    movss   [r9 + 4], xmm0
    mov     r10d, edx
    shr     r10d, 16
    and     r10d, 255
    add     r10d, eax
    cvtsi2ss xmm0, r10d
    mulss   xmm0, xmm3
    subss   xmm0, xmm4
    movss   [r9 + 8], xmm0
    mov     r10d, edx
    shr     r10d, 24
    add     r10d, r8d
    cvtsi2ss xmm0, r10d
    mulss   xmm0, xmm3
    subss   xmm0, xmm4
    movss   [r9 + 12], xmm0
    ret

; ecx face -> eax ABGR tint, edx extra vflags
face_tint:
    mov     edx, [rbp + MJ.m_id]
    lea     rax, [rel blk_tint]
    movzx   eax, byte [rax + rdx]
    cmp     eax, TINT_GRASS
    je      .grass
    cmp     eax, TINT_FOLIAGE
    je      .foliage
    cmp     eax, TINT_PINE
    je      .pine
    cmp     eax, TINT_BIRCH
    je      .birch
    cmp     eax, TINT_WATER
    je      .water
.white:
    mov     eax, 0xFFFFFFFF
    xor     edx, edx
    ret
.grass:
    ; grass side = dirt + baked green fringe. VF_GRASSSIDE tints only the green
    ; texels, so the fringe follows the biome colour
    lea     rax, [rel blk_model]
    cmp     byte [rax + rdx], MODEL_CUBE
    jne     .grass_t
    cmp     ecx, FACE_PY
    je      .grass_t
    cmp     ecx, FACE_NY
    je      .white
    mov     edx, [rbp + MJ.m_col]
    lea     rax, [rbp + MJ.col_tab]
    mov     eax, [rax + rdx*4]
    mov     edx, VF_GRASSSIDE
    ret
.grass_t:
    mov     edx, [rbp + MJ.m_col]
    lea     rax, [rbp + MJ.col_tab]
    mov     eax, [rax + rdx*4]
    xor     edx, edx
    ret
.foliage:
    mov     edx, [rbp + MJ.m_col]
    lea     rax, [rbp + MJ.col_tab]
    mov     eax, [rax + rdx*4 + 1024]
    xor     edx, edx
    ret
.water:
    mov     edx, [rbp + MJ.m_col]
    lea     rax, [rbp + MJ.col_tab]
    mov     eax, [rax + rdx*4 + 2048]
    xor     edx, edx
    ret
.pine:
    mov     eax, TINT_PINE_RGBA
    xor     edx, edx
    ret
.birch:
    mov     eax, TINT_BIRCH_RGBA
    xor     edx, edx
    ret

; ecx cell, edx id, r15 pad_light, rbp job. r8d += sky, r9d += blk, r10d++
; lava stores sky 0, and averaging that in would put a dark ring around every
; lava pool at noon. so it takes max(own, C) per channel
%macro LIGHT_SAMPLE 0
    movzx   eax, byte [r15 + rcx]
    cmp     byte [rbp + MJ.occ + rdx + 256], 0
    je      %%plain
    mov     edx, eax
    and     eax, 0xF0
    mov     ecx, [rbp + MJ.m_center_light]
    and     ecx, 0xF0
    cmp     eax, ecx
    cmovb   eax, ecx
    and     edx, 0x0F
    mov     ecx, [rbp + MJ.m_center_light]
    and     ecx, 0x0F
    cmp     edx, ecx
    cmovb   edx, ecx
    or      eax, edx
%%plain:
    mov     edx, eax
    shr     eax, 4
    add     r8d, eax
    and     edx, 15
    add     r9d, edx
    inc     r10d
%endmacro

; ecx face -> sky/blk/shade for the 4 stage verts + m_cval.
; per corner: C face neighbour, S1/S2 edge cells, K diagonal. ao = 0 if S1 and S2
; are both solid (K hidden), else 3-(S1+S2+K). smooth light off -> just C
compute_face_light:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     r12d, ecx
    lea     r13, [rel face_tab]
    mov     eax, r12d
    shl     eax, 7
    add     r13, rax
    lea     r14, [rbp + MJ.pad_blk]
    lea     r15, [rbp + MJ.pad_light]
    mov     esi, [rbp + MJ.m_p]
    lea     rax, [rel face_ndelta]
    mov     edi, esi
    add     edi, [rax + r12*4]                  ; C
    ; C solid (stone right on water etc) has light 0, use our own cell
    movzx   eax, byte [r14 + rdi]
    movzx   ecx, byte [rbp + MJ.occ + rax]
    movzx   eax, byte [r15 + rdi]
    test    ecx, ecx
    jz      .cl_ok
    mov     eax, [rbp + MJ.m_own_light]
.cl_ok:
    mov     [rbp + MJ.m_center_light], eax
    lea     rbx, [rbp + MJ.stage]
    xor     edi, edi
.corner:
    mov     eax, [rbp + MJ.m_center_light]
    mov     r8d, eax
    shr     r8d, 4
    and     eax, 15
    mov     r9d, eax
    mov     r10d, 1
    xor     r11d, r11d
    cmp     dword [rbp + MJ.m_smooth], 0
    je      .flat
    mov     ecx, esi
    add     ecx, [r13 + 12]
    movzx   edx, byte [r14 + rcx]
    cmp     byte [rbp + MJ.occ + rdx], 0
    jne     .s1o
    LIGHT_SAMPLE
    jmp     .s2
.s1o:
    or      r11d, 1
.s2:
    mov     ecx, esi
    add     ecx, [r13 + 16]
    movzx   edx, byte [r14 + rcx]
    cmp     byte [rbp + MJ.occ + rdx], 0
    jne     .s2o
    LIGHT_SAMPLE
    jmp     .s3
.s2o:
    or      r11d, 2
.s3:
    mov     ecx, esi
    add     ecx, [r13 + 20]
    movzx   edx, byte [r14 + rcx]
    cmp     byte [rbp + MJ.occ + rdx], 0
    je      .s3open
    or      r11d, 4
    jmp     .avg
.s3open:
    cmp     r11d, 3                             ; both sides solid, K can't leak in
    je      .avg
    LIGHT_SAMPLE
.avg:
    lea     rax, [rel recip]
    mov     ecx, [rax + r10*4]
    imul    r8d, r8d, 17
    imul    r8d, ecx
    shr     r8d, 16
    imul    r9d, r9d, 17
    imul    r9d, ecx
    shr     r9d, 16
    lea     rax, [rel ao_tab]
    movzx   r11d, byte [rax + r11]
    cmp     dword [rbp + MJ.m_noao], 0
    je      .shade
    mov     r11d, 3
    jmp     .shade
.flat:
    imul    r8d, r8d, 17
    imul    r9d, r9d, 17
    mov     r11d, 3
.shade:
    lea     rax, [rel shade_tab]
    lea     ecx, [r11 + r12*4]
    movzx   ecx, byte [rax + rcx]
    mov     [rbx + SV.sky], r8b
    mov     [rbx + SV.blk], r9b
    mov     [rbx + SV.shade], cl
    lea     eax, [rcx*2 + r8]
    add     eax, r9d
    lea     rdx, [rbp + MJ.m_cval]
    mov     [rdx + rdi*4], eax
    add     rbx, SV_size
    add     r13, 32
    inc     edi
    cmp     edi, 4
    jb      .corner
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; ecx shade -> eax, own cell only (non-cube models)
own_light_packed:
    mov     eax, [rbp + MJ.m_own_light]
    mov     edx, eax
    shr     eax, 4
    imul    eax, eax, 17                        ; 0..15 -> 0..255
    and     edx, 15
    imul    edx, edx, 17
    shl     edx, 8
    or      eax, edx
    shl     ecx, 16
    or      eax, ecx
    mov     edx, [rbp + MJ.m_vflags]
    shl     edx, 24
    or      eax, edx
    ret

; ecx 0 normal, 1 other diagonal, 2 back side. stage floats -> 4 packed VERTEX:
; pos *256 (y - 64, so it fits a signed short), uv *2048 minus the tile origin.
; reserve used up -> quad dropped. trashes rax rcx rdx r8-r11 xmm0 xmm1
emit_stage:
    mov     eax, [rbp + MJ.m_pass]
    mov     r8, [rbp + MJ.cur + rax*8]
    lea     r9, [r8 + 4*VERTEX_STRIDE]
    cmp     r9, [rbp + MJ.end + rax*8]
    ja      .grow
.go:
    lea     r9, [rel emit_order]
    lea     r9, [r9 + rcx*4]
    xor     r11d, r11d
.l:
    movzx   ecx, byte [r9 + r11]
    imul    ecx, ecx, SV_size
    lea     r10, [rbp + MJ.stage + rcx]
    movups  xmm0, [r10]                         ; x y z u
    addps   xmm0, [rel f_pbias]
    mulps   xmm0, [rel f_pack]
    cvtps2dq xmm0, xmm0
    pextrd  ecx, xmm0, 3
    packssdw xmm0, xmm0
    movq    [r8], xmm0                          ; x y z, u v get overwritten
    sub     ecx, [rbp + MJ.m_tu0]
    mov     [r8 + VERTEX.u], cl
    movss   xmm1, [r10 + SV.v]
    mulss   xmm1, [rel f_uvpack]
    cvtss2si ecx, xmm1
    sub     ecx, [rbp + MJ.m_tv0]
    mov     [r8 + VERTEX.v], cl
    mov     edx, [r10 + SV.r]
    and     edx, 0x00FFFFFF
    or      edx, [rbp + MJ.m_tilebits]
    mov     [r8 + VERTEX.r], edx
    mov     edx, [r10 + SV.sky]
    mov     [r8 + VERTEX.sky], edx
    add     r8, VERTEX_STRIDE
    inc     r11d
    cmp     r11d, 4
    jb      .l
    mov     [rbp + MJ.cur + rax*8], r8
    ret

; commit another MJ_STEP of this pass's reserve. can be anywhere in the helper
; chain, so it lines the stack up itself and keeps every volatile it touches
.grow:
    mov     r9, [rbp + MJ.buf + rax*8]
    test    r9, r9
    jz      .drop
    add     r9, MJ_BUF
    mov     r10, [rbp + MJ.end + rax*8]
    cmp     r10, r9
    jae     .drop
    push    rbx
    mov     rbx, rsp
    and     rsp, -16
    sub     rsp, 160
    mov     [rsp + 32], rax
    mov     [rsp + 40], rcx
    movdqu  [rsp + 48], xmm0
    movdqu  [rsp + 64], xmm1
    movdqu  [rsp + 80], xmm2
    movdqu  [rsp + 96], xmm3
    movdqu  [rsp + 112], xmm4
    movdqu  [rsp + 128], xmm5
    mov     rcx, r10
    mov     edx, MJ_STEP
    mov     r8d, MEM_COMMIT
    mov     r9d, PAGE_READWRITE
    call    VirtualAlloc
    mov     rdx, rax
    mov     rax, [rsp + 32]
    mov     rcx, [rsp + 40]
    movdqu  xmm0, [rsp + 48]
    movdqu  xmm1, [rsp + 64]
    movdqu  xmm2, [rsp + 80]
    movdqu  xmm3, [rsp + 96]
    movdqu  xmm4, [rsp + 112]
    movdqu  xmm5, [rsp + 128]
    mov     rsp, rbx
    pop     rbx
    test    rdx, rdx
    jz      .drop
    add     qword [rbp + MJ.end + rax*8], MJ_STEP
    jmp     emit_stage
.drop:
    ret

; ecx face, edx rect, r8d tile, xmm0 inset along the normal. flat own-cell light
box_face:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12d, ecx
    movss   [rbp + MJ.m_inset], xmm0
    mov     ecx, r8d
    call    set_tile_rect
    mov     ecx, r12d
    call    face_tint
    mov     r14d, eax
    lea     rax, [rel shade_tab]
    movzx   ecx, byte [rax + r12*4 + 3]
    call    own_light_packed
    mov     r15d, eax
    lea     r13, [rel face_tab]
    mov     eax, r12d
    shl     eax, 7
    add     r13, rax
    lea     rax, [rel face_nvec]
    imul    edx, r12d, 12
    lea     r11, [rax + rdx]
    lea     r10, [rbp + MJ.m_box]
    lea     rbx, [rbp + MJ.stage]
    xor     ecx, ecx
.c:
    ; x = x0 + cx*(x1-x0) - nx*inset + bx, same for y and z
    movss   xmm0, [r10 + 12]
    subss   xmm0, [r10 + 0]
    mulss   xmm0, [r13 + 0]
    addss   xmm0, [r10 + 0]
    movss   xmm1, [r11 + 0]
    mulss   xmm1, [rbp + MJ.m_inset]
    subss   xmm0, xmm1
    addss   xmm0, [rbp + MJ.m_bx]
    movss   [rbx + SV.x], xmm0
    movss   xmm0, [r10 + 16]
    subss   xmm0, [r10 + 4]
    mulss   xmm0, [r13 + 4]
    addss   xmm0, [r10 + 4]
    movss   xmm1, [r11 + 4]
    mulss   xmm1, [rbp + MJ.m_inset]
    subss   xmm0, xmm1
    addss   xmm0, [rbp + MJ.m_by]
    movss   [rbx + SV.y], xmm0
    movss   xmm0, [r10 + 20]
    subss   xmm0, [r10 + 8]
    mulss   xmm0, [r13 + 8]
    addss   xmm0, [r10 + 8]
    movss   xmm1, [r11 + 8]
    mulss   xmm1, [rbp + MJ.m_inset]
    subss   xmm0, xmm1
    addss   xmm0, [rbp + MJ.m_bz]
    movss   [rbx + SV.z], xmm0
    call    stage_uv_std
    mov     [rbx + SV.sky], r15d
    mov     [rbx + SV.r], r14d
    add     rbx, SV_size
    add     r13, 32
    inc     ecx
    cmp     ecx, 4
    jb      .c
    xor     ecx, ecx
    call    emit_stage
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

load_box:
    movups  xmm0, [rcx]
    movups  [rbp + MJ.m_box], xmm0
    movq    xmm0, [rcx + 16]
    movq    [rbp + MJ.m_box + 16], xmm0
    ret

block_tile:
    mov     eax, [rbp + MJ.m_id]
    lea     eax, [rax + rax*2]
    lea     eax, [rcx + rax*2]
    lea     rdx, [rel blk_tex]
    movzx   eax, byte [rdx + rax]
    ret

; torch 2/16 x 10/16, the top only uses the flame tip (texels 7..9 x 6..8)
mesh_torch:
    push    rbx
    sub     rsp, 16
    lea     rcx, [rel box_torch]
    call    load_box
    xor     ebx, ebx
.f:
    mov     ecx, ebx
    call    block_tile
    mov     r8d, eax
    mov     edx, RECT(7,6,9,16)
    cmp     ebx, FACE_PY
    jne     .nb
    mov     edx, RECT(7,6,9,8)
.nb:
    cmp     ebx, FACE_NY
    jne     .go
    mov     edx, RECT(7,14,9,16)
.go:
    mov     ecx, ebx
    xorps   xmm0, xmm0
    call    box_face
    inc     ebx
    cmp     ebx, 6
    jb      .f
    add     rsp, 16
    pop     rbx
    ret

mesh_lantern:
    push    rbx
    sub     rsp, 16
    lea     rcx, [rel box_lantern]
    call    load_box
    xor     ebx, ebx
.f:
    mov     ecx, ebx
    call    block_tile
    mov     r8d, eax
    mov     edx, RECT(5,9,11,16)
    cmp     ebx, FACE_PY
    je      .tb
    cmp     ebx, FACE_NY
    jne     .go
.tb:
    mov     edx, RECT(5,5,11,11)
.go:
    mov     ecx, ebx
    xorps   xmm0, xmm0
    call    box_face
    inc     ebx
    cmp     ebx, 6
    jb      .f
    lea     rcx, [rel box_lantern_cap]
    call    load_box
    xor     ebx, ebx
.g:
    cmp     ebx, FACE_NY                        ; cap bottom sits right on the body, skip
    je      .gn
    mov     ecx, ebx
    call    block_tile
    mov     r8d, eax
    mov     edx, RECT(6,7,10,9)
    cmp     ebx, FACE_PY
    jne     .gg
    mov     edx, RECT(6,6,10,10)
.gg:
    mov     ecx, ebx
    xorps   xmm0, xmm0
    call    box_face
.gn:
    inc     ebx
    cmp     ebx, 6
    jb      .g
    add     rsp, 16
    pop     rbx
    ret

; cactus sides sit 1/16 in, never touch a neighbour, always drawn
mesh_cactus:
    push    rbx
    sub     rsp, 16
    lea     rcx, [rel box_full]
    call    load_box
    xor     ebx, ebx
.f:
    xorps   xmm0, xmm0
    cmp     ebx, FACE_PY
    je      .cap
    cmp     ebx, FACE_NY
    je      .cap
    movss   xmm0, [rel f_16th]
    jmp     .draw
.cap:
    mov     ecx, ebx
    call    face_hidden
    test    eax, eax
    jnz     .skip
    xorps   xmm0, xmm0
.draw:
    movss   [rsp], xmm0
    mov     ecx, ebx
    call    block_tile
    mov     r8d, eax
    mov     edx, RECT_FULL
    mov     ecx, ebx
    movss   xmm0, [rsp]
    call    box_face
.skip:
    inc     ebx
    cmp     ebx, 6
    jb      .f
    add     rsp, 16
    pop     rbx
    ret

; X plants. hashed xz jitter so fields don't look like a grid (not reeds, they stack).
; only top verts wave so the base stays put. darker bottom = poor man's contact shadow
mesh_cross:
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 40
    xor     ecx, ecx
    call    block_tile
    mov     ecx, eax
    mov     edx, RECT_FULL
    call    set_tile_rect
    mov     ecx, FACE_PY
    call    face_tint
    mov     r14d, eax
    xorps   xmm4, xmm4
    xorps   xmm5, xmm5
    cmp     dword [rbp + MJ.m_id], B_REEDS
    je      .nojit
    imul    eax, [rbp + MJ.m_wx], 73856093
    imul    ecx, [rbp + MJ.m_wz], 19349663
    xor     eax, ecx
    imul    ecx, [rbp + MJ.m_wy], 83492791
    xor     eax, ecx
    mov     ecx, eax
    shr     ecx, 13
    xor     eax, ecx
    imul    eax, eax, 0x5BD1E995
    mov     ecx, eax
    shr     ecx, 15
    xor     eax, ecx
    mov     ecx, eax
    and     ecx, 15
    sub     ecx, 7
    cvtsi2ss xmm4, ecx
    mulss   xmm4, [rel f_jitter]
    shr     eax, 4
    and     eax, 15
    sub     eax, 7
    cvtsi2ss xmm5, eax
    mulss   xmm5, [rel f_jitter]
.nojit:
    movss   xmm0, [rel f_plant_lo]
    addss   xmm0, xmm4
    addss   xmm0, [rbp + MJ.m_bx]
    movss   [rsp + 0], xmm0                     ; [rsp] = x0 x1 z0 z1 y0 y1
    movss   xmm0, [rel f_plant_hi]
    addss   xmm0, xmm4
    addss   xmm0, [rbp + MJ.m_bx]
    movss   [rsp + 4], xmm0
    movss   xmm0, [rel f_plant_lo]
    addss   xmm0, xmm5
    addss   xmm0, [rbp + MJ.m_bz]
    movss   [rsp + 8], xmm0
    movss   xmm0, [rel f_plant_hi]
    addss   xmm0, xmm5
    addss   xmm0, [rbp + MJ.m_bz]
    movss   [rsp + 12], xmm0
    movss   xmm0, [rbp + MJ.m_by]
    movss   [rsp + 16], xmm0
    addss   xmm0, [rel f_one]
    movss   [rsp + 20], xmm0
    ; bottom: shade 0.8, no wave. top: 1.0, wave if it's a plant
    mov     dword [rbp + MJ.m_vflags], 0
    mov     ecx, 204
    call    own_light_packed
    mov     r12d, eax
    lea     rax, [rel blk_flags]
    mov     edx, [rbp + MJ.m_id]
    movzx   eax, word [rax + rdx*2]
    xor     ecx, ecx
    test    eax, BF_PLANT
    jz      .nowave
    mov     ecx, VF_WAVE
.nowave:
    mov     [rbp + MJ.m_vflags], ecx
    mov     ecx, 255
    call    own_light_packed
    mov     r13d, eax
    ; plane A (x0,z0)->(x1,z1), plane B (x0,z1)->(x1,z0)
    xor     ebx, ebx
.plane:
    lea     rcx, [rbp + MJ.stage]
    movss   xmm0, [rsp + 0]
    movss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 8]
    movss   xmm3, [rsp + 12]
    test    ebx, ebx
    jz      .pz
    movss   xmm2, [rsp + 12]
    movss   xmm3, [rsp + 8]
.pz:
    movss   xmm4, [rsp + 16]
    movss   xmm5, [rsp + 20]
    movss   [rcx + SV.x], xmm0
    movss   [rcx + SV.y], xmm4
    movss   [rcx + SV.z], xmm2
    movss   [rcx + SV_size + SV.x], xmm1
    movss   [rcx + SV_size + SV.y], xmm4
    movss   [rcx + SV_size + SV.z], xmm3
    movss   [rcx + SV_size*2 + SV.x], xmm1
    movss   [rcx + SV_size*2 + SV.y], xmm5
    movss   [rcx + SV_size*2 + SV.z], xmm3
    movss   [rcx + SV_size*3 + SV.x], xmm0
    movss   [rcx + SV_size*3 + SV.y], xmm5
    movss   [rcx + SV_size*3 + SV.z], xmm2
    mov     [rcx + SV.sky], r12d
    mov     [rcx + SV_size + SV.sky], r12d
    mov     [rcx + SV_size*2 + SV.sky], r13d
    mov     [rcx + SV_size*3 + SV.sky], r13d
    mov     [rcx + SV.r], r14d
    mov     [rcx + SV_size + SV.r], r14d
    mov     [rcx + SV_size*2 + SV.r], r14d
    mov     [rcx + SV_size*3 + SV.r], r14d
    push    rbx
    lea     rbx, [rbp + MJ.stage]
    xor     ecx, ecx
.uv:
    call    stage_uv_std
    add     rbx, SV_size
    inc     ecx
    cmp     ecx, 4
    jb      .uv
    pop     rbx
    xor     ecx, ecx
    call    emit_stage
    mov     ecx, 2
    call    emit_stage
    inc     ebx
    cmp     ebx, 2
    jb      .plane
    add     rsp, 40
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ecx id -> eax 0 none / 1 water / 2 lava
liq_kind:
    xor     eax, eax
    cmp     ecx, B_WATER
    jb      .r
    cmp     ecx, B_LAVA_LAST
    ja      .r
    mov     eax, 1
    cmp     ecx, B_WATER_LAST
    jbe     .r
    mov     eax, 2
.r:
    ret

; ecx cx, edx cz -> xmm0 corner height, weighted over the 4 cells around it.
; like MC: sources x4, air pulls toward 0, liquid on top of any of them -> full
liquid_corner:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    sub     rsp, 8
    xorps   xmm4, xmm4                          ; sum
    xorps   xmm5, xmm5                          ; weight
    lea     r12d, [rcx - 1]
    lea     esi, [rdx - 1]
    xor     ebx, ebx                             ; bit0 +x, bit1 +z
.cell:
    mov     edi, ebx
    and     edi, 1
    add     edi, r12d
    mov     eax, ebx
    shr     eax, 1
    add     eax, esi
    imul    eax, eax, PADW
    add     edi, eax
    add     edi, [rbp + MJ.m_p]
    lea     rax, [rbp + MJ.pad_blk]
    movzx   ecx, byte [rax + rdi]
    mov     r8d, ecx
    call    liq_kind
    cmp     eax, [rbp + MJ.m_lkind]
    jne     .other
    ; same liquid with more of it on top -> full
    lea     rax, [rbp + MJ.pad_blk]
    movzx   ecx, byte [rax + rdi + PADA]
    call    liq_kind
    cmp     eax, [rbp + MJ.m_lkind]
    je      .full
    lea     rax, [rel liq_h]
    movss   xmm0, [rax + r8*4 - B_WATER*4]
    cmp     r8d, B_WATER
    je      .src
    cmp     r8d, B_LAVA
    je      .src
    addss   xmm4, xmm0
    addss   xmm5, [rel f_one]
    jmp     .next
.src:
    mulss   xmm0, [rel f_four]
    addss   xmm4, xmm0
    addss   xmm5, [rel f_four]
    jmp     .next
.other:
    lea     rax, [rel blk_flags]
    movzx   eax, word [rax + r8*2]
    test    eax, BF_SOLID
    jnz     .next
    addss   xmm5, [rel f_one]                   ; air = height 0
.next:
    inc     ebx
    cmp     ebx, 4
    jb      .cell
    movaps  xmm0, xmm4
    divss   xmm0, xmm5
    jmp     .ret
.full:
    movss   xmm0, [rel f_one]
.ret:
    add     rsp, 8
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; water's top also goes out back facing so you see it from underwater.
; sides crop the texture to the side height instead of squashing it
mesh_liquid:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 16
    mov     ecx, [rbp + MJ.m_id]
    call    liq_kind
    mov     [rbp + MJ.m_lkind], eax
    mov     dword [rbp + MJ.m_noao], 1
    mov     dword [rbp + MJ.m_vflags], 0
    ; liquid above -> full height, no top
    mov     eax, [rbp + MJ.m_p]
    lea     rdx, [rbp + MJ.pad_blk]
    movzx   ecx, byte [rdx + rax + PADA]
    call    liq_kind
    xor     r15d, r15d                          ; 1 = covered
    cmp     eax, [rbp + MJ.m_lkind]
    jne     .heights
    mov     r15d, 1
    movss   xmm0, [rel f_one]
    movss   [rbp + MJ.m_hgt], xmm0
    movss   [rbp + MJ.m_hgt+4], xmm0
    movss   [rbp + MJ.m_hgt+8], xmm0
    movss   [rbp + MJ.m_hgt+12], xmm0
    jmp     .top_done
.heights:
    xor     ebx, ebx
.hl:
    mov     ecx, ebx
    and     ecx, 1
    mov     edx, ebx
    shr     edx, 1
    call    liquid_corner
    lea     rax, [rbp + MJ.m_hgt]
    movss   [rax + rbx*4], xmm0
    inc     ebx
    cmp     ebx, 4
    jb      .hl
    mov     ecx, FACE_PY
    call    block_tile
    mov     ecx, eax
    mov     edx, RECT_FULL
    call    set_tile_rect
    mov     ecx, FACE_PY
    call    liquid_face_geom
    mov     ecx, FACE_PY
    call    compute_face_light
    call    pick_diagonal
    mov     ecx, eax
    call    emit_stage
    cmp     dword [rbp + MJ.m_lkind], 1
    jne     .top_done
    mov     ecx, 2                              ; underside, for when you're swimming
    call    emit_stage
.top_done:
    xor     ebx, ebx
.side:
    cmp     ebx, FACE_PY
    je      .side_next
    cmp     ebx, FACE_NY
    je      .side_next
    mov     eax, [rbp + MJ.m_p]
    lea     rdx, [rel face_ndelta]
    add     eax, [rdx + rbx*4]
    lea     rdx, [rbp + MJ.pad_blk]
    movzx   ecx, byte [rdx + rax]
    mov     r12d, ecx
    lea     rdx, [rbp + MJ.occ]
    cmp     byte [rdx + rcx], 0
    jne     .side_next
    call    liq_kind
    cmp     eax, [rbp + MJ.m_lkind]
    je      .side_next
    mov     ecx, ebx
    call    block_tile
    mov     ecx, eax
    mov     edx, RECT_FULL
    call    set_tile_rect
    mov     ecx, ebx
    call    liquid_face_geom
    mov     ecx, ebx
    call    compute_face_light
    call    pick_diagonal
    mov     ecx, eax
    call    emit_stage
.side_next:
    inc     ebx
    cmp     ebx, 6
    jb      .side
    mov     eax, [rbp + MJ.m_p]
    lea     rdx, [rbp + MJ.pad_blk]
    movzx   ecx, byte [rdx + rax - PADA]
    lea     rdx, [rbp + MJ.occ]
    cmp     byte [rdx + rcx], 0
    jne     .done
    call    liq_kind
    cmp     eax, [rbp + MJ.m_lkind]
    je      .done
    mov     ecx, FACE_NY
    call    block_tile
    mov     ecx, eax
    mov     edx, RECT_FULL
    call    set_tile_rect
    mov     ecx, FACE_NY
    call    liquid_face_geom
    mov     ecx, FACE_NY
    call    compute_face_light
    xor     ecx, ecx
    call    emit_stage
.done:
    add     rsp, 16
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ecx face, top corners from m_hgt
liquid_face_geom:
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 8
    mov     r12d, ecx
    call    face_tint
    mov     r14d, eax
    lea     r13, [rel face_tab]
    mov     eax, r12d
    shl     eax, 7
    add     r13, rax
    lea     rbx, [rbp + MJ.stage]
    xor     ecx, ecx
.c:
    call    stage_uv_std
    mov     [rbx + SV.r], r14d
    mov     byte [rbx + SV.flags], 0
    movss   xmm0, [r13 + 0]
    addss   xmm0, [rbp + MJ.m_bx]
    movss   [rbx + SV.x], xmm0
    movss   xmm0, [r13 + 8]
    addss   xmm0, [rbp + MJ.m_bz]
    movss   [rbx + SV.z], xmm0
    movss   xmm1, [r13 + 4]
    xorps   xmm2, xmm2
    comiss  xmm1, xmm2
    je      .ybottom
    cvttss2si eax, [r13 + 0]
    cvttss2si edx, [r13 + 8]
    lea     eax, [rax + rdx*2]
    lea     rdx, [rbp + MJ.m_hgt]
    movss   xmm1, [rdx + rax*4]
    movss   xmm0, xmm1
    addss   xmm0, [rbp + MJ.m_by]
    movss   [rbx + SV.y], xmm0
    comiss  xmm1, [rel f_one]
    jae     .noflag
    mov     byte [rbx + SV.flags], VF_LIQUID
.noflag:
    cmp     r12d, FACE_PY
    je      .next
    movss   xmm0, [rel f_one]
    subss   xmm0, xmm1
    mulss   xmm0, [rel f_tile]
    addss   xmm0, [rbp + MJ.m_uv + 4]                ; v0 + (1-h)/16
    movss   [rbx + SV.v], xmm0
    jmp     .next
.ybottom:
    movss   xmm0, [rbp + MJ.m_by]
    movss   [rbx + SV.y], xmm0
.next:
    add     rbx, SV_size
    add     r13, 32
    inc     ecx
    cmp     ecx, 4
    jb      .c
    add     rsp, 8
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
