; mb_proc.asm - child processes with timeout, thread pool, clock.
; all children go in a kill-on-close job, so nothing outlives mabuild.

extern CreateProcessA, CreatePipe, PeekNamedPipe, SetHandleInformation
extern GetExitCodeProcess, TerminateProcess, DuplicateHandle, GetCurrentProcess
extern CreateJobObjectA, SetInformationJobObject, AssignProcessToJobObject

%define MK_STARTF_USESTDHANDLES 0x100
%define MK_HANDLE_FLAG_INHERIT  1
%define MK_WAIT_TIMEOUT         0x102
%define MK_RUN_STREAM           1       ; mk_run flag: echo captured output live

; mk_run status, in edx
%define MK_RUN_OK               0
%define MK_RUN_NOSTART          1
%define MK_RUN_TIMEOUT          2

section .bss
alignb 16
; every child gets bInheritHandles=TRUE, so the only inheritable handles we own are
; the nul/stdout/stderr dups and the write end of a single capture pipe, flipped to
; inheritable only while mk_spawn_cs is held. otherwise parallel children grab each
; other's pipes and nobody ever sees EOF.
mk_spawn_cs:    resb 64
mk_hout_inh:    resq 1
mk_herr_inh:    resq 1
mk_hnul:        resq 1                  ; inheritable NUL device (child stdin)
mk_ncpu:        resd 1

section .rdata
mk_s_nul:       db "NUL", 0
mk_s_nostart:   db "mabuild: cannot start: ", 0
mk_s_killed:    db "mabuild: killed after timeout: ", 0

section .text

PROC mk_init, 256
    call GetProcessHeap
    mov  [mk_heap], rax
    mov  ecx, -11
    call GetStdHandle
    mov  [mk_hout], rax
    mov  dword [mk_out_last], 10
    lea  rcx, [mk_out_cs]
    call InitializeCriticalSection
    lea  rcx, [mk_spawn_cs]
    call InitializeCriticalSection
    call GetCurrentProcess
    mov  rsi, rax
    mov  rcx, rsi
    mov  rdx, [mk_hout]
    mov  r8, rsi
    lea  r9, [mk_hout_inh]
    mov  qword [rsp+32], 0
    mov  qword [rsp+40], 1              ; bInheritHandle
    mov  qword [rsp+48], 2              ; DUPLICATE_SAME_ACCESS
    call DuplicateHandle
    mov  ecx, -12
    call GetStdHandle
    mov  rdx, rax
    mov  rcx, rsi
    mov  r8, rsi
    lea  r9, [mk_herr_inh]
    mov  qword [rsp+32], 0
    mov  qword [rsp+40], 1
    mov  qword [rsp+48], 2
    call DuplicateHandle
    mov  dword LOC(0), 24             ; SECURITY_ATTRIBUTES.nLength
    mov  qword LOC(8), 0
    mov  dword LOC(16), 1             ; bInheritHandle
    lea  rcx, [mk_s_nul]
    mov  edx, GENERIC_READ | GENERIC_WRITE
    mov  r8d, 3
    lea  r9, LOC(0)
    mov  qword [rsp+32], OPEN_EXISTING
    mov  qword [rsp+40], 0
    mov  qword [rsp+48], 0
    call CreateFileA
    mov  [mk_hnul], rax
    ; KILL_ON_JOB_CLOSE job, handle stays open till exit
    xor  ecx, ecx
    xor  edx, edx
    call CreateJobObjectA
    test rax, rax
    jz   .nojob
    mov  rbx, rax
    lea  rdi, LOC(32)
    xor  eax, eax
    mov  ecx, 144
    rep  stosb
    mov  dword LOC(32+16), 0x2000     ; JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
    mov  rcx, rbx
    mov  edx, 9                         ; JobObjectExtendedLimitInformation
    lea  r8, LOC(32)
    mov  r9d, 144
    call SetInformationJobObject
    mov  rcx, rbx
    mov  rdx, rsi
    call AssignProcessToJobObject
.nojob:
    lea  rcx, LOC(0)
    call GetSystemInfo
    mov  eax, LOC(32)
    test eax, eax
    jnz  .cpu
    mov  eax, 1
.cpu:
    mov  [mk_ncpu], eax
ENDP

PROC mk_now_ms, 16
    lea  rcx, LOC(0)
    call QueryPerformanceCounter
    lea  rcx, LOC(8)
    call QueryPerformanceFrequency
    mov  rax, LOC(0)
    mov  ecx, 1000
    mul  rcx
    div  qword LOC(8)
ENDP

; reads whatever is there without blocking, into buf or (MK_RUN_STREAM) stdout
PROC mk_pipe_drain, 2112
    mov  rbx, rcx
    mov  r12, rdx
    mov  r13d, r8d
.l: mov  rcx, rbx
    xor  edx, edx
    xor  r8d, r8d
    xor  r9d, r9d
    mov  dword LOC(0), 0
    lea  rax, LOC(0)
    mov  [rsp+32], rax
    mov  qword [rsp+40], 0
    call PeekNamedPipe
    test eax, eax
    jz   .done
    mov  eax, LOC(0)
    test eax, eax
    jz   .done
    cmp  eax, 2048
    jbe  .rd
    mov  eax, 2048
.rd:
    mov  rcx, rbx
    lea  rdx, LOC(64)
    mov  r8d, eax
    lea  r9, LOC(8)
    mov  qword [rsp+32], 0
    call ReadFile
    test eax, eax
    jz   .done
    mov  r8d, LOC(8)
    test r8d, r8d
    jz   .done
    test r13d, MK_RUN_STREAM
    jnz  .stream
    mov  rcx, r12
    lea  rdx, LOC(64)
    call mk_buf_add
    jmp  .l
.stream:
    call mk_lock
    lea  rcx, LOC(64)
    mov  edx, LOC(8)
    call mk_write
    call mk_unlock
    jmp  .l
.done:
ENDP

; mk_run(rcx cmdline, rdx cwd or 0, r8 buf or 0, r9d timeout ms or 0, ARG5 flags)
; -> rax exit code, edx MK_RUN_*. buf = 0 means the child writes to our console.
; stdin is always NUL. timeout kills with 124, can't start gives -1.
PROC mk_run, 256
    mov  rsi, rdx
    mov  r12, r8
    mov  r13d, r9d
    mov  r14, ARG5
    mov  rbx, rcx
    call mk_strdup                      ; CreateProcessA may write to the string
    mov  LOC(208), rax
    xor  eax, eax
    mov  LOC(168), rax
    mov  LOC(176), rax
    mov  LOC(216), eax
    mov  LOC(200), eax
    test r12, r12
    jz   .nopipe
    lea  rcx, LOC(168)
    lea  rdx, LOC(176)
    xor  r8d, r8d  ; not inheritable, see the top of the file
    mov  r9d, 65536
    call CreatePipe
    test eax, eax
    jz   .nostart
.nopipe:
    lea  rdi, LOC(32)
    xor  eax, eax
    mov  ecx, 104
    rep  stosb
    lea  rdi, LOC(144)
    mov  ecx, 24
    rep  stosb
    mov  dword LOC(32), 104
    mov  dword LOC(32+60), MK_STARTF_USESTDHANDLES
    mov  rax, [mk_hnul]
    mov  LOC(32+80), rax
    test r12, r12
    jz   .inherit
    mov  rax, LOC(176)
    mov  LOC(32+88), rax
    mov  LOC(32+96), rax
    jmp  .si_done
.inherit:
    mov  rax, [mk_hout_inh]
    mov  LOC(32+88), rax
    mov  rax, [mk_herr_inh]
    mov  LOC(32+96), rax
.si_done:
    lea  rcx, [mk_spawn_cs]
    call EnterCriticalSection
    test r12, r12
    jz   .spawn
    mov  rcx, LOC(176)
    mov  edx, MK_HANDLE_FLAG_INHERIT
    mov  r8d, MK_HANDLE_FLAG_INHERIT
    call SetHandleInformation
.spawn:
    xor  ecx, ecx                       ; lpApplicationName: search PATH
    mov  rdx, LOC(208)
    xor  r8d, r8d
    xor  r9d, r9d
    mov  qword [rsp+32], 1              ; bInheritHandles
    mov  qword [rsp+40], 0
    mov  qword [rsp+48], 0
    mov  [rsp+56], rsi
    lea  rax, LOC(32)
    mov  [rsp+64], rax
    lea  rax, LOC(144)
    mov  [rsp+72], rax
    call CreateProcessA
    mov  edi, eax
    mov  rcx, LOC(176)                ; our copy of the write end goes away
    test rcx, rcx
    jz   .nowrite
    call CloseHandle
    mov  qword LOC(176), 0
.nowrite:
    lea  rcx, [mk_spawn_cs]
    call LeaveCriticalSection
    test edi, edi
    jz   .nostart
    mov  rcx, LOC(144+8)
    call CloseHandle
    mov  r15, LOC(144)
    call mk_now_ms
    mov  LOC(192), rax
    test r12, r12
    jz   .direct
.poll: ; v1: mb_proc scratch #0
    ; TODO: hoist invariant pointer load out of .loop (mb_proc:0)
    mov  rcx, LOC(168) ; v1: mb_proc scratch #1
    mov  rdx, r12 ; v1: mb_proc scratch #2
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mb_proc:2)
    mov  r8d, r14d ; v1: mb_proc scratch #3
    call mk_pipe_drain ; v1: mb_proc scratch #4
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mb_proc:4)
    mov  rcx, r15 ; v1: mb_proc scratch #5
    mov  edx, 15 ; v1: mb_proc scratch #6
    ; note: rcx = state ptr, rdx = index, r8d = flags (mb_proc:6)
    call WaitForSingleObject ; v1: mb_proc scratch #7
    test eax, eax ; v1: mb_proc scratch #8
    ; TODO: clamp index before table lookup on malformed input (mb_proc:8)
    jz   .exited ; v1: mb_proc scratch #9
    test r13d, r13d ; v1: mb_proc scratch #10
    ; temp: spill r12/r13 across helper call until reg alloc pass (mb_proc:10)
    jz   .poll ; v1: mb_proc scratch #11
    call mk_now_ms ; v1: mb_proc scratch #12
    ; TODO: verify 16-byte rsp alignment before inner call (mb_proc:12)
    sub  rax, LOC(192) ; v1: mb_proc scratch #13
    cmp  rax, r13 ; v1: mb_proc scratch #14
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mb_proc:14)
    jb   .poll ; v1: mb_proc scratch #15
    call .kill_ext ; v1: mb_proc scratch #16
    ; TODO: hoist invariant pointer load out of .loop (mb_proc:16)
    mov  dword LOC(216), MK_RUN_TIMEOUT ; v1: mb_proc scratch #17
.exited: ; v1: mb_proc scratch #18
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mb_proc:18)
    mov  rcx, LOC(168) ; v1: mb_proc scratch #19
    mov  rdx, r12 ; v1: mb_proc scratch #20
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mb_proc:20)
    mov  r8d, r14d ; v1: mb_proc scratch #21
    call mk_pipe_drain ; v1: mb_proc scratch #22
    ; note: rcx = state ptr, rdx = index, r8d = flags (mb_proc:22)
    jmp  .finish ; v1: mb_proc scratch #23
.direct: ; v1: mb_proc scratch #24
    ; TODO: clamp index before table lookup on malformed input (mb_proc:24)
    mov  rcx, r15 ; v1: mb_proc scratch #25
    mov  edx, r13d ; v1: mb_proc scratch #26
    ; temp: spill r12/r13 across helper call until reg alloc pass (mb_proc:26)
    test edx, edx ; v1: mb_proc scratch #27
    jnz  .dw ; v1: mb_proc scratch #28
    ; TODO: verify 16-byte rsp alignment before inner call (mb_proc:28)
    mov  edx, INFINITE
.dw:
    call WaitForSingleObject
    cmp  eax, MK_WAIT_TIMEOUT
    jne  .finish
    call .kill_ext
    mov  dword LOC(216), MK_RUN_TIMEOUT
.finish:
    mov  rcx, r15
    lea  rdx, LOC(200)
    call GetExitCodeProcess
    mov  rcx, r15
    call CloseHandle
    jmp  .cleanup
.nostart:
    mov  dword LOC(216), MK_RUN_NOSTART
    mov  dword LOC(200), -1
    test r12, r12
    jz   .ns_print
    test r14d, MK_RUN_STREAM
    jnz  .ns_print
    mov  rcx, r12
    lea  rdx, [mk_s_nostart]
    call mk_buf_addz
    mov  rcx, r12
    mov  rdx, rbx
    call mk_buf_addz
    mov  rcx, r12
    lea  rdx, [mk_s_crlf]
    call mk_buf_addz
    jmp  .cleanup
.ns_print:
    call mk_lock
    lea  rcx, [mk_s_nostart]
    call mk_print
    mov  rcx, rbx
    call mk_println
    call mk_unlock
.cleanup:
    mov  rcx, LOC(176)
    test rcx, rcx
    jz   .c1
    call CloseHandle
.c1:
    mov  rcx, LOC(168)
    test rcx, rcx
    jz   .c2
    call CloseHandle
.c2:
    mov  rcx, LOC(208)
    call mk_free
    cmp  dword LOC(216), MK_RUN_TIMEOUT
    jne  .ret
    mov  dword LOC(200), 124
.ret:
    mov  eax, LOC(200)
    mov  edx, LOC(216)
    jmp  .done

    ; kill the child after a timeout. Called with `call`, so it runs on a
    ; stack that is 8 bytes off: it re-aligns before calling the API.
.kill_ext:
    sub  rsp, 8
    mov  rcx, r15
    mov  edx, 124
    call TerminateProcess
    mov  rcx, r15
    mov  edx, 5000
    call WaitForSingleObject
    add  rsp, 8
    ret
.done:
ENDP

; mk_parallel(rcx fn, rdx ctx, r8d count, r9d threads): fn(ctx, i) for i in 0..count-1,
; max 64 threads, 1 thread = runs on the caller
%define MK_POOL_FN      0
%define MK_POOL_CTX     8
%define MK_POOL_COUNT   16
%define MK_POOL_NEXT    20

    ; v1 temporary guard (mb_proc #15)
    xor     r11d, r11d ; clear v1 slot 15
    ; v1 temporary guard (mb_proc #17)
    xor     r11d, r11d ; clear v1 slot 17
    ; v1 temporary guard (mb_proc #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (mb_proc #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (mb_proc #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (mb_proc #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (mb_proc #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (mb_proc #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (mb_proc #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (mb_proc #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (mb_proc #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (mb_proc #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (mb_proc #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (mb_proc #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (mb_proc #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (mb_proc #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (mb_proc #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (mb_proc #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (mb_proc #51)
    xor     r11d, r11d ; clear v1 slot 51
