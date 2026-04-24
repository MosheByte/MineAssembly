; fakeworld.asm - 64^3 byte world standing in for world.asm in the player tests.
; x,z in [-32,32), y in [0,64), index (x+32) + (z+32)*64 + y*4096.
; y < 0 reads bedrock like the real thing, anything else outside is air.
%define IMPL_WORLD
%define IMPL_INVENTORY
%define IMPL_FAKEWORLD
%include "common.inc"

global test_world, test_set_calls, test_loaded

section .data
align 4
test_loaded:    dd 1            ; what world_is_loaded says, tests flip it

section .bss
alignb 16
test_world:     resb 64*64*64
test_set_calls: resd 1

section .text

; -> rax index or -1. only touches r9 besides rax
cell_index:
    lea  eax, [rcx+32]
    cmp  eax, 64
    jae  .out
    lea  r9d, [r8+32]
    cmp  r9d, 64
    jae  .out
    cmp  edx, 64
    jae  .out
    shl  r9d, 6
    add  eax, r9d
    mov  r9d, edx
    shl  r9d, 12
    add  eax, r9d
    ret
.out:
    mov  rax, -1
    ret

LEAF world_get_block
    test edx, edx
    js   .bedrock
    call cell_index
    cmp  rax, -1
    je   .air
    lea  rcx, [rel test_world]
    movzx eax, byte [rcx+rax]
    ret
.bedrock:
    mov  eax, B_BEDROCK
    ret
.air:
    xor  eax, eax
    ret

LEAF world_set_block
    inc  dword [rel test_set_calls]
    test edx, edx
    js   .fail
    push r9
    call cell_index
    pop  r9
    cmp  rax, -1
    je   .fail
    lea  rcx, [rel test_world]
    mov  [rcx+rax], r9b
    mov  eax, 1
    ret
.fail:
    xor  eax, eax
    ret

LEAF world_is_loaded
    mov  eax, [rel test_loaded]
    ret

; bare minimum inventory, just the hotbar
LEAF inv_held
    lea  rax, [rel g_player]
    mov  ecx, [rax+PLAYER.selected]
    cmp  ecx, 8
    jbe  .ok
    xor  ecx, ecx
.ok:
    lea  rax, [rax+PLAYER.inv+rcx*4]
    ret

LEAF inv_consume_held
    cmp  dword [rel g_gamemode], GM_CREATIVE
    je   .done
    mov  edx, ecx
    call inv_held
    sub  [rax+STACK.count], dl
    jnz  .done
    mov  dword [rax], 0
.done:
    ret

; test side

LEAF fw_clear
    push rdi
    lea  rdi, [rel test_world]
    xor  eax, eax
    mov  ecx, 64*64*64/8
    rep  stosq
    pop  rdi
    ret

LEAF fw_get
    jmp  world_get_block

; raw write, doesn't bump test_set_calls. outside the volume = dropped
LEAF fw_set
    test edx, edx
    js   .skip
    push r9
    call cell_index
    pop  r9
    cmp  rax, -1
    je   .skip
    lea  rcx, [rel test_world]
    mov  [rcx+rax], r9b
.skip:
    ret

; (x0, y0, z0, x1, y1, z1, id), inclusive
PROC fw_fill, 0
    mov  r12d, ecx
    mov  r13d, edx
    mov  r14d, r8d
    mov  r15d, r9d
    mov  ebx, r12d
.lx:
    cmp  ebx, r15d
    jg   .done
    mov  esi, r13d
.ly:
    cmp  esi, ARG5
    jg   .nx
    mov  edi, r14d
.lz:
    cmp  edi, ARG6
    jg   .ny
    mov  ecx, ebx
    mov  edx, esi
    mov  r8d, edi
    mov  r9d, ARG7
    call fw_set
    inc  edi
    jmp  .lz
.ny:
    inc  esi
    jmp  .ly
.nx:
    inc  ebx
    jmp  .lx
.done:
ENDP

; fills blk_flags / blk_model for the handful of ids the tests use. those tables
; are auto-stubbed zeros when blocks.asm isn't linked
%define ROCK (BF_SOLID | BF_OPAQUE | BF_SELECTABLE)
section .rdata
rock_ids: db 1, 2, 3, 7, 31, 18, 11     ; stone grass dirt sand tnt ice glass
section .text
LEAF fw_setup_blocks
    push rdi
    lea  rdi, [rel blk_flags]
    xor  eax, eax
    mov  ecx, 256*2/8
    rep  stosq
    lea  rdi, [rel blk_model]
    mov  ecx, 256/8
    rep  stosq
    pop  rdi
    lea  rcx, [rel blk_flags]
    lea  rdx, [rel blk_model]
    lea  r8, [rel rock_ids]
    xor  eax, eax
.rock:
    movzx r9d, byte [r8+rax]
    mov  word [rcx+r9*2], ROCK
    inc  eax
    cmp  eax, 7
    jb   .rock
    mov  word [rcx+0*2], BF_REPLACEABLE
    mov  word [rcx+19*2], BF_SOLID | BF_SELECTABLE | BF_SUPPORT        ; cactus
    mov  byte [rdx+19], MODEL_CACTUS
    mov  word [rcx+67*2], BF_SOLID | BF_SELECTABLE                     ; lantern
    mov  byte [rdx+67], MODEL_LANTERN
    mov  word [rcx+34*2], BF_SELECTABLE | BF_SUPPORT                   ; torch
    mov  byte [rdx+34], MODEL_TORCH
    mov  word [rcx+35*2], BF_SELECTABLE | BF_REPLACEABLE | BF_PLANT    ; tall grass
    mov  byte [rdx+35], MODEL_CROSS
    mov  eax, 80
.liq:
    mov  word [rcx+rax*2], BF_LIQUID | BF_REPLACEABLE
    mov  byte [rdx+rax], MODEL_LIQUID
    inc  eax
    cmp  eax, 92
    jb   .liq
    ret
