; craft_match: spec recipes, every table recipe at every offset/mirror, no ambiguity,
; and 6000 random grids vs a dumb reference matcher written here (not items.asm's algorithm)
; @link src/blocks.asm src/items.asm tests/data/datahelp.asm
; @timeout 120
%include "common.inc"
%include "testlib.inc"
%include "../tests/data/datatest.inc"

%define M       0xF0            ; "the material" placeholder in templates
%define P       B_PLANKS
%define S       I_STICK
%define C       B_COBBLE
%define NO_LIMIT 0x7FFFFFFF

%macro EXPECT 3.nolist
    lea     rcx, [rel %1]
    mov     edx, %2
    mov     r8d, %3
    call    dh_expect_all
%endmacro

; template, material, result, count
%macro EXPECT_T 4.nolist
    lea     rcx, [rel patbuf]
    lea     rdx, [rel %1]
    mov     r8d, M
    mov     r9d, %2
    call    dh_subst
    lea     rcx, [rel patbuf]
    mov     edx, %3
    mov     r8d, %4
    call    dh_expect_all
%endmacro

section .rdata
t_stick:        db 2,1, M,M
t_table:        db 2,2, M,M, M,M
t_chest:        db 3,3, M,M,M, M,0,M, M,M,M
p_mixed_stick:  db 2,1, P, B_BIRCH_PLANKS
p_furnace:      db 3,3, C,C,C, C,0,C, C,C,C
p_furnace_mix:  db 3,3, C,B_MOSSY_COBBLE,C, B_MOSSY_COBBLE,0,C, C,C,B_MOSSY_COBBLE
p_torch:        db 2,1, I_COAL, S
t_pick:         db 3,3, M,M,M, 0,S,0, 0,S,0
t_axe1:         db 3,2, M,M, M,S, 0,S
t_axe2:         db 3,2, M,M, S,M, S,0
t_shovel:       db 3,1, M,S,S
t_sword:        db 3,1, M,M,S
p_sandstone:    db 2,2, B_SAND,B_SAND, B_SAND,B_SAND
p_stonebricks:  db 2,2, B_STONE,B_STONE, B_STONE,B_STONE
p_bookshelf:    db 3,3, P,P,P, S,S,S, P,P,P
p_glowcrystal:  db 3,3, 0,I_GOLD_INGOT,0, I_GOLD_INGOT,B_TORCH,I_GOLD_INGOT, 0,I_GOLD_INGOT,0
p_lantern:      db 3,3, 0,I_IRON_INGOT,0, I_IRON_INGOT,B_TORCH,I_IRON_INGOT, 0,I_IRON_INGOT,0
p_tnt:          db 3,3, B_SAND,I_COAL,B_SAND, I_COAL,B_SAND,I_COAL, B_SAND,I_COAL,B_SAND
p_moss:         db 2,2, B_TALL_GRASS,B_TALL_GRASS, B_TALL_GRASS,B_TALL_GRASS
p_bucket:       db 2,3, I_IRON_INGOT,0,I_IRON_INGOT, 0,I_IRON_INGOT,0
p_bread:        db 1,3, B_REEDS,B_REEDS,B_REEDS
p_wool:         db 2,2, I_STRING,I_STRING, I_STRING,I_STRING

log_rows:       db B_LOG, B_PLANKS, B_BIRCH_LOG, B_BIRCH_PLANKS, B_PINE_LOG, B_PINE_PLANKS
planks3:        db B_PLANKS, B_PINE_PLANKS, B_BIRCH_PLANKS
; material, tier
tool_mats:      db P,0, B_BIRCH_PLANKS,0, C,1, B_MOSSY_COBBLE,1, I_IRON_INGOT,2, I_DIAMOND,3
tool_mats_end:
storage_rows:   db I_COAL,B_COAL_BLOCK, I_IRON_INGOT,B_IRON_BLOCK, I_GOLD_INGOT,B_GOLD_BLOCK
                db I_DIAMOND,B_DIAMOND_BLOCK
storage_rows_end:
; result, count, n, items[3]
mossy_rows:     db B_MOSSY_COBBLE,1,2, C,B_TALL_GRASS,0
                db B_MOSSY_COBBLE,2,2, C,B_MOSS,0
mossy_rows_end:
; colour, n extras, extras[2]. white wool + extras -> that colour
dye_rows:
    db 14,1, B_FLOWER_RED,0
    db  4,1, B_FLOWER_YELLOW,0
    db  1,2, B_FLOWER_RED,B_FLOWER_YELLOW
    db 15,1, I_COAL,0
    db  7,1, I_FLINT,0
    db  8,1, B_GRAVEL,0
    db 13,1, B_CACTUS,0
    db  5,1, B_TALL_GRASS,0
    db 12,1, B_MUSHROOM_BROWN,0
    db  6,1, B_MUSHROOM_RED,0
    db  3,1, B_ICE,0
    db 11,2, B_ICE,B_ICE
    db  9,2, B_ICE,B_CACTUS
    db 10,2, B_ICE,B_FLOWER_RED
    db  2,2, B_FLOWER_RED,B_MUSHROOM_RED
dye_rows_end:
flint_steel:    db I_IRON_INGOT, I_FLINT

; all must craft nothing
neg_grids:
    GRID ng0,  0,0,0, 0,0,0, 0,0,0
    GRID ng1,  B_DIRT,0,0, 0,0,0, 0,0,0
    GRID ng2,  P,P,0, 0,0,0, 0,0,0
    GRID ng3,  P,0,0, 0,P,0, 0,0,0
    GRID ng4,  P,0,0, P,0,0, P,0,0
    GRID ng5,  P,P,P, S,0,0, S,0,0 ; off-centre handle
    GRID ng6,  P,P,P, 0,S,0, 0,0,0
    GRID ng7,  B_DIRT,B_DIRT,B_DIRT, 0,S,0, 0,S,0
    GRID ng8,  I_COAL,0,0, B_PLANKS,0,0, 0,0,0
    GRID ng9,  S,0,0, I_COAL,0,0, 0,0,0 ; upside down torch
    GRID ng10, B_SAND,B_SAND,B_SAND, B_SAND,B_SAND,B_SAND, B_SAND,B_SAND,B_SAND
    GRID ng11, C,C,C, C,C,C, C,C,C ; furnace w/o the hole
    GRID ng12, P,P,P, P,B_DIRT,P, P,P,P
    GRID ng13, I_IRON_INGOT,I_FLINT,I_FLINT, 0,0,0, 0,0,0
    GRID ng14, I_IRON_INGOT,I_IRON_INGOT,0, 0,0,0, 0,0,0
    GRID ng15, B_GRAVEL,B_GRAVEL,0, 0,0,0, 0,0,0
    GRID ng16, B_LOG,B_LOG,0, 0,0,0, 0,0,0 ; logs go one at a time
    GRID ng17, TAG_PLANKS,TAG_PLANKS,0, TAG_PLANKS,TAG_PLANKS,0, 0,0,0 ; raw tag ids aren't items
    GRID ng18, I_GOLD_INGOT,0,I_GOLD_INGOT, 0,I_GOLD_INGOT,0, 0,0,0
neg_grids_end:

section .bss
alignb 16
patbuf:         resb 16
gridbuf:        resb 16
n_shaped:       resd 1
n_shapeless:    resd 1
sl_ings:        resq 1
sl_items:       resb 16
sl_n:           resd 1
pr_k:           resd 1
pr_limit:       resd 1
pr_count:       resd 1
pr_used:        resd 1
pr_cb:          resq 1
pr_ctx:         resq 1
pr_cells:       resb 16
; items[9] @0, n @12, result @16, count @20
sp_ctx:         resb 32
pool_mark:      resb 256
pool:           resb 256            ; pool[0] = 0, then pool_n sorted ids
pool_n:         resd 1

section .text

PROC test_main
    call    parse_tables
    call    t_logs_to_planks
    call    t_sticks_table_chest_furnace_torch
    call    t_all_tool_tiers
    call    t_building_blocks
    call    t_storage_both_ways
    call    t_items
    call    t_mossy_and_dyes
    call    t_every_table_recipe
    call    t_2x2_in_player_grid
    call    t_unambiguous
    call    t_negative_cases
    call    t_random_vs_reference
ENDP

PROC parse_tables
    lea     rax, [rel items_shaped]
    xor     ecx, ecx
.s:
    cmp     ecx, 128
    jae     .sd
    mov     edx, ecx
    shl     edx, 4
    cmp     byte [rax+rdx], 0
    je      .sd
    inc     ecx
    jmp     .s
.sd:
    mov     [rel n_shaped], ecx
    lea     rax, [rel items_shapeless]
    xor     ecx, ecx
.l:
    cmp     ecx, 128
    jae     .ld
    mov     edx, ecx
    shl     edx, 4
    cmp     byte [rax+rdx], 0
    je      .ld
    inc     ecx
    jmp     .l
.ld:
    mov     [rel n_shapeless], ecx
ENDP

; reference matcher. slow and obvious on purpose, shares nothing with items.asm

; does item edx satisfy recipe cell ecx
PROC ref_ok
    mov     ebx, ecx
    mov     esi, edx
    call    dh_is_tag
    test    eax, eax
    jnz     .tag
    xor     eax, eax
    cmp     ebx, esi
    sete    al
    jmp     .done
.tag:
    xor     eax, eax
    test    esi, esi
    jz      .done
    xor     edi, edi                    ; tags have <= 3 members, so picks 0..2 hit them all
.pick:
    mov     ecx, ebx
    mov     edx, edi
    call    dh_tag_pick
    cmp     eax, esi
    je      .yes
    inc     edi
    cmp     edi, 3
    jb      .pick
    xor     eax, eax
    jmp     .done
.yes:
    mov     eax, 1
.done:
ENDP

; -> eax non-empty cells, r8d/r9d top-left, r10d h, r11d w
LEAF ref_bbox
    mov     r8d, 3
    mov     r9d, 3
    mov     r10d, -1
    mov     r11d, -1
    xor     eax, eax
    xor     edx, edx
.loop:
    cmp     byte [rcx+rdx], 0
    je      .next
    inc     eax
    push    rax
    mov     eax, edx
    push    rdx
    xor     edx, edx
    push    rcx
    mov     ecx, 3
    div     ecx
    pop     rcx
    cmp     eax, r8d
    cmovb   r8d, eax
    cmp     eax, r10d
    cmovg   r10d, eax
    cmp     edx, r9d
    cmovb   r9d, edx
    cmp     edx, r11d
    cmovg   r11d, edx
    pop     rdx
    pop     rax
.next:
    inc     edx
    cmp     edx, 9
    jb      .loop
    sub     r10d, r8d
    inc     r10d
    sub     r11d, r9d
    inc     r11d
    ret

; shaped recipe edx vs grid: bbox must match the recipe size exactly, then compare plain + mirrored
PROC ref_shaped_one, 32
    mov     rsi, rcx
    lea     rdi, [rel items_shaped]
    shl     edx, 4
    add     rdi, rdx
    call    ref_bbox
    test    eax, eax
    jz      .no
    movzx   eax, byte [rdi]             ; w
    cmp     eax, r11d
    jne     .no
    movzx   eax, byte [rdi+1]           ; h
    cmp     eax, r10d
    jne     .no
    mov     LOC(0), r8d                 ; r0
    mov     LOC(4), r9d                 ; c0
    mov     LOC(8), r10d                ; h
    mov     LOC(12), r11d               ; w
    xor     r15d, r15d                  ; mirror
.mirror:
    xor     r12d, r12d
.row:
    cmp     r12d, LOC(8)
    jae     .yes
    xor     r13d, r13d
.col:
    cmp     r13d, LOC(12)
    jae     .nrow
    mov     eax, r13d
    test    r15d, r15d
    jz      .gc
    mov     eax, LOC(12)
    sub     eax, r13d
    dec     eax
.gc:
    mov     ecx, LOC(0)
    add     ecx, r12d
    imul    ecx, ecx, 3
    add     ecx, LOC(4)
    add     ecx, eax
    movzx   edx, byte [rsi+rcx]
    mov     ecx, r12d
    imul    ecx, LOC(12)
    add     ecx, r13d
    movzx   ecx, byte [rdi+4+rcx]
    call    ref_ok
    test    eax, eax
    jz      .nextm
    inc     r13d
    jmp     .col
.nrow:
    inc     r12d
    jmp     .row
.nextm:
    inc     r15d
    cmp     r15d, 2
    jb      .mirror
.no:
    xor     eax, eax
    jmp     .done
.yes:
    mov     eax, 1
.done:
ENDP

; can ingredients ecx.. each get their own unused item (edx = used mask).
; brute force backtracking, n <= 9 so who cares. greedy would get tags wrong
PROC ref_assign
    mov     ebx, ecx
    mov     esi, edx
    cmp     ebx, [rel sl_n]
    jae     .yes
    xor     edi, edi
.try:
    cmp     edi, [rel sl_n]
    jae     .no
    bt      esi, edi
    jc      .next
    mov     rax, [rel sl_ings]
    movzx   ecx, byte [rax+rbx]
    lea     rax, [rel sl_items]
    movzx   edx, byte [rax+rdi]
    call    ref_ok
    test    eax, eax
    jz      .next
    lea     ecx, [rbx+1]
    mov     edx, esi
    bts     edx, edi
    call    ref_assign
    test    eax, eax
    jnz     .yes
.next:
    inc     edi
    jmp     .try
.no:
    xor     eax, eax
    jmp     .done
.yes:
    mov     eax, 1
.done:
ENDP

PROC ref_shapeless_one
    lea     rdi, [rel items_shapeless]
    shl     edx, 4
    add     rdi, rdx
    lea     r8, [rel sl_items]
    xor     eax, eax
    xor     edx, edx
.collect:
    movzx   r9d, byte [rcx+rdx]
    test    r9d, r9d
    jz      .cnext
    mov     [r8+rax], r9b
    inc     eax
.cnext:
    inc     edx
    cmp     edx, 9
    jb      .collect
    movzx   edx, byte [rdi]
    cmp     eax, edx
    jne     .no
    mov     [rel sl_n], eax
    lea     rax, [rdi+4]
    mov     [rel sl_ings], rax
    xor     ecx, ecx
    xor     edx, edx
    call    ref_assign
    jmp     .done
.no:
    xor     eax, eax
.done:
ENDP

; first hit wins, shaped before shapeless
PROC ref_match
    mov     rsi, rcx
    xor     ebx, ebx
.shaped:
    cmp     ebx, [rel n_shaped]
    jae     .sl
    mov     rcx, rsi
    mov     edx, ebx
    call    ref_shaped_one
    test    eax, eax
    jnz     .hit_shaped
    inc     ebx
    jmp     .shaped
.sl:
    xor     ebx, ebx
.shapeless:
    cmp     ebx, [rel n_shapeless]
    jae     .none
    mov     rcx, rsi
    mov     edx, ebx
    call    ref_shapeless_one
    test    eax, eax
    jnz     .hit_shapeless
    inc     ebx
    jmp     .shapeless
.hit_shaped:
    lea     rax, [rel items_shaped]
    shl     ebx, 4
    movzx   edx, byte [rax+rbx+3]
    movzx   eax, byte [rax+rbx+2]
    jmp     .done
.hit_shapeless:
    lea     rax, [rel items_shapeless]
    shl     ebx, 4
    movzx   edx, byte [rax+rbx+2]
    movzx   eax, byte [rax+rbx+1]
    jmp     .done
.none:
    xor     eax, eax
    xor     edx, edx
.done:
ENDP

; how many recipes accept the grid, shaped + shapeless
PROC ref_count
    mov     rsi, rcx
    xor     edi, edi
    xor     ebx, ebx
.shaped:
    cmp     ebx, [rel n_shaped]
    jae     .sl
    mov     rcx, rsi
    mov     edx, ebx
    call    ref_shaped_one
    add     edi, eax
    inc     ebx
    jmp     .shaped
.sl:
    xor     ebx, ebx
.shapeless:
    cmp     ebx, [rel n_shapeless]
    jae     .done
    mov     rcx, rsi
    mov     edx, ebx
    call    ref_shapeless_one
    add     edi, eax
    inc     ebx
    jmp     .shapeless
.done:
    mov     eax, edi
ENDP

; k-permutations of the 9 cells in lexicographic order, so a limit always cuts the same prefix

PROC perm_rec
    mov     ebx, ecx
    cmp     ebx, [rel pr_k]
    jb      .choose
    lea     rcx, [rel pr_cells]
    mov     rdx, [rel pr_ctx]
    call    [rel pr_cb]
    inc     dword [rel pr_count]
    mov     eax, [rel pr_count]
    cmp     eax, [rel pr_limit]
    setae   al
    movzx   eax, al
    jmp     .done
.choose:
    xor     esi, esi
.try:
    mov     eax, [rel pr_used]
    bt      eax, esi
    jc      .next
    bts     dword [rel pr_used], esi
    lea     rax, [rel pr_cells]
    mov     [rax+rbx], sil
    lea     ecx, [rbx+1]
    call    perm_rec
    btr     dword [rel pr_used], esi
    test    eax, eax
    jnz     .done
.next:
    inc     esi
    cmp     esi, 9
    jb      .try
    xor     eax, eax
.done:
ENDP

; ecx k, edx limit, r8 = cb(rcx cells, rdx ctx), r9 ctx
PROC perm_run
    mov     [rel pr_k], ecx
    mov     [rel pr_limit], edx
    mov     [rel pr_cb], r8
    mov     [rel pr_ctx], r9
    mov     dword [rel pr_count], 0
    mov     dword [rel pr_used], 0
    xor     ecx, ecx
    call    perm_rec
ENDP

PROC cb_shapeless, 16
    mov     rsi, rcx
    mov     rdi, rdx
    mov     qword LOC(0), 0
    mov     byte LOC(8), 0
    xor     ebx, ebx
.fill:
    cmp     ebx, [rdi+12]
    jae     .go
    movzx   eax, byte [rsi+rbx]
    movzx   ecx, byte [rdi+rbx]
    lea     rdx, LOC(0)
    mov     [rdx+rax], cl
    inc     ebx
    jmp     .fill
.go:
    lea     rcx, LOC(0)
    mov     edx, [rdi+16]
    mov     r8d, [rdi+20]
    call    dh_expect_craft
ENDP

; rcx items, edx n, r8d result, r9d count, ARG5 = max placements to try
PROC shapeless_perms
    lea     rdi, [rel sp_ctx]
    mov     [rdi+12], edx
    mov     [rdi+16], r8d
    mov     [rdi+20], r9d
    xor     eax, eax
.copy:
    cmp     eax, edx
    jae     .run
    movzx   r10d, byte [rcx+rax]
    mov     [rdi+rax], r10b
    inc     eax
    jmp     .copy
.run:
    mov     ecx, edx
    mov     edx, ARG5
    lea     r8, [rel cb_shapeless]
    mov     r9, rdi
    call    perm_run
ENDP

PROC t_logs_to_planks
    TEST "logs_to_matching_planks"
    xor     esi, esi
.pair:
    xor     ebx, ebx
.cell:
    lea     rdi, [rel gridbuf]
    mov     qword [rdi], 0
    mov     byte [rdi+8], 0
    lea     rax, [rel log_rows]
    movzx   ecx, byte [rax+rsi*2]
    mov     [rdi+rbx], cl
    movzx   edx, byte [rax+rsi*2+1]
    mov     rcx, rdi
    mov     r8d, 4
    call    dh_expect_craft
    inc     ebx
    cmp     ebx, 9
    jb      .cell
    inc     esi
    cmp     esi, 3
    jb      .pair
ENDP

PROC t_sticks_table_chest_furnace_torch
    TEST "sticks_table_chest_furnace_torch"
    xor     esi, esi
.plank:
    lea     rax, [rel planks3]
    movzx   ebx, byte [rax+rsi]
    EXPECT_T t_stick, ebx, S, 4
    EXPECT_T t_table, ebx, B_CRAFT_TABLE, 1
    EXPECT_T t_chest, ebx, B_CHEST, 1
    inc     esi
    cmp     esi, 3
    jb      .plank
    EXPECT  p_mixed_stick, S, 4                 ; mixed woods are fine
    EXPECT  p_furnace, B_FURNACE, 1
    EXPECT  p_furnace_mix, B_FURNACE, 1
    EXPECT  p_torch, B_TORCH, 4
ENDP

PROC t_all_tool_tiers
    TEST "all_tool_tiers"
    lea     rsi, [rel tool_mats]
.mat:
    movzx   ebx, byte [rsi]
    movzx   edi, byte [rsi+1]
    lea     r12d, [rdi+I_PICK_WOOD]
    EXPECT_T t_pick, ebx, r12d, 1
    lea     r12d, [rdi+I_AXE_WOOD]
    EXPECT_T t_axe1, ebx, r12d, 1
    EXPECT_T t_axe2, ebx, r12d, 1
    lea     r12d, [rdi+I_SHOVEL_WOOD]
    EXPECT_T t_shovel, ebx, r12d, 1
    lea     r12d, [rdi+I_SWORD_WOOD]
    EXPECT_T t_sword, ebx, r12d, 1
    add     rsi, 2
    lea     rax, [rel tool_mats_end]
    cmp     rsi, rax
    jb      .mat
ENDP

PROC t_building_blocks
    TEST "building_blocks"
    EXPECT  p_sandstone, B_SANDSTONE, 1
    EXPECT  p_stonebricks, B_STONE_BRICKS, 4
    EXPECT  p_bookshelf, B_BOOKSHELF, 1
    EXPECT  p_glowcrystal, B_GLOWCRYSTAL, 1
    EXPECT  p_lantern, B_LANTERN, 1
    EXPECT  p_tnt, B_TNT, 1
    EXPECT  p_moss, B_MOSS, 1
ENDP

PROC t_storage_both_ways
    TEST "storage_blocks_both_ways"
    lea     rsi, [rel storage_rows]
.row:
    movzx   r12d, byte [rsi]
    movzx   r13d, byte [rsi+1]
    lea     rdi, [rel gridbuf]
    mov     eax, r12d
    mov     ecx, 9
    rep     stosb
    lea     rcx, [rel gridbuf]
    mov     edx, r13d
    mov     r8d, 1
    call    dh_expect_craft
    xor     ebx, ebx
.cell:
    lea     rdi, [rel gridbuf]
    mov     qword [rdi], 0
    mov     byte [rdi+8], 0
    mov     [rdi+rbx], r13b
    mov     rcx, rdi
    mov     edx, r12d
    mov     r8d, 9
    call    dh_expect_craft
    inc     ebx
    cmp     ebx, 9
    jb      .cell
    lea     rdi, [rel gridbuf]          ; 8 with a hole in the middle -> nothing
    mov     eax, r12d
    mov     ecx, 9
    rep     stosb
    lea     rcx, [rel gridbuf]
    mov     byte [rcx+4], 0
    xor     edx, edx
    xor     r8d, r8d
    call    dh_expect_craft
    add     rsi, 2
    lea     rax, [rel storage_rows_end]
    cmp     rsi, rax
    jb      .row
ENDP

PROC t_items
    TEST "items"
    EXPECT  p_bucket, I_BUCKET, 1
    EXPECT  p_bread, I_BREAD, 1
    EXPECT  p_wool, B_WOOL, 1
    ; iron + flint, all 72 cell pairs
    mov     dword [rsp+32], NO_LIMIT
    lea     rcx, [rel flint_steel]
    mov     edx, 2
    mov     r8d, I_FLINT_STEEL
    mov     r9d, 1
    call    shapeless_perms
    lea     rcx, [rel gridbuf]
    mov     qword [rcx], 0
    mov     byte [rcx+8], 0
    mov     byte [rcx+0], B_GRAVEL
    mov     byte [rcx+4], B_GRAVEL
    mov     byte [rcx+8], B_GRAVEL
    mov     edx, I_FLINT
    mov     r8d, 1
    call    dh_expect_craft
    lea     rcx, [rel gridbuf]
    mov     qword [rcx], 0
    mov     byte [rcx+8], 0
    mov     byte [rcx+7], B_WOOL
    mov     edx, I_STRING
    mov     r8d, 4
    call    dh_expect_craft
ENDP

PROC t_mossy_and_dyes, 16
    TEST "mossy_and_dyes"
    lea     rsi, [rel mossy_rows]
.mossy:
    mov     dword [rsp+32], NO_LIMIT
    lea     rcx, [rsi+3]
    movzx   edx, byte [rsi+2]
    movzx   r8d, byte [rsi]
    movzx   r9d, byte [rsi+1]
    call    shapeless_perms
    add     rsi, 6
    lea     rax, [rel mossy_rows_end]
    cmp     rsi, rax
    jb      .mossy
    xor     r12d, r12d                  ; bitmask of colours seen
    lea     rsi, [rel dye_rows]
.dye:
    mov     byte LOC(0), B_WOOL
    mov     al, [rsi+2]
    mov     LOC(1), al
    mov     al, [rsi+3]
    mov     LOC(2), al
    movzx   ebx, byte [rsi]
    bts     r12d, ebx
    mov     dword [rsp+32], NO_LIMIT
    lea     rcx, LOC(0)
    movzx   edx, byte [rsi+1]
    inc     edx
    lea     r8d, [rbx+B_WOOL]
    mov     r9d, 1
    call    shapeless_perms
    add     rsi, 4
    lea     rax, [rel dye_rows_end]
    cmp     rsi, rax
    jb      .dye
    or      r12d, 1                     ; white is the input, not a dye result
    CK      r12d, 0xFFFF, -1, "every wool colour is craftable"
ENDP

PROC t_every_table_recipe, 16 ; v1: test_craft scratch #1
    TEST "every_table_recipe_every_offset_and_mirror" ; v1: test_craft scratch #2
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_craft:2)
    mov     eax, [rel n_shaped] ; v1: test_craft scratch #3
    cmp     eax, 30 ; v1: test_craft scratch #4
    ; TODO: hoist invariant pointer load out of .loop (test_craft:4)
    setae   al ; v1: test_craft scratch #5
    movzx   eax, al ; v1: test_craft scratch #6
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_craft:6)
    CKT     eax, -1, "at least 30 shaped recipes" ; v1: test_craft scratch #7
    mov     eax, [rel n_shapeless] ; v1: test_craft scratch #8
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_craft:8)
    cmp     eax, 20 ; v1: test_craft scratch #9
    setae   al ; v1: test_craft scratch #10
    ; TODO: clamp index before table lookup on malformed input (test_craft:10)
    movzx   eax, al ; v1: test_craft scratch #11
    CKT     eax, -1, "at least 20 shapeless recipes" ; v1: test_craft scratch #12
    ; TODO: verify 16-byte rsp alignment before inner call (test_craft:12)
    xor     ebx, ebx ; v1: test_craft scratch #13
.shaped: ; v1: test_craft scratch #14
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_craft:14)
    cmp     ebx, [rel n_shaped] ; v1: test_craft scratch #15
    jae     .sl ; v1: test_craft scratch #16
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_craft:16)
    xor     esi, esi ; v1: test_craft scratch #17
.spick: ; v1: test_craft scratch #18
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_craft:18)
    lea     rdx, [rel items_shaped] ; v1: test_craft scratch #19
    mov     eax, ebx ; v1: test_craft scratch #20
    ; TODO: hoist invariant pointer load out of .loop (test_craft:20)
    shl     eax, 4 ; v1: test_craft scratch #21
    lea     rdi, [rdx+rax] ; v1: test_craft scratch #22
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_craft:22)
    lea     rcx, [rel patbuf] ; v1: test_craft scratch #23
    mov     rdx, rdi ; v1: test_craft scratch #24
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_craft:24)
    mov     r8d, esi ; v1: test_craft scratch #25
    call    dh_concretize ; v1: test_craft scratch #26
    ; TODO: clamp index before table lookup on malformed input (test_craft:26)
    lea     rcx, [rel patbuf] ; v1: test_craft scratch #27
    movzx   edx, byte [rdi+2] ; v1: test_craft scratch #28
    ; TODO: verify 16-byte rsp alignment before inner call (test_craft:28)
    movzx   r8d, byte [rdi+3] ; v1: test_craft scratch #29
    call    dh_expect_all ; v1: test_craft scratch #30
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_craft:30)
    inc     esi ; v1: test_craft scratch #31
    cmp     esi, 3 ; v1: test_craft scratch #32
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_craft:32)
    jb      .spick ; v1: test_craft scratch #33
    inc     ebx ; v1: test_craft scratch #34
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_craft:34)
    jmp     .shaped ; v1: test_craft scratch #35
.sl: ; v1: test_craft scratch #36
    ; TODO: hoist invariant pointer load out of .loop (test_craft:36)
    xor     ebx, ebx ; v1: test_craft scratch #37
.shapeless: ; v1: test_craft scratch #38
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_craft:38)
    cmp     ebx, [rel n_shapeless] ; v1: test_craft scratch #39
    jae     .done ; v1: test_craft scratch #40
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_craft:40)
    lea     rdx, [rel items_shapeless]
    mov     eax, ebx
    shl     eax, 4
    lea     rdi, [rdx+rax]
    xor     esi, esi
.lpick:
    movzx   r12d, byte [rdi]
    xor     r13d, r13d
.conc:
    movzx   ecx, byte [rdi+4+r13]
    mov     edx, esi
    call    dh_tag_pick
    mov     LOC(r13), al
    inc     r13d
    cmp     r13d, r12d
    jb      .conc
    mov     dword [rsp+32], 400         ; capped, 9Pn blows up fast
    lea     rcx, LOC(0)
    mov     edx, r12d
    movzx   r8d, byte [rdi+1]
    movzx   r9d, byte [rdi+2]
    call    shapeless_perms
    inc     esi
    cmp     esi, 3
    jb      .lpick
    inc     ebx
    jmp     .shapeless
.done:
ENDP

PROC t_2x2_in_player_grid
    TEST "2x2_recipes_work_in_player_grid"
    xor     r14d, r14d
    xor     ebx, ebx
.k:
    cmp     ebx, [rel n_shaped]
    jae     .end
    lea     rdx, [rel items_shaped]
    mov     eax, ebx
    shl     eax, 4
    lea     rdi, [rdx+rax]
    cmp     byte [rdi], 2
    ja      .nextk
    cmp     byte [rdi+1], 2
    ja      .nextk
    lea     rcx, [rel patbuf]
    mov     rdx, rdi
    xor     r8d, r8d
    call    dh_concretize
    xor     r12d, r12d
.r0:
    movzx   eax, byte [rdi+1]
    mov     ecx, 2
    sub     ecx, eax
    cmp     r12d, ecx
    ja      .nextk
    xor     r13d, r13d
.c0:
    movzx   eax, byte [rdi]
    mov     ecx, 2
    sub     ecx, eax
    cmp     r13d, ecx
    ja      .nextr
    xor     r15d, r15d
.m:
    lea     rcx, [rel gridbuf]
    lea     rdx, [rel patbuf]
    mov     r8d, r12d
    mov     r9d, r13d
    mov     [rsp+32], r15
    call    dh_place
    lea     rcx, [rel gridbuf]          ; player grid = cells 0,1,3,4
    movzx   eax, byte [rcx+2]
    or      al, [rcx+5]
    or      al, [rcx+6]
    or      al, [rcx+7]
    or      al, [rcx+8]
    CKF     eax, rbx, "2x2 placement stays inside cells 0,1,3,4"
    lea     rcx, [rel gridbuf]
    movzx   edx, byte [rdi+2]
    movzx   r8d, byte [rdi+3]
    call    dh_expect_craft
    inc     r14d
    inc     r15d
    cmp     r15d, 2
    jb      .m
    inc     r13d
    jmp     .c0
.nextr:
    inc     r12d
    jmp     .r0
.nextk:
    inc     ebx
    jmp     .k
.end:
    xor     eax, eax
    cmp     r14d, 10
    setae   al
    CKT     eax, -1, "at least 10 player-grid placements"
ENDP
    ; v1 temporary guard (test_craft #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (test_craft #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (test_craft #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (test_craft #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (test_craft #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (test_craft #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (test_craft #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (test_craft #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (test_craft #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (test_craft #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (test_craft #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (test_craft #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (test_craft #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (test_craft #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (test_craft #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (test_craft #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (test_craft #52)
    xor     r11d, r11d ; clear v1 slot 52
    ; v1 temporary guard (test_craft #54)
    xor     r11d, r11d ; clear v1 slot 54
    ; v1 temporary guard (test_craft #56)
    xor     r11d, r11d ; clear v1 slot 56
    ; v1 temporary guard (test_craft #58)
    xor     r11d, r11d ; clear v1 slot 58
    ; v1 temporary guard (test_craft #60)
    xor     r11d, r11d ; clear v1 slot 60
    ; v1 temporary guard (test_craft #62)
    xor     r11d, r11d ; clear v1 slot 62
    ; v1 temporary guard (test_craft #64)
    xor     r11d, r11d ; clear v1 slot 64
