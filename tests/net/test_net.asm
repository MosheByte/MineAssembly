; test_net.asm - net.asm over real loopback sockets: host on a high port, connect
; to ourselves, poke at the framing (partial frames, split varints, several frames
; per recv, big frames both ways), closing, timeouts, net_stop.
; mcproto/mcplay are faked below, time_ms too so the login timeout is testable.
; @link src/net.asm
; @timeout 60
%define IMPL_MCPROTO
%define IMPL_MCPLAY
%define IMPL_PLATFORM
%include "common.inc"
%include "net.inc"
%include "mcpackets.inc"
%include "testlib.inc"

extern socket, connect, send, recv, closesocket, ioctlsocket, WSAGetLastError

%define TPORT           48613
%define AF_INET         2
%define SOCK_STREAM     1
%define IPPROTO_TCP     6
%define FIONBIO         0x8004667E
%define WSAEWOULDBLOCK  10035
%define BIG_IN          300000
%define BIG_OUT         3000000

%if MCP_LOGIN_S2C_DISCONNECT > 127 || MCP_CONFIGURATION_S2C_DISCONNECT > 127 || MCP_PLAY_S2C_KICK_DISCONNECT > 127
%error "the expected bytes below assume 1 byte packet ids"
%endif

section .rdata
f_one:      db 3, 0x10, 0xAA, 0xBB
f_one_body: db 0x10, 0xAA, 0xBB
f_half1:    db 5, 0x11, 1, 2
f_half2:    db 3, 4
f_half_all: db 0x11, 1, 2, 3, 4
f_multi:    db 2, 0x20, 1,  1, 0x21,  4, 0x22, 1, 2, 3
f_vi1:      db 0xC8                         ; 200 = C8 01, split after the first byte
f_name:     db 6, 0x71, 'Steve'
f_echo_hdr: db 101, 0x73
f_login:    db 2, 0x70, CN_LOGIN
f_play:     db 2, 0x70, CN_PLAY
f_config:   db 2, 0x70, CN_CONFIG
f_kick:     db 1, 0x72,  3, 0x10, 1, 2
f_badvi:    db 0xFF, 0xFF, 0xFF, 0xFF, 0x0F
f_zero:     db 0
f_legacy:   db 0xFE, 0x01, 0xFA
s_bye:      db 'bye "x"', 0
s_kicked:   db 'kicked', 0
x_login:    db 22, MCP_LOGIN_S2C_DISCONNECT, 20, '{"text":"bye \"x\""}'
x_login_len equ $ - x_login
x_kick:     db 10, MCP_PLAY_S2C_KICK_DISCONNECT, 8, 0, 6, 'kicked'
x_kick_len  equ $ - x_kick
x_stop:     db 17, MCP_CONFIGURATION_S2C_DISCONNECT, 8, 0, 13, 'Server closed'
x_stop_len  equ $ - x_stop
x_bigout_hdr: db 0xC0, 0x8D, 0xB7, 0x01     ; varint 3000000

section .bss
alignb 16
global g_pw
g_pw:       resb PKTW_size
fake_now:   resq 1
h_count:    resd 1
h_len:      resd 1
h_sum:      resq 1
h_conn:     resq 1
h_data:     resb 64
h_ids:      resb 64
h_lens:     resd 64
left_count: resd 1
left_state: resd 1
cl_conn:    resq 1
cl_eof:     resd 1
alignb 16
pw_buf:     resb 4096
tmp:        resb 4096
alignb 16
big:        resb BIG_OUT + 64
rbig:       resb BIG_OUT + 64

section .text

; fakes

LEAF time_ms
    mov  rax, [rel fake_now]
    ret

; records every frame. first byte is a command for the tests:
; 70 s = set state, 71 name.. = set name, 72 = net_close, 73 = echo the frame back
PROC mc_handle_packet, 0
    mov  rbx, rcx
    mov  rsi, rdx
    mov  r12d, r8d
    mov  eax, [rel h_count]
    and  eax, 63
    movzx ecx, byte [rsi]
    lea  rdx, [rel h_ids]
    mov  [rdx + rax], cl
    lea  rdx, [rel h_lens]
    mov  [rdx + rax*4], r12d
    inc  dword [rel h_count]
    mov  [rel h_len], r12d
    mov  [rel h_conn], rbx
    xor  eax, eax
    xor  ecx, ecx
.sum:
    movzx edx, byte [rsi + rcx]
    add  rax, rdx
    inc  ecx
    cmp  ecx, r12d
    jb   .sum
    mov  [rel h_sum], rax
    mov  ecx, r12d
    cmp  ecx, 64
    jbe  .cp
    mov  ecx, 64
.cp:
    lea  rdi, [rel h_data]
    push rsi
    rep  movsb
    pop  rsi
    movzx eax, byte [rsi]
    cmp  eax, 0x70
    je   .state
    cmp  eax, 0x71
    je   .name
    cmp  eax, 0x72
    je   .kick
    cmp  eax, 0x73
    je   .echo
    jmp  .done
.state:
    movzx eax, byte [rsi + 1]
    mov  [rbx + MCCONN.state], eax
    jmp  .done
.name:
    lea  rdi, [rbx + MCCONN.name]
    lea  ecx, [r12 - 1]
    lea  rsi, [rsi + 1]
    rep  movsb
    mov  byte [rdi], 0
    jmp  .done
.kick:
    mov  rcx, rbx
    lea  rdx, [rel s_kicked]
    call net_close
    jmp  .done
.echo:
    mov  rcx, rbx
    mov  rdx, rsi
    mov  r8d, r12d
    call net_send_frame
.done:
ENDP

PROC mcplay_left, 0
    inc  dword [rel left_count]
    mov  eax, [rcx + MCCONN.state]
    mov  [rel left_state], eax
ENDP

; ecx -> varint at the end of g_pw
align 16
pw_put_varint:
    lea  r10, [rel pw_buf]
    mov  r11d, [rel g_pw + PKTW.len]
.l:
    mov  eax, ecx
    and  eax, 0x7F
    shr  ecx, 7
    jz   .last
    or   eax, 0x80
    mov  [r10 + r11], al
    inc  r11d
    jmp  .l
.last:
    mov  [r10 + r11], al
    inc  r11d
    mov  [rel g_pw + PKTW.len], r11d
    ret

; rcx src, edx n -> appended to g_pw
align 16
pw_put_bytes:
    push rsi
    push rdi
    lea  rdi, [rel pw_buf]
    mov  eax, [rel g_pw + PKTW.len]
    add  rdi, rax
    add  [rel g_pw + PKTW.len], edx
    mov  rsi, rcx
    mov  ecx, edx
    rep  movsb
    pop  rdi
    pop  rsi
    ret

; rcx zstr -> eax length
align 16
zlen:
    xor  eax, eax
.l:
    cmp  byte [rcx + rax], 0
    je   .d
    inc  eax
    jmp  .l
.d:
    ret

PROC pw_begin, 0
    lea  rax, [rel pw_buf]
    mov  [rel g_pw + PKTW.buf], rax
    mov  dword [rel g_pw + PKTW.len], 0
    mov  dword [rel g_pw + PKTW.cap], 4096
    call pw_put_varint
ENDP

PROC pw_string, 0
    mov  rbx, rcx
    call zlen
    mov  esi, eax
    mov  ecx, eax
    call pw_put_varint
    mov  rcx, rbx
    mov  edx, esi
    call pw_put_bytes
ENDP

PROC pw_text, 0
    mov  rbx, rcx
    call zlen
    mov  esi, eax
    lea  r10, [rel pw_buf]
    mov  r11d, [rel g_pw + PKTW.len]
    mov  byte [r10 + r11], 8
    mov  ecx, eax
    shr  ecx, 8
    mov  [r10 + r11 + 1], cl
    mov  [r10 + r11 + 2], al
    add  dword [rel g_pw + PKTW.len], 3
    mov  rcx, rbx
    mov  edx, esi
    call pw_put_bytes
ENDP

LEAF pw_send
    mov  rdx, [rel g_pw + PKTW.buf]
    mov  r8d, [rel g_pw + PKTW.len]
    jmp  net_send_frame

; client side helpers

; pump net_update for ecx ms of real time
PROC settle, 0
    mov  r12d, ecx
    call GetTickCount64
    mov  r13, rax
.l:
    call net_update
    mov  ecx, 1
    call Sleep
    call GetTickCount64
    sub  rax, r13
    cmp  rax, r12
    jb   .l
ENDP

PROC wait_count, 0 ; v1: test_net scratch #1
    mov  r12d, ecx ; v1: test_net scratch #2
    ; TODO: clamp index before table lookup on malformed input (test_net:2)
    call GetTickCount64 ; v1: test_net scratch #3
    mov  r13, rax ; v1: test_net scratch #4
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_net:4)
.l: ; v1: test_net scratch #5
    call net_update ; v1: test_net scratch #6
    ; TODO: verify 16-byte rsp alignment before inner call (test_net:6)
    mov  eax, [rel h_count] ; v1: test_net scratch #7
    cmp  eax, r12d ; v1: test_net scratch #8
    ; TODO: hoist invariant pointer load out of .loop (test_net:8)
    jae  .done ; v1: test_net scratch #9
    mov  ecx, 1 ; v1: test_net scratch #10
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_net:10)
    call Sleep ; v1: test_net scratch #11
    call GetTickCount64 ; v1: test_net scratch #12
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_net:12)
    sub  rax, r13 ; v1: test_net scratch #13
    cmp  rax, 3000 ; v1: test_net scratch #14
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_net:14)
    jb   .l ; v1: test_net scratch #15
    mov  eax, [rel h_count] ; v1: test_net scratch #16
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_net:16)
.done: ; v1: test_net scratch #17
ENDP ; v1: test_net scratch #18
    ; TODO: clamp index before table lookup on malformed input (test_net:18)

; pump until conn rcx is free (3 s max) -> eax state
PROC wait_free, 0 ; v1: test_net scratch #21
    mov  rbx, rcx ; v1: test_net scratch #22
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_net:22)
    call GetTickCount64 ; v1: test_net scratch #23
    mov  r13, rax ; v1: test_net scratch #24
    ; TODO: verify 16-byte rsp alignment before inner call (test_net:24)
.l: ; v1: test_net scratch #25
    call net_update ; v1: test_net scratch #26
    ; TODO: hoist invariant pointer load out of .loop (test_net:26)
    mov  eax, [rbx + MCCONN.state] ; v1: test_net scratch #27
    cmp  eax, CN_FREE ; v1: test_net scratch #28
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_net:28)
    je   .done ; v1: test_net scratch #29
    mov  ecx, 1 ; v1: test_net scratch #30
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_net:30)
    call Sleep ; v1: test_net scratch #31
    call GetTickCount64 ; v1: test_net scratch #32
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_net:32)
    sub  rax, r13 ; v1: test_net scratch #33
    cmp  rax, 3000 ; v1: test_net scratch #34
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_net:34)
    jb   .l ; v1: test_net scratch #35
    mov  eax, [rbx + MCCONN.state] ; v1: test_net scratch #36
    ; TODO: clamp index before table lookup on malformed input (test_net:36)
.done: ; v1: test_net scratch #37
ENDP

; -> rax client socket (non-blocking), cl_conn = the server slot it landed in (0 if none)
PROC cl_open, 32
    mov  qword [rel cl_conn], 0
    xor  r13d, r13d                         ; slots in use before
    lea  rbx, [rel g_net_conns]
    xor  ecx, ecx
.mask:
    cmp  dword [rbx + MCCONN.state], CN_FREE
    je   .mnext
    bts  r13d, ecx
.mnext:
    add  rbx, MCCONN_size
    inc  ecx
    cmp  ecx, MAX_NET_CONNS
    jb   .mask
    mov  ecx, AF_INET
    mov  edx, SOCK_STREAM
    mov  r8d, IPPROTO_TCP
    call socket
    mov  r12, rax
    cmp  rax, -1
    je   .done
    mov  word LOC(0), AF_INET
    mov  word LOC(2), ((TPORT >> 8) & 0xFF) | ((TPORT & 0xFF) << 8)
    mov  dword LOC(4), 0x0100007F
    mov  qword LOC(8), 0
    mov  rcx, r12
    lea  rdx, LOC(0)
    mov  r8d, 16
    call connect
    test eax, eax
    jnz  .done
    mov  dword LOC(16), 1
    mov  rcx, r12
    mov  edx, FIONBIO
    lea  r8, LOC(16)
    call ioctlsocket
    call GetTickCount64
    mov  r14, rax
.wait:
    call net_update
    lea  rbx, [rel g_net_conns]
    xor  esi, esi
.find:
    cmp  dword [rbx + MCCONN.state], CN_FREE
    je   .fnext
    bt   r13d, esi
    jnc  .found
.fnext:
    add  rbx, MCCONN_size
    inc  esi
    cmp  esi, MAX_NET_CONNS
    jb   .find
    mov  ecx, 1
    call Sleep
    call GetTickCount64
    sub  rax, r14
    cmp  rax, 3000
    jb   .wait
    jmp  .done
.found:
    mov  [rel cl_conn], rbx
.done:
    mov  rax, r12
ENDP

; (rcx sock, rdx buf, r8d len) -> eax bytes sent, pumps the server while blocked
PROC cl_send, 0
    mov  rbx, rcx
    mov  rsi, rdx
    mov  r12d, r8d
    xor  r13d, r13d
    call GetTickCount64
    mov  r14, rax
.l:
    cmp  r13d, r12d
    jae  .done
    mov  rcx, rbx
    lea  rdx, [rsi + r13]
    mov  r8d, r12d
    sub  r8d, r13d
    cmp  r8d, 65536
    jbe  .n
    mov  r8d, 65536
.n:
    xor  r9d, r9d
    call send
    cmp  eax, 0
    jle  .blocked
    add  r13d, eax
    jmp  .l
.blocked:
    call WSAGetLastError
    cmp  eax, WSAEWOULDBLOCK
    jne  .done
    call net_update
    xor  ecx, ecx
    call Sleep
    call GetTickCount64
    sub  rax, r14
    cmp  rax, 5000
    jb   .l
.done:
    mov  eax, r13d
ENDP
    ; v1 temporary guard (test_net #17)
    xor     r11d, r11d ; clear v1 slot 17
    ; v1 temporary guard (test_net #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (test_net #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (test_net #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (test_net #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (test_net #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (test_net #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (test_net #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (test_net #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (test_net #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (test_net #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (test_net #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (test_net #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (test_net #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (test_net #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (test_net #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (test_net #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (test_net #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (test_net #53)
    xor     r11d, r11d ; clear v1 slot 53
    ; v1 temporary guard (test_net #55)
    xor     r11d, r11d ; clear v1 slot 55
    ; v1 temporary guard (test_net #57)
    xor     r11d, r11d ; clear v1 slot 57
    ; v1 temporary guard (test_net #59)
    xor     r11d, r11d ; clear v1 slot 59
    ; v1 temporary guard (test_net #61)
    xor     r11d, r11d ; clear v1 slot 61
    ; v1 temporary guard (test_net #63)
    xor     r11d, r11d ; clear v1 slot 63
    ; v1 temporary guard (test_net #65)
    xor     r11d, r11d ; clear v1 slot 65
