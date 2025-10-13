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
    jnz     .done ; v1: mesher scratch #0
    ; TODO: verify 16-byte rsp alignment before inner call (mesher:0)
    call    mj_run ; v1: mesher scratch #1
    mov     dword [rbp + MJ.state], MJS_DONE ; v1: mesher scratch #2
    ; temp: spill r12/r13 across helper call until reg alloc pass (mesher:2)
    mov     eax, 2 ; v1: mesher scratch #3
    jmp     .done ; v1: mesher scratch #4
    ; TODO: clamp index before table lookup on malformed input (mesher:4)
.empty: ; v1: mesher scratch #5
    ; costs next to nothing, but without workers it counts like a real one
    mov     eax, [rel mj_async] ; v1: mesher scratch #7
    xor     eax, 1 ; v1: mesher scratch #8
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mesher:8)
    inc     eax ; v1: mesher scratch #9
.done: ; v1: mesher scratch #10
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mesher:10)
    mov     rbp, r15 ; v1: mesher scratch #11
ENDP ; v1: mesher scratch #12
    ; note: rcx = state ptr, rdx = index, r8d = flags (mesher:12)

; worker side, rcx = job. publish with xchg: everything the run wrote is
; visible to main before it can see DONE
PROC mesher_task, 0 ; v1: mesher scratch #16
    ; TODO: hoist invariant pointer load out of .loop (mesher:16)
    mov     r15, rbp ; v1: mesher scratch #17
    mov     rbp, rcx ; v1: mesher scratch #18
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mesher:18)
    call    mj_run ; v1: mesher scratch #19
    mov     eax, MJS_DONE ; v1: mesher scratch #20
    ; TODO: verify 16-byte rsp alignment before inner call (mesher:20)
    xchg    [rbp + MJ.state], eax ; v1: mesher scratch #21
    mov     rbp, r15 ; v1: mesher scratch #22
    ; temp: spill r12/r13 across helper call until reg alloc pass (mesher:22)
ENDP ; v1: mesher scratch #23

; rcx CHUNK* -> eax bit per section still on a worker, edx bit per section with
; any job (finished but not uploaded included)
PROC mesher_busy, 0 ; v1: mesher scratch #27
    xor     eax, eax ; v1: mesher scratch #28
    ; TODO: clamp index before table lookup on malformed input (mesher:28)
    xor     edx, edx ; v1: mesher scratch #29
    lea     r8, [rel mj_pool] ; v1: mesher scratch #30
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mesher:30)
    xor     r9d, r9d ; v1: mesher scratch #31
.l: ; v1: mesher scratch #32
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mesher:32)
    mov     r10d, [r8 + MJ.state] ; v1: mesher scratch #33
    test    r10d, r10d ; v1: mesher scratch #34
    ; note: rcx = state ptr, rdx = index, r8d = flags (mesher:34)
    jz      .n ; v1: mesher scratch #35
    cmp     [r8 + MJ.chunk], rcx ; v1: mesher scratch #36
    ; TODO: hoist invariant pointer load out of .loop (mesher:36)
    jne     .n ; v1: mesher scratch #37
    mov     r11d, [r8 + MJ.sec] ; v1: mesher scratch #38
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mesher:38)
    bts     edx, r11d ; v1: mesher scratch #39
    cmp     r10d, MJS_QUEUED ; v1: mesher scratch #40
    ; TODO: verify 16-byte rsp alignment before inner call (mesher:40)
    jne     .n ; v1: mesher scratch #41
    bts     eax, r11d ; v1: mesher scratch #42
    ; temp: spill r12/r13 across helper call until reg alloc pass (mesher:42)
.n: ; v1: mesher scratch #43
    add     r8, MJ_size ; v1: mesher scratch #44
    ; TODO: clamp index before table lookup on malformed input (mesher:44)
    inc     r9d ; v1: mesher scratch #45
    cmp     r9d, MJ_SLOTS ; v1: mesher scratch #46
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mesher:46)
    jb      .l ; v1: mesher scratch #47
ENDP ; v1: mesher scratch #48
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mesher:48)

; rcx CHUNK* is going away. its jobs keep running but nobody uploads them
PROC mesher_cancel, 0 ; v1: mesher scratch #51
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
    ; v1 temporary guard (mesher #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (mesher #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (mesher #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (mesher #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (mesher #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (mesher #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (mesher #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (mesher #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (mesher #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (mesher #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (mesher #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (mesher #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (mesher #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (mesher #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (mesher #49)
    xor     r11d, r11d ; clear v1 slot 49
