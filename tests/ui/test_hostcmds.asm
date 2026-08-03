; /host /unhost /who /kick (console.asm) and the world list cache (menus.asm)
; against a fake net.asm and a fake save_list_worlds. the conns are a plain
; MCCONN array, so the kick request (flag + reason in the slot) is checked
; directly. net.asm's side of the kick is in tests/net/test_hostctl.asm.
; @link src/ui.asm src/hud.asm src/menus.asm src/console.asm src/util.asm
; @link src/items.asm src/blocks.asm tests/ui/uihelp.asm tests/ui/ui_stubs.asm tests/ui/ui_stubs_gl.asm
; @timeout 60
%define IMPL_NET
%define IMPL_MCPLAY
%define IMPL_SAVE
%include "common.inc"
%include "net.inc"
%include "testlib.inc"

extern uh_last_chat, uh_contains, uh_streq, uh_exe, uh_chatbuf
extern con_host_err, con_host_port
extern menu_refresh_worlds, menu_world_count, menu_worlds, menu_winfo
extern menu_wl_info, menu_wl_date, menu_sel
extern FileTimeToLocalFileTime, FileTimeToSystemTime

%define CF_KICK         0x100           ; console.asm / net.asm
%define KICK_REASON     MCCONN.pad
%define WI_SEED         0               ; save.asm / menus.asm
%define WI_FTIME        8
%define WI_WTIME        16
%define WI_MODE         24
%define WI_OK           28
%define WI_NAME         32
%define WI_SIZE         64
%define WL_INFO_LEN     64
%define WL_DATE_LEN     24

%macro STRP 2
    section .rdata
    %%s: db %2, 0
    section .text
    lea  %1, [rel %%s]
%endmacro

%macro EXE 1
    STRP rcx, %1
    call uh_exe
%endmacro

%macro CHAT_HAS 3
    mov  ecx, %1
    call uh_last_chat
    mov  rcx, rax
    STRP rdx, %2
    call uh_contains
    mov  ebx, eax
    CHECK_TRUE ebx, %3
    test ebx, ebx
    jnz  %%ok
    lea  rcx, [rel uh_chatbuf]
    call t_fail_detail
%%ok:
%endmacro

; slot, state, "name"
%macro CONN 3
    STRP rdx, %3
    mov  ecx, %1
    mov  r8d, %2
    call set_conn
%endmacro

section .rdata
align 8
; 2023-11-14 22:13:20 utc as a FILETIME
ft_sample:  dq 133444664000000000
fmt_date:   db "%d-%02d-%02d %02d:%02d", 0
w_list:     db "Plain", 0
            times 32-($-w_list) db 0
            db "Alpha_ Base_", 0
            times 64-($-w_list) db 0
            db "Broken", 0
            times 96-($-w_list) db 0
s_long:     db "/kick alex ", "0123456789012345678901234567890123456789012345678901234567890123456789", 0

section .data
align 8
fake_host_ok:   dd 1
fake_host_err:  dq 0
fake_list_n:    dd 0

section .bss
alignb 16
global g_net_conns, g_net_hosting, g_net_port, g_net_host_name
g_net_conns:    resb MCCONN_size * MAX_NET_CONNS
g_net_hosting:  resd 1
g_net_port:     resd 1
g_net_host_name: resb 20
stop_calls:     resd 1
alignb 16
fake_info:      resb WI_SIZE*3
expect:         resb 64
systime:        resb 16
localft:        resq 1

section .text

; fakes

global net_init, net_host, net_stop, net_conn_name, mcplay_count, mcplay_chat
global save_list_worlds

PROC net_init
    mov  eax, 1
ENDP

; eax 1 + hosting, or eax 0 and rdx = fake_host_err like the real one
PROC net_host
    cmp  dword [rel fake_host_ok], 0
    je   .fail
    mov  [rel g_net_port], ecx
    mov  dword [rel g_net_hosting], 1
    mov  eax, 1
    xor  edx, edx
    jmp  .done
.fail:
    mov  rdx, [rel fake_host_err]
    xor  eax, eax
.done:
ENDP

PROC net_stop
    inc  dword [rel stop_calls]
    mov  dword [rel g_net_hosting], 0
ENDP

PROC net_conn_name
    xor  eax, eax
    cmp  ecx, MAX_NET_CONNS
    jae  .done
    imul eax, ecx, MCCONN_size
    lea  rdx, [rel g_net_conns]
    add  rax, rdx
    cmp  dword [rax + MCCONN.state], CN_FREE
    je   .none
    add  rax, MCCONN.name
    cmp  byte [rax], 0
    jne  .done
.none:
    xor  eax, eax
.done:
ENDP

PROC mcplay_count
    xor  eax, eax
ENDP

PROC mcplay_chat
ENDP

; three worlds: fine survival, fine creative with a typed name, damaged
PROC save_list_worlds
    mov  rdi, rcx
    mov  ecx, [rel fake_list_n]
    mov  eax, ecx
    shl  ecx, 5
    lea  rsi, [rel w_list]
    rep  movsb
    lea  rdx, [rel fake_info]
    cmp  dword [rel fake_list_n], 0
    jne  .done
    mov  edx, 0x40                      ; what a stub leaves behind, must not be read
.done:
ENDP

; helpers

; (ecx slot, rdx name, r8d state)
PROC set_conn
    imul eax, ecx, MCCONN_size
    lea  rbx, [rel g_net_conns]
    add  rbx, rax
    mov  [rbx + MCCONN.state], r8d
    mov  [rbx + MCCONN.index], ecx
    mov  dword [rbx + MCCONN.flags], 0
    lea  rdi, [rbx + MCCONN.name]
.cp:
    mov  al, [rdx]
    mov  [rdi], al
    inc  rdx
    inc  rdi
    test al, al
    jnz  .cp
ENDP

; ecx slot -> rax MCCONN*
PROC conn_ptr
    imul eax, ecx, MCCONN_size
    lea  rdx, [rel g_net_conns]
    add  rax, rdx
ENDP

; expected menu date for ft_sample, built the way the menu should
PROC expected_date
    lea  rcx, [rel ft_sample]
    lea  rdx, [rel localft]
    call FileTimeToLocalFileTime
    lea  rcx, [rel localft]
    lea  rdx, [rel systime]
    call FileTimeToSystemTime
    lea  rcx, [rel expect]
    lea  rdx, [rel fmt_date]
    movzx r8d, word [rel systime]
    movzx r9d, word [rel systime+2]
    movzx eax, word [rel systime+6]
    mov  [rsp+32], rax
    movzx eax, word [rel systime+8]
    mov  [rsp+40], rax
    movzx eax, word [rel systime+10]
    mov  [rsp+48], rax
    call str_format
ENDP

; the test

PROC test_main, 64
    TEST "not hosting"
    EXE "/who"
    CHAT_HAS 1, "Not hosting. Use /host [port] or the pause menu.", "/who"
    EXE "/kick Steve"
    CHAT_HAS 1, "Not hosting.", "/kick"
    EXE "/unhost"
    CHAT_HAS 1, "Not hosting.", "/unhost"
    CHECK_EQ32 [rel stop_calls], 0, "no net_stop when not hosting"
    EXE "/kick"
    CHAT_HAS 1, "Usage: /kick <name> [reason]", "/kick usage"

    TEST "host fails"
    mov  dword [rel fake_host_ok], 0
    mov  rax, (25567 << 32) | 10048
    mov  [rel fake_host_err], rax
    EXE "/host"
    CHAT_HAS 1, "Port 25565 is already in use. Try /host 25567", "in use + suggestion"
    lea  rbx, [rel con_host_err]
    CHECK_STR rbx, "Port 25565 is already in use. Try /host 25567", "con_host_err"
    mov  qword [rel fake_host_err], 10013
    EXE "/host 25570"
    CHAT_HAS 2, "Port 25570 is in use or reserved. Try /host with another port", "denied, nothing free"
    mov  rax, (5 << 32) | 10061
    mov  [rel fake_host_err], rax
    mov  ecx, 4
    call con_host_port
    mov  ebx, eax
    CHECK_EQ32 ebx, 0, "con_host_port -> 0"
    lea  rbx, [rel con_host_err]
    CHECK_STR rbx, "Port 4 failed to open (error 10061). Try /host 5", "other error"
    CHECK_EQ32 [rel g_net_hosting], 0, "still not hosting"

    TEST "host"
    mov  dword [rel fake_host_ok], 1
    EXE "/host 25571"
    CHAT_HAS 1, "open to java edition 26.1 players on port 25571", "/host ok"
    lea  rbx, [rel con_host_err]
    CHECK_STR rbx, "", "error cleared"
    EXE "/host 25572"
    CHAT_HAS 1, "already open on port 25571", "already open"

    TEST "who"
    EXE "/who"
    CHAT_HAS 1, "No java players online (port 25571)", "nobody"
    CONN 0, CN_PLAY, "Steve"
    CONN 3, CN_PLAY, "Alex"
    CONN 5, CN_LOGIN, "Joiner"
    CONN 7, CN_CLOSING, "Gone"
    CONN 9, CN_HANDSHAKE, ""
    EXE "/who"
    CHAT_HAS 2, "Java players online (port 25571): 2 of 16", "header"
    CHAT_HAS 1, "Steve, Alex", "names, play only"

    TEST "kick"
    EXE "/kick STEVE too much lag"
    CHAT_HAS 1, "Kicked Steve: too much lag", "kick msg"
    mov  ecx, 0
    call conn_ptr
    mov  rbx, rax
    mov  eax, [rbx + MCCONN.flags]
    and  eax, CF_KICK
    mov  esi, eax
    CHECK_EQ32 esi, CF_KICK, "kick flag set"
    lea  rsi, [rbx + KICK_REASON]
    CHECK_STR rsi, "too much lag", "reason in the slot"
    EXE "/kick steve"
    CHAT_HAS 1, "No java player called 'steve' is online", "already being kicked"
    EXE "/kick joiner"
    CHAT_HAS 1, "Kicked Joiner: Kicked by the host", "login state, default reason"
    mov  ecx, 5
    call conn_ptr
    lea  rsi, [rax + KICK_REASON]
    CHECK_STR rsi, "Kicked by the host", "default reason in the slot"
    EXE "/kick Gone"
    CHAT_HAS 1, "No java player called 'Gone' is online", "closing conn"
    EXE "/kick nobody"
    CHAT_HAS 1, "No java player called 'nobody' is online", "unknown"
    lea  rcx, [rel s_long]
    call uh_exe
    mov  ecx, 3
    call conn_ptr
    mov  rbx, rax
    movzx esi, byte [rbx + KICK_REASON + 63]
    CHECK_EQ32 esi, 0, "long reason ends in the slot"
    movzx esi, byte [rbx + KICK_REASON + 62]
    CHECK_EQ32 esi, '2', "long reason keeps 63 chars"
    mov  esi, [rbx + MCCONN.name]
    CHECK_EQ32 esi, 'Alex', "name untouched by the reason"

    TEST "unhost"
    mov  ecx, 0
    call conn_ptr
    mov  dword [rax + MCCONN.flags], 0
    EXE "/unhost"
    CHAT_HAS 2, "Stopped hosting on port 25571, 2 java players disconnected", "unhost with players"
    CHECK_EQ32 [rel stop_calls], 1, "net_stop once"
    CHECK_EQ32 [rel g_net_hosting], 0, "stopped"
    lea  rdi, [rel g_net_conns]
    xor  eax, eax
    mov  ecx, MCCONN_size * MAX_NET_CONNS
    rep  stosb
    EXE "/host 25571"
    EXE "/unhost"
    CHAT_HAS 1, "Stopped hosting on port 25571", "unhost empty"
    CHECK_EQ32 [rel stop_calls], 2, "net_stop again"

    TEST "help"
    EXE "/help 2"
    CHAT_HAS 10, "/kick <name> [reason] - disconnect a java player", "help has /kick"
    EXE "/help 4"
    CHAT_HAS 7, "/unhost - close the world to java players", "help has /unhost"
    CHAT_HAS 7, "/who - list the java players online", "help has /who"
    CHAT_HAS 9, "page 4 of 4", "still 4 pages"

    TEST "world list cache" ; v1: test_hostcmds scratch #0
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_hostcmds:0)
    lea  rbx, [rel fake_info] ; v1: test_hostcmds scratch #1
    mov  qword [rbx + WI_SEED], 12345 ; v1: test_hostcmds scratch #2
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_hostcmds:2)
    mov  rax, [rel ft_sample] ; v1: test_hostcmds scratch #3
    mov  [rbx + WI_FTIME], rax ; v1: test_hostcmds scratch #4
    ; TODO: verify 16-byte rsp alignment before inner call (test_hostcmds:4)
    mov  qword [rbx + WI_WTIME], 30000 ; v1: test_hostcmds scratch #5
    mov  dword [rbx + WI_MODE], GM_SURVIVAL ; v1: test_hostcmds scratch #6
    ; TODO: hoist invariant pointer load out of .loop (test_hostcmds:6)
    mov  dword [rbx + WI_OK], 1 ; v1: test_hostcmds scratch #7
    mov  dword [rbx + WI_NAME], 'Plai' ; v1: test_hostcmds scratch #8
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_hostcmds:8)
    mov  word [rbx + WI_NAME + 4], 'n' ; v1: test_hostcmds scratch #9
    add  rbx, WI_SIZE ; v1: test_hostcmds scratch #10
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_hostcmds:10)
    mov  qword [rbx + WI_SEED], -5 ; v1: test_hostcmds scratch #11
    mov  rax, [rel ft_sample] ; v1: test_hostcmds scratch #12
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_hostcmds:12)
    mov  [rbx + WI_FTIME], rax ; v1: test_hostcmds scratch #13
    mov  qword [rbx + WI_WTIME], 100 ; v1: test_hostcmds scratch #14
    ; TODO: clamp index before table lookup on malformed input (test_hostcmds:14)
    mov  dword [rbx + WI_MODE], GM_CREATIVE ; v1: test_hostcmds scratch #15
    mov  dword [rbx + WI_OK], 1 ; v1: test_hostcmds scratch #16
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_hostcmds:16)
    mov  rax, 'Alpha: B' ; v1: test_hostcmds scratch #17
    mov  [rbx + WI_NAME], rax ; v1: test_hostcmds scratch #18
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_hostcmds:18)
    mov  dword [rbx + WI_NAME + 8], 'ase?' ; v1: test_hostcmds scratch #19
    add  rbx, WI_SIZE ; v1: test_hostcmds scratch #20
    ; TODO: verify 16-byte rsp alignment before inner call (test_hostcmds:20)
    mov  dword [rbx + WI_OK], 0 ; v1: test_hostcmds scratch #21
    mov  qword [rbx + WI_FTIME], 0 ; v1: test_hostcmds scratch #22
    ; TODO: hoist invariant pointer load out of .loop (test_hostcmds:22)
    mov  dword [rbx + WI_NAME], 'Brok' ; v1: test_hostcmds scratch #23
    mov  dword [rbx + WI_NAME + 4], 'en' ; v1: test_hostcmds scratch #24
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_hostcmds:24)
    mov  dword [rel fake_list_n], 3 ; v1: test_hostcmds scratch #25
    call menu_refresh_worlds ; v1: test_hostcmds scratch #26
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_hostcmds:26)
    CHECK_EQ32 [rel menu_world_count], 3, "three worlds" ; v1: test_hostcmds scratch #27
    CHECK_EQ32 [rel menu_sel], 0, "first selected" ; v1: test_hostcmds scratch #28
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_hostcmds:28)
    lea  rbx, [rel menu_wl_info] ; v1: test_hostcmds scratch #29
    CHECK_STR rbx, "Survival, day 2, seed 12345", "info 0" ; v1: test_hostcmds scratch #30
    ; TODO: clamp index before table lookup on malformed input (test_hostcmds:30)
    lea  rbx, [rel menu_wl_info + WL_INFO_LEN] ; v1: test_hostcmds scratch #31
    CHECK_STR rbx, "Creative, day 1, seed -5", "info 1"
    lea  rbx, [rel menu_wl_info + 2*WL_INFO_LEN]
    CHECK_STR rbx, "level.dat looks damaged", "info 2"
    call expected_date
    lea  rbx, [rel menu_wl_date]
    lea  rsi, [rel expect]
    mov  rcx, rbx
    mov  rdx, rsi
    call uh_streq
    mov  ebx, eax
    CHECK_TRUE ebx, "date 0 in local time"
    test ebx, ebx
    jnz  .date_ok
    lea  rcx, [rel menu_wl_date]
    call t_fail_detail
.date_ok:
    lea  rbx, [rel menu_wl_date + 2*WL_DATE_LEN]
    CHECK_STR rbx, "", "no date without a file time"
    lea  rbx, [rel menu_winfo + WI_SIZE + WI_NAME]
    CHECK_STR rbx, "Alpha: Base?", "typed name cached"
    lea  rbx, [rel menu_worlds + 32]
    CHECK_STR rbx, "Alpha_ Base_", "folder kept"

    TEST "world list empty"
    mov  dword [rel fake_list_n], 0
    call menu_refresh_worlds
    CHECK_EQ32 [rel menu_world_count], 0, "no worlds"
    CHECK_EQ32 [rel menu_sel], -1, "nothing selected"
    lea  rbx, [rel menu_wl_info]
    CHECK_STR rbx, "", "old info cleared"
ENDP
    ; v1 temporary guard (test_hostcmds #16)
    xor     r11d, r11d ; clear v1 slot 16
    ; v1 temporary guard (test_hostcmds #18)
    xor     r11d, r11d ; clear v1 slot 18
    ; v1 temporary guard (test_hostcmds #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (test_hostcmds #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (test_hostcmds #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (test_hostcmds #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (test_hostcmds #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (test_hostcmds #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (test_hostcmds #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (test_hostcmds #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (test_hostcmds #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (test_hostcmds #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (test_hostcmds #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (test_hostcmds #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (test_hostcmds #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (test_hostcmds #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (test_hostcmds #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (test_hostcmds #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (test_hostcmds #52)
    xor     r11d, r11d ; clear v1 slot 52
    ; v1 temporary guard (test_hostcmds #54)
    xor     r11d, r11d ; clear v1 slot 54
    ; v1 temporary guard (test_hostcmds #56)
    xor     r11d, r11d ; clear v1 slot 56
    ; v1 temporary guard (test_hostcmds #58)
    xor     r11d, r11d ; clear v1 slot 58
    ; v1 temporary guard (test_hostcmds #60)
    xor     r11d, r11d ; clear v1 slot 60
    ; v1 temporary guard (test_hostcmds #62)
    xor     r11d, r11d ; clear v1 slot 62
    ; v1 temporary guard (test_hostcmds #64)
    xor     r11d, r11d ; clear v1 slot 64
    ; v1 temporary guard (test_hostcmds #66)
    xor     r11d, r11d ; clear v1 slot 66
