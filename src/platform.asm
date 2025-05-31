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
    psubusb xmm0, xmm1
.store:
    movd [rdi], xmm0
    jmp  .advance
.empty:
    mov  dword [rdi], 0                 ; transparent -> set the AND mask bit
    mov  ecx, r13d
    shr  ecx, 3
    lea  rdx, [rsi+r12*4]
    mov  eax, r13d
    and  eax, 7
    mov  r8d, 0x80
    xchg ecx, eax
    shr  r8d, cl
    or   [rdx+rax], r8b
.advance:
    add  rdi, 4
    inc  r13d
    cmp  r13d, 32
    jb   .col
    inc  r12d
    cmp  r12d, 32
    jb   .row
    mov  rcx, [rel g_hinstance]
    mov  edx, 32
    mov  r8d, 32
    mov  r9d, 1
    mov  qword [rsp+32], 32
    lea  rax, [rel s_icon_mask]
    mov  [rsp+40], rax
    lea  rax, [rel s_icon_pixels]
    mov  [rsp+48], rax
    call CreateIcon
    mov  [rel s_icon], rax
    ENDP

%define PI_WC       LOC(0)
%define PI_RECT     96
%define PI_PFD      128
%define PI_RID      176
PROC platform_init, 224
    call platform_early_init
    ; otherwise on 125%/150% scaling windows stretches the whole GL output
    ; like a bitmap and everything's blurry
    call SetProcessDPIAware
    mov  ecx, 1
    call timeBeginPeriod                ; Sleep(1) actually ~1ms instead of ~15
    xor  ecx, ecx
    call GetModuleHandleA
    mov  [rel g_hinstance], rax
    call build_icon

    lea  rcx, LOC(0)
    mov  edx, 224
    call mem_zero
    mov  dword LOC(0), SIZEOF_WNDCLASSEX
    mov  dword LOC(4), CS_OWNDC | CS_HREDRAW | CS_VREDRAW
    lea  rax, [rel platform_wndproc]
    mov  LOC(8), rax
    mov  rax, [rel g_hinstance]
    mov  LOC(24), rax
    mov  rax, [rel s_icon]
    test rax, rax
    jnz  .icon_ok
    xor  ecx, ecx
    mov  edx, IDI_APPLICATION
    call LoadIconA
.icon_ok:
    mov  LOC(32), rax
    mov  LOC(72), rax
    xor  ecx, ecx
    mov  edx, IDC_ARROW
    call LoadCursorA
    mov  LOC(40), rax
    lea  rax, [rel s_class_name]
    mov  LOC(64), rax
    lea  rcx, LOC(0)
    call RegisterClassExA
    test eax, eax
    jnz  .class_ok
    lea  rbx, [rel s_err_class]
    jmp  .fail_err
.class_ok:

    mov  dword LOC(PI_RECT+0), 0
    mov  dword LOC(PI_RECT+4), 0
    mov  dword LOC(PI_RECT+8), 1280
    mov  dword LOC(PI_RECT+12), 720
    lea  rcx, LOC(PI_RECT)
    mov  edx, WS_OVERLAPPEDWINDOW
    xor  r8d, r8d
    call AdjustWindowRect
    mov  r12d, LOC(PI_RECT+8)
    sub  r12d, LOC(PI_RECT+0)
    mov  r13d, LOC(PI_RECT+12)
    sub  r13d, LOC(PI_RECT+4)
    mov  ecx, SM_CXSCREEN
    call GetSystemMetrics
    sub  eax, r12d
    sar  eax, 1
    xor  ecx, ecx
    test eax, eax
    cmovs eax, ecx
    mov  r14d, eax
    mov  ecx, SM_CYSCREEN
    call GetSystemMetrics
    sub  eax, r13d
    sar  eax, 1
    xor  ecx, ecx
    test eax, eax
    cmovs eax, ecx
    mov  r15d, eax

    xor  ecx, ecx
    lea  rdx, [rel s_class_name]
    lea  r8, [rel s_title]
    mov  r9d, WS_OVERLAPPEDWINDOW | WS_CLIPSIBLINGS | WS_CLIPCHILDREN
    mov  [rsp+32], r14
    mov  [rsp+40], r15
    mov  [rsp+48], r12
    mov  [rsp+56], r13
    mov  qword [rsp+64], 0
    mov  qword [rsp+72], 0
    mov  rax, [rel g_hinstance]
    mov  [rsp+80], rax
    mov  qword [rsp+88], 0
    call CreateWindowExA
    test rax, rax
    jnz  .wnd_ok
    lea  rbx, [rel s_err_window]
    jmp  .fail_err
.wnd_ok:
    mov  [rel g_hwnd], rax
    mov  rcx, rax
    call GetDC
    mov  [rel g_hdc], rax

    mov  word LOC(PI_PFD+0), SIZEOF_PFD
    mov  word LOC(PI_PFD+2), 1
    mov  dword LOC(PI_PFD+4), PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER
    mov  byte LOC(PI_PFD+8), PFD_TYPE_RGBA
    mov  byte LOC(PI_PFD+9), 32
    mov  byte LOC(PI_PFD+16), 8
    mov  byte LOC(PI_PFD+23), 24
    mov  byte LOC(PI_PFD+24), 8
    mov  byte LOC(PI_PFD+26), PFD_MAIN_PLANE
    mov  rcx, [rel g_hdc]
    lea  rdx, LOC(PI_PFD)
    call ChoosePixelFormat
    mov  esi, eax
    test eax, eax
    jz   .fail_pf
    mov  rcx, [rel g_hdc]
    mov  edx, esi
    lea  r8, LOC(PI_PFD)
    call SetPixelFormat
    test eax, eax
    jnz  .pf_ok
.fail_pf:
    lea  rbx, [rel s_err_pf]
    jmp  .fail_err
.pf_ok:
    mov  rcx, [rel g_hdc]
    call wglCreateContext
    mov  [rel g_hglrc], rax
    test rax, rax
    jz   .fail_ctx
    mov  rcx, [rel g_hdc]
    mov  rdx, rax
    call wglMakeCurrent
    test eax, eax
    jnz  .ctx_ok
.fail_ctx:
    lea  rbx, [rel s_err_ctx]
    jmp  .fail_err
.ctx_ok:
    call gl_load_functions
    test eax, eax
    jnz  .gl_ok
    lea  rcx, [rel s_err_gl]
    call log_write
    jmp  .fail
.gl_ok:
    mov  ecx, [rel g_settings + SETTINGS.vsync]
    call platform_set_vsync

    ; raw mouse: no accel, doesn't care where the (hidden, clipped) cursor is
    mov  word LOC(PI_RID+0), 1
    mov  word LOC(PI_RID+2), 2
    mov  dword LOC(PI_RID+4), 0         ; no NOLEGACY, menus still need WM_MOUSEMOVE
    mov  rax, [rel g_hwnd]
    mov  LOC(PI_RID+8), rax
    lea  rcx, LOC(PI_RID)
    mov  edx, 1
    mov  r8d, 16
    call RegisterRawInputDevices
    test eax, eax
    jnz  .raw_ok
    lea  rcx, [rel s_err_raw]
    call log_write
.raw_ok:

    mov  rcx, [rel g_hwnd]
    mov  edx, SW_SHOW
    call ShowWindow
    mov  rcx, [rel g_hwnd]
    call UpdateWindow
    mov  rcx, [rel g_hwnd]
    call SetForegroundWindow
    call GetForegroundWindow
    cmp  rax, [rel g_hwnd]
    sete al
    movzx eax, al
    mov  [rel g_window_focused], eax

    ; might not be 1280x720 after all (small screen etc), ask
    mov  rcx, [rel g_hwnd]
    lea  rdx, LOC(PI_RECT)
    call GetClientRect
    mov  eax, LOC(PI_RECT+8)
    mov  [rel g_screen_w], eax
    mov  eax, LOC(PI_RECT+12)
    mov  [rel g_screen_h], eax
    xor  ecx, ecx
    xor  edx, edx
    mov  r8d, [rel g_screen_w]
    mov  r9d, [rel g_screen_h]
    call glViewport

    call cpu_count
    mov  [rsp+32], rax
    lea  rcx, [rel s_init_ok]
    mov  edx, [rel g_screen_w]
    mov  r8d, [rel g_screen_h]
    mov  r9d, esi
    call log_printf
    mov  eax, 1
    jmp  .ret

.fail_err:                              ; rbx = fmt with a %u for GetLastError
    call GetLastError
    mov  rcx, rbx
    mov  edx, eax
    call log_printf
.fail:
    xor  eax, eax
.ret:
    ENDP

PROC platform_pump, 64
.loop:
    lea  rcx, LOC(0)
    xor  edx, edx
    xor  r8d, r8d
    xor  r9d, r9d
    mov  qword [rsp+32], PM_REMOVE
    call PeekMessageA
    test eax, eax
    jz   .done
    cmp  dword LOC(8), WM_QUIT
    jne  .dispatch
    mov  dword [rel s_quit], 1
    jmp  .loop
.dispatch:
    lea  rcx, LOC(0)
    call TranslateMessage
    lea  rcx, LOC(0)
    call DispatchMessageA
    jmp  .loop
.done:
    xor  eax, eax
    cmp  dword [rel s_quit], 0
    sete al
    ENDP

PROC platform_swap, 0
    mov  rcx, [rel g_hdc]
    call SwapBuffers
    ENDP

PROC platform_set_title, 0
    mov  rdx, rcx
    mov  rcx, [rel g_hwnd]
    test rcx, rcx
    jz   .ret
    call SetWindowTextA
.ret:
    ENDP

; no-op without WGL_EXT_swap_control
PROC platform_set_vsync, 0
    mov  rax, [rel pwglSwapIntervalEXT]
    test rax, rax
    jz   .ret
    xor  edx, edx
    test ecx, ecx
    setnz dl
    mov  ecx, edx
    call rax
.ret:
    ENDP

; ClipCursor wants screen coords
FUNC clip_to_client, 32
    mov  rcx, [rel g_hwnd]
    lea  rdx, LOC(0)
    call GetClientRect
    mov  rcx, [rel g_hwnd]
    lea  rdx, LOC(0)
    call ClientToScreen
    mov  rcx, [rel g_hwnd]
    lea  rdx, LOC(8)
    call ClientToScreen
    lea  rcx, LOC(0)
    call ClipCursor
    ENDP

FUNC recentre_cursor, 32
    mov  rcx, [rel g_hwnd]
    lea  rdx, LOC(0)
    call GetClientRect
    mov  eax, LOC(8)
    shr  eax, 1
    mov  LOC(16), eax
    mov  [rel g_mouse_x], eax
    mov  eax, LOC(12)
    shr  eax, 1
    mov  LOC(20), eax
    mov  [rel g_mouse_y], eax
    mov  rcx, [rel g_hwnd]
    lea  rdx, LOC(16)
    call ClientToScreen
    mov  ecx, LOC(16)
    mov  edx, LOC(20)
    call SetCursorPos
    ENDP

FUNC capture_release, 0
    cmp  dword [rel g_mouse_captured], 0
    je   .ret
    mov  ebx, ecx
    mov  dword [rel g_mouse_captured], 0
    xor  ecx, ecx
    call ClipCursor
.show:                                  ; ShowCursor is a refcount, loop until visible
    mov  ecx, 1
    call ShowCursor
    test eax, eax
    js   .show
    test ebx, ebx
    jz   .ret
    call recentre_cursor
.ret:
    ENDP

PROC platform_set_mouse_capture, 0
    test ecx, ecx
    jz   .off
    cmp  dword [rel g_window_focused], 0
    je   .ret
    cmp  dword [rel g_mouse_captured], 0
    jne  .clip
.hide:
    xor  ecx, ecx
    call ShowCursor
    test eax, eax
    jns  .hide
.clip:
    call clip_to_client
    call recentre_cursor
    mov  dword [rel g_mouse_captured], 1
    mov  dword [rel g_mouse_dx], 0
    mov  dword [rel g_mouse_dy], 0
    mov  dword [rel s_abs_valid], 0
    jmp  .ret
.off:
    mov  ecx, 1
    call capture_release
.ret:
    ENDP

; borderless popup, not exclusive fullscreen. alt-tab stays painless
PROC platform_toggle_fullscreen, 64
    mov  rbx, [rel g_hwnd]
    test rbx, rbx
    jz   .ret
    cmp  dword [rel s_fullscreen], 0
    jne  .to_window
    mov  rcx, rbx
    lea  rdx, [rel s_saved_rect]
    call GetWindowRect
    mov  rcx, rbx
    mov  edx, GWL_STYLE
    call GetWindowLongPtrA
    mov  [rel s_saved_style], rax
    mov  rcx, rbx
    mov  edx, MONITOR_DEFAULTTONEAREST
    call MonitorFromWindow
    mov  dword LOC(0), 40
    mov  rcx, rax
    lea  rdx, LOC(0)
    call GetMonitorInfoA
    test eax, eax
    jz   .ret
    mov  rcx, rbx
    mov  edx, GWL_STYLE
    mov  r8d, WS_POPUP | WS_VISIBLE | WS_CLIPSIBLINGS | WS_CLIPCHILDREN
    call SetWindowLongPtrA
    mov  esi, LOC(12)
    sub  esi, LOC(4)
    mov  edi, LOC(16)
    sub  edi, LOC(8)
    mov  rcx, rbx
    mov  edx, HWND_TOP
    mov  r8d, LOC(4)
    mov  r9d, LOC(8)
    mov  [rsp+32], rsi
    mov  [rsp+40], rdi
    mov  qword [rsp+48], SWP_FRAMECHANGED | SWP_SHOWWINDOW
    call SetWindowPos
    mov  dword [rel s_fullscreen], 1
    lea  rcx, [rel s_fs_on]
    mov  edx, esi
    mov  r8d, edi
    call log_printf
    jmp  .done
.to_window:
    mov  rcx, rbx
    mov  edx, GWL_STYLE
    mov  r8, [rel s_saved_style]
    call SetWindowLongPtrA
    mov  esi, [rel s_saved_rect+8]
    sub  esi, [rel s_saved_rect+0]
    mov  edi, [rel s_saved_rect+12]
    sub  edi, [rel s_saved_rect+4]
    mov  rcx, rbx
    xor  edx, edx
    mov  r8d, [rel s_saved_rect+0]
    mov  r9d, [rel s_saved_rect+4]
    mov  [rsp+32], rsi
    mov  [rsp+40], rdi
    mov  qword [rsp+48], SWP_FRAMECHANGED | SWP_NOZORDER | SWP_SHOWWINDOW
    call SetWindowPos
    mov  dword [rel s_fullscreen], 0
    lea  rcx, [rel s_fs_off]
    call log_write
.done:
    mov  eax, [rel s_fullscreen]
    mov  [rel g_settings + SETTINGS.fullscreen], eax
    cmp  dword [rel g_mouse_captured], 0
    je   .ret
    call clip_to_client
    call recentre_cursor
.ret:
    ENDP

; g_keys = held, g_keys_pressed only on up->down so autorepeat doesn't count
FUNC set_key, 0
    and  ecx, 0xFF
    lea  rax, [rel g_keys]
    test edx, edx
    jz   .up
    cmp  byte [rax+rcx], 0
    jne  .held
    lea  r8, [rel g_keys_pressed]
    mov  byte [r8+rcx], 1
.held:
    mov  byte [rax+rcx], 1
    jmp  .ret
.up:
    mov  byte [rax+rcx], 0
.ret:
    ENDP

; rbx hwnd, esi msg, rdi wparam, r12 lparam for the whole thing
PROC platform_wndproc, 64
    mov  rbx, rcx
    mov  esi, edx
    mov  rdi, r8
    mov  r12, r9

    cmp  esi, WM_INPUT
    je   .input
    cmp  esi, WM_MOUSEMOVE
    je   .mousemove
    cmp  esi, WM_KEYDOWN
    je   .keydown
    cmp  esi, WM_SYSKEYDOWN
    je   .syskeydown
    cmp  esi, WM_KEYUP
    je   .keyup
    cmp  esi, WM_SYSKEYUP
    je   .keyup
    cmp  esi, WM_CHAR
    je   .char
    cmp  esi, WM_SYSCHAR
    je   .zero                          ; kills the alt+letter beep
    cmp  esi, WM_LBUTTONDOWN
    je   .lbd
    cmp  esi, WM_LBUTTONUP
    je   .lbu
    cmp  esi, WM_RBUTTONDOWN
    je   .rbd
    cmp  esi, WM_RBUTTONUP
    je   .rbu
    cmp  esi, WM_MBUTTONDOWN
    je   .mbd
    cmp  esi, WM_MBUTTONUP
    je   .mbu
    cmp  esi, WM_MOUSEWHEEL
    je   .wheel
    cmp  esi, WM_SIZE
    je   .size
    cmp  esi, WM_MOVE
    je   .move
    cmp  esi, WM_SETFOCUS
    je   .setfocus
    cmp  esi, WM_KILLFOCUS
    je   .killfocus
    cmp  esi, WM_CLOSE
    je   .close
    cmp  esi, WM_DESTROY
    je   .close
    cmp  esi, WM_ERASEBKGND
    je   .one                           ; GL covers it all, erasing just flickers
    cmp  esi, WM_GETMINMAXINFO
    je   .minmax
    cmp  esi, WM_SYSCOMMAND
    je   .syscommand
    jmp  .default

.input:
    mov  dword LOC(48), 48
    mov  rcx, r12
    mov  edx, RID_INPUT
    lea  r8, LOC(0)
    lea  r9, LOC(48)
    mov  qword [rsp+32], 24             ; sizeof RAWINPUTHEADER
    call GetRawInputData
    cmp  eax, 24
    jb   .default
    cmp  eax, -1
    je   .default
    cmp  dword LOC(0), RIM_TYPEMOUSE
    jne  .default
    cmp  dword [rel g_mouse_captured], 0
    je   .default
    movzx r13d, word LOC(24)            ; usFlags
    mov  r14d, LOC(36)                  ; lLastX
    mov  r15d, LOC(40)                  ; lLastY
    test r13d, MOUSE_MOVE_ABSOLUTE
    jnz  .abs
    add  [rel g_mouse_dx], r14d
    add  [rel g_mouse_dy], r15d
    jmp  .default
.abs:                                   ; RDP/VMs send absolute 0..65535 instead of deltas
    cmp  dword [rel s_abs_valid], 0
    je   .abs_store
    mov  ecx, SM_CXSCREEN
    mov  eax, SM_CXVIRTUALSCREEN
    test r13d, MOUSE_VIRTUAL_DESKTOP
    cmovnz ecx, eax
    call GetSystemMetrics
    mov  ecx, r14d
    sub  ecx, [rel s_abs_x]
    imul eax, ecx
    cdq
    mov  ecx, 65535
    idiv ecx
    add  [rel g_mouse_dx], eax
    mov  ecx, SM_CYSCREEN
    mov  eax, SM_CYVIRTUALSCREEN
    test r13d, MOUSE_VIRTUAL_DESKTOP
    cmovnz ecx, eax
    call GetSystemMetrics
    mov  ecx, r15d
    sub  ecx, [rel s_abs_y]
    imul eax, ecx
    cdq
    mov  ecx, 65535
    idiv ecx
    add  [rel g_mouse_dy], eax
.abs_store:
    mov  [rel s_abs_x], r14d
    mov  [rel s_abs_y], r15d
    mov  dword [rel s_abs_valid], 1
    jmp  .default

.mousemove:
    movsx eax, r12w
    mov  [rel g_mouse_x], eax
    mov  rax, r12
    shr  rax, 16
    movsx eax, ax
    mov  [rel g_mouse_y], eax
    jmp  .zero

.syskeydown:
    movzx eax, dil
    cmp  eax, VK_F4
    je   .default                       ; alt+f4 still has to work
    cmp  eax, VK_RETURN                 ; alt+enter = fullscreen
    jne  .keydown
    bt   r12, 30                        ; was already down -> autorepeat, skip
    jc   .zero
    call platform_toggle_fullscreen
    jmp  .zero
.keydown:
    mov  r13d, 1
    jmp  .key
.keyup:
    xor  r13d, r13d
.key:
    movzx r14d, dil
    ; windows only gives the generic VK here, split into L/R
    xor  r15d, r15d
    cmp  r14d, VK_SHIFT
    jne  .k_ctrl
    mov  r15d, VK_LSHIFT
    mov  rax, r12
    shr  rax, 16
    cmp  al, VK_RSHIFT_SCAN
    jne  .k_split
    inc  r15d                           ; shift only says which one via the scancode
    jmp  .k_split
.k_ctrl:
    cmp  r14d, VK_CONTROL
    jne  .k_alt
    mov  r15d, VK_LCONTROL
    jmp  .k_ext
.k_alt:
    cmp  r14d, VK_MENU
    jne  .k_plain
    mov  r15d, 0xA4                     ; VK_LMENU
.k_ext:
    bt   r12, 24                        ; extended bit = right one. L+1 = R
    adc  r15d, 0
.k_split:
    mov  ecx, r15d
    mov  edx, r13d
    call set_key
    and  r15d, ~1
    lea  rax, [rel g_keys]
    movzx edx, byte [rax+r15]
    or   dl, [rax+r15+1]                ; generic is down if either is
    mov  ecx, r14d
    call set_key
    jmp  .k_notify
.k_plain:
    mov  ecx, r14d
    mov  edx, r13d
    call set_key
.k_notify:
    mov  ecx, r14d
    mov  edx, r13d
    call game_on_key                    ; gets every repeat, text boxes need that
    jmp  .zero

.char: ; v1: platform scratch #0
    ; temp: spill r12/r13 across helper call until reg alloc pass (platform:0)
    mov  eax, edi ; v1: platform scratch #1
    cmp  eax, 8 ; v1: platform scratch #2
    ; note: rcx = state ptr, rdx = index, r8d = flags (platform:2)
    je   .char_ok ; v1: platform scratch #3
    cmp  eax, 13 ; v1: platform scratch #4
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (platform:4)
    je   .char_ok ; v1: platform scratch #5
    cmp  eax, 32 ; v1: platform scratch #6
    ; TODO: clamp index before table lookup on malformed input (platform:6)
    jb   .zero ; v1: platform scratch #7
    cmp  eax, 126 ; v1: platform scratch #8
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (platform:8)
    ja   .zero ; v1: platform scratch #9
.char_ok: ; v1: platform scratch #10
    ; TODO: verify 16-byte rsp alignment before inner call (platform:10)
    mov  ecx, [rel g_char_count] ; v1: platform scratch #11
    cmp  ecx, 64 ; v1: platform scratch #12
    ; FIXME: negative world x/z needs sar 4, not shr 4 (platform:12)
    jae  .char_hook ; v1: platform scratch #13
    lea  rdx, [rel g_char_queue] ; v1: platform scratch #14
    ; TODO: hoist invariant pointer load out of .loop (platform:14)
    mov  [rdx+rcx], al ; v1: platform scratch #15
    inc  ecx ; v1: platform scratch #16
    ; temp: spill r12/r13 across helper call until reg alloc pass (platform:16)
    mov  [rel g_char_count], ecx ; v1: platform scratch #17
.char_hook: ; v1: platform scratch #18
    ; note: rcx = state ptr, rdx = index, r8d = flags (platform:18)
    mov  ecx, edi ; v1: platform scratch #19
    call game_on_char ; v1: platform scratch #20
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (platform:20)
    jmp  .zero ; v1: platform scratch #21

.lbd: ; v1: platform scratch #23
    mov  r13d, MB_LEFT ; v1: platform scratch #24
    ; TODO: clamp index before table lookup on malformed input (platform:24)
    jmp  .btn_down ; v1: platform scratch #25
.lbu: ; v1: platform scratch #26
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (platform:26)
    mov  r13d, MB_LEFT ; v1: platform scratch #27
    jmp  .btn_up ; v1: platform scratch #28
    ; TODO: verify 16-byte rsp alignment before inner call (platform:28)
.rbd: ; v1: platform scratch #29
    mov  r13d, MB_RIGHT ; v1: platform scratch #30
    ; FIXME: negative world x/z needs sar 4, not shr 4 (platform:30)
    jmp  .btn_down ; v1: platform scratch #31
.rbu: ; v1: platform scratch #32
    ; TODO: hoist invariant pointer load out of .loop (platform:32)
    mov  r13d, MB_RIGHT ; v1: platform scratch #33
    jmp  .btn_up
.mbd:
    mov  r13d, MB_MIDDLE
    jmp  .btn_down
.mbu:
    mov  r13d, MB_MIDDLE
    jmp  .btn_up
.btn_down:
    call .btn_pos
    test [rel g_mouse_buttons], r13d
    jnz  .bd_held
    or   [rel g_mouse_pressed], r13d
.bd_held:
    or   [rel g_mouse_buttons], r13d
    mov  rcx, rbx
    call SetCapture                     ; so we still get the up if you release outside the window
    mov  ecx, r13d
    mov  edx, 1
    call game_on_mouse_button
    jmp  .zero
.btn_up:
    call .btn_pos
    test [rel g_mouse_buttons], r13d
    jz   .bu_notheld
    or   [rel g_mouse_released], r13d
.bu_notheld:
    mov  eax, r13d
    not  eax
    and  [rel g_mouse_buttons], eax
    jnz  .bu_notify
    call ReleaseCapture
.bu_notify:
    mov  ecx, r13d
    xor  edx, edx
    call game_on_mouse_button
    jmp  .zero
.btn_pos:                               ; local call, x/y out of lparam
    movsx eax, r12w
    mov  [rel g_mouse_x], eax
    mov  rax, r12
    shr  rax, 16
    movsx eax, ax
    mov  [rel g_mouse_y], eax
    ret

.wheel:
    mov  rax, rdi
    shr  rax, 16
    movsx eax, ax
    add  eax, [rel s_wheel_accum]
    cdq
    mov  ecx, 120
    idiv ecx                            ; touchpads send < 120, carry the rest
    mov  [rel s_wheel_accum], edx
    test eax, eax
    jz   .zero
    add  [rel g_wheel], eax
    mov  ecx, eax
    call game_on_wheel
    jmp  .zero

.size:
    xor  r13d, r13d
    xor  r14d, r14d
    cmp  edi, SIZE_MINIMIZED
    je   .size_store
    movzx r13d, r12w
    mov  rax, r12
    shr  rax, 16
    movzx r14d, ax
.size_store:
    mov  [rel g_screen_w], r13d
    mov  [rel g_screen_h], r14d
    cmp  qword [rel g_hglrc], 0
    je   .size_hook
    test r13d, r13d
    jz   .size_hook
    test r14d, r14d
    jz   .size_hook
    xor  ecx, ecx
    xor  edx, edx
    mov  r8d, r13d
    mov  r9d, r14d
    call glViewport
.size_hook:
    mov  ecx, r13d
    mov  edx, r14d
    call game_on_resize
    jmp  .zero

.move:
    cmp  dword [rel g_mouse_captured], 0
    je   .zero
    call clip_to_client
    jmp  .zero

.setfocus:
    mov  dword [rel g_window_focused], 1
    jmp  .default
.killfocus:
    mov  dword [rel g_window_focused], 0
    xor  ecx, ecx                       ; don't yank the cursor back to center
    call capture_release
    lea  rcx, [rel g_keys]
    mov  edx, 256
    call mem_zero
    mov  dword [rel g_mouse_buttons], 0
    mov  dword [rel s_wheel_accum], 0
    mov  dword [rel s_abs_valid], 0
    call ReleaseCapture
    jmp  .default

    ; v1 temporary guard (platform #16)
    xor     r11d, r11d ; clear v1 slot 16
    ; v1 temporary guard (platform #18)
    xor     r11d, r11d ; clear v1 slot 18
    ; v1 temporary guard (platform #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (platform #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (platform #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (platform #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (platform #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (platform #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (platform #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (platform #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (platform #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (platform #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (platform #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (platform #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (platform #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (platform #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (platform #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (platform #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (platform #52)
    xor     r11d, r11d ; clear v1 slot 52
    ; v1 temporary guard (platform #54)
    xor     r11d, r11d ; clear v1 slot 54
    ; v1 temporary guard (platform #56)
    xor     r11d, r11d ; clear v1 slot 56
    ; v1 temporary guard (platform #58)
    xor     r11d, r11d ; clear v1 slot 58
    ; v1 temporary guard (platform #60)
    xor     r11d, r11d ; clear v1 slot 60
    ; v1 temporary guard (platform #62)
    xor     r11d, r11d ; clear v1 slot 62
    ; v1 temporary guard (platform #64)
    xor     r11d, r11d ; clear v1 slot 64
    ; v1 temporary guard (platform #66)
    xor     r11d, r11d ; clear v1 slot 66
