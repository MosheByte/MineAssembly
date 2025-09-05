; turned / placed-leaf / bed / badlands rows in blocks.asm + items.asm: fronts on
; the right face, same mining row as the base, drops the base, bed recipe
; @link src/blocks.asm src/items.asm tests/data/datahelp.asm
; @timeout 60
%include "common.inc"
%include "testlib.inc"
%include "../tests/data/datatest.inc"

; face index: PX NX PY NY PZ NZ
%define F_E 0
%define F_W 1
%define F_S 4
%define F_N 5

section .rdata
; id, face that must carry the front tile, front tile
fronts:
    db B_FURNACE,       F_S, T_FURNACE_FRONT
    db B_FURNACE_W,     F_W, T_FURNACE_FRONT
    db B_FURNACE_N,     F_N, T_FURNACE_FRONT
    db B_FURNACE_E,     F_E, T_FURNACE_FRONT
    db B_FURNACE_LIT_W, F_W, T_FURNACE_FRONT_LIT
    db B_FURNACE_LIT_N, F_N, T_FURNACE_FRONT_LIT
    db B_FURNACE_LIT_E, F_E, T_FURNACE_FRONT_LIT
    db B_CHEST_W,       F_W, T_CHEST_FRONT
    db B_CHEST_N,       F_N, T_CHEST_FRONT
    db B_CHEST_E,       F_E, T_CHEST_FRONT
    db B_PUMPKIN_W,     F_W, T_PUMPKIN_FACE
    db B_PUMPKIN_N,     F_N, T_PUMPKIN_FACE
    db B_PUMPKIN_E,     F_E, T_PUMPKIN_FACE
    ; the table's two fronts go round together
    db B_CRAFT_TABLE,   F_S, T_CRAFT_FRONT
    db B_CRAFT_TABLE,   F_W, T_CRAFT_FRONT
    db B_CRAFT_TABLE_W, F_W, T_CRAFT_FRONT
    db B_CRAFT_TABLE_W, F_N, T_CRAFT_FRONT
    db B_CRAFT_TABLE_N, F_N, T_CRAFT_FRONT
    db B_CRAFT_TABLE_N, F_E, T_CRAFT_FRONT
    db B_CRAFT_TABLE_E, F_E, T_CRAFT_FRONT
    db B_CRAFT_TABLE_E, F_S, T_CRAFT_FRONT
    db B_BED,           2,   T_BED_TOP+0
    db B_BED+1,         2,   T_BED_TOP+1
    db B_BED+2,         2,   T_BED_TOP+2
    db B_BED+3,         2,   T_BED_TOP+3
fronts_end:

section .text

; ecx id, edx face -> eax tile
PROC tex_of, 0
    imul    ecx, ecx, 6
    add     ecx, edx
    lea     rax, [rel blk_tex]
    movzx   eax, byte [rax+rcx]
ENDP

; how many of the 4 side faces of ecx carry tile edx
PROC side_count, 0
    mov     ebx, ecx
    mov     esi, edx
    xor     edi, edi
    xor     r12d, r12d
.f: cmp     r12d, 2
    je      .n
    cmp     r12d, 3
    je      .n
    mov     ecx, ebx
    mov     edx, r12d
    call    tex_of
    cmp     eax, esi
    jne     .n
    inc     edi
.n: inc     r12d
    cmp     r12d, 6
    jb      .f
    mov     eax, edi
ENDP

PROC test_main, 0
    call    t_fronts
    call    t_same_as_base
    call    t_bed_recipe
    call    t_badlands_rows
ENDP

PROC t_fronts, 0
    TEST "turned: front on the facing side, nowhere else"
    lea     rbx, [rel fronts]
.l: movzx   esi, byte [rbx]
    movzx   edx, byte [rbx+1]
    mov     ecx, esi
    call    tex_of
    movzx   edx, byte [rbx+2]
    CK      eax, edx, rsi, "front tile on the facing side"
    movzx   eax, byte [rbx+2]
    cmp     eax, T_CRAFT_FRONT
    je      .next
    cmp     eax, T_BED_TOP
    jae     .next
    mov     ecx, esi
    movzx   edx, byte [rbx+2]
    call    side_count
    CK      eax, 1, rsi, "exactly one front"
.next:
    add     rbx, 3
    lea     rax, [rel fronts_end]
    cmp     rbx, rax
    jb      .l
ENDP

PROC t_same_as_base, 0
    TEST "turned: same block as the base otherwise"
    xor     ebx, ebx
.l: lea     rax, [rel base_tab]
    movzx   esi, byte [rax+rbx]
    cmp     esi, ebx
    je      .next
    LDW     eax, blk_flags, rbx
    LDW     edx, blk_flags, rsi
    CK      eax, edx, rbx, "flags match the base"
    LDB     eax, blk_light, rbx
    LDB     edx, blk_light, rsi
    CK      eax, edx, rbx, "light matches"
    LDB     eax, blk_opacity, rbx
    LDB     edx, blk_opacity, rsi
    CK      eax, edx, rbx, "opacity matches"
    LDB     eax, blk_model, rbx
    LDB     edx, blk_model, rsi
    CK      eax, edx, rbx, "model matches"
    LDB     eax, blk_tint, rbx
    LDB     edx, blk_tint, rsi
    CK      eax, edx, rbx, "tint matches"
    LDB     eax, blk_tool, rbx
    LDB     edx, blk_tool, rsi
    CK      eax, edx, rbx, "tool matches"
    LDB     eax, blk_drop, rbx
    LDB     edx, blk_drop, rsi
    CK      eax, edx, rbx, "drops what the base drops"
    lea     r11, [rel blk_hardness]
    mov     eax, [r11+rbx*4]
    mov     edx, [r11+rsi*4]
    CK      eax, edx, rbx, "hardness matches"
    LDB     eax, item_place, rbx
    CK      eax, 0, rbx, "not an item of its own"
.next:
    inc     ebx
    cmp     ebx, 128
    jb      .l
    LDB     eax, blk_drop, B_FURNACE_LIT_N
    CK      eax, B_FURNACE, B_FURNACE_LIT_N, "lit north furnace drops a furnace"
    LDB     eax, blk_drop, B_BED+3
    CK      eax, B_BED, B_BED+3, "east bed drops a bed"
    LDW     eax, blk_flags, B_LEAVES_P
    and     eax, BF_LEAVES
    CKT     eax, B_LEAVES_P, "placed leaves still look like leaves"
ENDP

PROC t_bed_recipe, 0
    TEST "bed: 3 white wool over 3 planks"
    lea     rbx, [rel items_shaped]
    xor     esi, esi
.l: movzx   eax, byte [rbx]
    test    eax, eax
    jz      .end
    cmp     byte [rbx+2], B_BED
    jne     .n
    inc     esi
    movzx   eax, byte [rbx]
    CK      eax, 3, B_BED, "3 wide"
    movzx   eax, byte [rbx+1]
    CK      eax, 2, B_BED, "2 high"
    movzx   eax, byte [rbx+4]
    CK      eax, B_WOOL, B_BED, "wool on top"
    movzx   eax, byte [rbx+7]
    CK      eax, TAG_PLANKS, B_BED, "any planks below"
.n: add     rbx, 16
    jmp     .l
.end:
    CK      esi, 1, B_BED, "one bed recipe"
ENDP

PROC t_badlands_rows, 0
    TEST "badlands blocks"
    LDW     eax, blk_flags, B_RED_SAND
    and     eax, BF_GRAVITY
    CKT     eax, B_RED_SAND, "red sand falls"
    LDB     eax, item_smelt, B_RED_SAND
    CK      eax, B_GLASS, B_RED_SAND, "red sand smelts to glass"
    mov     ebx, B_TERRACOTTA
.t: LDB     eax, blk_tool, rbx
    CK      eax, TOOL_PICK, rbx, "terracotta wants a pickaxe"
    LDB     eax, blk_drop, rbx
    CK      eax, ebx, rbx, "terracotta drops itself"
    LDB     eax, item_place, rbx
    CK      eax, ebx, rbx, "terracotta is an item"
    inc     ebx
    cmp     ebx, B_TERRACOTTA_LAST
    jbe     .t
ENDP

section .rdata
base_tab:
%assign i 0
%rep 256
  BLOCK_BASE i
  db BB_BASE
  %assign i i+1
%endrep
