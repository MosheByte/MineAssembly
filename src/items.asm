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

