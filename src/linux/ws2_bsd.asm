%ifdef LINUX
%define WIN32_INC
%include "common.inc"

extern socket, bind, listen, accept4, recv, send, shutdown, setsockopt, close
extern fcntl, ioctl, __errno_location, signal, memset

%macro CCALL 1
    xor  eax, eax
    call %1 wrt ..plt
%endmacro

%define W32E            0x10000         ; same errno tag as w32compat
%define O_NONBLOCK      0x800
%define SOCK_CLOEXEC    0x80000
%define MSG_NOSIGNAL    0x4000

section .rodata
align 4
; errno -> WSAE*, 0 ends it
ws_errmap:
    dd 4, 10004,  9, 10038,  13, 10013,  14, 10014,  22, 10022,  24, 10024
    dd 11, 10035,  115, 10036,  114, 10037,  88, 10038,  89, 10039,  90, 10040
    dd 91, 10041,  92, 10042,  93, 10043,  94, 10044,  95, 10045,  96, 10046
    dd 97, 10047,  98, 10048,  99, 10049,  100, 10050,  101, 10051,  102, 10052
    dd 103, 10053,  104, 10054,  105, 10055,  106, 10056,  107, 10057,  108, 10058
    dd 110, 10060,  111, 10061,  112, 10064,  113, 10065
    dd 32, 10054                        ; EPIPE: peer's gone, windows says reset
    dd 0, 0

section .text

; (version, WSADATA*) -> 0. nothing to start, but SIGPIPE has to go or the
; first send to a dead client kills the game
PROCX WSAStartup
    mov  ebx, ecx
    mov  r12, rdx
    test r12, r12
    jnz  .ok
    mov  eax, 10014                     ; WSAEFAULT
    jmp  .done
.ok:
    mov  edi, 13
    mov  esi, 1
    CCALL signal
    mov  rdi, r12
    xor  esi, esi
    mov  edx, 408                       ; sizeof WSADATA, x64
    CCALL memset
    mov  word [r12], 0x0202
    mov  word [r12+2], 0x0202
    xor  eax, eax
.done:
ENDPX

LEAF WSACleanup
    xor  eax, eax
    ret

PROCX WSAGetLastError
    CCALL __errno_location
    mov  eax, [rax]
    test eax, W32E
    jz   .map
    and  eax, 0xFFFF
    jmp  .done
.map:
    test eax, eax
    jz   .done
    lea  rdx, [rel ws_errmap]
.scan:
    mov  ecx, [rdx]
    test ecx, ecx
    jz   .raw
    cmp  ecx, eax
    je   .hit
    add  rdx, 8
    jmp  .scan
.hit:
    mov  eax, [rdx+4]
    jmp  .done
.raw:
    or   eax, 0x20000000
.done:
ENDPX

PROCX WSASetLastError
    mov  ebx, ecx
    CCALL __errno_location
    test ebx, ebx
    jz   .z
    or   ebx, W32E
.z:
    mov  [rax], ebx
ENDPX

; (af, type, proto) -> rax fd or -1. AF_INET6 is 23 on windows
PROCX ws_socket
    mov  edi, ecx
    cmp  edi, 23
    jne  .af
    mov  edi, 10
.af:
    mov  esi, edx
    or   esi, SOCK_CLOEXEC
    mov  edx, r8d
    CCALL socket
    movsxd rax, eax
ENDPX

; sockaddr_in is laid out the same on both
PROCX ws_bind
    mov  edi, ecx
    mov  rsi, rdx
    mov  edx, r8d
    CCALL bind
ENDPX

PROCX ws_listen
    mov  edi, ecx
    mov  esi, edx
    CCALL listen
ENDPX

; windows hands back a socket in the listener's blocking mode, linux doesn't
PROCX ws_accept
    mov  ebx, ecx
    mov  r12, rdx
    mov  r13, r8
    mov  edi, ebx
    mov  esi, 3                         ; F_GETFL
    CCALL fcntl
    mov  r14d, SOCK_CLOEXEC
    test eax, eax
    js   .acc
    test eax, O_NONBLOCK
    jz   .acc
    or   r14d, O_NONBLOCK               ; == SOCK_NONBLOCK
.acc:
    mov  edi, ebx
    mov  rsi, r12
    mov  rdx, r13
    mov  ecx, r14d
    CCALL accept4
    movsxd rax, eax
ENDPX

; (s, buf, len, flags) -> eax bytes, 0 = peer closed, -1 = error
PROCX ws_recv
    mov  edi, ecx
    mov  rsi, rdx
    mov  edx, r8d
    mov  ecx, r9d
    test ecx, 8                         ; MSG_WAITALL is 0x100 here
    jz   .go
    xor  ecx, 8 | 0x100
.go:
    CCALL recv
ENDPX

PROCX ws_send
    mov  edi, ecx
    mov  rsi, rdx
    mov  edx, r8d
    mov  ecx, r9d
    or   ecx, MSG_NOSIGNAL
    CCALL send
ENDPX

; SD_* == SHUT_*
PROCX ws_shutdown
    mov  edi, ecx
    mov  esi, edx
    CCALL shutdown
ENDPX

PROCX closesocket
    mov  edi, ecx
    CCALL close
ENDPX

; (s, level, opt, val, len). SOL_SOCKET options get renumbered, the ones with
; different value layouts converted. tcp level passes through (NODELAY = 1 both)
PROCX ws_setsockopt, 16
    mov  ebx, ecx
    mov  r12d, edx
    mov  r13d, r8d
    mov  r14, r9
    mov  r15d, ARG5
    cmp  r12d, 0xFFFF
    jne  .pass
    mov  r12d, 1                        ; SOL_SOCKET
    ; linux never lets two sockets listen on one port, so the exclusive flag
    ; is just reuseaddr: no TIME_WAIT lockout after a restart
    cmp  r13d, 0xFFFFFFFB               ; SO_EXCLUSIVEADDRUSE
    je   .reuse
    cmp  r13d, 4
    je   .reuse
    mov  eax, 9                         ; SO_KEEPALIVE
    cmp  r13d, 8
    je   .num
    mov  eax, 6                         ; SO_BROADCAST
    cmp  r13d, 0x20
    je   .num
    mov  eax, 7                         ; SO_SNDBUF
    cmp  r13d, 0x1001
    je   .num
    mov  eax, 8                         ; SO_RCVBUF
    cmp  r13d, 0x1002
    je   .num
    mov  eax, 21                        ; SO_SNDTIMEO
    cmp  r13d, 0x1005
    je   .tv
    mov  eax, 20                        ; SO_RCVTIMEO
    cmp  r13d, 0x1006
    je   .tv
    cmp  r13d, 0x80                     ; SO_LINGER
    je   .linger
    jmp  .pass
.reuse:
    mov  eax, 2
.num:
    mov  r13d, eax
    jmp  .pass
.tv:
    ; dword ms -> struct timeval
    mov  r13d, eax
    mov  eax, [r14]
    xor  edx, edx
    mov  ecx, 1000
    div  ecx
    mov  LOC(0), rax
    imul edx, edx, 1000
    mov  LOC(8), rdx
    lea  r14, LOC(0)
    mov  r15d, 16
    jmp  .pass
.linger:
    ; two u_shorts -> two ints
    mov  r13d, 13
    movzx eax, word [r14]
    mov  LOC(0), eax
    movzx eax, word [r14+2]
    mov  LOC(4), eax
    lea  r14, LOC(0)
    mov  r15d, 8
.pass:
    mov  edi, ebx
    mov  esi, r12d
    mov  edx, r13d
    mov  rcx, r14
    mov  r8d, r15d
    CCALL setsockopt
ENDPX

; FIONBIO -> O_NONBLOCK, FIONREAD -> ioctl FIONREAD. anything else EINVAL
PROCX ioctlsocket, 16
    mov  ebx, ecx
    mov  r12, r8
    cmp  edx, 0x8004667E
    je   .nbio
    cmp  edx, 0x4004667F
    je   .nread
    CCALL __errno_location
    mov  dword [rax], 22
    mov  eax, -1
    jmp  .done
.nbio:
    mov  edi, ebx
    mov  esi, 3                         ; F_GETFL
    CCALL fcntl
    test eax, eax
    js   .done
    mov  edx, eax
    and  edx, ~O_NONBLOCK
    cmp  dword [r12], 0
    je   .set
    or   edx, O_NONBLOCK
.set:
    mov  edi, ebx
    mov  esi, 4                         ; F_SETFL
    CCALL fcntl
    test eax, eax
    js   .done
    xor  eax, eax
    jmp  .done
.nread:
    mov  edi, ebx
    mov  esi, 0x541B
    lea  rdx, LOC(0)
    CCALL ioctl
    test eax, eax
    js   .done
    mov  eax, LOC(0)
    mov  [r12], eax
    xor  eax, eax
.done:
ENDPX

%endif
