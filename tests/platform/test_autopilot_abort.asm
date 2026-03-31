; test_autopilot_abort.asm - a selftest run that gets WM_CLOSE'd halfway must
; not exit 0. arg = game exe, default <root>\MineAssembly.exe.
; window is matched by pid so other running copies are left alone.
; @link tests/platform/pt_helpers.asm
; @gpu
; @timeout 120
%include "common.inc"
%include "testlib.inc"

extern EnumWindows, GetWindowThreadProcessId, GetClassNameA, PostMessageA
extern pt_strcpy, pt_strstr, pt_streq, pt_join, pt_root, pt_fresh_dir, pt_arg1
extern pt_read_file, pt_spawn, pt_wait_exit, pt_print_tail

%define WAIT_TIMEOUT    0x102

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
s_work_name:    db "autopilot_abort", 0
s_quote:        db '"', 0
s_args:         db '" --selftest --seed 7', 0
s_log:          db "mineassembly.log", 0
s_class:        db "MineAssemblyWindow", 0
s_pass:         db "selftest: PASS", 0
s_code_is:      db "exit code ", 0
s_empty:        db 0

section .text

; EnumWindows callback. search = {dword pid, pad, qword hwnd}, first hit wins
PROC enum_cb, 80
    mov  rbx, rcx
    mov  rsi, rdx
    cmp  qword [rsi+8], 0
    jne  .done
    mov  rcx, rbx
    lea  rdx, LOC(0)
    mov  dword LOC(0), 0
    call GetWindowThreadProcessId
    mov  eax, LOC(0)
    cmp  eax, [rsi]
    jne  .done
    mov  rcx, rbx
    lea  rdx, LOC(8)
    mov  r8d, 64
    call GetClassNameA
    lea  rcx, LOC(8)
    lea  rdx, [rel s_class]
    call pt_streq
    test eax, eax
    jz   .done
    mov  [rsi+8], rbx
.done:
    mov  eax, 1
    ENDP

%define L_ROOT   LOC(0)
%define L_EXE    LOC(272)
%define L_WORK   LOC(544)
%define L_PATH   LOC(816)
%define L_CMD    LOC(1088)
%define L_PI     LOC(1688)              ; PROCESS_INFORMATION
%define L_CODE   LOC(1712)
%define L_SIZE   LOC(1720)
%define L_FIND   LOC(1728)              ; enum_cb search block
%define L_DEAD   LOC(1744)

PROC test_main, 1760
    TEST "autopilot abort"
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
    lea  rcx, L_WORK
    lea  rdx, [rel s_work_name]
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
    ; give the window 20 s to show up, stop early if the game dies
    mov  eax, LOC(1688+16)              ; PROCESS_INFORMATION.dwProcessId
    mov  L_FIND, eax
    mov  qword LOC(1728+8), 0
    call GetTickCount64
    add  rax, 20000
    mov  L_DEAD, rax
.find:
    call GetTickCount64
    cmp  rax, L_DEAD
    jae  .found_or_not
    mov  rcx, L_PI
    xor  edx, edx
    call WaitForSingleObject
    cmp  eax, WAIT_TIMEOUT
    jne  .found_or_not                  ; already exited
    lea  rcx, [rel enum_cb]
    lea  rdx, L_FIND
    call EnumWindows
    cmp  qword LOC(1728+8), 0
    jne  .found_or_not
    mov  ecx, 200
    call Sleep
    jmp  .find
.found_or_not:
    mov  rbx, LOC(1728+8)
    xor  ecx, ecx
    test rbx, rbx
    setnz cl
    CHECK_TRUE ecx, "game window appeared"
    test rbx, rbx
    jz   .wait
    mov  ecx, 3000                      ; let the run get going
    call Sleep
    mov  rcx, rbx
    mov  edx, WM_CLOSE
    xor  r8d, r8d
    xor  r9d, r9d
    call PostMessageA
.wait:
    lea  rcx, L_PI
    mov  edx, 60000
    lea  r8, L_CODE
    call pt_wait_exit
    mov  r12d, eax
    CHECK_TRUE r12d, "process exits within 60 s of WM_CLOSE"
    test r12d, r12d
    jz   .log
    CHECK_EQ32 L_CODE, 1, "exit code 1 for an interrupted run"
.log:
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
    mov  r8d, 1200
    call pt_print_tail
    lea  rcx, [rel s_code_is]
    call t_print
    mov  ecx, L_CODE
    call t_print_int
    call t_newline
    LOG_HAS "autopilot: FAIL - run interrupted"
    LOG_HAS "game: shutting down"
    LOG_HAS "main: exit code 1"
    mov  rcx, rbx
    lea  rdx, [rel s_pass]
    call pt_strstr
    xor  ecx, ecx
    test rax, rax
    setz cl
    CHECK_TRUE ecx, "an interrupted run must not claim PASS"
.done:
    ENDP
