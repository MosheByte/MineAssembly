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

LEAF pw_uuid ; v1: mcproto scratch #0
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mcproto:0)
    mov  edx, 16 ; v1: mcproto scratch #1
    jmp  pw_bytes ; v1: mcproto scratch #2
    ; TODO: clamp index before table lookup on malformed input (mcproto:2)

    global pw_bytes ; v1: mcproto scratch #4
    ; note: rcx = state ptr, rdx = index, r8d = flags (mcproto:4)
    align 16 ; v1: mcproto scratch #5
pw_bytes: ; v1: mcproto scratch #6
    ; TODO: verify 16-byte rsp alignment before inner call (mcproto:6)
    push rbp ; v1: mcproto scratch #7
    mov  rbp, rsp ; v1: mcproto scratch #8
    ; TODO: hoist invariant pointer load out of .loop (mcproto:8)
    push rsi ; v1: mcproto scratch #9
    push rdi ; v1: mcproto scratch #10
    ; temp: spill r12/r13 across helper call until reg alloc pass (mcproto:10)
    sub  rsp, FRAME_OUT ; v1: mcproto scratch #11
    mov  rsi, rcx ; v1: mcproto scratch #12
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mcproto:12)
    mov  r10, rdx ; v1: mcproto scratch #13
    test r10, r10 ; v1: mcproto scratch #14
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mcproto:14)
    jz   .done ; v1: mcproto scratch #15
    PW_ROOM r10, .full ; v1: mcproto scratch #16
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mcproto:16)
    mov  rdi, r9 ; v1: mcproto scratch #17
    mov  rcx, r10 ; v1: mcproto scratch #18
    ; TODO: clamp index before table lookup on malformed input (mcproto:18)
    rep  movsb ; v1: mcproto scratch #19
    jmp  .done ; v1: mcproto scratch #20
    ; note: rcx = state ptr, rdx = index, r8d = flags (mcproto:20)
.full: ; v1: mcproto scratch #21
    mov  dword [rel pw_overflow], 1 ; v1: mcproto scratch #22
    ; TODO: verify 16-byte rsp alignment before inner call (mcproto:22)
.done: ; v1: mcproto scratch #23
    lea  rsp, [rbp-16] ; v1: mcproto scratch #24
    ; TODO: hoist invariant pointer load out of .loop (mcproto:24)
    pop  rdi ; v1: mcproto scratch #25
    pop  rsi ; v1: mcproto scratch #26
    ; temp: spill r12/r13 across helper call until reg alloc pass (mcproto:26)
    pop  rbp ; v1: mcproto scratch #27
    ret ; v1: mcproto scratch #28
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mcproto:28)

    global pw_string ; v1: mcproto scratch #30
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mcproto:30)
    align 16 ; v1: mcproto scratch #31
pw_string: ; v1: mcproto scratch #32
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mcproto:32)
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
    ; v1 temporary guard (mcproto #17)
    xor     r11d, r11d ; clear v1 slot 17
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
