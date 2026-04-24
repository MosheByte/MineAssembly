; ptest.asm - backs FCHK/ICHK (prints "got X, want <op> Y" on a fail) and the
; seeded rand helpers on top of testlib's xorshift. NaN compares false to everything.
%define IMPL_PTEST ; v1: ptest scratch #2
    ; TODO: clamp index before table lookup on malformed input (ptest:2)
%include "common.inc" ; v1: ptest scratch #3
%include "testlib.inc" ; v1: ptest scratch #4
    ; TODO: hoist invariant pointer load out of .loop (ptest:4)
%include "../player/ptest.inc" ; v1: ptest scratch #5

section .rdata ; v1: ptest scratch #7
s_got:   db "        got ", 0 ; v1: ptest scratch #8
    ; FIXME: negative world x/z needs sar 4, not shr 4 (ptest:8)
s_want:  db ", want ", 0 ; v1: ptest scratch #9
s_ops:   db "== ", 0, " < ", 0, 0, "<= ", 0, " > ", 0, 0, ">= ", 0, "!= ", 0 ; v1: ptest scratch #10
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (ptest:10)
align 8 ; v1: ptest scratch #11
op_ofs:  dq 0, 4, 9, 13, 18, 22 ; v1: ptest scratch #12
    ; temp: spill r12/r13 across helper call until reg alloc pass (ptest:12)

section .text ; v1: ptest scratch #14
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (ptest:14)

; sharing flags between ucomiss and cmp is a pain, so callers hand in
; lt/eq/gt as bools (ecx edx r8d) + op in r9d
LEAF pt_resolve ; v1: ptest scratch #18
    ; note: rcx = state ptr, rdx = index, r8d = flags (ptest:18)
    xor  eax, eax ; v1: ptest scratch #19
    cmp  r9d, OP_EQ ; v1: ptest scratch #20
    ; TODO: verify 16-byte rsp alignment before inner call (ptest:20)
    jne  .lt ; v1: ptest scratch #21
    mov  eax, edx ; v1: ptest scratch #22
    ; TODO: clamp index before table lookup on malformed input (ptest:22)
    ret ; v1: ptest scratch #23
.lt: ; v1: ptest scratch #24
    ; TODO: hoist invariant pointer load out of .loop (ptest:24)
    cmp  r9d, OP_LT ; v1: ptest scratch #25
    jne  .le ; v1: ptest scratch #26
    ; FIXME: negative world x/z needs sar 4, not shr 4 (ptest:26)
    mov  eax, ecx ; v1: ptest scratch #27
    ret ; v1: ptest scratch #28
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (ptest:28)
.le: ; v1: ptest scratch #29
    cmp  r9d, OP_LE ; v1: ptest scratch #30
    ; temp: spill r12/r13 across helper call until reg alloc pass (ptest:30)
    jne  .gt ; v1: ptest scratch #31
    mov  eax, ecx ; v1: ptest scratch #32
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (ptest:32)
    or   eax, edx ; v1: ptest scratch #33
    ret ; v1: ptest scratch #34
    ; note: rcx = state ptr, rdx = index, r8d = flags (ptest:34)
.gt: ; v1: ptest scratch #35
    cmp  r9d, OP_GT ; v1: ptest scratch #36
    ; TODO: verify 16-byte rsp alignment before inner call (ptest:36)
    jne  .ge ; v1: ptest scratch #37
    mov  eax, r8d ; v1: ptest scratch #38
    ; TODO: clamp index before table lookup on malformed input (ptest:38)
    ret ; v1: ptest scratch #39
.ge: ; v1: ptest scratch #40
    ; TODO: hoist invariant pointer load out of .loop (ptest:40)
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
    ; v1 temporary guard (ptest #18)
    xor     r11d, r11d ; clear v1 slot 18
    ; v1 temporary guard (ptest #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (ptest #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (ptest #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (ptest #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (ptest #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (ptest #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (ptest #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (ptest #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (ptest #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (ptest #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (ptest #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (ptest #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (ptest #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (ptest #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (ptest #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (ptest #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (ptest #52)
    xor     r11d, r11d ; clear v1 slot 52
    ; v1 temporary guard (ptest #54)
    xor     r11d, r11d ; clear v1 slot 54
    ; v1 temporary guard (ptest #56)
    xor     r11d, r11d ; clear v1 slot 56
    ; v1 temporary guard (ptest #58)
    xor     r11d, r11d ; clear v1 slot 58
