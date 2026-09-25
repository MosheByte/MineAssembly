; wglib.inc - helpers for the world tests (wglib.asm). tests link the real world
; modules via @link, everything else in api.inc gets stubbed to return 0.
%ifndef WGLIB_INC
%define WGLIB_INC

%define WG_SEA          62
%define WG_HM           256                 ; CHUNK.heightmap
%define WG_BIOME        512                 ; CHUNK.biome
%define WG_BLOCKS       1024                ; CHUNK_BLOCKS
%define WG_SET_END      0xFF

%define WG_IDX(x,y,z)   ((x) + ((z) << 4) + ((y) << 8))

; not in api.inc
extern world_alloc_chunk                    ; -> CHUNK* in CS_QUEUED, or 0
extern world_release_chunk

%ifndef IMPL_WGLIB
extern wg_set_seed
extern wg_chunk_new
extern wg_gen           ; generated but not registered in the world hash
extern wg_gen_new
extern wg_set_player
extern wg_chunk_count
extern wg_chunk_ptr
extern wg_grid          ; grid[(cz-cz0+64)*128 + (cx-cx0+64)] = 0x80|state, 0 = not loaded
extern wg_grid_get
extern wg_memeq
extern wg_make_set
extern wg_parallel      ; jobs run on worker threads -> no t_* checks inside them
extern wg_say
extern wg_say3
%endif

; operands must not be rcx/rdx/r8/r9
%macro WG_SAY3 4.nolist
    section .rdata
    %%s: db %1, 0
    section .text
    mov  eax, %2
    mov  r10d, %3
    mov  r11d, %4
    lea  rcx, [rel %%s]
    mov  edx, eax
    mov  r8d, r10d
    mov  r9d, r11d
    call wg_say3
%endmacro

%macro WG_SAY 2.nolist
    section .rdata
    %%s: db %1, 0
    section .text
    mov  rax, %2
    lea  rcx, [rel %%s]
    mov  rdx, rax
    call wg_say
%endmacro

%endif
