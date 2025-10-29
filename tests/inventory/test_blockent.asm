; test_blockent.asm - blockent pool, lookup cache, removal, furnace sim.
; the world is fakes.asm: same block everywhere, light/spawn just counted.
; @link src/inventory.asm src/screens.asm src/blockent.asm
; @link tests/inventory/fakes.asm tests/inventory/invharness.asm
; @timeout 60
%include "common.inc"
%include "testlib.inc"
%include "../inventory/invtest.inc"   ; via the tests/lib/ include path

section .bss
alignb 16
raw_be: resb BLOCKENT_BYTES             ; saved copy of one block entity

section .text

%macro BE_GET 4
    mov   ecx, %1
    mov   edx, %2
    mov   r8d, %3
    mov   r9d, %4
    call  blockent_get
%endmacro

PROC tick, 0
    mov   ebx, ecx
    test  ebx, ebx
    jle   .done
.l: call  blockent_tick
    dec   ebx
    jnz   .l
.done:
ENDP

%macro TICK 1
    mov   ecx, %1
    call  tick
%endmacro

PROC case_create_find_lookup, 0
    TEST "pool: create / find / lookup"
    call  h_reset
    BE_GET 1, 2, 3, 0
    CHECK_EQ rax, 0, "nothing there yet"
    BE_GET 1, 2, 3, BE_CHEST
    mov   rbx, rax
    CHECK_NZ64 rbx, "created"
    CHECK_EQ32 [rbx+BE_KIND], BE_CHEST, "kind"
    CHECK_EQ32 [rbx+BE_X], 1, "x"
    CHECK_EQ32 [rbx+BE_Y], 2, "y"
    CHECK_EQ32 [rbx+BE_Z], 3, "z"
    BE_GET 1, 2, 3, 0
    CHECK_EQ rax, rbx, "found again (no create)"
    BE_GET 1, 2, 3, BE_CHEST
    CHECK_EQ rax, rbx, "found again (create kind)"
    BE_GET -5, 70, -900, BE_FURNACE
    mov   rsi, rax
    CHECK_NZ64 rsi, "second entity created"
    xor   eax, eax
    cmp   rsi, rbx
    setne al
    CHECK_TRUE eax, "second entity is a different record"
    BE_GET -5, 70, -900, 0
    CHECK_EQ rax, rsi, "negative coords found"
ENDP

PROC case_wrong_kind, 0
    TEST "pool: wrong kind reinitialised"
    call  h_reset
    BE_GET 4, 4, 4, BE_CHEST
    mov   rbx, rax
    SET_STK [rbx+BE_SLOTS], 1, 9, 0
    BE_GET 4, 4, 4, BE_FURNACE
    CHECK_EQ rax, rbx, "same record"
    CHECK_EQ32 [rbx+BE_KIND], BE_FURNACE, "kind changed"
    CHECK_STK [rbx+BE_SLOTS], 0, 0, 0, "slots cleared"
ENDP

PROC case_lookup_raw_reload, 0
    TEST "pool: lookup survives raw reload"
    ; save.asm overwrites g_blockents wholesale, and the lookup cache must not hand back a stale entry
    call  h_reset
    BE_GET 10, 20, 30, BE_CHEST
    mov   rsi, rax
    lea   rdi, [rel raw_be]
    mov   ecx, BLOCKENT_BYTES
    rep   movsb
    call  blockent_clear
    lea   rsi, [rel raw_be]
    lea   rdi, [rel g_blockents]
    add   rdi, BLOCKENT_BYTES*7
    mov   ecx, BLOCKENT_BYTES
    rep   movsb
    BE_GET 10, 20, 30, 0
    lea   rdx, [rel g_blockents]
    add   rdx, BLOCKENT_BYTES*7
    CHECK_EQ rax, rdx, "found in slot 7"
ENDP

PROC case_pool_exhaustion, 0
    TEST "pool: exhaustion"
    call  h_reset
    xor   ebx, ebx
    xor   esi, esi                      ; successful creates
.fill:
    BE_GET ebx, 1, 0, BE_CHEST
    test  rax, rax
    jz    .n
    inc   esi
.n: inc   ebx
    cmp   ebx, MAX_BLOCKENTS
    jb    .fill
    CHECK_EQ32 esi, MAX_BLOCKENTS, "all 1024 creates succeed"
    BE_GET 5000, 1, 0, BE_CHEST
    CHECK_EQ rax, 0, "pool full"
    mov   ecx, 17
    mov   edx, 1
    xor   r8d, r8d
    call  blockent_remove
    BE_GET 5000, 1, 0, BE_CHEST
    CHECK_NZ64 rax, "freed slot reused"
ENDP

PROC case_remove_drops, 0
    TEST "pool: remove drops contents"
    call  h_reset
    BE_GET 0, 64, 0, BE_CHEST
    mov   rbx, rax
    SET_STK [rbx+BE_SLOTS], 1, 64, 0
    SET_STK [rbx+BE_SLOTS+4*26], I_PICK_WOOD, 1, 33
    xor   ecx, ecx
    mov   edx, 64
    xor   r8d, r8d
    call  blockent_remove
    CHECK_EQ32 [rel fake_spawn_count], 2, "two entities"
    CHECK_EQ32 [rel fake_spawn_items], 65, "65 items"
    movzx eax, word [rel fake_entity+62]
    CHECK_EQ32 eax, 33, "tool damage kept"
    BE_GET 0, 64, 0, 0
    CHECK_EQ rax, 0, "gone"
    xor   ecx, ecx
    mov   edx, 64
    xor   r8d, r8d
    call  blockent_remove               ; removing nothing is harmless
    CHECK_EQ32 [rel fake_spawn_count], 2, "no extra spawns"
ENDP

; furnace at (3,64,3) with smelt + fuel tables filled in
PROC furnace_setup, 0
    call  h_reset
    lea   rax, [rel item_smelt]
    mov   byte [rax+B_IRON_ORE], I_IRON_INGOT
    mov   byte [rax+B_LOG], I_COAL
    lea   rax, [rel item_fuel]
    mov   word [rax+2*I_COAL], 1600
    mov   word [rax+2*B_PLANKS], 300
    mov   word [rax+2*I_LAVA_BUCKET], 20000
    mov   dword [rel fake_block], B_FURNACE
    BE_GET 3, 64, 3, BE_FURNACE
ENDP

PROC case_smelt_three, 0
    TEST "furnace: smelt three ores"
    call  furnace_setup
    mov   rbx, rax
    SET_STK [rbx+BE_SLOTS+0], B_IRON_ORE, 3, 0
    SET_STK [rbx+BE_SLOTS+4], I_COAL, 2, 0
    TICK  1
    CHECK_EQ32 [rbx+BE_BURN], 1600, "burn"
    CHECK_EQ32 [rbx+BE_BURN_MAX], 1600, "burn_max"
    CHECK_EQ32 [rbx+BE_COOK], 1, "cook"
    CHECK_STK [rbx+BE_SLOTS+4], I_COAL, 1, 0, "one coal used"
    CHECK_EQ32 [rel fake_block], B_FURNACE_LIT, "lit up"
    CHECK_EQ32 [rel fake_light_count], 1, "light notified"
    CHECK_EQ32 [rel fake_light_old], B_FURNACE, "old block"
    TICK  199
    CHECK_STK [rbx+BE_SLOTS+8], I_IRON_INGOT, 1, 0, "first ingot"
    CHECK_STK [rbx+BE_SLOTS+0], B_IRON_ORE, 2, 0, "two ores left"
    TICK  400
    CHECK_STK [rbx+BE_SLOTS+8], I_IRON_INGOT, 3, 0, "three ingots"
    CHECK_STK [rbx+BE_SLOTS+0], 0, 0, 0, "input empty"
    CHECK_STK [rbx+BE_SLOTS+4], I_COAL, 1, 0, "spare coal untouched"
    ; the fire burns out on its own, then the block goes dark again
    TICK  1600-600                      ; 1600 lit ticks so far
    CHECK_EQ32 [rel fake_block], B_FURNACE_LIT, "still lit"
    TICK  1
    CHECK_EQ32 [rbx+BE_BURN], 0, "burnt out"
    CHECK_EQ32 [rel fake_block], B_FURNACE, "dark again"
    CHECK_STK [rbx+BE_SLOTS+4], I_COAL, 1, 0, "no work: no new fuel"
    CHECK_EQ32 [rel fake_setraw_count], 2, "two block swaps"
ENDP

PROC case_no_fuel, 0
    TEST "furnace: no fuel no progress"
    call  furnace_setup
    mov   rbx, rax
    SET_STK [rbx+BE_SLOTS+0], B_IRON_ORE, 1, 0
    TICK  50
    CHECK_EQ32 [rbx+BE_COOK], 0, "no cook"
    CHECK_EQ32 [rel fake_block], B_FURNACE, "unlit"
ENDP

PROC case_not_smeltable, 0
    TEST "furnace: not smeltable keeps fuel"
    call  furnace_setup
    mov   rbx, rax
    SET_STK [rbx+BE_SLOTS+0], B_PLANKS, 5, 0   ; planks: fuel but no smelt result
    SET_STK [rbx+BE_SLOTS+4], I_COAL, 1, 0
    TICK  10
    CHECK_STK [rbx+BE_SLOTS+4], I_COAL, 1, 0, "coal kept"
    CHECK_EQ32 [rbx+BE_BURN], 0, "not burning"
ENDP

PROC case_cook_decays, 0
    TEST "furnace: cook decays without fuel"
    call  furnace_setup
    mov   rbx, rax
    SET_STK [rbx+BE_SLOTS+0], B_IRON_ORE, 1, 0
    SET_STK [rbx+BE_SLOTS+4], B_PLANKS, 1, 0   ; 300 ticks of fire
    TICK  150
    CHECK_EQ32 [rbx+BE_COOK], 150, "cook 150"
    mov   dword [rbx+BE_BURN], 1        ; fire about to die, no fuel left
    TICK  1
    TICK  10
    CHECK_EQ32 [rbx+BE_COOK], 150-2*11, "decays 2 per tick"
ENDP

PROC case_output_full, 0
    TEST "furnace: output full blocks"
    call  furnace_setup
    mov   rbx, rax
    SET_STK [rbx+BE_SLOTS+0], B_IRON_ORE, 5, 0
    SET_STK [rbx+BE_SLOTS+4], I_COAL, 1, 0
    SET_STK [rbx+BE_SLOTS+8], I_IRON_INGOT, 64, 0
    TICK  5
    CHECK_EQ32 [rbx+BE_BURN], 0, "full output: no fire"
    CHECK_STK [rbx+BE_SLOTS+4], I_COAL, 1, 0, "coal kept"
    SET_STK [rbx+BE_SLOTS+8], B_COAL_ORE, 1, 0  ; different item in output also blocks
    TICK  5
    CHECK_EQ32 [rbx+BE_BURN], 0, "different output: no fire"
ENDP

PROC case_lava_bucket, 0
    TEST "furnace: lava bucket leaves bucket"
    call  furnace_setup
    mov   rbx, rax
    SET_STK [rbx+BE_SLOTS+0], B_LOG, 1, 0
    SET_STK [rbx+BE_SLOTS+4], I_LAVA_BUCKET, 1, 0
    TICK  1
    CHECK_STK [rbx+BE_SLOTS+4], I_BUCKET, 1, 0, "empty bucket back"
    TICK  199
    CHECK_STK [rbx+BE_SLOTS+8], I_COAL, 1, 0, "charcoal"
ENDP

PROC case_orphan_recycled, 0
    TEST "furnace: orphan recycled"
    call  furnace_setup
    mov   dword [rel fake_block], 0     ; furnace block gone
    TICK  1
    BE_GET 3, 64, 3, 0
    CHECK_EQ rax, 0, "freed"
ENDP

PROC case_chests_no_tick, 0
    TEST "furnace: chests do not tick"
    call  furnace_setup
    BE_GET 9, 9, 9, BE_CHEST
    mov   rbx, rax
    mov   dword [rel fake_block], 0
    TICK  1
    BE_GET 9, 9, 9, 0
    CHECK_EQ rax, rbx, "chest kept"
ENDP

PROC test_main, 0
    call  case_create_find_lookup
    call  case_wrong_kind
    call  case_lookup_raw_reload
    call  case_pool_exhaustion
    call  case_remove_drops
    call  case_smelt_three
    call  case_no_fuel
    call  case_not_smeltable
    call  case_cook_decays
    call  case_output_full
    call  case_lava_bucket
    call  case_orphan_recycled
    call  case_chests_no_tick
ENDP
