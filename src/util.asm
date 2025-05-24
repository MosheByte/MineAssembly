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
.c_float:
    mov  eax, [rbx]
    add  rbx, 8
    mov  ecx, L_PREC
    cmp  ecx, 0
    jge  .fp_clamp
    mov  ecx, 2
.fp_clamp:
    cmp  ecx, 9
    jle  .fp_prec_ok
    mov  ecx, 9
.fp_prec_ok:
    mov  L_PREC, ecx
    test eax, eax
    jns  .fp_pos
    mov  dword L_SIGN, '-'
.fp_pos:
    and  eax, 0x7FFFFFFF
    mov  edx, eax
    shr  edx, 23
    cmp  edx, 255
    jne  .fp_finite
    lea  r8, [rel str_inf]
    test eax, 0x007FFFFF
    jz   .fp_special
    lea  r8, [rel str_nan]
    mov  dword L_SIGN, 0
.fp_special:
    mov  L_TEXT, r8
    mov  dword L_TLEN, 3
    mov  dword L_NUMERIC, 0
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

.field:
    mov  eax, L_TLEN
    cmp  dword L_SIGN, 0
    je   .fl_nosign
    inc  eax
.fl_nosign:
    mov  ecx, r15d
    sub  ecx, eax
    test r14d, 1
    jnz  .fl_sign
    test r14d, 2
    jz   .fl_lspaces
    cmp  dword L_NUMERIC, 0
    jne  .fl_sign                       ; zeros go after the '-', not before
.fl_lspaces:
    test ecx, ecx
    jle  .fl_sign
    mov  dl, ' '
.fl_ls:
    EMIT dl
    dec  ecx
    jnz  .fl_ls
.fl_sign:
    mov  eax, L_SIGN
    test eax, eax
    jz   .fl_zeros
    EMIT al
.fl_zeros:
    test r14d, 1
    jnz  .fl_text
    test r14d, 2
    jz   .fl_text
    cmp  dword L_NUMERIC, 0
    je   .fl_text
    test ecx, ecx
    jle  .fl_text
    mov  dl, '0'
.fl_z:
    EMIT dl
    dec  ecx
    jnz  .fl_z
.fl_text:
    mov  r8, L_TEXT
    mov  r9d, L_TLEN
    test r9d, r9d
    jz   .fl_right
.fl_t:
    mov  al, [r8]
    EMIT al
    inc  r8
    dec  r9d
    jnz  .fl_t
.fl_right:
    test r14d, 1
    jz   .next
    test ecx, ecx
    jle  .next
    mov  dl, ' '
.fl_rs:
    EMIT dl
    dec  ecx
    jnz  .fl_rs
    jmp  .next

.end:
    mov  byte [rdi], 0
    mov  rax, rdi
    sub  rax, r13
.ret:
    ENDP

; spill r8/r9 into the home area and [rbp+32..] is one flat arg array. nice
    global str_format
    align 16
str_format:
    push rbp
    mov  rbp, rsp
    push rsi
    push rdi
    push r12
    sub  rsp, FRAME_OUT + 8
    mov  [rbp+32], r8
    mov  [rbp+40], r9
    lea  r8, [rbp+32]
    mov  r9, 0x7FFFFFFF                 ; unbounded, caller's buffer had better be big enough
    call util_vformat
    lea  rsp, [rbp-24]
    pop  r12
    pop  rdi
    pop  rsi
    pop  rbp
    ret

LEAF str_len
    mov  rax, rcx
.l: cmp  byte [rax], 0
    je   .d
    inc  rax
    jmp  .l
.d: sub  rax, rcx
    ret

; -> rax = the NUL in dst, handy for chaining
LEAF str_copy
.l: mov  al, [rdx]
    mov  [rcx], al
    test al, al
    jz   .d
    inc  rcx
    inc  rdx
    jmp  .l
.d: mov  rax, rcx
    ret

; r8 = max incl NUL, 0 touches nothing
LEAF str_ncopy
    mov  rax, rcx
    test r8, r8
    jz   .ret
    dec  r8
.l: test r8, r8
    jz   .term
    mov  r9b, [rdx]
    test r9b, r9b
    jz   .term
    mov  [rax], r9b
    inc  rax
    inc  rdx
    dec  r8
    jmp  .l
.term:
    mov  byte [rax], 0
.ret:
    ret

LEAF str_cat
.f: cmp  byte [rcx], 0
    je   .c
    inc  rcx
    jmp  .f
.c: mov  al, [rdx]
    mov  [rcx], al
    test al, al
    jz   .d
    inc  rcx
    inc  rdx
    jmp  .c
.d: mov  rax, rcx
    ret

LEAF str_cmp
.l: movzx eax, byte [rcx]
    movzx r8d, byte [rdx]
    sub  eax, r8d
    jnz  .d
    test r8d, r8d
    jz   .d
    inc  rcx
    inc  rdx
    jmp  .l
.d: ret

; ascii only
LEAF str_eq_nocase
.l: movzx eax, byte [rcx]
    movzx r8d, byte [rdx]
    lea  r9d, [rax-'A']
    cmp  r9d, 25
    ja   .a_ok
    add  eax, 32
.a_ok:
    lea  r9d, [r8-'A']
    cmp  r9d, 25
    ja   .b_ok
    add  r8d, 32
.b_ok:
    cmp  eax, r8d
    jne  .ne
    test eax, eax
    jz   .eq
    inc  rcx
    inc  rdx
    jmp  .l
.eq: mov  eax, 1
    ret
.ne: xor  eax, eax
    ret

LEAF str_starts_with
.l: movzx r8d, byte [rdx]
    test r8d, r8d
    jz   .yes
    cmp  r8b, [rcx]
    jne  .no
    inc  rcx
    inc  rdx
    jmp  .l
.yes:
    mov  eax, 1
    ret
.no:
    xor  eax, eax
    ret

; strtol-ish, optional 0x. no digits -> 0 and *end = s
LEAF str_to_int
    mov  r10, rcx
.sp:
    movzx eax, byte [rcx]
    cmp  al, ' '
    je   .skip
    cmp  al, 9
    je   .skip
    jmp  .sign
.skip:
    inc  rcx
    jmp  .sp
.sign:
    xor  r9d, r9d
    cmp  al, '-'
    jne  .plus
    mov  r9d, 1
    inc  rcx
    jmp  .base
.plus:
    cmp  al, '+'
    jne  .base
    inc  rcx
.base:
    xor  eax, eax
    xor  r11d, r11d
    cmp  byte [rcx], '0'
    jne  .dec
    movzx r8d, byte [rcx+1]
    or   r8d, 0x20
    cmp  r8d, 'x'
    jne  .dec
    ; "0x" with nothing after it is just 0, not hex
    movzx r8d, byte [rcx+2]
    call .hexval
    cmp  r8d, 15
    ja   .dec
    add  rcx, 2
.hex:
    movzx r8d, byte [rcx]
    call .hexval
    cmp  r8d, 15
    ja   .done
    shl  rax, 4
    add  rax, r8
    inc  r11d
    inc  rcx
    jmp  .hex
.dec:
    movzx r8d, byte [rcx]
    sub  r8d, '0'
    cmp  r8d, 9
    ja   .done
    imul rax, rax, 10
    add  rax, r8
    inc  r11d
    inc  rcx
    jmp  .dec
.done:
    test r11d, r11d
    jnz  .have
    mov  rcx, r10
    xor  eax, eax
.have:
    test r9d, r9d
    jz   .pos
    neg  rax
.pos:
    test rdx, rdx
    jz   .ret
    mov  [rdx], rcx
.ret:
    ret
; only touches r8. 0xFF = not hex
.hexval:
    sub  r8d, '0'
    cmp  r8d, 9
    jbe  .hv_ret
    add  r8d, '0'
    or   r8d, 0x20
    sub  r8d, 'a'
    cmp  r8d, 5
    ja   .hv_bad
    add  r8d, 10
    ret
.hv_bad:
    mov  r8d, 0xFF
.hv_ret:
    ret

; <= 18 sig digits into an int64 (exact), then one mul/div by 10^exp. same 0.1f as strtof
LEAF str_to_float
.sp:
    movzx eax, byte [rcx]
    cmp  al, ' '
    je   .skip
    cmp  al, 9
    jne  .sign
.skip:
    inc  rcx
    jmp  .sp
.sign:
    xor  r9d, r9d
    cmp  al, '-'
    jne  .plus
    mov  r9d, 1
    inc  rcx
    jmp  .mant
.plus:
    cmp  al, '+'
    jne  .mant
    inc  rcx
.mant:
    xor  eax, eax
    xor  r10d, r10d
    xor  r11d, r11d
.int:
    movzx edx, byte [rcx]
    sub  edx, '0'
    cmp  edx, 9
    ja   .dot
    inc  rcx
    cmp  r11d, 18
    jae  .int_drop
    imul rax, rax, 10
    add  rax, rdx
    test rax, rax
    jz   .int                           ; leading zeros don't count
    inc  r11d
    jmp  .int
.int_drop:
    inc  r10d
    jmp  .int
.dot:
    cmp  byte [rcx], '.'
    jne  .exp
    inc  rcx
.frac:
    movzx edx, byte [rcx]
    sub  edx, '0'
    cmp  edx, 9
    ja   .exp
    inc  rcx
    cmp  r11d, 18
    jae  .frac                          ; past 18 digits, who cares
    imul rax, rax, 10
    add  rax, rdx
    dec  r10d
    test rax, rax
    jz   .frac
    inc  r11d
    jmp  .frac
.exp:
    movzx edx, byte [rcx]
    or   edx, 0x20
    cmp  edx, 'e'
    jne  .build
    inc  rcx
    xor  r8d, r8d
    cmp  byte [rcx], '-'
    jne  .ep
    mov  r8d, 1
    inc  rcx
    jmp  .ed_start
.ep:
    cmp  byte [rcx], '+'
    jne  .ed_start
    inc  rcx
.ed_start:
    xor  r11d, r11d
.ed:
    movzx edx, byte [rcx]
    sub  edx, '0'
    cmp  edx, 9
    ja   .ed_done
    imul r11d, r11d, 10
    add  r11d, edx
    inc  rcx
    cmp  r11d, 400
    jb   .ed
    mov  r11d, 400
    jmp  .ed
.ed_done:
    test r8d, r8d
    jz   .ed_add
    neg  r11d
.ed_add:
    add  r10d, r11d
.build:
    cvtsi2sd xmm0, rax
    ; 10^|r10| the dumb way, loop of mulsd. |r10| <= ~420 so whatever
    movsd xmm1, [rel dbl_one]
    mov  edx, r10d
    test edx, edx
    jns  .pw
    neg  edx
.pw:
    test edx, edx
    jz   .apply
    mulsd xmm1, [rel dbl_ten]
    dec  edx
    jmp  .pw
.apply:
    test r10d, r10d
    js   .divide
    mulsd xmm0, xmm1
    jmp  .fin
.divide:
    divsd xmm0, xmm1
.fin:
    cvtsd2ss xmm0, xmm0
    test r9d, r9d
    jz   .ret
    mov  eax, 0x80000000
    movd xmm1, eax
    xorps xmm0, xmm1
.ret:
    ret

; FNV-1a
LEAF str_hash
    mov  rax, 0xcbf29ce484222325
    mov  r8, 0x100000001b3
.l: movzx edx, byte [rcx]
    test edx, edx
    jz   .d
    xor  rax, rdx
    imul rax, r8
    inc  rcx
    jmp  .l
.d: ret

; no overlap! rep movsb is fine on anything with ERMSB
LEAF mem_copy
    push rsi
    push rdi
    mov  rdi, rcx
    mov  rsi, rdx
    mov  rcx, r8
    rep  movsb
    pop  rdi
    pop  rsi
    ret

LEAF mem_set
    push rdi
    mov  rdi, rcx
    mov  eax, edx
    mov  rcx, r8
    rep  stosb
    pop  rdi
    ret

LEAF mem_zero
    push rdi
    mov  rdi, rcx
    xor  eax, eax
    mov  rcx, rdx
    rep  stosb
    pop  rdi
    ret
