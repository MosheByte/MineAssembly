; every exported data-module function through abi_call, results must match a direct call
; @link src/blocks.asm src/items.asm tests/data/abi_harness.asm tests/data/datahelp.asm
; @timeout 60
%include "common.inc"
%include "testlib.inc"
%include "../tests/data/datatest.inc"

extern abi_call
extern abi_rax, abi_rdx
extern abi_selftest_clobber

%define SELFTEST_MASK ((1 << 0) | (1 << 6) | (1 << 9))   ; rbx, r14, xmm7

section .rdata
GRID g_empty,  0,0,0, 0,0,0, 0,0,0
GRID g_log,    B_LOG,0,0, 0,0,0, 0,0,0
GRID g_table,  B_PLANKS,B_PLANKS,0, B_PLANKS,B_PLANKS,0, 0,0,0
GRID g_pick,   B_COBBLE,B_COBBLE,B_COBBLE, 0,I_STICK,0, 0,I_STICK,0

; "" can't live in this list (it'd look like the end), so it's q_empty below
queries:
    db "stone", 0, "diamond pick", 0, "iron", 0, "42", 0, " 7 ", 0, "zz", 0
    db "flowing w", 0, "Flint and Steel", 0, "glowc", 0, "999", 0
    db "light_blue_wool", 0, "leaves", 0, "log", 0, "and steel", 0, "eaves", 0
queries_end:
q_empty:    db 0

section .bss
alignb 16
grid:       resb 16
pool:       resb 512
pool_n:     resd 1
args_blk:   resq 16                 ; t_abi_call args, all zero
namebuf:    resb 160

section .text

PROC test_main
    call    t_harness_detects_clobbers
    call    t_init_functions
    call    t_craft_match
    call    t_find_by_name
ENDP

; abi_call + a check that nothing got clobbered. hands back the callee's eax/edx
PROC call_abi
    call    abi_call
    mov     ebx, eax
    CK      ebx, 0, -1, "callee preserved every nonvolatile register"
    test    eax, eax
    jnz     .ok
    mov     ecx, ebx
    lea     rdx, [rel namebuf]
    call    t_abi_mask_name
    lea     rcx, [rel namebuf]
    call    t_fail_detail
.ok:
    mov     eax, [rel abi_rax]
    mov     edx, [rel abi_rdx]
ENDP

PROC t_harness_detects_clobbers
    TEST "harness_detects_clobbers"
    lea     rcx, [rel abi_selftest_clobber]
    xor     edx, edx
    call    abi_call
    CK      eax, SELFTEST_MASK, -1, "abi_call reports rbx, r14 and xmm7"
    lea     rcx, [rel abi_selftest_clobber]
    lea     rdx, [rel args_blk]
    call    t_abi_call
    CK      ecx, SELFTEST_MASK, -1, "t_abi_call reports rbx, r14 and xmm7"
ENDP

PROC t_init_functions
    TEST "init_functions_preserve_registers"
    lea     rcx, [rel blocks_init]
    xor     edx, edx
    call    call_abi
    CK      eax, 0, -1, "blocks_init through the harness returns 0"
    lea     rcx, [rel items_init]
    xor     edx, edx
    call    call_abi
    CK      eax, 0, -1, "items_init through the harness returns 0"
ENDP

PROC craft_same
    mov     rsi, rcx
    mov     rdx, rcx
    lea     rcx, [rel craft_match]
    call    call_abi
    mov     r12d, eax
    mov     r13d, edx
    mov     rcx, rsi
    call    craft_match
    mov     r15d, eax
    mov     r14d, edx
    CK      r12d, r15d, -1, "craft_match result through the harness == direct"
    CK      r13d, r14d, -1, "craft_match count through the harness == direct"
ENDP

PROC t_craft_match
    TEST "craft_match_preserves_registers"
    ; 6 zeros up front so random grids get some empty cells
    lea     rdi, [rel pool]
    xor     eax, eax
    mov     ecx, 6
    rep     stosb
    mov     esi, 6
    xor     ebx, ebx
.ids:
    mov     ecx, ebx
    call    dh_valid_id
    test    eax, eax
    jz      .inext
    lea     rax, [rel pool]
    mov     [rax+rsi], bl
    inc     esi
.inext:
    inc     ebx
    cmp     ebx, 256
    jb      .ids
    mov     [rel pool_n], esi
    lea     rcx, [rel g_empty]
    call    craft_same
    lea     rcx, [rel g_log]
    call    craft_same
    lea     rcx, [rel g_table]
    call    craft_same
    lea     rcx, [rel g_pick]
    call    craft_same
    mov     ecx, 1234
    call    t_rng_seed
    xor     r12d, r12d
.grid:
    xor     ebx, ebx
.cell:
    call    t_rng_next
    xor     edx, edx
    mov     ecx, [rel pool_n]
    div     rcx
    lea     rax, [rel pool]
    movzx   eax, byte [rax+rdx]
    lea     rcx, [rel grid]
    mov     [rcx+rbx], al
    inc     ebx
    cmp     ebx, 9
    jb      .cell
    lea     rcx, [rel grid]
    call    craft_same
    inc     r12d
    cmp     r12d, 400
    jb      .grid
    lea     rdx, [rel g_log]
    lea     rcx, [rel craft_match]
    call    call_abi
    mov     ebx, edx
    CK      eax, B_PLANKS, -1, "log through the harness -> planks"
    CK      ebx, 4, -1, "log through the harness -> 4"
ENDP

PROC find_same
    mov     rsi, rcx
    mov     rdx, rcx
    lea     rcx, [rel item_find_by_name]
    call    call_abi
    mov     r12d, eax
    mov     rcx, rsi
    call    item_find_by_name
    mov     r13d, eax
    CK      r12d, r13d, -1, "item_find_by_name through the harness == direct"
    test    eax, eax
    jnz     .done
    mov     rcx, rsi
    call    t_fail_detail
.done:
ENDP

PROC t_find_by_name
    TEST "find_by_name_preserves_registers"
    lea     rsi, [rel queries]
.q:
    mov     rcx, rsi
    call    find_same
.skip:
    inc     rsi
    cmp     byte [rsi-1], 0
    jne     .skip
    lea     rax, [rel queries_end]
    cmp     rsi, rax
    jb      .q
    lea     rcx, [rel q_empty]
    call    find_same
    xor     ebx, ebx
.names:
    mov     ecx, ebx
    call    dh_valid_id
    test    eax, eax
    jz      .next
    LDQ     rcx, item_name, rbx
    call    find_same
.next:
    inc     ebx
    cmp     ebx, 256
    jb      .names
ENDP
