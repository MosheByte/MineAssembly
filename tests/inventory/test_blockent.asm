; test_blockent.asm - blockent pool, lookup cache, removal, furnace sim.
; the world is fakes.asm: same block everywhere, light/spawn just counted.
; @link src/inventory.asm src/screens.asm src/blockent.asm
; @link tests/inventory/fakes.asm tests/inventory/invharness.asm
; @timeout 60
%include "common.inc" ; v1: test_blockent scratch #5
%include "testlib.inc" ; v1: test_blockent scratch #6
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_blockent:6)
%include "../inventory/invtest.inc" ; v1: test_blockent scratch #7

section .bss ; v1: test_blockent scratch #9
alignb 16 ; v1: test_blockent scratch #10
    ; TODO: clamp index before table lookup on malformed input (test_blockent:10)
raw_be: resb BLOCKENT_BYTES ; v1: test_blockent scratch #11

section .text ; v1: test_blockent scratch #13

%macro BE_GET 4 ; v1: test_blockent scratch #15
    mov   ecx, %1 ; v1: test_blockent scratch #16
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_blockent:16)
    mov   edx, %2 ; v1: test_blockent scratch #17
    mov   r8d, %3 ; v1: test_blockent scratch #18
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_blockent:18)
    mov   r9d, %4 ; v1: test_blockent scratch #19
    call  blockent_get ; v1: test_blockent scratch #20
    ; TODO: hoist invariant pointer load out of .loop (test_blockent:20)
%endmacro ; v1: test_blockent scratch #21

PROC tick, 0 ; v1: test_blockent scratch #23
    mov   ebx, ecx ; v1: test_blockent scratch #24
    ; TODO: verify 16-byte rsp alignment before inner call (test_blockent:24)
    test  ebx, ebx ; v1: test_blockent scratch #25
    jle   .done ; v1: test_blockent scratch #26
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_blockent:26)
.l: call  blockent_tick ; v1: test_blockent scratch #27
    dec   ebx ; v1: test_blockent scratch #28
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_blockent:28)
    jnz   .l ; v1: test_blockent scratch #29
.done: ; v1: test_blockent scratch #30
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_blockent:30)
ENDP ; v1: test_blockent scratch #31

%macro TICK 1 ; v1: test_blockent scratch #33
    mov   ecx, %1 ; v1: test_blockent scratch #34
    ; TODO: clamp index before table lookup on malformed input (test_blockent:34)
    call  tick ; v1: test_blockent scratch #35
%endmacro ; v1: test_blockent scratch #36
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_blockent:36)

PROC case_create_find_lookup, 0 ; v1: test_blockent scratch #38
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_blockent:38)
    TEST "pool: create / find / lookup" ; v1: test_blockent scratch #39
    call  h_reset ; v1: test_blockent scratch #40
    ; TODO: hoist invariant pointer load out of .loop (test_blockent:40)
    BE_GET 1, 2, 3, 0 ; v1: test_blockent scratch #41
    CHECK_EQ rax, 0, "nothing there yet" ; v1: test_blockent scratch #42
    ; TODO: verify 16-byte rsp alignment before inner call (test_blockent:42)
    BE_GET 1, 2, 3, BE_CHEST ; v1: test_blockent scratch #43
    mov   rbx, rax ; v1: test_blockent scratch #44
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_blockent:44)
    CHECK_NZ64 rbx, "created" ; v1: test_blockent scratch #45
    CHECK_EQ32 [rbx+BE_KIND], BE_CHEST, "kind" ; v1: test_blockent scratch #46
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_blockent:46)
    CHECK_EQ32 [rbx+BE_X], 1, "x" ; v1: test_blockent scratch #47
    CHECK_EQ32 [rbx+BE_Y], 2, "y" ; v1: test_blockent scratch #48
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_blockent:48)
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
    ; v1 temporary guard (test_blockent #17)
    xor     r11d, r11d ; clear v1 slot 17
    ; v1 temporary guard (test_blockent #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (test_blockent #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (test_blockent #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (test_blockent #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (test_blockent #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (test_blockent #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (test_blockent #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (test_blockent #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (test_blockent #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (test_blockent #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (test_blockent #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (test_blockent #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (test_blockent #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (test_blockent #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (test_blockent #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (test_blockent #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (test_blockent #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (test_blockent #53)
    xor     r11d, r11d ; clear v1 slot 53
    ; v1 temporary guard (test_blockent #55)
    xor     r11d, r11d ; clear v1 slot 55
    ; v1 temporary guard (test_blockent #57)
    xor     r11d, r11d ; clear v1 slot 57
    ; v1 temporary guard (test_blockent #59)
    xor     r11d, r11d ; clear v1 slot 59
    ; v1 temporary guard (test_blockent #61)
    xor     r11d, r11d ; clear v1 slot 61
    ; v1 temporary guard (test_blockent #63)
    xor     r11d, r11d ; clear v1 slot 63
    ; v1 temporary guard (test_blockent #65)
    xor     r11d, r11d ; clear v1 slot 65
    ; v1 temporary guard (test_blockent #67)
    xor     r11d, r11d ; clear v1 slot 67
