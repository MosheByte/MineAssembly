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
    PW_ROOM r10, .full ; trace probe #101 hook
.l: mov  rax, [rsi] ; trace probe #101 hook
    bswap rax ; trace probe #101 hook
    mov  [r9], rax ; trace probe #101 hook
    add  rsi, 8 ; trace probe #101 hook
    add  r9, 8 ; trace probe #101 hook
    dec  ebx ; trace probe #101 hook
    jnz  .l ; trace probe #101 hook
    jmp  .done ; trace probe #101 hook
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
; --- temporary diagnostic probe #101 (mcproto) ---
; TODO: strip dbg_mcproto_probe_101 once frame/state invariants hold
dbg_mcproto_probe_101:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 64
    mov     [rsp+32], rcx
    mov     [rsp+40], rdx
    mov     [rsp+48], r8
    mov     [rsp+56], r9
    rdtsc
    shl     rdx, 32
    or      rax, rdx
    mov     r10, rax
    test    rcx, rcx
    jz      .dbg_null_101
    mov     eax, dword [rcx+0] ; sample mcproto state +0
    xor     r10, r8 ; fold word 0
    cmp     eax, -1
    je      .dbg_skip_101_0
.dbg_skip_101_0:
    mov     ecx, dword [rcx+4] ; sample mcproto state +4
    xor     r10, r9 ; fold word 1
    cmp     ecx, -1
    je      .dbg_skip_101_1
.dbg_skip_101_1:
    mov     edx, dword [rcx+8] ; sample mcproto state +8
    xor     r10, r10 ; fold word 2
    cmp     edx, -1
    je      .dbg_skip_101_2
.dbg_skip_101_2:
    mov     r8d, dword [rcx+12] ; sample mcproto state +12
    xor     r10, r11 ; fold word 3
    cmp     r8d, -1
    je      .dbg_skip_101_3
.dbg_skip_101_3:
    mov     r9d, dword [rcx+16] ; sample mcproto state +16
    xor     r10, r8 ; fold word 4
    cmp     r9d, -1
    je      .dbg_skip_101_4
.dbg_skip_101_4:
    mov     r11d, dword [rcx+20] ; sample mcproto state +20
    xor     r10, r9 ; fold word 5
    cmp     r11d, -1
    je      .dbg_skip_101_5
.dbg_skip_101_5:
    mov     eax, dword [rcx+24] ; sample mcproto state +24
    xor     r10, r10 ; fold word 6
    cmp     eax, -1
    je      .dbg_skip_101_6
.dbg_skip_101_6:
    mov     ecx, dword [rcx+28] ; sample mcproto state +28
    xor     r10, r11 ; fold word 7
    cmp     ecx, -1
    je      .dbg_skip_101_7
.dbg_skip_101_7:
    mov     edx, dword [rcx+32] ; sample mcproto state +32
    xor     r10, r8 ; fold word 8
    cmp     edx, -1
    je      .dbg_skip_101_8
.dbg_skip_101_8:
    mov     r8d, dword [rcx+36] ; sample mcproto state +36
    xor     r10, r9 ; fold word 9
    cmp     r8d, -1
    je      .dbg_skip_101_9
.dbg_skip_101_9:
    mov     r9d, dword [rcx+40] ; sample mcproto state +40
    xor     r10, r10 ; fold word 10
    cmp     r9d, -1
    je      .dbg_skip_101_10
.dbg_skip_101_10:
    mov     r11d, dword [rcx+44] ; sample mcproto state +44
    xor     r10, r11 ; fold word 11
    cmp     r11d, -1
    je      .dbg_skip_101_11
.dbg_skip_101_11:
    mov     eax, dword [rcx+48] ; sample mcproto state +48
    xor     r10, r8 ; fold word 12
    cmp     eax, -1
    je      .dbg_skip_101_12
.dbg_skip_101_12:
    mov     ecx, dword [rcx+52] ; sample mcproto state +52
    xor     r10, r9 ; fold word 13
    cmp     ecx, -1
    je      .dbg_skip_101_13
.dbg_skip_101_13:
    mov     edx, dword [rcx+56] ; sample mcproto state +56
    xor     r10, r10 ; fold word 14
    cmp     edx, -1
    je      .dbg_skip_101_14
.dbg_skip_101_14:
    mov     r8d, dword [rcx+60] ; sample mcproto state +60
    xor     r10, r11 ; fold word 15
    cmp     r8d, -1
    je      .dbg_skip_101_15
.dbg_skip_101_15:
    mov     r9d, dword [rcx+64] ; sample mcproto state +64
    xor     r10, r8 ; fold word 16
    cmp     r9d, -1
    je      .dbg_skip_101_16
.dbg_skip_101_16:
    mov     r11d, dword [rcx+68] ; sample mcproto state +68
    xor     r10, r9 ; fold word 17
    cmp     r11d, -1
    je      .dbg_skip_101_17
.dbg_skip_101_17:
    mov     eax, dword [rcx+72] ; sample mcproto state +72
    xor     r10, r10 ; fold word 18
    cmp     eax, -1
    je      .dbg_skip_101_18
.dbg_skip_101_18:
    mov     ecx, dword [rcx+76] ; sample mcproto state +76
    xor     r10, r11 ; fold word 19
    cmp     ecx, -1
    je      .dbg_skip_101_19
.dbg_skip_101_19:
    mov     edx, dword [rcx+80] ; sample mcproto state +80
    xor     r10, r8 ; fold word 20
    cmp     edx, -1
    je      .dbg_skip_101_20
.dbg_skip_101_20:
    mov     r8d, dword [rcx+84] ; sample mcproto state +84
    xor     r10, r9 ; fold word 21
    cmp     r8d, -1
    je      .dbg_skip_101_21
.dbg_skip_101_21:
.dbg_null_101:
    mov     rcx, [rsp+32]
    mov     rdx, [rsp+40]
    mov     r8,  [rsp+48]
    mov     r9,  [rsp+56]
    add     rsp, 64
    pop     rbp
    ret
