%define IMPL_PLATFORM
%include "common.inc"

extern CreateIcon, SetCapture, ReleaseCapture, GetFileType, SetProcessDPIAware
extern util_vformat

global platform_early_init
global platform_wndproc
global platform_last_shot

%macro FUNC 1-2 0
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

; timer/log get set up on first use, whoever gets there first
%macro ENSURE_INIT 0
    cmp  dword [rel s_init_state], 2
    je   %%ok
    call platform_early_init
%%ok:
%endmacro

; stuff win32.inc doesn't have
%define WM_MOVE             0x0003
%define WM_ERASEBKGND       0x0014
%define WM_GETMINMAXINFO    0x0024
%define WM_SYSCHAR          0x0106
%define WM_SYSCOMMAND       0x0112
%define SC_KEYMENU          0xF100
%define SC_SCREENSAVE       0xF140
%define SC_MONITORPOWER     0xF170
%define SIZE_MINIMIZED      1
%define MOUSE_MOVE_ABSOLUTE 1
%define MOUSE_VIRTUAL_DESKTOP 2
%define SM_CXVIRTUALSCREEN  78
%define SM_CYVIRTUALSCREEN  79
%define MONITOR_DEFAULTTONEAREST 2
%define STD_OUTPUT_HANDLE   -11
%define FILE_TYPE_UNKNOWN   0
%define FILE_SHARE_DELETE   4
%define MOVEFILE_WRITE_THROUGH 8
%define ERROR_ALREADY_EXISTS 183
%define VK_RSHIFT_SCAN      0x36
%define LOG_MAX_TEXT        1024

section .rdata
s_class_name:   db "MineAssemblyWindow", 0
s_title:        db "MineAssembly", 0
s_log_name:     db "mineassembly.log", 0
s_tmp_ext:      db ".tmp", 0
s_log_prefix:   db "[%4u.%03u] ", 0
s_crlf:         db 13, 10, 0
s_fatal_fmt:    db "FATAL: %s", 0
s_fatal_title:  db "MineAssembly - fatal error", 0
s_err_class:    db "platform: RegisterClassEx failed (error %u)", 0
s_err_window:   db "platform: CreateWindowEx failed (error %u)", 0
s_err_pf:       db "platform: no suitable pixel format (error %u)", 0
s_err_ctx:      db "platform: could not create/activate the OpenGL context (error %u)", 0
s_err_gl:       db "platform: OpenGL 2.0 is required but not available", 0
s_err_raw:      db "platform: raw mouse input unavailable, mouse look disabled", 0
s_init_ok:      db "platform: window %dx%d, pixel format %d, %d logical CPUs", 0
s_fs_on:        db "platform: borderless fullscreen %dx%d", 0
s_fs_off:       db "platform: windowed mode", 0
s_shot_dir:     db "screenshots", 0
s_shot_fmt:     db "screenshots\shot_%d.bmp", 0
s_shot_ok:      db "Screenshot saved: %s (%dx%d)", 0
s_shot_fail:    db "Screenshot FAILED: %s", 0

section .bss
alignb 16
s_init_state:   resd 1                  ; 0 no, 1 in progress, 2 done
s_quit:         resd 1
s_fullscreen:   resd 1
s_wheel_accum:  resd 1
s_abs_valid:    resd 1
s_abs_x:        resd 1
s_abs_y:        resd 1
s_shot_next:    resd 1
alignb 8
s_qpf:          resq 1
s_qpc_base:     resq 1
s_log_file:     resq 1
s_stdout:       resq 1
s_icon:         resq 1
s_saved_style:  resq 1
s_saved_rect:   resd 4
alignb 16
s_log_cs:       resb 64                 ; CRITICAL_SECTION is 40, rounded up
platform_last_shot: resb 272
alignb 16
s_icon_pixels:  resb 32*32*4
s_icon_mask:    resb 32*4

section .text

; any thread, any number of times. cmpxchg 0->1 winner inits, the rest spin till 2
PROC platform_early_init, 0
    xor  eax, eax
    mov  ecx, 1
    lock cmpxchg [rel s_init_state], ecx
    jz   .do_init
.wait:
    cmp  dword [rel s_init_state], 2
    je   .ret
    pause
    jmp  .wait
.do_init:
    lea  rcx, [rel s_qpf]
    call QueryPerformanceFrequency
    lea  rcx, [rel s_qpc_base]
    call QueryPerformanceCounter
    lea  rcx, [rel s_log_cs]
    call InitializeCriticalSection
    ; fresh log every run, share_read so you can tail it while playing
    lea  rcx, [rel s_log_name]
    mov  edx, GENERIC_WRITE
    mov  r8d, FILE_SHARE_READ
    xor  r9d, r9d
    mov  qword [rsp+32], CREATE_ALWAYS
    mov  qword [rsp+40], FILE_ATTRIBUTE_NORMAL
    mov  qword [rsp+48], 0
    call CreateFileA
    cmp  rax, INVALID_HANDLE_VALUE
    jne  .log_ok
    xor  eax, eax
.log_ok:
    mov  [rel s_log_file], rax
    ; stdout redirected to a pipe/file -> mirror the log there
    mov  ecx, STD_OUTPUT_HANDLE
    call GetStdHandle
    mov  rbx, rax
    cmp  rax, INVALID_HANDLE_VALUE
    je   .no_out
    test rax, rax
    jz   .no_out
    mov  rcx, rax
    call GetFileType
    cmp  eax, FILE_TYPE_UNKNOWN
    je   .no_out
    mov  [rel s_stdout], rbx
.no_out:
    mov  dword [rel s_init_state], 2
.ret:
    ENDP

; time/mem/file stuff below is fine from worker threads

PROC time_seconds, 16
    ENSURE_INIT
    lea  rcx, LOC(0)
    call QueryPerformanceCounter
    mov  rax, LOC(0)
    sub  rax, [rel s_qpc_base]
    cvtsi2sd xmm0, rax
    cvtsi2sd xmm1, qword [rel s_qpf]
    divsd xmm0, xmm1
    ENDP

PROC time_ms, 16
    ENSURE_INIT
    lea  rcx, LOC(0)
    call QueryPerformanceCounter
    mov  rax, LOC(0)
    sub  rax, [rel s_qpc_base]
    mov  ecx, 1000
    mul  rcx
    div  qword [rel s_qpf]
    ENDP

PROC sleep_ms, 0
    call Sleep
    ENDP

PROC mem_alloc, 0
    mov  rbx, rcx
    call GetProcessHeap
    mov  rcx, rax
    mov  edx, HEAP_ZERO_MEMORY
    mov  r8, rbx
    call HeapAlloc
    ENDP

PROC mem_free, 0
    test rcx, rcx
    jz   .ret
    mov  rbx, rcx
    call GetProcessHeap
    mov  rcx, rax
    xor  edx, edx
    mov  r8, rbx
    call HeapFree
.ret:
    ENDP

PROC mem_realloc, 0
    test rcx, rcx
    jnz  .re
    mov  rcx, rdx
    call mem_alloc
    jmp  .ret
.re:
    mov  rbx, rcx
    mov  rsi, rdx
    call GetProcessHeap
    mov  rcx, rax
    mov  edx, HEAP_ZERO_MEMORY
    mov  r8, rbx
    mov  r9, rsi
    call HeapReAlloc
.ret:
    ENDP

PROC mem_valloc, 0
    mov  rdx, rcx
    xor  ecx, ecx
    mov  r8d, MEM_COMMIT | MEM_RESERVE
    mov  r9d, PAGE_READWRITE
    call VirtualAlloc
    ENDP

PROC mem_vfree, 0
    test rcx, rcx
    jz   .ret
    xor  edx, edx
    mov  r8d, MEM_RELEASE
    call VirtualFree
.ret:
    ENDP

PROC file_read_all, 32
    mov  rsi, rdx
    xor  edi, edi
    test rsi, rsi
    jz   .open
    mov  qword [rsi], 0
.open:
    ; SHARE_DELETE so a file_write_all on another thread can still rename
    ; its .tmp over this one. we just keep reading the old data
    mov  edx, GENERIC_READ
    mov  r8d, FILE_SHARE_READ | FILE_SHARE_DELETE
    xor  r9d, r9d
    mov  qword [rsp+32], OPEN_EXISTING
    mov  qword [rsp+40], FILE_ATTRIBUTE_NORMAL
    mov  qword [rsp+48], 0
    call CreateFileA
    cmp  rax, INVALID_HANDLE_VALUE
    je   .ret
    mov  rbx, rax
    mov  rcx, rbx
    lea  rdx, LOC(0)
    call GetFileSizeEx
    test eax, eax
    jz   .close
    mov  r12, LOC(0)
    mov  rax, 0x7FFFFFFF                ; > 2GB? no thanks
    cmp  r12, rax
    ja   .close
    lea  rcx, [r12+1]
    call mem_alloc
    test rax, rax
    jz   .close
    mov  rdi, rax
    xor  r13d, r13d
.read:
    cmp  r13, r12
    jae  .done
    mov  rcx, rbx
    lea  rdx, [rdi+r13]
    mov  r8, r12
    sub  r8, r13
    lea  r9, LOC(8)
    mov  qword [rsp+32], 0
    call ReadFile
    test eax, eax
    jz   .error
    mov  eax, LOC(8)
    test eax, eax
    jz   .error                         ; got shorter while we read it
    add  r13, rax
    jmp  .read
.error:
    mov  rcx, rdi
    call mem_free
    xor  edi, edi
    jmp  .close
.done:
    mov  byte [rdi+r12], 0
    test rsi, rsi
    jz   .close
    mov  [rsi], r12
.close:
    mov  rcx, rbx
    call CloseHandle
.ret:
    mov  rax, rdi
    ENDP

; write path.tmp then rename over it, so a crash can't leave half a save
PROC file_write_all, 576
    mov  rsi, rcx
    mov  rdi, rdx
    mov  r12, r8
    lea  rcx, LOC(16)
    mov  rdx, rsi
    mov  r8d, 540
    call str_ncopy
    lea  rcx, LOC(16)
    lea  rdx, [rel s_tmp_ext]
    call str_cat
    lea  rcx, LOC(16)
    mov  edx, GENERIC_WRITE
    xor  r8d, r8d
    xor  r9d, r9d
    mov  qword [rsp+32], CREATE_ALWAYS
    mov  qword [rsp+40], FILE_ATTRIBUTE_NORMAL
    mov  qword [rsp+48], 0
    call CreateFileA
    cmp  rax, INVALID_HANDLE_VALUE
    je   .fail
    mov  rbx, rax
    xor  r13d, r13d
    mov  r14d, 1
.write:
    cmp  r13, r12
    jae  .closef
    mov  r8, r12
    sub  r8, r13
    mov  eax, 0x40000000                ; WriteFile takes a dword, chunk at 1GB
    cmp  r8, rax
    cmova r8, rax
    mov  rcx, rbx
    lea  rdx, [rdi+r13]
    lea  r9, LOC(0)
    mov  dword LOC(0), 0
    mov  qword [rsp+32], 0
    call WriteFile
    test eax, eax
    jz   .wfail
    mov  eax, LOC(0)
    test eax, eax
    jz   .wfail
    add  r13, rax
    jmp  .write
.wfail:
    xor  r14d, r14d
.closef:
    mov  rcx, rbx
    call CloseHandle
    test r14d, r14d
    jz   .del
    lea  rcx, LOC(16)
    mov  rdx, rsi
    mov  r8d, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH
    call MoveFileExA
    test eax, eax
    jnz  .ok
.del:
    lea  rcx, LOC(16)
    call DeleteFileA
.fail:
    xor  eax, eax
    jmp  .ret
.ok:
    mov  eax, 1
.ret:
    ENDP

PROC file_exists, 0
    call GetFileAttributesA
    cmp  eax, INVALID_FILE_ATTRIBUTES
    setne al
    movzx eax, al
    ENDP

PROC file_delete, 0
    call DeleteFileA
    test eax, eax
    setnz al
    movzx eax, al
    ENDP

PROC dir_create, 560
    mov  rdx, rcx
    lea  rcx, LOC(0)
    mov  r8d, 540
    call str_ncopy
    lea  rbx, LOC(0)
    cmp  byte [rbx], 0                  ; scan starts at 1, so "" has to bail here
    je   .no
    mov  esi, 1                         ; leading '\' isn't a dir
.scan:
    movzx eax, byte [rbx+rsi]
    test eax, eax
    jz   .last
    cmp  al, '\'
    je   .sep
    cmp  al, '/'
    jne  .next
.sep:
    cmp  byte [rbx+rsi-1], ':'          ; don't try to mkdir "C:\"
    je   .next
    mov  edi, eax
    mov  byte [rbx+rsi], 0
    mov  rcx, rbx
    xor  edx, edx
    call CreateDirectoryA               ; already exists = fine
    mov  [rbx+rsi], dil
.next:
    inc  esi
    jmp  .scan
.last:
    mov  rcx, rbx
    xor  edx, edx
    call CreateDirectoryA
    mov  rcx, rbx
    call GetFileAttributesA
    cmp  eax, INVALID_FILE_ATTRIBUTES
    je   .no
    test eax, FILE_ATTRIBUTE_DIRECTORY
    jz   .no
    mov  eax, 1
    jmp  .ret
.no:
    xor  eax, eax
.ret:
    ENDP

PROC thread_create, 0
    mov  r8, rcx
    mov  r9, rdx
    xor  ecx, ecx
    xor  edx, edx
    mov  qword [rsp+32], 0
    mov  qword [rsp+40], 0
    call CreateThread
    ENDP

PROC cpu_count, 64
    lea  rcx, LOC(0)
    call GetSystemInfo
    mov  eax, LOC(32)                   ; dwNumberOfProcessors
    test eax, eax
    jnz  .ret
    mov  eax, 1
.ret:
    ENDP

; "[sec.ms] text" -> file, stdout, debugger
PROC log_write, 1120
    test rcx, rcx
    jz   .ret
    mov  rsi, rcx
    ENSURE_INIT
    call time_ms
    xor  edx, edx
    mov  ecx, 1000
    div  rcx
    mov  r9, rdx
    mov  r8, rax
    lea  rcx, LOC(0)
    lea  rdx, [rel s_log_prefix]
    call str_format
    lea  rdi, LOC(0)
    add  rdi, rax
    mov  ecx, LOG_MAX_TEXT
.copy:
    mov  al, [rsi]
    test al, al
    jz   .eol
    mov  [rdi], al
    inc  rsi
    inc  rdi
    dec  ecx
    jnz  .copy
.eol:
    mov  word [rdi], 0x0A0D
    mov  byte [rdi+2], 0
    lea  r12, [rdi+2]
    lea  rax, LOC(0)
    sub  r12, rax
    lea  rcx, [rel s_log_cs]
    call EnterCriticalSection
    mov  rcx, [rel s_log_file]
    test rcx, rcx
    jz   .no_file
    lea  rdx, LOC(0)
    mov  r8d, r12d
    lea  r9, LOC(1100)
    mov  qword [rsp+32], 0
    call WriteFile
.no_file:
    mov  rcx, [rel s_stdout]
    test rcx, rcx
    jz   .no_out
    lea  rdx, LOC(0)
    mov  r8d, r12d
    lea  r9, LOC(1100)
    mov  qword [rsp+32], 0
    call WriteFile
.no_out:
    lea  rcx, [rel s_log_cs]
    call LeaveCriticalSection
    lea  rcx, LOC(0)
    call OutputDebugStringA
.ret:
    ENDP

PROC log_printf, 1040
    mov  [rbp+24], rdx                  ; spill into home area = flat arg array
    mov  [rbp+32], r8
    mov  [rbp+40], r9
    mov  rdx, rcx
    lea  rcx, LOC(0)
    lea  r8, [rbp+24]
    mov  r9d, 1024
    call util_vformat
    lea  rcx, LOC(0)
    call log_write
    ENDP

PROC fatal_error, 0
    mov  rbx, rcx
    lea  rcx, [rel s_fatal_fmt]
    mov  rdx, rbx
    call log_printf
    xor  ecx, ecx
    call ClipCursor
.show:
    mov  ecx, 1
    call ShowCursor
    test eax, eax
    js   .show
    cmp  dword [rel g_run_mode], 0      ; a dialog would hang selftest/bench forever
    jne  .exit
    mov  rcx, [rel g_hwnd]
    mov  rdx, rbx
    lea  r8, [rel s_fatal_title]
    mov  r9d, MB_OK | MB_ICONERROR
    call MessageBoxA
.exit:
    mov  ecx, 1
    call ExitProcess
    ENDP

; icon: 32x32 grass block, 2:1 iso
;   top   : |2x+1-32| + 2*|2y+1-16| <= 32   (diamond around 16,8)
;   left  : x < 16,  16+x <= 2y < 48+x
;   right : x >= 16, 48-x <= 2y < 80-x
FUNC build_icon, 0
    lea  rdi, [rel s_icon_pixels]
    lea  rsi, [rel s_icon_mask]
    xor  r12d, r12d
.row:
    xor  r13d, r13d
.col:
    lea  eax, [r13*2+1-32]
    cdq
    xor  eax, edx
    sub  eax, edx
    lea  ecx, [r12*2+1-16]
    mov  r8d, ecx
    sar  r8d, 31
    xor  ecx, r8d
    sub  ecx, r8d
    lea  eax, [rax+rcx*2]
    cmp  eax, 32
    jbe  .top
    lea  eax, [r12*2]
    cmp  r13d, 16
    jae  .right
    lea  ecx, [r13+16]                  ; left face
    cmp  eax, ecx
    jl   .empty
    lea  edx, [r13+48]
    cmp  eax, edx
    jge  .empty
    sub  eax, ecx                       ; 2 * dist from the top edge
    mov  ebx, 0xFF4F3726                ; dirt, darker side
    cmp  eax, 6
    jge  .paint
    mov  ebx, 0xFF3E6722                ; 3px of grass edge
    jmp  .paint
.right:
    mov  ecx, 48
    sub  ecx, r13d
    cmp  eax, ecx
    jl   .empty
    lea  edx, [rcx+32]
    cmp  eax, edx
    jge  .empty
    sub  eax, ecx
    mov  ebx, 0xFF674831
    cmp  eax, 6
    jge  .paint
    mov  ebx, 0xFF51872D
    jmp  .paint
.top:
    mov  ebx, 0xFF5F9F35                ; top, BGRA byte order
.paint:
    ; +-16 noise on all 3 channels, saturating so nothing wraps
    imul eax, r13d, 73856093
    imul ecx, r12d, 19349663
    xor  eax, ecx
    imul eax, eax, 0x2C1B3C6D
    shr  eax, 27
    movd xmm0, ebx
    sub  eax, 16
    jl   .darker
    imul eax, eax, 0x010101
    movd xmm1, eax
    paddusb xmm0, xmm1
    jmp  .store
.darker:
    neg  eax
    imul eax, eax, 0x010101
    movd xmm1, eax
