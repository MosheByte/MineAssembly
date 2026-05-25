; set_hunger.asm - pokes hunger/saturation into a saved level.dat. there's no console
; command for hunger and you can't eat on a full bar, so the eat scenario needs this.
; usage: set MA_SET_HUNGER=<level.dat>,<hunger>,<sat> then run test_set_hunger.
; level.dat: 'MASW' at 0, header size H at 8, g_player verbatim at H, fnv1a of
; bytes 64..end at 56.
%include "common.inc"

global lvl_set_hunger, lvl_fnv1a

%define LV_MAX      (1 << 20)           ; real ones are a few KB
%define LV_CRC_OFF  56
%define LV_CRC_FROM 64

section .bss
alignb 16
lv_buf:     resb LV_MAX

section .text

LEAF lvl_fnv1a
    mov  eax, 2166136261
    test rdx, rdx
    jz   .done
.l:
    movzx r8d, byte [rcx]
    xor  eax, r8d
    imul eax, eax, 16777619
    inc  rcx
    dec  rdx
    jnz  .l
.done:
    ret

; (path, hunger, xmm2 sat) -> 0 ok, 1 not a level, 2 io error
PROC lvl_set_hunger, 32
    mov  r12, rcx
    mov  r13d, edx
    ; game never lets saturation go above hunger
    cvtsi2ss xmm0, r13d
    minss xmm2, xmm0
    movss LOC(0), xmm2
    mov  rcx, r12
    mov  edx, GENERIC_READ
    xor  r8d, r8d
    xor  r9d, r9d
    mov  qword [rsp+32], OPEN_EXISTING
    mov  qword [rsp+40], 0
    mov  qword [rsp+48], 0
    call CreateFileA
    cmp  rax, -1
    je   .ioerr
    mov  rbx, rax
    mov  rcx, rbx
    lea  rdx, [rel lv_buf]
    mov  r8d, LV_MAX
    lea  r9, LOC(8)
    mov  qword [rsp+32], 0
    call ReadFile
    mov  esi, eax
    mov  rcx, rbx
    call CloseHandle
    test esi, esi
    jz   .ioerr
    mov  r14d, LOC(8)
    cmp  r14d, LV_MAX
    jae  .bad                           ; filled the buffer, so not a level
    lea  rdi, [rel lv_buf]
    cmp  dword [rdi], 'MASW'
    jne  .bad
    cmp  r14d, LV_CRC_FROM
    jb   .bad
    lea  rcx, [rdi+LV_CRC_FROM]
    mov  edx, r14d
    sub  edx, LV_CRC_FROM
    call lvl_fnv1a
    cmp  eax, [rdi+LV_CRC_OFF]
    jne  .bad
    mov  r15d, [rdi+8]                  ; H
    lea  eax, [r15+PLAYER.saturation+4]
    cmp  eax, r14d
    ja   .bad
    mov  [rdi+r15+PLAYER.hunger], r13d
    movss xmm0, LOC(0)
    movss [rdi+r15+PLAYER.saturation], xmm0
    lea  rcx, [rdi+LV_CRC_FROM]
    mov  edx, r14d
    sub  edx, LV_CRC_FROM
    call lvl_fnv1a
    mov  [rdi+LV_CRC_OFF], eax
    mov  rcx, r12
    mov  edx, GENERIC_WRITE
    xor  r8d, r8d
    xor  r9d, r9d
    mov  qword [rsp+32], CREATE_ALWAYS
    mov  qword [rsp+40], 0
    mov  qword [rsp+48], 0
    call CreateFileA
    cmp  rax, -1
    je   .ioerr
    mov  rbx, rax
    mov  rcx, rbx
    lea  rdx, [rel lv_buf]
    mov  r8d, r14d
    lea  r9, LOC(8)
    mov  qword [rsp+32], 0
    call WriteFile
    mov  esi, eax
    mov  rcx, rbx
    call CloseHandle
    test esi, esi
    jz   .ioerr
    cmp  LOC(8), r14d
    jne  .ioerr
    xor  eax, eax
    jmp  .done
.bad:
    mov  eax, 1
    jmp  .done
.ioerr:
    mov  eax, 2
.done:
ENDP
