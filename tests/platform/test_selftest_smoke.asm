; test_selftest_smoke.asm - --selftest --seed 42 has to get through window/gl/
; main loop and exit by itself. full game: exit 0 + five bmps. stub build never
; finishes loading, so exit 2 after the 90 s load timeout is fine too.
; @link tests/platform/pt_helpers.asm
; @gpu
; @timeout 150
%include "common.inc"
%include "testlib.inc"

extern pt_strlen, pt_strcpy, pt_strstr, pt_join, pt_root, pt_fresh_dir, pt_arg1
extern pt_read_file, pt_file_size, pt_spawn, pt_wait_exit, pt_print_tail

; log text is in rbx
%macro LOG_HAS 1
    section .rdata
    %%n: db %1, 0
    section .text
    mov  rcx, rbx
    lea  rdx, [rel %%n]
    call pt_strstr
    xor  ecx, ecx
    test rax, rax
    setnz cl
    CHECK_TRUE ecx, %1
%endmacro

section .rdata
s_exe_rel:      db "MineAssembly.exe", 0
s_work_prefix:  db "selftest_smoke_", 0
s_root_tag:     db "root", 0
s_quote:        db '"', 0
s_args:         db '" --selftest --seed 42', 0
s_log:          db "mineassembly.log", 0
s_bmp_name:     db "selftest_0.bmp", 0
s_exe_is:       db "exe: ", 0
s_code_is:      db "exit code ", 0
s_no_start:     db "could not start the game exe", 0
s_empty:        db 0

section .text

%define L_ROOT   LOC(0)
%define L_EXE    LOC(272)
%define L_WORK   LOC(544)
%define L_NAME   LOC(816)
%define L_CMD    LOC(1088)
%define L_PI     LOC(1688)              ; PROCESS_INFORMATION
%define L_CODE   LOC(1712)
%define L_SIZE   LOC(1720)
%define L_PATH   LOC(1728)
%define L_HDR    LOC(2000)

PROC test_main, 2080
    TEST "selftest smoke"
    lea  rcx, L_ROOT
    call pt_root
    lea  rcx, L_EXE
    call pt_arg1
    test eax, eax
    jnz  .have_exe
    lea  rcx, L_EXE
    lea  rdx, L_ROOT
    lea  r8, [rel s_exe_rel]
    call pt_join
.have_exe:
    lea  rcx, [rel s_exe_is]
    call t_print
    lea  rcx, L_EXE
    call t_print
    call t_newline

    ; work dir is selftest_smoke_<name of the exe's dir>, so stub/fake/full runs
    ; don't wipe each other's files
    lea  rcx, L_PATH
    lea  rdx, L_EXE
    call pt_strcpy
    lea  rcx, L_PATH
    call pt_strlen
    lea  rsi, L_PATH
    lea  rdi, [rsi+rax]
.cut_file:
    cmp  rdi, rsi
    jbe  .tag_root
    dec  rdi
    cmp  byte [rdi], '\'
    jne  .cut_file
    mov  byte [rdi], 0
.find_base:
    cmp  rdi, rsi
    jbe  .base_here
    cmp  byte [rdi-1], '\'
    je   .base_here
    dec  rdi
    jmp  .find_base
.base_here:
    cmp  byte [rdi], 0
    je   .tag_root
    cmp  byte [rdi+1], ':'              ; bare "C:" -> "root"
    jne  .tag_ok
    cmp  byte [rdi+2], 0
    jne  .tag_ok
.tag_root:
    lea  rdi, [rel s_root_tag]
.tag_ok:
    lea  rcx, L_NAME
    lea  rdx, [rel s_work_prefix]
    call pt_strcpy
    mov  rcx, rax
    mov  rdx, rdi
    call pt_strcpy
    lea  rcx, L_WORK
    lea  rdx, L_NAME
    call pt_fresh_dir
    CHECK_TRUE eax, "work directory created"

    lea  rcx, L_CMD
    lea  rdx, [rel s_quote]
    call pt_strcpy
    mov  rcx, rax
    lea  rdx, L_EXE
    call pt_strcpy
    mov  rcx, rax
    lea  rdx, [rel s_args]
    call pt_strcpy
    lea  rcx, L_CMD
    lea  rdx, L_WORK
    lea  r8, L_PI
    call pt_spawn
    test eax, eax
    jnz  .started
    CHECK_TRUE 0, "game process started"
    jmp  .done
.started:
    lea  rcx, L_PI
    mov  edx, 110000
    lea  r8, L_CODE
    call pt_wait_exit
    test eax, eax
    jnz  .exited
    CHECK_TRUE 0, "process exits within 110 s"
    jmp  .done
.exited:
    lea  rcx, L_PATH
    lea  rdx, L_WORK
    lea  r8, [rel s_log]
    call pt_join
    lea  rcx, L_PATH
    lea  rdx, L_SIZE
    call pt_read_file
    mov  rbx, rax
    xor  ecx, ecx
    test rbx, rbx
    setnz cl
    CHECK_TRUE ecx, "mineassembly.log written"
    test rbx, rbx
    jnz  .have_log
    lea  rbx, [rel s_empty]
    mov  qword L_SIZE, 0
.have_log:
    mov  rcx, rbx
    mov  rdx, L_SIZE
    mov  r8d, 3000
    call pt_print_tail
    lea  rcx, [rel s_code_is]
    call t_print
    mov  ecx, L_CODE
    call t_print_int
    call t_newline

    mov  eax, L_CODE
    xor  ecx, ecx
    cmp  eax, 0
    je   .code_ok
    cmp  eax, 2
    jne  .code_chk
.code_ok:
    mov  ecx, 1
.code_chk:
    CHECK_TRUE ecx, "exit code is 0 (full game) or 2 (stub build)"
    LOG_HAS "run mode 1, seed 42"
    LOG_HAS "platform: window"
    LOG_HAS "OpenGL version"
    LOG_HAS "game: ready in"
    LOG_HAS "autopilot: selftest run started (seed 42)"
    LOG_HAS "game: shutting down"
    LOG_HAS "main: exit code"
    cmp  dword L_CODE, 2
    jne  .not_timeout
    LOG_HAS "spawn area not ready"
.not_timeout:
    cmp  dword L_CODE, 0
    jne  .done

    mov  r12d, 1
.bmp:
    lea  rcx, L_NAME
    lea  rdx, [rel s_bmp_name]
    call pt_strcpy
    lea  eax, [r12d+'0']
    mov  byte LOC(816+9), al             ; the N in selftest_N.bmp
    lea  rcx, L_PATH
    lea  rdx, L_WORK
    lea  r8, L_NAME
    call pt_join
    ; "BM", 24 bpp, size == 54 + ((w*3+3)&~3)*h
    lea  rcx, L_PATH
    lea  rdx, L_SIZE
    call pt_read_file
    xor  r13d, r13d
    test rax, rax
    jz   .bmp_chk
    cmp  qword L_SIZE, 54
    jb   .bmp_chk
    cmp  word [rax], 'BM'
    jne  .bmp_chk
    cmp  word [rax+28], 24
    jne  .bmp_chk
    movsxd rcx, dword [rax+18]
    movsxd rdx, dword [rax+22]
    lea  rcx, [rcx+rcx*2+3]
    and  rcx, ~3
    imul rcx, rdx
    add  rcx, 54
    cmp  rcx, L_SIZE
    jne  .bmp_chk
    mov  r13d, 1
.bmp_chk:
    CHECK_TRUE r13d, "selftest_N.bmp exists and is a valid 24-bit BMP"
    test r13d, r13d
    jnz  .bmp_next
    lea  rcx, L_PATH
    call t_print
    call t_newline
.bmp_next:
    inc  r12d
    cmp  r12d, 5
    jbe  .bmp
.done:
    ENDP
