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
    mov  ecx, ebx
    mov  edx, 4095
    xor  r8d, r8d
    lea  r9, [rel gl_info_log]
    call [rel pglGetProgramInfoLog]
    lea  rcx, [rel gl_info_log]
    call log_write
    mov  ecx, ebx
    call [rel pglDeleteProgram]
    jmp  .fail
.fail_both:
    mov  ecx, r13d
    call [rel pglDeleteShader]
.fail_vs:
    mov  ecx, r12d
    call [rel pglDeleteShader]
.fail:
    xor  eax, eax
    jmp  .ret
.ok:
    mov  eax, ebx
.ret:
    ENDP

    global gl_check_error
    align 16
gl_check_error:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push r12
    sub  rsp, FRAME_OUT + 8
    mov  rsi, rcx
    mov  ebx, 16                        ; cap it, a lost context can spam forever
.loop:
    call glGetError
    test eax, eax
    jz   .done
    mov  edx, eax
    lea  r8, [rel s_unknown]
    lea  ecx, [rax-0x500]
    cmp  ecx, 6
    ja   .log
    lea  r8, [rel gl_err_names]
    mov  r8, [r8+rcx*8]
.log:
    lea  rcx, [rel s_err_fmt]
    mov  r9, rsi
    test r9, r9
    jnz  .tag_ok
    lea  r9, [rel s_unknown]
.tag_ok:
    call log_printf
    dec  ebx
    jnz  .loop
.done:
    lea  rsp, [rbp-24]
    pop  r12
    pop  rsi
    pop  rbx
    pop  rbp
    ret
