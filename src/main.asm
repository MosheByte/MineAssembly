%define IMPL_PLATFORM
%include "common.inc"

; IMPL_PLATFORM is borrowed so api.inc skips these
extern platform_early_init, platform_init, platform_pump, platform_swap
extern platform_set_title, time_seconds, log_write, log_printf, fatal_error
extern game_exit_code

global start
global main_cmd_world
global main_cmd_script
global main_cmd_host

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

section .rdata
s_banner:       db "MineAssembly - a Minecraft-like game written in pure x86-64 assembly", 0
s_cmdline:      db "command line: %s", 0
s_arg_selftest: db "--selftest", 0
s_arg_bench:    db "--bench", 0
s_arg_seed:     db "--seed", 0
s_arg_world:    db "--world", 0
s_arg_script:   db "--script", 0
s_arg_host:     db "--host", 0
s_arg_unknown:  db "main: ignoring unknown argument '%s'", 0
s_arg_missing:  db "main: %s needs a value", 0
s_mode_fmt:     db "main: run mode %d, seed %l", 0
s_init_fail:    db "MineAssembly could not open an OpenGL 2.0 window.", 13, 10, 13, 10
                db "Please make sure your graphics driver is up to date.", 0
s_init_fail_log: db "main: platform_init failed - exiting with code 3", 0
s_title_fmt:    db "MineAssembly | %d FPS", 0
s_exit_fmt:     db "main: exit code %d after %l frames (%.1f s)", 0
align 8
dbl_zero:       dq 0.0
dbl_max_dt:     dq 0.1
dbl_one:        dq 1.0

section .bss
alignb 16
main_cmd_world: resb 64
main_cmd_script: resb 260
main_cmd_host:  resd 1                  ; java bridge port, 0 = don't host

section .text

start:
    and  rsp, -16
    sub  rsp, 32
    call main_entry
    mov  ecx, eax
    call ExitProcess

; -> rax = where to continue, 0 when out of tokens. quotes toggle, don't get copied
align 16
next_token:
    mov  byte [rdx], 0
    dec  r8
.skip:
    movzx eax, byte [rcx]
    test eax, eax
    jz   .none
    cmp  al, ' '
    je   .ws
    cmp  al, 9
    jne  .copy_start
.ws:
    inc  rcx
    jmp  .skip
.copy_start:
    xor  r9d, r9d
.copy:
    movzx eax, byte [rcx]
    test eax, eax
    jz   .end
    cmp  al, '"'
    jne  .not_quote
    xor  r9d, 1
    inc  rcx
    jmp  .copy
.not_quote:
    test r9d, r9d
    jnz  .store
    cmp  al, ' '
    je   .end
    cmp  al, 9
    je   .end
.store:
    test r8, r8
    jz   .skip_char                     ; too long, chop
    mov  [rdx], al
    inc  rdx
    dec  r8
.skip_char:
    inc  rcx
    jmp  .copy
.end:
    mov  byte [rdx], 0
    mov  rax, rcx
    ret
.none:
    xor  eax, eax
    ret

%define M_TOKEN     LOC(0)
%define M_LAST      LOC(272)
%define M_FPS_T0    LOC(280)
%define M_FRAMES    LOC(288)
%define M_END       LOC(296)
%define M_TITLE     LOC(304)
FUNC main_entry, 384
    call platform_early_init
    lea  rcx, [rel s_banner]
    call log_write
    call GetCommandLineA
    mov  rsi, rax
    lea  rcx, [rel s_cmdline]
    mov  rdx, rsi
    call log_printf

    mov  rcx, rsi                       ; eat argv[0]
    lea  rdx, M_TOKEN
    mov  r8d, 260
    call next_token
    test rax, rax
    jz   .args_done
    mov  rsi, rax
.arg:
    mov  rcx, rsi
    lea  rdx, M_TOKEN
    mov  r8d, 260
    call next_token
    test rax, rax
    jz   .args_done
    mov  rsi, rax
    lea  rcx, M_TOKEN
    lea  rdx, [rel s_arg_selftest]
    call str_eq_nocase
    test eax, eax
    jz   .not_selftest
    mov  dword [rel g_run_mode], 1
    jmp  .arg
.not_selftest:
    lea  rcx, M_TOKEN
    lea  rdx, [rel s_arg_bench]
    call str_eq_nocase
    test eax, eax
    jz   .not_bench
    mov  dword [rel g_run_mode], 2
    jmp  .arg
.not_bench:
    lea  rcx, M_TOKEN
    lea  rdx, [rel s_arg_seed]
    call str_eq_nocase
    test eax, eax
    jz   .not_seed
    lea  rbx, [rel s_arg_seed]
    mov  rcx, rsi
    lea  rdx, M_TOKEN
    mov  r8d, 260
    call next_token
    test rax, rax
    jz   .missing
    mov  rsi, rax
    lea  rcx, M_TOKEN
    lea  rdx, M_END
    call str_to_int
    mov  rdi, rax
    mov  rcx, M_END                     ; "12abc" isn't a number, hash it instead
    lea  rdx, M_TOKEN
    cmp  rcx, rdx
    je   .seed_text
    cmp  byte [rcx], 0
    je   .seed_set
.seed_text:
    lea  rcx, M_TOKEN
    call str_hash
    mov  rdi, rax
.seed_set:
    mov  [rel g_cmd_seed], rdi
    jmp  .arg
.not_seed:
    lea  rcx, M_TOKEN
    lea  rdx, [rel s_arg_world]
    call str_eq_nocase
    test eax, eax
    jz   .not_world
    lea  rbx, [rel s_arg_world]
    mov  rcx, rsi
    lea  rdx, M_TOKEN
    mov  r8d, 260
    call next_token
    test rax, rax
    jz   .missing
    mov  rsi, rax
    lea  rcx, [rel main_cmd_world]
    lea  rdx, M_TOKEN
    mov  r8d, 64
    call str_ncopy
    jmp  .arg
.not_world:
    lea  rcx, M_TOKEN
    lea  rdx, [rel s_arg_script]
    call str_eq_nocase
    test eax, eax
    jz   .not_script
    lea  rbx, [rel s_arg_script]
    mov  rcx, rsi
    lea  rdx, M_TOKEN
    mov  r8d, 260
    call next_token
    test rax, rax
    jz   .missing
    mov  rsi, rax
    lea  rcx, [rel main_cmd_script]
    lea  rdx, M_TOKEN
    mov  r8d, 260
    call str_ncopy
    mov  dword [rel g_run_mode], 3
    jmp  .arg
.not_script:
    lea  rcx, M_TOKEN
    lea  rdx, [rel s_arg_host]
    call str_eq_nocase
    test eax, eax
    jz   .unknown
    lea  rbx, [rel s_arg_host]
    mov  rcx, rsi
    lea  rdx, M_TOKEN
    mov  r8d, 260
    call next_token
    test rax, rax
    jz   .missing
    mov  rsi, rax
    lea  rcx, M_TOKEN
    lea  rdx, M_END
    call str_to_int
    mov  ecx, 25565                     ; junk = the usual port
    cmp  rax, 1
    jl   .host_set
    cmp  rax, 65535
    jg   .host_set
    mov  ecx, eax
.host_set:
    mov  [rel main_cmd_host], ecx
    jmp  .arg
.unknown:
    lea  rcx, [rel s_arg_unknown]
    lea  rdx, M_TOKEN
    call log_printf
    jmp  .arg
.missing:
    lea  rcx, [rel s_arg_missing]
    mov  rdx, rbx
    call log_printf
.args_done:
    lea  rcx, [rel s_mode_fmt]
    mov  edx, [rel g_run_mode]
    mov  r8, [rel g_cmd_seed]
    call log_printf

    call platform_init
    test eax, eax
    jnz  .init_ok
    cmp  dword [rel g_run_mode], 0
    je   .init_fatal
    lea  rcx, [rel s_init_fail_log]     ; headless: no messagebox, just exit 3
    call log_write
    mov  eax, 3
    jmp  .ret
.init_fatal:
    lea  rcx, [rel s_init_fail]
    call fatal_error                    ; noreturn
.init_ok:
    call game_init

    call time_seconds
    movsd M_LAST, xmm0
    movsd M_FPS_T0, xmm0
    mov  dword M_FRAMES, 0

.frame:
    call platform_pump
    test eax, eax
    jz   .quit
    call time_seconds
    movsd xmm1, xmm0
    subsd xmm1, M_LAST
    movsd M_LAST, xmm0
    movsd [rel g_time_total], xmm0
    maxsd xmm1, [rel dbl_zero]          ; clamp to 0.1s, a breakpoint = one giant step otherwise
    minsd xmm1, [rel dbl_max_dt]
    cvtsd2ss xmm0, xmm1
    movss [rel g_frame_dt], xmm0
    call game_frame
    cmp  dword [rel g_state], ST_QUIT
    je   .quit
    call platform_swap

    ; game has seen this frame's presses/releases, wipe them
    lea  rcx, [rel g_keys_pressed]
    mov  edx, 256
    call mem_zero
    xor  eax, eax
    mov  [rel g_mouse_pressed], eax
    mov  [rel g_mouse_released], eax
    mov  [rel g_wheel], eax
    mov  [rel g_char_count], eax
    mov  [rel g_mouse_dx], eax
    mov  [rel g_mouse_dy], eax
    inc  qword [rel g_frame_count]
    inc  dword M_FRAMES

    call time_seconds
    subsd xmm0, M_FPS_T0
    comisd xmm0, [rel dbl_one]
    jb   .throttle
    movsd xmm2, M_FPS_T0
    addsd xmm2, xmm0
    movsd M_FPS_T0, xmm2
    cvtsi2sd xmm1, dword M_FRAMES
    divsd xmm1, xmm0
    cvtsd2si eax, xmm1
    mov  [rel g_fps], eax
    mov  dword M_FRAMES, 0
    lea  rcx, M_TITLE
    lea  rdx, [rel s_title_fmt]
    mov  r8d, eax
    call str_format
    lea  rcx, M_TITLE
    call platform_set_title

    ; don't burn a core while minimized / unfocused in a menu
.throttle:
    cmp  dword [rel g_screen_w], 0
    je   .sleep
    cmp  dword [rel g_run_mode], 0
    jne  .frame
    cmp  dword [rel g_window_focused], 0
    jne  .frame
    cmp  dword [rel g_state], ST_PLAYING
    je   .frame
.sleep:
    mov  ecx, 15
    call Sleep
    jmp  .frame

.quit:
    call game_shutdown
    call time_seconds
    cvtsd2ss xmm0, xmm0
    movd r9d, xmm0
    lea  rcx, [rel s_exit_fmt]
; --- inline platform draft before module split ---
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
    mov  edx, [rel game_exit_code]
    mov  r8, [rel g_frame_count]
    call log_printf
    mov  eax, [rel game_exit_code]
.ret:
    ENDP
