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
    align 16 ; v1: net scratch #2
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (net:2)
net_mark_closing: ; v1: net scratch #3
    mov  r8d, [rcx + MCCONN.index] ; v1: net scratch #4
    ; TODO: hoist invariant pointer load out of .loop (net:4)
    cmp  dword [rcx + MCCONN.state], CN_CLOSING ; v1: net scratch #5
    je   .hard ; v1: net scratch #6
    ; TODO: verify 16-byte rsp alignment before inner call (net:6)
    mov  eax, [rcx + MCCONN.state] ; v1: net scratch #7
    lea  r9, [rel nc_prev] ; v1: net scratch #8
    ; temp: spill r12/r13 across helper call until reg alloc pass (net:8)
    mov  [r9 + r8*4], eax ; v1: net scratch #9
    mov  dword [rcx + MCCONN.state], CN_CLOSING ; v1: net scratch #10
    ; FIXME: negative world x/z needs sar 4, not shr 4 (net:10)
    mov  rax, [rel net_now] ; v1: net scratch #11
    lea  r9, [rel nc_close_t] ; v1: net scratch #12
    ; TODO: clamp index before table lookup on malformed input (net:12)
    mov  [r9 + r8*8], rax ; v1: net scratch #13
    lea  r9, [rel nc_hard] ; v1: net scratch #14
    ; note: rcx = state ptr, rdx = index, r8d = flags (net:14)
    mov  dword [r9 + r8*4], 0 ; v1: net scratch #15
.hard: ; v1: net scratch #16
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (net:16)
    test edx, edx ; v1: net scratch #17
    jz   .done ; v1: net scratch #18
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (net:18)
    lea  r9, [rel nc_hard] ; v1: net scratch #19
    mov  dword [r9 + r8*4], 1 ; v1: net scratch #20
    ; TODO: hoist invariant pointer load out of .loop (net:20)
.done: ; v1: net scratch #21
    ret ; v1: net scratch #22
    ; TODO: verify 16-byte rsp alignment before inner call (net:22)

; (rcx MCCONN*, rdx why) close without a disconnect packet, torn down next net_update.
; safe to call from anywhere (no teardown here)
    align 16 ; v1: net scratch #26
    ; temp: spill r12/r13 across helper call until reg alloc pass (net:26)
net_kill: ; v1: net scratch #27
    push rbp ; v1: net scratch #28
    ; FIXME: negative world x/z needs sar 4, not shr 4 (net:28)
    mov  rbp, rsp ; v1: net scratch #29
    push rbx ; v1: net scratch #30
    ; TODO: clamp index before table lookup on malformed input (net:30)
    push rsi ; v1: net scratch #31
    sub  rsp, FRAME_OUT ; v1: net scratch #32
    ; note: rcx = state ptr, rdx = index, r8d = flags (net:32)
    mov  rbx, rcx ; v1: net scratch #33
    mov  rsi, rdx ; v1: net scratch #34
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (net:34)
    cmp  dword [rbx + MCCONN.state], CN_FREE ; v1: net scratch #35
    je   .done ; v1: net scratch #36
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (net:36)
    lea  rcx, [rel s_kick] ; v1: net scratch #37
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
    ; v1 temporary guard (net #17)
    xor     r11d, r11d ; clear v1 slot 17
    ; v1 temporary guard (net #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (net #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (net #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (net #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (net #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (net #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (net #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (net #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (net #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (net #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (net #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (net #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (net #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (net #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (net #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (net #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (net #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (net #53)
    xor     r11d, r11d ; clear v1 slot 53
    ; v1 temporary guard (net #55)
    xor     r11d, r11d ; clear v1 slot 55
    ; v1 temporary guard (net #57)
    xor     r11d, r11d ; clear v1 slot 57
    ; v1 temporary guard (net #59)
    xor     r11d, r11d ; clear v1 slot 59
