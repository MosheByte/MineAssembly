; ptest.asm - backs FCHK/ICHK (prints "got X, want <op> Y" on a fail) and the
; seeded rand helpers on top of testlib's xorshift. NaN compares false to everything.
%define IMPL_PTEST
%include "common.inc"
%include "testlib.inc"
%include "../player/ptest.inc"

section .rdata
s_got:   db "        got ", 0
s_want:  db ", want ", 0
s_ops:   db "== ", 0, " < ", 0, 0, "<= ", 0, " > ", 0, 0, ">= ", 0, "!= ", 0
align 8
op_ofs:  dq 0, 4, 9, 13, 18, 22                 ; into s_ops

section .text

; sharing flags between ucomiss and cmp is a pain, so callers hand in
; lt/eq/gt as bools (ecx edx r8d) + op in r9d
LEAF pt_resolve
    xor  eax, eax
    cmp  r9d, OP_EQ
    jne  .lt
    mov  eax, edx
    ret
.lt:
    cmp  r9d, OP_LT
    jne  .le
    mov  eax, ecx
    ret
.le:
    cmp  r9d, OP_LE
    jne  .gt
    mov  eax, ecx
    or   eax, edx
    ret
.gt:
    cmp  r9d, OP_GT
    jne  .ge
    mov  eax, r8d
    ret
.ge:
    cmp  r9d, OP_GE
    jne  .ne
    mov  eax, r8d
    or   eax, edx
    ret
.ne:                                    ; lt|gt, so NaN != x is false too
    mov  eax, ecx
    or   eax, r8d
    ret

PROCX pt_fcmp, 32
    movss LOC(0), xmm0
    movss LOC(4), xmm1
    mov  r12d, r8d
    mov  r13, r9
    xor  ecx, ecx
    xor  edx, edx
    xor  r8d, r8d
    ucomiss xmm0, xmm1
    jp   .decide                        ; NaN, all three stay 0
    setb cl
    sete dl
    seta r8b
.decide:
    mov  r9d, r12d
    call pt_resolve
    test eax, eax
    jz   .bad
    call t_pass
    mov  eax, 1
    jmp  .done
.bad:
    mov  rcx, r13
    mov  rdx, ARG5
    mov  r8d, ARG6
    call t_fail
    lea  rcx, [rel s_got]
    call t_print
    movss xmm0, LOC(0)
    mov  edx, 6
    call t_print_float
    lea  rcx, [rel s_want]
    call t_print
    lea  rax, [rel op_ofs]
    mov  rcx, [rax+r12*8]
    lea  rax, [rel s_ops]
    add  rcx, rax
    call t_print
    movss xmm0, LOC(4)
    mov  edx, 6
    call t_print_float
    call t_newline
    xor  eax, eax
.done:
ENDPX

PROC pt_icmp, 0
    mov  ebx, ecx
    mov  esi, edx
    mov  r12d, r8d
    mov  r13, r9
    xor  ecx, ecx
    xor  edx, edx
    xor  r8d, r8d
    cmp  ebx, esi
    setl cl
    sete dl
    setg r8b
    mov  r9d, r12d
    call pt_resolve
    test eax, eax
    jz   .bad
    call t_pass
    mov  eax, 1
    jmp  .done
.bad:
    mov  rcx, r13
    mov  rdx, ARG5
    mov  r8d, ARG6
    call t_fail
    lea  rcx, [rel s_got]
    call t_print
    movsxd rcx, ebx
    call t_print_int
    lea  rcx, [rel s_want]
    call t_print
    lea  rax, [rel op_ofs]
    mov  rcx, [rax+r12*8]
    lea  rax, [rel s_ops]
    add  rcx, rax
    call t_print
    movsxd rcx, esi
    call t_print_int
    call t_newline
    xor  eax, eax
.done:
ENDP

; [lo, hi] inclusive
PROC pt_rand_int, 0
    mov  ebx, ecx
    mov  esi, edx
    sub  esi, ebx
    inc  esi
    call t_rng_next
    shr  rax, 11                        ; low bits of xorshift are weak
    xor  edx, edx
    mov  ecx, esi
    div  rcx
    lea  eax, [rbx+rdx]
ENDP

; doubles in and out, [lo, hi)
PROC pt_rand_uniform, 16
    movsd LOC(0), xmm0
    subsd xmm1, xmm0
    movsd LOC(8), xmm1
    call t_rng_float                    ; single precision u, fine for tests
    cvtss2sd xmm0, xmm0
    mulsd xmm0, LOC(8)
    addsd xmm0, LOC(0)
ENDP
