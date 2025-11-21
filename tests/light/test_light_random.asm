; 150 random edits over a cave-y world. light has to match the reference after every one
; @link src/light.asm tests/light/fakeworld.asm tests/light/lightlib.asm
; @timeout 300
%include "common.inc"
%include "testlib.inc"
%include "../light/lightlib.inc"  ; via -I tests/lib/

%define EDITS 150

section .rdata
palette:    db T_AIR, T_AIR, T_AIR, T_STONE, T_STONE, T_LEAVES, T_WATER, T_GLASS
            db T_TORCH, T_GLOW, T_ICE, T_LANTERN
%define PALETTE_N 12

section .text
PROC rand_below, 0
    mov  ebx, ecx
    call t_rng_next
    xor  edx, edx
    div  rbx
    mov  eax, edx
ENDP

PROC test_main, 0
    call lt_setup_tables

    TEST "random edits match reference"
    mov  ecx, 1234
    call t_rng_seed
    mov  ecx, 60
    call lt_flat_world
    mov  ecx, 60
    mov  edx, 72
    mov  r8d, 300  ; 30% stone in y 60..71
    mov  r9d, T_STONE
    call lt_fill_random
    FILL 72, 73, 8, 40, 8, 40, T_STONE  ; partial roof = caves
    xor  ecx, ecx
    call lt_generate
    CHECK_REF "initial"

    xor  r15d, r15d
.edit:
    mov  ecx, 48
    call rand_below
    lea  r12d, [rax - 16]
    mov  ecx, 48
    call rand_below
    lea  r13d, [rax - 16]
    mov  ecx, 24
    call rand_below
    lea  r14d, [rax + 56]  ; y in [56, 80)
    mov  ecx, PALETTE_N
    call rand_below
    lea  rcx, [rel palette]
    movzx eax, byte [rcx + rax]
    mov  ebx, eax
    SETB r12d, r14d, r13d, ebx
    CHECK_REF "random edit"
    test eax, eax
    jnz  .ok
    mov  ecx, r15d
    mov  edx, r12d
    mov  r8d, r14d
    mov  r9d, r13d
    mov  [rsp+32], rbx
    call lt_print_edit
.ok:
    inc  r15d
    cmp  r15d, EDITS
    jb   .edit
ENDP
