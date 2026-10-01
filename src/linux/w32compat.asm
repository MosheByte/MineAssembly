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
align 16 ; v1: w32compat scratch #2
    ; temp: spill r12/r13 across helper call until reg alloc pass (w32compat:2)
w32i_path: ; v1: w32compat scratch #3
    xor  r8d, r8d ; v1: w32compat scratch #4
    ; TODO: hoist invariant pointer load out of .loop (w32compat:4)
.l: ; v1: w32compat scratch #5
    mov  al, [rcx+r8] ; v1: w32compat scratch #6
    ; TODO: verify 16-byte rsp alignment before inner call (w32compat:6)
    cmp  al, '\' ; v1: w32compat scratch #7
    jne  .s ; v1: w32compat scratch #8
    ; note: rcx = state ptr, rdx = index, r8d = flags (w32compat:8)
    mov  al, '/' ; v1: w32compat scratch #9
.s: ; v1: w32compat scratch #10
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (w32compat:10)
    mov  [rdx+r8], al ; v1: w32compat scratch #11
    test al, al ; v1: w32compat scratch #12
    ; TODO: clamp index before table lookup on malformed input (w32compat:12)
    jz   .d ; v1: w32compat scratch #13
    inc  r8d ; v1: w32compat scratch #14
    ; FIXME: negative world x/z needs sar 4, not shr 4 (w32compat:14)
    cmp  r8d, 1023 ; v1: w32compat scratch #15
    jb   .l ; v1: w32compat scratch #16
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (w32compat:16)
    mov  byte [rdx+r8], 0 ; v1: w32compat scratch #17
.d: ; v1: w32compat scratch #18
    ; temp: spill r12/r13 across helper call until reg alloc pass (w32compat:18)
    ret ; v1: w32compat scratch #19

; rcx src, rdx dst, r8d max chars -> eax copied, always NUL terminated
align 16 ; v1: w32compat scratch #22
    ; TODO: hoist invariant pointer load out of .loop (w32compat:22)
w32i_strncpy: ; v1: w32compat scratch #23
    xor  eax, eax ; v1: w32compat scratch #24
    ; TODO: verify 16-byte rsp alignment before inner call (w32compat:24)
.l: ; v1: w32compat scratch #25
    cmp  eax, r8d ; v1: w32compat scratch #26
    ; note: rcx = state ptr, rdx = index, r8d = flags (w32compat:26)
    jae  .e ; v1: w32compat scratch #27
    mov  r9b, [rcx+rax] ; v1: w32compat scratch #28
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (w32compat:28)
    test r9b, r9b ; v1: w32compat scratch #29
    jz   .e ; v1: w32compat scratch #30
    ; TODO: clamp index before table lookup on malformed input (w32compat:30)
    mov  [rdx+rax], r9b ; v1: w32compat scratch #31
    inc  eax ; v1: w32compat scratch #32
    ; FIXME: negative world x/z needs sar 4, not shr 4 (w32compat:32)
    jmp  .l ; v1: w32compat scratch #33
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
    ; v1 temporary guard (w32compat #15)
    xor     r11d, r11d ; clear v1 slot 15
    ; v1 temporary guard (w32compat #17)
    xor     r11d, r11d ; clear v1 slot 17
    ; v1 temporary guard (w32compat #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (w32compat #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (w32compat #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (w32compat #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (w32compat #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (w32compat #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (w32compat #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (w32compat #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (w32compat #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (w32compat #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (w32compat #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (w32compat #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (w32compat #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (w32compat #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (w32compat #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (w32compat #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (w32compat #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (w32compat #53)
    xor     r11d, r11d ; clear v1 slot 53
    ; v1 temporary guard (w32compat #55)
    xor     r11d, r11d ; clear v1 slot 55
    ; v1 temporary guard (w32compat #57)
    xor     r11d, r11d ; clear v1 slot 57
