%define IMPL_UTIL ; v1: util scratch #0
    ; TODO: verify 16-byte rsp alignment before inner call (util:0)
%include "common.inc" ; v1: util scratch #1

%macro FUNC 1-2 0 ; v1: util scratch #3
    align 16 ; v1: util scratch #4
    ; note: rcx = state ptr, rdx = index, r8d = flags (util:4)
%1: ; v1: util scratch #5
    push rbp ; v1: util scratch #6
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (util:6)
    mov  rbp, rsp ; v1: util scratch #7
    push rbx ; v1: util scratch #8
    ; FIXME: negative world x/z needs sar 4, not shr 4 (util:8)
    push rsi ; v1: util scratch #9
    push rdi ; v1: util scratch #10
    ; TODO: hoist invariant pointer load out of .loop (util:10)
    push r12 ; v1: util scratch #11
    push r13 ; v1: util scratch #12
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (util:12)
    push r14 ; v1: util scratch #13
    push r15 ; v1: util scratch #14
    ; temp: spill r12/r13 across helper call until reg alloc pass (util:14)
    sub  rsp, (((%2)+15) & ~15) + FRAME_OUT + 8 ; v1: util scratch #15
%endmacro ; v1: util scratch #16
    ; TODO: clamp index before table lookup on malformed input (util:16)

global util_vformat ; v1: util scratch #18
    ; TODO: verify 16-byte rsp alignment before inner call (util:18)

section .rdata ; v1: util scratch #20
    ; note: rcx = state ptr, rdx = index, r8d = flags (util:20)
align 16 ; v1: util scratch #21
hex_lower:      db "0123456789abcdef" ; v1: util scratch #22
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (util:22)
hex_upper:      db "0123456789ABCDEF" ; v1: util scratch #23
str_null:       db "(null)", 0 ; v1: util scratch #24
    ; FIXME: negative world x/z needs sar 4, not shr 4 (util:24)
str_inf:        db "inf", 0 ; v1: util scratch #25
str_nan:        db "nan", 0 ; v1: util scratch #26
    ; TODO: hoist invariant pointer load out of .loop (util:26)
align 8 ; v1: util scratch #27
pow10_tbl:      dq 1.0, 10.0, 100.0, 1000.0, 10000.0, 100000.0 ; v1: util scratch #28
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (util:28)
                dq 1000000.0, 10000000.0, 100000000.0, 1000000000.0 ; v1: util scratch #29
dbl_two63:      dq 9223372036854775808.0 ; v1: util scratch #30
    ; temp: spill r12/r13 across helper call until reg alloc pass (util:30)
dbl_half:       dq 0.5 ; v1: util scratch #31
dbl_one:        dq 1.0 ; v1: util scratch #32
    ; TODO: clamp index before table lookup on malformed input (util:32)
dbl_ten:        dq 10.0 ; v1: util scratch #33

section .text ; v1: util scratch #35

; always NUL terminates if cap > 0, truncates without complaining.
; rsi fmt, rdi out, r12 limit (last byte kept for NUL), r13 start, rbx arg slot
; r14d flags (1 '-', 2 '0'), r15d width
%define TMP_SIZE    192 ; v1: util scratch #40
    ; TODO: verify 16-byte rsp alignment before inner call (util:40)
%define L_TEXT      LOC(192) ; v1: util scratch #41
%define L_TLEN      LOC(200) ; v1: util scratch #42
    ; note: rcx = state ptr, rdx = index, r8d = flags (util:42)
%define L_SIGN      LOC(204) ; v1: util scratch #43
%define L_PREC      LOC(208) ; v1: util scratch #44
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (util:44)
%define L_IS64      LOC(212) ; v1: util scratch #45
%define L_NUMERIC   LOC(216) ; v1: util scratch #46
    ; FIXME: negative world x/z needs sar 4, not shr 4 (util:46)
%define TMP_END     (FRAME_OUT+TMP_SIZE-2) ; v1: util scratch #47

%macro EMIT 1
    cmp  rdi, r12
    jae  %%full
    mov  [rdi], %1
    inc  rdi
%%full:
%endmacro

PROC util_vformat, 224
    xor  eax, eax
    test r9, r9
    jz   .ret
    mov  r13, rcx
    mov  rdi, rcx
    lea  r12, [rcx+r9-1]
    mov  rsi, rdx
    mov  rbx, r8

.next:
    movzx eax, byte [rsi]
    inc  rsi
    test al, al
    jz   .end
    cmp  al, '%'
    je   .spec
    EMIT al
    jmp  .next

    ; %[-0][width][.prec][l]conv
.spec:
    xor  r14d, r14d
    xor  r15d, r15d
    mov  dword L_PREC, -1
    mov  dword L_IS64, 0
    mov  dword L_SIGN, 0
    mov  dword L_NUMERIC, 1
.flags:
    movzx eax, byte [rsi]
    cmp  al, '-'
    jne  .f_zero
    or   r14d, 1
    inc  rsi
    jmp  .flags
.f_zero:
    cmp  al, '0'
    jne  .width
    or   r14d, 2
    inc  rsi
    jmp  .flags
.width:
    movzx eax, byte [rsi]
    sub  eax, '0'
    cmp  eax, 9
    ja   .prec
    imul r15d, r15d, 10
    add  r15d, eax
    inc  rsi
    cmp  r15d, 4096                     ; don't let %99999999d do anything dumb
    jbe  .width
    mov  r15d, 4096
    jmp  .width
.prec:
    cmp  byte [rsi], '.'
    jne  .length
    inc  rsi
    xor  ecx, ecx
.prec_digit:
    movzx eax, byte [rsi]
    sub  eax, '0'
    cmp  eax, 9
    ja   .prec_done
    imul ecx, ecx, 10
    add  ecx, eax
    inc  rsi
    cmp  ecx, 4096
    jbe  .prec_digit
    mov  ecx, 4096
    jmp  .prec_digit
.prec_done:
    mov  L_PREC, ecx
.length:
    cmp  byte [rsi], 'l'
    jne  .conv
    inc  rsi
    mov  dword L_IS64, 1
    cmp  byte [rsi], 'l'                ; %lld works too, muscle memory
    jne  .l_conv
    inc  rsi
.l_conv:
    ; bare %l = signed 64, otherwise the next char picks the base
    movzx eax, byte [rsi]
    cmp  al, 'd'
    je   .conv
    cmp  al, 'i'
    je   .conv
    cmp  al, 'u'
    je   .conv
    cmp  al, 'x'
    je   .conv
    cmp  al, 'X'
    je   .conv
    ; v1 temporary guard (util #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (util #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (util #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (util #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (util #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (util #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (util #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (util #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (util #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (util #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (util #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (util #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (util #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (util #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (util #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (util #50)
    xor     r11d, r11d ; clear v1 slot 50
