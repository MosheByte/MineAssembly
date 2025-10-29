; test_inventory.asm - stack algebra (inv_add/count/capacity/move_range) and
; the player-facing inventory calls: give, held, consume, wear, clear, drop.
; @link src/inventory.asm src/screens.asm src/blockent.asm
; @link tests/inventory/fakes.asm tests/inventory/invharness.asm
; @timeout 60
%include "common.inc"
%include "testlib.inc"
%include "../inventory/invtest.inc"   ; via the tests/lib/ include path

section .bss
alignb 16
arr_a:  resb 64                         ; scratch STACK arrays
arr_b:  resb 64

section .text

LEAF clear_arrs
    xor   eax, eax
    lea   rdx, [rel arr_a]
    mov   ecx, 16
.l: mov   [rdx], rax
    add   rdx, 8
    dec   ecx
    jnz   .l
    ret

PROC case_merge_before_empty, 0
    TEST "inv_add: merge before empty"
    call  h_reset
    call  clear_arrs
    SET_STK [rel arr_a+0], 1, 60, 0
    SET_STK [rel arr_a+8], 1, 10, 0
    lea   rcx, [rel arr_a]
    mov   edx, 4
    mov   r8d, 1
    mov   r9d, 20
    call  inv_add
    CHECK_EQ32 eax, 0, "leftover"
    ; merge pass tops up slot 0 (+4) and slot 2 (+16) before touching empties
    CHECK_STK [rel arr_a+0], 1, 64, 0, "slot 0 topped up"
    CHECK_STK [rel arr_a+4], 0, 0, 0, "slot 1 untouched"
    CHECK_STK [rel arr_a+8], 1, 26, 0, "slot 2 merged"
    CHECK_STK [rel arr_a+12], 0, 0, 0, "slot 3 untouched"
ENDP

PROC case_overflow_into_empty, 0
    TEST "inv_add: overflow into empty and leftover"
    call  h_reset
    call  clear_arrs
    SET_STK [rel arr_a+4], 2, 5, 0
    lea   rcx, [rel arr_a]
    mov   edx, 4
    mov   r8d, 1
    mov   r9d, 300                      ; 3 empty slots * 64 = 192 fit
    call  inv_add
    CHECK_EQ32 eax, 108, "leftover"
    CHECK_STK [rel arr_a+0], 1, 64, 0, "slot 0"
    CHECK_STK [rel arr_a+4], 2, 5, 0, "slot 1 other item"
    CHECK_STK [rel arr_a+8], 1, 64, 0, "slot 2"
    CHECK_STK [rel arr_a+12], 1, 64, 0, "slot 3"
ENDP

PROC case_respects_max_stack, 0
    TEST "inv_add: respects max stack"
    call  h_reset
    call  clear_arrs
    lea   rax, [rel item_max_stack]
    mov   byte [rax+200], 16
    SET_STK [rel arr_a+0], 200, 10, 0
    lea   rcx, [rel arr_a]
    mov   edx, 2
    mov   r8d, 200
    mov   r9d, 30
    call  inv_add
    CHECK_EQ32 eax, 8, "leftover"
    CHECK_STK [rel arr_a+0], 200, 16, 0, "slot 0"
    CHECK_STK [rel arr_a+4], 200, 16, 0, "slot 1"
ENDP

PROC case_unstackable_tools, 0
    TEST "inv_add: unstackable tools never merge"
    call  h_reset
    call  clear_arrs
    SET_STK [rel arr_a+0], I_PICK_WOOD, 1, 0
    lea   rcx, [rel arr_a]
    mov   edx, 3
    mov   r8d, I_PICK_WOOD
    mov   r9d, 3
    call  inv_add
    CHECK_EQ32 eax, 1, "leftover"
    movzx eax, byte [rel arr_a+1]
    CHECK_EQ32 eax, 1, "count slot 0"
    movzx eax, byte [rel arr_a+5]
    CHECK_EQ32 eax, 1, "count slot 1"
    movzx eax, byte [rel arr_a+9]
    CHECK_EQ32 eax, 1, "count slot 2"
ENDP

PROC case_degenerate_args, 0
    TEST "inv_add: degenerate args"
    call  h_reset
    call  clear_arrs
    lea   rcx, [rel arr_a]
    mov   edx, 1
    xor   r8d, r8d
    mov   r9d, 5
    call  inv_add
    CHECK_EQ32 eax, 0, "item 0"
    lea   rcx, [rel arr_a]
    mov   edx, 1
    mov   r8d, 3
    xor   r9d, r9d
    call  inv_add
    CHECK_EQ32 eax, 0, "count 0"
    lea   rcx, [rel arr_a]
    mov   edx, 1
    mov   r8d, 3
    mov   r9d, -4
    call  inv_add
    CHECK_EQ32 eax, 0, "negative count"
    CHECK_STK [rel arr_a], 0, 0, 0, "array untouched"
    lea   rcx, [rel arr_a]
    xor   edx, edx
    mov   r8d, 3
    mov   r9d, 7
    call  inv_add
    CHECK_EQ32 eax, 7, "zero slots: all left over"
ENDP

PROC case_count_and_capacity, 0
    TEST "inv_count / inv_capacity"
    call  h_reset
    call  clear_arrs
    SET_STK [rel arr_a+0], 1, 10, 0
    SET_STK [rel arr_a+4], 2, 3, 0
    SET_STK [rel arr_a+8], 1, 64, 0
    lea   rcx, [rel arr_a]
    mov   edx, 4
    mov   r8d, 1
    call  inv_count
    CHECK_EQ32 eax, 74, "count item 1"
    lea   rcx, [rel arr_a]
    mov   edx, 4
    mov   r8d, 2
    call  inv_count
    CHECK_EQ32 eax, 3, "count item 2"
    lea   rcx, [rel arr_a]
    mov   edx, 4
    mov   r8d, 1
    call  inv_capacity
    CHECK_EQ32 eax, 54+64, "capacity item 1"
    lea   rcx, [rel arr_a]
    mov   edx, 4
    mov   r8d, 2
    call  inv_capacity
    CHECK_EQ32 eax, 61+64, "capacity item 2"
ENDP

PROC case_move_range_reverse, 0
    TEST "inv_move_range: keeps damage, reverse"
    call  h_reset
    call  clear_arrs
    SET_STK [rel arr_a], I_PICK_WOOD, 1, 37
    lea   rcx, [rel arr_a]
    lea   rdx, [rel arr_b]
    xor   r8d, r8d
    mov   r9d, 3
    mov   qword [rsp+32], 1
    call  inv_move_range
    CHECK_EQ32 eax, 0, "nothing left"
    CHECK_STK [rel arr_a], 0, 0, 0, "src cleared"
    CHECK_STK [rel arr_b+8], I_PICK_WOOD, 1, 37, "reverse: last slot first"
ENDP

PROC case_move_range_partial, 0
    TEST "inv_move_range: partial"
    call  h_reset
    call  clear_arrs
    SET_STK [rel arr_a], 1, 50, 0
    SET_STK [rel arr_b+0], 1, 40, 0
    SET_STK [rel arr_b+4], 2, 1, 0
    lea   rcx, [rel arr_a]
    lea   rdx, [rel arr_b]
    xor   r8d, r8d
    mov   r9d, 2
    mov   qword [rsp+32], 0
    call  inv_move_range
    CHECK_EQ32 eax, 26, "left in src"
    CHECK_STK [rel arr_a], 1, 26, 0, "src"
    CHECK_STK [rel arr_b+0], 1, 64, 0, "dst 0"
    CHECK_STK [rel arr_b+4], 2, 1, 0, "dst 1"
ENDP

PROC case_give_hotbar_first, 0
    TEST "inv_give_player: hotbar first"
    call  h_reset
    mov   ecx, B_LOG
    mov   edx, 10
    call  inv_give_player
    CHECK_EQ32 eax, 0, "leftover"
    CHECK_STK [rel INVS(0)], B_LOG, 10, 0, "slot 0"
    SET_STK [rel INVS(1)], 3, 1, 0
    SET_STK [rel INVS(12)], B_LOG, 60, 0
    mov   ecx, B_LOG
    mov   edx, 100
    call  inv_give_player
    CHECK_EQ32 eax, 0, "leftover 2"
    ; merge pass: slot0 -> 64 (+54), slot12 -> 64 (+4); rest (42) to the first empty: slot 2
    CHECK_STK [rel INVS(0)], B_LOG, 64, 0, "slot 0 full"
    CHECK_STK [rel INVS(12)], B_LOG, 64, 0, "slot 12 full"
    CHECK_STK [rel INVS(2)], B_LOG, 42, 0, "slot 2 rest"
ENDP

PROC case_give_full_leftover, 0
    TEST "inv_give_player: full inventory leftover"
    call  h_reset
    lea   rax, [rel INVS(0)]
    mov   ecx, 36
.fill:
    mov   dword [rax], STK(3, 64, 0)
    add   rax, 4
    dec   ecx
    jnz   .fill
    mov   ecx, 4
    mov   edx, 5
    call  inv_give_player
    CHECK_EQ32 eax, 5, "all left over"
    SET_STK [rel INVS(35)], 4, 62, 0
    mov   ecx, 4
    mov   edx, 5
    call  inv_give_player
    CHECK_EQ32 eax, 3, "two fit"
ENDP

PROC case_held_consume, 0
    TEST "inv_held / inv_consume_held"
    call  h_reset
    mov   dword [rel g_player+P_SELECTED], 3
    SET_STK [rel INVS(3)], 7, 5, 0
    call  inv_held
    lea   rdx, [rel INVS(3)]
    CHECK_EQ rax, rdx, "held = slot 3"
    mov   ecx, 2
    call  inv_consume_held
    CHECK_STK [rel INVS(3)], 7, 3, 0, "consumed 2"
    mov   dword [rel g_gamemode], GM_CREATIVE
    mov   ecx, 2
    call  inv_consume_held
    CHECK_STK [rel INVS(3)], 7, 3, 0, "creative: infinite"
    mov   dword [rel g_gamemode], GM_SURVIVAL
    mov   ecx, 5
    call  inv_consume_held
    CHECK_STK [rel INVS(3)], 0, 0, 0, "over-consume empties"
ENDP

PROC case_bad_selection, 0
    TEST "inv_held: bad selection clamped"
    call  h_reset
    mov   dword [rel g_player+P_SELECTED], 99
    call  inv_held
    lea   rdx, [rel INVS(0)]
    CHECK_EQ rax, rdx, "clamped to slot 0"
ENDP

PROC case_tool_wear, 0
    TEST "inv_damage_held: wear and break"
    call  h_reset
    lea   rax, [rel item_durability]
    mov   word [rax+2*I_PICK_WOOD], 10
    SET_STK [rel INVS(0)], I_PICK_WOOD, 1, 0
    mov   ecx, 4
    call  inv_damage_held
    CHECK_STK [rel INVS(0)], I_PICK_WOOD, 1, 4, "worn 4"
    mov   dword [rel g_gamemode], GM_CREATIVE
    mov   ecx, 100
    call  inv_damage_held
    CHECK_STK [rel INVS(0)], I_PICK_WOOD, 1, 4, "creative: no wear"
    mov   dword [rel g_gamemode], GM_SURVIVAL
    mov   ecx, 5
    call  inv_damage_held
    CHECK_STK [rel INVS(0)], I_PICK_WOOD, 1, 9, "worn 9"
    mov   ecx, 1
    call  inv_damage_held                ; reaches durability: shatters
    CHECK_STK [rel INVS(0)], 0, 0, 0, "shattered"
ENDP

PROC case_non_tool, 0
    TEST "inv_damage_held: non-tool not damaged"
    call  h_reset
    SET_STK [rel INVS(0)], B_LOG, 3, 0
    mov   ecx, 1
    call  inv_damage_held
    CHECK_STK [rel INVS(0)], B_LOG, 3, 0, "log unchanged"
ENDP

PROC case_clear_and_drop_all, 0
    TEST "inv_drop_all / inv_clear_player"
    call  h_reset
    SET_STK [rel INVS(0)], 1, 5, 0
    SET_STK [rel INVS(35)], 2, 7, 0
    SET_STK [rel CURSORS], 3, 2, 0
    SET_STK [rel CRAFTS(4)], 4, 1, 0
    call  inv_drop_all
    CHECK_EQ32 [rel fake_spawn_count], 4, "spawned 4 entities"
    CHECK_EQ32 [rel fake_spawn_items], 15, "15 items dropped"
    CHECK_STK [rel INVS(0)], 0, 0, 0, "slot 0 empty"
    CHECK_STK [rel CURSORS], 0, 0, 0, "cursor empty"
    CHECK_STK [rel CRAFTS(4)], 0, 0, 0, "craft 4 empty"
    SET_STK [rel INVS(5)], 1, 5, 0
    SET_STK [rel CRAFTS(0)], 1, 1, 0
    call  inv_clear_player
    ; every byte from PLAYER.inv to the end of craft_out must be zero
    lea   rax, [rel INVS(0)]
    xor   edx, edx
    mov   ecx, P_CRAFT_OUT + 4 - P_INV
.or:
    movzx r8d, byte [rax]
    or    edx, r8d
    inc   rax
    dec   ecx
    jnz   .or
    CHECK_EQ32 edx, 0, "everything cleared"
ENDP

PROC test_main, 0
    call  case_merge_before_empty
    call  case_overflow_into_empty
    call  case_respects_max_stack
    call  case_unstackable_tools
    call  case_degenerate_args
    call  case_count_and_capacity
    call  case_move_range_reverse
    call  case_move_range_partial
    call  case_give_hotbar_first
    call  case_give_full_leftover
    call  case_held_consume
    call  case_bad_selection
    call  case_tool_wear
    call  case_non_tool
    call  case_clear_and_drop_all
ENDP
