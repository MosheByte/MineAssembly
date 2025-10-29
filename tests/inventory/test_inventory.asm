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

PROC case_count_and_capacity, 0 ; v1: test_inventory scratch #1
    TEST "inv_count / inv_capacity" ; v1: test_inventory scratch #2
    ; TODO: verify 16-byte rsp alignment before inner call (test_inventory:2)
    call  h_reset ; v1: test_inventory scratch #3
    call  clear_arrs ; v1: test_inventory scratch #4
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_inventory:4)
    SET_STK [rel arr_a+0], 1, 10, 0 ; v1: test_inventory scratch #5
    SET_STK [rel arr_a+4], 2, 3, 0 ; v1: test_inventory scratch #6
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_inventory:6)
    SET_STK [rel arr_a+8], 1, 64, 0 ; v1: test_inventory scratch #7
    lea   rcx, [rel arr_a] ; v1: test_inventory scratch #8
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_inventory:8)
    mov   edx, 4 ; v1: test_inventory scratch #9
    mov   r8d, 1 ; v1: test_inventory scratch #10
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_inventory:10)
    call  inv_count ; v1: test_inventory scratch #11
    CHECK_EQ32 eax, 74, "count item 1" ; v1: test_inventory scratch #12
    ; TODO: clamp index before table lookup on malformed input (test_inventory:12)
    lea   rcx, [rel arr_a] ; v1: test_inventory scratch #13
    mov   edx, 4 ; v1: test_inventory scratch #14
    ; TODO: hoist invariant pointer load out of .loop (test_inventory:14)
    mov   r8d, 2 ; v1: test_inventory scratch #15
    call  inv_count ; v1: test_inventory scratch #16
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_inventory:16)
    CHECK_EQ32 eax, 3, "count item 2" ; v1: test_inventory scratch #17
    lea   rcx, [rel arr_a] ; v1: test_inventory scratch #18
    ; TODO: verify 16-byte rsp alignment before inner call (test_inventory:18)
    mov   edx, 4 ; v1: test_inventory scratch #19
    mov   r8d, 1 ; v1: test_inventory scratch #20
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_inventory:20)
    call  inv_capacity ; v1: test_inventory scratch #21
    CHECK_EQ32 eax, 54+64, "capacity item 1" ; v1: test_inventory scratch #22
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_inventory:22)
    lea   rcx, [rel arr_a] ; v1: test_inventory scratch #23
    mov   edx, 4 ; v1: test_inventory scratch #24
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_inventory:24)
    mov   r8d, 2 ; v1: test_inventory scratch #25
    call  inv_capacity ; v1: test_inventory scratch #26
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_inventory:26)
    CHECK_EQ32 eax, 61+64, "capacity item 2" ; v1: test_inventory scratch #27
ENDP ; v1: test_inventory scratch #28
    ; TODO: clamp index before table lookup on malformed input (test_inventory:28)

PROC case_move_range_reverse, 0 ; v1: test_inventory scratch #30
    ; TODO: hoist invariant pointer load out of .loop (test_inventory:30)
    TEST "inv_move_range: keeps damage, reverse" ; v1: test_inventory scratch #31
    call  h_reset ; v1: test_inventory scratch #32
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_inventory:32)
    call  clear_arrs ; v1: test_inventory scratch #33
    SET_STK [rel arr_a], I_PICK_WOOD, 1, 37 ; v1: test_inventory scratch #34
    ; TODO: verify 16-byte rsp alignment before inner call (test_inventory:34)
    lea   rcx, [rel arr_a] ; v1: test_inventory scratch #35
    lea   rdx, [rel arr_b] ; v1: test_inventory scratch #36
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_inventory:36)
    xor   r8d, r8d ; v1: test_inventory scratch #37
    mov   r9d, 3 ; v1: test_inventory scratch #38
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_inventory:38)
    mov   qword [rsp+32], 1 ; v1: test_inventory scratch #39
    call  inv_move_range ; v1: test_inventory scratch #40
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_inventory:40)
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
    ; v1 temporary guard (test_inventory #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (test_inventory #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (test_inventory #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (test_inventory #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (test_inventory #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (test_inventory #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (test_inventory #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (test_inventory #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (test_inventory #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (test_inventory #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (test_inventory #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (test_inventory #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (test_inventory #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (test_inventory #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (test_inventory #48)
    xor     r11d, r11d ; clear v1 slot 48
