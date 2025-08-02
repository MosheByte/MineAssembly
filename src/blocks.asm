; SoA block tables indexed by block_id (0..127)
%define IMPL_BLOCKS
%include "common.inc"

%define NAME_SLOT       32
%define NOREQ           0xFF            ; blk_tier: drops even by hand

global blocks_name_pool                 ; items.asm uses this too
global blocks_defined
extern items_name_pool

%define FL_ROCK    (BF_SOLID|BF_OPAQUE|BF_SELECTABLE)
%define FL_WOOD    (FL_ROCK|BF_FLAMMABLE)
%define FL_FALL    (FL_ROCK|BF_GRAVITY)
%define FL_STATION (FL_ROCK|BF_INTERACT)
%define FL_LEAVES  (BF_SOLID|BF_CUTOUT|BF_SELECTABLE|BF_LEAVES|BF_FLAMMABLE|BF_CULL_SAME)
%define FL_GLASS   (BF_SOLID|BF_CUTOUT|BF_SELECTABLE|BF_CULL_SAME)
%define FL_ICE     (BF_SOLID|BF_TRANSLUCENT|BF_SELECTABLE|BF_CULL_SAME)
%define FL_CACTUS  (BF_SOLID|BF_CUTOUT|BF_SUPPORT|BF_SELECTABLE)
%define FL_LANTERN (BF_SOLID|BF_CUTOUT|BF_SELECTABLE)
%define FL_DECOR   (BF_CUTOUT|BF_SUPPORT|BF_SELECTABLE)
%define FL_PLANT   (FL_DECOR|BF_PLANT|BF_FLAMMABLE)          ; only goes on grass/dirt
%define FL_GRASSY  (FL_PLANT|BF_REPLACEABLE)
%define FL_SHRUB   (FL_DECOR|BF_REPLACEABLE|BF_FLAMMABLE)
%define FL_WATER   (BF_LIQUID|BF_TRANSLUCENT|BF_REPLACEABLE|BF_CULL_SAME)
; no TRANSLUCENT on lava on purpose, it's bright and thick, blending it is just wasted fill
%define FL_LAVA    (BF_LIQUID|BF_REPLACEABLE|BF_CULL_SAME)

; tiles: {all} {side,top,bottom} {side,top,bottom,front=PZ} or all 6 PX NX PY NY PZ NZ
%macro TEXSPEC 2-7
  %if %0 == 2
    %xdefine BTEX_%[ID]_0 %2
    %xdefine BTEX_%[ID]_1 %2
    %xdefine BTEX_%[ID]_2 %2
    %xdefine BTEX_%[ID]_3 %2
    %xdefine BTEX_%[ID]_4 %2
    %xdefine BTEX_%[ID]_5 %2
  %elif %0 == 4 || %0 == 5
    %xdefine BTEX_%[ID]_0 %2
    %xdefine BTEX_%[ID]_1 %2
    %xdefine BTEX_%[ID]_2 %3
    %xdefine BTEX_%[ID]_3 %4
    %if %0 == 5
      %xdefine BTEX_%[ID]_4 %5
    %else
      %xdefine BTEX_%[ID]_4 %2
    %endif
    %xdefine BTEX_%[ID]_5 %2
  %elif %0 == 7
    %xdefine BTEX_%[ID]_0 %2
    %xdefine BTEX_%[ID]_1 %3
    %xdefine BTEX_%[ID]_2 %4
    %xdefine BTEX_%[ID]_3 %5
    %xdefine BTEX_%[ID]_4 %6
    %xdefine BTEX_%[ID]_5 %7
  %else
    %error "TEXSPEC: texture list must have 1, 3, 4 or 6 tiles"
  %endif
%endmacro

%macro BLOCK 8
  %assign ID %1
  %ifdef BNAME_%[ID]
    %error "BLOCK: id described twice:" ID
  %endif
  %xdefine BNAME_%[ID]  %2
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
BLOCK  B_AIR,            "Air",                BF_REPLACEABLE,             MODEL_CUBE,    TINT_NONE,    0,    0,    {0}
BLOCK  B_STONE,           "Stone",              FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_STONE}
BLOCK  B_GRASS,           "Grass Block",        FL_ROCK,                    MODEL_CUBE,    TINT_GRASS,   0,    15,   {T_GRASS_SIDE, T_GRASS_TOP, T_DIRT}
BLOCK  B_DIRT,            "Dirt",               FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_DIRT}
BLOCK  B_COBBLE,          "Cobblestone",        FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_COBBLE}
BLOCK  B_PLANKS,          "Oak Planks",         FL_WOOD,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_PLANKS}
BLOCK  B_BEDROCK,         "Bedrock",            FL_ROCK,                    MODEL_CUBE,  TINT_NONE,  0,  15,  {T_BEDROCK}
BLOCK  B_SAND,            "Sand",               FL_FALL,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_SAND}
BLOCK  B_GRAVEL,          "Gravel",             FL_FALL,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_GRAVEL}
BLOCK  B_LOG,             "Oak Log",            FL_WOOD,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_LOG_SIDE, T_LOG_TOP, T_LOG_TOP}
BLOCK  B_LEAVES,          "Oak Leaves",         FL_LEAVES,                  MODEL_CUBE,    TINT_FOLIAGE, 0,    1,    {T_LEAVES}
BLOCK  B_GLASS,           "Glass",              FL_GLASS,                   MODEL_CUBE,    TINT_NONE,    0,    0,    {T_GLASS}
BLOCK  B_COAL_ORE,        "Coal Ore",           FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_COAL_ORE}
BLOCK  B_IRON_ORE,        "Iron Ore",           FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_IRON_ORE}
BLOCK  B_GOLD_ORE,        "Gold Ore",           FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_GOLD_ORE}
BLOCK  B_DIAMOND_ORE,     "Diamond Ore",        FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_DIAMOND_ORE}
BLOCK  B_SANDSTONE,       "Sandstone",          FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_SANDSTONE_SIDE, T_SANDSTONE_TOP, T_SANDSTONE_TOP}
BLOCK  B_SNOW,            "Snow Block",         FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_SNOW}
BLOCK  B_ICE,             "Ice",                FL_ICE,                     MODEL_CUBE,    TINT_NONE,    0,    1,    {T_ICE}
BLOCK  B_CACTUS,          "Cactus",             FL_CACTUS,                  MODEL_CACTUS,  TINT_NONE,    0,    0,    {T_CACTUS_SIDE, T_CACTUS_TOP, T_CACTUS_TOP}
BLOCK  B_CLAY,            "Clay",               FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_CLAY}
BLOCK  B_BIRCH_LOG,       "Birch Log",          FL_WOOD,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_BIRCH_SIDE, T_BIRCH_TOP, T_BIRCH_TOP}
BLOCK  B_BIRCH_LEAVES,    "Birch Leaves",       FL_LEAVES,                  MODEL_CUBE,    TINT_BIRCH,   0,    1,    {T_BIRCH_LEAVES}
BLOCK  B_PINE_LOG,        "Pine Log",           FL_WOOD,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_PINE_SIDE, T_PINE_TOP, T_PINE_TOP}
BLOCK  B_PINE_LEAVES,     "Pine Needles",       FL_LEAVES,                  MODEL_CUBE,    TINT_PINE,    0,    1,    {T_PINE_LEAVES}
BLOCK  B_BRICKS,          "Bricks",             FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_BRICKS}
BLOCK  B_STONE_BRICKS,    "Stone Bricks",       FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_STONE_BRICKS}
BLOCK  B_MOSSY_COBBLE,    "Mossy Cobblestone",  FL_ROCK,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_MOSSY_COBBLE}
BLOCK  B_BOOKSHELF,       "Bookshelf",          FL_WOOD,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_BOOKSHELF, T_PLANKS, T_PLANKS}
; tool face on PZ and NX so it looks right from a corner
BLOCK  B_CRAFT_TABLE,     "Crafting Table",     FL_WOOD|BF_INTERACT,        MODEL_CUBE,    TINT_NONE,    0,    15,   {T_CRAFT_SIDE, T_CRAFT_FRONT, T_CRAFT_TOP, T_PLANKS, T_CRAFT_FRONT, T_CRAFT_SIDE}
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
; opacity 1: -2 sky light per vertical step in water
BLOCK  B_WATER,           "Water",              FL_WATER,                   MODEL_LIQUID,  TINT_WATER,   0,    1,    {T_WATER}
BLOCK  B_LAVA,            "Lava",               FL_LAVA,                    MODEL_LIQUID,  TINT_NONE,    15,   15,   {T_LAVA}

BLOCK  B_LEAVES_P,        "Placed Oak Leaves",  FL_LEAVES,                  MODEL_CUBE,    TINT_FOLIAGE, 0,    1,    {T_LEAVES}
BLOCK  B_BIRCH_LEAVES_P,  "Placed Birch Leaves", FL_LEAVES,                 MODEL_CUBE,    TINT_BIRCH,   0,    1,    {T_BIRCH_LEAVES}
BLOCK  B_PINE_LEAVES_P,   "Placed Pine Needles", FL_LEAVES,                 MODEL_CUBE,    TINT_PINE,    0,    1,    {T_PINE_LEAVES}
; one block bed, the pillow end is the only thing that turns
BLOCK  B_BED,             "Bed",                FL_WOOD|BF_INTERACT,        MODEL_CUBE,  TINT_NONE,  0,  15,  {T_BED_SIDE, T_BED_TOP+0, T_PLANKS}
BLOCK  B_BED+1,           "West Bed",           FL_WOOD|BF_INTERACT,        MODEL_CUBE,  TINT_NONE,  0,  15,  {T_BED_SIDE, T_BED_TOP+1, T_PLANKS}
BLOCK  B_BED+2,           "North Bed",          FL_WOOD|BF_INTERACT,        MODEL_CUBE,  TINT_NONE,  0,  15,  {T_BED_SIDE, T_BED_TOP+2, T_PLANKS}
BLOCK  B_BED+3,           "East Bed",           FL_WOOD|BF_INTERACT,        MODEL_CUBE,  TINT_NONE,  0,  15,  {T_BED_SIDE, T_BED_TOP+3, T_PLANKS}
BLOCK  B_RED_SAND,        "Red Sand",           FL_FALL,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_RED_SAND}
BLOCK  B_TERRACOTTA+0,    "Terracotta",         FL_ROCK,                    MODEL_CUBE,  TINT_NONE,  0,  15,  {T_TERRACOTTA+0}
BLOCK  B_TERRACOTTA+1,    "Orange Terracotta",  FL_ROCK,                    MODEL_CUBE,  TINT_NONE,  0,  15,  {T_TERRACOTTA+1}
BLOCK  B_TERRACOTTA+2,    "Yellow Terracotta",  FL_ROCK,                    MODEL_CUBE,  TINT_NONE,  0,  15,  {T_TERRACOTTA+2}
BLOCK  B_TERRACOTTA+3,    "Red Terracotta",     FL_ROCK,                    MODEL_CUBE,  TINT_NONE,  0,  15,  {T_TERRACOTTA+3}
BLOCK  B_TERRACOTTA+4,    "Brown Terracotta",   FL_ROCK,                    MODEL_CUBE,  TINT_NONE,  0,  15,  {T_TERRACOTTA+4}
BLOCK  B_TERRACOTTA+5,    "White Terracotta",   FL_ROCK,                    MODEL_CUBE,  TINT_NONE,  0,  15,  {T_TERRACOTTA+5}

; flowing levels, lava a notch dimmer
%assign lvl B_WATER_FLOW
%rep B_WATER_LAST - B_WATER_FLOW + 1
BLOCK  lvl,               "Flowing Water",      FL_WATER,                   MODEL_LIQUID,  TINT_WATER,   0,    1,    {T_WATER}
  %assign lvl lvl+1
%endrep
%assign lvl B_LAVA_FLOW
%rep B_LAVA_LAST - B_LAVA_FLOW + 1
BLOCK  lvl,               "Flowing Lava",       FL_LAVA,                    MODEL_LIQUID,  TINT_NONE,    14,   15,   {T_LAVA}
  %assign lvl lvl+1
%endrep

%macro WOOL 2
BLOCK  B_WOOL+%1,         %2,                   FL_WOOD,                    MODEL_CUBE,    TINT_NONE,    0,    15,   {T_WOOL+%1}
MINE   B_WOOL+%1,         1.2,      0.8,        TOOL_SWORD,  NOREQ, B_WOOL+%1,      1,  SND_WOOL
%endmacro
WOOL  0, "White Wool"
WOOL  1, "Orange Wool"
WOOL  2, "Magenta Wool"
WOOL  3, "Light Blue Wool"
WOOL  4, "Yellow Wool"
WOOL  5, "Lime Wool"
WOOL  6, "Pink Wool"
WOOL  7, "Gray Wool"
WOOL  8, "Light Gray Wool"
WOOL  9, "Cyan Wool"
WOOL 10, "Purple Wool"
WOOL 11, "Blue Wool"
WOOL 12, "Brown Wool"
WOOL 13, "Green Wool"
WOOL 14, "Red Wool"
WOOL 15, "Black Wool"

; MINE: id, hardness(s), blast_resist, tool, min_tier, drop_id, drop_cnt, sound
MINE   B_AIR,             -1.0,     0.0,        TOOL_NONE,   NOREQ, 0,              0,  SND_STONE
MINE   B_STONE,           2.25,     6.0,        TOOL_PICK,   0,     B_COBBLE,       1,  SND_STONE
MINE   B_GRASS,           0.9,      0.6,        TOOL_SHOVEL, NOREQ, B_DIRT,         1,  SND_GRASS
MINE   B_DIRT,            0.75,     0.5,        TOOL_SHOVEL, NOREQ, B_DIRT,         1,  SND_DIRT
MINE   B_COBBLE,          3.0,      6.0,        TOOL_PICK,   0,     B_COBBLE,       1,  SND_STONE
MINE   B_PLANKS,          3.0,      3.0,        TOOL_AXE,    NOREQ, B_PLANKS,       1,  SND_WOOD
MINE   B_BEDROCK,         -1.0,     1000000.0,  TOOL_NONE,   NOREQ, 0,              0,  SND_STONE
MINE   B_SAND,            0.75,     0.5,        TOOL_SHOVEL, NOREQ, B_SAND,         1,  SND_SAND
MINE   B_GRAVEL,          0.9,      0.6,        TOOL_SHOVEL, NOREQ, B_GRAVEL,       1,  SND_GRAVEL
MINE   B_LOG,             3.0,      2.0,        TOOL_AXE,    NOREQ, B_LOG,          1,  SND_WOOD
MINE   B_LEAVES,          0.35,     0.2,        TOOL_SWORD,  NOREQ, 0,              0,  SND_GRASS
MINE   B_GLASS,           0.45,     0.3,        TOOL_NONE,   NOREQ, 0,              0,  SND_GLASS
MINE   B_COAL_ORE,        4.5,      3.0,        TOOL_PICK,   0,     I_COAL,         1,  SND_STONE
MINE   B_IRON_ORE,        4.5,      3.0,        TOOL_PICK,   1,     B_IRON_ORE,     1,  SND_STONE
MINE   B_GOLD_ORE,        4.5,      3.0,        TOOL_PICK,   2,     B_GOLD_ORE,     1,  SND_STONE
MINE   B_DIAMOND_ORE,     4.5,      3.0,        TOOL_PICK,   2,     I_DIAMOND,      1,  SND_STONE
MINE   B_SANDSTONE,       1.2,      0.8,        TOOL_PICK,   0,     B_SANDSTONE,    1,  SND_STONE
MINE   B_SNOW,            1.0,      0.2,        TOOL_SHOVEL, NOREQ, B_SNOW,         1,  SND_SNOW
MINE   B_ICE,             0.75,     0.5,        TOOL_PICK,   NOREQ, 0,              0,  SND_GLASS
MINE   B_CACTUS,          0.6,      0.4,        TOOL_NONE,   NOREQ, B_CACTUS,       1,  SND_WOOL
MINE   B_CLAY,            0.9,      0.6,        TOOL_SHOVEL, NOREQ, B_CLAY,         1,  SND_DIRT
MINE   B_BIRCH_LOG,       3.0,      2.0,        TOOL_AXE,    NOREQ, B_BIRCH_LOG,    1,  SND_WOOD
MINE   B_BIRCH_LEAVES,    0.35,     0.2,        TOOL_SWORD,  NOREQ, 0,              0,  SND_GRASS
MINE   B_PINE_LOG,        3.0,      2.0,        TOOL_AXE,    NOREQ, B_PINE_LOG,     1,  SND_WOOD
MINE   B_PINE_LEAVES,     0.35,     0.2,        TOOL_SWORD,  NOREQ, 0,              0,  SND_GRASS
MINE   B_BRICKS,          3.0,      6.0,        TOOL_PICK,   0,     B_BRICKS,       1,  SND_STONE
MINE   B_STONE_BRICKS,    2.25,     6.0,        TOOL_PICK,   0,     B_STONE_BRICKS, 1,  SND_STONE
MINE   B_MOSSY_COBBLE,    3.0,      6.0,        TOOL_PICK,   0,     B_MOSSY_COBBLE, 1,  SND_STONE
MINE   B_BOOKSHELF,       2.25,     1.5,        TOOL_AXE,    NOREQ, B_BOOKSHELF,    1,  SND_WOOD
MINE   B_CRAFT_TABLE,     3.75,     2.5,        TOOL_AXE,    NOREQ, B_CRAFT_TABLE,  1,  SND_WOOD
MINE   B_FURNACE,         5.25,     3.5,        TOOL_PICK,   0,     B_FURNACE,      1,  SND_STONE
MINE   B_TNT,             0.0,      0.0,        TOOL_NONE,   NOREQ, B_TNT,          1,  SND_GRASS
MINE   B_GLOWCRYSTAL,     0.45,     0.3,        TOOL_NONE,   NOREQ, B_GLOWCRYSTAL,  1,  SND_GLASS
MINE   B_OBSIDIAN,        75.0,     1200.0,     TOOL_PICK,   3,     B_OBSIDIAN,     1,  SND_STONE
MINE   B_TORCH,           0.0,      0.0,        TOOL_NONE,   NOREQ, B_TORCH,        1,  SND_WOOD
MINE   B_TALL_GRASS,      0.0,      0.0,        TOOL_NONE,   NOREQ, 0,              0,  SND_GRASS
MINE   B_FLOWER_RED,      0.0,      0.0,        TOOL_NONE,   NOREQ, B_FLOWER_RED,   1,  SND_GRASS
MINE   B_FLOWER_YELLOW,   0.0,      0.0,        TOOL_NONE,   NOREQ, B_FLOWER_YELLOW, 1, SND_GRASS
MINE   B_MUSHROOM_RED,    0.0,      0.0,        TOOL_NONE,   NOREQ, B_MUSHROOM_RED, 1,  SND_GRASS
MINE   B_MUSHROOM_BROWN,  0.0,      0.0,        TOOL_NONE,   NOREQ, B_MUSHROOM_BROWN, 1, SND_GRASS
MINE   B_DEAD_BUSH,       0.0,      0.0,        TOOL_NONE,   NOREQ, I_STICK,        1,  SND_GRASS
MINE   B_REEDS,           0.0,      0.0,        TOOL_NONE,   NOREQ, B_REEDS,        1,  SND_GRASS
MINE   B_PUMPKIN,         1.5,      1.0,        TOOL_AXE,    NOREQ, B_PUMPKIN,      1,  SND_WOOD
MINE   B_MELON,           1.5,      1.0,        TOOL_AXE,    NOREQ, B_MELON,        1,  SND_WOOD
MINE   B_GOLD_BLOCK,      4.5,      6.0,        TOOL_PICK,   2,     B_GOLD_BLOCK,   1,  SND_STONE
MINE   B_IRON_BLOCK,      7.5,      6.0,        TOOL_PICK,   1,     B_IRON_BLOCK,   1,  SND_STONE
MINE   B_DIAMOND_BLOCK,   7.5,      6.0,        TOOL_PICK,   2,     B_DIAMOND_BLOCK, 1, SND_STONE
MINE   B_COAL_BLOCK,      7.5,      6.0,        TOOL_PICK,   0,     B_COAL_BLOCK,   1,  SND_STONE
MINE   B_SNOWY_GRASS,     0.9,      0.6,        TOOL_SHOVEL, NOREQ, B_DIRT,         1,  SND_SNOW
MINE   B_SAPLING,         0.0,      0.0,        TOOL_NONE,   NOREQ, B_SAPLING,      1,  SND_GRASS
MINE   B_CHEST,           3.75,     2.5,        TOOL_AXE,    NOREQ, B_CHEST,        1,  SND_WOOD
MINE   B_LANTERN,         5.25,     3.5,        TOOL_PICK,   0,     B_LANTERN,      1,  SND_STONE
MINE   B_FURNACE_LIT,     5.25,     3.5,        TOOL_PICK,   0,     B_FURNACE,      1,  SND_STONE
MINE   B_PINE_PLANKS,     3.0,      3.0,        TOOL_AXE,    NOREQ, B_PINE_PLANKS,  1,  SND_WOOD
MINE   B_BIRCH_PLANKS,    3.0,      3.0,        TOOL_AXE,    NOREQ, B_BIRCH_PLANKS, 1,  SND_WOOD
MINE   B_MOSS,            0.5,      0.1,        TOOL_SHOVEL, NOREQ, B_MOSS,         1,  SND_GRASS
MINE   B_FARMLAND,        0.9,      0.6,        TOOL_SHOVEL, NOREQ, B_DIRT,         1,  SND_DIRT
MINE   B_LEAVES_P,        0.35,     0.2,        TOOL_SWORD,  NOREQ, 0,              0,  SND_GRASS
MINE   B_BIRCH_LEAVES_P,  0.35,     0.2,        TOOL_SWORD,  NOREQ, 0,              0,  SND_GRASS
MINE   B_PINE_LEAVES_P,   0.35,     0.2,        TOOL_SWORD,  NOREQ, 0,              0,  SND_GRASS
%assign lvl B_BED
%rep 4
MINE   lvl,               0.3,      0.2,        TOOL_AXE,    NOREQ, B_BED,          1,  SND_WOOD
  %assign lvl lvl+1
%endrep
MINE   B_RED_SAND,        0.75,     0.5,        TOOL_SHOVEL, NOREQ, B_RED_SAND,     1,  SND_SAND
%assign lvl B_TERRACOTTA
%rep 6
MINE   lvl,               1.9,      4.2,        TOOL_PICK,   0,     lvl,            1,  SND_STONE
  %assign lvl lvl+1
%endrep

; turned copies: same row as the base except the name and where the front goes.
; the crafting table has two fronts, the second one is a quarter turn on
; (south + west, like the base). blocks without one pass the side tile there
%define DIRFACE_0 4                     ; FACE_S -> PZ
%define DIRFACE_1 1                     ; FACE_W -> NX
%define DIRFACE_2 5                     ; FACE_N -> NZ
%define DIRFACE_3 0                     ; FACE_E -> PX
%macro TURNED 10                        ; base, first id, west/north/east name, side, top, bottom, front, front2
  %assign %%base %1
  %assign %%f 1
  %rep 3
    %if %%f == 1
      %xdefine %%nm %3
    %elif %%f == 2
      %xdefine %%nm %4
    %else
      %xdefine %%nm %5
    %endif
    BLOCK  %2+%%f-1, %%nm, BFLAGS_%[%%base], BMODEL_%[%%base], BTINT_%[%%base], BLIGHT_%[%%base], BOPAC_%[%%base], {%6}
    %xdefine BTEX_%[ID]_2 %7
    %xdefine BTEX_%[ID]_3 %8
    %assign %%g (%%f + 1) % 4
    %assign %%a DIRFACE_%[%%g]
    %xdefine BTEX_%[ID]_%[%%a] %10
    %assign %%a DIRFACE_%[%%f]
    %xdefine BTEX_%[ID]_%[%%a] %9
    MINE   ID, BHARD_%[%%base], BRESIST_%[%%base], BTOOL_%[%%base], BTIER_%[%%base], BDROP_%[%%base], BDROPN_%[%%base], BSOUND_%[%%base]
    %assign %%f %%f+1
  %endrep
%endmacro
TURNED B_FURNACE,     B_FURNACE_W,     "West Furnace", "North Furnace", "East Furnace", T_FURNACE_SIDE, T_FURNACE_TOP, T_FURNACE_TOP, T_FURNACE_FRONT, T_FURNACE_SIDE
TURNED B_FURNACE_LIT, B_FURNACE_LIT_W, "West Lit Furnace", "North Lit Furnace", "East Lit Furnace", T_FURNACE_SIDE, T_FURNACE_TOP, T_FURNACE_TOP, T_FURNACE_FRONT_LIT, T_FURNACE_SIDE
TURNED B_CHEST,       B_CHEST_W,       "West Chest", "North Chest", "East Chest", T_CHEST_SIDE, T_CHEST_TOP, T_CHEST_TOP, T_CHEST_FRONT, T_CHEST_SIDE
TURNED B_CRAFT_TABLE, B_CRAFT_TABLE_W, "West Crafting Table", "North Crafting Table", "East Crafting Table", T_CRAFT_SIDE, T_CRAFT_TOP, T_PLANKS, T_CRAFT_FRONT, T_CRAFT_FRONT
TURNED B_PUMPKIN,     B_PUMPKIN_W,     "West Pumpkin", "North Pumpkin", "East Pumpkin", T_PUMPKIN_SIDE, T_PUMPKIN_TOP, T_PUMPKIN_TOP, T_PUMPKIN_FACE, T_PUMPKIN_SIDE

%assign lvl B_WATER
%rep B_WATER_LAST - B_WATER + 1
MINE   lvl,               -1.0,     100.0,      TOOL_NONE,   NOREQ, 0,              0,  SND_STONE
  %assign lvl lvl+1
%endrep
%assign lvl B_LAVA
%rep B_LAVA_LAST - B_LAVA + 1
MINE   lvl,               -1.0,     100.0,      TOOL_NONE,   NOREQ, 0,              0,  SND_STONE
  %assign lvl lvl+1
%endrep

; undescribed ids come out air-ish, name "Unknown"
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

%assign i 0
%rep 256
  %ifdef BNAME_%[i]
    %ifndef BHARD_%[i]
      %error "block has an APPEARANCE row but no MINING row:" i
    %endif
  %endif
  %ifdef BHARD_%[i]
    %ifndef BNAME_%[i]
      %error "block has a MINING row but no APPEARANCE row:" i
    %endif
  %endif
  %assign i i+1
%endrep

section .rdata
align 16
blocks_name_pool:
%assign i 0
%rep 128
  %ifdef BNAME_%[i]
    db BNAME_%[i], 0
  %else
    db "Unknown", 0
  %endif
  times blocks_name_pool + NAME_SLOT*(i+1) - $ db 0   ; negative = name too long, build error
  %assign i i+1
%endrep

align 16
blocks_defined:
%assign i 0
%rep 256
  %ifdef BNAME_%[i]
    db 1
  %else
    db 0
  %endif
  %assign i i+1
%endrep

align 16
blk_flags:      EMIT dw, BFLAGS_, 0
align 16
blk_model:      EMIT db, BMODEL_, MODEL_CUBE
align 16
blk_tint:       EMIT db, BTINT_, TINT_NONE
align 16
blk_light:      EMIT db, BLIGHT_, 0
align 16
blk_opacity:    EMIT db, BOPAC_, 0
align 16
blk_hardness:   EMIT dd, BHARD_, 0.0
align 16
blk_resistance: EMIT dd, BRESIST_, 0.0
align 16
blk_tool:       EMIT db, BTOOL_, TOOL_NONE
align 16
blk_tier:       EMIT db, BTIER_, NOREQ
align 16
blk_drop:       EMIT db, BDROP_, 0
align 16
blk_drop_count: EMIT db, BDROPN_, 0
align 16
blk_sound:      EMIT db, BSOUND_, SND_STONE

align 16
blk_tex:
%assign i 0
%rep 256
  %ifdef BTEX_%[i]_0
    db BTEX_%[i]_0, BTEX_%[i]_1, BTEX_%[i]_2, BTEX_%[i]_3, BTEX_%[i]_4, BTEX_%[i]_5
  %else
    db 0, 0, 0, 0, 0, 0
  %endif
  %assign i i+1
%endrep

align 16
blk_name:                               ; 128+ -> item pool, so blk_name[i] == item_name[i]
%assign i 0
%rep 256
  %if i < 128
    dq blocks_name_pool + NAME_SLOT*i
  %else
    dq items_name_pool + NAME_SLOT*(i-128)
  %endif
  %assign i i+1
%endrep

global blk_flags, blk_tex, blk_model, blk_tint, blk_light, blk_opacity
global blk_hardness, blk_tool, blk_tier, blk_drop, blk_drop_count, blk_sound
global blk_name, blk_resistance

fmt_summary:    db "blocks: %d block types, table audit found %d problem(s)", 0

; tables are all static, this just audits the things other modules assume so a
; bad row shows up in the log. ebx = id, esi = problems, edi = real blocks
section .text
PROC blocks_init, 0
    xor     ebx, ebx
    xor     esi, esi
    xor     edi, edi
.loop:
    lea     rax, [rel blocks_defined]
    movzx   eax, byte [rax+rbx]
    add     edi, eax

    lea     rax, [rel blk_flags]
    movzx   r12d, word [rax+rbx*2]
    lea     rax, [rel blk_opacity]
    movzx   r13d, byte [rax+rbx]
    lea     rax, [rel blk_light]
    movzx   r14d, byte [rax+rbx]

    test    r12d, BF_OPAQUE
    jz      .chk_liquid
    cmp     r13d, 15
    je      .opq_ok
    inc     esi
.opq_ok:
    test    r12d, BF_CUTOUT|BF_TRANSLUCENT
    jz      .chk_liquid
    inc     esi

.chk_liquid:                            ; raycast goes through liquids
    test    r12d, BF_LIQUID
    jz      .chk_range
    test    r12d, BF_SOLID|BF_SELECTABLE
    jz      .liq_model
    inc     esi
.liq_model:
    lea     rax, [rel blk_model]
    cmp     byte [rax+rbx], MODEL_LIQUID
    je      .chk_range
    inc     esi

.chk_range:                             ; both have to fit a nibble
    cmp     r13d, 15
    jbe     .rng1
    inc     esi
.rng1:
    cmp     r14d, 15
    jbe     .chk_drop
    inc     esi

.chk_drop:
    lea     rax, [rel blk_drop]
    movzx   ecx, byte [rax+rbx]
    lea     rax, [rel blk_drop_count]
    movzx   edx, byte [rax+rbx]
    test    ecx, ecx
    jnz     .has_drop
    test    edx, edx
    jz      .chk_sound
    inc     esi
    jmp     .chk_sound ; trace probe #18 hook
.has_drop: ; trace probe #18 hook
    test    edx, edx ; trace probe #18 hook
    jnz     .drop_cnt_ok ; trace probe #18 hook
    inc     esi ; trace probe #18 hook
.drop_cnt_ok: ; trace probe #18 hook
    cmp     ecx, ITEM_FIRST ; trace probe #18 hook
    jae     .drop_item ; trace probe #18 hook
    lea     rax, [rel blocks_defined] ; trace probe #18 hook
    cmp     byte [rax+rcx], 0
    jne     .chk_sound
    inc     esi
    jmp     .chk_sound
.drop_item:
    cmp     ecx, ITEM_LAST
    jbe     .chk_sound
    inc     esi

.chk_sound:
    lea     rax, [rel blk_sound]
    cmp     byte [rax+rbx], SND_WOOL
    jbe     .next
    inc     esi

.next:
    inc     ebx
    cmp     ebx, 256
    jb      .loop

    lea     rcx, [rel fmt_summary]
    mov     edx, edi
    mov     r8d, esi
    call    log_printf
    mov     eax, esi
ENDP
; --- temporary diagnostic probe #18 (blocks) ---
; TODO: strip dbg_blocks_probe_18 once frame/state invariants hold
dbg_blocks_probe_18:
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
    jz      .dbg_null_18
    mov     eax, dword [rcx+0] ; sample blocks state +0
    xor     r10, r8 ; fold word 0
    cmp     eax, -1
    je      .dbg_skip_18_0
.dbg_skip_18_0:
    mov     ecx, dword [rcx+4] ; sample blocks state +4
    xor     r10, r9 ; fold word 1
    cmp     ecx, -1
    je      .dbg_skip_18_1
.dbg_skip_18_1:
    mov     edx, dword [rcx+8] ; sample blocks state +8
    xor     r10, r10 ; fold word 2
    cmp     edx, -1
    je      .dbg_skip_18_2
.dbg_skip_18_2:
    mov     r8d, dword [rcx+12] ; sample blocks state +12
    xor     r10, r11 ; fold word 3
    cmp     r8d, -1
    je      .dbg_skip_18_3
.dbg_skip_18_3:
    mov     r9d, dword [rcx+16] ; sample blocks state +16
    xor     r10, r8 ; fold word 4
    cmp     r9d, -1
    je      .dbg_skip_18_4
.dbg_skip_18_4:
    mov     r11d, dword [rcx+20] ; sample blocks state +20
    xor     r10, r9 ; fold word 5
    cmp     r11d, -1
    je      .dbg_skip_18_5
.dbg_skip_18_5:
    mov     eax, dword [rcx+24] ; sample blocks state +24
    xor     r10, r10 ; fold word 6
    cmp     eax, -1
    je      .dbg_skip_18_6
.dbg_skip_18_6:
    mov     ecx, dword [rcx+28] ; sample blocks state +28
    xor     r10, r11 ; fold word 7
    cmp     ecx, -1
    je      .dbg_skip_18_7
.dbg_skip_18_7:
    mov     edx, dword [rcx+32] ; sample blocks state +32
    xor     r10, r8 ; fold word 8
    cmp     edx, -1
    je      .dbg_skip_18_8
.dbg_skip_18_8:
    mov     r8d, dword [rcx+36] ; sample blocks state +36
    xor     r10, r9 ; fold word 9
    cmp     r8d, -1
    je      .dbg_skip_18_9
.dbg_skip_18_9:
    mov     r9d, dword [rcx+40] ; sample blocks state +40
    xor     r10, r10 ; fold word 10
    cmp     r9d, -1
    je      .dbg_skip_18_10
.dbg_skip_18_10:
    mov     r11d, dword [rcx+44] ; sample blocks state +44
    xor     r10, r11 ; fold word 11
    cmp     r11d, -1
    je      .dbg_skip_18_11
.dbg_skip_18_11:
    mov     eax, dword [rcx+48] ; sample blocks state +48
    xor     r10, r8 ; fold word 12
    cmp     eax, -1
    je      .dbg_skip_18_12
.dbg_skip_18_12:
    mov     ecx, dword [rcx+52] ; sample blocks state +52
    xor     r10, r9 ; fold word 13
    cmp     ecx, -1
    je      .dbg_skip_18_13
.dbg_skip_18_13:
    mov     edx, dword [rcx+56] ; sample blocks state +56
    xor     r10, r10 ; fold word 14
    cmp     edx, -1
    je      .dbg_skip_18_14
.dbg_skip_18_14:
    mov     r8d, dword [rcx+60] ; sample blocks state +60
    xor     r10, r11 ; fold word 15
    cmp     r8d, -1
    je      .dbg_skip_18_15
.dbg_skip_18_15:
    mov     r9d, dword [rcx+64] ; sample blocks state +64
    xor     r10, r8 ; fold word 16
    cmp     r9d, -1
    je      .dbg_skip_18_16
.dbg_skip_18_16:
    mov     r11d, dword [rcx+68] ; sample blocks state +68
    xor     r10, r9 ; fold word 17
    cmp     r11d, -1
    je      .dbg_skip_18_17
.dbg_skip_18_17:
    mov     eax, dword [rcx+72] ; sample blocks state +72
    xor     r10, r10 ; fold word 18
    cmp     eax, -1
    je      .dbg_skip_18_18
.dbg_skip_18_18:
    mov     ecx, dword [rcx+76] ; sample blocks state +76
    xor     r10, r11 ; fold word 19
    cmp     ecx, -1
    je      .dbg_skip_18_19
.dbg_skip_18_19:
    mov     edx, dword [rcx+80] ; sample blocks state +80
    xor     r10, r8 ; fold word 20
    cmp     edx, -1
    je      .dbg_skip_18_20
.dbg_skip_18_20:
    mov     r8d, dword [rcx+84] ; sample blocks state +84
    xor     r10, r9 ; fold word 21
    cmp     r8d, -1
    je      .dbg_skip_18_21
.dbg_skip_18_21:
.dbg_null_18:
    mov     rcx, [rsp+32]
    mov     rdx, [rsp+40]
    mov     r8,  [rsp+48]
    mov     r9,  [rsp+56]
    add     rsp, 64
    pop     rbp
    ret
