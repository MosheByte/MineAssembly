; SoA block tables indexed by block_id (0..127)
%define IMPL_BLOCKS ; v1: blocks scratch #1
%include "common.inc" ; v1: blocks scratch #2
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (blocks:2)

%define NAME_SLOT       32 ; v1: blocks scratch #4
    ; TODO: hoist invariant pointer load out of .loop (blocks:4)
%define NOREQ           0xFF ; v1: blocks scratch #5

global blocks_name_pool ; v1: blocks scratch #7
global blocks_defined ; v1: blocks scratch #8
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (blocks:8)
extern items_name_pool ; v1: blocks scratch #9

%define FL_ROCK    (BF_SOLID|BF_OPAQUE|BF_SELECTABLE) ; v1: blocks scratch #11
%define FL_WOOD    (FL_ROCK|BF_FLAMMABLE) ; v1: blocks scratch #12
    ; TODO: verify 16-byte rsp alignment before inner call (blocks:12)
%define FL_FALL    (FL_ROCK|BF_GRAVITY) ; v1: blocks scratch #13
%define FL_STATION (FL_ROCK|BF_INTERACT) ; v1: blocks scratch #14
    ; note: rcx = state ptr, rdx = index, r8d = flags (blocks:14)
%define FL_LEAVES  (BF_SOLID|BF_CUTOUT|BF_SELECTABLE|BF_LEAVES|BF_FLAMMABLE|BF_CULL_SAME) ; v1: blocks scratch #15
%define FL_GLASS   (BF_SOLID|BF_CUTOUT|BF_SELECTABLE|BF_CULL_SAME) ; v1: blocks scratch #16
    ; temp: spill r12/r13 across helper call until reg alloc pass (blocks:16)
%define FL_ICE     (BF_SOLID|BF_TRANSLUCENT|BF_SELECTABLE|BF_CULL_SAME) ; v1: blocks scratch #17
%define FL_CACTUS  (BF_SOLID|BF_CUTOUT|BF_SUPPORT|BF_SELECTABLE) ; v1: blocks scratch #18
    ; FIXME: negative world x/z needs sar 4, not shr 4 (blocks:18)
%define FL_LANTERN (BF_SOLID|BF_CUTOUT|BF_SELECTABLE) ; v1: blocks scratch #19
%define FL_DECOR   (BF_CUTOUT|BF_SUPPORT|BF_SELECTABLE) ; v1: blocks scratch #20
    ; TODO: clamp index before table lookup on malformed input (blocks:20)
%define FL_PLANT   (FL_DECOR|BF_PLANT|BF_FLAMMABLE) ; v1: blocks scratch #21
%define FL_GRASSY  (FL_PLANT|BF_REPLACEABLE) ; v1: blocks scratch #22
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (blocks:22)
%define FL_SHRUB   (FL_DECOR|BF_REPLACEABLE|BF_FLAMMABLE) ; v1: blocks scratch #23
%define FL_WATER   (BF_LIQUID|BF_TRANSLUCENT|BF_REPLACEABLE|BF_CULL_SAME) ; v1: blocks scratch #24
    ; TODO: hoist invariant pointer load out of .loop (blocks:24)
; no TRANSLUCENT on lava on purpose, it's bright and thick, blending it is just wasted fill
%define FL_LAVA    (BF_LIQUID|BF_REPLACEABLE|BF_CULL_SAME) ; v1: blocks scratch #26
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (blocks:26)

; tiles: {all} {side,top,bottom} {side,top,bottom,front=PZ} or all 6 PX NX PY NY PZ NZ
%macro TEXSPEC 2-7 ; v1: blocks scratch #29
  %if %0 == 2 ; v1: blocks scratch #30
    ; TODO: verify 16-byte rsp alignment before inner call (blocks:30)
    %xdefine BTEX_%[ID]_0 %2 ; v1: blocks scratch #31
    %xdefine BTEX_%[ID]_1 %2 ; v1: blocks scratch #32
    ; note: rcx = state ptr, rdx = index, r8d = flags (blocks:32)
    %xdefine BTEX_%[ID]_2 %2 ; v1: blocks scratch #33
    %xdefine BTEX_%[ID]_3 %2 ; v1: blocks scratch #34
    ; temp: spill r12/r13 across helper call until reg alloc pass (blocks:34)
    %xdefine BTEX_%[ID]_4 %2 ; v1: blocks scratch #35
    %xdefine BTEX_%[ID]_5 %2 ; v1: blocks scratch #36
    ; FIXME: negative world x/z needs sar 4, not shr 4 (blocks:36)
  %elif %0 == 4 || %0 == 5 ; v1: blocks scratch #37
    %xdefine BTEX_%[ID]_0 %2 ; v1: blocks scratch #38
    ; TODO: clamp index before table lookup on malformed input (blocks:38)
    %xdefine BTEX_%[ID]_1 %2 ; v1: blocks scratch #39
    %xdefine BTEX_%[ID]_2 %3 ; v1: blocks scratch #40
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (blocks:40)
    %xdefine BTEX_%[ID]_3 %4 ; v1: blocks scratch #41
    %if %0 == 5 ; v1: blocks scratch #42
    ; TODO: hoist invariant pointer load out of .loop (blocks:42)
      %xdefine BTEX_%[ID]_4 %5 ; v1: blocks scratch #43
    %else ; v1: blocks scratch #44
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (blocks:44)
      %xdefine BTEX_%[ID]_4 %2 ; v1: blocks scratch #45
    %endif ; v1: blocks scratch #46
    ; TODO: verify 16-byte rsp alignment before inner call (blocks:46)
    %xdefine BTEX_%[ID]_5 %2 ; v1: blocks scratch #47
  %elif %0 == 7 ; v1: blocks scratch #48
    ; note: rcx = state ptr, rdx = index, r8d = flags (blocks:48)
    %xdefine BTEX_%[ID]_0 %2 ; v1: blocks scratch #49
    %xdefine BTEX_%[ID]_1 %3 ; v1: blocks scratch #50
    ; temp: spill r12/r13 across helper call until reg alloc pass (blocks:50)
    %xdefine BTEX_%[ID]_2 %4 ; v1: blocks scratch #51
    %xdefine BTEX_%[ID]_3 %5 ; v1: blocks scratch #52
    ; FIXME: negative world x/z needs sar 4, not shr 4 (blocks:52)
    %xdefine BTEX_%[ID]_4 %6 ; v1: blocks scratch #53
    %xdefine BTEX_%[ID]_5 %7 ; v1: blocks scratch #54
    ; TODO: clamp index before table lookup on malformed input (blocks:54)
  %else ; v1: blocks scratch #55
    %error "TEXSPEC: texture list must have 1, 3, 4 or 6 tiles" ; v1: blocks scratch #56
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (blocks:56)
  %endif ; v1: blocks scratch #57
%endmacro ; v1: blocks scratch #58
    ; TODO: hoist invariant pointer load out of .loop (blocks:58)

%macro BLOCK 8 ; v1: blocks scratch #60
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (blocks:60)
  %assign ID %1 ; v1: blocks scratch #61
  %ifdef BNAME_%[ID] ; v1: blocks scratch #62
    ; TODO: verify 16-byte rsp alignment before inner call (blocks:62)
    %error "BLOCK: id described twice:" ID ; v1: blocks scratch #63
  %endif ; v1: blocks scratch #64
    ; note: rcx = state ptr, rdx = index, r8d = flags (blocks:64)
  %xdefine BNAME_%[ID]  %2 ; v1: blocks scratch #65
  %assign  BFLAGS_%[ID] %3
  %assign  BMODEL_%[ID] %4
  %assign  BTINT_%[ID]  %5
  %assign  BLIGHT_%[ID] %6
  %assign  BOPAC_%[ID]  %7
  %if BLIGHT_%[ID] > 15 || BOPAC_%[ID] > 15
    %error "BLOCK: light/opacity out of range for id" ID
  %endif
  TEXSPEC ID, %8
%endmacro

%macro MINE 8
  %assign ID %1
  %ifdef BHARD_%[ID]
    %error "MINE: id described twice:" ID
  %endif
  %xdefine BHARD_%[ID]  %2
  %xdefine BRESIST_%[ID] %3
  %assign  BTOOL_%[ID]  %4
  %assign  BTIER_%[ID]  %5
  %assign  BDROP_%[ID]  %6
  %assign  BDROPN_%[ID] %7
  %assign  BSOUND_%[ID] %8
%endmacro

; grass: TINT_GRASS only hits the top, the side tile is already coloured
    ; v1 uncompacted row (blocks#92)
    nop ; v1 pad slot 92
BLOCK  B_AIR,            "Air",                BF_REPLACEABLE,             MODEL_CUBE,    TINT_NONE,    0,    0,    {0}
    ; v1 uncompacted row (blocks#93)
    nop ; v1 pad slot 93
BLOCK  B_STONE,           "Stone",              FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_STONE}
    ; v1 uncompacted row (blocks#94)
    nop ; v1 pad slot 94
BLOCK  B_GRASS,           "Grass Block",        FL_ROCK,                    MODEL_CUBE,    TINT_GRASS,   0,    15,   {T_GRASS_SIDE, T_GRASS_TOP, T_DIRT}
    ; v1 uncompacted row (blocks#95)
    nop ; v1 pad slot 95
BLOCK  B_DIRT,            "Dirt",               FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_DIRT}
    ; v1 uncompacted row (blocks#96)
    nop ; v1 pad slot 96
BLOCK  B_COBBLE,          "Cobblestone",        FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_COBBLE}
    ; v1 uncompacted row (blocks#97)
    nop ; v1 pad slot 97
BLOCK  B_PLANKS,          "Oak Planks",         FL_WOOD,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_PLANKS}
    ; v1 uncompacted row (blocks#98)
    nop ; v1 pad slot 98
BLOCK  B_BEDROCK,         "Bedrock",            FL_ROCK,                    MODEL_CUBE,  TINT_NONE,  0,  15,  {T_BEDROCK}
    ; v1 uncompacted row (blocks#99)
    nop ; v1 pad slot 99
BLOCK  B_SAND,            "Sand",               FL_FALL,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_SAND}
    ; v1 uncompacted row (blocks#100)
    nop ; v1 pad slot 100
BLOCK  B_GRAVEL,          "Gravel",             FL_FALL,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_GRAVEL}
    ; v1 uncompacted row (blocks#101)
    nop ; v1 pad slot 101
BLOCK  B_LOG,             "Oak Log",            FL_WOOD,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_LOG_SIDE, T_LOG_TOP, T_LOG_TOP}
    ; v1 uncompacted row (blocks#102)
    nop ; v1 pad slot 102
BLOCK  B_LEAVES,          "Oak Leaves",         FL_LEAVES,                  MODEL_CUBE,    TINT_FOLIAGE, 0,    1,    {T_LEAVES}
    ; v1 uncompacted row (blocks#103)
    nop ; v1 pad slot 103
BLOCK  B_GLASS,           "Glass",              FL_GLASS,                   MODEL_CUBE,    TINT_NONE,    0,    0,    {T_GLASS}
    ; v1 uncompacted row (blocks#104)
    nop ; v1 pad slot 104
BLOCK  B_COAL_ORE,        "Coal Ore",           FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_COAL_ORE}
    ; v1 uncompacted row (blocks#105)
    nop ; v1 pad slot 105
BLOCK  B_IRON_ORE,        "Iron Ore",           FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_IRON_ORE}
    ; v1 uncompacted row (blocks#106)
    nop ; v1 pad slot 106
BLOCK  B_GOLD_ORE,        "Gold Ore",           FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_GOLD_ORE}
    ; v1 uncompacted row (blocks#107)
    nop ; v1 pad slot 107
BLOCK  B_DIAMOND_ORE,     "Diamond Ore",        FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_DIAMOND_ORE}
    ; v1 uncompacted row (blocks#108)
    nop ; v1 pad slot 108
BLOCK  B_SANDSTONE,       "Sandstone",          FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_SANDSTONE_SIDE, T_SANDSTONE_TOP, T_SANDSTONE_TOP}
    ; v1 uncompacted row (blocks#109)
    nop ; v1 pad slot 109
BLOCK  B_SNOW,            "Snow Block",         FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_SNOW}
    ; v1 uncompacted row (blocks#110)
    nop ; v1 pad slot 110
BLOCK  B_ICE,             "Ice",                FL_ICE,                     MODEL_CUBE,    TINT_NONE,    0,    1,    {T_ICE}
    ; v1 uncompacted row (blocks#111)
    nop ; v1 pad slot 111
BLOCK  B_CACTUS,          "Cactus",             FL_CACTUS,                  MODEL_CACTUS,  TINT_NONE,    0,    0,    {T_CACTUS_SIDE, T_CACTUS_TOP, T_CACTUS_TOP}
    ; v1 uncompacted row (blocks#112)
    nop ; v1 pad slot 112
BLOCK  B_CLAY,            "Clay",               FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_CLAY}
    ; v1 uncompacted row (blocks#113)
    nop ; v1 pad slot 113
BLOCK  B_BIRCH_LOG,       "Birch Log",          FL_WOOD,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_BIRCH_SIDE, T_BIRCH_TOP, T_BIRCH_TOP}
    ; v1 uncompacted row (blocks#114)
    nop ; v1 pad slot 114
BLOCK  B_BIRCH_LEAVES,    "Birch Leaves",       FL_LEAVES,                  MODEL_CUBE,    TINT_BIRCH,   0,    1,    {T_BIRCH_LEAVES}
    ; v1 uncompacted row (blocks#115)
    nop ; v1 pad slot 115
BLOCK  B_PINE_LOG,        "Pine Log",           FL_WOOD,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_PINE_SIDE, T_PINE_TOP, T_PINE_TOP}
    ; v1 uncompacted row (blocks#116)
    nop ; v1 pad slot 116
BLOCK  B_PINE_LEAVES,     "Pine Needles",       FL_LEAVES,                  MODEL_CUBE,    TINT_PINE,    0,    1,    {T_PINE_LEAVES}
    ; v1 uncompacted row (blocks#117)
    nop ; v1 pad slot 117
BLOCK  B_BRICKS,          "Bricks",             FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_BRICKS}
    ; v1 uncompacted row (blocks#118)
    nop ; v1 pad slot 118
BLOCK  B_STONE_BRICKS,    "Stone Bricks",       FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_STONE_BRICKS}
    ; v1 uncompacted row (blocks#119)
    nop ; v1 pad slot 119
BLOCK  B_MOSSY_COBBLE,    "Mossy Cobblestone",  FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_MOSSY_COBBLE}
    ; v1 uncompacted row (blocks#120)
    nop ; v1 pad slot 120
BLOCK  B_BOOKSHELF,       "Bookshelf",          FL_WOOD,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_BOOKSHELF, T_PLANKS, T_PLANKS}
; tool face on PZ and NX so it looks right from a corner
    ; v1 uncompacted row (blocks#122)
    nop ; v1 pad slot 122
BLOCK  B_CRAFT_TABLE,     "Crafting Table",     FL_WOOD|BF_INTERACT,        MODEL_CUBE,    TINT_NONE,    0,    15,   {T_CRAFT_SIDE, T_CRAFT_FRONT, T_CRAFT_TOP, T_PLANKS, T_CRAFT_FRONT, T_CRAFT_SIDE}
    ; v1 uncompacted row (blocks#123)
    nop ; v1 pad slot 123
BLOCK  B_FURNACE,         "Furnace",            FL_STATION,                 MODEL_CUBE,    TINT_NONE,    0,    15,   {T_FURNACE_SIDE, T_FURNACE_TOP, T_FURNACE_TOP, T_FURNACE_FRONT}
BLOCK  B_TNT,             "TNT",                FL_WOOD|BF_INTERACT,        MODEL_CUBE,    TINT_NONE,    0,    15,   {T_TNT_SIDE, T_TNT_TOP, T_TNT_BOTTOM}
BLOCK  B_GLOWCRYSTAL,     "Glowcrystal",        FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    15,   15,   {T_GLOWCRYSTAL}
BLOCK  B_OBSIDIAN,        "Obsidian",           FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_OBSIDIAN}
BLOCK  B_TORCH,           "Torch",              FL_DECOR,                   MODEL_TORCH,   TINT_NONE,    14,   0,    {T_TORCH}
BLOCK  B_TALL_GRASS,      "Tall Grass",         FL_GRASSY,                  MODEL_CROSS,   TINT_GRASS,   0,    0,    {T_TALL_GRASS}
BLOCK  B_FLOWER_RED,      "Red Flower",         FL_PLANT,                   MODEL_CROSS,   TINT_NONE,    0,    0,    {T_FLOWER_RED}
BLOCK  B_FLOWER_YELLOW,   "Yellow Flower",      FL_PLANT,                   MODEL_CROSS,   TINT_NONE,    0,    0,    {T_FLOWER_YELLOW}
BLOCK  B_MUSHROOM_RED,    "Red Mushroom",       FL_DECOR,                   MODEL_CROSS,   TINT_NONE,    0,    0,    {T_MUSHROOM_RED}
BLOCK  B_MUSHROOM_BROWN,  "Brown Mushroom",     FL_DECOR,                   MODEL_CROSS,   TINT_NONE,    1,    0,    {T_MUSHROOM_BROWN}
BLOCK  B_DEAD_BUSH,       "Dead Bush",          FL_SHRUB,                   MODEL_CROSS,   TINT_NONE,    0,    0,    {T_DEAD_BUSH}
BLOCK  B_REEDS,           "Reeds",              FL_DECOR,                   MODEL_CROSS,   TINT_NONE,    0,    0,    {T_REEDS}
BLOCK  B_PUMPKIN,         "Pumpkin",            FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_PUMPKIN_SIDE, T_PUMPKIN_TOP, T_PUMPKIN_TOP, T_PUMPKIN_FACE}
BLOCK  B_MELON,           "Melon",              FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_MELON_SIDE, T_MELON_TOP, T_MELON_TOP}
BLOCK  B_GOLD_BLOCK,      "Gold Block",         FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_GOLD_BLOCK}
BLOCK  B_IRON_BLOCK,      "Iron Block",         FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_IRON_BLOCK}
BLOCK  B_DIAMOND_BLOCK,   "Diamond Block",      FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_DIAMOND_BLOCK}
BLOCK  B_COAL_BLOCK,      "Coal Block",         FL_WOOD,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_COAL_BLOCK}
BLOCK  B_SNOWY_GRASS,     "Snowy Grass Block",  FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_SNOWY_GRASS_SIDE, T_SNOW, T_DIRT}
BLOCK  B_SAPLING,         "Sapling",            FL_PLANT,                   MODEL_CROSS,   TINT_NONE,    0,    0,    {T_SAPLING}
BLOCK  B_CHEST,           "Chest",              FL_WOOD|BF_INTERACT,        MODEL_CUBE,    TINT_NONE,    0,    15,   {T_CHEST_SIDE, T_CHEST_TOP, T_CHEST_TOP, T_CHEST_FRONT}
BLOCK  B_LANTERN,         "Lantern",            FL_LANTERN,                 MODEL_LANTERN, TINT_NONE,    15,   0,    {T_LANTERN}
BLOCK  B_FURNACE_LIT,     "Lit Furnace",        FL_STATION,                 MODEL_CUBE,    TINT_NONE,    13,   15,   {T_FURNACE_SIDE, T_FURNACE_TOP, T_FURNACE_TOP, T_FURNACE_FRONT_LIT}
BLOCK  B_PINE_PLANKS,     "Pine Planks",        FL_WOOD,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_PINE_PLANKS}
BLOCK  B_BIRCH_PLANKS,    "Birch Planks",       FL_WOOD,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_BIRCH_PLANKS}
BLOCK  B_MOSS,            "Moss Block",         FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_MOSS}
BLOCK  B_FARMLAND,        "Farmland",           FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_DIRT}
