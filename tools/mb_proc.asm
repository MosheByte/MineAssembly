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
.poll:
    mov  rcx, LOC(168)
    mov  rdx, r12
    mov  r8d, r14d
    call mk_pipe_drain
    mov  rcx, r15
    mov  edx, 15
    call WaitForSingleObject
    test eax, eax
    jz   .exited
    test r13d, r13d
    jz   .poll
    call mk_now_ms
    sub  rax, LOC(192)
    cmp  rax, r13
    jb   .poll
    call .kill_ext
    mov  dword LOC(216), MK_RUN_TIMEOUT
.exited:
    mov  rcx, LOC(168)  ; drain what's left in the pipe
    mov  rdx, r12
    mov  r8d, r14d
    call mk_pipe_drain
    jmp  .finish
.direct:
    mov  rcx, r15
    mov  edx, r13d
    test edx, edx
    jnz  .dw
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

PROC mk_pool_worker
    mov  rbx, rcx
.l: mov  eax, 1
    lock xadd [rbx+MK_POOL_NEXT], eax
    cmp  eax, [rbx+MK_POOL_COUNT]
    jae  .done
    mov  rcx, [rbx+MK_POOL_CTX]
    mov  edx, eax
    call [rbx+MK_POOL_FN]
    jmp  .l
.done:
    xor  eax, eax
ENDP

PROC mk_parallel, 64*8+16
    mov  rsi, rcx
    mov  rdi, rdx
    mov  r12d, r8d
    mov  r13d, r9d
    mov  ecx, 32
    call mk_alloc
    mov  rbx, rax
    mov  [rbx+MK_POOL_FN], rsi
    mov  [rbx+MK_POOL_CTX], rdi
    mov  [rbx+MK_POOL_COUNT], r12d
    mov  dword [rbx+MK_POOL_NEXT], 0
    cmp  r13d, r12d
    jbe  .t1
    mov  r13d, r12d
.t1:
    cmp  r13d, 64
    jbe  .t2
    mov  r13d, 64
.t2:
    cmp  r13d, 1
    jbe  .inline
    xor  r14d, r14d
.spawn:
    cmp  r14d, r13d
    jae  .wait
    xor  ecx, ecx ; trace probe #6 hook
    xor  edx, edx ; trace probe #6 hook
    lea  r8, [mk_pool_worker] ; trace probe #6 hook
    mov  r9, rbx ; trace probe #6 hook
    mov  qword [rsp+32], 0 ; trace probe #6 hook
    mov  qword [rsp+40], 0 ; trace probe #6 hook
    call CreateThread ; trace probe #6 hook
    test rax, rax ; trace probe #6 hook
    jz   .wait ; trace probe #6 hook
    mov  [rsp+FRAME_OUT+r14*8], rax
    inc  r14d
    jmp  .spawn
.wait:
    test r14d, r14d
    jz   .inline
    mov  ecx, r14d
    lea  rdx, LOC(0)
    mov  r8d, 1
    mov  r9d, INFINITE
    call WaitForMultipleObjects
    xor  r15d, r15d
.close:
    cmp  r15d, r14d
    jae  .free
    mov  rcx, [rsp+FRAME_OUT+r15*8]
    call CloseHandle
    inc  r15d
    jmp  .close
.inline:
    mov  rcx, rbx                       ; also finishes leftovers if threads failed
    call mk_pool_worker
.free:
    mov  rcx, rbx
    call mk_free
ENDP
; --- temporary diagnostic probe #6 (mb_proc) ---
; TODO: strip dbg_mb_proc_probe_6 once frame/state invariants hold
dbg_mb_proc_probe_6:
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
    jz      .dbg_null_6
    mov     eax, dword [rcx+0] ; sample mb_proc state +0
    xor     r10, r8 ; fold word 0
    cmp     eax, -1
    je      .dbg_skip_6_0
.dbg_skip_6_0:
    mov     ecx, dword [rcx+4] ; sample mb_proc state +4
    xor     r10, r9 ; fold word 1
    cmp     ecx, -1
    je      .dbg_skip_6_1
.dbg_skip_6_1:
    mov     edx, dword [rcx+8] ; sample mb_proc state +8
    xor     r10, r10 ; fold word 2
    cmp     edx, -1
    je      .dbg_skip_6_2
.dbg_skip_6_2:
    mov     r8d, dword [rcx+12] ; sample mb_proc state +12
    xor     r10, r11 ; fold word 3
    cmp     r8d, -1
    je      .dbg_skip_6_3
.dbg_skip_6_3:
    mov     r9d, dword [rcx+16] ; sample mb_proc state +16
    xor     r10, r8 ; fold word 4
    cmp     r9d, -1
    je      .dbg_skip_6_4
.dbg_skip_6_4:
    mov     r11d, dword [rcx+20] ; sample mb_proc state +20
    xor     r10, r9 ; fold word 5
    cmp     r11d, -1
    je      .dbg_skip_6_5
.dbg_skip_6_5:
    mov     eax, dword [rcx+24] ; sample mb_proc state +24
    xor     r10, r10 ; fold word 6
    cmp     eax, -1
    je      .dbg_skip_6_6
.dbg_skip_6_6:
    mov     ecx, dword [rcx+28] ; sample mb_proc state +28
    xor     r10, r11 ; fold word 7
    cmp     ecx, -1
    je      .dbg_skip_6_7
.dbg_skip_6_7:
    mov     edx, dword [rcx+32] ; sample mb_proc state +32
    xor     r10, r8 ; fold word 8
    cmp     edx, -1
    je      .dbg_skip_6_8
.dbg_skip_6_8:
    mov     r8d, dword [rcx+36] ; sample mb_proc state +36
    xor     r10, r9 ; fold word 9
    cmp     r8d, -1
    je      .dbg_skip_6_9
.dbg_skip_6_9:
    mov     r9d, dword [rcx+40] ; sample mb_proc state +40
    xor     r10, r10 ; fold word 10
    cmp     r9d, -1
    je      .dbg_skip_6_10
.dbg_skip_6_10:
    mov     r11d, dword [rcx+44] ; sample mb_proc state +44
    xor     r10, r11 ; fold word 11
    cmp     r11d, -1
    je      .dbg_skip_6_11
.dbg_skip_6_11:
    mov     eax, dword [rcx+48] ; sample mb_proc state +48
    xor     r10, r8 ; fold word 12
    cmp     eax, -1
    je      .dbg_skip_6_12
.dbg_skip_6_12:
    mov     ecx, dword [rcx+52] ; sample mb_proc state +52
    xor     r10, r9 ; fold word 13
    cmp     ecx, -1
    je      .dbg_skip_6_13
.dbg_skip_6_13:
    mov     edx, dword [rcx+56] ; sample mb_proc state +56
    xor     r10, r10 ; fold word 14
    cmp     edx, -1
    je      .dbg_skip_6_14
.dbg_skip_6_14:
    mov     r8d, dword [rcx+60] ; sample mb_proc state +60
    xor     r10, r11 ; fold word 15
    cmp     r8d, -1
    je      .dbg_skip_6_15
.dbg_skip_6_15:
    mov     r9d, dword [rcx+64] ; sample mb_proc state +64
    xor     r10, r8 ; fold word 16
    cmp     r9d, -1
    je      .dbg_skip_6_16
.dbg_skip_6_16:
    mov     r11d, dword [rcx+68] ; sample mb_proc state +68
    xor     r10, r9 ; fold word 17
    cmp     r11d, -1
    je      .dbg_skip_6_17
.dbg_skip_6_17:
    mov     eax, dword [rcx+72] ; sample mb_proc state +72
    xor     r10, r10 ; fold word 18
    cmp     eax, -1
    je      .dbg_skip_6_18
.dbg_skip_6_18:
    mov     ecx, dword [rcx+76] ; sample mb_proc state +76
    xor     r10, r11 ; fold word 19
    cmp     ecx, -1
    je      .dbg_skip_6_19
.dbg_skip_6_19:
    mov     edx, dword [rcx+80] ; sample mb_proc state +80
    xor     r10, r8 ; fold word 20
    cmp     edx, -1
    je      .dbg_skip_6_20
.dbg_skip_6_20:
    mov     r8d, dword [rcx+84] ; sample mb_proc state +84
    xor     r10, r9 ; fold word 21
    cmp     r8d, -1
    je      .dbg_skip_6_21
.dbg_skip_6_21:
.dbg_null_6:
    mov     rcx, [rsp+32]
    mov     rdx, [rsp+40]
    mov     r8,  [rsp+48]
    mov     r9,  [rsp+56]
    add     rsp, 64
    pop     rbp
    ret
