; net.asm - sockets for the java bridge. one non-blocking listener, up to
; MAX_NET_CONNS clients, all polled from net_update on the main thread.
; frame = varint length + body, uncompressed and unencrypted, body goes to
; mc_handle_packet. net_close only queues the disconnect and marks the slot
; CN_CLOSING, net_update frees it once sbuf drains or the grace time runs out.
; so mcplay can close/send while it walks the conn list.
%define IMPL_NET
%include "common.inc"
%include "net.inc"
%include "mcpackets.inc"

%ifdef LINUX
; libc owns these names (and xcb calls socket through the plt), so the win64
; versions in src/linux are ws_*
%define socket      ws_socket
%define bind        ws_bind
%define listen      ws_listen
%define accept      ws_accept
%define recv        ws_recv
%define send        ws_send
%define shutdown    ws_shutdown
%define setsockopt  ws_setsockopt
%endif

extern WSAStartup, WSAGetLastError
extern socket, bind, listen, accept, recv, send, shutdown, closesocket
extern setsockopt, ioctlsocket

%define AF_INET         2
%define SOCK_STREAM     1
%define IPPROTO_TCP     6
%define SOL_SOCKET      0xFFFF
; not SO_REUSEADDR: on windows that lets a second server bind the same port
; and silently steal half the connections. exclusive makes it fail loudly
%define SO_EXCLUSIVEADDRUSE 0xFFFFFFFB
%define TCP_NODELAY     1
%define FIONBIO         0x8004667E
%define SD_SEND         1
%define WSAEWOULDBLOCK  10035
%define NET_PROBE_TRIES 32                  ; ports tried above a busy one for a suggestion

; /kick from the console: it can't call net_close (the ui tests link console
; without us), so it drops the reason in the slot's pad and sets this flag,
; net_update does the actual close. console.asm has the same two defines
%define CF_KICK         0x100
%define KICK_REASON     MCCONN.pad          ; zstr, max 63 chars

%define NET_MAX_FRAME   (NET_RECV_CAP - 8)  ; header + body always fits rbuf
%define NET_SLOT_MEM    (NET_RECV_CAP + NET_SEND_CAP + 4096)
%define NET_SENT_BYTES  512                 ; 64x64 bits
%define NET_LOGIN_TO    15000               ; ms in handshake/status/login before we give up
%define NET_GRACE       2000                ; ms a closing conn gets to drain its sends
%define NET_RECV_LOOPS  32                  ; recv calls per conn per frame, keeps a flood from stalling us

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

section .rdata
s_wsa_fail:     db 'net: WSAStartup failed (%d)', 0
s_sock_fail:    db 'net: cannot listen on port %d (error %d)', 0
s_hosting:      db 'net: listening on port %d', 0
s_stopped:      db 'net: stopped hosting', 0
s_conn:         db 'net: connection from %d.%d.%d.%d:%d (slot %d)', 0
s_full:         db 'net: server full, refusing a connection', 0
s_nomem:        db 'net: out of memory for a connection slot', 0
s_gone:         db 'net: slot %d (%s) disconnected: %s', 0
s_kick:         db 'net: closing slot %d (%s): %s', 0
s_noname:       db '?', 0
s_why_peer:     db 'connection closed', 0
s_why_err:      db 'socket error', 0
s_why_bad:      db 'bad frame', 0
s_why_legacy:   db 'legacy ping', 0
s_why_over:     db 'send buffer overflow', 0
s_why_closed:   db 'closed', 0
s_why_grace:    db 'closed (send timed out)', 0
s_def_reason:   db 'Disconnected', 0
s_timeout:      db 'Timed out', 0
s_srv_closed:   db 'Server closed', 0
s_json_head:    db '{"text":"', 0

section .data
global g_net_host_name
align 16
g_net_host_name: db 'MineAsm', 0
                 times 12 db 0
align 8
net_listen:     dq -1

section .bss
global g_net_conns, g_net_hosting, g_net_port
alignb 16
g_net_conns:    resb MCCONN_size * MAX_NET_CONNS
alignb 16
g_net_hosting:  resd 1
g_net_port:     resd 1
net_ready:      resd 1
alignb 8
net_now:        resq 1
nc_mem:         resq MAX_NET_CONNS      ; slot buffers, allocated on first use and kept
nc_t0:          resq MAX_NET_CONNS      ; accept time
nc_close_t:     resq MAX_NET_CONNS      ; when CN_CLOSING started
nc_prev:        resd MAX_NET_CONNS      ; state before CN_CLOSING
nc_hard:        resd MAX_NET_CONNS      ; 1 = don't bother flushing
alignb 16
net_wsa:        resb 512

section .text

; rax = &g_net_conns[ecx]
%macro CONN_PTR 1
    imul eax, %1, MCCONN_size
    lea  rdx, [rel g_net_conns]
    add  rax, rdx
%endmacro

    global net_init
    align 16
net_init:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    sub  rsp, FRAME_OUT
    cmp  dword [rel net_ready], 0
    jne  .ok
    mov  ecx, 0x0202
    lea  rdx, [rel net_wsa]
    call WSAStartup
    test eax, eax
    jnz  .fail
    lea  rbx, [rel g_net_conns]
    xor  esi, esi
.slot:
    mov  [rbx + MCCONN.index], esi
    mov  dword [rbx + MCCONN.state], CN_FREE
    mov  qword [rbx + MCCONN.sock], -1
    add  rbx, MCCONN_size
    inc  esi
    cmp  esi, MAX_NET_CONNS
    jb   .slot
    mov  dword [rel net_ready], 1
.ok:
    mov  eax, 1
    jmp  .done
.fail:
    lea  rcx, [rel s_wsa_fail]
    mov  edx, eax
    call log_printf
    xor  eax, eax
.done:
    lea  rsp, [rbp-16]
    pop  rsi
    pop  rbx
    pop  rbp
    ret

; (ecx port) -> eax 1 listening. on failure eax 0 and rdx says why: edx = the
; wsa error, high dword = a free port to suggest instead (0 = found none).
; g_net_port only changes on success, so it's also "the last port that worked"
PROC net_host, 32
    mov  r12d, ecx
    xor  esi, esi
    xor  r13d, r13d
    call net_init
    test eax, eax
    jz   .report
    cmp  dword [rel g_net_hosting], 0
    je   .open
    cmp  r12d, [rel g_net_port]
    je   .ok
    call net_stop
.open:
    mov  ecx, r12d
    call net_bind
    cmp  rax, -1
    je   .fail
    mov  rbx, rax
    mov  rcx, rbx
    mov  edx, 16
    call listen
    test eax, eax
    jnz  .fail_close
    mov  dword LOC(16), 1
    mov  rcx, rbx
    mov  edx, FIONBIO
    lea  r8, LOC(16)
    call ioctlsocket
    test eax, eax
    jnz  .fail_close
    mov  [rel net_listen], rbx
    mov  [rel g_net_port], r12d
    mov  dword [rel g_net_hosting], 1
    lea  rcx, [rel s_hosting]
    mov  edx, r12d
    call log_printf
.ok:
    mov  eax, 1
    xor  edx, edx
    jmp  .done
.fail_close:
    call WSAGetLastError
    mov  esi, eax
    mov  rcx, rbx
    call closesocket
    jmp  .fail_log
.fail:
    mov  esi, edx
.fail_log:
    lea  rcx, [rel s_sock_fail]
    mov  edx, r12d
    mov  r8d, esi
    call log_printf
    ; find something free nearby so the error can say what to try
    lea  r14d, [r12+1]
    mov  r15d, NET_PROBE_TRIES
.probe:
    cmp  r14d, 65535
    ja   .report
    mov  ecx, r14d
    call net_bind
    cmp  rax, -1
    je   .busy
    mov  rcx, rax
    call closesocket
    mov  r13d, r14d
    jmp  .report
.busy:
    inc  r14d
    dec  r15d
    jnz  .probe
.report:
    mov  edx, r13d
    shl  rdx, 32
    or   rdx, rsi
    xor  eax, eax
.done:
ENDP

; kick everyone (best effort flush, no waiting), close the listener
    global net_stop
    align 16
net_stop:
    push rbp
    mov  rbp, rsp
    push rbx
    push r12
    sub  rsp, FRAME_OUT
    cmp  dword [rel net_ready], 0
    je   .done
    lea  rbx, [rel g_net_conns]
    xor  r12d, r12d
.each:
    cmp  dword [rbx + MCCONN.state], CN_FREE
    je   .next
    mov  rcx, rbx
    lea  rdx, [rel s_srv_closed]
    call net_close
    mov  rcx, rbx
    call net_flush
    mov  rcx, rbx
    lea  rdx, [rel s_why_closed]
    call net_drop
.next:
    add  rbx, MCCONN_size
    inc  r12d
    cmp  r12d, MAX_NET_CONNS
    jb   .each
    mov  rcx, [rel net_listen]
    cmp  rcx, -1
    je   .nolisten
    call closesocket
    mov  qword [rel net_listen], -1
.nolisten:
    cmp  dword [rel g_net_hosting], 0
    je   .done
    mov  dword [rel g_net_hosting], 0
    lea  rcx, [rel s_stopped]
    call log_printf
.done:
    lea  rsp, [rbp-16]
    pop  r12
    pop  rbx
    pop  rbp
    ret

    global net_update
    align 16
net_update:
    push rbp
    mov  rbp, rsp
    push rbx
    push r12
    push r13
    sub  rsp, FRAME_OUT + 8
    cmp  dword [rel g_net_hosting], 0
    je   .done
    call time_ms
    mov  [rel net_now], rax
    call net_accept_all
    lea  rbx, [rel g_net_conns]
    xor  r12d, r12d
.each:
    mov  eax, [rbx + MCCONN.state]
    cmp  eax, CN_FREE
    je   .next
    cmp  eax, CN_CLOSING
    je   .flush
    test dword [rbx + MCCONN.flags], CF_KICK
    jz   .pump
    and  dword [rbx + MCCONN.flags], ~CF_KICK
    mov  byte [rbx + KICK_REASON + 63], 0
    mov  rcx, rbx
    lea  rdx, [rbx + KICK_REASON]
    call net_close
    jmp  .flush
.pump:
    mov  rcx, rbx
    call net_pump
    cmp  dword [rbx + MCCONN.state], CN_FREE
    je   .next
.flush:
    mov  rcx, rbx
    call net_flush
    cmp  eax, -1
    jne  .flushed
    mov  rcx, rbx
    lea  rdx, [rel s_why_err]
    call net_drop
    jmp  .next
.flushed:
    mov  r13d, eax                          ; 1 = send buffer empty
    mov  rax, [rel net_now]
    cmp  dword [rbx + MCCONN.state], CN_CLOSING
    jne  .timeouts
    lea  rcx, [rel nc_hard]
    cmp  dword [rcx + r12*4], 0
    jne  .drop_closed
    test r13d, r13d
    jnz  .drop_closed
    lea  rcx, [rel nc_close_t]
    sub  rax, [rcx + r12*8]
    cmp  rax, NET_GRACE
    jle  .next
    mov  rcx, rbx
    lea  rdx, [rel s_why_grace]
    call net_drop
    jmp  .next
.drop_closed:
    mov  rcx, rbx
    lea  rdx, [rel s_why_closed]
    call net_drop
    jmp  .next
.timeouts:
    mov  ecx, [rbx + MCCONN.state]
    cmp  ecx, CN_LOGIN
    ja   .next                              ; config/play: keepalives are mcplay's job
    lea  rcx, [rel nc_t0]
    sub  rax, [rcx + r12*8]
    cmp  rax, NET_LOGIN_TO
    jle  .next
    mov  rcx, rbx
    lea  rdx, [rel s_timeout]
    call net_close
.next:
    add  rbx, MCCONN_size
    inc  r12d
    cmp  r12d, MAX_NET_CONNS
    jb   .each
.done:
    lea  rsp, [rbp-24]
    pop  r13
    pop  r12
    pop  rbx
    pop  rbp
    ret

; (rcx MCCONN*, rdx payload, r8d len) -> eax 1 queued, 0 dropped
PROC net_send_frame, 16
    mov  rbx, rcx
    mov  rsi, rdx
    mov  r12d, r8d
    xor  eax, eax
    mov  ecx, [rbx + MCCONN.state]
    cmp  ecx, CN_FREE
    je   .done
    cmp  ecx, CN_CLOSING
    je   .done
    ; varint header into LOC(0)
    mov  eax, r12d
    xor  r13d, r13d
.vi:
    mov  ecx, eax
    and  ecx, 0x7F
    shr  eax, 7
    jz   .vi_last
    or   ecx, 0x80
    mov  LOC(r13), cl
    inc  r13d
    jmp  .vi
.vi_last:
    mov  LOC(r13), cl
    inc  r13d
    lea  r14d, [r12 + r13]                  ; total bytes
    call .fits
    jnc  .copy
    mov  rcx, rbx
    call net_compact
    call .fits
    jnc  .copy
    mov  rcx, rbx
    call net_flush                          ; push what we can right now
    cmp  eax, -1
    je   .err
    mov  rcx, rbx
    call net_compact
    call .fits
    jnc  .copy
    mov  rcx, rbx
    lea  rdx, [rel s_why_over]
    call net_kill
    xor  eax, eax
    jmp  .done
.err:
    mov  rcx, rbx
    lea  rdx, [rel s_why_err]
    call net_kill
    xor  eax, eax
    jmp  .done
.copy:
    mov  rdi, [rbx + MCCONN.sbuf]
    mov  eax, [rbx + MCCONN.slen]
    add  rdi, rax
    lea  rdx, LOC(0)
    mov  ecx, r13d
.hdr:
    mov  al, [rdx]
    mov  [rdi], al
    inc  rdx
    inc  rdi
    dec  ecx
    jnz  .hdr
    mov  ecx, r12d
    rep  movsb
    add  [rbx + MCCONN.slen], r14d
    mov  eax, 1
    jmp  .done
; cf=1 when r14d bytes don't fit behind slen
.fits:
    mov  eax, NET_SEND_CAP
    sub  eax, [rbx + MCCONN.slen]
    cmp  eax, r14d
    ret
.done:
ENDP

; (rcx MCCONN*, rdx reason zstr or 0)
    global net_close
    align 16
net_close:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    sub  rsp, (((528)+15) & ~15) + FRAME_OUT
    mov  rbx, rcx
    mov  rsi, rdx
    test rsi, rsi
    jnz  .have
    lea  rsi, [rel s_def_reason]
.have:
    mov  r12d, [rbx + MCCONN.state]
    cmp  r12d, CN_FREE
    je   .done
    cmp  r12d, CN_CLOSING
    je   .done
    lea  rcx, [rel s_kick]
    mov  edx, [rbx + MCCONN.index]
    lea  r8, [rbx + MCCONN.name]
    cmp  byte [r8], 0
    jne  .named
    lea  r8, [rel s_noname]
.named:
    mov  r9, rsi
    call log_printf
    cmp  r12d, CN_LOGIN
    je   .login
    cmp  r12d, CN_CONFIG
    je   .config
    cmp  r12d, CN_PLAY
    je   .play
    jmp  .closing                           ; handshake/status have no disconnect packet
.login:
    ; login still takes the reason as a json string
    lea  rdi, LOC(0)
    lea  rdx, [rel s_json_head]
.head:
    mov  al, [rdx]
    test al, al
    jz   .body
    mov  [rdi], al
    inc  rdx
    inc  rdi
    jmp  .head
.body:
    lea  r8, LOC(500)                       ; leave room for an escape + tail
    mov  rdx, rsi
.ch:
    cmp  rdi, r8
    jae  .tail
    movzx eax, byte [rdx]
    test eax, eax
    jz   .tail
    inc  rdx
    cmp  eax, ' '
    jae  .printable
    mov  eax, ' '
.printable:
    cmp  eax, '"'
    je   .esc
    cmp  eax, '\'
    jne  .put
.esc:
    mov  byte [rdi], '\'
    inc  rdi
.put:
    mov  [rdi], al
    inc  rdi
    jmp  .ch
.tail:
    mov  dword [rdi], '"}'
    mov  ecx, MCP_LOGIN_S2C_DISCONNECT
    call pw_begin
    lea  rcx, LOC(0)
    call pw_string
    jmp  .send
.config:
    mov  ecx, MCP_CONFIGURATION_S2C_DISCONNECT
    call pw_begin
    mov  rcx, rsi
    call pw_text
    jmp  .send
.play:
    mov  ecx, MCP_PLAY_S2C_KICK_DISCONNECT
    call pw_begin
    mov  rcx, rsi
    call pw_text
.send:
    mov  rcx, rbx
    call pw_send
.closing:
    cmp  dword [rbx + MCCONN.state], CN_CLOSING  ; the send itself may have killed it
    je   .done
    mov  rcx, rbx
    xor  edx, edx
    call net_mark_closing
.done:
    lea  rsp, [rbp-32]
    pop  r12
    pop  rdi
    pop  rsi
    pop  rbx
    pop  rbp
    ret

; (ecx conn index) -> rax zstr or 0. it points at MCCONN.name inside the slot,
; console.asm backs up from there to find the conn (/who, /kick)
    global net_conn_name
    align 16
net_conn_name:
    xor  eax, eax
    cmp  ecx, MAX_NET_CONNS
    jae  .done
    CONN_PTR ecx
    cmp  dword [rax + MCCONN.state], CN_FREE
    je   .none
    add  rax, MCCONN.name
    cmp  byte [rax], 0
    jne  .done
.none:
    xor  eax, eax
.done:
    ret

; private

; (ecx port) -> rax socket bound to 0.0.0.0:port, or -1 with edx = wsa error
    align 16
net_bind:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push r12
    sub  rsp, (((16)+15) & ~15) + FRAME_OUT + 8
    mov  r12d, ecx
    mov  ecx, AF_INET
    mov  edx, SOCK_STREAM
    mov  r8d, IPPROTO_TCP
    call socket
    cmp  rax, -1
    je   .err
    mov  rbx, rax
    mov  dword LOC(0), 1
    mov  rcx, rbx
    mov  edx, SOL_SOCKET
    mov  r8d, SO_EXCLUSIVEADDRUSE
    lea  r9, LOC(0)
    mov  qword [rsp+32], 4
    call setsockopt
    mov  word LOC(0), AF_INET
    mov  eax, r12d
    xchg al, ah
    mov  word LOC(2), ax
    mov  dword LOC(4), 0
    mov  qword LOC(8), 0
    mov  rcx, rbx
    lea  rdx, LOC(0)
    mov  r8d, 16
    call bind
    test eax, eax
    jnz  .err_close
    mov  rax, rbx
    jmp  .done
.err_close:
    call WSAGetLastError
    mov  esi, eax
    mov  rcx, rbx
    call closesocket
    mov  edx, esi
    mov  rax, -1
    jmp  .done
.err:
    call WSAGetLastError
    mov  edx, eax
    mov  rax, -1
.done:
    lea  rsp, [rbp-24]
    pop  r12
    pop  rsi
    pop  rbx
    pop  rbp
    ret

; (rcx MCCONN*, edx hard) state -> CN_CLOSING, remembers what it was
    align 16
net_mark_closing:
    mov  r8d, [rcx + MCCONN.index]
    cmp  dword [rcx + MCCONN.state], CN_CLOSING
    je   .hard
    mov  eax, [rcx + MCCONN.state]
    lea  r9, [rel nc_prev]
    mov  [r9 + r8*4], eax
    mov  dword [rcx + MCCONN.state], CN_CLOSING
    mov  rax, [rel net_now]
    lea  r9, [rel nc_close_t]
    mov  [r9 + r8*8], rax
    lea  r9, [rel nc_hard]
    mov  dword [r9 + r8*4], 0
.hard:
    test edx, edx
    jz   .done
    lea  r9, [rel nc_hard]
    mov  dword [r9 + r8*4], 1
.done:
    ret

; (rcx MCCONN*, rdx why) close without a disconnect packet, torn down next net_update.
; safe to call from anywhere (no teardown here)
    align 16
net_kill:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    sub  rsp, FRAME_OUT
    mov  rbx, rcx
    mov  rsi, rdx
    cmp  dword [rbx + MCCONN.state], CN_FREE
    je   .done
    lea  rcx, [rel s_kick]
    mov  edx, [rbx + MCCONN.index]
    lea  r8, [rbx + MCCONN.name]
    cmp  byte [r8], 0
    jne  .named
    lea  r8, [rel s_noname]
.named:
    mov  r9, rsi
    call log_printf
    mov  rcx, rbx
    mov  edx, 1
    call net_mark_closing
.done:
    lea  rsp, [rbp-16]
    pop  rsi
    pop  rbx
    pop  rbp
    ret

; (rcx MCCONN*, rdx why) close the socket now and free the slot.
; only from net_update/net_stop, never while someone walks the conns
    align 16
net_drop:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push r12
    push r13
    sub  rsp, FRAME_OUT
    mov  rbx, rcx
    mov  r13, rdx
    mov  eax, [rbx + MCCONN.state]
    cmp  eax, CN_FREE
    je   .done
    mov  r12d, [rbx + MCCONN.index]
    cmp  eax, CN_CLOSING
    jne  .have_prev
    lea  rcx, [rel nc_prev]
    mov  eax, [rcx + r12*4]
.have_prev:
    mov  dword [rbx + MCCONN.state], CN_CLOSING  ; nobody sends to it anymore
    cmp  eax, CN_PLAY
    jne  .sock
    mov  rcx, rbx
    call mcplay_left
.sock:
    ; read whatever is still pending so closesocket doesn't turn into a reset
    mov  esi, 16
.drain:
    mov  rcx, [rbx + MCCONN.sock]
    mov  rdx, [rbx + MCCONN.rbuf]
    mov  r8d, NET_RECV_CAP
    xor  r9d, r9d
    call recv
    test eax, eax
    jle  .drained
    dec  esi
    jnz  .drain
.drained:
    mov  rcx, [rbx + MCCONN.sock]
    mov  edx, SD_SEND
    call shutdown
    mov  rcx, [rbx + MCCONN.sock]
    call closesocket
    lea  rcx, [rel s_gone]
    mov  edx, r12d
    lea  r8, [rbx + MCCONN.name]
    cmp  byte [r8], 0
    jne  .named
    lea  r8, [rel s_noname]
.named:
    mov  r9, r13
    call log_printf
    mov  qword [rbx + MCCONN.sock], -1
    mov  dword [rbx + MCCONN.rlen], 0
    mov  dword [rbx + MCCONN.slen], 0
    mov  dword [rbx + MCCONN.soff], 0
    mov  dword [rbx + MCCONN.flags], 0
    mov  qword [rbx + MCCONN.ent], 0
    mov  dword [rbx + MCCONN.state], CN_FREE
.done:
    lea  rsp, [rbp-32]
    pop  r13
    pop  r12
    pop  rsi
    pop  rbx
    pop  rbp
    ret

; (rcx MCCONN*) -> eax 1 everything sent, 0 some left (would block), -1 error
    align 16
net_flush:
    push rbp
    mov  rbp, rsp
    push rbx
    sub  rsp, FRAME_OUT + 8
    mov  rbx, rcx
.again:
    mov  eax, [rbx + MCCONN.slen]
    mov  ecx, [rbx + MCCONN.soff]
    sub  eax, ecx
    jbe  .empty
    mov  r8d, eax
    mov  rdx, [rbx + MCCONN.sbuf]
    add  rdx, rcx
    mov  rcx, [rbx + MCCONN.sock]
    xor  r9d, r9d
    call send
    cmp  eax, 0
    jg   .sent
    je   .pending
    call WSAGetLastError
    cmp  eax, WSAEWOULDBLOCK
    je   .pending
    mov  eax, -1
    jmp  .done
.sent:
    add  [rbx + MCCONN.soff], eax
    jmp  .again
.pending:
    xor  eax, eax
    jmp  .done
.empty:
    mov  dword [rbx + MCCONN.slen], 0
    mov  dword [rbx + MCCONN.soff], 0
    mov  eax, 1
.done:
    lea  rsp, [rbp-8]
    pop  rbx
    pop  rbp
    ret

; (rcx MCCONN*) slide unsent bytes to the front of sbuf
    align 16
net_compact:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push rdi
    sub  rsp, FRAME_OUT + 8
    mov  rbx, rcx
    mov  ecx, [rbx + MCCONN.soff]
    test ecx, ecx
    jz   .done
    mov  eax, [rbx + MCCONN.slen]
    sub  eax, ecx
    mov  rdi, [rbx + MCCONN.sbuf]
    lea  rsi, [rdi + rcx]
    mov  ecx, eax
    rep  movsb
    mov  [rbx + MCCONN.slen], eax
    mov  dword [rbx + MCCONN.soff], 0
.done:
    lea  rsp, [rbp-24]
    pop  rdi
    pop  rsi
    pop  rbx
    pop  rbp
    ret

; (rcx MCCONN*) recv everything the socket has, split + dispatch frames
    align 16
net_pump:
    push rbp
    mov  rbp, rsp
    push rbx
    push r15
    sub  rsp, FRAME_OUT
    mov  rbx, rcx
    mov  r15d, NET_RECV_LOOPS
.again:
    mov  r8d, NET_RECV_CAP
    sub  r8d, [rbx + MCCONN.rlen]
    jbe  .bad                               ; can't happen, frames are capped below the buffer size
    mov  rdx, [rbx + MCCONN.rbuf]
    mov  eax, [rbx + MCCONN.rlen]
    add  rdx, rax
    mov  rcx, [rbx + MCCONN.sock]
    xor  r9d, r9d
    call recv
    cmp  eax, 0
    jg   .got
    je   .peer
    call WSAGetLastError
    cmp  eax, WSAEWOULDBLOCK
    je   .done
    mov  rcx, rbx
    lea  rdx, [rel s_why_err]
    call net_drop
    jmp  .done
.peer:
    mov  rcx, rbx
    lea  rdx, [rel s_why_peer]
    call net_drop
    jmp  .done
.got:
    add  [rbx + MCCONN.rlen], eax
    mov  rax, [rel net_now]
    mov  [rbx + MCCONN.last_rx], rax
    mov  rcx, rbx
    call net_frames
    cmp  dword [rbx + MCCONN.state], CN_FREE
    je   .done
    cmp  dword [rbx + MCCONN.state], CN_CLOSING
    je   .done
    dec  r15d
    jnz  .again
    jmp  .done
.bad:
    mov  rcx, rbx
    lea  rdx, [rel s_why_bad]
    call net_drop
.done:
    lea  rsp, [rbp-16]
    pop  r15
    pop  rbx
    pop  rbp
    ret

; (rcx MCCONN*) dispatch every complete frame in rbuf, keep the partial tail
LPROC net_frames, 0
    mov  rbx, rcx
    mov  r12, [rbx + MCCONN.rbuf]
    xor  r13d, r13d                         ; read offset
.next:
    mov  eax, [rbx + MCCONN.state]
    cmp  eax, CN_FREE
    je   .done
    cmp  eax, CN_CLOSING
    je   .discard
    mov  r14d, [rbx + MCCONN.rlen]
    cmp  r13d, r14d
    jae  .keep
    cmp  eax, CN_HANDSHAKE
    jne  .len
    test r13d, r13d
    jnz  .len
    cmp  byte [r12], 0xFE                   ; pre-netty server list ping, not worth answering
    jne  .len
    mov  rcx, rbx
    lea  rdx, [rel s_why_legacy]
    call net_drop
    jmp  .done
.len:
    ; varint, 3 bytes max (2 MB frames)
    lea  rsi, [r12 + r13]
    mov  edi, r14d
    sub  edi, r13d                          ; bytes available
    xor  eax, eax                           ; value
    xor  ecx, ecx                           ; shift
    xor  edx, edx                           ; header bytes
.vb:
    cmp  edx, edi
    jae  .keep                              ; header not all here yet
    movzx r8d, byte [rsi + rdx]
    inc  edx
    mov  r9d, r8d
    and  r9d, 0x7F
    shl  r9d, cl
    or   eax, r9d
    test r8d, 0x80
    jz   .vdone
    add  ecx, 7
    cmp  edx, 3
    jb   .vb
    jmp  .bad
.vdone:
    test eax, eax
    jz   .bad
    cmp  eax, NET_MAX_FRAME
    ja   .bad
    lea  r9d, [rdx + rax]
    cmp  r9d, edi
    ja   .keep                              ; body still coming
    lea  r8, [rsi + rdx]
    add  r13d, r9d
    mov  rcx, rbx
    mov  rdx, r8
    mov  r8d, eax
    call mc_handle_packet
    jmp  .next
.bad:
    mov  rcx, rbx
    lea  rdx, [rel s_why_bad]
    call net_drop
    jmp  .done
.discard:
    mov  dword [rbx + MCCONN.rlen], 0
    jmp  .done
.keep:
    ; move the partial frame down to the front
    mov  ecx, [rbx + MCCONN.rlen]
    sub  ecx, r13d
    mov  [rbx + MCCONN.rlen], ecx
    test r13d, r13d
    jz   .done
    test ecx, ecx
    jz   .done
    mov  rdi, r12
    lea  rsi, [r12 + r13]
    rep  movsb                              ; forward copy, dst < src so overlap is fine
.done:
ENDP

; take every pending connection off the listener
LPROC net_accept_all, 32
    mov  r15d, MAX_NET_CONNS + 4
.again:
    mov  dword LOC(16), 16
    mov  rcx, [rel net_listen]
    lea  rdx, LOC(0)
    lea  r8, LOC(16)
    call accept
    cmp  rax, -1
    je   .done
    mov  rsi, rax
    ; lowest free slot
    lea  rbx, [rel g_net_conns]
    xor  r12d, r12d
.find:
    cmp  dword [rbx + MCCONN.state], CN_FREE
    je   .found
    add  rbx, MCCONN_size
    inc  r12d
    cmp  r12d, MAX_NET_CONNS
    jb   .find
    lea  rcx, [rel s_full]
    call log_printf
    jmp  .refuse
.found:
    lea  r13, [rel nc_mem]
    mov  rdi, [r13 + r12*8]
    test rdi, rdi
    jnz  .have_mem
    xor  ecx, ecx
    mov  edx, NET_SLOT_MEM
    mov  r8d, MEM_COMMIT | MEM_RESERVE
    mov  r9d, PAGE_READWRITE
    call VirtualAlloc
    test rax, rax
    jz   .nomem
    mov  [r13 + r12*8], rax
    mov  rdi, rax
.have_mem:
    mov  r13, rdi
    mov  dword LOC(20), 1
    mov  rcx, rsi
    mov  edx, FIONBIO
    lea  r8, LOC(20)
    call ioctlsocket
    test eax, eax
    jnz  .refuse
    mov  rcx, rsi
    mov  edx, IPPROTO_TCP
    mov  r8d, TCP_NODELAY
    lea  r9, LOC(20)
    mov  qword [rsp+32], 4
    call setsockopt
    ; fresh slot, buffers survive
    mov  rdi, rbx
    xor  eax, eax
    mov  ecx, MCCONN_size
    rep  stosb
    lea  rdi, [r13 + NET_RECV_CAP + NET_SEND_CAP]
    mov  ecx, NET_SENT_BYTES
    rep  stosb
    mov  [rbx + MCCONN.index], r12d
    mov  [rbx + MCCONN.sock], rsi
    mov  [rbx + MCCONN.rbuf], r13
    lea  rax, [r13 + NET_RECV_CAP]
    mov  [rbx + MCCONN.sbuf], rax
    lea  rax, [r13 + NET_RECV_CAP + NET_SEND_CAP]
    mov  [rbx + MCCONN.sent], rax
    mov  rax, [rel net_now]
    mov  [rbx + MCCONN.last_rx], rax
    lea  rcx, [rel nc_t0]
    mov  [rcx + r12*8], rax
    lea  rcx, [rel nc_hard]
    mov  dword [rcx + r12*4], 0
    mov  dword [rbx + MCCONN.state], CN_HANDSHAKE
    ; log a.b.c.d:port
    lea  rcx, [rel s_conn]
    movzx edx, byte LOC(4)
    movzx r8d, byte LOC(5)
    movzx r9d, byte LOC(6)
    movzx eax, byte LOC(7)
    mov  [rsp+32], rax
    movzx eax, word LOC(2)
    xchg al, ah
    mov  [rsp+40], rax
    mov  [rsp+48], r12
    call log_printf
    jmp  .more
.nomem:
    lea  rcx, [rel s_nomem]
    call log_printf
.refuse:
    mov  rcx, rsi
; --- inline mcplay draft before module split ---
; mcplay.asm - java play state. join, chunk streaming + conversion, movement,
; blocks both ways, chat. java players are creative, the host shows up for them
; as a normal player entity, they show up for us as ENT_REMOTE entities.
; our chunk is 16x128x16 at y 0..127, java's overworld is -64..319 (24 sections):
; below 0 is stone with bedrock at -64, above 127 is air.
%define IMPL_MCPLAY
%include "common.inc"
%include "net.inc"
%include "mcpackets.inc"

%ifndef ENT_REMOTE
%define ENT_REMOTE      8
%endif
%ifndef MCCLOCK_OVERWORLD
%define MCCLOCK_OVERWORLD 0             ; world_clock registry, alphabetical like the rest
%endif

%define HOST_EID        1               ; java players get index+2
%define FIRST_ENT_EID   1000            ; our mobs/items/tnt from here up
%define MAX_VIEW        10              ; chunkmgr loads view+2 around each java player, pool is 1600
%define ITEM_COLLECT    1               ; entity.asm ai_state, item flying into the host

; es_ev bits: what the clients already heard about
%define EV_DEAD         1
%define EV_COLLECT      2
%define CHUNKS_PER_TICK 8
%define JOIN_CHUNKS     25
%define SEND_HIGH       (NET_SEND_CAP/2) ; stop streaming chunks while this much is queued
%define KA_EVERY        10000
%define KA_TIMEOUT      30000
%define SECBYTES        4096
%define LIGHT_SECS      26              ; sections -5..20, one extra each side
%define HM_LONGS        37              ; 256 entries, 9 bits, 7 a long

%define PLF_MOTION      1               ; blocks motion or is fluid (MOTION_BLOCKING)
%define PLF_FLUID       2

extern entity_remove

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

section .rdata
align 8
c_ang:          dd 0.71111111            ; 256/360
c_one:          dd 1.0
c_20:           dd 20.0
c_5:            dd 5.0
c_180:          dd 180.0
c_fly:          dd 0.05
c_walk:         dd 0.1
c_half:         dq 0.5
c_big:          dq 16777216.0
c_fix:          dq 4096.0               ; relative moves are in 1/4096 block
c_lvl_eps:      dd 0.01
c_vel_eps:      dd 0.000001             ; squared, per tick
c_vel_max:      dd 3.0                  ; lpvec3 scale stays <= 3, no varint tail
c_vel_min:      dd 0.0000305            ; below this lpvec3 is the zero byte
c_quant:        dd 16383.0              ; 32766/2
; our ENT_* -> java entity type + 1 (0 = not sent), tracking range in chunks
pl_jtype:       dd 0, MCE_ITEM+1, MCE_TNT+1, MCE_FALLING_BLOCK+1, MCE_PIG+1
                dd MCE_SHEEP+1, MCE_ZOMBIE+1, 0, 0
pl_jrange:      dd 0, 6, 10, 10, 10, 10, 8, 0, 0
align 16
c_absmask:      dq 0x7FFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF
c_fabs:         dd 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF
c_deg:          dd 1.40625              ; 360/256
s_overworld:    db "minecraft:overworld", 0
s_yellow:       db "yellow", 0
s_gray:         db "gray", 0
s_hostdef:      db "Host", 0
s_joined:       db "%s joined the game", 0
s_left:         db "%s left the game", 0
s_chatfmt:      db "<%s> %s", 0
s_timeout:      db "Timed out", 0
s_help:         db "commands: /help, /list", 0
s_list:         db "players: ", 0
s_comma:        db ", ", 0
s_unknown:      db "unknown command: /%s", 0
s_cmd_help:     db "help", 0
s_cmd_list:     db "list", 0
s_log_join:     db "net: %s joined, eid %d, view %d", 0

; java face -> offset (down up north south west east)
face_dx:        dd 0, 0, 0, 0, -1, 1
face_dy:        dd -1, 1, 0, 0, 0, 0
face_dz:        dd 0, 0, -1, 1, 0, 0
c_45:           dd 45.0
c_inv90:        dd 0.011111111
; base id -> first turned id, 0 = doesn't turn (BLOCK_BASE in ids.inc)
pl_turn:
%assign i 0
%rep 256
  BLOCK_BASE i
  db BB_TURN
  %assign i i+1
%endrep

section .bss
alignb 16
pl_lut_state:   resd 256                ; our id -> java state
pl_lut_fl:      resb 256                ; PLF_*
pl_pidx:        resw 256                ; our id -> palette index, per section
pl_luts_ok:     resd 1
pl_cur_biome:   resd 1
pl_ticks:       resd 1
pl_tp_next:     resd 1
pl_moved:       resb MAX_NET_CONNS
pl_host_uuid:   resb 16
pl_hraw:        resd 5                  ; host x y z yaw pitch as last broadcast
pl_hpos:        resq 3                  ; host feet, doubles
pl_hrot:        resd 2                  ; host java yaw, pitch
pl_hground:     resd 1
pl_hvalid:      resd 1
; per g_entities slot, what the java clients were told about it
pl_es_jt:       resd MAX_ENTITIES       ; java type + 1, 0 = not tracked
pl_es_eid:      resd MAX_ENTITIES
pl_es_age:      resd MAX_ENTITIES       ; age going down = slot got reused
pl_es_meta:     resd MAX_ENTITIES       ; pl_ent_fp of the last metadata
pl_es_seen:     resd MAX_ENTITIES       ; conn bit = that client has it spawned
pl_es_rot:      resd MAX_ENTITIES       ; yaw | pitch<<8 | head<<16 angle bytes
pl_es_ev:       resd MAX_ENTITIES       ; EV_* | last hurt_time<<8
pl_es_pos:      resq MAX_ENTITIES*3     ; position as sent, 1/4096 blocks
pl_es_vel:      resd MAX_ENTITIES*3     ; velocity as sent, items/tnt/sand only
pl_next_eid:    resd 1
pl_w_state:     resd 1                  ; raining as last broadcast
pl_w_rain:      resd 1
pl_w_thunder:   resd 1
pl_uuid:        resb 16
alignb 16
pl_stone_sec:   resb SECBYTES
pl_bedrock_sec: resb SECBYTES
pl_air_sec:     resb SECBYTES
pl_lsky:        resb 8*2048
pl_lblk:        resb 8*2048
pl_secbuf:      resb 128*1024
pl_pkt:         resb 256*1024

section .text

; little writers, cursor in rdi. trash rax rcx only

align 16
pl_wvar:
    mov  eax, ecx
    and  eax, 0x7F
    shr  ecx, 7
    jz   .last
    or   al, 0x80
    mov  [rdi], al
    inc  rdi
    jmp  pl_wvar
.last:
    mov  [rdi], al
    inc  rdi
    ret

align 16
pl_w8:
    mov  [rdi], cl
    inc  rdi
    ret

align 16
pl_w16:
    mov  eax, ecx
    xchg al, ah
    mov  [rdi], ax
    add  rdi, 2
    ret

align 16
pl_w32:
    mov  eax, ecx
    bswap eax
    mov  [rdi], eax
    add  rdi, 4
    ret

align 16
pl_w64:
    mov  rax, rcx
    bswap rax
    mov  [rdi], rax
    add  rdi, 8
    ret

; bitset as java wants it: no longs when empty
align 16
pl_wmask:
    test rcx, rcx
    jnz  .some
    mov  byte [rdi], 0
    inc  rdi
    ret
.some:
    mov  byte [rdi], 1
    inc  rdi
    jmp  pl_w64

; chunk conversion

LPROC pl_init_luts
    cmp  dword [rel pl_luts_ok], 0
    jne  .done
    xor  ebx, ebx
.l:
    mov  ecx, ebx
    call mcmap_block_state
    lea  rdx, [rel pl_lut_state]
    mov  [rdx+rbx*4], eax
    lea  rdx, [rel blk_flags]
    movzx eax, word [rdx+rbx*2]
    xor  ecx, ecx
    test eax, BF_SOLID|BF_LIQUID
    jz   .nm
    or   ecx, PLF_MOTION
.nm:
    test eax, BF_LIQUID
    jz   .nf
    or   ecx, PLF_FLUID
.nf:
    lea  rdx, [rel pl_lut_fl]
    mov  [rdx+rbx], cl
    inc  ebx
    cmp  ebx, 256
    jb   .l
    lea  rdi, [rel pl_stone_sec]
    mov  al, B_STONE
    mov  ecx, SECBYTES
    rep  stosb
    lea  rdi, [rel pl_bedrock_sec]
    mov  al, B_BEDROCK
    mov  ecx, 256
    rep  stosb
    mov  al, B_STONE
    mov  ecx, SECBYTES-256
    rep  stosb
    mov  dword [rel pl_luts_ok], 1
.done:
ENDP

; (rcx 4096 of our ids, rdx out) -> rax out end. one section: block count,
; fluid count, block states, biomes
LPROC pl_enc_sec, 1056
    mov  rsi, rcx
    mov  rdi, rdx
    lea  rax, [rel pl_pidx]
    mov  ecx, 64
.clr:
    mov  qword [rax], -1
    add  rax, 8
    dec  ecx
    jnz  .clr
    xor  r12d, r12d                 ; non-air
    xor  r13d, r13d                 ; fluid
    xor  r14d, r14d                 ; palette size
    lea  r8, [rel pl_lut_state]
    lea  r9, [rel pl_lut_fl]
    lea  r10, [rel pl_pidx]
    lea  rbx, LOC(0)                ; palette, java states
    xor  r11d, r11d
.p:
    movzx eax, byte [rsi+r11]
    cmp  dword [r8+rax*4], 0
    je   .p1
    inc  r12d
.p1:
    test byte [r9+rax], PLF_FLUID
    jz   .p2
    inc  r13d
.p2:
    cmp  word [r10+rax*2], 0xFFFF
    jne  .p3
    mov  [r10+rax*2], r14w
    mov  edx, [r8+rax*4]
    mov  [rbx+r14*4], edx
    inc  r14d
.p3:
    inc  r11d
    cmp  r11d, SECBYTES
    jb   .p
    mov  ecx, r12d
    call pl_w16
    mov  ecx, r13d
    call pl_w16
    cmp  r14d, 1
    ja   .multi
    xor  ecx, ecx                   ; single value
    call pl_w8
    mov  ecx, [rbx]
    call pl_wvar
    jmp  .biome
.multi:
    mov  r15d, 4
.bits:
    mov  eax, 1
    mov  ecx, r15d
    shl  eax, cl
    cmp  eax, r14d
    jae  .bitsok
    inc  r15d
    jmp  .bits
.bitsok:
    mov  dword LOC(1024), 0
    cmp  r15d, 8
    jbe  .indirect
    mov  r15d, MC_STATE_BITS        ; can't happen with byte ids, but be correct
    mov  dword LOC(1024), 1
    mov  ecx, r15d
    call pl_w8
    jmp  .pack
.indirect:
    mov  ecx, r15d
    call pl_w8
    mov  ecx, r14d
    call pl_wvar
    xor  r12d, r12d
.pal:
    mov  ecx, [rbx+r12*4]
    call pl_wvar
    inc  r12d
    cmp  r12d, r14d
    jb   .pal
.pack:
    mov  eax, 64                    ; entries don't straddle longs
    xor  edx, edx
    div  r15d
    mov  LOC(1028), eax
    xor  r12d, r12d                 ; current long
    xor  r13d, r13d                 ; entries in it
    xor  r11d, r11d
.e:
    movzx eax, byte [rsi+r11]
    cmp  dword LOC(1024), 0
    jne  .direct
    movzx eax, word [r10+rax*2]
    jmp  .put
.direct:
    mov  eax, [r8+rax*4]
.put:
    mov  ecx, r13d
    imul ecx, r15d
    shl  rax, cl
    or   r12, rax
    inc  r13d
    cmp  r13d, LOC(1028)
    jb   .en
    mov  rcx, r12
    call pl_w64
    xor  r12d, r12d
    xor  r13d, r13d
.en:
    inc  r11d
    cmp  r11d, SECBYTES
    jb   .e
    test r13d, r13d
    jz   .biome
    mov  rcx, r12
    call pl_w64
.biome:
    xor  ecx, ecx                   ; one biome for the whole section
    call pl_w8
    mov  ecx, [rel pl_cur_biome]
    call pl_wvar
    mov  rax, rdi
ENDP

; (rcx 4096 light bytes, edx 4 sky / 0 block, r8 out 2048) -> eax 1 if anything nonzero.
; java nibbles: x + z*16 + y*256 like ours, low nibble first
LPROC pl_pack_nib
    mov  rsi, rcx
    mov  ecx, edx
    xor  r9d, r9d
    mov  r10d, 2048
.l:
    movzx eax, byte [rsi]
    shr  eax, cl
    and  eax, 15
    movzx edx, byte [rsi+1]
    shr  edx, cl
    and  edx, 15
    shl  edx, 4
    or   eax, edx
    mov  [r8], al
    or   r9d, eax
    add  rsi, 2
    inc  r8
    dec  r10d
    jnz  .l
    xor  eax, eax
    test r9d, r9d
    setnz al
ENDP

; (rcx CHUNK*, rdx out) -> eax bytes. map_chunk body without the packet id.
; the chunk needs blocks + light (>= CS_LIT)
PROC mcplay_encode_chunk, 640
    mov  rbx, rcx
    mov  r15, rdx
    mov  rdi, rdx
    call pl_init_luts
    mov  ecx, [rbx+CHUNK.cx]
    call pl_w32
    mov  ecx, [rbx+CHUNK.cz]
    call pl_w32

    ; heightmaps. LOC(0) world_surface, LOC(296) motion_blocking, value = top+1 - min y
    lea  rdx, LOC(0)
    xor  eax, eax
    mov  ecx, HM_LONGS*2
.hz:
    mov  [rdx], rax
    add  rdx, 8
    dec  ecx
    jnz  .hz
    lea  r10, [rel pl_lut_fl]
    xor  r12d, r12d                 ; column
    xor  r13d, r13d                 ; long
    xor  r14d, r14d                 ; shift
.hcol:
    lea  rsi, [rbx+CHUNK_BLOCKS+127*256]
    add  rsi, r12
    mov  r8d, -1
    mov  r9d, -1
    mov  r11d, 127
.hy:
    movzx eax, byte [rsi]
    test eax, eax
    jz   .hnext
    cmp  r8d, -1
    jne  .hmb
    mov  r8d, r11d
.hmb:
    test byte [r10+rax], PLF_MOTION
    jz   .hnext
    mov  r9d, r11d                  ; ws is set by now too
    jmp  .hput
.hnext:
    sub  rsi, 256
    dec  r11d
    jns  .hy
.hput:
    sub  r8d, MC_WORLD_MIN_Y-1
    sub  r9d, MC_WORLD_MIN_Y-1
    mov  ecx, r14d
    shl  r8, cl
    shl  r9, cl
    lea  rax, LOC(0)
    or   [rax+r13*8], r8
    or   [rax+r13*8+HM_LONGS*8], r9
    add  r14d, 9
    cmp  r14d, 63
    jb   .hsame
    xor  r14d, r14d
    inc  r13d
.hsame:
    inc  r12d
    cmp  r12d, 256
    jb   .hcol
    mov  ecx, 2
    call pl_wvar
    mov  ecx, 1                     ; WORLD_SURFACE
    call pl_wvar
    lea  rsi, LOC(0)
    call .hm_out
    mov  ecx, 4                     ; MOTION_BLOCKING
    call pl_wvar
    lea  rsi, LOC(HM_LONGS*8)
    call .hm_out
    jmp  .sections
.hm_out:                            ; rsi longs, own little sub, stack stays aligned enough
    mov  ecx, HM_LONGS
    call pl_wvar
    mov  r12d, HM_LONGS
.hmo:
    mov  rcx, [rsi]
    call pl_w64
    add  rsi, 8
    dec  r12d
    jnz  .hmo
    ret
    call closesocket
.more:
    dec  r15d
    jnz  .again
.done:
ENDP
