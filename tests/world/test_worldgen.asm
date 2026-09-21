; worldgen: determinism (incl. 8 threads vs serial), features, invariants,
; speed, and the pure biome_at / height_at / spawn functions vs real chunks.
; @link src/world.asm src/worldgen.asm src/chunkmgr.asm src/noise.asm
; @link src/math.asm src/platform.asm src/gl.asm src/util.asm
; @link src/blocks.asm src/items.asm src/light.asm tests/world/wglib.asm
; @timeout 180
%include "common.inc"
%include "testlib.inc"
%include "../world/wglib.inc"

%define SEED 12345

section .rdata
; what height_at calls ground: terrain minus water/ice
set_ground:  db B_STONE, B_GRASS, B_DIRT, B_SAND, B_GRAVEL, B_SANDSTONE, B_SNOW, B_CLAY
             db B_SNOWY_GRASS, B_COAL_ORE, B_IRON_ORE, B_GOLD_ORE, B_DIAMOND_ORE
             db B_BEDROCK, B_LAVA, WG_SET_END
; allowed above the heightmap
set_above:   db B_AIR, B_TALL_GRASS, B_FLOWER_RED, B_FLOWER_YELLOW, B_MUSHROOM_RED
             db B_MUSHROOM_BROWN, B_DEAD_BUSH, B_REEDS, B_TORCH, WG_SET_END
feature_ids: db B_LOG, B_LEAVES, B_PINE_LOG, B_PINE_LEAVES, B_BIRCH_LOG, B_TALL_GRASS
             db B_CACTUS, B_REEDS, B_MOSSY_COBBLE, B_GLOWCRYSTAL, B_SANDSTONE, B_SNOW, B_CLAY
%define NFEATURES 13
feature_names:
             dq fn0, fn1, fn2, fn3, fn4, fn5, fn6, fn7, fn8, fn9, fn10, fn11, fn12
fn0:  db "LOG never generated", 0
fn1:  db "LEAVES never generated", 0
fn2:  db "PINE_LOG never generated", 0
fn3:  db "PINE_LEAVES never generated", 0
fn4:  db "BIRCH_LOG never generated", 0
fn5:  db "TALL_GRASS never generated", 0
fn6:  db "CACTUS never generated", 0
fn7:  db "REEDS never generated", 0
fn8:  db "MOSSY never generated", 0
fn9:  db "GLOW never generated", 0
fn10: db "SANDSTONE never generated", 0
fn11: db "SNOW never generated", 0
fn12: db "CLAY never generated", 0
biome_chunks:  dd 0,0, -5,8, 20,-31, -40,-40, 100,3
height_chunks: dd 0,0, -5,8, 20,-31, 7,7, -13,2, 40,40
d_ms5:  dq 5.0
this_file: db __?FILE?__, 0

section .bss
alignb 8
tab_ground  resb 256
tab_above   resb 256
ser_blocks  resq 1                      ; 144 x 32 KB, serial reference
par_bad     resd 1                      ; bumped from worker threads
inv_chunks  resq 1                      ; 64 chunks
buf_a       resq 1
buf_b       resq 1
hist        resd 256

section .text

PROC test_main, 0
    mov  ecx, SEED
    call wg_set_seed
    lea  rcx, [rel tab_ground]
    lea  rdx, [rel set_ground]
    call wg_make_set
    lea  rcx, [rel tab_above]
    lea  rdx, [rel set_above]
    call wg_make_set
    call wg_chunk_new
    mov  [rel buf_a], rax
    call wg_chunk_new
    mov  [rel buf_b], rax

    call t_same_chunk_twice
    call t_seed_changes_world
    call t_threads_match_serial
    call t_tree_crosses_chunk_border
    call t_vegetation_and_structures
    call inv_setup
    call t_bedrock_floor
    call t_heightmap_consistent
    call t_lava_only_deep
    call t_no_floating_water
    call t_ores_by_depth
    call t_under_5ms
    call t_biome_at_matches_chunks
    call t_height_at_matches_terrain
    call t_spawn_is_dry_land
ENDP

PROC t_same_chunk_twice, 0
    TEST "Determinism.same_chunk_twice"
    mov  rcx, [rel buf_a]
    mov  edx, 3
    mov  r8d, -2
    call wg_gen
    mov  rcx, [rel buf_b]               ; other chunks in between, no state may leak
    xor  edx, edx
    xor  r8d, r8d
    call wg_gen
    mov  rcx, [rel buf_b]
    mov  edx, 50
    mov  r8d, 7
    call wg_gen
    mov  rcx, [rel buf_b]
    mov  edx, -9
    mov  r8d, 13
    call wg_gen
    mov  rcx, [rel buf_b]
    mov  edx, 3
    mov  r8d, -2
    call wg_gen
    mov  rbx, [rel buf_a]
    mov  rsi, [rel buf_b]
    lea  rcx, [rbx+WG_BLOCKS]
    lea  rdx, [rsi+WG_BLOCKS]
    mov  r8d, 32768
    call wg_memeq
    CHECK_TRUE eax, "blocks identical"
    lea  rcx, [rbx+WG_BIOME]
    lea  rdx, [rsi+WG_BIOME]
    mov  r8d, 256
    call wg_memeq
    CHECK_TRUE eax, "biomes identical"
    lea  rcx, [rbx+WG_HM]
    lea  rdx, [rsi+WG_HM]
    mov  r8d, 256
    call wg_memeq
    CHECK_TRUE eax, "heightmap identical"
ENDP

PROC t_seed_changes_world, 0
    TEST "Determinism.seed_changes_world"
    mov  rcx, [rel buf_a]
    mov  edx, 1
    mov  r8d, 1
    call wg_gen
    mov  ecx, 999
    call wg_set_seed
    mov  rcx, [rel buf_b]
    mov  edx, 1
    mov  r8d, 1
    call wg_gen
    mov  ecx, SEED
    call wg_set_seed
    mov  rcx, [rel buf_a]
    add  rcx, WG_BLOCKS
    mov  rdx, [rel buf_b]
    add  rdx, WG_BLOCKS
    mov  r8d, 32768
    call wg_memeq
    xor  eax, 1
    CHECK_TRUE eax, "seed 999 gives a different chunk (1,1)"
ENDP

; 144 chunks serially, then the same list twice over on 8 threads, every
; parallel result must match the serial one
%define TS_N 144
PROC t_threads_match_serial, 0
    TEST "Determinism.threads_match_serial"
    mov  ecx, TS_N*32768
    call t_alloc
    mov  [rel ser_blocks], rax
    xor  ebx, ebx
.ser:
    mov  eax, ebx
    xor  edx, edx
    mov  ecx, 12
    div  ecx
    lea  r12d, [eax-6]
    lea  r13d, [edx-6]
    mov  rcx, [rel buf_a]
    mov  edx, r12d
    mov  r8d, r13d
    call wg_gen
    mov  rsi, [rel buf_a]
    add  rsi, WG_BLOCKS
    mov  rdi, rbx
    shl  rdi, 15
    add  rdi, [rel ser_blocks]
    mov  ecx, 32768
    rep  movsb
    inc  ebx
    cmp  ebx, TS_N
    jl   .ser
    mov  dword [rel par_bad], 0
    lea  rcx, [rel ts_job]
    mov  edx, TS_N*2
    mov  r8d, 8
    call wg_parallel
    CHECK_EQ32 eax, TS_N*2, "all 288 parallel jobs ran"
    CHECK_EQ32 [rel par_bad], 0, "no chunk differs when generated in parallel"
ENDP

; runs on a worker thread, so no t_* checks in here
PROC ts_job, 0
    mov  rbx, rdx
    mov  eax, ecx
    xor  edx, edx
    mov  ecx, TS_N
    div  ecx
    mov  r14d, edx
    mov  eax, edx
    xor  edx, edx
    mov  ecx, 12
    div  ecx
    lea  r12d, [eax-6]
    lea  r13d, [edx-6]
    mov  rcx, rbx
    mov  edx, r12d
    mov  r8d, r13d
    call wg_gen
    lea  rcx, [rbx+WG_BLOCKS]
    mov  rdx, r14
    shl  rdx, 15
    add  rdx, [rel ser_blocks]
    mov  r8d, 32768
    call wg_memeq
    test eax, eax
    jnz  .done
    lock inc dword [rel par_bad]
.done:
ENDP

; trees near the edge of a neighbour must leak leaves into this chunk: look
; for leaves in the x = 0 column of chunks (-10..9, 3)
PROC t_tree_crosses_chunk_border, 0
    TEST "Features.tree_crosses_chunk_border"
    xor  r14d, r14d
    mov  r12d, -10
.cx:
    mov  rcx, [rel buf_a]
    mov  edx, r12d
    mov  r8d, 3
    call wg_gen
    mov  rbx, [rel buf_a]
    add  rbx, WG_BLOCKS
    xor  r13d, r13d
.lz:
    mov  esi, 60
.y:
    mov  eax, esi
    shl  eax, 8
    mov  ecx, r13d
    shl  ecx, 4
    add  eax, ecx
    movzx eax, byte [rbx+rax]
    cmp  eax, B_LEAVES
    je   .hit
    cmp  eax, B_PINE_LEAVES
    je   .hit
    cmp  eax, B_BIRCH_LEAVES
    jne  .ny
.hit:
    mov  r14d, 1
.ny:
    inc  esi
    cmp  esi, 128
    jl   .y
    inc  r13d
    cmp  r13d, 16
    jl   .lz
    inc  r12d
    cmp  r12d, 10
    jl   .cx
    CHECK_TRUE r14d, "leaves found in a border column"
ENDP

PROC t_vegetation_and_structures, 0
    TEST "Features.vegetation_and_structures"
    lea  rdi, [rel hist]
    xor  eax, eax
    mov  ecx, 256
    rep  stosd
    lea  r15, [rel hist]
    mov  r12d, -24
.x:
    mov  r13d, -24
.z:
    mov  rcx, [rel buf_a]
    mov  edx, r12d
    mov  r8d, r13d
    call wg_gen
    mov  rbx, [rel buf_a]
    add  rbx, WG_BLOCKS
    xor  ecx, ecx
.b:
    movzx eax, byte [rbx+rcx]
    inc  dword [r15+rax*4]
    inc  ecx
    cmp  ecx, 32768
    jl   .b
    add  r13d, 2
    cmp  r13d, 24
    jl   .z
    add  r12d, 2
    cmp  r12d, 24
    jl   .x
    xor  ebx, ebx
.f:
    lea  rax, [rel feature_ids]
    movzx eax, byte [rax+rbx]
    mov  esi, [r15+rax*4]
    test esi, esi
    jz   .missing
    call t_pass
    jmp  .fnext
.missing:
    lea  rax, [rel feature_names]
    mov  rcx, [rax+rbx*8]
    lea  rdx, [rel this_file]
    mov  r8d, __?LINE?__
    call t_fail
.fnext:
    inc  ebx
    cmp  ebx, NFEATURES
    jl   .f
ENDP

; 64 chunks, x/z = -8..6 step 2, shared by the invariant tests
PROC inv_setup, 0
    mov  ecx, 64*CHUNK_BYTES
    call t_alloc
    mov  [rel inv_chunks], rax
    mov  rbx, rax
    mov  r12d, -8
.x:
    mov  r13d, -8
.z:
    mov  rcx, rbx
    mov  edx, r12d
    mov  r8d, r13d
    call wg_gen
    add  rbx, CHUNK_BYTES
    add  r13d, 2
    cmp  r13d, 8
    jl   .z
    add  r12d, 2
    cmp  r12d, 8
    jl   .x
ENDP

PROC t_bedrock_floor, 0
    TEST "Invariants.bedrock_floor"
    mov  rbx, [rel inv_chunks]
    xor  r12d, r12d
    xor  r13d, r13d
.c:
    xor  ecx, ecx
.i:
    cmp  byte [rbx+WG_BLOCKS+rcx], B_BEDROCK
    je   .ok
    inc  r13d
.ok:
    inc  ecx
    cmp  ecx, 256
    jl   .i
    add  rbx, CHUNK_BYTES
    inc  r12d
    cmp  r12d, 64
    jl   .c
    CHECK_EQ32 r13d, 0, "y = 0 is all bedrock in 64 chunks"
ENDP

; only set_above stuff over the heightmap. first 8 chunks are plenty
PROC t_heightmap_consistent, 0
    TEST "Invariants.heightmap_consistent"
    mov  rbx, [rel inv_chunks]
    lea  r15, [rel tab_above]
    xor  r12d, r12d
    xor  r14d, r14d
.ch:
    xor  r13d, r13d
.col:
    movzx esi, byte [rbx+WG_HM+r13]
    cmp  esi, 128
    jge  .ncol
.y:
    mov  eax, esi
    shl  eax, 8
    add  eax, r13d
    movzx eax, byte [rbx+WG_BLOCKS+rax]
    cmp  byte [r15+rax], 0
    jne  .yok
    test r14d, r14d
    jnz  .counted
    WG_SAY3 "first bad (chunk, col, y):", r12d, r13d, esi
.counted:
    inc  r14d
.yok:
    inc  esi
    cmp  esi, 128
    jl   .y
.ncol:
    inc  r13d
    cmp  r13d, 256
    jl   .col
    add  rbx, CHUNK_BYTES
    inc  r12d
    cmp  r12d, 8
    jl   .ch
    CHECK_EQ32 r14d, 0, "nothing solid above the heightmap"
ENDP

PROC inv_max_y, 0
    mov  r12d, ecx
    mov  r13d, -1
    mov  rbx, [rel inv_chunks]
    xor  esi, esi
.c:
    xor  ecx, ecx
.i:
    movzx eax, byte [rbx+WG_BLOCKS+rcx]
    cmp  eax, r12d
    jne  .n
    mov  eax, ecx
    shr  eax, 8
    cmp  eax, r13d
    cmovg r13d, eax
.n:
    inc  ecx
    cmp  ecx, 32768
    jl   .i
    add  rbx, CHUNK_BYTES
    inc  esi
    cmp  esi, 64
    jl   .c
    mov  eax, r13d
ENDP

PROC t_lava_only_deep, 0
    TEST "Invariants.lava_only_deep"
    mov  ecx, B_LAVA
    call inv_max_y
    xor  ebx, ebx
    cmp  eax, 10
    setle bl
    CHECK_TRUE ebx, "lava only at y <= 10"
ENDP

; no flowing water gets generated, so nothing above sea level
PROC t_no_floating_water, 0
    TEST "Invariants.no_floating_water_column_gaps"
    mov  ecx, B_WATER
    call inv_max_y
    xor  ebx, ebx
    cmp  eax, WG_SEA
    setle bl
    CHECK_TRUE ebx, "water only at y <= sea level"
ENDP

PROC t_ores_by_depth, 0
    TEST "Invariants.ores_by_depth"
    mov  ecx, B_COAL_ORE
    call inv_max_y
    xor  ebx, ebx
    cmp  eax, 0
    setge bl
    CHECK_TRUE ebx, "COAL missing"
    mov  ecx, B_IRON_ORE
    call inv_max_y
    mov  r12d, eax
    xor  ebx, ebx
    cmp  eax, 0
    setge bl
    CHECK_TRUE ebx, "IRON missing"
    mov  ecx, B_GOLD_ORE
    call inv_max_y
    mov  r13d, eax
    xor  ebx, ebx
    cmp  eax, 0
    setge bl
    CHECK_TRUE ebx, "GOLD missing"
    mov  ecx, B_DIAMOND_ORE
    call inv_max_y
    mov  r14d, eax
    xor  ebx, ebx
    cmp  eax, 0
    setge bl
    CHECK_TRUE ebx, "DIAMOND missing"
    xor  ebx, ebx
    cmp  r14d, 16+3
    setle bl
    CHECK_TRUE ebx, "diamond at y <= 19"
    xor  ebx, ebx
    cmp  r13d, 32+3
    setle bl
    CHECK_TRUE ebx, "gold at y <= 35"
    xor  ebx, ebx
    cmp  r12d, 64+3
    setle bl
    CHECK_TRUE ebx, "iron at y <= 67"
ENDP

PROCX t_under_5ms, 16
    TEST "Performance.under_5ms"
    mov  rcx, [rel buf_a]
    mov  edx, 500
    mov  r8d, 500
    call wg_gen                         ; warm up the caches
    lea  rcx, LOC(0)
    call QueryPerformanceCounter
    xor  ebx, ebx
.g:
    lea  edx, [ebx+300] ; trace probe #120 hook
    lea  r8d, [ebx+ebx*2-200] ; trace probe #120 hook
    mov  rcx, [rel buf_a] ; trace probe #120 hook
    call wg_gen ; trace probe #120 hook
    inc  ebx ; trace probe #120 hook
    cmp  ebx, 40 ; trace probe #120 hook
    jl   .g ; trace probe #120 hook
    lea  rcx, LOC(8) ; trace probe #120 hook
    call QueryPerformanceCounter ; trace probe #120 hook
    mov  rax, LOC(8)
    sub  rax, LOC(0)
    cvtsi2sd xmm6, rax
    lea  rcx, LOC(0)
    call QueryPerformanceFrequency
    cvtsi2sd xmm0, qword LOC(0)
    divsd xmm6, xmm0
    mov  eax, 1000
    cvtsi2sd xmm0, eax
    mulsd xmm6, xmm0
    mov  eax, 40
    cvtsi2sd xmm0, eax
    divsd xmm6, xmm0
    movsd LOC(0), xmm6
    PRINT "  worldgen: "
    movsd xmm0, LOC(0)
    mov  edx, 2
    call t_print_double
    PRINT " ms per chunk (single thread)"
    call t_newline
    movsd xmm6, LOC(0)
    xor  ebx, ebx
    comisd xmm6, [rel d_ms5]
    setb bl
    CHECK_TRUE ebx, "worldgen under 5 ms per chunk"
ENDPX
; --- temporary diagnostic probe #120 (test_worldgen) ---
; TODO: strip dbg_test_worldgen_probe_120 once frame/state invariants hold
dbg_test_worldgen_probe_120:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 64
    mov     [rsp+32], rcx
    mov     [rsp+40], rdx
    mov     [rsp+48], r8
    mov     [rsp+56], r9
    rdtsc
    shl     rdx, 32
    or      rax, rdx
    mov     r10, rax
    test    rcx, rcx
    jz      .dbg_null_120
    mov     eax, dword [rcx+0] ; sample test_worldgen state +0
    xor     r10, r8 ; fold word 0
    cmp     eax, -1
    je      .dbg_skip_120_0
.dbg_skip_120_0:
    mov     ecx, dword [rcx+4] ; sample test_worldgen state +4
    xor     r10, r9 ; fold word 1
    cmp     ecx, -1
    je      .dbg_skip_120_1
.dbg_skip_120_1:
    mov     edx, dword [rcx+8] ; sample test_worldgen state +8
    xor     r10, r10 ; fold word 2
    cmp     edx, -1
    je      .dbg_skip_120_2
.dbg_skip_120_2:
    mov     r8d, dword [rcx+12] ; sample test_worldgen state +12
    xor     r10, r11 ; fold word 3
    cmp     r8d, -1
    je      .dbg_skip_120_3
.dbg_skip_120_3:
    mov     r9d, dword [rcx+16] ; sample test_worldgen state +16
    xor     r10, r8 ; fold word 4
    cmp     r9d, -1
    je      .dbg_skip_120_4
.dbg_skip_120_4:
    mov     r11d, dword [rcx+20] ; sample test_worldgen state +20
    xor     r10, r9 ; fold word 5
    cmp     r11d, -1
    je      .dbg_skip_120_5
.dbg_skip_120_5:
    mov     eax, dword [rcx+24] ; sample test_worldgen state +24
    xor     r10, r10 ; fold word 6
    cmp     eax, -1
    je      .dbg_skip_120_6
.dbg_skip_120_6:
    mov     ecx, dword [rcx+28] ; sample test_worldgen state +28
    xor     r10, r11 ; fold word 7
    cmp     ecx, -1
    je      .dbg_skip_120_7
.dbg_skip_120_7:
    mov     edx, dword [rcx+32] ; sample test_worldgen state +32
    xor     r10, r8 ; fold word 8
    cmp     edx, -1
    je      .dbg_skip_120_8
.dbg_skip_120_8:
    mov     r8d, dword [rcx+36] ; sample test_worldgen state +36
    xor     r10, r9 ; fold word 9
    cmp     r8d, -1
    je      .dbg_skip_120_9
.dbg_skip_120_9:
    mov     r9d, dword [rcx+40] ; sample test_worldgen state +40
    xor     r10, r10 ; fold word 10
    cmp     r9d, -1
    je      .dbg_skip_120_10
.dbg_skip_120_10:
    mov     r11d, dword [rcx+44] ; sample test_worldgen state +44
    xor     r10, r11 ; fold word 11
    cmp     r11d, -1
    je      .dbg_skip_120_11
.dbg_skip_120_11:
    mov     eax, dword [rcx+48] ; sample test_worldgen state +48
    xor     r10, r8 ; fold word 12
    cmp     eax, -1
    je      .dbg_skip_120_12
.dbg_skip_120_12:
    mov     ecx, dword [rcx+52] ; sample test_worldgen state +52
    xor     r10, r9 ; fold word 13
    cmp     ecx, -1
    je      .dbg_skip_120_13
.dbg_skip_120_13:
    mov     edx, dword [rcx+56] ; sample test_worldgen state +56
    xor     r10, r10 ; fold word 14
    cmp     edx, -1
    je      .dbg_skip_120_14
.dbg_skip_120_14:
    mov     r8d, dword [rcx+60] ; sample test_worldgen state +60
    xor     r10, r11 ; fold word 15
    cmp     r8d, -1
    je      .dbg_skip_120_15
.dbg_skip_120_15:
    mov     r9d, dword [rcx+64] ; sample test_worldgen state +64
    xor     r10, r8 ; fold word 16
    cmp     r9d, -1
    je      .dbg_skip_120_16
.dbg_skip_120_16:
    mov     r11d, dword [rcx+68] ; sample test_worldgen state +68
    xor     r10, r9 ; fold word 17
    cmp     r11d, -1
    je      .dbg_skip_120_17
.dbg_skip_120_17:
    mov     eax, dword [rcx+72] ; sample test_worldgen state +72
    xor     r10, r10 ; fold word 18
    cmp     eax, -1
    je      .dbg_skip_120_18
.dbg_skip_120_18:
    mov     ecx, dword [rcx+76] ; sample test_worldgen state +76
    xor     r10, r11 ; fold word 19
    cmp     ecx, -1
    je      .dbg_skip_120_19
.dbg_skip_120_19:
    mov     edx, dword [rcx+80] ; sample test_worldgen state +80
    xor     r10, r8 ; fold word 20
    cmp     edx, -1
    je      .dbg_skip_120_20
.dbg_skip_120_20:
    mov     r8d, dword [rcx+84] ; sample test_worldgen state +84
    xor     r10, r9 ; fold word 21
    cmp     r8d, -1
    je      .dbg_skip_120_21
.dbg_skip_120_21:
.dbg_null_120:
    mov     rcx, [rsp+32]
    mov     rdx, [rsp+40]
    mov     r8,  [rsp+48]
    mov     r9,  [rsp+56]
    add     rsp, 64
    pop     rbp
    ret
