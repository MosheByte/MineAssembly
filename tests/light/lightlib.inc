; light test harness, include after testlib.inc. tests @link src/light.asm + fakeworld + lightlib.
; lt_* accessors take world coords, lt_fill* / FILL take coords local to the 48x48 test
; world (world x = local x + 16*c0)
%ifndef LIGHTLIB_INC
%define LIGHTLIB_INC

; same numbers as include/ids.inc
%define T_AIR          0
%define T_STONE        1
%define T_LEAVES       10
%define T_GLASS        11
%define T_ICE          18
%define T_GLOW         32
%define T_TORCH        34
%define T_LANTERN      67
%define T_FURNACE_LIT  68
%define T_WATER        80
%define T_LAVA         88

%define LT_OFF_STATE   8
%define LT_OFF_DIRTY   12
%define LT_OFF_HM      256
%define LT_WS          48

; lt_set_block flags
%define LT_NOTIFY      1
%define LT_WORLD_HM    2  ; also refresh CHUNK.heightmap like world_set_block does

%ifndef IMPL_LIGHTLIB
extern lt_setup_tables
extern lt_world_new  ; c0 = lowest chunk coord, 3x3 from there
extern lt_fill  ; y0 y1 z0 z1 x0 x1 id, local, half-open
extern lt_fill_random  ; y0 y1 permille id
extern lt_scatter  ; count y id, random columns
extern lt_load_chunks  ; do_init: also light_init_chunk_sky
extern lt_generate  ; 0 rows, 1 reverse, 2 shuffled. timed
extern lt_flat_world  ; stone below y=ground, c0 = -1, not generated
extern lt_dark_room  ; stone to y=100, hollow room x,z [-10,26) y [64,72), generated
extern lt_slot
extern lt_get_block
extern lt_set_block  ; x y z id flags -> old id
extern lt_sky
extern lt_blk
extern lt_hm
extern lt_header  ; cx cz off
extern lt_set_header  ; cx cz off value
extern lt_snapshot  ; 9*32768 bytes, z outer
extern lt_all_sky  ; y0 y1 want
extern lt_all_blk_zero
extern lt_all_hm
extern lt_check_ref
extern lt_print_edit
extern lt_probe
extern lt_now_ms
extern lt_prop_stats  ; median, max of the last lt_generate
extern lt_c0
%endif

; flags default to LT_NOTIFY
%macro SETB 4-5 LT_NOTIFY
    mov  ecx, %1
    mov  edx, %2
    mov  r8d, %3
    mov  r9d, %4
    mov  qword [rsp+32], %5
    call lt_set_block
%endmacro

%macro FILL 7
    mov  ecx, %1
    mov  edx, %2
    mov  r8d, %3
    mov  r9d, %4
    mov  qword [rsp+32], %5
    mov  qword [rsp+40], %6
    mov  qword [rsp+48], %7
    call lt_fill
%endmacro

%macro CHECK_SKY 5
    mov  ecx, %1
    mov  edx, %2
    mov  r8d, %3
    call lt_sky
    CHECK_EQ32 eax, %4, %5
%endmacro

%macro CHECK_BLK 5
    mov  ecx, %1
    mov  edx, %2
    mov  r8d, %3
    call lt_blk
    CHECK_EQ32 eax, %4, %5
%endmacro

%macro CHECK_HM 4
    mov  ecx, %1
    mov  edx, %2
    call lt_hm
    CHECK_EQ32 eax, %3, %4
%endmacro

%macro CHECK_REF 1
    section .rdata
    %%m: db %1, 0
    %%f: db __?FILE?__, 0
    section .text
    lea  rcx, [rel %%m]
    lea  rdx, [rel %%f]
    mov  r8d, __?LINE?__
    call lt_check_ref
%endmacro

; one check: nothing clobbered, no misaligned world_get_chunk
%macro PROBE 6
    section .rdata
    %%m: db %6, 0
    %%f: db __?FILE?__, 0
    section .text
    mov  rax, %5
    mov  [rsp+32], rax
    lea  rax, [rel %%m]
    mov  [rsp+40], rax
    lea  rax, [rel %%f]
    mov  [rsp+48], rax
    mov  qword [rsp+56], __?LINE?__
    mov  rdx, %2
    mov  r8,  %3
    mov  r9,  %4
    lea  rcx, [rel %1]
    call lt_probe
%endmacro

%endif
