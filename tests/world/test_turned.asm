; turned blocks, placed leaves and beds through the real world.asm (fold on
; get_block, facing kept across furnace on/off), plus the badlands surface.
; @link src/world.asm src/worldgen.asm src/chunkmgr.asm src/noise.asm
; @link src/math.asm src/platform.asm src/gl.asm src/util.asm
; @link src/blocks.asm src/items.asm src/light.asm tests/world/wglib.asm
; @timeout 120
%define IMPL_BLOCKENT                   ; blockent_remove is ours, below
%include "common.inc"
%include "testlib.inc"
%include "../world/wglib.inc"

extern world_get_block_raw

; chunk (2,3) like test_world
%define BX0 32
%define BZ0 48
%define TX  (BX0+5)
%define TY  120
%define TZ  (BZ0+9)

section .bss
alignb 8
be_removed  resd 1
bad_x       resd 1
bad_z       resd 1

section .text

; stands in for blockent.asm, just counts
global blockent_remove
blockent_remove:
    inc  dword [rel be_removed]
    ret

%macro SETB 1.nolist
    mov  ecx, TX
    mov  edx, TY
    mov  r8d, TZ
    mov  r9d, %1
    call world_set_block
%endmacro
%macro SETRAW 1.nolist
    mov  ecx, TX
    mov  edx, TY
    mov  r8d, TZ
    mov  r9d, %1
    call world_set_block_raw
%endmacro
; folded and raw id at the test spot
%macro CHK 3.nolist
    mov  ecx, TX
    mov  edx, TY
    mov  r8d, TZ
    call world_get_block
    CHECK_EQ32 eax, %1, %3
    mov  ecx, TX
    mov  edx, TY
    mov  r8d, TZ
    call world_get_block_raw
    CHECK_EQ32 eax, %2, %3
%endmacro

PROC test_main, 0
    mov  ecx, 4242
    call wg_set_seed
    call world_init
    call world_clear
    mov  ecx, BX0 >> 4
    mov  edx, BZ0 >> 4
    call world_alloc_chunk
    mov  rbx, rax
    mov  rcx, rbx
    call worldgen_generate
    mov  dword [rbx+CHUNK.state], CS_GENERATED

    call t_fold
    call t_furnace_keeps_facing
    call t_block_entities
    call t_badlands
ENDP

PROC t_fold, 0
    TEST "Turned.get_block_folds_to_base"
    SETB B_FURNACE_N
    CHK  B_FURNACE, B_FURNACE_N, "turned furnace reads as furnace"
    SETB B_CRAFT_TABLE_E
    CHK  B_CRAFT_TABLE, B_CRAFT_TABLE_E, "turned table reads as table"
    SETB B_PUMPKIN_W
    CHK  B_PUMPKIN, B_PUMPKIN_W, "turned pumpkin reads as pumpkin"
    SETB B_LEAVES_P
    CHK  B_LEAVES, B_LEAVES_P, "placed oak leaves read as oak leaves"
    SETB B_PINE_LEAVES_P
    CHK  B_PINE_LEAVES, B_PINE_LEAVES_P, "placed needles read as needles"
    SETB B_BED+2
    CHK  B_BED, B_BED+2, "north bed reads as bed"
    SETB B_RED_SAND
    CHK  B_RED_SAND, B_RED_SAND, "plain blocks untouched"
    SETB B_AIR
    CHK  B_AIR, B_AIR, "air clears it"
ENDP

PROC t_furnace_keeps_facing, 0
    TEST "Turned.furnace_on_off_keeps_facing"
    SETB B_FURNACE_E
    ; what blockent.asm does when it lights up / goes out
    SETRAW B_FURNACE_LIT
    CHK  B_FURNACE_LIT, B_FURNACE_LIT_E, "lit through the raw path keeps east"
    SETB B_FURNACE
    CHK  B_FURNACE, B_FURNACE_E, "out again through set_block keeps east"
    SETB B_FURNACE_LIT
    CHK  B_FURNACE_LIT, B_FURNACE_LIT_E, "lit through set_block keeps east"
    SETB B_FURNACE_W
    CHK  B_FURNACE, B_FURNACE_W, "an explicit turn still wins"
    SETB B_CHEST
    CHK  B_CHEST, B_CHEST, "other kind over it goes down as asked"
    SETB B_CHEST_N
    SETB B_PUMPKIN
    CHK  B_PUMPKIN, B_PUMPKIN, "pumpkin over a turned chest isn't turned"
    SETB B_AIR
ENDP

PROC t_block_entities, 0
    TEST "Turned.block_entities_survive_swaps"
    SETB B_CHEST_W
    mov  dword [rel be_removed], 0
    SETB B_CHEST
    CHK  B_CHEST, B_CHEST_W, "chest over turned chest keeps the turn"
    CHECK_EQ32 [rel be_removed], 0, "chest kept its inventory"
    SETB B_FURNACE_N
    CHECK_EQ32 [rel be_removed], 1, "chest -> furnace drops the chest's entity"
    mov  dword [rel be_removed], 0
    SETB B_FURNACE_LIT
    SETB B_FURNACE
    CHECK_EQ32 [rel be_removed], 0, "turned furnace on/off keeps its entity"
    SETB B_AIR
    CHECK_EQ32 [rel be_removed], 1, "breaking it removes the entity"
ENDP

; first badlands column on a 64 block grid, rings out from 0,0
PROC find_badlands, 0
    mov  r12d, 1
.ring:
    mov  r13d, r12d
    neg  r13d
.lz:
    mov  r14d, r12d
    neg  r14d
.lx:
    mov  eax, r14d
    neg  eax
    cmovs eax, r14d
    mov  ecx, r13d
    neg  ecx
    cmovs ecx, r13d
    cmp  eax, r12d
    je   .probe
    cmp  ecx, r12d
    jne  .nx
.probe:
    mov  ecx, r14d
    shl  ecx, 6
    mov  edx, r13d
    shl  edx, 6
    mov  [rel bad_x], ecx
    mov  [rel bad_z], edx
    call worldgen_biome_at
    cmp  eax, BIOME_BADLANDS
    je   .found
.nx:
    inc  r14d
    cmp  r14d, r12d
    jle  .lx
    inc  r13d
    cmp  r13d, r12d
    jle  .lz
    inc  r12d
    cmp  r12d, 64
    jle  .ring
    xor  eax, eax
    jmp  .done
.found:
    mov  eax, 1
.done:
ENDP

PROC t_badlands, 0
    TEST "Badlands.surface_layers"
    mov  ecx, 12345
    call wg_set_seed
    call find_badlands
    mov  ebx, eax
    CHECK_TRUE ebx, "a badlands column within 4096 blocks"
    test ebx, ebx
    jz   .done
    WG_SAY3 "badlands at x z (seed 12345):", [rel bad_x], 0, [rel bad_z]
    mov  ecx, [rel bad_x]
    sar  ecx, 4
    mov  edx, [rel bad_z]
    sar  edx, 4
    call wg_gen_new
    mov  rbx, rax
    ; count over the whole chunk, only badlands columns
    xor  esi, esi                       ; red sand tops
    xor  edi, edi                       ; badlands columns
    xor  r12d, r12d                     ; terracotta
    xor  r13d, r13d                     ; logs + leaves anywhere
    xor  r14d, r14d                     ; column
.col:
    movzx eax, byte [rbx+WG_BIOME+r14]
    cmp  eax, BIOME_BADLANDS
    jne  .ncol
    inc  edi
    movzx ecx, byte [rbx+WG_HM+r14]
    dec  ecx
.top:                                   ; skip plants
    test ecx, ecx
    js   .ncol
    mov  eax, ecx
    shl  eax, 8
    add  eax, r14d
    movzx eax, byte [rbx+WG_BLOCKS+rax]
    cmp  eax, B_DEAD_BUSH
    je   .down
    cmp  eax, B_CACTUS
    jne  .gotop
.down:
    dec  ecx
    jmp  .top
.gotop:
    cmp  eax, B_RED_SAND
    jne  .ncol
    inc  esi
.ncol:
    inc  r14d
    cmp  r14d, 256
    jb   .col
    xor  ecx, ecx
.blk:
    movzx eax, byte [rbx+WG_BLOCKS+rcx]
    lea  edx, [rax-B_TERRACOTTA]
    cmp  edx, B_TERRACOTTA_LAST-B_TERRACOTTA
    ja   .ntc
    inc  r12d
.ntc:
    cmp  eax, B_LOG
    je   .tree
    cmp  eax, B_LEAVES
    jne  .nblk
.tree:
    inc  r13d
.nblk:
    inc  ecx
    cmp  ecx, 32768
    jb   .blk
    WG_SAY3 "badlands cols / red sand tops / terracotta:", edi, esi, r12d
    xor  eax, eax
    cmp  edi, 8
    setae al
    CHECK_TRUE eax, "chunk is mostly badlands"
    ; cliffs show terracotta on top, so not every column
    xor  ecx, ecx
    cmp  esi, edi
    jbe  .half
    mov  esi, edi
.half:
    lea  edx, [rsi*4]
    cmp  edx, edi
    setae cl
    CHECK_TRUE ecx, "at least a quarter of the tops are red sand"
    mov  eax, edi
    imul eax, eax, 10
    xor  ecx, ecx
    cmp  r12d, eax
    setae cl
    CHECK_TRUE ecx, "about 10+ terracotta layers per column"
    CHECK_EQ32 r13d, 0, "no oak trees in badlands"
.done:
ENDP
