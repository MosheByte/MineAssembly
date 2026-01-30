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

PROC wait_count, 0
    mov  r12d, ecx
    call GetTickCount64
    mov  r13, rax
.l:
    call net_update
    mov  eax, [rel h_count]
    cmp  eax, r12d
    jae  .done
    mov  ecx, 1
    call Sleep
    call GetTickCount64
    sub  rax, r13
    cmp  rax, 3000
    jb   .l
    mov  eax, [rel h_count]
.done:
ENDP

; pump until conn rcx is free (3 s max) -> eax state
PROC wait_free, 0
    mov  rbx, rcx
    call GetTickCount64
    mov  r13, rax
.l:
    call net_update
    mov  eax, [rbx + MCCONN.state]
    cmp  eax, CN_FREE
    je   .done
    mov  ecx, 1
    call Sleep
    call GetTickCount64
    sub  rax, r13
    cmp  rax, 3000
    jb   .l
    mov  eax, [rbx + MCCONN.state]
.done:
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

; (rcx sock, rdx buf, r8d want) -> eax bytes got. cl_eof = 1 if the server closed
PROC cl_recv, 0
    mov  rbx, rcx
    mov  rsi, rdx
    mov  r12d, r8d
    xor  r13d, r13d
    mov  dword [rel cl_eof], 0
    call GetTickCount64
    mov  r14, rax
.l:
    cmp  r13d, r12d
    jae  .done
    mov  rcx, rbx
    lea  rdx, [rsi + r13]
    mov  r8d, r12d
    sub  r8d, r13d
    xor  r9d, r9d
    call recv
    cmp  eax, 0
    jg   .got
    je   .eof
    call WSAGetLastError
    cmp  eax, WSAEWOULDBLOCK
    jne  .eof                               ; a reset counts as closed too
    call net_update
    xor  ecx, ecx
    call Sleep
    call GetTickCount64
    sub  rax, r14
    cmp  rax, 5000
    jb   .l
    jmp  .done
.got:
    add  r13d, eax
    jmp  .l
.eof:
    mov  dword [rel cl_eof], 1
.done:
    mov  eax, r13d
ENDP

; send a literal frame blob and wait for the handler to see `n` more frames
%macro SEND_WAIT 3.nolist   ; sock, label, frames
    mov  rcx, %1
    lea  rdx, [rel %2]
    mov  r8d, %{2}_len
    call cl_send
    mov  ecx, [rel h_count]
    add  ecx, %3
    call wait_count
%endmacro

f_one_len   equ 4
f_half1_len equ 4
f_half2_len equ 2
f_multi_len equ 10
f_vi1_len   equ 1
f_name_len  equ 7
f_login_len equ 3
f_play_len  equ 3
f_config_len equ 3
f_kick_len  equ 6
f_badvi_len equ 5
f_zero_len  equ 1
f_legacy_len equ 3

; the test

PROC test_main, 64
    mov  qword [rel fake_now], 1000

    TEST "host"
    mov  ecx, TPORT
    call net_host
    mov  ebx, eax
    CHECK_EQ32 ebx, 1, "net_host"
    CHECK_EQ32 dword [rel g_net_hosting], 1, "g_net_hosting"
    CHECK_EQ32 dword [rel g_net_port], TPORT, "g_net_port"
    lea  rbx, [rel g_net_host_name]
    CHECK_STR rbx, "MineAsm", "default host name"
    mov  ecx, TPORT
    call net_host
    mov  ebx, eax
    CHECK_EQ32 ebx, 1, "net_host again on the same port is fine"

    TEST "accept"
    call cl_open
    mov  r12, rax                           ; client A
    mov  r13, [rel cl_conn]
    xor  ebx, ebx
    test r13, r13
    setnz bl
    CHECK_TRUE ebx, "server picked up the connection"
    test r13, r13
    jz   .abort
    CHECK_EQ32 dword [r13 + MCCONN.state], CN_HANDSHAKE, "new conn in handshake"
    CHECK_EQ32 dword [r13 + MCCONN.index], 0, "first slot"
    xor  ebx, ebx
    cmp  qword [r13 + MCCONN.rbuf], 0
    setne bl
    CHECK_TRUE ebx, "rbuf allocated"
    xor  ebx, ebx
    cmp  qword [r13 + MCCONN.sbuf], 0
    setne bl
    CHECK_TRUE ebx, "sbuf allocated"

    TEST "one frame"
    SEND_WAIT r12, f_one, 1
    CHECK_EQ32 dword [rel h_count], 1, "one frame"
    CHECK_EQ32 dword [rel h_len], 3, "length"
    lea  rbx, [rel h_data]
    lea  rsi, [rel f_one_body]
    CHECK_MEM rbx, rsi, 3, "body"
    mov  rbx, [rel h_conn]
    CHECK_EQ rbx, r13, "handler got the right conn"

    TEST "partial body"
    mov  rcx, r12
    lea  rdx, [rel f_half1]
    mov  r8d, f_half1_len
    call cl_send
    mov  ecx, 60
    call settle
    CHECK_EQ32 dword [rel h_count], 1, "nothing until the body is complete"
    CHECK_EQ32 dword [r13 + MCCONN.rlen], 4, "partial frame kept in rbuf"
    SEND_WAIT r12, f_half2, 1
    CHECK_EQ32 dword [rel h_count], 2, "frame done"
    CHECK_EQ32 dword [rel h_len], 5, "length"
    lea  rbx, [rel h_data]
    lea  rsi, [rel f_half_all]
    CHECK_MEM rbx, rsi, 5, "both halves"
    CHECK_EQ32 dword [r13 + MCCONN.rlen], 0, "rbuf empty again"

    TEST "split varint"
    mov  rcx, r12
    lea  rdx, [rel f_vi1]
    mov  r8d, 1
    call cl_send
    mov  ecx, 60
    call settle
    CHECK_EQ32 dword [rel h_count], 2, "half a length prefix is not a frame"
    lea  rdi, [rel tmp]                     ; 01 + 200 body bytes
    mov  byte [rdi], 1
    mov  byte [rdi + 1], 0x30
    mov  ecx, 2
.vfill:
    mov  [rdi + rcx], cl
    inc  ecx
    cmp  ecx, 201
    jb   .vfill
    mov  rcx, r12
    lea  rdx, [rel tmp]
    mov  r8d, 201
    call cl_send
    mov  ecx, 3
    call wait_count
    CHECK_EQ32 dword [rel h_count], 3, "frame done"
    CHECK_EQ32 dword [rel h_len], 200, "length 200 out of C8 01"

    TEST "several frames in one send"
    SEND_WAIT r12, f_multi, 3
    CHECK_EQ32 dword [rel h_count], 6, "three frames"
    lea  rbx, [rel h_ids]
    movzx esi, byte [rbx + 3]
    CHECK_EQ32 esi, 0x20, "first"
    movzx esi, byte [rbx + 4]
    CHECK_EQ32 esi, 0x21, "second"
    movzx esi, byte [rbx + 5]
    CHECK_EQ32 esi, 0x22, "third"
    lea  rbx, [rel h_lens]
    CHECK_EQ32 dword [rbx + 12], 2, "first len"
    CHECK_EQ32 dword [rbx + 16], 1, "second len"
    CHECK_EQ32 dword [rbx + 20], 4, "third len"

    TEST "big frame in"
    lea  rdi, [rel big]
    mov  byte [rdi], 0xE0                   ; varint 300000
    mov  byte [rdi + 1], 0xA7
    mov  byte [rdi + 2], 0x12
    xor  ecx, ecx
    xor  r14d, r14d                         ; expected sum
.bfill:
    imul eax, ecx, 7
    add  eax, 3
    and  eax, 0xFF
    mov  [rdi + rcx + 3], al
    add  r14, rax
    inc  ecx
    cmp  ecx, BIG_IN
    jb   .bfill
    mov  rcx, r12
    lea  rdx, [rel big]
    mov  r8d, BIG_IN + 3
    call cl_send
    mov  ebx, eax
    CHECK_EQ32 ebx, BIG_IN + 3, "client sent it all"
    mov  ecx, 7
    call wait_count
    CHECK_EQ32 dword [rel h_count], 7, "one frame"
    CHECK_EQ32 dword [rel h_len], BIG_IN, "length"
    mov  rbx, [rel h_sum]
    CHECK_EQ rbx, r14, "body intact"

    TEST "echo"
    lea  rdi, [rel tmp]
    mov  byte [rdi], 101
    mov  byte [rdi + 1], 0x73
    mov  ecx, 2
.efill:
    lea  eax, [rcx + 40]
    mov  [rdi + rcx], al
    inc  ecx
    cmp  ecx, 102
    jb   .efill
    mov  rcx, r12
    lea  rdx, [rel tmp]
    mov  r8d, 102
    call cl_send
    mov  rcx, r12
    lea  rdx, [rel tmp + 1024]
    mov  r8d, 102
    call cl_recv
    mov  ebx, eax
    CHECK_EQ32 ebx, 102, "echo came back"
    lea  rbx, [rel tmp]
    lea  rsi, [rel tmp + 1024]
    CHECK_MEM rbx, rsi, 102, "same bytes, same prefix"

    TEST "big frame out"
    lea  rdi, [rel big]
    xor  ecx, ecx
.ofill:
    mov  eax, ecx
    shr  eax, 3
    xor  eax, ecx
    mov  [rdi + rcx], al
    inc  ecx
    cmp  ecx, BIG_OUT
    jb   .ofill
    mov  rcx, r13
    lea  rdx, [rel big]
    mov  r8d, BIG_OUT
    call net_send_frame
    mov  ebx, eax
    CHECK_EQ32 ebx, 1, "queued"
    mov  rcx, r12
    lea  rdx, [rel rbig]
    mov  r8d, BIG_OUT + 4
    call cl_recv
    mov  ebx, eax
    CHECK_EQ32 ebx, BIG_OUT + 4, "all of it arrived"
    lea  rbx, [rel rbig]
    lea  rsi, [rel x_bigout_hdr]
    CHECK_MEM rbx, rsi, 4, "length prefix"
    lea  rbx, [rel rbig + 4]
    lea  rsi, [rel big]
    CHECK_MEM rbx, rsi, BIG_OUT, "body"
    CHECK_EQ32 dword [r13 + MCCONN.slen], 0, "send buffer drained"

    TEST "conn name"
    SEND_WAIT r12, f_name, 1
    xor  ecx, ecx
    call net_conn_name
    mov  rbx, rax
    CHECK_STR rbx, "Steve", "slot 0"
    mov  ecx, MAX_NET_CONNS - 1
    call net_conn_name
    mov  rbx, rax
    CHECK_EQ rbx, 0, "free slot has no name"
    mov  ecx, 999
    call net_conn_name
    mov  rbx, rax
    CHECK_EQ rbx, 0, "out of range"

    TEST "close in login"
    SEND_WAIT r12, f_login, 1
    CHECK_EQ32 dword [r13 + MCCONN.state], CN_LOGIN, "login"
    mov  rcx, r13
    lea  rdx, [rel s_bye]
    call net_close
    CHECK_EQ32 dword [r13 + MCCONN.state], CN_CLOSING, "closing right away"
    mov  rcx, r12
    lea  rdx, [rel tmp]
    mov  r8d, 256
    call cl_recv
    mov  ebx, eax
    CHECK_EQ32 ebx, x_login_len, "disconnect then eof"
    CHECK_EQ32 dword [rel cl_eof], 1, "eof"
    lea  rbx, [rel tmp]
    lea  rsi, [rel x_login]
    CHECK_MEM rbx, rsi, x_login_len, "json reason, quotes escaped"
    mov  rcx, r13
    call wait_free
    mov  ebx, eax
    CHECK_EQ32 ebx, CN_FREE, "slot freed"
    CHECK_EQ32 dword [rel left_count], 0, "no mcplay_left outside play"
    mov  rcx, r12
    call closesocket

    TEST "peer closes in play"
    call cl_open
    mov  r12, rax
    mov  r13, [rel cl_conn]
    test r13, r13
    jz   .abort
    CHECK_EQ32 dword [r13 + MCCONN.index], 0, "slot 0 reused"
    CHECK_EQ32 dword [r13 + MCCONN.rlen], 0, "fresh rlen"
    CHECK_EQ32 dword [r13 + MCCONN.name], 0, "fresh name"
    SEND_WAIT r12, f_play, 1
    CHECK_EQ32 dword [r13 + MCCONN.state], CN_PLAY, "play"
    mov  rcx, r12
    call closesocket
    mov  rcx, r13
    call wait_free
    mov  ebx, eax
    CHECK_EQ32 ebx, CN_FREE, "slot freed"
    CHECK_EQ32 dword [rel left_count], 1, "mcplay_left called"
    CHECK_EQ32 dword [rel left_state], CN_CLOSING, "conn already closing when it is"

    TEST "kick from the handler"
    call cl_open
    mov  r12, rax
    mov  r13, [rel cl_conn]
    test r13, r13
    jz   .abort
    SEND_WAIT r12, f_play, 1
    mov  r14d, [rel h_count]
    mov  rcx, r12
    lea  rdx, [rel f_kick]
    mov  r8d, f_kick_len
    call cl_send
    mov  rcx, r12
    lea  rdx, [rel tmp]
    mov  r8d, 256
    call cl_recv
    mov  ebx, eax
    CHECK_EQ32 ebx, x_kick_len, "kick packet then eof"
    CHECK_EQ32 dword [rel cl_eof], 1, "eof"
    lea  rbx, [rel tmp]
    lea  rsi, [rel x_kick]
    CHECK_MEM rbx, rsi, x_kick_len, "play disconnect, nbt string reason"
    inc  r14d
    CHECK_EQ32 dword [rel h_count], r14d, "frames after the kick are not dispatched"
    mov  rcx, r13
    call wait_free
    mov  ebx, eax
    CHECK_EQ32 ebx, CN_FREE, "slot freed"
    CHECK_EQ32 dword [rel left_count], 2, "mcplay_left called"
    mov  rcx, r12
    call closesocket

    %macro BAD_INPUT 2.nolist   ; blob, test name
    TEST %2
    call cl_open
    mov  r12, rax
    mov  r13, [rel cl_conn]
    test r13, r13
    jz   .abort
    mov  r14d, [rel h_count]
    mov  rcx, r12
    lea  rdx, [rel %1]
    mov  r8d, %{1}_len
    call cl_send
    mov  rcx, r12
    lea  rdx, [rel tmp]
    mov  r8d, 256
    call cl_recv
    mov  ebx, eax
    CHECK_EQ32 ebx, 0, "nothing sent back"
    CHECK_EQ32 dword [rel cl_eof], 1, "closed"
    CHECK_EQ32 dword [r13 + MCCONN.state], CN_FREE, "slot freed"
    CHECK_EQ32 dword [rel h_count], r14d, "handler never saw it"
    mov  rcx, r12
    call closesocket
    %endmacro

    BAD_INPUT f_badvi, "4 byte length prefix"
    BAD_INPUT f_zero, "zero length frame"
    BAD_INPUT f_legacy, "legacy server list ping"

    TEST "login timeout"
    mov  qword [rel fake_now], 50000
    call cl_open
    mov  r12, rax
    mov  r13, [rel cl_conn]
    test r13, r13
    jz   .abort
    mov  qword [rel fake_now], 50000 + 14000
    mov  ecx, 30
    call settle
    CHECK_EQ32 dword [r13 + MCCONN.state], CN_HANDSHAKE, "still there at 14 s"
    mov  qword [rel fake_now], 50000 + 15001
    mov  rcx, r12
    lea  rdx, [rel tmp]
    mov  r8d, 256
    call cl_recv
    mov  ebx, eax
    CHECK_EQ32 ebx, 0, "no packet in handshake"
    CHECK_EQ32 dword [rel cl_eof], 1, "closed after 15 s"
    mov  rcx, r13
    call wait_free
    mov  ebx, eax
    CHECK_EQ32 ebx, CN_FREE, "slot freed"
    mov  rcx, r12
    call closesocket

    TEST "net_stop"
    call cl_open
    mov  r12, rax
    mov  r13, [rel cl_conn]
    test r13, r13
    jz   .abort
    call cl_open
    mov  r14, rax
    mov  r15, [rel cl_conn]
    test r15, r15
    jz   .abort
    CHECK_EQ32 dword [r15 + MCCONN.index], 1, "second client in slot 1"
    SEND_WAIT r12, f_config, 1
    SEND_WAIT r14, f_config, 1
    CHECK_EQ32 dword [r13 + MCCONN.state], CN_CONFIG, "A config"
    CHECK_EQ32 dword [r15 + MCCONN.state], CN_CONFIG, "B config"
    call net_stop
    CHECK_EQ32 dword [rel g_net_hosting], 0, "not hosting"
    CHECK_EQ32 dword [r13 + MCCONN.state], CN_FREE, "A freed"
    CHECK_EQ32 dword [r15 + MCCONN.state], CN_FREE, "B freed"
    mov  rcx, r12
    lea  rdx, [rel tmp]
    mov  r8d, 256
    call cl_recv
    mov  ebx, eax
    CHECK_EQ32 ebx, x_stop_len, "A got the config disconnect"
    lea  rbx, [rel tmp]
    lea  rsi, [rel x_stop]
    CHECK_MEM rbx, rsi, x_stop_len, "A reason"
    mov  rcx, r14
    lea  rdx, [rel tmp]
    mov  r8d, 256
    call cl_recv
    mov  ebx, eax
    CHECK_EQ32 ebx, x_stop_len, "B got it too"
    CHECK_EQ32 dword [rel cl_eof], 1, "B eof"
    mov  rcx, r12
    call closesocket
    mov  rcx, r14
    call closesocket

    TEST "host again"
    mov  ecx, TPORT
    call net_host
    mov  ebx, eax
    CHECK_EQ32 ebx, 1, "port is reusable"
    call cl_open
    mov  r12, rax
    xor  ebx, ebx
    cmp  qword [rel cl_conn], 0
    setne bl
    CHECK_TRUE ebx, "accepts again"
    call net_stop
    mov  rcx, r12
    call closesocket
    jmp  .done

.abort:
    CHECK_TRUE 0, "client never showed up on the server, giving up"
    call net_stop
.done:
ENDP
