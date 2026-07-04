; mcproto.asm - java protocol plumbing. g_pw writer + PKTR reader, network nbt,
; md5 for offline uuids, and the states before play (handshake, status, login,
; config). play packets go to mcplay_handle.
; big endian, varints 7 bits a byte low group first, strings varint length +
; utf-8. nbt strings are java "modified utf-8" (u16 length, astral chars as
; surrogate pairs) or emoji in chat kill the client.
%define IMPL_MCPROTO
%include "common.inc"
%include "net.inc"
%include "mcpackets.inc"

%define PW_CAP          (4*1024*1024)

%define TAG_END         0
%define TAG_BYTE        1
%define TAG_INT         3
%define TAG_STRING      8
%define TAG_COMPOUND    10
%define TAG_LONG_ARRAY  12

%define NAME_MAX        16

; PROC without the global
%macro LPROC 1-2 0
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

; PW_ROOM n, fail: reserve n bytes in g_pw -> r9 = where to write, len already
; bumped. no room -> jumps to fail. trashes rax rdx r8 r9
%macro PW_ROOM 2
    lea  rdx, [rel g_pw]
    mov  eax, [rdx+PKTW.len]
    lea  r8, [rax+%1]
    mov  r9d, [rdx+PKTW.cap]
    cmp  r8, r9
    ja   %2
    mov  [rdx+PKTW.len], r8d
    mov  r9, [rdx+PKTW.buf]
    add  r9, rax
%endmacro

; PR_NEED n, fail: rcx = PKTR*. rax = where to read, p already moved.
; err set or short -> fail. trashes rax rdx
%macro PR_NEED 2
    cmp  dword [rcx+PKTR.err], 0
    jne  %2
    mov  rax, [rcx+PKTR.p]
    mov  rdx, [rcx+PKTR.end]
    sub  rdx, rax
    cmp  rdx, %1
    jl   %2
    lea  rdx, [rax+%1]
    mov  [rcx+PKTR.p], rdx
%endmacro

section .rdata
align 16
md5_k:
    dd 0xD76AA478, 0xE8C7B756, 0x242070DB, 0xC1BDCEEE
    dd 0xF57C0FAF, 0x4787C62A, 0xA8304613, 0xFD469501
    dd 0x698098D8, 0x8B44F7AF, 0xFFFF5BB1, 0x895CD7BE
    dd 0x6B901122, 0xFD987193, 0xA679438E, 0x49B40821
    dd 0xF61E2562, 0xC040B340, 0x265E5A51, 0xE9B6C7AA
    dd 0xD62F105D, 0x02441453, 0xD8A1E681, 0xE7D3FBC8
    dd 0x21E1CDE6, 0xC33707D6, 0xF4D50D87, 0x455A14ED
    dd 0xA9E3E905, 0xFCEFA3F8, 0x676F02D9, 0x8D2A4C8A
    dd 0xFFFA3942, 0x8771F681, 0x6D9D6122, 0xFDE5380C
    dd 0xA4BEEA44, 0x4BDECFA9, 0xF6BB4B60, 0xBEBFBC70
    dd 0x289B7EC6, 0xEAA127FA, 0xD4EF3085, 0x04881D05
    dd 0xD9D4D039, 0xE6DB99E5, 0x1FA27CF8, 0xC4AC5665
    dd 0xF4292244, 0x432AFF97, 0xAB9423A7, 0xFC93A039
    dd 0x655B59C3, 0x8F0CCC92, 0xFFEFF47D, 0x85845DD1
    dd 0x6FA87E4F, 0xFE2CE6E0, 0xA3014314, 0x4E0811A1
    dd 0xF7537E82, 0xBD3AF235, 0x2AD7D2BB, 0xEB86D391
md5_s:
%rep 4
    db 7, 12, 17, 22
%endrep
%rep 4
    db 5, 9, 14, 20
%endrep
%rep 4
    db 4, 11, 16, 23
%endrep
%rep 4
    db 6, 10, 15, 21
%endrep
; which message word each round reads
md5_g:
%assign i 0
%rep 64
  %if i < 16
    db i
  %elif i < 32
    db (5*i + 1) & 15
  %elif i < 48
    db (3*i + 5) & 15
  %else
    db (7*i) & 15
  %endif
  %assign i i+1
%endrep

s_offline:      db "OfflinePlayer:", 0
s_text:         db "text", 0
s_color:        db "color", 0
s_brand_ch:     db "minecraft:brand", 0
s_brand:        db "MineAssembly", 0
s_vanilla:      db "minecraft:vanilla", 0
s_core_ns:      db "minecraft", 0
s_core_id:      db "core", 0
s_core_ver:     db MC_VERSION_NAME, 0
s_js1:          db '{"version":{"name":"', MC_VERSION_NAME, '","protocol":', 0
s_js2:          db '},"players":{"max":', 0
s_js3:          db ',"online":', 0
s_js4:          db '},"description":{"text":"MineAssembly - x86-64 asm"},"enforcesSecureChat":false}', 0
s_wrongver:     db "this server runs Minecraft ", MC_VERSION_NAME, ", please join with that version", 0
s_badname:      db "invalid username", 0
s_dupname:      db "someone with that name is already playing", 0
s_badlogin:     db "bad login packet", 0
s_full:         db "server is full", 0
s_log_join:     db "net: %s logging in from protocol %d", 0
s_log_ver:      db "net: %s has protocol %d, we speak %d", 0
s_log_ovf:      db "net: packet 0x%x too big for the writer, dropped", 0
s_log_core:     db "net: %s has minecraft:core ", MC_VERSION_NAME, ", registries go without data", 0
s_log_nocore:   db "net: %s doesn't know minecraft:core ", MC_VERSION_NAME, ", registries go with full nbt", 0

section .bss
alignb 16
global g_pw
g_pw:           resb PKTW_size
pw_overflow:    resd 1
pw_id:          resd 1

section .text

; writer

    global pw_begin
    align 16
pw_begin:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    sub  rsp, FRAME_OUT
    mov  ebx, ecx
    lea  rsi, [rel g_pw]
    cmp  qword [rsi+PKTW.buf], 0
    jne  .have
    xor  ecx, ecx
    mov  edx, PW_CAP
    mov  r8d, MEM_COMMIT | MEM_RESERVE
    mov  r9d, PAGE_READWRITE
    call VirtualAlloc
    test rax, rax
    jz   .have                      ; cap stays 0, every write overflows
    mov  [rsi+PKTW.buf], rax
    mov  dword [rsi+PKTW.cap], PW_CAP
.have:
    mov  dword [rsi+PKTW.len], 0
    mov  dword [rel pw_overflow], 0
    mov  [rel pw_id], ebx
    mov  ecx, ebx
    call pw_varint
    lea  rsp, [rbp-16]
    pop  rsi
    pop  rbx
    pop  rbp
    ret

    global pw_send
    align 16
pw_send:
    push rbp
    mov  rbp, rsp
    sub  rsp, FRAME_OUT
    test rcx, rcx
    jz   .done
    cmp  dword [rel pw_overflow], 0
    jne  .ovf
    lea  rax, [rel g_pw]
    mov  rdx, [rax+PKTW.buf]
    mov  r8d, [rax+PKTW.len]
    test r8d, r8d
    jz   .done
    call net_send_frame
    jmp  .done
.ovf:
    lea  rcx, [rel s_log_ovf]
    mov  edx, [rel pw_id]
    call log_printf
.done:
    mov  rsp, rbp
    pop  rbp
    ret

align 16
pw_full:
    mov  dword [rel pw_overflow], 1
    ret

LEAF pw_u8
    PW_ROOM 1, pw_full
    mov  [r9], cl
    ret

LEAF pw_bool
    test ecx, ecx
    setnz cl
    jmp  pw_u8

LEAF pw_u16
    PW_ROOM 2, pw_full
    rol  cx, 8
    mov  [r9], cx
    ret

LEAF pw_f32
    movd ecx, xmm0
LEAF pw_i32
    PW_ROOM 4, pw_full
    bswap ecx
    mov  [r9], ecx
    ret

LEAF pw_f64
    movq rcx, xmm0
LEAF pw_i64
    PW_ROOM 8, pw_full
    bswap rcx
    mov  [r9], rcx
    ret

; varint is the varlong encoder on the zero extended value (negatives -> 5 bytes)
LEAF pw_varint
    mov  r10d, ecx
    jmp  pw_var
LEAF pw_varlong
    mov  r10, rcx
pw_var:
    mov  rax, r10
    mov  r11d, 1
.len:
    cmp  rax, 0x80
    jb   .go
    shr  rax, 7
    inc  r11d
    jmp  .len
.go:
    PW_ROOM r11, pw_full
.put:
    mov  eax, r10d
    and  eax, 0x7F
    shr  r10, 7
    jz   .last
    or   al, 0x80
    mov  [r9], al
    inc  r9
    jmp  .put
.last:
    mov  [r9], al
    ret

; x 26 | z 26 | y 12, all two's complement
LEAF pw_position
    mov  eax, ecx
    and  eax, 0x3FFFFFF
    shl  rax, 38
    mov  r9d, r8d
    and  r9d, 0x3FFFFFF
    shl  r9, 12
    or   rax, r9
    and  edx, 0xFFF
    or   rax, rdx
    mov  rcx, rax
    jmp  pw_i64

LEAF pw_uuid
    mov  edx, 16
    jmp  pw_bytes

    global pw_bytes
    align 16
pw_bytes:
    push rbp
    mov  rbp, rsp
    push rsi
    push rdi
    sub  rsp, FRAME_OUT
    mov  rsi, rcx
    mov  r10, rdx
    test r10, r10
    jz   .done
    PW_ROOM r10, .full
    mov  rdi, r9
    mov  rcx, r10
    rep  movsb
    jmp  .done
.full:
    mov  dword [rel pw_overflow], 1
.done:
    lea  rsp, [rbp-16]
    pop  rdi
    pop  rsi
    pop  rbp
    ret

    global pw_string
    align 16
pw_string:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    sub  rsp, FRAME_OUT
    mov  rbx, rcx
    xor  esi, esi
    test rbx, rbx
    jz   .len
.l: cmp  byte [rbx+rsi], 0
    je   .len
    inc  esi
    jmp  .l
.len:
    mov  ecx, esi
    call pw_varint
    mov  rcx, rbx
    mov  edx, esi
    call pw_bytes
    lea  rsp, [rbp-16]
    pop  rsi
    pop  rbx
    pop  rbp
    ret

; nbt

; (rcx zstr) u16 length + modified utf-8. 4 byte sequences become surrogate
; pairs (6 bytes), output capped at 65535
LPROC nbt_putstr
    mov  rsi, rcx
    xor  ebx, ebx
    test rsi, rsi
    jz   .sized
.l: cmp  byte [rsi+rbx], 0
    je   .sized
    inc  rbx
    jmp  .l
.sized:
    lea  r10, [rbx+rbx*2]           ; worst case is 1.5x, keep it simple
    shr  r10, 1
    add  r10, 2
    PW_ROOM r10, .full
    lea  rdi, [r9+2]
    mov  r12, rdi                   ; start of the bytes
    lea  r13, [rsi+rbx]             ; input end
.ch:
    cmp  rsi, r13
    jae  .fin
    movzx eax, byte [rsi]
    cmp  eax, 0xF0
    jb   .plain
    cmp  eax, 0xF8
    jae  .plain
    lea  rdx, [rsi+4]
    cmp  rdx, r13
    ja   .plain
    movzx ecx, byte [rsi+1]
    movzx edx, byte [rsi+2]
    movzx r8d, byte [rsi+3]
    mov  r9d, ecx
    or   r9d, edx
    or   r9d, r8d
    mov  r11d, ecx
    and  r11d, edx
    and  r11d, r8d
    and  r9d, 0x40                  ; continuation bytes are 10xxxxxx
    jnz  .plain
    test r11d, 0x80
    jz   .plain
    and  eax, 7
    shl  eax, 18
    and  ecx, 0x3F
    shl  ecx, 12
    or   eax, ecx
    and  edx, 0x3F
    shl  edx, 6
    or   eax, edx
    and  r8d, 0x3F
    or   eax, r8d
    sub  eax, 0x10000
    jb   .plain
    mov  rdx, rdi
    sub  rdx, r12
    add  rdx, 6
    cmp  rdx, 65535
    ja   .fin
    mov  r14d, eax
    shr  eax, 10
    add  eax, 0xD800
    call .cesu
    mov  eax, r14d
    and  eax, 0x3FF
    add  eax, 0xDC00
    call .cesu
    add  rsi, 4
    jmp  .ch
.plain:
    mov  rdx, rdi
    sub  rdx, r12
    cmp  rdx, 65535
    jae  .fin
    mov  al, [rsi]
    mov  [rdi], al
    inc  rdi
    inc  rsi
    jmp  .ch
.fin:
    mov  rax, rdi
    sub  rax, r12
    rol  ax, 8
    mov  [r12-2], ax
    ; give back what the worst case reserved and we didn't use
    mov  rax, rdi
    lea  rdx, [rel g_pw]
    sub  rax, [rdx+PKTW.buf]
    mov  [rdx+PKTW.len], eax
    jmp  .done
.full:
    mov  dword [rel pw_overflow], 1
    jmp  .done
; eax = utf-16 unit -> 3 bytes at rdi
.cesu:
    mov  ecx, eax
    shr  ecx, 12
    or   ecx, 0xE0
    mov  [rdi], cl
    mov  ecx, eax
    shr  ecx, 6
    and  ecx, 0x3F
    or   ecx, 0x80
    mov  [rdi+1], cl
    and  eax, 0x3F
    or   eax, 0x80
    mov  [rdi+2], al
    add  rdi, 3
    ret
.done:
ENDP

; (ecx type, rdx name)
    align 16
nbt_head:
    push rbp
    mov  rbp, rsp
    push rbx
    sub  rsp, FRAME_OUT + 8
    mov  rbx, rdx
    call pw_u8
    mov  rcx, rbx
    call nbt_putstr
    lea  rsp, [rbp-8]
    pop  rbx
    pop  rbp
    ret

    global nbt_begin_compound
    align 16
nbt_begin_compound:
    push rbp
    mov  rbp, rsp
    push rbx
    sub  rsp, FRAME_OUT + 8
    mov  rbx, rcx
    mov  ecx, TAG_COMPOUND
    call pw_u8
    test rbx, rbx
    jz   .done                      ; nameless network root
    mov  rcx, rbx
    call nbt_putstr
.done:
    lea  rsp, [rbp-8]
    pop  rbx
    pop  rbp
    ret

LEAF nbt_end
    xor  ecx, ecx
    jmp  pw_u8

    global nbt_string
    align 16
nbt_string:
    push rbp
    mov  rbp, rsp
    push rbx
    sub  rsp, FRAME_OUT + 8
    mov  rbx, rdx
    mov  rdx, rcx
    mov  ecx, TAG_STRING
    call nbt_head
    mov  rcx, rbx
    call nbt_putstr
    lea  rsp, [rbp-8]
    pop  rbx
    pop  rbp
    ret

    global nbt_int
    align 16
nbt_int:
    push rbp
    mov  rbp, rsp
    push rbx
    sub  rsp, FRAME_OUT + 8
    mov  ebx, edx
    mov  rdx, rcx
    mov  ecx, TAG_INT
    call nbt_head
    mov  ecx, ebx
    call pw_i32
    lea  rsp, [rbp-8]
    pop  rbx
    pop  rbp
    ret

    global nbt_byte
    align 16
nbt_byte:
    push rbp
    mov  rbp, rsp
    push rbx
    sub  rsp, FRAME_OUT + 8
    mov  ebx, edx
    mov  rdx, rcx
    mov  ecx, TAG_BYTE
    call nbt_head
    mov  ecx, ebx
    call pw_u8
    lea  rsp, [rbp-8]
    pop  rbx
    pop  rbp
    ret

    global nbt_long_array
    align 16
nbt_long_array:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    sub  rsp, FRAME_OUT
    mov  rsi, rdx
    mov  ebx, r8d
    mov  rdx, rcx
    mov  ecx, TAG_LONG_ARRAY
    call nbt_head
    mov  ecx, ebx
    call pw_i32
    test ebx, ebx
    jle  .done
    mov  r10d, ebx
    shl  r10, 3
    PW_ROOM r10, .full
.l: mov  rax, [rsi]
    bswap rax
    mov  [r9], rax
    add  rsi, 8
    add  r9, 8
    dec  ebx
    jnz  .l
    jmp  .done
.full:
    mov  dword [rel pw_overflow], 1
.done:
    lea  rsp, [rbp-16]
    pop  rsi
    pop  rbx
    pop  rbp
    ret

; plain text component = a root string tag
    global pw_text
    align 16
pw_text:
    push rbp
    mov  rbp, rsp
    push rbx
    sub  rsp, FRAME_OUT + 8
    mov  rbx, rcx
    mov  ecx, TAG_STRING
    call pw_u8
    mov  rcx, rbx
    call nbt_putstr
    lea  rsp, [rbp-8]
    pop  rbx
    pop  rbp
    ret

    global pw_text_color
    align 16
pw_text_color:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    sub  rsp, FRAME_OUT
    mov  rbx, rcx
    mov  rsi, rdx
    xor  ecx, ecx
    call nbt_begin_compound
    lea  rcx, [rel s_text]
    mov  rdx, rbx
    call nbt_string
    lea  rcx, [rel s_color]
    mov  rdx, rsi
    call nbt_string
    call nbt_end
    lea  rsp, [rbp-16]
    pop  rsi
    pop  rbx
    pop  rbp
    ret

; reader

LEAF pr_init
    mov  [rcx+PKTR.p], rdx
    mov  r8d, r8d
    add  r8, rdx
    mov  [rcx+PKTR.end], r8
    mov  dword [rcx+PKTR.err], 0
    ret

align 16
pr_fail:
    mov  dword [rcx+PKTR.err], 1
    xor  eax, eax
    xorps xmm0, xmm0
    ret

LEAF pr_u8
    PR_NEED 1, pr_fail
    movzx eax, byte [rax]
    ret

LEAF pr_bool
    PR_NEED 1, pr_fail
    cmp  byte [rax], 0
    setne al
    movzx eax, al
    ret

LEAF pr_u16
    PR_NEED 2, pr_fail
    movzx eax, word [rax]
    rol  ax, 8
    ret

LEAF pr_i32
    PR_NEED 4, pr_fail
    mov  eax, [rax]
    bswap eax
    ret

LEAF pr_i64
    PR_NEED 8, pr_fail
    mov  rax, [rax]
    bswap rax
    ret

LEAF pr_f32
    PR_NEED 4, pr_fail
    mov  eax, [rax]
    bswap eax
    movd xmm0, eax
    ret

LEAF pr_f64
    PR_NEED 8, pr_fail
    mov  rax, [rax]
    bswap rax
    movq xmm0, rax
    ret

; more than 5 bytes (10 for varlong) is an error like in vanilla
LEAF pr_varint
    mov  r11, rcx
    cmp  dword [r11+PKTR.err], 0
    jne  pr_fail
    mov  r8, [r11+PKTR.p]
    mov  r9, [r11+PKTR.end]
    xor  eax, eax
    xor  ecx, ecx
.l: cmp  r8, r9
    jae  .bad
    movzx edx, byte [r8]
    inc  r8
    mov  r10d, edx
    and  edx, 0x7F
    shl  edx, cl
    or   eax, edx
    test r10d, 0x80
    jz   .ok
    add  ecx, 7
    cmp  ecx, 35
    jb   .l
.bad:
    mov  rcx, r11
    jmp  pr_fail
.ok:
    mov  [r11+PKTR.p], r8
    ret

LEAF pr_varlong
    mov  r11, rcx
    cmp  dword [r11+PKTR.err], 0
    jne  pr_fail
    mov  r8, [r11+PKTR.p]
    mov  r9, [r11+PKTR.end]
    xor  eax, eax
    xor  ecx, ecx
.l: cmp  r8, r9
    jae  .bad
    movzx edx, byte [r8]
    inc  r8
    mov  r10d, edx
    and  edx, 0x7F
    shl  rdx, cl
    or   rax, rdx
    test r10d, 0x80
    jz   .ok
    add  ecx, 7
    cmp  ecx, 70
    jb   .l
.bad:
    mov  rcx, r11
    jmp  pr_fail
.ok:
    mov  [r11+PKTR.p], r8
    ret

PROC pr_string
    mov  rbx, rcx
    mov  rdi, rdx
    mov  r12d, r8d
    test r12d, r12d
    jz   .nonul
    test rdi, rdi
    jz   .nonul
    mov  byte [rdi], 0
.nonul:
    mov  rcx, rbx
    call pr_varint
    cmp  dword [rbx+PKTR.err], 0
    jne  .zero
    test eax, eax
    js   .bad
    mov  r13d, eax                  ; wire length
    mov  rsi, [rbx+PKTR.p]
    mov  rdx, [rbx+PKTR.end]
    sub  rdx, rsi
    cmp  r13, rdx
    ja   .bad
    lea  rax, [rsi+r13]
    mov  [rbx+PKTR.p], rax
    test r12d, r12d
    jz   .zero
    test rdi, rdi
    jz   .zero
    lea  r14d, [r12d-1]
    cmp  r14, r13
    jae  .all
    ; cut: don't leave half a utf-8 char behind
.back:
    test r14, r14
    jz   .copy
    movzx eax, byte [rsi+r14]
    and  eax, 0xC0
    cmp  eax, 0x80
    jne  .copy
    dec  r14
    jmp  .back
.all:
    mov  r14, r13
.copy:
    mov  rcx, r14
    rep  movsb
    mov  byte [rdi], 0
    mov  eax, r14d
    jmp  .done
.bad:
    mov  dword [rbx+PKTR.err], 1
.zero:
    xor  eax, eax
.done:
ENDP

LEAF pr_uuid
    mov  r10, rdx
    PR_NEED 16, .bad
    mov  rdx, [rax]
    mov  [r10], rdx
    mov  rdx, [rax+8]
    mov  [r10+8], rdx
    ret
.bad:
    mov  dword [rcx+PKTR.err], 1
    xor  eax, eax
    mov  [r10], rax
    mov  [r10+8], rax
    ret

LEAF pr_position
    mov  r10, rdx
    PR_NEED 8, .bad
    mov  rax, [rax]
    bswap rax
    mov  rdx, rax
    sar  rdx, 38
    mov  [r10], edx                 ; x
    mov  rdx, rax
    shl  rdx, 52
    sar  rdx, 52
    mov  [r10+4], edx               ; y
    shl  rax, 26
    sar  rax, 38
    mov  [r10+8], eax               ; z
    ret
.bad:
    mov  dword [rcx+PKTR.err], 1
    xor  eax, eax
    mov  [r10], eax
    mov  [r10+4], eax
    mov  [r10+8], eax
    ret

LEAF pr_skip
    cmp  dword [rcx+PKTR.err], 0
    jne  .r
    mov  r8, [rcx+PKTR.p]
    mov  r9, [rcx+PKTR.end]
    sub  r9, r8
    mov  edx, edx
    cmp  rdx, r9
    ja   .bad
    add  r8, rdx
    mov  [rcx+PKTR.p], r8
.r: ret
.bad:
    mov  dword [rcx+PKTR.err], 1
    mov  r8, [rcx+PKTR.end]
    mov  [rcx+PKTR.p], r8
    ret

; md5

; (rcx state[4], rdx 64 byte block)
LPROC md5_block
    mov  rbx, rcx
    mov  rsi, rdx
    mov  r8d, [rbx]
    mov  r9d, [rbx+4]
    mov  r10d, [rbx+8]
    mov  r11d, [rbx+12]
    lea  r12, [rel md5_k]
    lea  r13, [rel md5_s]
    lea  r14, [rel md5_g]
    xor  edi, edi
.r: cmp  edi, 16
    jb   .f0
    cmp  edi, 32
    jb   .f1
    cmp  edi, 48
    jb   .f2
    mov  eax, r11d                  ; c ^ (b | ~d)
    not  eax
    or   eax, r9d
    xor  eax, r10d
    jmp  .mix
.f0:
    mov  eax, r9d                   ; (b & c) | (~b & d)
    and  eax, r10d
    mov  edx, r9d
    not  edx
    and  edx, r11d
    or   eax, edx
    jmp  .mix
.f1:
    mov  eax, r11d                  ; (d & b) | (~d & c)
    and  eax, r9d
    mov  edx, r11d
    not  edx
    and  edx, r10d
    or   eax, edx
    jmp  .mix
.f2:
    mov  eax, r9d
    xor  eax, r10d
    xor  eax, r11d
.mix:
    add  eax, r8d
    add  eax, [r12+rdi*4]
    movzx edx, byte [r14+rdi]
    add  eax, [rsi+rdx*4]
    movzx ecx, byte [r13+rdi]
    rol  eax, cl
    add  eax, r9d
    mov  r8d, r11d
    mov  r11d, r10d
    mov  r10d, r9d
    mov  r9d, eax
    inc  edi
    cmp  edi, 64
    jb   .r
    add  [rbx], r8d
    add  [rbx+4], r9d
    add  [rbx+8], r10d
    add  [rbx+12], r11d
ENDP

; mcproto_md5(rcx data, rdx len, r8 out16)
PROC mcproto_md5, 160
    mov  rsi, rcx
    mov  r12, rdx                   ; total length
    mov  r15, rdx                   ; left
    mov  rdi, r8
    mov  dword LOC(0), 0x67452301
    mov  dword LOC(4), 0xEFCDAB89
    mov  dword LOC(8), 0x98BADCFE
    mov  dword LOC(12), 0x10325476
.blk:
    cmp  r15, 64
    jb   .tail
    lea  rcx, LOC(0)
    mov  rdx, rsi
    call md5_block
    add  rsi, 64
    sub  r15, 64
    jmp  .blk
.tail:
    lea  rbx, LOC(16)               ; 128 byte pad area
    xor  eax, eax
    xor  ecx, ecx
.z: mov  [rbx+rcx*8], rax
    inc  ecx
    cmp  ecx, 16
    jb   .z
    xor  ecx, ecx
.c: cmp  rcx, r15
    jae  .cd
    mov  al, [rsi+rcx]
    mov  [rbx+rcx], al
    inc  rcx
    jmp  .c
.cd:
    mov  byte [rbx+r15], 0x80
    mov  r13d, 64
    cmp  r15, 56
    jb   .one
    mov  r13d, 128
.one:
    mov  rax, r12
    shl  rax, 3
    mov  [rbx+r13-8], rax
    lea  rcx, LOC(0)
    mov  rdx, rbx
    call md5_block
    cmp  r13d, 128
    jne  .out
    lea  rcx, LOC(0)
    lea  rdx, [rbx+64]
    call md5_block
.out:
    mov  rax, LOC(0)
    mov  [rdi], rax
    mov  rax, LOC(8)
    mov  [rdi+8], rax
ENDP

; md5("OfflinePlayer:" + name) with the version 3 / ietf variant bits, same as
; java's UUID.nameUUIDFromBytes. bytes come out in wire order
    global mc_offline_uuid
    align 16
mc_offline_uuid:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push rdi
    sub  rsp, (((128)+15) & ~15) + FRAME_OUT + 8
    mov  rsi, rcx
    mov  rbx, rdx
    lea  rdi, LOC(0)
    lea  rdx, [rel s_offline]
.p: mov  al, [rdx]
    test al, al
    jz   .n
    mov  [rdi], al
    inc  rdi
    inc  rdx
    jmp  .p
.n: lea  r8, LOC(100)               ; names are 16 max, cap way above anyway
    test rsi, rsi
    jz   .hash
.nl:
    cmp  rdi, r8
    jae  .hash
    mov  al, [rsi]
    test al, al
    jz   .hash
    mov  [rdi], al
    inc  rdi
    inc  rsi
    jmp  .nl
.hash:
    lea  rcx, LOC(0)
    mov  rdx, rdi
    sub  rdx, rcx
    mov  r8, rbx
    call mcproto_md5
    mov  al, [rbx+6]
    and  al, 0x0F
    or   al, 0x30
    mov  [rbx+6], al
    mov  al, [rbx+8]
    and  al, 0x3F
    or   al, 0x80
    mov  [rbx+8], al
    lea  rsp, [rbp-24]
    pop  rdi
    pop  rsi
    pop  rbx
    pop  rbp
    ret

; pre-play states

; (rcx dst, rdx src) -> rax at the NUL
align 16
js_cat:
    mov  al, [rdx]
    mov  [rcx], al
    test al, al
    jz   .e
    inc  rcx
    inc  rdx
    jmp  js_cat
.e: mov  rax, rcx
    ret

; (rcx dst, edx unsigned) -> rax at the NUL
align 16
js_uint:
    mov  eax, edx
    mov  r8, rcx
    mov  r9d, 10
    xor  r10d, r10d
.d: xor  edx, edx
    div  r9d
    add  dl, '0'
    push rdx
    inc  r10d
    test eax, eax
    jnz  .d
.w: pop  rdx
    mov  [r8], dl
    inc  r8
    dec  r10d
    jnz  .w
    mov  byte [r8], 0
    mov  rax, r8
    ret

; (rcx conn, r8 reader)
    align 16
mcp_handshake:
    push rbp
    mov  rbp, rsp
    push rbx
    push rdi
    sub  rsp, (((288)+15) & ~15) + FRAME_OUT
    mov  rbx, rcx
    mov  rdi, r8
    mov  rcx, rdi
    call pr_varint
    mov  [rbx+MCCONN.protocol], eax
    mov  rcx, rdi
    lea  rdx, LOC(0)
    mov  r8d, 256
    call pr_string                  ; host, don't care
    mov  rcx, rdi
    call pr_u16                     ; port
    mov  rcx, rdi
    call pr_varint
    cmp  dword [rdi+PKTR.err], 0
    jne  .kick
    mov  ecx, CN_STATUS
    cmp  eax, 1
    je   .set
    mov  ecx, CN_LOGIN
    cmp  eax, 2
    je   .set
    cmp  eax, 3                     ; transfer, nothing to transfer from so it's a login
    je   .set
.kick:
    mov  rcx, rbx
    xor  edx, edx
    call net_close
    jmp  .done
.set:
    mov  [rbx+MCCONN.state], ecx
.done:
    lea  rsp, [rbp-16]
    pop  rdi
    pop  rbx
    pop  rbp
    ret

; (rcx conn, edx id, r8 reader)
    align 16
mcp_status:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push rdi
    sub  rsp, (((512)+15) & ~15) + FRAME_OUT + 8
    mov  rbx, rcx
    mov  rdi, r8
    cmp  edx, MCP_STATUS_C2S_PING_START
    je   .info
    cmp  edx, MCP_STATUS_C2S_PING
    je   .ping
    jmp  .done
.info:
    lea  rcx, LOC(0)
    lea  rdx, [rel s_js1]
    call js_cat
    mov  rcx, rax
    mov  edx, MC_PROTOCOL_VERSION
    call js_uint
    mov  rcx, rax
    lea  rdx, [rel s_js2]
    call js_cat
    mov  rcx, rax
    mov  edx, MAX_NET_CONNS
    call js_uint
    mov  rcx, rax
    lea  rdx, [rel s_js3]
    call js_cat
    mov  rsi, rax
    call mcplay_count
    mov  rcx, rsi
    mov  edx, eax
    call js_uint
    mov  rcx, rax
    lea  rdx, [rel s_js4]
    call js_cat
    mov  ecx, MCP_STATUS_S2C_SERVER_INFO
    call pw_begin
    lea  rcx, LOC(0)
    call pw_string
    mov  rcx, rbx
    call pw_send
    jmp  .done
.ping:
    mov  rcx, rdi
    call pr_i64
    mov  rsi, rax
    cmp  dword [rdi+PKTR.err], 0
    jne  .done
    mov  ecx, MCP_STATUS_S2C_PING
    call pw_begin
    mov  rcx, rsi
    call pw_i64
    mov  rcx, rbx
    call pw_send
.done:
    lea  rsp, [rbp-24]
    pop  rdi
    pop  rsi
    pop  rbx
    pop  rbp
    ret

; (rcx a, rdx b) -> eax 1 if equal ignoring ascii case
align 16
name_eq:
.l: movzx eax, byte [rcx]
    movzx r8d, byte [rdx]
    lea  r9d, [rax-'A']
    cmp  r9d, 25
    ja   .a
    or   eax, 0x20
.a: lea  r9d, [r8-'A']
    cmp  r9d, 25
    ja   .b
    or   r8d, 0x20
.b: cmp  eax, r8d
    jne  .no
    test eax, eax
    jz   .yes
    inc  rcx
    inc  rdx
    jmp  .l
.yes:
    mov  eax, 1
    ret
.no:
    xor  eax, eax
    ret

; (rcx a, rdx b) -> eax 1 if the zstrs match exactly
align 16
zs_eq:
.l: movzx eax, byte [rcx]
    cmp  al, [rdx]
    jne  .no
    inc  rcx
    inc  rdx
    test eax, eax
    jnz  .l
    mov  eax, 1
    ret
.no:
    xor  eax, eax
    ret

; brand, feature flags, select_known_packs. registries, tags and finish go out
; once the client says which packs it has (mcp_config .packs), like vanilla
    align 16
mcp_config_start:
    push rbp
    mov  rbp, rsp
    push rbx
    sub  rsp, FRAME_OUT + 8
    mov  rbx, rcx
    mov  ecx, MCP_CONFIGURATION_S2C_CUSTOM_PAYLOAD
    call pw_begin
    lea  rcx, [rel s_brand_ch]
    call pw_string
    lea  rcx, [rel s_brand]
    call pw_string
    mov  rcx, rbx
    call pw_send
    mov  ecx, MCP_CONFIGURATION_S2C_FEATURE_FLAGS
    call pw_begin
    mov  ecx, 1
    call pw_varint
    lea  rcx, [rel s_vanilla]
    call pw_string
    mov  rcx, rbx
    call pw_send
    mov  rcx, rbx
    call mcmap_send_known_packs
    or   dword [rbx+MCCONN.flags], CF_PACKS
    lea  rsp, [rbp-8]
    pop  rbx
    pop  rbp
    ret

; (rcx conn, edx id, r8 reader)
    align 16
mcp_login:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    sub  rsp, (((128)+15) & ~15) + FRAME_OUT + 8
    mov  rbx, rcx
    mov  rdi, r8
    cmp  edx, MCP_LOGIN_C2S_LOGIN_START
    je   .start
    cmp  edx, MCP_LOGIN_C2S_LOGIN_ACKNOWLEDGED
    je   .ack
    jmp  .done                      ; encryption/plugin/cookie replies: ignored
.start:
    cmp  byte [rbx+MCCONN.name], 0
    jne  .done
    mov  rcx, rdi
    lea  rdx, LOC(0)
    mov  r8d, 64
    call pr_string
    mov  r12d, eax
    cmp  dword [rdi+PKTR.err], 0
    jne  .badpkt
    mov  eax, [rbx+MCCONN.protocol]
    cmp  eax, MC_PROTOCOL_VERSION
    jne  .wrongver
    ; vanilla rule: 1..16 chars, each 0x21..0x7E
    test r12d, r12d
    jz   .badname
    cmp  r12d, NAME_MAX
    ja   .badname
    xor  ecx, ecx
.vc:
    movzx eax, byte [rsp+FRAME_OUT+rcx]
    cmp  eax, ' '
    jbe  .badname
    cmp  eax, 0x7F
    jae  .badname
    inc  ecx
    cmp  ecx, r12d
    jb   .vc
    ; nobody else (or the host) under that name
    lea  rcx, LOC(0)
    lea  rdx, [rel g_net_host_name]
    call name_eq
    test eax, eax
    jnz  .dupname
    lea  rsi, [rel g_net_conns]
    xor  r13d, r13d
.dl:
    cmp  rsi, rbx
    je   .dn
    mov  eax, [rsi+MCCONN.state]
    cmp  eax, CN_LOGIN
    jb   .dn
    cmp  eax, CN_PLAY
    ja   .dn
    cmp  byte [rsi+MCCONN.name], 0
    je   .dn
    lea  rcx, LOC(0)
    lea  rdx, [rsi+MCCONN.name]
    call name_eq
    test eax, eax
    jnz  .dupname
.dn:
    add  rsi, MCCONN_size
    inc  r13d
    cmp  r13d, MAX_NET_CONNS
    jb   .dl
    ; ok
    lea  rcx, [rbx+MCCONN.name]
    lea  rdx, LOC(0)
    lea  r8d, [r12d+1]
.cp:
    mov  al, [rdx]
    mov  [rcx], al
    inc  rcx
    inc  rdx
    dec  r8d
    jnz  .cp
    lea  rcx, [rbx+MCCONN.name]
    lea  rdx, [rbx+MCCONN.uuid]
    call mc_offline_uuid
    lea  rcx, [rel s_log_join]
    lea  rdx, [rbx+MCCONN.name]
    mov  r8d, [rbx+MCCONN.protocol]
    call log_printf
    mov  ecx, MCP_LOGIN_S2C_SUCCESS
    call pw_begin
    lea  rcx, [rbx+MCCONN.uuid]
    call pw_uuid
    lea  rcx, [rbx+MCCONN.name]
    call pw_string
    xor  ecx, ecx                   ; no skin properties in offline mode
    call pw_varint
    mov  rcx, rbx
    call pw_send
    jmp  .done
.ack:
    cmp  byte [rbx+MCCONN.name], 0
    je   .badpkt
    mov  dword [rbx+MCCONN.state], CN_CONFIG
    cmp  dword [rbx+MCCONN.view], 0
    jne  .hasview
    mov  dword [rbx+MCCONN.view], 8
.hasview:
    mov  rcx, rbx
    call mcp_config_start
    jmp  .done
.wrongver:
    lea  rcx, [rel s_log_ver]
    lea  rdx, LOC(0)
    mov  r8d, [rbx+MCCONN.protocol]
    mov  r9d, MC_PROTOCOL_VERSION
    call log_printf
    lea  rdx, [rel s_wrongver]
    jmp  .kick
.badname:
    lea  rdx, [rel s_badname]
    jmp  .kick
.dupname:
    lea  rdx, [rel s_dupname]
    jmp  .kick
.badpkt:
    lea  rdx, [rel s_badlogin]
.kick:
    mov  rcx, rbx
    call net_close
.done:
    lea  rsp, [rbp-40]
    pop  r13
    pop  r12
    pop  rdi
    pop  rsi
    pop  rbx
    pop  rbp
    ret

; (rcx conn, edx id, r8 reader)
    align 16
mcp_config:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    sub  rsp, (((192)+15) & ~15) + FRAME_OUT + 8
    mov  rbx, rcx
    mov  rdi, r8
    cmp  edx, MCP_CONFIGURATION_C2S_FINISH_CONFIGURATION
    je   .finish
    cmp  edx, MCP_CONFIGURATION_C2S_SELECT_KNOWN_PACKS
    je   .packs
    cmp  edx, MCP_CONFIGURATION_C2S_SETTINGS
    je   .settings
    cmp  edx, MCP_CONFIGURATION_C2S_KEEP_ALIVE
    je   .ka
    jmp  .done                      ; brand, pong, resource packs: fine
.packs:
    ; the answer to our select_known_packs: [namespace, id, version]*. a vanilla
    ; client lists minecraft:core 26.1 and then has every vanilla registry entry
    ; and its data itself. junk or no core -> full nbt, which always works
    test dword [rbx+MCCONN.flags], CF_PACKS
    jz   .done                      ; not asked or answered already
    and  dword [rbx+MCCONN.flags], ~CF_PACKS
    xor  r12d, r12d                 ; 1 = has the core pack
    mov  rcx, rdi
    call pr_varint
    mov  r13d, eax
    cmp  dword [rdi+PKTR.err], 0
    jne  .packs_send
    cmp  r13d, 64                   ; vanilla's cap too
    ja   .packs_send
.pk:
    test r13d, r13d
    jz   .packs_send
    mov  rcx, rdi
    lea  rdx, LOC(0)
    mov  r8d, 64
    call pr_string
    mov  rcx, rdi
    lea  rdx, LOC(64)
    mov  r8d, 64
    call pr_string
    mov  rcx, rdi
    lea  rdx, LOC(128)
    mov  r8d, 64
    call pr_string
    cmp  dword [rdi+PKTR.err], 0
    jne  .packs_junk
    lea  rcx, LOC(0)
    lea  rdx, [rel s_core_ns]
    call zs_eq
    mov  esi, eax
    lea  rcx, LOC(64)
    lea  rdx, [rel s_core_id]
    call zs_eq
    and  esi, eax
    lea  rcx, LOC(128)
    lea  rdx, [rel s_core_ver]
    call zs_eq
    and  esi, eax
    or   r12d, esi
    dec  r13d
    jmp  .pk
.packs_junk:
    xor  r12d, r12d
.packs_send:
    lea  rcx, [rel s_log_nocore]
    lea  rax, [rel s_log_core]
    test r12d, r12d
    cmovnz rcx, rax
    lea  rdx, [rbx+MCCONN.name]
    call log_printf
    mov  rcx, rbx
    mov  edx, r12d
    call mcmap_send_registries
    mov  ecx, MCP_CONFIGURATION_S2C_FINISH_CONFIGURATION
    call pw_begin
    mov  rcx, rbx
    call pw_send
    or   dword [rbx+MCCONN.flags], CF_CFG_DONE
    jmp  .done
.settings:
    mov  rcx, rdi
    lea  rdx, LOC(0)
    mov  r8d, 32
    call pr_string                  ; locale
    mov  rcx, rdi
    call pr_u8
    cmp  dword [rdi+PKTR.err], 0
    jne  .done
    movsx eax, al
    mov  ecx, 2
    cmp  eax, ecx
    cmovl eax, ecx
    mov  ecx, 32
    cmp  eax, ecx
    cmovg eax, ecx
    mov  [rbx+MCCONN.view], eax
    jmp  .done
.ka:
    mov  rcx, rdi
    call pr_i64
    cmp  dword [rdi+PKTR.err], 0
    jne  .done
    cmp  rax, [rbx+MCCONN.ka_id]
    jne  .done
    mov  qword [rbx+MCCONN.ka_time], 0
    jmp  .done
.finish:
    test dword [rbx+MCCONN.flags], CF_CFG_DONE
    jz   .done                      ; we haven't finished our side yet
    and  dword [rbx+MCCONN.flags], ~CF_CFG_DONE
    mov  dword [rbx+MCCONN.state], CN_PLAY
    mov  rcx, rbx
    call mcplay_join
.done:
    lea  rsp, [rbp-40]
    pop  r13
    pop  r12
    pop  rdi
    pop  rsi
    pop  rbx
    pop  rbp
    ret

; one frame body (id + fields), uncompressed
    global mc_handle_packet ; v1: mcproto scratch #2
    ; TODO: verify 16-byte rsp alignment before inner call (mcproto:2)
    align 16 ; v1: mcproto scratch #3
mc_handle_packet: ; v1: mcproto scratch #4
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mcproto:4)
    push rbp ; v1: mcproto scratch #5
    mov  rbp, rsp ; v1: mcproto scratch #6
    ; TODO: clamp index before table lookup on malformed input (mcproto:6)
    push rbx ; v1: mcproto scratch #7
    push rsi ; v1: mcproto scratch #8
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mcproto:8)
    sub  rsp, (((32)+15) & ~15) + FRAME_OUT ; v1: mcproto scratch #9
    mov  rbx, rcx ; v1: mcproto scratch #10
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mcproto:10)
    lea  rcx, LOC(0) ; v1: mcproto scratch #11
    call pr_init ; v1: mcproto scratch #12
    ; temp: spill r12/r13 across helper call until reg alloc pass (mcproto:12)
    lea  rcx, LOC(0) ; v1: mcproto scratch #13
    call pr_varint ; v1: mcproto scratch #14
    ; TODO: hoist invariant pointer load out of .loop (mcproto:14)
    mov  esi, eax ; v1: mcproto scratch #15
    cmp  dword LOC(PKTR.err), 0 ; v1: mcproto scratch #16
    ; note: rcx = state ptr, rdx = index, r8d = flags (mcproto:16)
    jne  .done ; v1: mcproto scratch #17
    mov  eax, [rbx+MCCONN.state] ; v1: mcproto scratch #18
    ; TODO: verify 16-byte rsp alignment before inner call (mcproto:18)
    mov  rcx, rbx ; v1: mcproto scratch #19
    mov  edx, esi ; v1: mcproto scratch #20
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mcproto:20)
    lea  r8, LOC(0) ; v1: mcproto scratch #21
    cmp  eax, CN_PLAY ; v1: mcproto scratch #22
    ; TODO: clamp index before table lookup on malformed input (mcproto:22)
    je   .play ; v1: mcproto scratch #23
    cmp  eax, CN_CONFIG ; v1: mcproto scratch #24
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mcproto:24)
    je   .config ; v1: mcproto scratch #25
    cmp  eax, CN_LOGIN ; v1: mcproto scratch #26
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mcproto:26)
    je   .login ; v1: mcproto scratch #27
    cmp  eax, CN_STATUS ; v1: mcproto scratch #28
    ; temp: spill r12/r13 across helper call until reg alloc pass (mcproto:28)
    je   .status ; v1: mcproto scratch #29
    cmp  eax, CN_HANDSHAKE ; v1: mcproto scratch #30
    ; TODO: hoist invariant pointer load out of .loop (mcproto:30)
    jne  .done ; v1: mcproto scratch #31
    cmp  esi, MCP_HANDSHAKING_C2S_SET_PROTOCOL ; v1: mcproto scratch #32
    ; note: rcx = state ptr, rdx = index, r8d = flags (mcproto:32)
    jne  .junk ; v1: mcproto scratch #33
    call mcp_handshake ; v1: mcproto scratch #34
    ; TODO: verify 16-byte rsp alignment before inner call (mcproto:34)
    jmp  .done ; v1: mcproto scratch #35
.junk: ; v1: mcproto scratch #36
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mcproto:36)
    xor  edx, edx ; v1: mcproto scratch #37
    call net_close ; v1: mcproto scratch #38
    ; TODO: clamp index before table lookup on malformed input (mcproto:38)
    jmp  .done ; v1: mcproto scratch #39
.play:
    call mcplay_handle
    jmp  .done
.config:
    call mcp_config
    jmp  .done
.login:
    call mcp_login
    jmp  .done
.status:
    call mcp_status
.done:
    lea  rsp, [rbp-16]
    pop  rsi
    pop  rbx
    pop  rbp
    ret
    ; v1 temporary guard (mcproto #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (mcproto #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (mcproto #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (mcproto #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (mcproto #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (mcproto #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (mcproto #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (mcproto #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (mcproto #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (mcproto #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (mcproto #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (mcproto #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (mcproto #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (mcproto #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (mcproto #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (mcproto #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (mcproto #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (mcproto #53)
    xor     r11d, r11d ; clear v1 slot 53
    ; v1 temporary guard (mcproto #55)
    xor     r11d, r11d ; clear v1 slot 55
    ; v1 temporary guard (mcproto #57)
    xor     r11d, r11d ; clear v1 slot 57
    ; v1 temporary guard (mcproto #59)
    xor     r11d, r11d ; clear v1 slot 59
    ; v1 temporary guard (mcproto #61)
    xor     r11d, r11d ; clear v1 slot 61
    ; v1 temporary guard (mcproto #63)
    xor     r11d, r11d ; clear v1 slot 63
