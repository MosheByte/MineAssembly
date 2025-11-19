; abi checks on the three light entry points, plus stuff the scenario tests never hit:
; all-negative coords, the y=0 / y=127 rows, chunk reload, and a CS_GENERATING chunk
; that a worker owns, which we must not touch at all
; @link src/light.asm tests/light/fakeworld.asm tests/light/lightlib.asm
; @timeout 300
%include "common.inc"
%include "testlib.inc"
%include "../light/lightlib.inc"  ; via -I tests/lib/

extern fw_misaligned

%define SNAP_BYTES (9*32768)
%define NEG_EDITS  60

section .rdata
neg_palette: db T_AIR, T_AIR, T_STONE, T_LEAVES, T_WATER, T_TORCH, T_GLOW, T_GLASS
%define NEG_PALETTE_N 8

; x, y, z, id
probe_edits: dd 8, 66, 8, T_TORCH
             dd 8, 66, 8, T_AIR
             dd 3, 110, 3, T_STONE
             dd 3, 110, 3, T_AIR
             dd -5, 99, -5, T_AIR
             dd -5, 99, -5, T_STONE
%define PROBE_EDITS 6

; cx, cz
reload_list: dd 0, 0, -1, -1, 1, 0

section .text
PROC rand_below, 0
    mov  ebx, ecx
    call t_rng_next
    xor  edx, edx
    div  rbx
    mov  eax, edx
ENDP

PROC test_main, 0
    call lt_setup_tables

    TEST "abi nonvolatile registers and alignment"
    mov  ecx, -1
    call lt_world_new
    FILL 0, 100, 0, LT_WS, 0, LT_WS, T_STONE
    FILL 64, 72, 6, 42, 6, 42, T_AIR
    xor  ecx, ecx
    call lt_load_chunks  ; no column pass
    xor  r12d, r12d
.init:
    mov  eax, r12d
    xor  edx, edx
    mov  ecx, 3
    div  ecx
    lea  ecx, [rdx - 1]
    lea  edx, [rax - 1]
    call lt_slot
    mov  r13, rax
    PROBE light_init_chunk_sky, r13, 0, 0, 0, "light_init_chunk_sky ABI"
    inc  r12d
    cmp  r12d, 9
    jb   .init
    xor  r12d, r12d
.prop:
    mov  eax, r12d
    xor  edx, edx
    mov  ecx, 3
    div  ecx
    lea  ecx, [rdx - 1]
    lea  edx, [rax - 1]
    call lt_slot
    mov  r13, rax
    PROBE light_propagate_chunk, r13, 0, 0, 0, "light_propagate_chunk ABI"
    inc  r12d
    cmp  r12d, 9
    jb   .prop
    CHECK_REF "after probed generation"
    ; place and remove a torch and a sky-shading block through the probe
    lea  r14, [rel probe_edits]
    xor  r15d, r15d
.edit:
    mov  ecx, [r14]
    mov  edx, [r14 + 4]
    mov  r8d, [r14 + 8]
    mov  r9d, [r14 + 12]
    mov  qword [rsp+32], 0  ; no notify, the probe makes the call
    call lt_set_block
    movsxd r12, dword [r14]
    movsxd r13, dword [r14 + 4]
    movsxd rbx, dword [r14 + 8]
    mov  esi, eax
    PROBE light_on_block_changed, r12, r13, rbx, rsi, "light_on_block_changed ABI"
    add  r14, 16
    inc  r15d
    cmp  r15d, PROBE_EDITS
    jb   .edit
    CHECK_REF "after probed edits"
    ; early outs: unloaded chunk, y out of range
    PROBE light_on_block_changed, 1000, 70, 1000, 0, "early out: unloaded chunk"
    PROBE light_on_block_changed, 0, -1, 0, T_STONE, "early out: y = -1"
    PROBE light_on_block_changed, 0, 128, 0, T_STONE, "early out: y = 128"
    CHECK_REF "after no-op calls"

    TEST "negative coordinates"
    ; chunks -3..-1, so every block coord is negative
    mov  ecx, 99
    call t_rng_seed
    mov  ecx, -3
    call lt_world_new
    FILL 0, 60, 0, LT_WS, 0, LT_WS, T_STONE
    mov  ecx, 60
    mov  edx, 70
    mov  r8d, 300
    mov  r9d, T_STONE
    call lt_fill_random
    FILL 70, 71, 6, 42, 6, 42, T_STONE
    xor  ecx, ecx
    call lt_generate
    CHECK_REF "initial"
    ; fresh dark pocket right on the -2/-3 border
    mov  r12d, 62
.ky:
    mov  r13d, -30
.kz:
    mov  r14d, -36
.kx:
    SETB r14d, r12d, r13d, T_AIR
    inc  r14d
    cmp  r14d, -28
    jl   .kx
    inc  r13d
    cmp  r13d, -22
    jl   .kz
    inc  r12d
    cmp  r12d, 69
    jl   .ky
    SETB -33, 65, -26, T_TORCH  ; x=-33 is chunk -3, lx=15
    CHECK_BLK -33, 65, -26, 14, "torch cell"
    CHECK_BLK -32, 65, -26, 13, "chunk -2, lx=0"
    CHECK_BLK -30, 66, -25, 9, "distance 5"
    CHECK_REF "torch at a negative border"
    xor  r15d, r15d
.nedit:
    mov  ecx, 48
    call rand_below
    lea  r12d, [rax - 48]
    mov  ecx, 48
    call rand_below
    lea  r13d, [rax - 48]
    mov  ecx, 16
    call rand_below
    lea  r14d, [rax + 58]
    mov  ecx, NEG_PALETTE_N
    call rand_below
    lea  rcx, [rel neg_palette]
    movzx ebx, byte [rcx + rax]
    SETB r12d, r14d, r13d, ebx
    CHECK_REF "negative-coordinate random edit"
    test eax, eax
    jnz  .nok
    mov  ecx, r15d
    mov  edx, r12d
    mov  r8d, r14d
    mov  r9d, r13d
    mov  [rsp+32], rbx
    call lt_print_edit
.nok:
    inc  r15d
    cmp  r15d, NEG_EDITS
    jb   .nedit

    TEST "world top and bottom rows"
    mov  ecx, 64
    call lt_flat_world
    xor  ecx, ecx
    call lt_generate
    SETB 5, 127, 5, T_STONE
    CHECK_HM 5, 5, 128, "heightmap of a block at y=127"
    CHECK_SKY 5, 126, 5, 14, "below the top block"
    CHECK_REF "stone at y=127"
    SETB 6, 127, 5, T_TORCH
    CHECK_BLK 6, 127, 5, 14, "torch at y=127"
    CHECK_REF "torch at y=127"
    ; pocket at the very bottom, glow at y=0
    SETB 2, 0, 2, T_AIR
    SETB 2, 1, 2, T_AIR
    SETB 2, 2, 2, T_AIR
    SETB 2, 0, 2, T_GLOW
    CHECK_BLK 2, 1, 2, 14, "above the glow at y=0"
    CHECK_REF "glow at y=0"
    SETB 5, 127, 5, T_AIR
    SETB 6, 127, 5, T_AIR
    SETB 2, 0, 2, T_AIR
    CHECK_REF "cleared"

    TEST "chunk reload restores the same light"
    ; reload = column init + propagate again. has to pull the neighbours' light
    ; back in through the faces and land on the same fixpoint
    mov  ecx, 21
    call t_rng_seed
    mov  ecx, 60
    call lt_flat_world
    mov  ecx, 60
    mov  edx, 72
    mov  r8d, 300
    mov  r9d, T_STONE
    call lt_fill_random
    FILL 72, 73, 8, 40, 8, 40, T_STONE
    mov  ecx, 25
    mov  edx, 61
    mov  r8d, T_TORCH
    call lt_scatter
    FILL 65, 66, 15, 18, 15, 18, T_GLOW
    xor  ecx, ecx
    call lt_generate
    CHECK_REF "initial"
    mov  ecx, SNAP_BYTES
    call t_alloc
    mov  r12, rax
    mov  rcx, r12
    call lt_snapshot
    lea  r14, [rel reload_list]
    xor  r15d, r15d
.reload:
    mov  ecx, [r14]
    mov  edx, [r14 + 4]
    call lt_slot
    mov  r13, rax
    lea  rdi, [r13 + CHUNK_LIGHT]  ; garbage the old light first
    mov  ecx, 32768
    mov  al, 0x5A
    rep  stosb
    mov  rcx, r13
    call light_init_chunk_sky
    mov  rcx, r13
    call light_propagate_chunk
    CHECK_REF "reloaded chunk"
    add  r14, 8
    inc  r15d
    cmp  r15d, 3
    jb   .reload
    mov  ecx, SNAP_BYTES
    call t_alloc
    mov  r13, rax
    mov  rcx, r13
    call lt_snapshot
    CHECK_MEM r12, r13, SNAP_BYTES, "light identical after the reloads"

    TEST "chunk owned by a worker is never touched"
    call lt_dark_room
    mov  ecx, 1
    xor  edx, edx
    mov  r8d, LT_OFF_STATE
    mov  r9d, CS_GENERATING
    call lt_set_header  ; chunk (1,0) is "owned" by a worker
    mov  ecx, 1
    xor  edx, edx
    call lt_slot
    mov  rbx, rax
    mov  ecx, 32768 + 1024
    call t_alloc
    mov  r12, rax  ; light[] then header
    mov  rdi, r12
    lea  rsi, [rbx + CHUNK_LIGHT]
    mov  ecx, 32768
    rep  movsb
    mov  rsi, rbx
    mov  ecx, 1024
    rep  movsb
    SETB 15, 66, 8, T_GLOW
    SETB 15, 66, 8, T_AIR
    SETB 15, 66, 9, T_TORCH
    lea  rax, [rbx + CHUNK_LIGHT]
    CHECK_MEM r12, rax, 32768, "busy chunk light untouched"
    lea  rax, [r12 + 32768]
    CHECK_MEM rax, rbx, 1024, "busy chunk header untouched"
    CHECK_BLK 14, 66, 9, 13, "light next to the busy chunk"
    ; edits inside the busy chunk get ignored completely
    mov  ecx, SNAP_BYTES
    call t_alloc
    mov  r13, rax
    mov  rcx, r13
    call lt_snapshot
    SETB 20, 66, 8, T_TORCH
    mov  ecx, SNAP_BYTES
    call t_alloc
    mov  r14, rax
    mov  rcx, r14
    call lt_snapshot
    CHECK_MEM r13, r14, SNAP_BYTES, "edit inside the busy chunk ignored"
ENDP
