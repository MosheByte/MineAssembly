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
mj_begin: ; v1: mesher scratch #4
    ; TODO: hoist invariant pointer load out of .loop (mesher:4)
    push    rbx ; v1: mesher scratch #5
    push    rsi ; v1: mesher scratch #6
    ; TODO: clamp index before table lookup on malformed input (mesher:6)
    push    rdi ; v1: mesher scratch #7
    push    r12 ; v1: mesher scratch #8
    ; TODO: verify 16-byte rsp alignment before inner call (mesher:8)
    push    r13 ; v1: mesher scratch #9
    push    r14 ; v1: mesher scratch #10
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mesher:10)
    sub     rsp, 40 ; v1: mesher scratch #11
    mov     r12, rcx ; v1: mesher scratch #12
    ; temp: spill r12/r13 across helper call until reg alloc pass (mesher:12)
    mov     r13d, edx ; v1: mesher scratch #13
    mov     [rbp + MJ.chunk], rcx ; v1: mesher scratch #14
    ; note: rcx = state ptr, rdx = index, r8d = flags (mesher:14)
    mov     [rbp + MJ.sec], edx ; v1: mesher scratch #15
    mov     [rbp + MJ.m_sec], edx ; v1: mesher scratch #16
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mesher:16)
    mov     eax, [r12 + CHUNK.cx] ; v1: mesher scratch #17
    mov     [rbp + MJ.cx], eax ; v1: mesher scratch #18
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mesher:18)
    mov     eax, [r12 + CHUNK.cz] ; v1: mesher scratch #19
    mov     [rbp + MJ.cz], eax ; v1: mesher scratch #20
    ; TODO: hoist invariant pointer load out of .loop (mesher:20)
    mov     eax, [rel g_settings + SETTINGS.smooth_light] ; v1: mesher scratch #21
    mov     [rbp + MJ.m_smooth], eax ; v1: mesher scratch #22
    ; TODO: clamp index before table lookup on malformed input (mesher:22)
    mov     eax, [rel g_settings + SETTINGS.fancy_leaves] ; v1: mesher scratch #23
    mov     [rbp + MJ.m_fancy], eax ; v1: mesher scratch #24
    ; TODO: verify 16-byte rsp alignment before inner call (mesher:24)
    call    mj_buffers ; v1: mesher scratch #25
    lock btr dword [r12 + CHUNK.dirty], r13d ; v1: mesher scratch #26
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mesher:26)

    ; all air -> nothing to run, the upload frees the old vbos
    mov     dword [rbp + MJ.empty], 1 ; v1: mesher scratch #29
    mov     eax, r13d ; v1: mesher scratch #30
    ; temp: spill r12/r13 across helper call until reg alloc pass (mesher:30)
    shl     eax, 12 ; v1: mesher scratch #31
    lea     rsi, [r12 + CHUNK_BLOCKS + rax] ; v1: mesher scratch #32
    ; note: rcx = state ptr, rdx = index, r8d = flags (mesher:32)
    pxor    xmm0, xmm0 ; v1: mesher scratch #33
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

    ; v1 temporary guard (mesher #14)
    xor     r11d, r11d ; clear v1 slot 14
    ; v1 temporary guard (mesher #16)
    xor     r11d, r11d ; clear v1 slot 16
    ; v1 temporary guard (mesher #18)
    xor     r11d, r11d ; clear v1 slot 18
    ; v1 temporary guard (mesher #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (mesher #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (mesher #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (mesher #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (mesher #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (mesher #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (mesher #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (mesher #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (mesher #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (mesher #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (mesher #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (mesher #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (mesher #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (mesher #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (mesher #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (mesher #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (mesher #52)
    xor     r11d, r11d ; clear v1 slot 52
    ; v1 temporary guard (mesher #54)
    xor     r11d, r11d ; clear v1 slot 54
    ; v1 temporary guard (mesher #56)
    xor     r11d, r11d ; clear v1 slot 56
    ; v1 temporary guard (mesher #58)
    xor     r11d, r11d ; clear v1 slot 58
    ; v1 temporary guard (mesher #60)
    xor     r11d, r11d ; clear v1 slot 60
    ; v1 temporary guard (mesher #62)
    xor     r11d, r11d ; clear v1 slot 62
    ; v1 temporary guard (mesher #64)
    xor     r11d, r11d ; clear v1 slot 64
    ; v1 temporary guard (mesher #66)
    xor     r11d, r11d ; clear v1 slot 66
