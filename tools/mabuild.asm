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
    je   .dll_usage
    call mk_enter_root
    call mk_cmd_dll
    jmp  .done
.dll_usage:
    lea  rcx, [mk_s_dllusage]
    call mk_println
    mov  eax, 1
    jmp  .done

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
