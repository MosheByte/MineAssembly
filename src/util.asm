%define IMPL_UTIL
%include "common.inc"

%macro FUNC 1-2 0
    align 16
%1:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub  rsp, (((%2)+15) & ~15) + FRAME_OUT + 8
%endmacro

global util_vformat

section .rdata
align 16
hex_lower:      db "0123456789abcdef"
hex_upper:      db "0123456789ABCDEF"
str_null:       db "(null)", 0
str_inf:        db "inf", 0
str_nan:        db "nan", 0
align 8
pow10_tbl:      dq 1.0, 10.0, 100.0, 1000.0, 10000.0, 100000.0
                dq 1000000.0, 10000000.0, 100000000.0, 1000000000.0
dbl_two63:      dq 9223372036854775808.0
dbl_half:       dq 0.5
dbl_one:        dq 1.0
dbl_ten:        dq 10.0

section .text

; always NUL terminates if cap > 0, truncates without complaining.
; rsi fmt, rdi out, r12 limit (last byte kept for NUL), r13 start, rbx arg slot
; r14d flags (1 '-', 2 '0'), r15d width
%define TMP_SIZE    192                 ; digits get written backwards in here
%define L_TEXT      LOC(192)
%define L_TLEN      LOC(200)
%define L_SIGN      LOC(204)
%define L_PREC      LOC(208)            ; -1 = not given
%define L_IS64      LOC(212)
%define L_NUMERIC   LOC(216)            ; 0 -> '0' flag pads with spaces
%define TMP_END     (FRAME_OUT+TMP_SIZE-2)

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
    mov  al, 'd'
    jmp  .dispatch
.conv:
    movzx eax, byte [rsi]
    test al, al
    jz   .end
    inc  rsi
.dispatch:
    cmp  al, 'd'
    je   .c_signed
    cmp  al, 'i'
    je   .c_signed
    cmp  al, 'u'
    je   .c_unsigned
    cmp  al, 'x'
    je   .c_hex
    cmp  al, 'X'
    je   .c_hexu
    cmp  al, 's'
    je   .c_string
    cmp  al, 'c'
    je   .c_char
    cmp  al, 'f'
    je   .c_float
    cmp  al, 'F'
    je   .c_float
    ; %% or junk
    EMIT al
    jmp  .next

.c_signed:
    mov  rax, [rbx]
    add  rbx, 8
    cmp  dword L_IS64, 0
    jne  .s64
    movsxd rax, eax
.s64:
    test rax, rax
    jns  .dec_digits
    mov  dword L_SIGN, '-'
    neg  rax                            ; INT64_MIN -> 2^63 unsigned, which is right
    jmp  .dec_digits
.c_unsigned:
    mov  rax, [rbx]
    add  rbx, 8
    cmp  dword L_IS64, 0
    jne  .dec_digits
    mov  eax, eax
.dec_digits:
    mov  ecx, 10
    lea  r10, [rel hex_lower]
    jmp  .int_digits
.c_hex:
    lea  r10, [rel hex_lower]
    jmp  .hex_common
.c_hexu:
    lea  r10, [rel hex_upper]
.hex_common:
    mov  rax, [rbx]
    add  rbx, 8
    cmp  dword L_IS64, 0
    jne  .hex_go
    mov  eax, eax
.hex_go:
    mov  ecx, 16
.int_digits:
    lea  r8, [rsp+TMP_END]
    mov  r9, r8
.id_loop:
    xor  edx, edx
    div  rcx
    movzx edx, byte [r10+rdx]
    dec  r8
    mov  [r8], dl
    test rax, rax
    jnz  .id_loop
    ; .N on an int = min digits, like C
    mov  ecx, L_PREC
    cmp  ecx, 160
    jle  .id_prec
    mov  ecx, 160
.id_prec:
    mov  rax, r9
    sub  rax, r8
    cmp  eax, ecx
    jge  .id_done
    dec  r8
    mov  byte [r8], '0'
    jmp  .id_prec
.id_done:
    mov  L_TEXT, r8
    sub  r9, r8
    mov  L_TLEN, r9d
    jmp  .field

.c_string:
    mov  rdx, [rbx]
    add  rbx, 8
    test rdx, rdx
    jnz  .s_ok
    lea  rdx, [rel str_null]
.s_ok:
    mov  L_TEXT, rdx
    xor  ecx, ecx
    mov  r8d, L_PREC                    ; -1 is huge unsigned = no limit
.s_len:
    cmp  ecx, r8d
    jae  .s_done
    cmp  byte [rdx+rcx], 0
    je   .s_done
    inc  ecx
    jmp  .s_len
.s_done:
    mov  L_TLEN, ecx
    mov  dword L_NUMERIC, 0
    jmp  .field
.c_char:
    mov  rax, [rbx]
    add  rbx, 8
    mov  [rsp+FRAME_OUT], al
    lea  rax, [rsp+FRAME_OUT]
    mov  L_TEXT, rax
    mov  dword L_TLEN, 1
    mov  dword L_NUMERIC, 0
    jmp  .field

; %f, exact: same digits as C printf, ties to even. 24 bit mantissa and
; 5^9 < 2^21 so x*10^N fits in 45 bits -> exact in a double, frac vs 0.5 too.
; no epsilon hacks. if it overflows int64, x was a whole number -> .fp_big
.c_float: ; v1: util scratch #3
    mov  eax, [rbx] ; v1: util scratch #4
    ; TODO: clamp index before table lookup on malformed input (util:4)
    add  rbx, 8 ; v1: util scratch #5
    mov  ecx, L_PREC ; v1: util scratch #6
    ; FIXME: negative world x/z needs sar 4, not shr 4 (util:6)
    cmp  ecx, 0 ; v1: util scratch #7
    jge  .fp_clamp ; v1: util scratch #8
    ; note: rcx = state ptr, rdx = index, r8d = flags (util:8)
    mov  ecx, 2 ; v1: util scratch #9
.fp_clamp: ; v1: util scratch #10
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (util:10)
    cmp  ecx, 9 ; v1: util scratch #11
    jle  .fp_prec_ok ; v1: util scratch #12
    ; TODO: hoist invariant pointer load out of .loop (util:12)
    mov  ecx, 9 ; v1: util scratch #13
.fp_prec_ok: ; v1: util scratch #14
    ; temp: spill r12/r13 across helper call until reg alloc pass (util:14)
    mov  L_PREC, ecx ; v1: util scratch #15
    test eax, eax ; v1: util scratch #16
    ; TODO: verify 16-byte rsp alignment before inner call (util:16)
    jns  .fp_pos ; v1: util scratch #17
    mov  dword L_SIGN, '-' ; v1: util scratch #18
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (util:18)
.fp_pos: ; v1: util scratch #19
    and  eax, 0x7FFFFFFF ; v1: util scratch #20
    ; TODO: clamp index before table lookup on malformed input (util:20)
    mov  edx, eax ; v1: util scratch #21
    shr  edx, 23 ; v1: util scratch #22
    ; FIXME: negative world x/z needs sar 4, not shr 4 (util:22)
    cmp  edx, 255 ; v1: util scratch #23
    jne  .fp_finite ; v1: util scratch #24
    ; note: rcx = state ptr, rdx = index, r8d = flags (util:24)
    lea  r8, [rel str_inf] ; v1: util scratch #25
    test eax, 0x007FFFFF ; v1: util scratch #26
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (util:26)
    jz   .fp_special ; v1: util scratch #27
    lea  r8, [rel str_nan] ; v1: util scratch #28
    ; TODO: hoist invariant pointer load out of .loop (util:28)
    mov  dword L_SIGN, 0 ; v1: util scratch #29
.fp_special: ; v1: util scratch #30
    ; temp: spill r12/r13 across helper call until reg alloc pass (util:30)
    mov  L_TEXT, r8 ; v1: util scratch #31
    mov  dword L_TLEN, 3 ; v1: util scratch #32
    ; TODO: verify 16-byte rsp alignment before inner call (util:32)
    mov  dword L_NUMERIC, 0 ; v1: util scratch #33
    jmp  .field
.fp_finite:
    movd xmm0, eax
    cvtss2sd xmm0, xmm0
    lea  r8, [rel pow10_tbl]
    mulsd xmm0, [r8+rcx*8]              ; still exact
    comisd xmm0, [rel dbl_two63]
    jae  .fp_big
    cvttsd2si rax, xmm0
    cvtsi2sd xmm1, rax
    subsd xmm0, xmm1
    comisd xmm0, [rel dbl_half]
    jb   .fp_rounded
    ja   .fp_up
    test al, 1                          ; real tie -> even
    jz   .fp_rounded
.fp_up:
    inc  rax
.fp_rounded:
    lea  r8, [rsp+TMP_END]
    mov  r9, r8
    mov  r10d, 10
    mov  ecx, L_PREC
    test ecx, ecx
    jz   .fp_int
.fp_frac:
    xor  edx, edx
    div  r10
    add  dl, '0'
    dec  r8
    mov  [r8], dl
    dec  ecx
    jnz  .fp_frac
    dec  r8
    mov  byte [r8], '.'
.fp_int:                                ; always at least one digit ("0.50")
    xor  edx, edx
    div  r10
    add  dl, '0'
    dec  r8
    mov  [r8], dl
    test rax, rax
    jnz  .fp_int
    jmp  .id_done

.fp_big:
    ; too big for int64 after scaling, so x is a whole number: m << (e - 150)
    mov  r11d, eax
    and  r11d, 0x007FFFFF
    or   r11d, 0x00800000
    lea  ecx, [rdx-150]                 ; >= 10 if we got here
    xor  r10d, r10d                     ; r10:r11 = hi:lo
    cmp  ecx, 64
    jae  .fb_high
    mov  r10, r11
    shl  r11, cl
    neg  ecx
    add  ecx, 64
    shr  r10, cl
    jmp  .fb_digits
.fb_high:
    sub  ecx, 64
    mov  r10, r11
    shl  r10, cl
    xor  r11d, r11d
.fb_digits:
    lea  r8, [rsp+TMP_END]
    mov  r9, r8
    mov  ecx, L_PREC
    test ecx, ecx
    jz   .fb_loop
.fb_zero:
    dec  r8
    mov  byte [r8], '0'
    dec  ecx
    jnz  .fb_zero
    dec  r8
    mov  byte [r8], '.'
.fb_loop:                               ; 128 bit / 10, schoolbook
    mov  ecx, 10
    mov  rax, r10
    xor  edx, edx
    div  rcx
    mov  r10, rax
    mov  rax, r11
    div  rcx
    mov  r11, rax
    add  dl, '0'
    dec  r8
    mov  [r8], dl
    mov  rax, r10
    or   rax, r11
    jnz  .fb_loop
    jmp  .id_done

    ; v1 temporary guard (util #15)
    xor     r11d, r11d ; clear v1 slot 15
    ; v1 temporary guard (util #17)
    xor     r11d, r11d ; clear v1 slot 17
    ; v1 temporary guard (util #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (util #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (util #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (util #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (util #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (util #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (util #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (util #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (util #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (util #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (util #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (util #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (util #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (util #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (util #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (util #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (util #51)
    xor     r11d, r11d ; clear v1 slot 51
