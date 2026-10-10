; gl_linux.asm - gl.asm for the linux build. the glFoo thunks (thunks_gl.asm) get their
; libGL addresses from dlsym here, the 2.0 set comes from glXGetProcAddressARB and lands
; in pgl* as a thunk address so callers don't change. shader compile is the same as gl.asm.
; needs a current GLX context before gl_load_functions, same as wgl.
%define IMPL_GL
%include "common.inc"

extern dlopen, dlsym, dprintf
extern gl1_table, gl1_table_end, gl2_table, gl2_table_end
extern pglCreateShader, pglShaderSource, pglCompileShader, pglGetShaderiv, pglGetShaderInfoLog
extern pglDeleteShader, pglCreateProgram, pglAttachShader, pglBindAttribLocation, pglLinkProgram
extern pglGetProgramiv, pglGetProgramInfoLog, pglDeleteProgram

%define RTLD_LAZY   1
%define RTLD_GLOBAL 0x100

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

; FUNC with xmm6-15 saved, for anything that calls into libc/libGL
%macro FUNCX 1-2 0
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
    sub  rsp, 168
    movdqa [rsp+0],   xmm6
    movdqa [rsp+16],  xmm7
    movdqa [rsp+32],  xmm8
    movdqa [rsp+48],  xmm9
    movdqa [rsp+64],  xmm10
    movdqa [rsp+80],  xmm11
    movdqa [rsp+96],  xmm12
    movdqa [rsp+112], xmm13
    movdqa [rsp+128], xmm14
    movdqa [rsp+144], xmm15
    sub  rsp, (((%2)+15) & ~15) + FRAME_OUT
%endmacro

section .rodata
s_libgl1:       db "libGL.so.1", 0
s_libgl:        db "libGL.so", 0
s_nolib:        db "MineAssembly: can't load libGL.so.1", 10, 0
s_nosym:        db "MineAssembly: libGL has no %s", 10, 0
s_gpa_arb:      db "glXGetProcAddressARB", 0
s_gpa:          db "glXGetProcAddress", 0
s_getdpy:       db "glXGetCurrentDisplay", 0
s_getdrw:       db "glXGetCurrentDrawable", 0
s_qext:         db "glXQueryExtensionsString", 0
s_xdefscr:      db "XDefaultScreen", 0
s_ext_ext:      db "GLX_EXT_swap_control", 0
s_ext_mesa:     db "GLX_MESA_swap_control", 0
s_ext_sgi:      db "GLX_SGI_swap_control", 0
s_fn_ext:       db "glXSwapIntervalEXT", 0
s_fn_mesa:      db "glXSwapIntervalMESA", 0
s_fn_sgi:       db "glXSwapIntervalSGI", 0
s_vsync_name:   db "glXSwapInterval*", 0
s_old_gl:       db "OpenGL: context is %s, need 2.0", 0
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

section .data
align 8
gl_err_names:   dq s_e500, s_e501, s_e502, s_e503, s_e504, s_e505, s_e506
; {extension, function, mode} in order of preference
sw_table:       dq s_ext_ext, s_fn_ext, 1
                dq s_ext_mesa, s_fn_mesa, 2
                dq s_ext_sgi, s_fn_sgi, 3
sw_table_end:

section .bss
alignb 8
global gl_libgl, pwglSwapIntervalEXT
gl_libgl:       resq 1                  ; dlopen handle, 0 if there's no libGL
pwglSwapIntervalEXT: resq 1             ; same as windows: (ecx interval) -> eax BOOL
sw_fn:          resq 1
sw_getdpy:      resq 1
sw_getdrw:      resq 1
sw_mode:        resd 1                  ; 1 EXT, 2 MESA, 3 SGI
gl_inited:      resb 1
alignb 16
gl_info_log:    resb 4096               ; main thread only

section .text

; empty slot target, so a symbol libGL doesn't have reads as 0 instead of crashing
align 16
gl_thunk_missing:
    xor  eax, eax
    ret

; a 1.1 thunk found its slot empty. rax = that thunk, args still in place.
; run the init and go back in with everything restored
global gl_thunk_lazy
align 16
gl_thunk_lazy:
    mov  [rsp+8], rcx
    mov  [rsp+16], rdx
    mov  [rsp+24], r8
    mov  [rsp+32], r9
    sub  rsp, 120
    movaps [rsp+32], xmm0
    movaps [rsp+48], xmm1
    movaps [rsp+64], xmm2
    movaps [rsp+80], xmm3
    mov  [rsp+96], rax
    call gl_thunks_init
    movaps xmm0, [rsp+32]
    movaps xmm1, [rsp+48]
    movaps xmm2, [rsp+64]
    movaps xmm3, [rsp+80]
    mov  rax, [rsp+96]
    add  rsp, 120
    mov  rcx, [rsp+8]
    mov  rdx, [rsp+16]
    mov  r8, [rsp+24]
    mov  r9, [rsp+32]
    jmp  rax

; fills every 1.1 slot. safe to call more than once, no context needed
PROCX gl_thunks_init, 0
    cmp  byte [rel gl_inited], 0
    jne  .done
    mov  byte [rel gl_inited], 1
    lea  rdi, [rel s_libgl1]
    mov  esi, RTLD_LAZY | RTLD_GLOBAL
    call dlopen wrt ..plt
    test rax, rax
    jnz  .have
    lea  rdi, [rel s_libgl]
    mov  esi, RTLD_LAZY | RTLD_GLOBAL
    call dlopen wrt ..plt
    test rax, rax
    jnz  .have
    mov  edi, 2
    lea  rsi, [rel s_nolib]
    xor  eax, eax
    call dprintf wrt ..plt
    xor  eax, eax
.have:
    mov  [rel gl_libgl], rax
    lea  rbx, [rel gl1_table]
    lea  r12, [rel gl1_table_end]
.loop:
    cmp  rbx, r12
    jae  .done
    mov  rdi, [rel gl_libgl]
    test rdi, rdi
    jz   .stub                          ; already complained once
    mov  rsi, [rbx]
    call dlsym wrt ..plt
    test rax, rax
    jnz  .set
    mov  edi, 2
    lea  rsi, [rel s_nosym]
    mov  rdx, [rbx]
    xor  eax, eax
    call dprintf wrt ..plt
.stub:
    lea  rax, [rel gl_thunk_missing]
.set:
    mov  rcx, [rbx+8]
    mov  [rcx], rax
    add  rbx, 16
    jmp  .loop
.done:
    ENDPX

; (rcx name) -> rax, dlsym on libGL, 0 without it
FUNCX gl_sym, 0
    mov  rdi, [rel gl_libgl]
    xor  eax, eax
    test rdi, rdi
    jz   .ret
    mov  rsi, rcx
    call dlsym wrt ..plt
.ret:
    ENDPX

; (rcx space separated list, rdx name) -> eax 1 if name is one of the words
FUNC ext_has, 0
    mov  rsi, rcx
.word:
    cmp  byte [rsi], ' '
    jne  .cmp
    inc  rsi
    jmp  .word
.cmp:
    cmp  byte [rsi], 0
    je   .no
    xor  ecx, ecx
.ch:
    mov  al, [rdx+rcx]
    test al, al
    jz   .end
    cmp  al, [rsi+rcx]
    jne  .skip
    inc  ecx
    jmp  .ch
.end:
    mov  al, [rsi+rcx]                  ; prefix match only counts at a word end
    test al, al
    jz   .yes
    cmp  al, ' '
    je   .yes
.skip:
    mov  al, [rsi]
    test al, al
    jz   .no
    cmp  al, ' '
    je   .word
    inc  rsi
    jmp  .skip
.yes:
    mov  eax, 1
    jmp  .ret
.no:
    xor  eax, eax
.ret:
    ENDP

; what pwglSwapIntervalEXT points at. (ecx interval) -> eax 1 ok
FUNCX gl_swap_interval, 0
    mov  ebx, ecx
    mov  eax, [rel sw_mode]
    cmp  eax, 1
    jne  .mesa
    call [rel sw_getdpy]
    mov  r12, rax
    call [rel sw_getdrw]
    test r12, r12
    jz   .fail
    test rax, rax
    jz   .fail
    mov  rdi, r12
    mov  rsi, rax
    mov  edx, ebx
    call [rel sw_fn]                    ; void
    mov  eax, 1
    jmp  .ret
.mesa:
    cmp  eax, 2
    je   .call
    test ebx, ebx                       ; SGI can't switch it off, 0 is an error there
    jz   .fail
.call:
    mov  edi, ebx
    call [rel sw_fn]
    test eax, eax
    sete al
    movzx eax, al
    jmp  .ret
.fail:
    xor  eax, eax
.ret:
    ENDPX

; pick a swap control ext, leaves pwglSwapIntervalEXT 0 if there's none
FUNCX gl_find_swap, 0
    mov  qword [rel pwglSwapIntervalEXT], 0
    mov  dword [rel sw_mode], 0
    lea  rcx, [rel s_getdpy]
    call gl_sym
    mov  [rel sw_getdpy], rax
    lea  rcx, [rel s_getdrw]
    call gl_sym
    mov  [rel sw_getdrw], rax
    lea  rcx, [rel s_qext]
    call gl_sym
    mov  r12, rax
    mov  rax, [rel sw_getdpy]
    test rax, rax
    jz   .none
    test r12, r12
    jz   .none
    call rax
    mov  r13, rax                       ; Display*
    test rax, rax
    jz   .none
    xor  r14d, r14d                     ; screen, 0 if libX11 isn't around somehow
    xor  edi, edi                       ; RTLD_DEFAULT
    lea  rsi, [rel s_xdefscr]
    call dlsym wrt ..plt
    test rax, rax
    jz   .scr
    mov  rdi, r13
    call rax
    mov  r14d, eax
.scr:
    mov  rdi, r13
    mov  esi, r14d
    call r12
    test rax, rax
    jz   .none
    mov  r15, rax
    lea  rbx, [rel sw_table]
.pick:
    lea  rax, [rel sw_table_end]
    cmp  rbx, rax
    jae  .none
    mov  rcx, r15
    mov  rdx, [rbx]
    call ext_has
    test eax, eax
    jz   .next
    cmp  qword [rbx+16], 1              ; EXT wants the current drawable
    jne  .gpa
    cmp  qword [rel sw_getdrw], 0
    je   .next
.gpa:
    mov  rdi, [rbx+8]
    call [rel gl_gpa]
    test rax, rax
    jz   .next
    mov  [rel sw_fn], rax
    mov  eax, [rbx+16]
    mov  [rel sw_mode], eax
    lea  rax, [rel gl_swap_interval]
    mov  [rel pwglSwapIntervalEXT], rax
    jmp  .ret
.next:
    add  rbx, 24
    jmp  .pick
.none:
    lea  rcx, [rel s_gl_optional]
    lea  rdx, [rel s_vsync_name]
    call log_printf
.ret:
    ENDPX

section .bss
gl_gpa:         resq 1                  ; glXGetProcAddressARB
section .text

PROC gl_load_functions, 0
    call gl_thunks_init
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
    mov  r15, rax
    lea  rdx, [rel s_unknown]
    test rax, rax
    cmovnz rdx, rax
    lea  rcx, [rel s_gl_info3]
    call log_printf

    xor  r13d, r13d                     ; required + missing
    xor  r14d, r14d
    ; glvnd hands out a stub for any name, so the pointers alone prove nothing.
    ; version string starts with "major.minor"
    test r15, r15
    jz   .old
    movzx eax, byte [r15]
    sub  eax, '0'
    cmp  eax, 9
    ja   .old
    movzx ecx, byte [r15+1]
    sub  ecx, '0'
    cmp  ecx, 9
    jbe  .ver_ok                        ; two digit major
    cmp  eax, 2
    jae  .ver_ok
.old:
    inc  r13d
    lea  rdx, [rel s_unknown]
    test r15, r15
    cmovnz rdx, r15
    lea  rcx, [rel s_old_gl]
    call log_printf
.ver_ok:
    lea  rcx, [rel s_gpa_arb]
    call gl_sym
    test rax, rax
    jnz  .gpa_ok
    lea  rcx, [rel s_gpa]
    call gl_sym
.gpa_ok:
    mov  [rel gl_gpa], rax
    mov  r15, rax

    lea  rbx, [rel gl2_table]
    lea  r12, [rel gl2_table_end]
.loop:
    cmp  rbx, r12
    jae  .loaded
    xor  eax, eax
    test r15, r15
    jz   .got
    mov  rcx, [rbx]
    call gl_gpa_call
.got:
    test rax, rax
    jz   .bad
    mov  rcx, [rbx+8] ; trace probe #125 hook
    mov  [rcx], rax ; trace probe #125 hook
    mov  rcx, [rbx+24] ; trace probe #125 hook
    mov  rax, [rbx+16] ; trace probe #125 hook
    mov  [rcx], rax ; trace probe #125 hook
    inc  r14d ; trace probe #125 hook
    jmp  .next ; trace probe #125 hook
.bad: ; trace probe #125 hook
    mov  rcx, [rbx+24] ; trace probe #125 hook
    mov  qword [rcx], 0
    mov  rdx, [rbx]
    cmp  qword [rbx+32], 0
    je   .optional
    inc  r13d
    lea  rcx, [rel s_gl_missing]
    call log_printf
    jmp  .next
.optional:
    lea  rcx, [rel s_gl_optional]
    call log_printf
.next:
    add  rbx, 40
    jmp  .loop
.loaded:
    test r15, r15
    jz   .no_swap
    call gl_find_swap
.no_swap:
    lea  rcx, [rel s_gl_loaded]
    mov  edx, r14d
    call log_printf
    xor  eax, eax
    test r13d, r13d
    setz al
    ENDP
; --- temporary diagnostic probe #125 (gl_linux) ---
; TODO: strip dbg_gl_linux_probe_125 once frame/state invariants hold
dbg_gl_linux_probe_125:
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
    jz      .dbg_null_125
    mov     eax, dword [rcx+0] ; sample gl_linux state +0
    xor     r10, r8 ; fold word 0
    cmp     eax, -1
    je      .dbg_skip_125_0
.dbg_skip_125_0:
    mov     ecx, dword [rcx+4] ; sample gl_linux state +4
    xor     r10, r9 ; fold word 1
    cmp     ecx, -1
    je      .dbg_skip_125_1
.dbg_skip_125_1:
    mov     edx, dword [rcx+8] ; sample gl_linux state +8
    xor     r10, r10 ; fold word 2
    cmp     edx, -1
    je      .dbg_skip_125_2
.dbg_skip_125_2:
    mov     r8d, dword [rcx+12] ; sample gl_linux state +12
    xor     r10, r11 ; fold word 3
    cmp     r8d, -1
    je      .dbg_skip_125_3
.dbg_skip_125_3:
    mov     r9d, dword [rcx+16] ; sample gl_linux state +16
    xor     r10, r8 ; fold word 4
    cmp     r9d, -1
    je      .dbg_skip_125_4
.dbg_skip_125_4:
    mov     r11d, dword [rcx+20] ; sample gl_linux state +20
    xor     r10, r9 ; fold word 5
    cmp     r11d, -1
    je      .dbg_skip_125_5
.dbg_skip_125_5:
    mov     eax, dword [rcx+24] ; sample gl_linux state +24
    xor     r10, r10 ; fold word 6
    cmp     eax, -1
    je      .dbg_skip_125_6
.dbg_skip_125_6:
    mov     ecx, dword [rcx+28] ; sample gl_linux state +28
    xor     r10, r11 ; fold word 7
    cmp     ecx, -1
    je      .dbg_skip_125_7
.dbg_skip_125_7:
    mov     edx, dword [rcx+32] ; sample gl_linux state +32
    xor     r10, r8 ; fold word 8
    cmp     edx, -1
    je      .dbg_skip_125_8
.dbg_skip_125_8:
    mov     r8d, dword [rcx+36] ; sample gl_linux state +36
    xor     r10, r9 ; fold word 9
    cmp     r8d, -1
    je      .dbg_skip_125_9
.dbg_skip_125_9:
    mov     r9d, dword [rcx+40] ; sample gl_linux state +40
    xor     r10, r10 ; fold word 10
    cmp     r9d, -1
    je      .dbg_skip_125_10
.dbg_skip_125_10:
    mov     r11d, dword [rcx+44] ; sample gl_linux state +44
    xor     r10, r11 ; fold word 11
    cmp     r11d, -1
    je      .dbg_skip_125_11
.dbg_skip_125_11:
    mov     eax, dword [rcx+48] ; sample gl_linux state +48
    xor     r10, r8 ; fold word 12
    cmp     eax, -1
    je      .dbg_skip_125_12
.dbg_skip_125_12:
    mov     ecx, dword [rcx+52] ; sample gl_linux state +52
    xor     r10, r9 ; fold word 13
    cmp     ecx, -1
    je      .dbg_skip_125_13
.dbg_skip_125_13:
    mov     edx, dword [rcx+56] ; sample gl_linux state +56
    xor     r10, r10 ; fold word 14
    cmp     edx, -1
    je      .dbg_skip_125_14
.dbg_skip_125_14:
    mov     r8d, dword [rcx+60] ; sample gl_linux state +60
    xor     r10, r11 ; fold word 15
    cmp     r8d, -1
    je      .dbg_skip_125_15
.dbg_skip_125_15:
    mov     r9d, dword [rcx+64] ; sample gl_linux state +64
    xor     r10, r8 ; fold word 16
    cmp     r9d, -1
    je      .dbg_skip_125_16
.dbg_skip_125_16:
    mov     r11d, dword [rcx+68] ; sample gl_linux state +68
    xor     r10, r9 ; fold word 17
    cmp     r11d, -1
    je      .dbg_skip_125_17
.dbg_skip_125_17:
    mov     eax, dword [rcx+72] ; sample gl_linux state +72
    xor     r10, r10 ; fold word 18
    cmp     eax, -1
    je      .dbg_skip_125_18
.dbg_skip_125_18:
    mov     ecx, dword [rcx+76] ; sample gl_linux state +76
    xor     r10, r11 ; fold word 19
    cmp     ecx, -1
    je      .dbg_skip_125_19
.dbg_skip_125_19:
    mov     edx, dword [rcx+80] ; sample gl_linux state +80
    xor     r10, r8 ; fold word 20
    cmp     edx, -1
    je      .dbg_skip_125_20
.dbg_skip_125_20:
    mov     r8d, dword [rcx+84] ; sample gl_linux state +84
    xor     r10, r9 ; fold word 21
    cmp     r8d, -1
    je      .dbg_skip_125_21
.dbg_skip_125_21:
.dbg_null_125:
    mov     rcx, [rsp+32]
    mov     rdx, [rsp+40]
    mov     r8,  [rsp+48]
    mov     r9,  [rsp+56]
    add     rsp, 64
    pop     rbp
    ret
