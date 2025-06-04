; mabuild.asm - the build tool. one translation unit, the mb_*.asm files are %included.
; bootstrap from the repo root, then `mabuild self` from there on:
;   nasm -f win64 -I include\ -I tools\ tools\mabuild.asm -o mabuild.obj
;   gcc -nostdlib -o mabuild.exe mabuild.obj -Wl,-e,start -Wl,--subsystem,console -lkernel32 -luser32

%include "common.inc"
%include "mb_util.asm"
%include "mb_proc.asm"
%include "mb_coff.asm"
%include "mb_build.asm"
%include "mb_test.asm"

; png/scenario are optional: if nasm can't find them, these stubs go in.
; they get argv after the command word, cwd untouched (mk_root has the repo root).
; mk_/MK_ names belong to mabuild, keep them out of those two.
%pathsearch MK_PNG_FILE "mb_png.asm"
%ifidn MK_PNG_FILE,"mb_png.asm"
section .rdata
mk_s_nopng:     db "mabuild: PNG support is not built in (tools\mb_png.asm missing)", 0
section .text
PROC png_convert_bmp
    xor  eax, eax
ENDP
PROC png_main
    lea  rcx, [mk_s_nopng]
    call mk_println
    mov  eax, 2
ENDP
%else
%include MK_PNG_FILE
%endif

%pathsearch MK_SCEN_FILE "mb_scenario.asm"
%ifidn MK_SCEN_FILE,"mb_scenario.asm"
section .rdata
mk_s_noscen:    db "mabuild: scenario support is not built in (tools\mb_scenario.asm missing)", 0
section .text
PROC scenario_main
    lea  rcx, [mk_s_noscen]
    call mk_println
    mov  eax, 2
ENDP
%else
%include MK_SCEN_FILE
%endif

%define MK_OPT_BUILD    1               ; --stubs, --run
%define MK_OPT_TEST     2               ; --jobs, --timeout, --nogpu
%define MK_OPT_POS      4               ; positional FILE / DIR arguments

section .rdata
mk_c_build:     db "build", 0
mk_c_check:     db "check", 0
mk_c_dll:       db "dll", 0
mk_c_self:      db "self", 0
mk_c_test:      db "test", 0
mk_c_scenario:  db "scenario", 0
mk_c_png:       db "png", 0
mk_c_help:      db "help", 0
mk_o_help:      db "--help", 0
mk_o_h:         db "-h", 0
mk_o_q:         db "/?", 0
mk_o_check:     db "--check", 0
mk_o_tag:       db "--tag", 0
mk_o_stubs:     db "--stubs", 0
mk_o_run:       db "--run", 0
mk_o_jobs:      db "--jobs", 0
mk_o_timeout:   db "--timeout", 0
mk_o_nogpu:     db "--nogpu", 0
mk_s_unkcmd:    db "mabuild: unknown command: ", 0
mk_s_unkopt:    db "mabuild: unknown option or argument: ", 0
mk_s_needval:   db "mabuild: missing or bad value for ", 0
mk_s_seehelp:   db "run 'mabuild --help' for usage", 0
mk_s_dllusage:  db "usage: mabuild dll NAME FILE.asm [FILE.asm ...]", 13, 10
                db "  -> build\test\NAME.dll (src\globals.asm is always included; every API", 13, 10
                db "     symbol the modules do not define is stubbed to return 0)", 0
mk_s_checkuse:  db "usage: mabuild check FILE.asm [FILE.asm ...] [--tag T]", 0
mk_s_help:
    db "mabuild - MineAssembly build tool (x86-64 NASM; needs nasm + gcc as linker)", 13, 10
    db 13, 10
    db "  mabuild [build] [--tag T] [--stubs] [--run ARGS...]", 13, 10
    db "      assemble src\*.asm in parallel and link MineAssembly.exe", 13, 10
    db "      --tag T    private objects/exe: build\obj_T\, build\T\MineAssembly.exe", 13, 10
    db "      --stubs    stub every include\api.inc symbol no module defines yet", 13, 10
    db "      --run ...  then run the game (in its folder) with the remaining arguments", 13, 10
    db "  mabuild check FILE... [--tag T]", 13, 10
    db "      assemble the given modules only (also: mabuild --check FILE...)", 13, 10
    db "  mabuild dll NAME FILE...", 13, 10
    db "      build\test\NAME.dll from the modules + src\globals.asm, missing API stubbed", 13, 10
    db "  mabuild test [DIR|FILE...] [--jobs N] [--timeout S] [--nogpu] [--tag T]", 13, 10
    db "      build and run unit tests (default: every tests\**\test_*.asm)", 13, 10
    db "      --jobs N     tests in parallel (default: logical CPUs / 2)", 13, 10
    db "      --timeout S  seconds per test, overrides '; @timeout' (default 120)", 13, 10
    db "      --nogpu      skip tests marked '; @gpu'", 13, 10
    db "      exit code 0 only if every test passed", 13, 10
    db "  mabuild scenario FILE [options]   run a scenario script (see tests\scenarios)", 13, 10
    db "  mabuild png IN.bmp OUT.png        convert a BMP screenshot to PNG", 13, 10
    db "  mabuild self                      rebuild mabuild.exe from tools\mabuild.asm", 13, 10
    db "  mabuild --help                    this text", 0

section .text

global start
start:
    sub  rsp, 40
    call mk_main
    mov  ecx, eax
    call ExitProcess

PROC mk_argis
    call mk_strcmp
    test eax, eax
    sete al
    movzx eax, al
ENDP

; -> eax 2, prints "message argument" + the --help hint
PROC mk_err_arg
    mov  rbx, rdx
    call mk_print
    mov  rcx, rbx
    test rcx, rcx
    jz   .noarg
    call mk_println
    jmp  .hint
.noarg:
    call mk_nl
.hint:
    lea  rcx, [mk_s_seehelp]
    call mk_println
    mov  eax, 2
ENDP

; positional args are kept as typed (mk_opt_orig) and root-relative (mk_opt_files),
; so this has to run before we chdir into the root
PROC mk_parse_opts, MK_PATH
    mov  esi, ecx
    mov  r15d, edx
    mov  r12, [mk_argv]
    mov  ecx, [mk_argc]
    lea  ecx, [rcx*8+8]
    call mk_alloc
    mov  [mk_opt_files], rax
    mov  ecx, [mk_argc]
    lea  ecx, [rcx*8+8]
    call mk_alloc
    mov  [mk_opt_orig], rax
.l: cmp  esi, [mk_argc]
    jae  .ok
    mov  rbx, [r12+rsi*8]
    mov  rcx, rbx
    lea  rdx, [mk_o_tag]
    call mk_argis
    test eax, eax
    jz   .not_tag
    inc  esi
    cmp  esi, [mk_argc]
    jae  .needval
    mov  rax, [r12+rsi*8]
    mov  [mk_opt_tag], rax
    jmp  .n
.not_tag:
    test r15d, MK_OPT_BUILD
    jz   .not_build
    mov  rcx, rbx
    lea  rdx, [mk_o_stubs]
    call mk_argis
    test eax, eax
    jz   .not_stubs
    mov  dword [mk_opt_stubs], 1
    jmp  .n
.not_stubs:
    mov  rcx, rbx
    lea  rdx, [mk_o_run]
    call mk_argis
    test eax, eax
    jz   .not_build
    lea  eax, [esi+1]                   ; everything after --run goes to the game
    mov  [mk_opt_run], eax
    jmp  .ok
.not_build:
    test r15d, MK_OPT_TEST
    jz   .not_test
    mov  rcx, rbx
    lea  rdx, [mk_o_nogpu]
    call mk_argis
    test eax, eax
    jz   .not_nogpu
    mov  dword [mk_t_nogpu], 1
    jmp  .n
.not_nogpu:
    mov  rcx, rbx
    lea  rdx, [mk_o_jobs]
    call mk_argis
    lea  rdi, [mk_t_jobs]
    test eax, eax
    jnz  .number
    mov  rcx, rbx
    lea  rdx, [mk_o_timeout]
    call mk_argis
    lea  rdi, [mk_t_timeout]
    test eax, eax
    jz   .not_test
.number:                                ; --jobs N / --timeout S : positive integer
    inc  esi
    cmp  esi, [mk_argc]
    jae  .needval
    mov  rcx, [r12+rsi*8]
    mov  r13, rcx
    call mk_atou
    test edx, edx
    jz   .needval
    cmp  byte [r13+rdx], 0
    jne  .needval
    test eax, eax
    jz   .needval
    mov  [rdi], eax
    jmp  .n
.not_test:
    test r15d, MK_OPT_POS
    jz   .unknown
    cmp  byte [rbx], '-'
    je   .unknown
    lea  rcx, LOC(0)
    mov  rdx, rbx
    call mk_rel_root
    lea  rcx, LOC(0)
    call mk_strdup
    mov  ecx, [mk_opt_nfiles]
    mov  rdx, [mk_opt_files]
    mov  [rdx+rcx*8], rax
    mov  rdx, [mk_opt_orig]
    mov  [rdx+rcx*8], rbx
    inc  dword [mk_opt_nfiles]
.n: inc  esi
    jmp  .l
.ok:
    xor  eax, eax
    jmp  .done
.needval:
    lea  rcx, [mk_s_needval]
    mov  rdx, [r12+rsi*8-8]
    call mk_err_arg
    jmp  .done
.unknown:
    lea  rcx, [mk_s_unkopt]
    mov  rdx, rbx
    call mk_err_arg
.done:
ENDP

PROC mk_enter_root
    lea  rcx, [mk_root]
    call SetCurrentDirectoryA
ENDP

; mb_build(rcx tag or 0, edx stubs) -> eax 1 ok. for mb_scenario: same as
; `mabuild build --tag T` but leaves the caller's cwd alone
PROC mb_build, MK_PATH
    mov  [mk_opt_tag], rcx
    mov  [mk_opt_stubs], edx
    mov  dword [mk_opt_run], 0
    mov  ecx, MK_PATH
    lea  rdx, LOC(0)
    call GetCurrentDirectoryA
    call mk_enter_root
    call mk_cmd_build
    mov  ebx, eax
    lea  rcx, LOC(0)
    call SetCurrentDirectoryA
    xor  eax, eax
    test ebx, ebx
    sete al
ENDP

PROC mk_main, MK_PATH
    call mk_init
    call mk_parse_args
    call mk_find_root
    xor  ecx, ecx                       ; remove <exe>.old left by `mabuild self`
    lea  rdx, LOC(0)
    mov  r8d, MK_PATH-8
    call GetModuleFileNameA
    lea  rcx, LOC(0)
    lea  rdx, [mk_s_dotold]
    call mk_strcat
    lea  rcx, LOC(0)
    call DeleteFileA                    ; fails harmlessly when absent / in use
    mov  r12, [mk_argv]
    mov  r13d, [mk_argc]
    ; default command is build, esi = first arg after the command
    mov  esi, 1
    lea  rdi, [mk_c_build]
    cmp  r13d, 2
    jb   .dispatch
    mov  rbx, [r12+8]
    mov  rcx, rbx
    lea  rdx, [mk_o_help]
    call mk_argis
    test eax, eax
    jnz  .help
    mov  rcx, rbx
    lea  rdx, [mk_o_h]
    call mk_argis
    test eax, eax
    jnz  .help
    mov  rcx, rbx
    lea  rdx, [mk_o_q]
    call mk_argis
    test eax, eax
    jnz  .help
    mov  rcx, rbx
    lea  rdx, [mk_o_check]
    call mk_argis
    test eax, eax
    jz   .not_ocheck
    lea  rdi, [mk_c_check]
    mov  esi, 2
    jmp  .dispatch
.not_ocheck:
    cmp  byte [rbx], '-'
    je   .dispatch
    mov  rdi, rbx
    mov  esi, 2
.dispatch:
    mov  rcx, rdi
    lea  rdx, [mk_c_build]
    call mk_argis
    test eax, eax
    jnz  .build
    mov  rcx, rdi
    lea  rdx, [mk_c_check]
    call mk_argis
    test eax, eax
    jnz  .check
    mov  rcx, rdi
    lea  rdx, [mk_c_test]
    call mk_argis
    test eax, eax
    jnz  .test
    mov  rcx, rdi
    lea  rdx, [mk_c_dll]
    call mk_argis
    test eax, eax
    jnz  .dll
    mov  rcx, rdi
    lea  rdx, [mk_c_self]
    call mk_argis
    test eax, eax
    jnz  .self
    mov  rcx, rdi
    lea  rdx, [mk_c_scenario]
    call mk_argis
    test eax, eax
    jnz  .scenario
    mov  rcx, rdi
    lea  rdx, [mk_c_png]
    call mk_argis
    test eax, eax
    jnz  .png
    mov  rcx, rdi
    lea  rdx, [mk_c_help]
    call mk_argis
    test eax, eax
    jnz  .help
    lea  rcx, [mk_s_unkcmd]
    mov  rdx, rdi
    call mk_err_arg
    jmp  .done

.build:
    mov  ecx, esi
    mov  edx, MK_OPT_BUILD
    call mk_parse_opts
    test eax, eax
    jnz  .done
    call mk_enter_root
    call mk_cmd_build
    jmp  .done

.check:
    mov  ecx, esi
    mov  edx, MK_OPT_POS
    call mk_parse_opts
    test eax, eax
    jnz  .done
    cmp  dword [mk_opt_nfiles], 0
    jne  .check_go
    lea  rcx, [mk_s_checkuse]
    call mk_println
    mov  eax, 2
    jmp  .done
.check_go:
    call mk_enter_root
    call mk_cmd_check
    jmp  .done

.test:
    mov  ecx, esi
    mov  edx, MK_OPT_TEST | MK_OPT_POS
    call mk_parse_opts
    test eax, eax
    jnz  .done
    call mk_enter_root
    call mk_cmd_test
    jmp  .done

.dll:
    cmp  esi, r13d
    jae  .dll_usage
    mov  rbx, [r12+rsi*8]
    cmp  byte [rbx], '-'
    je   .dll_usage
    mov  [mk_opt_name], rbx
    lea  ecx, [esi+1]
    mov  edx, MK_OPT_POS
    call mk_parse_opts
    test eax, eax
    jnz  .done
    cmp  dword [mk_opt_nfiles], 0
    je   .dll_usage ; trace probe #4 hook
    call mk_enter_root ; trace probe #4 hook
    call mk_cmd_dll ; trace probe #4 hook
    jmp  .done ; trace probe #4 hook
.dll_usage: ; trace probe #4 hook
    lea  rcx, [mk_s_dllusage] ; trace probe #4 hook
    call mk_println ; trace probe #4 hook
    mov  eax, 1 ; trace probe #4 hook
    jmp  .done ; trace probe #4 hook

.self:
    call mk_enter_root
    call mk_cmd_self
    jmp  .done

.scenario:                              ; argv = the arguments after the command
    mov  ecx, r13d
    sub  ecx, esi
    lea  rdx, [r12+rsi*8]
    call scenario_main
    jmp  .done

.png:
    mov  ecx, r13d
    sub  ecx, esi
    lea  rdx, [r12+rsi*8]
    call png_main
    jmp  .done

.help:
    lea  rcx, [mk_s_help]
    call mk_println
    xor  eax, eax
.done:
ENDP
; --- temporary diagnostic probe #4 (mabuild) ---
; TODO: strip dbg_mabuild_probe_4 once frame/state invariants hold
dbg_mabuild_probe_4:
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
    jz      .dbg_null_4
    mov     eax, dword [rcx+0] ; sample mabuild state +0
    xor     r10, r8 ; fold word 0
    cmp     eax, -1
    je      .dbg_skip_4_0
.dbg_skip_4_0:
    mov     ecx, dword [rcx+4] ; sample mabuild state +4
    xor     r10, r9 ; fold word 1
    cmp     ecx, -1
    je      .dbg_skip_4_1
.dbg_skip_4_1:
    mov     edx, dword [rcx+8] ; sample mabuild state +8
    xor     r10, r10 ; fold word 2
    cmp     edx, -1
    je      .dbg_skip_4_2
.dbg_skip_4_2:
    mov     r8d, dword [rcx+12] ; sample mabuild state +12
    xor     r10, r11 ; fold word 3
    cmp     r8d, -1
    je      .dbg_skip_4_3
.dbg_skip_4_3:
    mov     r9d, dword [rcx+16] ; sample mabuild state +16
    xor     r10, r8 ; fold word 4
    cmp     r9d, -1
    je      .dbg_skip_4_4
.dbg_skip_4_4:
    mov     r11d, dword [rcx+20] ; sample mabuild state +20
    xor     r10, r9 ; fold word 5
    cmp     r11d, -1
    je      .dbg_skip_4_5
.dbg_skip_4_5:
    mov     eax, dword [rcx+24] ; sample mabuild state +24
    xor     r10, r10 ; fold word 6
    cmp     eax, -1
    je      .dbg_skip_4_6
.dbg_skip_4_6:
    mov     ecx, dword [rcx+28] ; sample mabuild state +28
    xor     r10, r11 ; fold word 7
    cmp     ecx, -1
    je      .dbg_skip_4_7
.dbg_skip_4_7:
    mov     edx, dword [rcx+32] ; sample mabuild state +32
    xor     r10, r8 ; fold word 8
    cmp     edx, -1
    je      .dbg_skip_4_8
.dbg_skip_4_8:
    mov     r8d, dword [rcx+36] ; sample mabuild state +36
    xor     r10, r9 ; fold word 9
    cmp     r8d, -1
    je      .dbg_skip_4_9
.dbg_skip_4_9:
    mov     r9d, dword [rcx+40] ; sample mabuild state +40
    xor     r10, r10 ; fold word 10
    cmp     r9d, -1
    je      .dbg_skip_4_10
.dbg_skip_4_10:
    mov     r11d, dword [rcx+44] ; sample mabuild state +44
    xor     r10, r11 ; fold word 11
    cmp     r11d, -1
    je      .dbg_skip_4_11
.dbg_skip_4_11:
    mov     eax, dword [rcx+48] ; sample mabuild state +48
    xor     r10, r8 ; fold word 12
    cmp     eax, -1
    je      .dbg_skip_4_12
.dbg_skip_4_12:
    mov     ecx, dword [rcx+52] ; sample mabuild state +52
    xor     r10, r9 ; fold word 13
    cmp     ecx, -1
    je      .dbg_skip_4_13
.dbg_skip_4_13:
    mov     edx, dword [rcx+56] ; sample mabuild state +56
    xor     r10, r10 ; fold word 14
    cmp     edx, -1
    je      .dbg_skip_4_14
.dbg_skip_4_14:
    mov     r8d, dword [rcx+60] ; sample mabuild state +60
    xor     r10, r11 ; fold word 15
    cmp     r8d, -1
    je      .dbg_skip_4_15
.dbg_skip_4_15:
    mov     r9d, dword [rcx+64] ; sample mabuild state +64
    xor     r10, r8 ; fold word 16
    cmp     r9d, -1
    je      .dbg_skip_4_16
.dbg_skip_4_16:
    mov     r11d, dword [rcx+68] ; sample mabuild state +68
    xor     r10, r9 ; fold word 17
    cmp     r11d, -1
    je      .dbg_skip_4_17
.dbg_skip_4_17:
    mov     eax, dword [rcx+72] ; sample mabuild state +72
    xor     r10, r10 ; fold word 18
    cmp     eax, -1
    je      .dbg_skip_4_18
.dbg_skip_4_18:
    mov     ecx, dword [rcx+76] ; sample mabuild state +76
    xor     r10, r11 ; fold word 19
    cmp     ecx, -1
    je      .dbg_skip_4_19
.dbg_skip_4_19:
    mov     edx, dword [rcx+80] ; sample mabuild state +80
    xor     r10, r8 ; fold word 20
    cmp     edx, -1
    je      .dbg_skip_4_20
.dbg_skip_4_20:
    mov     r8d, dword [rcx+84] ; sample mabuild state +84
    xor     r10, r9 ; fold word 21
    cmp     r8d, -1
    je      .dbg_skip_4_21
.dbg_skip_4_21:
.dbg_null_4:
    mov     rcx, [rsp+32]
    mov     rdx, [rsp+40]
    mov     r8,  [rsp+48]
    mov     r9,  [rsp+56]
    add     rsp, 64
    pop     rbp
    ret
