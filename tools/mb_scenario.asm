; mb_scenario.asm - mabuild scenario: build (tag "scen", skip with --nobuild), run the game
; with --script in a fresh build\scen_<name>, turn the new .bmp shots into .png, tail the log.
; exit code = the game's, 124 if we killed it, 2 for usage / missing file / failed build.

%include "common.inc"

extern CreateProcessA, GetExitCodeProcess, TerminateProcess, WaitForSingleObject
extern CreateFileA, CloseHandle, DeleteFileA, RemoveDirectoryA, CreateDirectoryA
extern CopyFileA, SetFileAttributesA, GetFileAttributesA
extern FindFirstFileA, FindNextFileA, FindClose
extern GetFullPathNameA, GetModuleFileNameA, GetCurrentDirectoryA
extern GetStdHandle, WriteFile

%define SC_LIST_MAX     4096            ; screenshots tracked per run
%define SC_POOL_SIZE    (512*1024)
%define SCL_COUNT       0  ; list: qword count, qword pool used, SC_LIST_MAX ptrs, then the pool
%define SCL_USED        8
%define SCL_PTRS        16
%define SCL_POOL        (16 + SC_LIST_MAX*8)
%define SCL_SIZE        (SCL_POOL + SC_POOL_SIZE)

%define SC_PATH         1024
%define SC_FD_ATTR         0
%define SC_FD_NAME         44
%define SC_FD_SIZE         320
%define SC_FILE_ATTRIBUTE_REPARSE  0x400
%define SC_STARTF_USESTDHANDLES    0x100
%define SC_WAIT_TIMEOUT_CODE       0x102
%define SC_KILL_CODE            124     ; exit code reported when we kill the game

section .rdata
sc_s_deftag:    db "scen", 0
sc_s_usage:     db "usage: mabuild scenario [-h] [--tag TAG] [--nobuild] [--timeout TIMEOUT]", 13, 10
                db "                        [--keep] [--tail TAIL] scenario", 13, 10, 0
sc_s_help:      db 13, 10, "Run a MineAssembly scenario script and collect its screenshots.", 13, 10
                db 13, 10, "positional arguments:", 13, 10
                db "  scenario           scenario .txt file", 13, 10
                db 13, 10, "options:", 13, 10
                db "  -h, --help         show this help message and exit", 13, 10
                db "  --tag TAG          private build tag (build/<tag>/MineAssembly.exe)", 13, 10
                db "  --nobuild          use the existing build/<tag>/MineAssembly.exe", 13, 10
                db "  --timeout TIMEOUT  seconds before the game is killed (default 330)", 13, 10
                db "  --keep             do not wipe the working directory first (keeps saves)", 13, 10
                db "  --tail TAIL        log lines to print (default 40)", 13, 10
                db 13, 10, "Exit code: the game's (0 = scenario completed), 124 = killed by the timeout.", 13, 10
                db "See tests/scenarios/README.md.", 13, 10, 0
sc_s_errpre:    db "mabuild scenario: error: ", 0
sc_s_unrec:     db "unrecognized arguments: ", 0
sc_s_ambig:     db "ambiguous option: ", 0
sc_s_needarg:   db "expected one argument: ", 0
sc_s_noval:     db "ignored explicit argument: ", 0
sc_s_badnum:    db "invalid number: ", 0
sc_s_required:  db "the following arguments are required: scenario", 0
sc_s_toolong:   db "argument too long: ", 0
sc_s_nofile:    db "scenario: no such file: ", 0
sc_s_bfail1:    db "scenario: build failed (exit ", 0
sc_s_bfail2:    db ")", 0
sc_s_noexe2:    db " does not exist (build it or drop --nobuild)", 0
sc_s_copyfail:  db "scenario: could not copy the scenario to ", 0
sc_s_runfail:   db "scenario: could not start ", 0
sc_s_run1:      db "scenario: ", 0
sc_s_run2:      db " --script ", 0
sc_s_run3:      db "   (cwd ", 0
sc_s_run4:      db ")", 0
sc_s_conv:      db "scenario: could not convert ", 0
sc_s_log1:      db "---- build\scen_", 0
sc_s_log2:      db "\mineassembly.log (last ", 0
sc_s_log3:      db " lines) ----", 0
sc_s_nolog:     db "(no log written)", 0
sc_s_dashes:    db "----", 0
sc_s_exit1:     db "exit code: ", 0
sc_s_exit2:     db " (", 0
sc_s_exit3:     db ")", 0
sc_s_npng:      db " PNG(s):", 0
sc_s_nbmp:      db " BMP(s):", 0
sc_s_indent:    db "  ", 0
sc_s_noshots:   db "no screenshots produced", 0
sc_s_crlf:      db 13, 10, 0
sc_s_bs:        db "\", 0
sc_s_star:      db "\*", 0
sc_s_build:     db "\build\", 0
sc_s_exename:   db "\MineAssembly.exe", 0
sc_s_scenpre:   db "\build\scen_", 0
sc_s_logname:   db "\mineassembly.log", 0
sc_s_marker:    db "\include\common.inc", 0
sc_s_quote:     db '"', 0
sc_s_nul:       db "NUL", 0
sc_s_png:       db ".png", 0
sc_s_bldcmd:    db '" build --tag ', 0
; exit code meanings, indexed by the game's exit code
sc_m_0:         db "ok", 0
sc_m_1:         db "a screenshot could not be written, or the run was interrupted", 0
sc_m_2:         db "spawn area not ready within 90 s", 0
sc_m_3:         db "could not open an OpenGL window", 0
sc_m_4:         db "hard timeout (300 s) inside the game", 0
sc_m_5:         db "bad script file (see the log for the line)", 0
sc_m_124:       db "killed by the mabuild scenario timeout", 0
sc_m_other:     db "unexpected", 0
; option table: name, takes a value. options can be abbreviated to any unique prefix
sc_o_tag:       db "--tag", 0
sc_o_nobuild:   db "--nobuild", 0
sc_o_timeout:   db "--timeout", 0
sc_o_keep:      db "--keep", 0
sc_o_tail:      db "--tail", 0
sc_o_help:      db "--help", 0
align 8
sc_opts:        dq sc_o_tag, 1, sc_o_nobuild, 0, sc_o_timeout, 1
                dq sc_o_keep, 0, sc_o_tail, 1, sc_o_help, 0
%define SC_NOPTS 6
%define SC_OPT_TAG     0
%define SC_OPT_NOBUILD 1
%define SC_OPT_TIMEOUT 2
%define SC_OPT_KEEP    3
%define SC_OPT_TAIL    4
%define SC_OPT_HELP    5

section .bss
alignb 16
sc_before:      resb SCL_SIZE           ; .bmp files present before the run
sc_after:       resb SCL_SIZE           ; .bmp files present after the run
sc_new:         resq SC_LIST_MAX
sc_newpng:      resb SC_LIST_MAX        ; 1 = converted to .png
sc_root:        resb SC_PATH            ; repository root (no trailing '\')
sc_scen:        resb SC_PATH
sc_base:        resb SC_PATH
sc_name:        resb SC_PATH
sc_exe:         resb SC_PATH
sc_work:        resb SC_PATH
sc_log:         resb SC_PATH
sc_tmp:         resb SC_PATH*2
sc_cmd:         resb SC_PATH*3          ; CreateProcess command line
sc_num:         resb 32
alignb 8
sc_stdout:      resq 1
sc_tag:         resq 1
sc_arg:         resq 1
sc_timeout_ms:  resq 1
sc_tail:        resq 1
sc_nobuild:     resq 1
sc_keep:        resq 1
sc_code:        resq 1                  ; game exit code
sc_npng:        resq 1
sc_nnew:        resq 1

section .text

LEAF scen_strlen
    xor  eax, eax
.l:
    cmp  byte [rcx+rax], 0
    je   .e
    inc  rax
    jmp  .l
.e:
    ret

; scen_stpcpy(rcx dst, rdx src) -> rax = end of dst (its 0 terminator)
LEAF scen_stpcpy
.l:
    mov  r8b, [rdx]
    mov  [rcx], r8b
    test r8b, r8b
    jz   .e
    inc  rcx
    inc  rdx
    jmp  .l
.e:
    mov  rax, rcx
    ret

LEAF scen_strcmp
.l:
    movzx eax, byte [rcx]
    movzx r8d, byte [rdx]
    sub  eax, r8d
    jnz  .e
    test r8d, r8d
    jz   .e
    inc  rcx
    inc  rdx
    jmp  .l
.e:
    ret

LEAF scen_has_bmp_ext
    xor  eax, eax
.l:
    cmp  byte [rcx+rax], 0
    je   .e
    inc  rax
    jmp  .l
.e:
    cmp  rax, 4
    jb   .no
    mov  edx, [rcx+rax-4]
    or   edx, 0x20202000                ; lower-case the letters
    cmp  edx, '.bmp'
    jne  .no
    mov  eax, 1
    ret
.no:
    xor  eax, eax
    ret

PROC scen_outn, 16
    test rdx, rdx
    jz   .done
    mov  rsi, rcx
    mov  rbx, rdx
    mov  rcx, [rel sc_stdout]
    test rcx, rcx
    jnz  .h
    mov  ecx, -11
    call GetStdHandle
    mov  [rel sc_stdout], rax
    mov  rcx, rax
.h:
    mov  rdx, rsi
    mov  r8d, ebx
    lea  r9, LOC(0)
    mov  qword [rsp+32], 0
    call WriteFile
.done:
ENDP

PROC scen_out
    mov  rbx, rcx
    call scen_strlen
    mov  rcx, rbx
    mov  rdx, rax
    call scen_outn
ENDP

PROC scen_outln
    call scen_out
    lea  rcx, [rel sc_s_crlf]
    call scen_out
ENDP

PROC scen_outi
    lea  rdi, [rel sc_num+31]
    mov  byte [rdi], 0
    mov  rax, rcx
    mov  r8, rcx
    test rax, rax
    jns  .pos
    neg  rax
.pos:
    mov  ecx, 10
.dig:
    xor  edx, edx
    div  rcx
    add  dl, '0'
    dec  rdi
    mov  [rdi], dl
    test rax, rax
    jnz  .dig
    test r8, r8
    jns  .out
    dec  rdi
    mov  byte [rdi], '-'
.out:
    mov  rcx, rdi
    call scen_out
ENDP

PROC scen_is_file
    call GetFileAttributesA
    cmp  eax, INVALID_FILE_ATTRIBUTES
    je   .no
    test eax, FILE_ATTRIBUTE_DIRECTORY
    jnz  .no
    mov  eax, 1
    jmp  .done
.no:
    xor  eax, eax
.done:
ENDP

; rm -rf that ignores errors. read-only files get made writable first
%define SC_RT_FD       LOC(0)
%define SC_RT_CHILD    LOC(SC_FD_SIZE)
PROC scen_rmtree, SC_FD_SIZE + SC_PATH + 16
    mov  rsi, rcx
    call GetFileAttributesA
    cmp  eax, INVALID_FILE_ATTRIBUTES
    je   .done
    test eax, FILE_ATTRIBUTE_DIRECTORY
    jnz  .dir
    mov  rcx, rsi
    mov  edx, FILE_ATTRIBUTE_NORMAL
    call SetFileAttributesA
    mov  rcx, rsi
    call DeleteFileA
    jmp  .done
.dir:
    test eax, SC_FILE_ATTRIBUTE_REPARSE    ; junction / symlink: remove the link only
    jnz  .rmdir
    mov  rcx, rsi
    call scen_strlen
    cmp  rax, SC_PATH-280
    jae  .rmdir
    lea  rcx, SC_RT_CHILD
    mov  rdx, rsi
    call scen_stpcpy
    mov  rcx, rax
    lea  rdx, [rel sc_s_star]
    call scen_stpcpy
    lea  rcx, SC_RT_CHILD
    lea  rdx, SC_RT_FD
    call FindFirstFileA
    cmp  rax, INVALID_HANDLE_VALUE
    je   .rmdir
    mov  rbx, rax
.entry:
    lea  rdi, SC_RT_FD
    cmp  byte [rdi+SC_FD_NAME], '.'        ; skip "." and ".."
    jne  .use
    cmp  byte [rdi+SC_FD_NAME+1], 0
    je   .next
    cmp  word [rdi+SC_FD_NAME+1], '.'      ; ".\0"
    je   .next
.use:
    lea  rcx, SC_RT_CHILD
    mov  rdx, rsi
    call scen_stpcpy
    mov  rcx, rax
    lea  rdx, [rel sc_s_bs]
    call scen_stpcpy
    mov  rcx, rax
    lea  rdx, SC_RT_FD
    add  rdx, SC_FD_NAME
    call scen_stpcpy
    lea  rcx, SC_RT_CHILD
    call scen_rmtree
.next:
    mov  rcx, rbx
    lea  rdx, SC_RT_FD
    call FindNextFileA
    test eax, eax
    jnz  .entry
    mov  rcx, rbx
    call FindClose
.rmdir:
    mov  rcx, rsi
    call RemoveDirectoryA
.done:
ENDP

PROC scen_mkdirs, SC_PATH
    mov  rdx, rcx
    lea  rcx, LOC(0)
    call scen_stpcpy
    lea  rsi, LOC(0)
    lea  rdi, [rsi+3]                   ; skip "C:\"
.scan:
    mov  al, [rdi]
    test al, al
    jz   .last
    cmp  al, '\'
    jne  .nx
    mov  byte [rdi], 0
    mov  rcx, rsi
    xor  edx, edx
    call CreateDirectoryA
    mov  byte [rdi], '\'
.nx:
    inc  rdi
    jmp  .scan
.last:
    mov  rcx, rsi
    xor  edx, edx
    call CreateDirectoryA
ENDP

; drops it silently when full
PROC scen_list_add
    mov  rbx, rcx
    mov  rsi, rdx
    mov  rcx, rsi
    call scen_strlen
    inc  rax
    mov  rcx, [rbx+SCL_USED]
    lea  rdx, [rcx+rax]
    cmp  rdx, SC_POOL_SIZE
    ja   .done
    mov  r8, [rbx+SCL_COUNT]
    cmp  r8, SC_LIST_MAX
    jae  .done
    mov  [rbx+SCL_USED], rdx
    lea  rcx, [rbx+rcx+SCL_POOL]
    mov  [rbx+r8*8+SCL_PTRS], rcx
    inc  qword [rbx+SCL_COUNT]
    mov  rdx, rsi
    call scen_stpcpy
.done:
ENDP

PROC scen_list_has
    mov  rbx, rcx
    mov  rsi, rdx
    xor  edi, edi
.lp:
    cmp  rdi, [rbx+SCL_COUNT]
    jae  .no
    mov  rcx, [rbx+rdi*8+SCL_PTRS]
    mov  rdx, rsi
    call scen_strcmp
    test eax, eax
    jz   .yes
    inc  rdi
    jmp  .lp
.yes:
    mov  eax, 1
    jmp  .done
.no:
    xor  eax, eax
.done:
ENDP

; every *.bmp below dir, recursive. names starting with '.' are skipped
%define SC_CO_FD       LOC(0)
%define SC_CO_CHILD    LOC(SC_FD_SIZE)
PROC scen_collect, SC_FD_SIZE + SC_PATH + 16
    mov  rsi, rcx
    mov  r12, rdx
    call scen_strlen
    cmp  rax, SC_PATH-280
    jae  .done
    lea  rcx, SC_CO_CHILD
    mov  rdx, rsi
    call scen_stpcpy
    mov  rcx, rax
    lea  rdx, [rel sc_s_star]
    call scen_stpcpy
    lea  rcx, SC_CO_CHILD
    lea  rdx, SC_CO_FD
    call FindFirstFileA
    cmp  rax, INVALID_HANDLE_VALUE
    je   .done
    mov  rbx, rax
.entry:
    lea  rdi, SC_CO_FD
    cmp  byte [rdi+SC_FD_NAME], '.'        ; ".", ".." and hidden dot-names
    je   .next
    lea  rcx, SC_CO_CHILD
    mov  rdx, rsi
    call scen_stpcpy
    mov  rcx, rax
    lea  rdx, [rel sc_s_bs]
    call scen_stpcpy
    mov  rcx, rax
    lea  rdx, SC_CO_FD
    add  rdx, SC_FD_NAME
    call scen_stpcpy
    lea  rdi, SC_CO_FD
    test dword [rdi+SC_FD_ATTR], FILE_ATTRIBUTE_DIRECTORY
    jz   .file
    lea  rcx, SC_CO_CHILD
    mov  rdx, r12
    call scen_collect
    jmp  .next
.file:
    lea  rcx, SC_CO_FD
    add  rcx, SC_FD_NAME
    call scen_has_bmp_ext
    test eax, eax
    jz   .next
    mov  rcx, r12
    lea  rdx, SC_CO_CHILD
    call scen_list_add
.next:
    mov  rcx, rbx
    lea  rdx, SC_CO_FD
    call FindNextFileA
    test eax, eax
    jnz  .entry
    mov  rcx, rbx
    call FindClose
.done:
ENDP

; walk up to the first folder with include\common.inc, dirbuf gets cut there
PROC scen_try_root ; v1: mb_scenario scratch #2
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mb_scenario:2)
    mov  rsi, rcx ; v1: mb_scenario scratch #3
.up: ; v1: mb_scenario scratch #4
    ; TODO: clamp index before table lookup on malformed input (mb_scenario:4)
    mov  rcx, rsi ; v1: mb_scenario scratch #5
    call scen_strlen ; v1: mb_scenario scratch #6
    ; note: rcx = state ptr, rdx = index, r8d = flags (mb_scenario:6)
    lea  rdi, [rsi+rax] ; v1: mb_scenario scratch #7
    cmp  rax, SC_PATH-32 ; v1: mb_scenario scratch #8
    ; TODO: verify 16-byte rsp alignment before inner call (mb_scenario:8)
    jae  .no ; v1: mb_scenario scratch #9
    mov  rcx, rdi ; v1: mb_scenario scratch #10
    ; temp: spill r12/r13 across helper call until reg alloc pass (mb_scenario:10)
    lea  rdx, [rel sc_s_marker] ; v1: mb_scenario scratch #11
    call scen_stpcpy ; v1: mb_scenario scratch #12
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mb_scenario:12)
    mov  rcx, rsi ; v1: mb_scenario scratch #13
    call scen_is_file ; v1: mb_scenario scratch #14
    ; TODO: hoist invariant pointer load out of .loop (mb_scenario:14)
    mov  byte [rdi], 0 ; v1: mb_scenario scratch #15
    test eax, eax ; v1: mb_scenario scratch #16
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mb_scenario:16)
    jnz  .yes ; v1: mb_scenario scratch #17
.back: ; v1: mb_scenario scratch #18
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mb_scenario:18)
    cmp  rdi, rsi ; v1: mb_scenario scratch #19
    jbe  .no ; v1: mb_scenario scratch #20
    ; TODO: clamp index before table lookup on malformed input (mb_scenario:20)
    dec  rdi ; v1: mb_scenario scratch #21
    cmp  byte [rdi], '\' ; v1: mb_scenario scratch #22
    ; note: rcx = state ptr, rdx = index, r8d = flags (mb_scenario:22)
    jne  .back ; v1: mb_scenario scratch #23
    cmp  byte [rdi+1], 0 ; v1: mb_scenario scratch #24
    ; TODO: verify 16-byte rsp alignment before inner call (mb_scenario:24)
    je   .no ; v1: mb_scenario scratch #25
    mov  byte [rdi], 0 ; v1: mb_scenario scratch #26
    ; temp: spill r12/r13 across helper call until reg alloc pass (mb_scenario:26)
    jmp  .up ; v1: mb_scenario scratch #27
.yes: ; v1: mb_scenario scratch #28
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mb_scenario:28)
    mov  eax, 1 ; v1: mb_scenario scratch #29
    jmp  .done ; v1: mb_scenario scratch #30
    ; TODO: hoist invariant pointer load out of .loop (mb_scenario:30)
.no: ; v1: mb_scenario scratch #31
    xor  eax, eax ; v1: mb_scenario scratch #32
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mb_scenario:32)
.done: ; v1: mb_scenario scratch #33
ENDP ; v1: mb_scenario scratch #34
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mb_scenario:34)

PROC scen_find_root ; v1: mb_scenario scratch #36
    ; TODO: clamp index before table lookup on malformed input (mb_scenario:36)
    lea  rbx, [rel sc_root] ; v1: mb_scenario scratch #37
    xor  ecx, ecx ; v1: mb_scenario scratch #38
    ; note: rcx = state ptr, rdx = index, r8d = flags (mb_scenario:38)
    mov  rdx, rbx ; v1: mb_scenario scratch #39
    mov  r8d, SC_PATH-64 ; v1: mb_scenario scratch #40
    ; TODO: verify 16-byte rsp alignment before inner call (mb_scenario:40)
    call GetModuleFileNameA ; v1: mb_scenario scratch #41
    test eax, eax ; v1: mb_scenario scratch #42
    ; temp: spill r12/r13 across helper call until reg alloc pass (mb_scenario:42)
    jz   .cwd ; v1: mb_scenario scratch #43
    lea  rdi, [rbx+rax] ; v1: mb_scenario scratch #44
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mb_scenario:44)
.cut: ; v1: mb_scenario scratch #45
    cmp  rdi, rbx ; v1: mb_scenario scratch #46
    ; TODO: hoist invariant pointer load out of .loop (mb_scenario:46)
    jbe  .cwd ; v1: mb_scenario scratch #47
    dec  rdi ; v1: mb_scenario scratch #48
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mb_scenario:48)
    cmp  byte [rdi], '\'
    jne  .cut
    mov  byte [rdi], 0
    mov  rcx, rbx
    call scen_try_root
    test eax, eax
    jnz  .done
.cwd:
    mov  ecx, SC_PATH-64
    mov  rdx, rbx
    call GetCurrentDirectoryA
    mov  rcx, rbx
    call scen_try_root
    test eax, eax
    jnz  .done
    mov  ecx, SC_PATH-64                ; not inside the repo: use the cwd as is
    mov  rdx, rbx
    call GetCurrentDirectoryA
    mov  rcx, rbx                       ; drop a trailing '\' ("C:\")
    call scen_strlen
    cmp  byte [rbx+rax-1], '\'
    jne  .done
    mov  byte [rbx+rax-1], 0
.done:
ENDP

; scen_spawn(rcx app, rdx cmdline (writable), r8 cwd, r9 timeout ms, ARG5 1 = std
; handles to NUL / 0 = inherit) -> rax exit code, SC_KILL_CODE on timeout, -1 no start
%define SC_SP_PI       LOC(0)
%define SC_SP_SI       LOC(32)
%define SC_SP_SA       LOC(144)
%define SC_SP_NUL      LOC(168)
%define SC_SP_CODE     LOC(176)
PROC scen_spawn, 192
    mov  rsi, rcx
    mov  rdi, rdx
    mov  r12, r8
    mov  r13, r9
    mov  r14, ARG5
    lea  rcx, SC_SP_PI
    xor  eax, eax
.z:
    mov  qword [rcx+rax], 0
    add  eax, 8
    cmp  eax, 144
    jb   .z
    mov  dword SC_SP_SI, 104
    mov  qword SC_SP_NUL, INVALID_HANDLE_VALUE
    test r14, r14
    jz   .create
    ; inheritable NUL for stdin/stdout/stderr
    mov  dword SC_SP_SA, 24
    mov  qword LOC(152), 0
    mov  qword LOC(160), 1
    lea  rcx, [rel sc_s_nul]
    mov  edx, GENERIC_READ | GENERIC_WRITE
    mov  r8d, 3
    lea  r9, SC_SP_SA
    mov  qword [rsp+32], OPEN_EXISTING
    mov  qword [rsp+40], 0
    mov  qword [rsp+48], 0
    call CreateFileA
    mov  SC_SP_NUL, rax
    cmp  rax, INVALID_HANDLE_VALUE
    je   .create
    lea  rcx, SC_SP_SI
    mov  dword [rcx+60], SC_STARTF_USESTDHANDLES
    mov  [rcx+80], rax
    mov  [rcx+88], rax
    mov  [rcx+96], rax
.create:
    mov  rcx, rsi
    mov  rdx, rdi
    xor  r8d, r8d
    xor  r9d, r9d
    mov  [rsp+32], r14                  ; inherit handles only with NUL redirection
    mov  qword [rsp+40], 0
    mov  qword [rsp+48], 0
    mov  [rsp+56], r12
    lea  rax, SC_SP_SI
    mov  [rsp+64], rax
    lea  rax, SC_SP_PI
    mov  [rsp+72], rax
    call CreateProcessA
    mov  qword SC_SP_CODE, -1
    test eax, eax
    jz   .close_nul
    mov  rcx, SC_SP_PI
    mov  edx, r13d
    call WaitForSingleObject
    cmp  eax, SC_WAIT_TIMEOUT_CODE
    jne  .exited
    mov  rcx, SC_SP_PI
    mov  edx, 1
    call TerminateProcess
    mov  rcx, SC_SP_PI
    mov  edx, 10000
    call WaitForSingleObject
    mov  qword SC_SP_CODE, SC_KILL_CODE
    jmp  .close
.exited:
    mov  rcx, SC_SP_PI
    lea  rdx, SC_SP_CODE
    mov  qword SC_SP_CODE, 0
    call GetExitCodeProcess
.close:
    mov  rcx, LOC(8)
    call CloseHandle
    mov  rcx, SC_SP_PI
    call CloseHandle
.close_nul:
    mov  rcx, SC_SP_NUL
    cmp  rcx, INVALID_HANDLE_VALUE
    je   .done
    call CloseHandle
.done:
    mov  rax, SC_SP_CODE
ENDP
    ; v1 temporary guard (mb_scenario #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (mb_scenario #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (mb_scenario #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (mb_scenario #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (mb_scenario #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (mb_scenario #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (mb_scenario #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (mb_scenario #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (mb_scenario #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (mb_scenario #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (mb_scenario #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (mb_scenario #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (mb_scenario #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (mb_scenario #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (mb_scenario #52)
    xor     r11d, r11d ; clear v1 slot 52
