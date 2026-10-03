; w32compat.asm - the kernel32 (+ a bit of user32) the shared modules call, on
; top of libc. exact win32 names, ms x64 in and out. PROCX around anything that
; calls sysv code, libc is allowed to eat rsi/rdi/xmm6-15 and our callers park
; stuff there. linux build only.
; last error lives in errno: a libc errno as is, or a raw win32 code | W32E.
%ifdef LINUX
%define WIN32_INC                       ; skip win32.inc, its externs are what we define
%include "common.inc"

extern __errno_location, clock_gettime, nanosleep, sched_yield
extern malloc, calloc, realloc, free, memset
extern mmap, munmap, mprotect, madvise
extern open, close, read, write, lseek, fstat, fsync, stat, unlink, rmdir, mkdir, rename
extern opendir, readdir, closedir, fnmatch
extern localtime_r, gmtime_r, sysconf, sysinfo, setpriority, signal, fflush, _exit
extern pthread_create, pthread_detach
extern pthread_mutex_init, pthread_mutex_destroy, pthread_mutex_lock, pthread_mutex_unlock
extern pthread_mutex_trylock
extern pthread_mutexattr_init, pthread_mutexattr_settype, pthread_mutexattr_destroy
extern pthread_cond_init, pthread_cond_destroy, pthread_cond_wait, pthread_cond_timedwait
extern pthread_cond_broadcast
extern pthread_condattr_init, pthread_condattr_setclock, pthread_condattr_destroy

; libc call: al = 0 for the varargs ones, harmless for the rest
%macro CCALL 1
    xor  eax, eax
    call %1 wrt ..plt
%endmacro

%define W32E            0x10000         ; errno tag: low word is a win32 code
%macro SETERR 1
    CCALL __errno_location
    mov  dword [rax], (%1) | W32E
%endmacro

%define ERROR_FILE_NOT_FOUND    2
%define ERROR_PATH_NOT_FOUND    3
%define ERROR_ACCESS_DENIED     5
%define ERROR_INVALID_HANDLE    6
%define ERROR_NOT_ENOUGH_MEMORY 8
%define ERROR_NO_MORE_FILES     18
%define ERROR_INVALID_PARAMETER 87
%define ERROR_ALREADY_EXISTS    183
%define ERROR_TOO_MANY_POSTS    298

%define WAIT_TIMEOUT    0x102
%define WAIT_FAILED     0xFFFFFFFF
%define INFINITE        0xFFFFFFFF
%define INVALID_FILE_ATTRIBUTES 0xFFFFFFFF
%define HEAP_ZERO_MEMORY 8
%define MEM_COMMIT      0x1000
%define MEM_RESERVE     0x2000
%define MEM_DECOMMIT    0x4000
%define MEM_RELEASE     0x8000

; handles are calloc'd objects, type first so Close/Wait can tell them apart
%define HT_FILE         0x77330001
%define HT_STD          0x77330002      ; stdin/out/err, static, never freed
%define HT_EVENT        0x77330003
%define HT_SEM          0x77330004
%define HT_THRD         0x77330005
%define HT_FIND         0x77330006
%define H_TYPE          0
%define H_REFS          4               ; thread: handle + the thread itself
%define H_FD            8               ; fd, or DIR* for a find
%define H_MTX           16              ; pthread_mutex_t, 40
%define H_COND          56              ; pthread_cond_t, 48
%define H_STATE         104             ; event set / sem count / thread done
%define H_AUX           108             ; event manual reset / sem max
%define H_FN            112
%define H_ARG           120
%define H_EXIT          128
%define H_SIZE          144
%define F_PAT           16              ; find: name pattern
%define F_DIR           272             ; find: dir, no trailing /
%define F_SIZE          1040

%define ST_MODE         24              ; struct stat, x86-64 glibc
%define ST_SIZE         48
%define ST_ATIME        72
%define ST_MTIME        88
%define ST_LEN          144

section .data
align 16
w32_std_in:     dd HT_STD, 1, 0, 0
w32_std_out:    dd HT_STD, 1, 1, 0
w32_std_err:    dd HT_STD, 1, 2, 0
w32_heap:       dq 0

section .rodata
align 8
zero_ts:        dq 0, 0                 ; already-passed deadline = poll
s_proc_cmd:     db "/proc/self/cmdline", 0
s_mb_sep:       db ": ", 0
s_nl:           db 10, 0
; errno -> win32 error, 0 ends it
align 4
w32_errmap:
    dd 1, 5,  2, 2,  5, 1117,  9, 6,  12, 8,  13, 5,  16, 170,  17, 183,  18, 17
    dd 20, 3,  21, 5,  22, 87,  23, 4,  24, 4,  27, 223,  28, 112,  30, 19
    dd 32, 109,  36, 206,  39, 145,  110, 1460
    dd 0, 0

section .bss
alignb 8
global w32_clipboard_hook
w32_clipboard_hook: resq 1              ; platform fills it: () -> rax zstr or 0, ms x64
w32_tid_next:   resd 1
w32_cmd_done:   resd 1
w32_cmd_raw:    resb 8192
w32_cmd_buf:    resb 24640

section .text

; ---- leaf helpers, volatile regs only, no libc ----

; rcx handle -> eax type, 0 for null/-1/pseudo handles
align 16
w32i_type:
    xor  eax, eax
    cmp  rcx, 4096
    jb   .r
    cmp  rcx, -4096
    jae  .r
    mov  eax, [rcx+H_TYPE]
.r:
    ret

; rcx handle -> eax fd, -1 if it isn't a file
align 16
w32i_fd:
    call w32i_type
    cmp  eax, HT_FILE
    je   .ok
    cmp  eax, HT_STD
    je   .ok
    mov  eax, -1
    ret
.ok:
    mov  eax, [rcx+H_FD]
    ret

; rcx win path -> rdx (1024) with / for \. paths are all relative anyway
align 16
w32i_path:
    xor  r8d, r8d
.l:
    mov  al, [rcx+r8]
    cmp  al, '\'
    jne  .s
    mov  al, '/'
.s:
    mov  [rdx+r8], al
    test al, al
    jz   .d
    inc  r8d
    cmp  r8d, 1023
    jb   .l
    mov  byte [rdx+r8], 0
.d:
    ret

; rcx src, rdx dst, r8d max chars -> eax copied, always NUL terminated
align 16
w32i_strncpy:
    xor  eax, eax
.l:
    cmp  eax, r8d
    jae  .e
    mov  r9b, [rcx+rax]
    test r9b, r9b
    jz   .e
    mov  [rdx+rax], r9b
    inc  eax
    jmp  .l
.e:
    mov  byte [rdx+rax], 0
    ret

; rcx stat -> eax FILE_ATTRIBUTE_*
align 16
w32i_attr:
    mov  edx, [rcx+ST_MODE]
    mov  eax, edx
    and  eax, 0xF000
    cmp  eax, 0x4000
    jne  .f
    mov  eax, 0x10                      ; directory
    test edx, 0x80                      ; S_IWUSR
    jnz  .r
    or   eax, 1
    ret
.f:
    mov  eax, 0x80                      ; normal, only valid on its own
    test edx, 0x80
    jnz  .r
    mov  eax, 1                         ; readonly
.r:
    ret

; r8 sec, r9 nsec -> rax FILETIME (100ns since 1601). eats rcx rdx
align 16
w32i_ft:
    mov  rax, r9
    xor  edx, edx
    mov  ecx, 100
    div  rcx
    mov  rcx, rax
    mov  rax, 11644473600
    add  rax, r8
    imul rax, rax, 10000000
    add  rax, rcx
    ret

; rcx stat -> rdx+4.. the times + size part shared by WIN32_FIND_DATA and
; WIN32_FILE_ATTRIBUTE_DATA. no birth time in stat, creation = mtime
align 16
w32i_filltimes:
    mov  r10, rdx
    mov  r11, rcx
    mov  r8, [r11+ST_MTIME]
    mov  r9, [r11+ST_MTIME+8]
    call w32i_ft
    mov  [r10+4], rax
    mov  [r10+20], rax
    mov  r8, [r11+ST_ATIME]
    mov  r9, [r11+ST_ATIME+8]
    call w32i_ft
    mov  [r10+12], rax
    mov  rax, [r11+ST_SIZE]
    mov  [r10+32], eax                  ; low
    shr  rax, 32
    mov  [r10+28], eax                  ; high
    ret

; rcx struct tm, rdx SYSTEMTIME, r8d ms
align 16
w32i_tm2st:
    mov  eax, [rcx+20]
    add  eax, 1900
    mov  [rdx], ax
    mov  eax, [rcx+16]
    inc  eax
    mov  [rdx+2], ax
    mov  eax, [rcx+24]
    mov  [rdx+4], ax
    mov  eax, [rcx+12]
    mov  [rdx+6], ax
    mov  eax, [rcx+8]
    mov  [rdx+8], ax
    mov  eax, [rcx+4]
    mov  [rdx+10], ax
    mov  eax, [rcx]
    cmp  eax, 59                        ; leap second, windows has none
    jbe  .s
    mov  eax, 59
.s:
    mov  [rdx+12], ax
    mov  [rdx+14], r8w
    ret

; ecx PAGE_* -> eax PROT_*
align 16
w32i_prot:
    and  ecx, 0xFF                      ; guard/nocache bits don't matter
    mov  eax, 3
    cmp  ecx, 0x04
    je   .r
    cmp  ecx, 0x08
    je   .r
    xor  eax, eax
    cmp  ecx, 0x01
    je   .r
    mov  eax, 1
    cmp  ecx, 0x02
    je   .r
    mov  eax, 4
    cmp  ecx, 0x10
    je   .r
    mov  eax, 5
    cmp  ecx, 0x20
    je   .r
    mov  eax, 7
.r:
    ret

; ---- sysv helpers for the sync objects ----

; edi type, esi state, edx aux -> rax obj (1 ref) or 0
align 16
w32i_new_sync:
    push rbx
    push r12
    push r13
    push r14
    sub  rsp, 24
    mov  r12d, edi
    mov  r13d, esi
    mov  r14d, edx
    mov  edi, 1
    mov  esi, H_SIZE
    call calloc wrt ..plt
    test rax, rax
    jz   .out
    mov  rbx, rax
    mov  [rbx+H_TYPE], r12d
    mov  dword [rbx+H_REFS], 1
    mov  [rbx+H_STATE], r13d
    mov  [rbx+H_AUX], r14d
    lea  rdi, [rbx+H_MTX]
    xor  esi, esi
    call pthread_mutex_init wrt ..plt
    ; monotonic, so a clock change can't stretch a timed wait
    mov  rdi, rsp
    call pthread_condattr_init wrt ..plt
    mov  rdi, rsp
    mov  esi, 1
    call pthread_condattr_setclock wrt ..plt
    lea  rdi, [rbx+H_COND]
    mov  rsi, rsp
    call pthread_cond_init wrt ..plt
    mov  rdi, rsp
    call pthread_condattr_destroy wrt ..plt
    mov  rax, rbx
.out:
    add  rsp, 24
    pop  r14
    pop  r13
    pop  r12
    pop  rbx
    ret

; rdi obj. last ref frees it
align 16
w32i_unref:
    lock dec dword [rdi+H_REFS]
    jnz  .r
    push rbx
    mov  rbx, rdi
    mov  dword [rbx+H_TYPE], 0
    lea  rdi, [rbx+H_MTX]
    call pthread_mutex_destroy wrt ..plt
    lea  rdi, [rbx+H_COND]
    call pthread_cond_destroy wrt ..plt
    mov  rdi, rbx
    call free wrt ..plt
    pop  rbx
.r:
    ret

; rdi timespec out, esi ms -> now(monotonic) + ms
align 16
w32i_deadline:
    push rbx
    push r12
    sub  rsp, 8
    mov  rbx, rdi
    mov  r12d, esi
    mov  edi, 1
    mov  rsi, rbx
    call clock_gettime wrt ..plt
    mov  eax, r12d
    xor  edx, edx
    mov  ecx, 1000
    div  ecx
    add  [rbx], rax
    imul edx, edx, 1000000
    add  rdx, [rbx+8]
    cmp  rdx, 1000000000
    jb   .n
    sub  rdx, 1000000000
    inc  qword [rbx]
.n:
    mov  [rbx+8], rdx
    add  rsp, 8
    pop  r12
    pop  rbx
    ret

; rdi obj, rsi deadline or 0 = forever -> eax 0 got it (consumed), WAIT_TIMEOUT
align 16
w32i_wait:
    push rbx
    push r12
    push r13
    mov  rbx, rdi
    mov  r12, rsi
    lea  rdi, [rbx+H_MTX]
    call pthread_mutex_lock wrt ..plt
    xor  r13d, r13d                     ; 1 once the deadline has passed
.check:
    mov  eax, [rbx+H_TYPE]
    cmp  eax, HT_SEM
    je   .sem
    cmp  dword [rbx+H_STATE], 0
    je   .block
    cmp  eax, HT_EVENT
    jne  .got
    cmp  dword [rbx+H_AUX], 0
    jne  .got
    mov  dword [rbx+H_STATE], 0         ; auto reset
    jmp  .got
.sem:
    cmp  dword [rbx+H_STATE], 0
    je   .block
    dec  dword [rbx+H_STATE]
    jmp  .got
.block:
    test r13d, r13d
    jnz  .timeout
    test r12, r12
    jnz  .timed
    lea  rdi, [rbx+H_COND]
    lea  rsi, [rbx+H_MTX]
    call pthread_cond_wait wrt ..plt
    jmp  .check
.timed:
    lea  rdi, [rbx+H_COND]
    lea  rsi, [rbx+H_MTX]
    mov  rdx, r12
    call pthread_cond_timedwait wrt ..plt
    cmp  eax, 110                       ; ETIMEDOUT, one last look then give up
    jne  .check
    mov  r13d, 1
    jmp  .check
.timeout:
    mov  r13d, WAIT_TIMEOUT
    jmp  .out
.got:
    xor  r13d, r13d
.out:
    lea  rdi, [rbx+H_MTX]
    call pthread_mutex_unlock wrt ..plt
    mov  eax, r13d
    pop  r13
    pop  r12
    pop  rbx
    ret

; pthread start: rdi = thread obj. runs the win64 fn with rcx = arg
align 16
w32i_thread_start:
    push rbx
    push rbp
    sub  rsp, 40                        ; shadow + 16 aligned
    mov  rbx, rdi
    mov  rcx, [rbx+H_ARG]
    call [rbx+H_FN]
    mov  [rbx+H_EXIT], eax
    lea  rdi, [rbx+H_MTX]
    call pthread_mutex_lock wrt ..plt
    mov  dword [rbx+H_STATE], 1
    lea  rdi, [rbx+H_COND]
    call pthread_cond_broadcast wrt ..plt
    lea  rdi, [rbx+H_MTX]
    call pthread_mutex_unlock wrt ..plt
    mov  rdi, rbx
    call w32i_unref
    add  rsp, 40
    pop  rbp
    pop  rbx
    xor  eax, eax
    ret

; ---- errors ----

PROCX GetLastError
    CCALL __errno_location
    mov  eax, [rax]
    test eax, W32E
    jz   .map
    and  eax, 0xFFFF
    jmp  .done
.map:
    test eax, eax
    jz   .done
    lea  rdx, [rel w32_errmap]
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
    or   eax, 0x20000000                ; customer bit, unmapped errno underneath
.done:
ENDPX

PROCX SetLastError
    mov  ebx, ecx
    CCALL __errno_location
    test ebx, ebx
    jz   .z
    or   ebx, W32E
.z:
    mov  [rax], ebx
ENDPX

; ---- time ----

LEAF QueryPerformanceFrequency
    mov  qword [rcx], 1000000000        ; ns
    mov  eax, 1
    ret

PROCX QueryPerformanceCounter, 16
    mov  rbx, rcx
    mov  edi, 1                         ; CLOCK_MONOTONIC
    lea  rsi, LOC(0)
    CCALL clock_gettime
    imul rax, LOC(0), 1000000000
    add  rax, LOC(8)
    mov  [rbx], rax
    mov  eax, 1
ENDPX

PROCX GetTickCount64, 16
    mov  edi, 1
    lea  rsi, LOC(0)
    CCALL clock_gettime
    mov  rax, LOC(8)
    xor  edx, edx
    mov  ecx, 1000000
    div  rcx
    imul rcx, LOC(0), 1000
    add  rax, rcx
ENDPX

PROCX GetTickCount
    call GetTickCount64
ENDPX

PROCX Sleep, 16
    test ecx, ecx
    jnz  .ns
    CCALL sched_yield
    jmp  .done
.ns:
    mov  eax, ecx
    xor  edx, edx
    mov  ecx, 1000
    div  ecx
    mov  LOC(0), rax
    imul edx, edx, 1000000
    mov  LOC(8), rdx
.again:
    lea  rdi, LOC(0)
    lea  rsi, LOC(0)                    ; remaining goes back in, EINTR resumes
    CCALL nanosleep
    test eax, eax
    jz   .done
    CCALL __errno_location
    cmp  dword [rax], 4
    je   .again
.done:
ENDPX

; local wall clock
PROCX GetLocalTime, 96
    mov  rbx, rcx
    xor  edi, edi                       ; CLOCK_REALTIME
    lea  rsi, LOC(0)
    CCALL clock_gettime
    lea  rdi, LOC(0)
    lea  rsi, LOC(16)
    CCALL localtime_r
    mov  rax, LOC(8)
    xor  edx, edx
    mov  ecx, 1000000
    div  rcx
    mov  r8d, eax
    lea  rcx, LOC(16)
    mov  rdx, rbx
    call w32i_tm2st
ENDPX
