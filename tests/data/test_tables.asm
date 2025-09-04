; block/item property tables: spec values + invariants over all 256 ids
; @link src/blocks.asm src/items.asm tests/data/datahelp.asm
; @timeout 60
%include "common.inc"
%include "testlib.inc"
%include "../tests/data/datatest.inc"

section .rdata
s_unknown:      db "Unknown", 0
s_wool_sfx:     db " Wool", 0
s_flow_water:   db "Flowing Water", 0
s_flow_lava:    db "Flowing Lava", 0

; every B_* in ids.inc except the *_LAST markers. add new blocks here
all_block_ids:
    db B_AIR, B_STONE, B_GRASS, B_DIRT, B_COBBLE, B_PLANKS, B_BEDROCK, B_SAND
    db B_GRAVEL, B_LOG, B_LEAVES, B_GLASS, B_COAL_ORE, B_IRON_ORE, B_GOLD_ORE
    db B_DIAMOND_ORE, B_SANDSTONE, B_SNOW, B_ICE, B_CACTUS, B_CLAY, B_BIRCH_LOG
    db B_BIRCH_LEAVES, B_PINE_LOG, B_PINE_LEAVES, B_BRICKS, B_STONE_BRICKS
    db B_MOSSY_COBBLE, B_BOOKSHELF, B_CRAFT_TABLE, B_FURNACE, B_TNT
    db B_GLOWCRYSTAL, B_OBSIDIAN, B_TORCH, B_TALL_GRASS, B_FLOWER_RED
    db B_FLOWER_YELLOW, B_MUSHROOM_RED, B_MUSHROOM_BROWN, B_DEAD_BUSH, B_REEDS
    db B_PUMPKIN, B_MELON, B_WOOL, B_GOLD_BLOCK, B_IRON_BLOCK, B_DIAMOND_BLOCK
    db B_COAL_BLOCK, B_SNOWY_GRASS, B_SAPLING, B_CHEST, B_LANTERN, B_FURNACE_LIT
    db B_PINE_PLANKS, B_BIRCH_PLANKS, B_MOSS, B_FARMLAND, B_WATER, B_WATER_FLOW
    db B_LAVA, B_LAVA_FLOW
    db B_FURNACE_W, B_FURNACE_N, B_FURNACE_E, B_FURNACE_LIT_W, B_FURNACE_LIT_N
    db B_FURNACE_LIT_E, B_CHEST_W, B_CHEST_N, B_CHEST_E, B_CRAFT_TABLE_W
    db B_CRAFT_TABLE_N, B_CRAFT_TABLE_E, B_PUMPKIN_W, B_PUMPKIN_N, B_PUMPKIN_E
    db B_LEAVES_P, B_BIRCH_LEAVES_P, B_PINE_LEAVES_P, B_BED, B_BED+1, B_BED+2
    db B_BED+3, B_RED_SAND, B_TERRACOTTA, B_TERRACOTTA+1, B_TERRACOTTA+2
    db B_TERRACOTTA+3, B_TERRACOTTA+4, B_TERRACOTTA+5
all_block_ids_end:

; 1 = id whose BLOCK_BASE is something else (turned, placed leaves)
world_only:
%assign i 0
%rep 256
  BLOCK_BASE i
  %if BB_BASE != i
    db 1
  %else
    db 0
  %endif
  %assign i i+1
%endrep

; trademarked words, lowercase for dh_contains_ci
banned:
    db "creeper", 0, "steve", 0, "nether", 0, "redstone", 0, "minecraft", 0
    db "mojang", 0, "enderman", 0, "glowstone", 0, 0

; id, seconds with a tool that can harvest it, speed 1
hardness_rows:
    dd B_DIRT, 0.75,  B_STONE, 2.25,  B_COBBLE, 3.0,  B_LOG, 3.0,  B_LEAVES, 0.35
    dd B_GLASS, 0.45,  B_TORCH, 0.0,  B_TALL_GRASS, 0.0,  B_OBSIDIAN, 75.0
    dd B_COAL_ORE, 4.5,  B_IRON_ORE, 4.5,  B_GOLD_ORE, 4.5,  B_DIAMOND_ORE, 4.5
    dd B_SANDSTONE, 1.2,  B_BRICKS, 3.0,  B_STONE_BRICKS, 2.25,  B_MOSSY_COBBLE, 3.0
    dd B_FURNACE, 5.25,  B_FURNACE_LIT, 5.25,  B_LANTERN, 5.25,  B_GOLD_BLOCK, 4.5
    dd B_IRON_BLOCK, 7.5,  B_DIAMOND_BLOCK, 7.5,  B_COAL_BLOCK, 7.5
hardness_rows_end:

; block, speed, can harvest, seconds
breaktime_rows:
    dd B_STONE,       1.0, 0, 7.5
    dd B_STONE,       2.0, 1, 1.125
    dd B_IRON_ORE,    2.0, 0, 7.5
    dd B_DIAMOND_ORE, 6.0, 1, 0.75
    dd B_OBSIDIAN,    8.0, 1, 9.375
breaktime_rows_end:

; 0xFF = no tier needed
tier_rows:
    db B_STONE, 0, B_COBBLE, 0, B_COAL_ORE, 0, B_IRON_ORE, 1, B_GOLD_ORE, 2
    db B_DIAMOND_ORE, 2, B_OBSIDIAN, 3, B_DIRT, 0xFF, B_LOG, 0xFF
tier_rows_end:

; block, drop, count
drop_rows:
    db B_STONE, B_COBBLE, 1,  B_GRASS, B_DIRT, 1,  B_COAL_ORE, I_COAL, 1
    db B_DIAMOND_ORE, I_DIAMOND, 1,  B_IRON_ORE, B_IRON_ORE, 1
    db B_GOLD_ORE, B_GOLD_ORE, 1,  B_FURNACE_LIT, B_FURNACE, 1
    db B_SNOWY_GRASS, B_DIRT, 1
drop_rows_end:
no_drop:
    db B_LEAVES, B_BIRCH_LEAVES, B_PINE_LEAVES, B_GLASS, B_TALL_GRASS, B_ICE
    db B_BEDROCK, B_AIR, B_WATER, B_LAVA
no_drop_end:

sound_rows:
    db B_STONE, SND_STONE, B_DIRT, SND_DIRT, B_GRASS, SND_GRASS, B_PLANKS, SND_WOOD
    db B_SAND, SND_SAND, B_GRAVEL, SND_GRAVEL, B_GLASS, SND_GLASS, B_SNOW, SND_SNOW
    db B_WOOL, SND_WOOL
sound_rows_end:

sprite_rows:
    db B_TORCH, T_TORCH, B_SAPLING, T_SAPLING, B_REEDS, T_REEDS
    db B_TALL_GRASS, T_TALL_GRASS, B_FLOWER_RED, T_FLOWER_RED
sprite_rows_end:

; wood id, kind, icon, attack per tier. 7 B rows
tool_rows:
    db I_PICK_WOOD,   TOOL_PICK,   T_PICK,   2, 3, 4, 5
    db I_AXE_WOOD,    TOOL_AXE,    T_AXE,    3, 4, 5, 6
    db I_SHOVEL_WOOD, TOOL_SHOVEL, T_SHOVEL, 1, 2, 3, 4
    db I_SWORD_WOOD,  TOOL_SWORD,  T_SWORD,  4, 5, 6, 7
tool_rows_end:
tool_dur:       dw 59, 131, 250, 1561
tool_spd:       dd 2.0, 4.0, 6.0, 8.0

stack1_ids:     db I_BUCKET, I_WATER_BUCKET, I_LAVA_BUCKET, I_FLINT_STEEL
stack64_ids:    db I_STICK, I_APPLE, B_STONE, I_COOKED_MEAT
; anything not listed must have food 0
food_rows:
    db I_APPLE, 4, I_RAW_MEAT, 3, I_COOKED_MEAT, 8, I_ROTTEN_FLESH, 4, I_BREAD, 5
food_rows_end:
; id, ticks (dw)
fuel_rows:
    dw B_PLANKS, 300, B_LOG, 300, B_PINE_LOG, 300, B_BIRCH_PLANKS, 300, I_STICK, 100
    dw I_COAL, 1600, B_COAL_BLOCK, 16000, I_LAVA_BUCKET, 20000, B_SAPLING, 100
    dw I_PICK_WOOD, 200, I_SWORD_WOOD, 200, B_STONE, 0, I_IRON_INGOT, 0
fuel_rows_end:
smelt_rows:
    db B_IRON_ORE, I_IRON_INGOT, B_GOLD_ORE, I_GOLD_INGOT, B_SAND, B_GLASS
    db B_COBBLE, B_STONE, I_RAW_MEAT, I_COOKED_MEAT, B_CLAY, B_BRICKS
    db B_LOG, I_COAL, B_BIRCH_LOG, I_COAL, B_PINE_LOG, I_COAL
smelt_rows_end:

section .bss
creative_seen:  resb 256

section .text

PROC test_main
    call    t_audits
    call    t_block_ids_described
    call    t_item_ids_described
    call    t_unused_ids_air_like
    call    t_names_agree
    call    t_names_unique
    call    t_no_trademarks
    call    t_flag_profiles
    call    t_flag_invariants
    call    t_textures
    call    t_models_tints
    call    t_light_opacity
    call    t_hardness_tiers
    call    t_drops
    call    t_sound_resistance
    call    t_placeable
    call    t_icons
    call    t_tools
    call    t_stacks_food_fuel_smelt
    call    t_creative_list
    call    t_find_by_name
    call    t_find_trailing_separators
ENDP

PROC t_audits
    TEST "runtime_audits_clean"
    call    blocks_init
    CK      eax, 0, -1, "blocks_init audit finds no problems"
    call    items_init
    CK      eax, 0, -1, "items_init audit finds no problems"
ENDP

PROC t_block_ids_described
    TEST "every_block_id_from_ids_inc_is_described"
    lea     rsi, [rel all_block_ids]
.ids:
    movzx   ebx, byte [rsi]
    LDB     eax, blocks_defined, rbx
    CKT     eax, rbx, "blocks_defined[id] for an ids.inc block"
    LDQ     rcx, blk_name, rbx
    lea     rdx, [rel s_unknown]
    call    dh_streq
    CKF     eax, rbx, "blk_name of an ids.inc block is not Unknown"
    inc     rsi
    lea     rax, [rel all_block_ids_end]
    cmp     rsi, rax
    jb      .ids
    mov     ebx, B_WOOL
.wool:
    LDQ     rcx, blk_name, rbx
    lea     rdx, [rel s_wool_sfx]
    call    dh_ends_with
    CKT     eax, rbx, "wool names end with ' Wool'"
    inc     ebx
    cmp     ebx, B_WOOL_LAST
    jbe     .wool
    mov     ebx, B_WATER
.liq:
    LDB     eax, blocks_defined, rbx
    CKT     eax, rbx, "every liquid level is a defined block"
    inc     ebx
    cmp     ebx, B_LAVA_LAST
    jbe     .liq
ENDP

PROC t_item_ids_described
    TEST "every_item_id_from_ids_inc_is_described"
    mov     ebx, ITEM_FIRST
.items:
    mov     ecx, ebx
    call    dh_valid_id
    CKT     eax, rbx, "ids.inc item has a name"
    inc     ebx
    cmp     ebx, ITEM_LAST
    jbe     .items
    xor     esi, esi                    ; valid ids >= 128. catches named items outside the ids.inc range
    mov     ebx, 128
.count:
    mov     ecx, ebx
    call    dh_valid_id
    add     esi, eax
    inc     ebx
    cmp     ebx, 256
    jb      .count
    CK      esi, ITEM_LAST-ITEM_FIRST+1, -1, "number of real items == ids.inc item range"
ENDP

PROC t_unused_ids_air_like
    TEST "unused_ids_are_air_like"
    xor     ebx, ebx
.loop:
    mov     ecx, ebx
    call    dh_valid_id
    test    eax, eax
    jnz     .next
    LDQ     rcx, blk_name, rbx
    lea     rdx, [rel s_unknown]
    call    dh_streq
    CKT     eax, rbx, "unused id: blk_name is Unknown"
    WEQ     blk_flags, rbx, 0, "unused id: flags 0"
    BEQ     blk_light, rbx, 0, "unused id: light 0"
    BEQ     blk_opacity, rbx, 0, "unused id: opacity 0"
    BEQ     blk_drop, rbx, 0, "unused id: drop 0"
    BEQ     blk_drop_count, rbx, 0, "unused id: drop count 0"
    BEQ     item_place, rbx, 0, "unused id: place 0"
    WEQ     item_fuel, rbx, 0, "unused id: fuel 0"
    BEQ     item_smelt, rbx, 0, "unused id: smelt 0"
    BEQ     item_food, rbx, 0, "unused id: food 0"
    BEQ     item_tool_kind, rbx, 0, "unused id: tool kind 0"
    BEQ     blk_tier, rbx, 0xFF, "unused id: blk_tier 0xFF"
    BEQ     item_tool_tier, rbx, 0xFF, "unused id: item_tool_tier 0xFF"
.next:
    inc     ebx
    cmp     ebx, 256
    jb      .loop
ENDP

PROC t_names_agree
    TEST "blk_name_and_item_name_agree"
    xor     ebx, ebx
.loop:
    LDQ     rcx, blk_name, rbx
    LDQ     rdx, item_name, rbx
    call    dh_streq
    CKT     eax, rbx, "blk_name[i] == item_name[i]"
    inc     ebx
    cmp     ebx, 256
    jb      .loop
ENDP

; flowing levels all share one name, they're the only allowed dupes
PROC is_flowing_name
    LDQ     rbx, item_name, rcx
    mov     rcx, rbx
    lea     rdx, [rel s_flow_water]
    call    dh_streq
    test    eax, eax
    jnz     .done
    mov     rcx, rbx
    lea     rdx, [rel s_flow_lava]
    call    dh_streq
.done:
ENDP

PROC t_names_unique
    TEST "names_unique_except_liquid_levels"
    xor     ebx, ebx
.outer:
    mov     ecx, ebx
    call    dh_valid_id
    test    eax, eax
    jz      .next
    mov     ecx, ebx
    call    is_flowing_name
    test    eax, eax
    jnz     .next
    xor     edi, edi                    ; dupes among j < i
    xor     esi, esi
.inner:
    cmp     esi, ebx
    jae     .check
    mov     ecx, esi
    call    dh_valid_id
    test    eax, eax
    jz      .inext
    mov     ecx, esi
    call    is_flowing_name
    test    eax, eax
    jnz     .inext
    LDQ     rcx, item_name, rsi
    LDQ     rdx, item_name, rbx
    call    dh_streq
    add     edi, eax
.inext:
    inc     esi
    jmp     .inner
.check:
    CK      edi, 0, rbx, "item name is unique"
.next:
    inc     ebx
    cmp     ebx, 256
    jb      .outer
    NAMEQ   1, "Stone", "id 1 is Stone"
    NAMEQ   2, "Grass Block", "id 2 is Grass Block"
    NAMEQ   32, "Glowcrystal", "id 32 is Glowcrystal"
ENDP

PROC t_no_trademarks
    TEST "no_trademarked_names"
    xor     ebx, ebx
.ids:
    lea     rsi, [rel banned]
.words:
    LDQ     rcx, item_name, rbx
    mov     rdx, rsi
    call    dh_contains_ci
    CKF     eax, rbx, "name contains a banned word"
.skip:
    inc     rsi
    cmp     byte [rsi-1], 0
    jne     .skip
    cmp     byte [rsi], 0
    jne     .words
    inc     ebx
    cmp     ebx, 256
    jb      .ids
ENDP

%define SOLID_OPAQUE_SEL (BF_SOLID|BF_OPAQUE|BF_SELECTABLE)
%define LEAF_FLAGS (BF_SOLID|BF_CUTOUT|BF_SELECTABLE|BF_LEAVES|BF_FLAMMABLE|BF_CULL_SAME)

PROC t_flag_profiles
    TEST "flag_profiles"
%macro SOLID_BLOCK 1.nolist 
    HAS     %1, SOLID_OPAQUE_SEL, "solid opaque selectable block"
    LACKS   %1, BF_CUTOUT|BF_TRANSLUCENT|BF_LIQUID|BF_REPLACEABLE, "plain block lacks cutout/translucent/liquid/replaceable"
%endmacro
    SOLID_BLOCK B_STONE
    SOLID_BLOCK B_DIRT
    SOLID_BLOCK B_COBBLE
    SOLID_BLOCK B_OBSIDIAN
    SOLID_BLOCK B_BRICKS
%macro LEAF_BLOCK 1.nolist 
    HAS     %1, LEAF_FLAGS, "leaves flags"
    LACKS   %1, BF_OPAQUE, "leaves are not opaque"
%endmacro
    LEAF_BLOCK B_LEAVES
    LEAF_BLOCK B_BIRCH_LEAVES
    LEAF_BLOCK B_PINE_LEAVES
    HAS     B_GLASS, BF_SOLID|BF_CUTOUT|BF_CULL_SAME|BF_SELECTABLE, "glass flags"
    LACKS   B_GLASS, BF_OPAQUE, "glass not opaque"
    HAS     B_ICE, BF_SOLID|BF_TRANSLUCENT|BF_SELECTABLE|BF_CULL_SAME, "ice flags"
    mov     ebx, B_WATER
.water:
    HAS     rbx, BF_LIQUID|BF_TRANSLUCENT|BF_REPLACEABLE|BF_CULL_SAME, "water flags"
    LACKS   rbx, BF_SOLID|BF_SELECTABLE|BF_OPAQUE, "water lacks solid/selectable/opaque"
    inc     ebx
    cmp     ebx, B_WATER_LAST
    jbe     .water
    mov     ebx, B_LAVA
.lava:
    HAS     rbx, BF_LIQUID|BF_REPLACEABLE|BF_CULL_SAME, "lava flags"
    LACKS   rbx, BF_SOLID|BF_SELECTABLE|BF_TRANSLUCENT|BF_OPAQUE, "lava lacks solid/selectable/translucent/opaque"
    inc     ebx
    cmp     ebx, B_LAVA_LAST
    jbe     .lava
    HAS     B_TALL_GRASS, BF_CUTOUT|BF_SUPPORT|BF_PLANT|BF_SELECTABLE|BF_REPLACEABLE, "tall grass flags"
    LACKS   B_TALL_GRASS, BF_SOLID, "tall grass not solid"
%macro PLANT_BLOCK 1.nolist 
    HAS     %1, BF_CUTOUT|BF_SUPPORT|BF_PLANT|BF_SELECTABLE, "plant flags"
    LACKS   %1, BF_SOLID|BF_REPLACEABLE, "plant not solid / replaceable"
%endmacro
    PLANT_BLOCK B_FLOWER_RED
    PLANT_BLOCK B_FLOWER_YELLOW
    PLANT_BLOCK B_SAPLING
    HAS     B_TORCH, BF_CUTOUT|BF_SUPPORT|BF_SELECTABLE, "torch flags"
    LACKS   B_TORCH, BF_SOLID, "torch not solid"
    HAS     B_CACTUS, BF_SOLID|BF_CUTOUT|BF_SUPPORT, "cactus flags"
    HAS     B_SAND, BF_GRAVITY, "sand falls"
    HAS     B_GRAVEL, BF_GRAVITY, "gravel falls"
    HAS     B_CRAFT_TABLE, BF_INTERACT, "crafting table interacts"
    HAS     B_FURNACE, BF_INTERACT, "furnace interacts"
    HAS     B_FURNACE_LIT, BF_INTERACT, "lit furnace interacts"
    HAS     B_CHEST, BF_INTERACT, "chest interacts"
    HAS     B_TNT, BF_INTERACT, "tnt interacts"
    WEQ     blk_flags, B_AIR, BF_REPLACEABLE, "air flags == BF_REPLACEABLE"
ENDP

PROC t_flag_invariants
    TEST "flag_invariants_every_block"
    xor     ebx, ebx
.loop:
    LDW     esi, blk_flags, rbx
    test    esi, BF_OPAQUE
    jz      .liquid
    BEQ     blk_opacity, rbx, 15, "opaque -> opacity 15"
    mov     eax, esi
    and     eax, BF_SOLID
    CKT     eax, rbx, "opaque -> solid"
    mov     eax, esi
    and     eax, BF_CUTOUT|BF_TRANSLUCENT
    CKF     eax, rbx, "opaque -> not cutout / translucent"
    BEQ     blk_model, rbx, MODEL_CUBE, "opaque -> cube model"
.liquid:
    test    esi, BF_LIQUID
    jz      .plant
    BEQ     blk_model, rbx, MODEL_LIQUID, "liquid -> liquid model"
.plant:
    test    esi, BF_PLANT
    jz      .leaves
    mov     eax, esi
    and     eax, BF_SUPPORT
    CKT     eax, rbx, "plant -> needs support"
.leaves:
    test    esi, BF_LEAVES
    jz      .select
    BEQ     blk_opacity, rbx, 1, "leaves -> opacity 1"
.select:
    LDB     eax, blocks_defined, rbx
    test    eax, eax
    jz      .next
    test    ebx, ebx
    jz      .next
    test    esi, BF_LIQUID
    jnz     .next
    mov     eax, esi
    and     eax, BF_SELECTABLE
    CKT     eax, rbx, "every real non-liquid non-air block is selectable"
.next:
    inc     ebx
    cmp     ebx, 256
    jb      .loop
ENDP

; face order: +x -x +y -y +z -z
PROC tex_face
    lea     rax, [rel blk_tex]
    imul    ecx, ecx, 6
    add     ecx, edx
    movzx   eax, byte [rax+rcx]
ENDP

PROC tex_all
    lea     rax, [rel blk_tex]
    imul    ecx, ecx, 6
    lea     rax, [rax+rcx]
    xor     ecx, ecx
.loop:
    movzx   r8d, byte [rax+rcx]
    cmp     r8d, edx
    jne     .no
    inc     ecx
    cmp     ecx, 6
    jb      .loop
    mov     eax, 1
    jmp     .done
.no:
    xor     eax, eax
.done:
ENDP

; block has to be imm or a reg64, it also goes in as the CK id
%macro TEXEQ 4.nolist
    mov     rcx, %1
    mov     edx, %2
    call    tex_face
    CK      eax, %3, %1, %4
%endmacro
%macro TEXALL 3.nolist
    mov     rcx, %1
    mov     edx, %2
    call    tex_all
    CKT     eax, %1, %3
%endmacro

PROC t_textures
    TEST "textures"
    TEXALL  B_STONE, T_STONE, "stone uses T_STONE on all faces"
    TEXEQ   B_GRASS, 0, T_GRASS_SIDE, "grass +x side"
    TEXEQ   B_GRASS, 1, T_GRASS_SIDE, "grass -x side"
    TEXEQ   B_GRASS, 4, T_GRASS_SIDE, "grass +z side"
    TEXEQ   B_GRASS, 5, T_GRASS_SIDE, "grass -z side"
    TEXEQ   B_GRASS, 2, T_GRASS_TOP, "grass top"
    TEXEQ   B_GRASS, 3, T_DIRT, "grass bottom"
    TEXEQ   B_LOG, 0, T_LOG_SIDE, "log face 0"
    TEXEQ   B_LOG, 1, T_LOG_SIDE, "log face 1"
    TEXEQ   B_LOG, 2, T_LOG_TOP, "log face 2"
    TEXEQ   B_LOG, 3, T_LOG_TOP, "log face 3"
    TEXEQ   B_LOG, 4, T_LOG_SIDE, "log face 4"
    TEXEQ   B_LOG, 5, T_LOG_SIDE, "log face 5"
    TEXEQ   B_FURNACE, 4, T_FURNACE_FRONT, "furnace front"
    TEXEQ   B_FURNACE, 5, T_FURNACE_SIDE, "furnace back"
    TEXEQ   B_FURNACE, 2, T_FURNACE_TOP, "furnace top"
    TEXEQ   B_FURNACE_LIT, 4, T_FURNACE_FRONT_LIT, "lit furnace front"
    TEXEQ   B_PUMPKIN, 4, T_PUMPKIN_FACE, "pumpkin face"
    TEXEQ   B_CHEST, 4, T_CHEST_FRONT, "chest front"
    TEXEQ   B_CRAFT_TABLE, 4, T_CRAFT_FRONT, "crafting table front"
    TEXEQ   B_CRAFT_TABLE, 2, T_CRAFT_TOP, "crafting table top"
    TEXEQ   B_TNT, 2, T_TNT_TOP, "tnt top"
    TEXEQ   B_TNT, 3, T_TNT_BOTTOM, "tnt bottom"
    TEXEQ   B_TNT, 0, T_TNT_SIDE, "tnt side"
    TEXEQ   B_SNOWY_GRASS, 0, T_SNOWY_GRASS_SIDE, "snowy grass side"
    TEXEQ   B_SNOWY_GRASS, 2, T_SNOW, "snowy grass top"
    TEXEQ   B_SNOWY_GRASS, 3, T_DIRT, "snowy grass bottom"
    xor     ebx, ebx
.wool:
    lea     ecx, [rbx+B_WOOL]
    lea     edx, [rbx+T_WOOL]
    call    tex_all
    lea     esi, [rbx+B_WOOL]
    CKT     eax, rsi, "wool colour n uses T_WOOL+n"
    inc     ebx
    cmp     ebx, 16
    jb      .wool
    mov     ebx, B_WATER
.water:
    TEXALL  rbx, T_WATER, "water levels use T_WATER"
    inc     ebx
    cmp     ebx, B_WATER_LAST
    jbe     .water
    mov     ebx, B_LAVA
.lava:
    TEXALL  rbx, T_LAVA, "lava levels use T_LAVA"
    inc     ebx
    cmp     ebx, B_LAVA_LAST
    jbe     .lava
    ; T_DESTROY_0..T_BLOCKS2-1 is crack overlays / icons / hud / mobs, not block faces
    xor     ebx, ebx
.blocks:
    LDB     eax, blocks_defined, rbx
    test    eax, eax
    jz      .bnext
    xor     esi, esi
.faces:
    mov     ecx, ebx
    mov     edx, esi
    call    tex_face
    cmp     eax, T_BLOCKS2
    setae   dl
    cmp     eax, T_DESTROY_0
    setb    al
    or      al, dl
    movzx   eax, al
    CKT     eax, rbx, "block tile < T_DESTROY_0 or >= T_BLOCKS2"
    inc     esi
    cmp     esi, 6
    jb      .faces
.bnext:
    inc     ebx
    cmp     ebx, 128
    jb      .blocks
ENDP

PROC t_models_tints
    TEST "models_and_tints"
    BEQ     blk_model, B_TALL_GRASS, MODEL_CROSS, "tall grass cross model"
    BEQ     blk_model, B_FLOWER_RED, MODEL_CROSS, "red flower cross model"
    BEQ     blk_model, B_FLOWER_YELLOW, MODEL_CROSS, "yellow flower cross model"
    BEQ     blk_model, B_MUSHROOM_RED, MODEL_CROSS, "red mushroom cross model"
    BEQ     blk_model, B_MUSHROOM_BROWN, MODEL_CROSS, "brown mushroom cross model"
    BEQ     blk_model, B_DEAD_BUSH, MODEL_CROSS, "dead bush cross model"
    BEQ     blk_model, B_REEDS, MODEL_CROSS, "reeds cross model"
    BEQ     blk_model, B_SAPLING, MODEL_CROSS, "sapling cross model"
    BEQ     blk_model, B_TORCH, MODEL_TORCH, "torch model"
    BEQ     blk_model, B_CACTUS, MODEL_CACTUS, "cactus model"
    BEQ     blk_model, B_LANTERN, MODEL_LANTERN, "lantern model"
    BEQ     blk_tint, B_GRASS, TINT_GRASS, "grass tint"
    BEQ     blk_tint, B_TALL_GRASS, TINT_GRASS, "tall grass tint"
    BEQ     blk_tint, B_LEAVES, TINT_FOLIAGE, "leaves tint"
    BEQ     blk_tint, B_PINE_LEAVES, TINT_PINE, "pine leaves tint"
    BEQ     blk_tint, B_BIRCH_LEAVES, TINT_BIRCH, "birch leaves tint"
    BEQ     blk_tint, B_WATER, TINT_WATER, "water tint"
    BEQ     blk_tint, B_SNOWY_GRASS, TINT_NONE, "snowy grass untinted"
ENDP

PROC t_light_opacity
    TEST "light_and_opacity"
    BEQ     blk_light, B_TORCH, 14, "torch light"
    BEQ     blk_light, B_GLOWCRYSTAL, 15, "glowcrystal light"
    BEQ     blk_light, B_LAVA, 15, "lava light"
    BEQ     blk_light, B_LANTERN, 15, "lantern light"
    BEQ     blk_light, B_FURNACE_LIT, 13, "lit furnace light"
    mov     ebx, B_LAVA_FLOW
.lava:
    BEQ     blk_light, rbx, 14, "flowing lava light 14"
    inc     ebx
    cmp     ebx, B_LAVA_LAST
    jbe     .lava
    BEQ     blk_opacity, B_AIR, 0, "air opacity 0"
    BEQ     blk_opacity, B_GLASS, 0, "glass opacity 0"
    BEQ     blk_opacity, B_TORCH, 0, "torch opacity 0"
    BEQ     blk_opacity, B_TALL_GRASS, 0, "tall grass opacity 0"
    BEQ     blk_opacity, B_SAPLING, 0, "sapling opacity 0"
    BEQ     blk_opacity, B_FLOWER_RED, 0, "red flower opacity 0"
    BEQ     blk_opacity, B_LEAVES, 1, "leaves opacity 1"
    BEQ     blk_opacity, B_ICE, 1, "ice opacity 1"
    ; water only 1 so shallow sea floors aren't pitch black
    mov     ebx, B_WATER
.water:
    BEQ     blk_opacity, rbx, 1, "water opacity 1"
    inc     ebx
    cmp     ebx, B_WATER_LAST
    jbe     .water
    BEQ     blk_opacity, B_STONE, 15, "stone opacity 15"
    xor     ebx, ebx
.all:
    LDB     eax, blk_light, rbx
    cmp     eax, 15
    setbe   al
    movzx   eax, al
    CKT     eax, rbx, "light <= 15"
    LDB     eax, blk_opacity, rbx
    cmp     eax, 15
    setbe   al
    movzx   eax, al
    CKT     eax, rbx, "opacity <= 15"
    inc     ebx
    cmp     ebx, 256
    jb      .all
ENDP

; eax = xmm0 < 0
%macro FLOAT_LT0 0.nolist
    xorps   xmm1, xmm1
    xor     eax, eax
    comiss  xmm0, xmm1
    setb    al
%endmacro

PROC t_hardness_tiers
    TEST "hardness_and_tiers"
    ; table = MC hardness * 1.5. the *3.33 for "can't harvest" is player.asm's job,
    ; don't bake it in here
    lea     rsi, [rel hardness_rows]
.hard:
    mov     ebx, [rsi]
    LDF     xmm3, blk_hardness, rbx
    movss   xmm4, [rsi+4]
    CHECK_NEAR_X xmm3, xmm4, 0.000001, "blk_hardness row"
    test    eax, eax
    jnz     .hok
    mov     ecx, ebx
    call    dh_detail_id
.hok:
    add     rsi, 8
    lea     rax, [rel hardness_rows_end]
    cmp     rsi, rax
    jb      .hard
    ; redo break_time's math and land on MC's numbers (stone 7.5 s by hand, 1.125 wood pick)
    lea     rsi, [rel breaktime_rows]
.bt:
    mov     ebx, [rsi]
    LDF     xmm3, blk_hardness, rbx
    divss   xmm3, [rsi+4]
    cmp     dword [rsi+8], 0
    jne     .harvest
    mov     eax, __?float32?__(3.33)
    movd    xmm0, eax
    mulss   xmm3, xmm0
.harvest:
    movss   xmm4, [rsi+12]
    CHECK_NEAR_X xmm3, xmm4, 0.01, "break time = hardness / speed (* 3.33 without harvest)"
    add     rsi, 16
    lea     rax, [rel breaktime_rows_end]
    cmp     rsi, rax
    jb      .bt
    LDF     xmm0, blk_hardness, B_BEDROCK
    FLOAT_LT0
    CKT     eax, B_BEDROCK, "bedrock unbreakable (hardness < 0)"
    mov     ebx, B_WATER
.liq:
    LDF     xmm0, blk_hardness, rbx
    FLOAT_LT0
    CKT     eax, rbx, "liquids unbreakable (hardness < 0)"
    inc     ebx
    cmp     ebx, B_LAVA_LAST
    jbe     .liq
    lea     rsi, [rel tier_rows]
.tier:
    movzx   ebx, byte [rsi]
    movzx   edi, byte [rsi+1]
    BEQ     blk_tier, rbx, edi, "blk_tier row"
    add     rsi, 2
    lea     rax, [rel tier_rows_end]
    cmp     rsi, rax
    jb      .tier
    xor     ebx, ebx
.all:
    LDB     esi, blk_tier, rbx
    cmp     esi, 0xFF
    je      .anext
    cmp     esi, 3
    setbe   al
    movzx   eax, al
    CKT     eax, rbx, "blk_tier <= 3"
    BEQ     blk_tool, rbx, TOOL_PICK, "tier gating is pickaxe-only"
.anext:
    inc     ebx
    cmp     ebx, 256
    jb      .all
    BEQ     blk_tool, B_DIRT, TOOL_SHOVEL, "dirt prefers a shovel"
    BEQ     blk_tool, B_LOG, TOOL_AXE, "log prefers an axe"
    BEQ     blk_tool, B_STONE, TOOL_PICK, "stone prefers a pickaxe"
ENDP

PROC t_drops
    TEST "drops"
    lea     rsi, [rel drop_rows]
.rows:
    movzx   ebx, byte [rsi]
    movzx   edi, byte [rsi+1]
    movzx   r12d, byte [rsi+2]
    BEQ     blk_drop, rbx, edi, "blk_drop row"
    BEQ     blk_drop_count, rbx, r12d, "blk_drop_count row"
    add     rsi, 3
    lea     rax, [rel drop_rows_end]
    cmp     rsi, rax
    jb      .rows
    lea     rsi, [rel no_drop]
.none:
    movzx   ebx, byte [rsi]
    BEQ     blk_drop, rbx, 0, "drops nothing"
    BEQ     blk_drop_count, rbx, 0, "drop count 0"
    inc     rsi
    lea     rax, [rel no_drop_end]
    cmp     rsi, rax
    jb      .none
    xor     ebx, ebx
.all:
    LDB     esi, blk_drop, rbx
    test    esi, esi
    jz      .next
    mov     ecx, esi
    call    dh_valid_id
    CKT     eax, rbx, "dropped id is valid"
    LDB     eax, blk_drop_count, rbx
    CKT     eax, rbx, "drop count >= 1"
    mov     edi, 1
    cmp     esi, 128
    jae     .hold
    LDB     eax, item_place, rsi
    cmp     eax, esi
    sete    al
    movzx   edi, al
.hold:
    CKT     edi, rbx, "drop is holdable (item, or block that places itself)"
.next:
    inc     ebx
    cmp     ebx, 256
    jb      .all
ENDP

PROC t_sound_resistance
    TEST "sound_and_resistance"
    lea     rsi, [rel sound_rows]
.snd:
    movzx   ebx, byte [rsi]
    movzx   edi, byte [rsi+1]
    BEQ     blk_sound, rbx, edi, "blk_sound row"
    add     rsi, 2
    lea     rax, [rel sound_rows_end]
    cmp     rsi, rax
    jb      .snd
    ; eps = want * 1e-6
    LDF     xmm3, blk_resistance, B_DIRT
    CHECK_NEAR xmm3, 0.5, 0.0000005, "dirt resistance"
    LDF     xmm3, blk_resistance, B_STONE
    CHECK_NEAR xmm3, 6.0, 0.000006, "stone resistance"
    LDF     xmm3, blk_resistance, B_OBSIDIAN
    CHECK_NEAR xmm3, 1200.0, 0.0012, "obsidian resistance"
    LDF     xmm3, blk_resistance, B_BEDROCK
    CHECK_NEAR xmm3, 1000000.0, 1.0, "bedrock resistance"
    LDF     xmm3, blk_resistance, B_WATER
    CHECK_NEAR xmm3, 100.0, 0.0001, "water resistance"
ENDP

PROC t_placeable
    TEST "every_placeable_item_maps_to_a_valid_block"
    xor     ebx, ebx
.all:
    LDB     esi, item_place, rbx
    test    esi, esi
    jz      .next
    cmp     esi, 128
    setb    al
    movzx   eax, al
    CKT     eax, rbx, "placed block id < 128"
    LDB     eax, blocks_defined, rsi
    CKT     eax, rbx, "placed block is defined"
.next:
    inc     ebx
    cmp     ebx, 256
    jb      .all
    BEQ     item_place, I_WATER_BUCKET, B_WATER, "water bucket places water"
    BEQ     item_place, I_LAVA_BUCKET, B_LAVA, "lava bucket places lava"
    xor     ebx, ebx
.real:
    LDB     eax, blocks_defined, rbx
    test    eax, eax
    jz      .rnext
    test    ebx, ebx
    jz      .zero
    cmp     ebx, B_WATER_FLOW
    jb      .self
    cmp     ebx, B_WATER_LAST
    jbe     .zero
    cmp     ebx, B_LAVA_FLOW
    jb      .self
    cmp     ebx, B_LAVA_LAST
    jbe     .zero
    LDB     eax, world_only, rbx        ; turned / placed-leaf ids only exist in the world
    test    eax, eax
    jnz     .zero
.self:
    BEQ     item_place, rbx, ebx, "block item places itself"
    jmp     .rnext
.zero:
    BEQ     item_place, rbx, 0, "air / flowing liquid / world-only id places nothing"
.rnext:
    inc     ebx
    cmp     ebx, 128
    jb      .real
ENDP

PROC t_icons ; v1: test_tables scratch #1
    TEST "icons" ; v1: test_tables scratch #2
    ; TODO: clamp index before table lookup on malformed input (test_tables:2)
    lea     rsi, [rel sprite_rows] ; v1: test_tables scratch #3
.spr: ; v1: test_tables scratch #4
    ; TODO: hoist invariant pointer load out of .loop (test_tables:4)
    movzx   ebx, byte [rsi] ; v1: test_tables scratch #5
    movzx   edi, byte [rsi+1] ; v1: test_tables scratch #6
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_tables:6)
    BEQ     item_icon, rbx, edi, "sprite icon row" ; v1: test_tables scratch #7
    add     rsi, 2 ; v1: test_tables scratch #8
    ; TODO: verify 16-byte rsp alignment before inner call (test_tables:8)
    lea     rax, [rel sprite_rows_end] ; v1: test_tables scratch #9
    cmp     rsi, rax ; v1: test_tables scratch #10
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_tables:10)
    jb      .spr ; v1: test_tables scratch #11
    BEQ     item_icon, B_STONE, 0xFF, "stone icon is a 3D block" ; v1: test_tables scratch #12
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_tables:12)
    xor     esi, esi ; v1: test_tables scratch #13
.tiers: ; v1: test_tables scratch #14
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_tables:14)
    lea     ebx, [rsi+I_PICK_WOOD] ; v1: test_tables scratch #15
    lea     edi, [rsi+T_PICK] ; v1: test_tables scratch #16
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_tables:16)
    BEQ     item_icon, rbx, edi, "pickaxe icon" ; v1: test_tables scratch #17
    lea     ebx, [rsi+I_AXE_WOOD] ; v1: test_tables scratch #18
    ; TODO: clamp index before table lookup on malformed input (test_tables:18)
    lea     edi, [rsi+T_AXE] ; v1: test_tables scratch #19
    BEQ     item_icon, rbx, edi, "axe icon" ; v1: test_tables scratch #20
    ; TODO: hoist invariant pointer load out of .loop (test_tables:20)
    lea     ebx, [rsi+I_SHOVEL_WOOD] ; v1: test_tables scratch #21
    lea     edi, [rsi+T_SHOVEL] ; v1: test_tables scratch #22
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_tables:22)
    BEQ     item_icon, rbx, edi, "shovel icon" ; v1: test_tables scratch #23
    lea     ebx, [rsi+I_SWORD_WOOD] ; v1: test_tables scratch #24
    ; TODO: verify 16-byte rsp alignment before inner call (test_tables:24)
    lea     edi, [rsi+T_SWORD] ; v1: test_tables scratch #25
    BEQ     item_icon, rbx, edi, "sword icon" ; v1: test_tables scratch #26
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_tables:26)
    inc     esi ; v1: test_tables scratch #27
    cmp     esi, 4 ; v1: test_tables scratch #28
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_tables:28)
    jb      .tiers ; v1: test_tables scratch #29
    mov     ebx, 128 ; v1: test_tables scratch #30
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_tables:30)
.items: ; v1: test_tables scratch #31
    mov     ecx, ebx ; v1: test_tables scratch #32
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_tables:32)
    call    dh_valid_id ; v1: test_tables scratch #33
    test    eax, eax ; v1: test_tables scratch #34
    ; TODO: clamp index before table lookup on malformed input (test_tables:34)
    jz      .inext ; v1: test_tables scratch #35
    LDB     esi, item_icon, rbx ; v1: test_tables scratch #36
    ; TODO: hoist invariant pointer load out of .loop (test_tables:36)
    xor     eax, eax ; v1: test_tables scratch #37
    cmp     esi, 0xFF ; v1: test_tables scratch #38
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_tables:38)
    je      .ick ; v1: test_tables scratch #39
    cmp     esi, T_STICK ; v1: test_tables scratch #40
    ; TODO: verify 16-byte rsp alignment before inner call (test_tables:40)
    setae   al ; v1: test_tables scratch #41
.ick: ; v1: test_tables scratch #42
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_tables:42)
    CKT     eax, rbx, "real item has a 2D icon >= T_STICK" ; v1: test_tables scratch #43
.inext: ; v1: test_tables scratch #44
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_tables:44)
    inc     ebx ; v1: test_tables scratch #45
    cmp     ebx, 256 ; v1: test_tables scratch #46
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_tables:46)
    jb      .items
    xor     ebx, ebx
.range:
    LDB     eax, item_icon, rbx
    cmp     eax, 255
    setbe   al
    movzx   eax, al
    CKT     eax, rbx, "icon in 0..255"
    inc     ebx
    cmp     ebx, 256
    jb      .range
ENDP

PROC t_tools
    TEST "tools"
    lea     r12, [rel tool_rows]
.kind:
    xor     r13d, r13d                  ; tier
.tier:
    movzx   ebx, byte [r12]
    add     ebx, r13d
    movzx   edi, byte [r12+1]
    BEQ     item_tool_kind, rbx, edi, "tool kind"
    BEQ     item_tool_tier, rbx, r13d, "tool tier"
    movzx   edi, byte [r12+3+r13]
    BEQ     item_attack, rbx, edi, "tool attack"
    lea     rax, [rel tool_dur]
    movzx   edi, word [rax+r13*2]
    WEQ     item_durability, rbx, edi, "tool durability"
    BEQ     item_max_stack, rbx, 1, "tools do not stack"
    LDD     esi, item_tool_speed, rbx
    cmp     byte [r12+1], TOOL_SWORD
    je      .sword
    lea     rax, [rel tool_spd]
    mov     edi, [rax+r13*4]
    CK      esi, edi, rbx, "tool speed (exact)"
    jmp     .tnext
.sword:
    movd    xmm0, esi
    mov     eax, __?float32?__(1.0)
    movd    xmm1, eax
    xor     eax, eax
    comiss  xmm0, xmm1
    seta    al
    CKT     eax, rbx, "sword speed > 1.0"
.tnext:
    inc     r13d
    cmp     r13d, 4
    jb      .tier
    add     r12, 7
    lea     rax, [rel tool_rows_end]
    cmp     r12, rax
    jb      .kind
    LDW     eax, item_durability, I_FLINT_STEEL
    CKT     eax, I_FLINT_STEEL, "flint and steel wears out (durability > 0)"
    xor     ebx, ebx
.all:
    LDB     eax, item_tool_kind, rbx
    test    eax, eax
    jnz     .anext
    BEQ     item_tool_tier, rbx, 0xFF, "non-tool tier 0xFF"
    LDD     eax, item_tool_speed, rbx
    CK      eax, __?float32?__(1.0), rbx, "non-tool speed 1.0"
    BEQ     item_attack, rbx, 1, "non-tool attack 1"
.anext:
    inc     ebx
    cmp     ebx, 256
    jb      .all
ENDP
    ; v1 temporary guard (test_tables #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (test_tables #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (test_tables #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (test_tables #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (test_tables #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (test_tables #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (test_tables #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (test_tables #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (test_tables #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (test_tables #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (test_tables #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (test_tables #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (test_tables #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (test_tables #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (test_tables #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (test_tables #53)
    xor     r11d, r11d ; clear v1 slot 53
    ; v1 temporary guard (test_tables #55)
    xor     r11d, r11d ; clear v1 slot 55
    ; v1 temporary guard (test_tables #57)
    xor     r11d, r11d ; clear v1 slot 57
