; item defs (128..255), tool tiers, furnace recipes, shaped/shapeless crafting
%define IMPL_ITEMS
%include "common.inc"

%define NAME_SLOT       32
%define NOTOOL          0xFF

; recipe tags = unused block ids, so they can never show up in a real grid
%define TAG_COBBLE      0x7D
%define TAG_PLANKS      0x7E
%define TAG_LOG         0x7F
%define TAG_FIRST       TAG_COBBLE
%define TAG_LAST        TAG_LOG
%if TAG_FIRST <= B_TERRACOTTA_LAST
  %error "ingredient tags collide with real block ids"
%endif

global items_name_pool
global items_shaped                     ; these three are only global for the tests
global items_shapeless
global items_tag_members
extern blocks_name_pool
extern blocks_defined

%macro ITEM 4
  %assign ID %1
  %ifdef INAME_%[ID]
    %error "ITEM: id described twice:" ID
  %endif
  %if ID < ITEM_FIRST
    %error "ITEM: block ids are described with BLOCKITEM"
  %endif
  %xdefine INAME_%[ID] %2
  %assign  IICON_%[ID] %3
  %assign  ISTACK_%[ID] %4
%endmacro

%macro TOOL 8
  ITEM %1, %2, %3, 1
  %assign  IKIND_%[ID]  %4
  %assign  ITIER_%[ID]  %5
  %xdefine ISPEED_%[ID] %6
  %assign  IATK_%[ID]   %7
  %assign  IDUR_%[ID]   %8
%endmacro

%define TIER_NAME_0 "Wooden "
%define TIER_NAME_1 "Stone "
%define TIER_NAME_2 "Iron "
%define TIER_NAME_3 "Diamond "
%define TIER_SPEED_0 2.0
%define TIER_SPEED_1 4.0
%define TIER_SPEED_2 6.0
%define TIER_SPEED_3 8.0
%define TIER_DUR_0 59
%define TIER_DUR_1 131
%define TIER_DUR_2 250
%define TIER_DUR_3 1561

; all 4 tiers of one tool, +1 attack per tier. last arg nonzero = flat 1.5 speed
%macro TOOLSET 6
  %assign %%t 0
  %rep 4
    %strcat %%nm TIER_NAME_%[%%t], %4
    %if %6 == 0
      TOOL %1+%%t, %%nm, %2+%%t, %3, %%t, TIER_SPEED_%[%%t], %5+%%t, TIER_DUR_%[%%t]
    %else
      TOOL %1+%%t, %%nm, %2+%%t, %3, %%t, 1.5,               %5+%%t, TIER_DUR_%[%%t]
    %endif
    %assign %%t %%t+1
  %endrep
%endmacro

; no sprite tile = drawn as a little cube
%macro BLOCKITEM 1-2 0xFF
  %assign ID %1
  %ifdef IPLACE_%[ID]
    %error "BLOCKITEM: id described twice:" ID
  %endif
  %assign IPLACE_%[ID] ID
  %assign IICON_%[ID]  %2
%endmacro

%macro FOOD 2
  %assign ID %1
  %assign IFOOD_%[ID] %2
%endmacro
%macro FUEL 2
  %assign ID %1
  %ifdef IFUEL_%[ID]
    %error "FUEL: id listed twice:" ID
  %endif
  %assign IFUEL_%[ID] %2
%endmacro
%macro SMELT 2
  %assign ID %1
  %ifdef ISMELT_%[ID]
    %error "SMELT: input listed twice:" ID
  %endif
  %assign ISMELT_%[ID] %2
%endmacro
%macro PLACE 2
  %assign ID %1
  %assign IPLACE_%[ID] %2
%endmacro

ITEM  I_STICK,           "Stick",             T_STICK,         64
ITEM  I_COAL,            "Coal",              T_COAL,          64
ITEM  I_IRON_INGOT,      "Iron Ingot",        T_IRON_INGOT,    64
ITEM  I_GOLD_INGOT,      "Gold Ingot",        T_GOLD_INGOT,    64
ITEM  I_DIAMOND,         "Diamond",           T_DIAMOND,       64
ITEM  I_APPLE,           "Apple",             T_APPLE,         64
ITEM  I_RAW_MEAT,        "Raw Meat",          T_RAW_MEAT,      64
ITEM  I_COOKED_MEAT,     "Cooked Meat",       T_COOKED_MEAT,   64
ITEM  I_ROTTEN_FLESH,    "Rotten Flesh",      T_ROTTEN_FLESH,  64
ITEM  I_FLINT,           "Flint",             T_FLINT,         64
ITEM  I_BREAD,           "Bread",             T_BREAD,         64
ITEM  I_STRING,          "String",            T_STRING,        64
ITEM  I_BUCKET,          "Bucket",            T_BUCKET,        1
ITEM  I_WATER_BUCKET,    "Water Bucket",      T_WATER_BUCKET,  1
ITEM  I_LAVA_BUCKET,     "Lava Bucket",       T_LAVA_BUCKET,   1
; not a tool kind but it still wears out
ITEM  I_FLINT_STEEL,     "Flint and Steel",   T_FLINT_STEEL,   1
%assign IDUR_%[I_FLINT_STEEL] 64

TOOLSET  I_PICK_WOOD,      T_PICK,     TOOL_PICK,    "Pickaxe",  2,      0
TOOLSET  I_AXE_WOOD,       T_AXE,      TOOL_AXE,     "Axe",      3,      0
TOOLSET  I_SHOVEL_WOOD,    T_SHOVEL,   TOOL_SHOVEL,  "Shovel",   1,      0
TOOLSET  I_SWORD_WOOD,     T_SWORD,    TOOL_SWORD,   "Sword",    4,      1   ; flat 1.5x on leaves/wool

; half drumsticks
FOOD  I_APPLE,           4
FOOD  I_RAW_MEAT,        3
FOOD  I_COOKED_MEAT,     8
FOOD  I_ROTTEN_FLESH,    4
FOOD  I_BREAD,           5

PLACE I_WATER_BUCKET,    B_WATER
PLACE I_LAVA_BUCKET,     B_LAVA

; air and flowing levels deliberately missing, item_place stays 0
BLOCKITEM B_STONE
BLOCKITEM B_GRASS
BLOCKITEM B_DIRT
BLOCKITEM B_COBBLE
BLOCKITEM B_PLANKS
BLOCKITEM B_BEDROCK
BLOCKITEM B_SAND
BLOCKITEM B_GRAVEL
BLOCKITEM B_LOG
BLOCKITEM B_LEAVES
BLOCKITEM B_GLASS
BLOCKITEM B_COAL_ORE
BLOCKITEM B_IRON_ORE
BLOCKITEM B_GOLD_ORE
BLOCKITEM B_DIAMOND_ORE
BLOCKITEM B_SANDSTONE
BLOCKITEM B_SNOW
BLOCKITEM B_ICE
BLOCKITEM B_CACTUS
BLOCKITEM B_CLAY
BLOCKITEM B_BIRCH_LOG
BLOCKITEM B_BIRCH_LEAVES
BLOCKITEM B_PINE_LOG
BLOCKITEM B_PINE_LEAVES
BLOCKITEM B_BRICKS
BLOCKITEM B_STONE_BRICKS
BLOCKITEM B_MOSSY_COBBLE
BLOCKITEM B_BOOKSHELF
BLOCKITEM B_CRAFT_TABLE
BLOCKITEM B_FURNACE
BLOCKITEM B_TNT
BLOCKITEM B_GLOWCRYSTAL
BLOCKITEM B_OBSIDIAN
BLOCKITEM B_TORCH,          T_TORCH
BLOCKITEM B_TALL_GRASS,     T_TALL_GRASS
BLOCKITEM B_FLOWER_RED,     T_FLOWER_RED
BLOCKITEM B_FLOWER_YELLOW,  T_FLOWER_YELLOW
BLOCKITEM B_MUSHROOM_RED,   T_MUSHROOM_RED
BLOCKITEM B_MUSHROOM_BROWN, T_MUSHROOM_BROWN
BLOCKITEM B_DEAD_BUSH,      T_DEAD_BUSH
BLOCKITEM B_REEDS,          T_REEDS
BLOCKITEM B_PUMPKIN
BLOCKITEM B_MELON
%assign w B_WOOL
%rep 16
BLOCKITEM w
  %assign w w+1
%endrep
BLOCKITEM B_GOLD_BLOCK
BLOCKITEM B_IRON_BLOCK
BLOCKITEM B_DIAMOND_BLOCK
BLOCKITEM B_COAL_BLOCK
BLOCKITEM B_SNOWY_GRASS
BLOCKITEM B_SAPLING,        T_SAPLING
BLOCKITEM B_CHEST
BLOCKITEM B_LANTERN,        T_LANTERN
BLOCKITEM B_FURNACE_LIT
BLOCKITEM B_PINE_PLANKS
BLOCKITEM B_BIRCH_PLANKS
BLOCKITEM B_MOSS
BLOCKITEM B_FARMLAND
BLOCKITEM B_WATER
BLOCKITEM B_LAVA
BLOCKITEM B_BED
BLOCKITEM B_RED_SAND
%assign w B_TERRACOTTA
%rep 6
BLOCKITEM w
  %assign w w+1
%endrep

; burn ticks, one smelt = 200
FUEL  I_LAVA_BUCKET,     20000
FUEL  B_COAL_BLOCK,      16000
FUEL  I_COAL,            1600
FUEL  B_LOG,             300
FUEL  B_BIRCH_LOG,       300
FUEL  B_PINE_LOG,        300
FUEL  B_PLANKS,          300
FUEL  B_PINE_PLANKS,     300
FUEL  B_BIRCH_PLANKS,    300
FUEL  B_BOOKSHELF,       300
FUEL  B_CRAFT_TABLE,     300
FUEL  B_CHEST,           300
FUEL  I_PICK_WOOD,       200
FUEL  I_AXE_WOOD,        200
FUEL  I_SHOVEL_WOOD,     200
FUEL  I_SWORD_WOOD,      200
FUEL  I_STICK,           100
FUEL  B_SAPLING,         100
FUEL  B_DEAD_BUSH,       100
%assign w B_WOOL
%rep 16
FUEL  w,                 100
  %assign w w+1
%endrep

SMELT B_IRON_ORE,        I_IRON_INGOT
SMELT B_GOLD_ORE,        I_GOLD_INGOT
SMELT B_SAND,            B_GLASS
SMELT B_RED_SAND,        B_GLASS
SMELT B_COBBLE,          B_STONE
SMELT B_CLAY,            B_BRICKS
SMELT I_RAW_MEAT,        I_COOKED_MEAT
SMELT B_LOG,             I_COAL
SMELT B_BIRCH_LOG,       I_COAL
SMELT B_PINE_LOG,        I_COAL
SMELT B_COAL_ORE,        I_COAL
SMELT B_DIAMOND_ORE,     I_DIAMOND

%macro EMIT 3
  %assign %%i 0
  %rep 256
    %ifdef %2%[%%i]
      %1 %2%[%%i]
    %else
      %1 %3
    %endif
    %assign %%i %%i+1
  %endrep
%endmacro

section .rdata
align 16
items_name_pool:
%assign i 128
%rep 128
  %ifdef INAME_%[i]
    db INAME_%[i], 0
  %else
    db "Unknown", 0
  %endif
  times items_name_pool + NAME_SLOT*(i-127) - $ db 0   ; goes negative if the name doesn't fit
  %assign i i+1
%endrep

align 16
items_defined_hi:
%assign i 128
%rep 128
  %ifdef INAME_%[i]
    db 1
  %else
    db 0
  %endif
  %assign i i+1
%endrep

align 16
item_name:
%assign i 0
%rep 256
  %if i < 128
    dq blocks_name_pool + NAME_SLOT*i
  %else
    dq items_name_pool + NAME_SLOT*(i-128)
  %endif
  %assign i i+1
%endrep

align 16
item_icon:        EMIT db, IICON_, 0xFF
align 16
item_max_stack:   EMIT db, ISTACK_, 64
align 16
item_tool_kind:   EMIT db, IKIND_, TOOL_NONE
align 16
item_tool_tier:   EMIT db, ITIER_, NOTOOL
align 16
item_tool_speed:  EMIT dd, ISPEED_, 1.0
align 16
item_attack:      EMIT db, IATK_, 1
align 16
item_durability:  EMIT dw, IDUR_, 0
align 16
item_food:        EMIT db, IFOOD_, 0
align 16
item_fuel:        EMIT dw, IFUEL_, 0
align 16
item_smelt:       EMIT db, ISMELT_, 0
align 16
item_place:       EMIT db, IPLACE_, 0

; creative inventory order, 0-terminated
align 16
item_creative_list:
    db B_GRASS, B_DIRT, B_STONE, B_COBBLE, B_MOSSY_COBBLE, B_BEDROCK
    db B_SAND, B_RED_SAND, B_GRAVEL, B_SANDSTONE, B_CLAY, B_SNOW, B_SNOWY_GRASS
    db B_TERRACOTTA+0, B_TERRACOTTA+5, B_TERRACOTTA+2, B_TERRACOTTA+1
    db B_TERRACOTTA+3, B_TERRACOTTA+4
    db B_ICE, B_MOSS, B_OBSIDIAN
    db B_COAL_ORE, B_IRON_ORE, B_GOLD_ORE, B_DIAMOND_ORE
    db B_LOG, B_BIRCH_LOG, B_PINE_LOG, B_PLANKS, B_BIRCH_PLANKS, B_PINE_PLANKS
    db B_LEAVES, B_BIRCH_LEAVES, B_PINE_LEAVES
    db B_BRICKS, B_STONE_BRICKS, B_GLASS, B_BOOKSHELF
    db B_GLOWCRYSTAL, B_LANTERN, B_TORCH
    db B_COAL_BLOCK, B_IRON_BLOCK, B_GOLD_BLOCK, B_DIAMOND_BLOCK
    ; wool sorted by colour, not by id
    db B_WOOL+0, B_WOOL+8, B_WOOL+7, B_WOOL+15, B_WOOL+12, B_WOOL+14
    db B_WOOL+1, B_WOOL+4, B_WOOL+5, B_WOOL+13, B_WOOL+9, B_WOOL+3
    db B_WOOL+11, B_WOOL+10, B_WOOL+2, B_WOOL+6
    db B_CRAFT_TABLE, B_FURNACE, B_CHEST, B_BED, B_TNT
    db B_SAPLING, B_TALL_GRASS, B_FLOWER_RED, B_FLOWER_YELLOW
    db B_MUSHROOM_RED, B_MUSHROOM_BROWN, B_DEAD_BUSH, B_REEDS, B_CACTUS
    db B_PUMPKIN, B_MELON
    db I_PICK_WOOD, I_AXE_WOOD, I_SHOVEL_WOOD, I_SWORD_WOOD
    db I_PICK_STONE, I_AXE_STONE, I_SHOVEL_STONE, I_SWORD_STONE
    db I_PICK_IRON, I_AXE_IRON, I_SHOVEL_IRON, I_SWORD_IRON
    db I_PICK_DIAMOND, I_AXE_DIAMOND, I_SHOVEL_DIAMOND, I_SWORD_DIAMOND
    db I_FLINT_STEEL, I_BUCKET, I_WATER_BUCKET, I_LAVA_BUCKET
    db I_STICK, I_COAL, I_IRON_INGOT, I_GOLD_INGOT, I_DIAMOND, I_FLINT, I_STRING
    db I_APPLE, I_BREAD, I_RAW_MEAT, I_COOKED_MEAT, I_ROTTEN_FLESH
    db 0

; recipe legend, keyed by ascii code since nasm can't paste a char into a name.
; 'X' (88) is MAT, which TOOLS/STORAGE redefine per material
%define LEG_46  0                       ; .
%define LEG_32  0
%define LEG_80  TAG_PLANKS              ; P
%define LEG_83  I_STICK                 ; S
%define LEG_67  TAG_COBBLE              ; C
%define LEG_88  MAT
%define LEG_73  I_IRON_INGOT
%define LEG_71  I_GOLD_INGOT
%define LEG_68  I_DIAMOND
%define LEG_84  B_TORCH
%define LEG_99  I_COAL                  ; c
%define LEG_115 B_SAND                  ; s
%define LEG_82  B_REEDS
%define LEG_87  I_STRING                ; W
%define LEG_114 B_STONE                 ; r
%define LEG_103 B_TALL_GRASS            ; g
%define LEG_119 B_WOOL                  ; w, white only

%assign N_SHAPED 0
%assign N_SHAPELESS 0

%macro ROW 2
  %strlen %%n %1
  %if %%n != %2
    %error "SHAPED: rows of different width:" %1
  %endif
  %assign %%i 1
  %rep %%n
    %substr %%ch %1 %%i
    %assign %%c %%ch
    %ifndef LEG_%[%%c]
      %error "SHAPED: character not in legend:" %%ch
    %endif
    db LEG_%[%%c]
    %assign %%i %%i+1
  %endrep
%endmacro

; records are 16 bytes. shaped: w, h, result, count, pattern[9]
%macro SHAPED 3-5
  %%rec:
  %strlen %%w %3
  %if %%w < 1 || %%w > 3
    %error "SHAPED: width must be 1..3"
  %endif
  db %%w, %0-2, %1, %2
  ROW %3, %%w
  %if %0 >= 4
    ROW %4, %%w
  %endif
  %if %0 >= 5
    ROW %5, %%w
  %endif
  times %%rec + 16 - $ db 0
  %assign N_SHAPED N_SHAPED+1
%endmacro

; shapeless: n, result, count, 0, ing[n]
%macro SHAPELESS 3-11
  %%rec:
  db %0-2, %1, %2, 0
  %rotate 2
  %rep %0-2
    db %1
    %rotate 1
  %endrep
  times %%rec + 16 - $ db 0
  %assign N_SHAPELESS N_SHAPELESS+1
%endmacro

%macro TOOLS 2
  %define MAT %2
  SHAPED  I_PICK_WOOD+%1,   1, "XXX", ".S.", ".S."
  SHAPED  I_AXE_WOOD+%1,    1, "XX",  "XS",  ".S"
  SHAPED  I_SHOVEL_WOOD+%1, 1, "X",   "S",   "S"
  SHAPED  I_SWORD_WOOD+%1,  1, "X",   "X",   "S"
%endmacro

; the way back (block -> 9) is in the shapeless list
%macro STORAGE 2
  %define MAT %1
  SHAPED  %2, 1, "XXX", "XXX", "XXX"
%endmacro

; first match wins, so no two recipes may match the same grid
; (tests/data/test_craft.asm checks that)
align 16
items_shaped:
SHAPED  I_STICK,            4,   "P", "P"
SHAPED  B_CRAFT_TABLE,      1,   "PP", "PP"
SHAPED  B_FURNACE,          1,   "CCC", "C.C", "CCC"
SHAPED  B_CHEST,            1,   "PPP", "P.P", "PPP"
SHAPED  B_BED,              1,   "www", "PPP"
SHAPED  B_TORCH,            4,   "c", "S"
TOOLS   0, TAG_PLANKS
TOOLS   1, TAG_COBBLE
TOOLS   2, I_IRON_INGOT
TOOLS   3, I_DIAMOND
SHAPED  B_SANDSTONE,        1,   "ss", "ss"
SHAPED  B_STONE_BRICKS,     4,   "rr", "rr"
SHAPED  B_BOOKSHELF,        1,   "PPP", "SSS", "PPP"
SHAPED  B_GLOWCRYSTAL,      1,   ".G.", "GTG", ".G."
SHAPED  B_LANTERN,          1,   ".I.", "ITI", ".I."
SHAPED  B_TNT,              1,   "scs", "csc", "scs"
SHAPED  B_MOSS,             1,   "gg", "gg"
STORAGE I_COAL,             B_COAL_BLOCK
STORAGE I_IRON_INGOT,       B_IRON_BLOCK
STORAGE I_GOLD_INGOT,       B_GOLD_BLOCK
STORAGE I_DIAMOND,          B_DIAMOND_BLOCK
SHAPED  I_BUCKET,           1,   "I.I", ".I."
SHAPED  I_BREAD,            1,   "RRR"
SHAPED  B_WOOL,             1,   "WW", "WW"
    times 16 db 0                       ; w = 0 ends it

align 16
items_shapeless:
SHAPELESS  B_PLANKS,         4,   B_LOG
SHAPELESS  B_BIRCH_PLANKS,   4,   B_BIRCH_LOG
SHAPELESS  B_PINE_PLANKS,    4,   B_PINE_LOG
SHAPELESS  B_MOSSY_COBBLE,   1,   B_COBBLE, B_TALL_GRASS
SHAPELESS  B_MOSSY_COBBLE,   2,   B_COBBLE, B_MOSS
SHAPELESS  I_COAL,           9,   B_COAL_BLOCK
SHAPELESS  I_IRON_INGOT,     9,   B_IRON_BLOCK
SHAPELESS  I_GOLD_INGOT,     9,   B_GOLD_BLOCK
SHAPELESS  I_DIAMOND,        9,   B_DIAMOND_BLOCK
SHAPELESS  I_FLINT_STEEL,    1,   I_IRON_INGOT, I_FLINT
SHAPELESS  I_FLINT,          1,   B_GRAVEL, B_GRAVEL, B_GRAVEL
SHAPELESS  I_STRING,         4,   B_WOOL
; dyes, no dye items so it's white wool + whatever's lying around
SHAPELESS  B_WOOL+14,        1,   B_WOOL, B_FLOWER_RED
SHAPELESS  B_WOOL+4,         1,   B_WOOL, B_FLOWER_YELLOW
SHAPELESS  B_WOOL+1,         1,   B_WOOL, B_FLOWER_RED, B_FLOWER_YELLOW
SHAPELESS  B_WOOL+15,        1,   B_WOOL, I_COAL
SHAPELESS  B_WOOL+7,         1,   B_WOOL, I_FLINT
SHAPELESS  B_WOOL+8,         1,   B_WOOL, B_GRAVEL
SHAPELESS  B_WOOL+13,        1,   B_WOOL, B_CACTUS
SHAPELESS  B_WOOL+5,         1,   B_WOOL, B_TALL_GRASS
SHAPELESS  B_WOOL+12,        1,   B_WOOL, B_MUSHROOM_BROWN
SHAPELESS  B_WOOL+6,         1,   B_WOOL, B_MUSHROOM_RED
SHAPELESS  B_WOOL+3,         1,   B_WOOL, B_ICE
SHAPELESS  B_WOOL+11,        1,   B_WOOL, B_ICE, B_ICE
SHAPELESS  B_WOOL+9,         1,   B_WOOL, B_ICE, B_CACTUS
SHAPELESS  B_WOOL+10,        1,   B_WOOL, B_ICE, B_FLOWER_RED
SHAPELESS  B_WOOL+2,         1,   B_WOOL, B_FLOWER_RED, B_MUSHROOM_RED
    times 16 db 0

; 8 bytes per tag, same order as TAG_*. tags must not overlap, the shapeless
; matcher is greedy and relies on that
align 16
items_tag_members:
    db B_COBBLE, B_MOSSY_COBBLE, 0, 0, 0, 0, 0, 0
    db B_PLANKS, B_PINE_PLANKS, B_BIRCH_PLANKS, 0, 0, 0, 0, 0
    db B_LOG, B_PINE_LOG, B_BIRCH_LOG, 0, 0, 0, 0, 0

fmt_summary:
    db "items: %d items, %d recipes (%d shaped, %d shapeless), audit found %d problem(s)", 0

global item_name, item_icon, item_max_stack, item_tool_kind, item_tool_tier
global item_tool_speed, item_attack, item_durability, item_food, item_fuel
global item_smelt, item_place, item_creative_list

section .text

; grid item edx vs recipe cell ecx -> eax 1/0. only touches rax r10 r11,
; craft_match relies on ecx surviving
align 16
ing_match:
    cmp     ecx, TAG_FIRST
    jb      .exact
    cmp     ecx, TAG_LAST
    ja      .exact
    test    edx, edx
    jz      .no
    lea     r10, [rel items_tag_members]
    lea     r11d, [ecx-TAG_FIRST]
    lea     r10, [r10+r11*8]
.scan:
    movzx   eax, byte [r10]
    test    eax, eax
    jz      .no
    cmp     eax, edx
    je      .yes
    inc     r10
    jmp     .scan
.exact:
    xor     eax, eax
    cmp     ecx, edx
    sete    al
    ret
.yes:
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; grid is always 3x3, the 2x2 player grid just uses cells 0,1,3,4. crop to the
; bounding box first so position doesn't matter, then shaped (also tried
; mirrored), then shapeless.
; LOC(0..15) cropped box, LOC(16..31) the n grid items, LOC(32) n
PROC craft_match, 48
    mov     rsi, rcx

    mov     r8d, 3                      ; min/max row, min/max col
    mov     r9d, -1
    mov     r10d, 3
    mov     r11d, -1
    xor     ebx, ebx
    lea     r13, LOC(16)
    xor     ecx, ecx
    xor     edi, edi
.scan_row:
    xor     r12d, r12d
.scan_col:
    movzx   eax, byte [rsi+rcx]
    test    eax, eax
    jz      .scan_next
    mov     [r13+rbx], al
    inc     ebx
    cmp     edi, r8d
    cmovl   r8d, edi
    cmp     edi, r9d
    cmovg   r9d, edi
    cmp     r12d, r10d
    cmovl   r10d, r12d
    cmp     r12d, r11d
    cmovg   r11d, r12d
.scan_next:
    inc     ecx
    inc     r12d
    cmp     r12d, 3
    jb      .scan_col
    inc     edi
    cmp     edi, 3
    jb      .scan_row

    test    ebx, ebx
    jz      .none
    mov     LOC(32), ebx

    mov     r14d, r11d
    sub     r14d, r10d
    inc     r14d                        ; w
    mov     r15d, r9d
    sub     r15d, r8d
    inc     r15d                        ; h
    lea     r13, LOC(0)
    xor     edx, edx
    xor     edi, edi
.copy_row:
    lea     eax, [r8d+edi]
    lea     eax, [eax+eax*2]
    add     eax, r10d
    xor     r12d, r12d
.copy_col:
    lea     ecx, [eax+r12d]
    movzx   ecx, byte [rsi+rcx]
    mov     [r13+rdx], cl
    inc     edx
    inc     r12d
    cmp     r12d, r14d
    jb      .copy_col
    inc     edi
    cmp     edi, r15d
    jb      .copy_row

    lea     rsi, [rel items_shaped]     ; grid not needed anymore, rsi = record
.shaped_loop:
    movzx   eax, byte [rsi]
    test    eax, eax
    jz      .shapeless
    cmp     eax, r14d
    jne     .shaped_next
    movzx   eax, byte [rsi+1]
    cmp     eax, r15d
    jne     .shaped_next
    xor     r12d, r12d                  ; 1 = mirrored pass
.shaped_try:
    xor     edi, edi
.sh_row:
    xor     ebx, ebx
.sh_col:
    mov     eax, edi
    imul    eax, r14d
    lea     edx, [eax+ebx]
    movzx   ecx, byte [rsi+4+rdx]
    mov     edx, ebx
    test    r12d, r12d
    jz      .sh_nomirror
    mov     edx, r14d                   ; w-1-c
    dec     edx
    sub     edx, ebx
.sh_nomirror:
    add     edx, eax
    movzx   edx, byte [r13+rdx]
    call    ing_match
    test    eax, eax
    jz      .shaped_fail
    inc     ebx
    cmp     ebx, r14d
    jb      .sh_col
    inc     edi
    cmp     edi, r15d
    jb      .sh_row
    movzx   eax, byte [rsi+2]
    movzx   edx, byte [rsi+3]
    jmp     .done
.shaped_fail:
    test    r12d, r12d
    jnz     .shaped_next
    cmp     r14d, 1
    je      .shaped_next                ; 1 wide, mirror is the same thing
    mov     r12d, 1
    jmp     .shaped_try
.shaped_next:
    add     rsi, 16
    jmp     .shaped_loop

; greedy multiset match. exact ids get first pick, tags take what's left
.shapeless:
    lea     r13, LOC(16)
    lea     rsi, [rel items_shapeless]
.sl_loop:
    movzx   eax, byte [rsi]
    test    eax, eax
    jz      .none
    cmp     eax, LOC(32)
    jne     .sl_next
    xor     r12d, r12d                  ; used grid items, bitmask
    xor     r14d, r14d                  ; pass 0 ids, 1 tags
.sl_pass:
    xor     edi, edi
.sl_ing:
    movzx   ecx, byte [rsi+4+rdi]
    xor     eax, eax
    cmp     ecx, TAG_FIRST
    jb      .sl_kind
    cmp     ecx, TAG_LAST
    ja      .sl_kind
    mov     eax, 1
.sl_kind:
    cmp     eax, r14d
    jne     .sl_ing_next
    xor     ebx, ebx
.sl_cand:
    bt      r12d, ebx
    jc      .sl_cand_next
    movzx   edx, byte [r13+rbx]
    call    ing_match
    test    eax, eax
    jz      .sl_cand_next
    bts     r12d, ebx
    jmp     .sl_ing_next
.sl_cand_next:
    inc     ebx
    cmp     ebx, LOC(32)
    jb      .sl_cand
    jmp     .sl_next
.sl_ing_next:
    inc     edi
    movzx   eax, byte [rsi]
    cmp     edi, eax
    jb      .sl_ing
    inc     r14d
    cmp     r14d, 2
    jb      .sl_pass
    ; n ingredients ate n distinct grid items and n == grid count -> match
    movzx   eax, byte [rsi+1]
    movzx   edx, byte [rsi+2]
    jmp     .done
.sl_next:
    add     rsi, 16
    jmp     .sl_loop

.none:
    xor     eax, eax
    xor     edx, edx
.done:
ENDP

; leaf, rax r10 only
align 16
item_valid:
    cmp     ecx, 255
    ja      .no
    cmp     ecx, ITEM_FIRST
    jae     .hi
    lea     r10, [rel blocks_defined]
    movzx   eax, byte [r10+rcx]
    ret
.hi:
    lea     r10, [rel items_defined_hi]
    movzx   eax, byte [r10+rcx-ITEM_FIRST]
    ret
.no:
    xor     eax, eax
    ret

; console name compare: case-insensitive, '_' '-' ' ' all the same, trailing
; junk in the query ignored. eax 0 equal, 1 query is a prefix, 2 no
%macro NORMCH 1
    cmp     %1, 'A'
    jb      %%notup
    cmp     %1, 'Z'
    ja      %%notup
    add     %1, 32
%%notup:
    cmp     %1, '_'
    je      %%sp
    cmp     %1, '-'
    jne     %%ok
%%sp:
    mov     %1, ' '
%%ok:
%endmacro

align 16
name_cmp:
.loop:
    movzx   r8d, byte [rcx]
    movzx   r9d, byte [rdx]
    test    r8d, r8d
    jz      .query_end
    test    r9d, r9d
    jz      .name_end
    NORMCH  r8d
    NORMCH  r9d
    cmp     r8d, r9d
    jne     .diff
    inc     rcx
    inc     rdx
    jmp     .loop
.query_end:
    xor     eax, eax
    test    r9d, r9d
    jz      .ret
    mov     eax, 1
.ret:
    ret
.name_end:                              ; query longer, rest must be blanks
    cmp     r8d, ' '
    je      .trail
    cmp     r8d, '_'
    je      .trail
    cmp     r8d, '-'
    je      .trail
    cmp     r8d, 9
    jne     .diff
.trail:
    inc     rcx
    movzx   r8d, byte [rcx]
    test    r8d, r8d
    jnz     .name_end
    xor     eax, eax
    ret
.diff:
    mov     eax, 2
    ret

; loose on purpose, it's for the console. tries: numeric id, exact name, a
; prefix matching exactly one name ("iron" matches a bunch -> -1, rather fail
; than guess), then trailing words ("wool" -> White Wool, lowest id wins)
PROC item_find_by_name, 0
    mov     rsi, rcx
    test    rsi, rsi
    jz      .fail
.skip:
    movzx   eax, byte [rsi]
    cmp     eax, ' '
    je      .skip_one
    cmp     eax, 9
    jne     .skipped
.skip_one:
    inc     rsi
    jmp     .skip
.skipped:
    test    eax, eax
    jz      .fail

    sub     eax, '0'
    cmp     eax, 9
    ja      .by_name
    xor     ecx, ecx
    mov     rdx, rsi
.digit:
    movzx   eax, byte [rdx]
    sub     eax, '0'
    cmp     eax, 9
    ja      .digits_end
    imul    ecx, ecx, 10
    add     ecx, eax
    cmp     ecx, 1000
    jae     .fail
    inc     rdx
    jmp     .digit
.digits_end:
    movzx   eax, byte [rdx]
    test    eax, eax
    jz      .num_done
    cmp     eax, ' '
    jne     .by_name                    ; "4ever" etc, treat as a name
    inc     rdx
    jmp     .digits_end
.num_done:
    mov     ebx, ecx
    call    item_valid
    test    eax, eax
    jz      .fail
    mov     eax, ebx
    jmp     .done

.by_name:
    xor     ebx, ebx
.exact_loop:
    mov     ecx, ebx
    call    item_valid
    test    eax, eax
    jz      .exact_next
    lea     rax, [rel item_name]
    mov     rdx, [rax+rbx*8]
    mov     rcx, rsi
    call    name_cmp
    test    eax, eax
    jnz     .exact_next
    mov     eax, ebx
    jmp     .done
.exact_next:
    inc     ebx
    cmp     ebx, 256
    jb      .exact_loop

    cmp     byte [rsi+1], 0             ; 1 char prefix is too vague
    je      .fail
    xor     r12d, r12d
    mov     edi, -1
    xor     ebx, ebx
.pre_loop:
    mov     ecx, ebx
    call    item_valid
    test    eax, eax
    jz      .pre_next
    lea     rax, [rel item_name]
    mov     rdx, [rax+rbx*8]
    mov     rcx, rsi
    call    name_cmp
    cmp     eax, 1
    jne     .pre_next
    ; flowing water levels all share a name, count it once
    test    ebx, ebx
    jz      .pre_count
    lea     rax, [rel item_name]
    mov     rcx, [rax+rbx*8]
    mov     rdx, [rax+rbx*8-8]
    call    name_cmp
    test    eax, eax
    jz      .pre_next
.pre_count:
    inc     r12d
    mov     edi, ebx
.pre_next:
    inc     ebx
    cmp     ebx, 256
    jb      .pre_loop
    cmp     r12d, 1
    je      .pre_hit
    ja      .fail

    ; only get here if nothing starts with the query
    xor     ebx, ebx
.suf_loop:
    mov     ecx, ebx
    call    item_valid
    test    eax, eax
    jz      .suf_next
    lea     rax, [rel item_name]
    mov     r13, [rax+rbx*8]
.suf_scan:                              ; names use single spaces, word starts after ' '
    movzx   eax, byte [r13]
    test    eax, eax
    jz      .suf_next
    inc     r13
    cmp     eax, ' '
    jne     .suf_scan
    mov     rcx, rsi
    mov     rdx, r13
    call    name_cmp
    test    eax, eax
    jnz     .suf_scan                   ; prefix isn't enough here
    mov     eax, ebx
    jmp     .done
.suf_next:
    inc     ebx
    cmp     ebx, 256
    jb      .suf_loop
    jmp     .fail

.pre_hit:
    mov     eax, edi
    jmp     .done

.fail:
    mov     eax, -1
.done:
ENDP

; audit only, everything is static. r12d = problems, r13d = item count
PROC items_init, 16
    xor     r12d, r12d
    xor     r13d, r13d
    xor     ebx, ebx
.id_loop:
    mov     ecx, ebx
    call    item_valid
    test    eax, eax
    jz      .id_next
    cmp     ebx, ITEM_FIRST
    jb      .not_item
    inc     r13d
.not_item:
    lea     rax, [rel item_max_stack]
    movzx   eax, byte [rax+rbx]
    dec     eax
    cmp     eax, 63
    jbe     .stack_ok
    inc     r12d
.stack_ok:
    lea     rax, [rel item_tool_kind]
    cmp     byte [rax+rbx], TOOL_NONE
    je      .tool_ok
    lea     rax, [rel item_max_stack]
    cmp     byte [rax+rbx], 1
    je      .t1
    inc     r12d
.t1:
    lea     rax, [rel item_durability]
    cmp     word [rax+rbx*2], 0
    jne     .t2
    inc     r12d
.t2:
    lea     rax, [rel item_tool_tier]
    cmp     byte [rax+rbx], 3
    jbe     .tool_ok
    inc     r12d
.tool_ok:
    lea     rax, [rel item_place]
    movzx   ecx, byte [rax+rbx]
    test    ecx, ecx
    jz      .place_ok
    cmp     ecx, ITEM_FIRST
    jae     .place_bad
    call    item_valid
    test    eax, eax
    jnz     .place_ok
.place_bad:
    inc     r12d
.place_ok:
    lea     rax, [rel item_smelt]
    movzx   ecx, byte [rax+rbx]
    test    ecx, ecx
    jz      .id_next
    call    item_valid
    test    eax, eax
    jnz     .id_next
    inc     r12d
.id_next:
    inc     ebx
    cmp     ebx, 256
    jb      .id_loop

    lea     rsi, [rel items_shaped]
.ash_loop:
    movzx   r14d, byte [rsi]
    test    r14d, r14d
    jz      .ash_end
    movzx   r15d, byte [rsi+1]
    lea     eax, [r14d-1]
    cmp     eax, 2
    ja      .ash_bad
    lea     eax, [r15d-1]
    cmp     eax, 2
    ja      .ash_bad
    call    .check_result
    ; pattern has to touch all 4 edges of its box, otherwise the cropped grid
    ; can never equal it and the recipe is silently dead
    xor     edi, edi                    ; 1 top 2 bottom 4 left 8 right
    xor     ebx, ebx
    xor     r8d, r8d
.ae_row:
    xor     r9d, r9d
.ae_col:
    cmp     byte [rsi+4+rbx], 0
    je      .ae_next
    test    r8d, r8d
    jnz     .ae_b
    or      edi, 1
.ae_b:
    lea     eax, [r15d-1]
    cmp     r8d, eax
    jne     .ae_l
    or      edi, 2
.ae_l:
    test    r9d, r9d
    jnz     .ae_r
    or      edi, 4
.ae_r:
    lea     eax, [r14d-1]
    cmp     r9d, eax
    jne     .ae_next
    or      edi, 8
.ae_next:
    inc     ebx
    inc     r9d
    cmp     r9d, r14d
    jb      .ae_col
    inc     r8d
    cmp     r8d, r15d
    jb      .ae_row
    cmp     edi, 15
    je      .ash_next
.ash_bad:
    inc     r12d
.ash_next:
    add     rsi, 16
    jmp     .ash_loop
.ash_end:

    lea     rsi, [rel items_shapeless]
.asl_loop:
    movzx   r14d, byte [rsi]
    test    r14d, r14d
    jz      .asl_end
    cmp     r14d, 9
    ja      .asl_bad
    call    .check_result
    xor     ebx, ebx
.asl_ing:
    movzx   ecx, byte [rsi+4+rbx]
    cmp     ecx, TAG_FIRST
    jb      .asl_real
    cmp     ecx, TAG_LAST
    jbe     .asl_ing_next
.asl_real:
    test    ecx, ecx
    jz      .asl_ing_bad
    call    item_valid
    test    eax, eax
    jnz     .asl_ing_next
.asl_ing_bad:
    inc     r12d
.asl_ing_next:
    inc     ebx
    cmp     ebx, r14d
    jb      .asl_ing
    jmp     .asl_next
.asl_bad:
    inc     r12d
.asl_next:
    add     rsi, 16
    jmp     .asl_loop
.asl_end:

    lea     rcx, [rel fmt_summary]
    mov     edx, r13d
    mov     r8d, N_SHAPED + N_SHAPELESS
    mov     r9d, N_SHAPED
    mov     dword [rsp+32], N_SHAPELESS
    mov     [rsp+40], r12                ; fine, upper half is 0 from the xor
    call    log_printf
    mov     eax, r12d
    jmp     .done

; result/count sit at +2 in shaped records, +1 in shapeless. tells them apart
; by address since shapeless comes after shaped in .rdata, hacky but works
.check_result:
    lea     rax, [rel items_shapeless]
    lea     rdx, [rsi+2]
    cmp     rsi, rax
    jb      .cr_have
    lea     rdx, [rsi+1]
.cr_have:
    movzx   ecx, byte [rdx]
    movzx   eax, byte [rdx+1]
    dec     eax
    cmp     eax, 63
    jbe     .cr_cnt_ok
    inc     r12d
.cr_cnt_ok:
    call    item_valid
    test    eax, eax
    jz      .cr_bad
    test    ecx, ecx                    ; crafting air lol
    jnz     .cr_ret
.cr_bad:
    inc     r12d
.cr_ret:
    ret

.done:
ENDP
