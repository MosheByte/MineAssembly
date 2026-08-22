; shared bits for test_ui / test_review: chat log peeking, string helpers, console
; drivers, and a child runner that re-runs this exe as "--child <name> [arg]" and
; waits for a "CHILD <text>" line on its stdout.
%include "common.inc"
%include "testlib.inc"

extern console_execute, con_insert
extern con_lines, con_head, con_total
extern CreatePipe, CreateProcessA, TerminateProcess, GetExitCodeProcess
extern GetModuleFileNameA, SetHandleInformation, PeekNamedPipe

%define CHAT_RING       100             ; must match console.asm
%define CHAT_STRIDE     144

; STARTUPINFOA / PROCESS_INFORMATION offsets (x64)
%define SI_SIZE         104
%define SI_FLAGS        60
%define SI_STDIN        80
%define SI_STDOUT       88
%define SI_STDERR       96
%define STARTF_USESTDHANDLES 0x100
%define PI_HPROCESS     0
%define PI_HTHREAD      8

global uh_chat_line, uh_last_chat, uh_strip, uh_width, uh_contains, uh_starts
global uh_streq, uh_strcpy, uh_strlen, uh_exe, uh_type
global uh_child_mode, uh_run_child, uh_child_result
global uh_chatbuf

section .rdata
s_child_flag:   db "--child ", 0
s_child_pfx:    db "CHILD ", 0
s_crash:        db "crash rc=", 0
s_nl:           db 13, 10, 0

section .bss
alignb 16
uh_chatbuf:     resb 4096
uh_tmp:         resb 256
uh_cmdline:     resb 1024
uh_pipebuf:     resb 8192
uh_exe_path:    resb 520
alignb 8
uh_hread:       resq 1
uh_hproc:       resq 1
uh_hthread:     resq 1

section .text

LEAF uh_strlen
    xor  eax, eax
.l: cmp  byte [rcx+rax], 0
    je   .r
    inc  rax
    jmp  .l
.r: ret

LEAF uh_strcpy
    mov  rax, rcx
.l: mov  r8b, [rdx]
    mov  [rcx], r8b
    inc  rcx
    inc  rdx
    test r8b, r8b
    jnz  .l
    ret

LEAF uh_streq
.l: mov  al, [rcx]
    cmp  al, [rdx]
    jne  .no
    inc  rcx
    inc  rdx
    test al, al
    jnz  .l
    mov  eax, 1
    ret
.no:
    xor  eax, eax
    ret

LEAF uh_starts
.l: mov  al, [rdx]
    test al, al
    jz   .yes
    cmp  al, [rcx]
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

LEAF uh_contains
.outer:
    xor  r8d, r8d
.inner:
    mov  al, [rdx+r8]
    test al, al
    jz   .yes
    cmp  al, [rcx+r8]
    jne  .next
    inc  r8
    jmp  .inner
.next:
    cmp  byte [rcx], 0
    je   .no
    inc  rcx
    jmp  .outer
.yes:
    mov  eax, 1
    ret
.no:
    xor  eax, eax
    ret

; colour codes are 0x0C + one char
LEAF uh_strip
.l: movzx eax, byte [rcx]
    test eax, eax
    jz   .end
    cmp  eax, 12
    jne  .put
    cmp  byte [rcx+1], 0                ; lone \f at the end: drop it
    je   .end
    add  rcx, 2
    jmp  .l
.put:
    mov  [rdx], al
    inc  rdx
    inc  rcx
    jmp  .l
.end:
    mov  byte [rdx], 0
    ret

; fallback font widths: space 4, everything else 6
LEAF uh_width
    xor  eax, eax
.l: movzx edx, byte [rcx]
    test edx, edx
    jz   .r
    cmp  edx, 12
    jne  .ch
    cmp  byte [rcx+1], 0
    je   .r
    add  rcx, 2
    jmp  .l
.ch:
    add  eax, 6
    cmp  edx, ' '
    jne  .n
    sub  eax, 2
.n: inc  rcx
    jmp  .l
.r: ret

; k = 0 is the oldest line. slot = (head - total + k) mod 100
LEAF uh_chat_line
    mov  eax, [rel con_head]
    sub  eax, [rel con_total]
    add  eax, ecx
    add  eax, CHAT_RING*4               ; keep the dividend positive
    xor  edx, edx
    mov  ecx, CHAT_RING
    div  ecx
    imul edx, edx, CHAT_STRIDE
    lea  rax, [rel con_lines]
    add  rax, rdx
    ret

PROC uh_last_chat
    mov  ebx, ecx
    mov  esi, [rel con_total]
    cmp  ebx, esi
    jle  .ok
    mov  ebx, esi
.ok:
    lea  rdi, [rel uh_chatbuf]
    mov  byte [rdi], 0
    mov  r12d, esi
    sub  r12d, ebx
    xor  r13d, r13d
.lp:
    cmp  r12d, esi
    jge  .done
    test r13d, r13d
    jz   .nosp
    mov  byte [rdi], ' '
    inc  rdi
.nosp:
    mov  ecx, r12d
    call uh_chat_line
    mov  rcx, rax
    mov  rdx, rdi
    call uh_strip
    mov  rcx, rdi
    call uh_strlen
    add  rdi, rax
    inc  r12d
    inc  r13d
    jmp  .lp
.done:
    lea  rax, [rel uh_chatbuf]
ENDP

PROC uh_exe
    call console_execute
ENDP

PROC uh_type
    mov  rbx, rcx
.l: movzx ecx, byte [rbx]
    test ecx, ecx
    jz   .done
    call con_insert
    inc  rbx
    jmp  .l
.done:
ENDP

; one space separated word rsi -> rdi (max 63, quotes dropped), rsi ends up after it.
; not a PROC, clobbers rax rcx
uh_word:
    xor  ecx, ecx
.l: mov  al, [rsi]
    test al, al
    jz   .e
    cmp  al, ' '
    je   .e
    cmp  al, '"'
    je   .skip
    cmp  ecx, 63
    jae  .skip
    mov  [rdi+rcx], al
    inc  ecx
.skip:
    inc  rsi
    jmp  .l
.e: mov  byte [rdi+rcx], 0
    ret

PROC uh_child_mode
    mov  r12, rcx
    mov  r13, rdx
    mov  byte [r12], 0
    mov  byte [r13], 0
    call GetCommandLineA
    mov  rbx, rax
    xor  eax, eax
    test rbx, rbx
    jz   .done
.find:
    mov  rcx, rbx
    lea  rdx, [rel s_child_flag]
    call uh_starts
    test eax, eax
    jnz  .found
    cmp  byte [rbx], 0
    je   .done
    inc  rbx
    jmp  .find
.found:
    lea  rsi, [rbx+8]
    mov  rdi, r12
    call uh_word
.sp:cmp  byte [rsi], ' '
    jne  .arg
    inc  rsi
    jmp  .sp
.arg:
    mov  rdi, r13
    call uh_word
    mov  eax, 1
.done:
ENDP

PROC uh_child_result
    mov  rbx, rcx
    lea  rcx, [rel s_child_pfx]
    call t_print
    mov  rcx, rbx
    call t_print
    call t_newline
    xor  ecx, ecx
    call ExitProcess
ENDP

; -> eax 1 got the CHILD line (text in out), 0 timed out and killed, 2 no CHILD line (out = "crash rc=N")
PROC uh_run_child, 256
    mov  r12, rcx
    mov  r13, rdx
    mov  r14, r8
    mov  r15d, r9d
    mov  byte [r14], 0
    xor  ecx, ecx
    lea  rdx, [rel uh_exe_path]
    mov  r8d, 512
    call GetModuleFileNameA
    lea  rdi, [rel uh_cmdline]
    mov  byte [rdi], '"'
    inc  rdi
    mov  rcx, rdi
    lea  rdx, [rel uh_exe_path]
    call uh_strcpy
    mov  rcx, rdi
    call uh_strlen
    add  rdi, rax
    mov  byte [rdi], '"'
    inc  rdi
    mov  byte [rdi], ' '
    inc  rdi
    mov  rcx, rdi
    lea  rdx, [rel s_child_flag]
    call uh_strcpy
    add  rdi, 8
    mov  rcx, rdi
    mov  rdx, r12
    call uh_strcpy
    mov  rcx, rdi
    call uh_strlen
    add  rdi, rax
    test r13, r13
    jz   .cmd_done
    mov  byte [rdi], ' '
    inc  rdi
    mov  rcx, rdi
    mov  rdx, r13
    call uh_strcpy
.cmd_done:
; inheritable pipe, LOC(0) read / LOC(8) write. SECURITY_ATTRIBUTES at LOC(16)
    mov  dword LOC(16), 24
    mov  qword LOC(24), 0
    mov  dword LOC(32), 1
    lea  rcx, LOC(0)
    lea  rdx, LOC(8)
    lea  r8,  LOC(16)
    mov  r9d, 65536
    call CreatePipe
    test eax, eax
    jz   .crash0
    mov  rcx, LOC(0)                    ; read end stays here, not inherited
    mov  [rel uh_hread], rcx
    mov  edx, 1                         ; HANDLE_FLAG_INHERIT
    xor  r8d, r8d
    call SetHandleInformation
; STARTUPINFOA at LOC(48), PROCESS_INFORMATION at LOC(160)
    lea  rdi, LOC(48)
    xor  eax, eax
    mov  ecx, (SI_SIZE + 24) / 8
    rep  stosq
    mov  dword LOC(48), SI_SIZE
    mov  dword LOC(48+SI_FLAGS), STARTF_USESTDHANDLES
    mov  rax, LOC(8)
    mov  LOC(48+SI_STDOUT), rax
    mov  LOC(48+SI_STDERR), rax
    xor  ecx, ecx
    lea  rdx, [rel uh_cmdline]
    xor  r8d, r8d
    xor  r9d, r9d
    mov  qword [rsp+32], 1              ; bInheritHandles
    mov  qword [rsp+40], 0x08000000     ; CREATE_NO_WINDOW
    mov  qword [rsp+48], 0
    mov  qword [rsp+56], 0
    lea  rax, LOC(48)
    mov  [rsp+64], rax
    lea  rax, LOC(160)
    mov  [rsp+72], rax
    call CreateProcessA
    mov  ebx, eax
    mov  rax, LOC(160+PI_HPROCESS)
    mov  [rel uh_hproc], rax
    mov  rax, LOC(160+PI_HTHREAD)
    mov  [rel uh_hthread], rax
    mov  rcx, LOC(8)
    call CloseHandle
    test ebx, ebx
    jz   .crash_close
; keep draining while we wait, otherwise a chatty child blocks on a full pipe
    xor  esi, esi
    call t_time_ms
    mov  LOC(192), rax
.wait:
    call .drain
    mov  rcx, LOC(160+PI_HPROCESS)
    mov  edx, 20
    call WaitForSingleObject
    test eax, eax
    jz   .exited                        ; WAIT_OBJECT_0
    call t_time_ms
    sub  rax, LOC(192)
    cmp  rax, r15
    jb   .wait
    mov  rcx, LOC(160+PI_HPROCESS)
    mov  edx, 99
    call TerminateProcess
    mov  rcx, LOC(160+PI_HPROCESS)
    mov  edx, 5000
    call WaitForSingleObject
    call .close_all
    xor  eax, eax
    jmp  .done
.exited:
    call .drain
    lea  rdx, LOC(200)
    mov  dword [rdx], 0
    mov  rcx, LOC(160+PI_HPROCESS)
    call GetExitCodeProcess
    call .close_all
    lea  rbx, [rel uh_pipebuf]
    mov  byte [rbx+rsi], 0
.scan:
    mov  rcx, rbx
    lea  rdx, [rel s_child_pfx]
    call uh_starts
    test eax, eax
    jnz  .hit
.skip_line:
    mov  al, [rbx]
    test al, al
    jz   .nohit
    inc  rbx
    cmp  al, 10
    jne  .skip_line
    jmp  .scan
.hit:
    add  rbx, 6
    mov  rdi, r14
    xor  ecx, ecx
.cp:mov  al, [rbx+rcx]
    test al, al
    jz   .cpe
    cmp  al, 13
    je   .cpe
    cmp  al, 10
    je   .cpe
    cmp  ecx, 1000
    jae  .cpe
    mov  [rdi+rcx], al
    inc  ecx
    jmp  .cp
.cpe:
    mov  byte [rdi+rcx], 0
    mov  eax, 1
    jmp  .done
.nohit:
; dump what the child printed so its FAIL lines show up
    lea  rcx, [rel uh_pipebuf]
    call t_print
    mov  rcx, r14
    lea  rdx, [rel s_crash]
    call uh_strcpy
    lea  rcx, [r14+9]
    mov  edx, LOC(200)
    call fmt_u32
    mov  eax, 2
    jmp  .done
.crash_close:
    mov  rcx, LOC(0)
    call CloseHandle
.crash0:
    mov  rcx, r14
    lea  rdx, [rel s_crash]
    call uh_strcpy
    mov  byte [r14+9], '?'
    mov  byte [r14+10], 0
    mov  eax, 2
    jmp  .done

; pull whatever the pipe has into uh_pipebuf, esi = fill level
.drain:
    sub  rsp, 56                        ; ret addr + 56: rsp 16-aligned again
.dr_lp:
    mov  dword [rsp+48], 0
    mov  rcx, [rel uh_hread]            ; not LOC(0): LOC is rsp based and we moved rsp
    xor  edx, edx
    xor  r8d, r8d
    xor  r9d, r9d
    lea  rax, [rsp+48]
    mov  [rsp+32], rax
    mov  qword [rsp+40], 0
    call PeekNamedPipe
    test eax, eax
    jz   .dr_end
    mov  eax, [rsp+48]
    test eax, eax
    jz   .dr_end
    mov  r8d, 8190
    sub  r8d, esi
    jle  .dr_discard
    cmp  r8d, eax
    jbe  .dr_rd
    mov  r8d, eax
.dr_rd:
    mov  rcx, [rel uh_hread]
    lea  rdx, [rel uh_pipebuf]
    add  rdx, rsi
    lea  r9,  [rsp+48]
    mov  qword [rsp+32], 0
    call ReadFile
    test eax, eax
    jz   .dr_end
    add  esi, [rsp+48]
    jmp  .dr_lp
.dr_discard:                            ; buffer full, toss the rest
    mov  r8d, eax
    cmp  r8d, 256
    jbe  .dr_d2
    mov  r8d, 256
.dr_d2:
    mov  rcx, [rel uh_hread]
    lea  rdx, [rel uh_tmp]
    lea  r9,  [rsp+48]
    mov  qword [rsp+32], 0
    call ReadFile
    test eax, eax
    jnz  .dr_lp
.dr_end:
    add  rsp, 56
    ret
