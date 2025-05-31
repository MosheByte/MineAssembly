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
; --- inline gl draft before module split ---
; wglGetProcAddress loader + GL 2.0 shader compile/link helpers
%define IMPL_GL
%include "common.inc"

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

%macro GLFN 2
    section .bss
    global p%1
    alignb 8
    p%1: resq 1
    section .rdata
    %defstr GLFN_NAME %1
    %%name: db GLFN_NAME, 0
    section .data
    dq %%name, p%1, %2
%endmacro

section .data
align 8
gl_fn_table:
GLFN glGenBuffers, 1
GLFN glDeleteBuffers, 1
GLFN glBindBuffer, 1
GLFN glBufferData, 1
GLFN glBufferSubData, 1
GLFN glCreateShader, 1
GLFN glShaderSource, 1
GLFN glCompileShader, 1
GLFN glGetShaderiv, 1
GLFN glGetShaderInfoLog, 1
GLFN glDeleteShader, 1
GLFN glCreateProgram, 1
GLFN glAttachShader, 1
GLFN glLinkProgram, 1
GLFN glGetProgramiv, 1
GLFN glGetProgramInfoLog, 1
GLFN glDeleteProgram, 1
GLFN glUseProgram, 1
GLFN glGetUniformLocation, 1
GLFN glUniform1f, 1
GLFN glUniform2f, 1
GLFN glUniform3f, 1
GLFN glUniform4f, 1
GLFN glUniform1i, 1
GLFN glUniformMatrix4fv, 1
GLFN glBindAttribLocation, 1
GLFN glVertexAttribPointer, 1
GLFN glEnableVertexAttribArray, 1
GLFN glDisableVertexAttribArray, 1
GLFN glActiveTexture, 1
GLFN wglSwapIntervalEXT, 0              ; vsync, fine if it's missing
section .data
gl_fn_table_end:

section .rdata
s_unknown:      db "?", 0
s_gl_info:      db "OpenGL vendor:   %s", 0
s_gl_info2:     db "OpenGL renderer: %s", 0
s_gl_info3:     db "OpenGL version:  %s", 0
s_gl_missing:   db "OpenGL: required function %s is missing (need OpenGL 2.0)", 0
s_gl_optional:  db "OpenGL: optional function %s not available", 0
s_gl_loaded:    db "OpenGL: %d functions loaded", 0
s_vs:           db "vertex", 0
s_fs:           db "fragment", 0
s_sh_fail:      db "GLSL %s shader failed to compile:", 0
s_link_fail:    db "GLSL program failed to link:", 0
s_err_fmt:      db "GL error 0x%x (%s) at %s", 0
s_e500:         db "GL_INVALID_ENUM", 0
s_e501:         db "GL_INVALID_VALUE", 0
s_e502:         db "GL_INVALID_OPERATION", 0
s_e503:         db "GL_STACK_OVERFLOW", 0
s_e504:         db "GL_STACK_UNDERFLOW", 0
s_e505:         db "GL_OUT_OF_MEMORY", 0
s_e506:         db "GL_INVALID_FRAMEBUFFER_OPERATION", 0
align 8
gl_err_names:   dq s_e500, s_e501, s_e502, s_e503, s_e504, s_e505, s_e506

section .bss
alignb 16
gl_info_log:    resb 4096               ; main thread only

section .text

    global gl_load_functions
    align 16
gl_load_functions:
    push rbp
    mov  rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    sub  rsp, FRAME_OUT
    ; first thing I want to see in a bug report
    mov  ecx, GL_VENDOR
    call glGetString
    lea  rdx, [rel s_unknown]
    test rax, rax
    cmovnz rdx, rax
    lea  rcx, [rel s_gl_info]
    call log_printf
    mov  ecx, GL_RENDERER
    call glGetString
    lea  rdx, [rel s_unknown]
    test rax, rax
    cmovnz rdx, rax
    lea  rcx, [rel s_gl_info2]
    call log_printf
    mov  ecx, GL_VERSION
    call glGetString
    lea  rdx, [rel s_unknown]
    test rax, rax
    cmovnz rdx, rax
    lea  rcx, [rel s_gl_info3]
    call log_printf

    lea  rbx, [rel gl_fn_table]
    lea  r12, [rel gl_fn_table_end]
    xor  r13d, r13d                     ; required + missing
    xor  r14d, r14d
.loop:
    cmp  rbx, r12
    jae  .done
    mov  rcx, [rbx]
    call wglGetProcAddress
    ; drivers return 1/2/3/-1 instead of NULL sometimes. +1 and one unsigned cmp
    lea  rcx, [rax+1]
    cmp  rcx, 4
    jbe  .bad
    mov  rcx, [rbx+8]
    mov  [rcx], rax
    inc  r14d
    jmp  .next
.bad:
    mov  rcx, [rbx+8]
    mov  qword [rcx], 0
    mov  rdx, [rbx]
    cmp  qword [rbx+16], 0
    je   .optional
    inc  r13d
    lea  rcx, [rel s_gl_missing]
    call log_printf
    jmp  .next
.optional:
    lea  rcx, [rel s_gl_optional]
    call log_printf
.next:
    add  rbx, 24
    jmp  .loop
.done:
    lea  rcx, [rel s_gl_loaded]
    mov  edx, r14d
    call log_printf
    xor  eax, eax
    test r13d, r13d
    setz al
    lea  rsp, [rbp-32]
    pop  r14
    pop  r13
    pop  r12
    pop  rbx
    pop  rbp
    ret

FUNC compile_shader, 16
    mov  r12d, ecx
    mov  LOC(0), rdx                    ; glShaderSource wants &src
    call [rel pglCreateShader]
    mov  ebx, eax
    test eax, eax
    jz   .fail0
    mov  ecx, ebx
    mov  edx, 1
    lea  r8, LOC(0)
    xor  r9d, r9d
    call [rel pglShaderSource]
    mov  ecx, ebx
    call [rel pglCompileShader]
    mov  dword LOC(8), 0
    mov  ecx, ebx
    mov  edx, GL_COMPILE_STATUS
    lea  r8, LOC(8)
    call [rel pglGetShaderiv]
    cmp  dword LOC(8), 0
    jne  .ok
    lea  rdx, [rel s_vs]
    lea  rax, [rel s_fs]
    cmp  r12d, GL_VERTEX_SHADER
    cmovne rdx, rax
    lea  rcx, [rel s_sh_fail]
    call log_printf
    mov  byte [rel gl_info_log], 0
    mov  ecx, ebx
    mov  edx, 4095
    xor  r8d, r8d
    lea  r9, [rel gl_info_log]
    call [rel pglGetShaderInfoLog]
    lea  rcx, [rel gl_info_log]
    call log_write
    mov  ecx, ebx
    call [rel pglDeleteShader]
.fail0:
    xor  eax, eax
    jmp  .ret
.ok:
    mov  eax, ebx
.ret:
    ENDP

; r8 = null-terminated list of attrib names, index = location. mesher layout depends on it
PROC gl_compile_program, 16
    mov  rsi, rdx
    mov  rdi, r8                        ; can be 0
    mov  rdx, rcx
    mov  ecx, GL_VERTEX_SHADER
    call compile_shader
    mov  r12d, eax
    test eax, eax
    jz   .fail
    mov  ecx, GL_FRAGMENT_SHADER
    mov  rdx, rsi
    call compile_shader
    mov  r13d, eax
    test eax, eax
    jz   .fail_vs
    call [rel pglCreateProgram]
    mov  ebx, eax
    test eax, eax
    jz   .fail_both
    mov  ecx, ebx
    mov  edx, r12d
    call [rel pglAttachShader]
    mov  ecx, ebx
    mov  edx, r13d
    call [rel pglAttachShader]
    ; has to happen before link or it does nothing
    test rdi, rdi
    jz   .link
    xor  r14d, r14d
.attr:
    mov  r8, [rdi+r14*8]
    test r8, r8
    jz   .link
    mov  ecx, ebx
    mov  edx, r14d
    call [rel pglBindAttribLocation]
    inc  r14d
    jmp  .attr
.link:
    mov  ecx, ebx
    call [rel pglLinkProgram]
    ; safe to delete now, GL only flags them while they're attached
    mov  ecx, r12d
    call [rel pglDeleteShader]
    mov  ecx, r13d
    call [rel pglDeleteShader]
    mov  dword LOC(0), 0
    mov  ecx, ebx
    mov  edx, GL_LINK_STATUS
    lea  r8, LOC(0)
    call [rel pglGetProgramiv]
    cmp  dword LOC(0), 0
    jne  .ok
    lea  rcx, [rel s_link_fail]
    call log_write
    mov  byte [rel gl_info_log], 0
    mov  edx, [rel game_exit_code]
    mov  r8, [rel g_frame_count]
    call log_printf
    mov  eax, [rel game_exit_code]
.ret:
    ENDP
