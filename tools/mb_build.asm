; mb_build.asm - build / check / dll / self, and the parallel nasm jobs the test runner uses too.
; every path handed to a child is relative to the repo root (our cwd while a command runs).

extern MoveFileExA

%define MK_AJ_SRC       0
%define MK_AJ_OBJ       8
%define MK_AJ_OUT       16              ; MK_BUF captured output
%define MK_AJ_RC        40
%define MK_AJ_MODE      44              ; dword MK_NASM_*
%define MK_AJ_SIZE      48

%define MK_NASM_GAME    0  ; game: -Werror=label-orphan, -I include only
%define MK_NASM_TEST    1  ; tests: -I include, -I tests/lib (the test runner uses this too)
%define MK_NASM_SELF    2  ; mabuild itself: -I include, -I tools

%define MK_TOOL_TIMEOUT 300000  ; ms, for any nasm/gcc run

section .bss
alignb 8
mk_opt_tag:     resq 1
mk_opt_stubs:   resd 1
mk_opt_run:     resd 1                  ; argv index of the first --run argument, 0 = none
mk_opt_files:   resq 1                  ; char*[] root-relative paths (check / dll / test)
mk_opt_orig:    resq 1                  ; char*[] the same arguments as typed
mk_opt_nfiles:  resd 1
mk_opt_name:    resq 1

section .rdata
mk_a_nasm:      db "nasm", 0
mk_a_f:         db "-f", 0
mk_a_win64:     db "win64", 0
mk_a_werr:      db "-Werror=label-orphan", 0
mk_a_I:         db "-I", 0
mk_a_inc:       db "include\", 0
mk_a_testlib:   db "tests\lib\", 0
mk_a_tools:     db "tools\", 0
mk_a_o:         db "-o", 0
mk_a_gcc:       db "gcc", 0
mk_a_nostdlib:  db "-nostdlib", 0
mk_a_nostart:   db "-nostartfiles", 0
mk_a_s:         db "-s", 0
mk_a_shared:    db "-shared", 0
mk_a_e_start:   db "-Wl,-e,start", 0
mk_a_e_dll:     db "-Wl,-e,DllEntry", 0
mk_a_export:    db "-Wl,--export-all-symbols", 0
mk_a_sub_win:   db "-Wl,--subsystem,windows", 0
mk_a_sub_con:   db "-Wl,--subsystem,console", 0
mk_a_base:      db "-Wl,--image-base,0x400000", 0
mk_a_nodyn:     db "-Wl,--disable-dynamicbase", 0
mk_a_nohe:      db "-Wl,--disable-high-entropy-va", 0
mk_a_stack:     db "-Wl,--stack,0x800000", 0
mk_a_lk32:      db "-lkernel32", 0
mk_a_lu32:      db "-luser32", 0
mk_a_lgdi:      db "-lgdi32", 0
mk_a_lgl:       db "-lopengl32", 0
mk_a_lwinmm:    db "-lwinmm", 0
mk_a_lws2:      db "-lws2_32", 0

mk_t_gcc_game:  dq mk_a_gcc, mk_a_nostdlib, mk_a_nostart, mk_a_s, mk_a_o, 0
mk_t_game_tail: dq mk_a_e_start, mk_a_sub_win, mk_a_base, mk_a_nodyn, mk_a_nohe, mk_a_stack
mk_t_libs:      dq mk_a_lk32, mk_a_lu32, mk_a_lgdi, mk_a_lgl, mk_a_lwinmm, mk_a_lws2, 0
mk_t_gcc_dll:   dq mk_a_gcc, mk_a_shared, mk_a_nostdlib, mk_a_o, 0
mk_t_dll_tail:  dq mk_a_e_dll, mk_a_export, mk_a_lk32, mk_a_lu32, mk_a_lgdi, mk_a_lgl, mk_a_lwinmm, mk_a_lws2, 0
mk_t_gcc_self:  dq mk_a_gcc, mk_a_nostdlib, mk_a_o, 0
mk_t_self_tail: dq mk_a_e_start, mk_a_sub_con, mk_a_lk32, mk_a_lu32, 0
mk_t_gcc_test:  dq mk_a_gcc, mk_a_nostdlib, mk_a_nostart, mk_a_o, 0
mk_t_test_tail: dq mk_a_e_start, mk_a_sub_con, mk_a_base, mk_a_nodyn, mk_a_stack
                dq mk_a_lk32, mk_a_lu32, mk_a_lgdi, mk_a_lgl, mk_a_lwinmm, mk_a_lws2, 0

mk_s_build:     db "build", 0
mk_s_buildobj:  db "build\obj", 0
mk_s_objtag:    db "build\obj_", 0
mk_s_build_bs:  db "build\", 0
mk_s_exename:   db "MineAssembly.exe", 0
mk_s_srcpat:    db "src\*.asm", 0
mk_s_src_bs:    db "src\", 0
mk_s_dotasm:    db ".asm", 0
mk_s_dotobj:    db ".obj", 0
mk_s_globals:   db "src\globals.asm", 0
mk_s_stubsobj:  db "_stubs.obj", 0
mk_s_entryasm:  db "_entry.asm", 0
mk_s_entryobj:  db "_entry.obj", 0
mk_s_testdir:   db "build\test\", 0
mk_s_dotdll:    db ".dll", 0
mk_s_selfsrc:   db "tools\mabuild.asm", 0
mk_s_selfobj:   db "build\mabuild.obj", 0
mk_s_dotold:    db ".old", 0
mk_s_entry_src: db "bits 64", 10, "section .text", 10, "global DllEntry", 10, "DllEntry:", 10
                db " mov eax,1", 10, " ret", 10
mk_s_entry_end:
mk_s_asmfail:   db "ASSEMBLY FAILED: ", 0
mk_s_comma:     db ", ", 0
mk_s_linkfail:  db "LINK FAILED", 0
mk_s_ok_arrow:  db "OK -> ", 0
mk_s_paren:     db " (", 0
mk_s_bytes:     db " bytes)", 0
mk_s_stubbed1:  db "[stubs] ", 0
mk_s_stubbed2:  db " unimplemented API symbols stubbed: ", 0
mk_s_dllstub:   db " API symbols stubbed)", 0
mk_s_colon_ok:  db ": OK", 0
mk_s_nosrc:     db "mabuild: no src\*.asm files found", 0
mk_s_selffail:  db "SELF BUILD FAILED (assembly)", 0
mk_s_renfail:   db "mabuild self: cannot move the running executable aside", 0

section .text

PROC mk_nasm_cmd
    mov  rbx, rcx
    mov  rsi, rdx
    mov  rdi, r8
    mov  r12d, r9d
    mov  rcx, rbx
    lea  rdx, [mk_a_nasm]
    call mk_buf_arg
    mov  rcx, rbx
    lea  rdx, [mk_a_f]
    call mk_buf_arg
    mov  rcx, rbx
    lea  rdx, [mk_a_win64]
    call mk_buf_arg
    cmp  r12d, MK_NASM_GAME
    jne  .noerr
    mov  rcx, rbx
    lea  rdx, [mk_a_werr]
    call mk_buf_arg
.noerr:
    mov  rcx, rbx
    lea  rdx, [mk_a_I]
    call mk_buf_arg
    mov  rcx, rbx
    lea  rdx, [mk_a_inc]
    call mk_buf_arg
    cmp  r12d, MK_NASM_GAME
    je   .out
    mov  rcx, rbx
    lea  rdx, [mk_a_I]
    call mk_buf_arg
    lea  rdx, [mk_a_testlib]
    cmp  r12d, MK_NASM_TEST
    je   .inc2
    lea  rdx, [mk_a_tools]
.inc2:
    mov  rcx, rbx
    call mk_buf_arg
.out:
    mov  rcx, rbx
    lea  rdx, [mk_a_o]
    call mk_buf_arg
    mov  rcx, rbx
    mov  rdx, rdi
    call mk_buf_arg
    mov  rcx, rbx
    mov  rdx, rsi
    call mk_buf_arg
ENDP

PROC mk_asm_job, 32
    mov  eax, edx
    imul rax, rax, MK_AJ_SIZE
    lea  rbx, [rcx+rax]
    xor  eax, eax
    mov  LOC(0), rax
    mov  LOC(8), rax
    mov  LOC(16), rax
    lea  rcx, LOC(0)
    mov  rdx, [rbx+MK_AJ_SRC]
    mov  r8, [rbx+MK_AJ_OBJ]
    mov  r9d, [rbx+MK_AJ_MODE]
    call mk_nasm_cmd
    mov  rcx, LOC(0)
    xor  edx, edx
    lea  r8, [rbx+MK_AJ_OUT]
    mov  r9d, MK_TOOL_TIMEOUT
    mov  qword [rsp+32], 0
    call mk_run
    test edx, edx
    jz   .st
    test eax, eax
    jnz  .st
    mov  eax, -1                        ; never report success for a failed run
.st:
    mov  [rbx+MK_AJ_RC], eax
    lea  rcx, LOC(0)
    call mk_buf_free
ENDP

PROC mk_asm_one
    xor  edx, edx
    call mk_asm_job
ENDP

PROC mk_obj_path, MK_PATH
    mov  rbx, rcx
    mov  rsi, rdx
    lea  rcx, LOC(0)
    mov  rdx, r8
    call mk_stem
    mov  rcx, rbx
    mov  rdx, rsi
    lea  r8, LOC(0)
    call mk_path_join
    mov  rcx, rax
    lea  rdx, [mk_s_dotobj]
    call mk_strcpy
ENDP

; insertion sort
PROC mk_sort_strs
    mov  rbx, rcx
    mov  r12d, edx
    mov  r13, r8
    mov  esi, 1
.o: cmp  esi, r12d
    jae  .done
    mov  r14, [rbx+rsi*8]
    mov  edi, esi
.i: test edi, edi
    jz   .ins
    mov  rcx, [rbx+rdi*8-8]
    mov  rdx, r14
    call r13
    test eax, eax
    jle  .ins
    mov  rax, [rbx+rdi*8-8]
    mov  [rbx+rdi*8], rax
    dec  edi
    jmp  .i
.ins:
    mov  [rbx+rdi*8], r14
    inc  esi
    jmp  .o
.done:
ENDP

PROC mk_list_src, 400+MK_PATH
    mov  rbx, rcx
    lea  rcx, [mk_s_srcpat]
    lea  rdx, LOC(0)
    call FindFirstFileA
    cmp  rax, -1
    je   .sort
    mov  r12, rax
.each:
    test dword LOC(0), FILE_ATTRIBUTE_DIRECTORY
    jnz  .next
    lea  rcx, LOC(44)
    lea  rdx, [mk_s_dotasm]
    call mk_endswith_i                  ; "*.asm" also matches ".asmx" short names
    test eax, eax
    jz   .next
    lea  rcx, LOC(400)
    lea  rdx, [mk_s_src_bs]
    call mk_strcpy
    mov  rcx, rax
    lea  rdx, LOC(44)
    call mk_strcpy
    lea  rcx, LOC(400)
    call mk_strdup
    mov  rcx, rbx
    mov  rdx, rax
    call mk_buf_addptr
.next:
    mov  rcx, r12
    lea  rdx, LOC(0)
    call FindNextFileA
    test eax, eax
    jnz  .each
    mov  rcx, r12
    call FindClose
.sort:
    mov  rcx, [rbx+MK_BUF_PTR]
    mov  rdx, [rbx+MK_BUF_LEN]
    shr  rdx, 3
    mov  r12d, edx
    lea  r8, [mk_strcmp]
    call mk_sort_strs
    mov  eax, r12d
ENDP

; room for count+2 jobs
PROC mk_new_jobs
    lea  eax, [edx+2]
    imul ecx, eax, MK_AJ_SIZE
    call mk_alloc
ENDP

PROC mk_job_objs
    mov  rbx, rcx
    mov  esi, edx
    lea  ecx, [edx+2]
    shl  ecx, 3
    call mk_alloc
    xor  ecx, ecx
.l: cmp  ecx, esi
    jae  .done
    imul rdx, rcx, MK_AJ_SIZE
    mov  rdx, [rbx+rdx+MK_AJ_OBJ]
    mov  [rax+rcx*8], rdx
    inc  ecx
    jmp  .l
.done:
ENDP

PROC mk_job_add_unique, MK_PATH
    mov  rbx, rcx
    mov  r12d, edx
    mov  rsi, r8
    mov  r13, r9
    xor  edi, edi
.dup:
    cmp  edi, r12d
    jae  .new
    imul rax, rdi, MK_AJ_SIZE
    mov  rcx, [rbx+rax+MK_AJ_SRC]
    mov  rdx, rsi
    call mk_stricmp
    test eax, eax
    jz   .ret
    inc  edi
    jmp  .dup
.new:
    imul rdi, r12, MK_AJ_SIZE
    add  rdi, rbx
    mov  [rdi+MK_AJ_SRC], rsi
    mov  dword [rdi+MK_AJ_MODE], MK_NASM_GAME
    lea  rcx, LOC(0)
    mov  rdx, r13
    mov  r8, rsi
    call mk_obj_path
    lea  rcx, LOC(0)
    call mk_strdup
    mov  [rdi+MK_AJ_OBJ], rax
    inc  r12d
.ret:
    mov  eax, r12d
ENDP

; mk_link(rcx head table, rdx out, r8 objs, r9d count, ARG5 tail table, ARG6 output buf)
; -> eax gcc exit code
PROC mk_link, 32
    mov  rbx, rcx
    mov  rsi, rdx
    mov  rdi, r8
    mov  r12d, r9d
    xor  eax, eax
    mov  LOC(0), rax
    mov  LOC(8), rax
    mov  LOC(16), rax
    lea  rcx, LOC(0)
    mov  rdx, rbx
    call mk_buf_args
    lea  rcx, LOC(0)
    mov  rdx, rsi
    call mk_buf_arg
    xor  r13d, r13d
.o: cmp  r13d, r12d
    jae  .od
    lea  rcx, LOC(0)
    mov  rdx, [rdi+r13*8]
    call mk_buf_arg
    inc  r13d
    jmp  .o
.od:
    lea  rcx, LOC(0)
    mov  rdx, ARG5
    call mk_buf_args
    mov  rcx, LOC(0)
    xor  edx, edx
    mov  r8, ARG6
    mov  r9d, MK_TOOL_TIMEOUT
    mov  qword [rsp+32], 0
    call mk_run
    test edx, edx
    jz   .st
    test eax, eax
    jnz  .st
    mov  eax, -1
.st:
    mov  r14d, eax
    lea  rcx, LOC(0)
    call mk_buf_free
    mov  eax, r14d
ENDP

PROC mk_print_ok, MK_PATH
    mov  rdx, rcx
    lea  rcx, LOC(0)
    call mk_abs
    lea  rcx, [mk_s_ok_arrow]
    call mk_print
    lea  rcx, LOC(0)
    call mk_print
    lea  rcx, [mk_s_paren]
    call mk_print
    lea  rcx, LOC(0)
    call mk_file_size
    mov  rcx, rax
    call mk_print_u
    lea  rcx, [mk_s_bytes]
    call mk_println
ENDP

PROC mk_cmd_build, 3*MK_PATH+160
    ; LOC(0) object dir, LOC(520) exe path, LOC(1040) scratch path,
    ; LOC(1560) source list, LOC(1584) failed names, LOC(1608) missing names,
    ; LOC(1632) link output, LOC(1656) command line
    lea  rdi, LOC(1560)
    xor  eax, eax
    mov  ecx, 120
    rep  stosb
    ; build\obj + MineAssembly.exe, or the _tag variants
    mov  rax, [mk_opt_tag]
    test rax, rax
    jz   .notag
    lea  rcx, LOC(0)
    lea  rdx, [mk_s_objtag]
    call mk_strcpy
    mov  rcx, rax
    mov  rdx, [mk_opt_tag]
    call mk_strcpy
    lea  rcx, LOC(1040)
    lea  rdx, [mk_s_build_bs]
    call mk_strcpy
    mov  rcx, rax
    mov  rdx, [mk_opt_tag]
    call mk_strcpy
    lea  rcx, LOC(1040)
    call mk_mkdirs
    lea  rcx, LOC(520)
    lea  rdx, LOC(1040)
    lea  r8, [mk_s_exename]
    call mk_path_join
    jmp  .dirs
.notag:
    lea  rcx, LOC(0)
    lea  rdx, [mk_s_buildobj]
    call mk_strcpy
    lea  rcx, LOC(520)
    lea  rdx, [mk_s_exename]
    call mk_strcpy
.dirs:
    lea  rcx, LOC(0)
    call mk_mkdirs
    lea  rcx, LOC(1560)
    call mk_list_src
    mov  r12d, eax
    test eax, eax
    jnz  .have
    lea  rcx, [mk_s_nosrc]
    call mk_println
    mov  eax, 1
    jmp  .done
.have:
    mov  edx, r12d
    call mk_new_jobs
    mov  rbx, rax
    xor  esi, esi
.mk:
    cmp  esi, r12d
    jae  .mkd
    imul rdi, rsi, MK_AJ_SIZE
    add  rdi, rbx
    mov  rax, LOC(1560)
    mov  rax, [rax+rsi*8]
    mov  [rdi+MK_AJ_SRC], rax
    lea  rcx, LOC(1040)
    lea  rdx, LOC(0)
    mov  r8, rax
    call mk_obj_path
    lea  rcx, LOC(1040)
    call mk_strdup
    mov  [rdi+MK_AJ_OBJ], rax
    mov  dword [rdi+MK_AJ_MODE], MK_NASM_GAME
    inc  esi
    jmp  .mk
.mkd:
    ; one nasm per logical cpu
    lea  rcx, [mk_asm_job]
    mov  rdx, rbx
    mov  r8d, r12d
    mov  r9d, [mk_ncpu]
    call mk_parallel
    ; report in source order so the output doesn't depend on which job finished first
    xor  esi, esi
.rep:
    cmp  esi, r12d
    jae  .repd
    imul rdi, rsi, MK_AJ_SIZE
    add  rdi, rbx
    mov  rcx, [rdi+MK_AJ_OUT+MK_BUF_PTR]
    mov  rdx, [rdi+MK_AJ_OUT+MK_BUF_LEN]
    call mk_print_stripped
    cmp  dword [rdi+MK_AJ_RC], 0
    je   .repn
    cmp  qword LOC(1584+MK_BUF_LEN), 0
    je   .f1
    lea  rcx, LOC(1584)
    lea  rdx, [mk_s_comma]
    call mk_buf_addz
.f1:
    mov  rcx, [rdi+MK_AJ_SRC]
    call mk_basename
    lea  rcx, LOC(1584)
    mov  rdx, rax
    call mk_buf_addz
.repn:
    inc  esi
    jmp  .rep
.repd:
    cmp  qword LOC(1584+MK_BUF_LEN), 0
    je   .asm_ok
    lea  rcx, [mk_s_asmfail]
    call mk_print
    mov  rcx, LOC(1584+MK_BUF_PTR)
    call mk_println
    mov  eax, 1
    jmp  .done
.asm_ok:
    mov  rcx, rbx
    mov  edx, r12d
    call mk_job_objs
    mov  r15, rax
    mov  r13d, r12d
    cmp  dword [mk_opt_stubs], 0
    je   .link
    call mk_api_load
    test eax, eax
    jz   .fail1
    mov  rcx, r15
    mov  edx, r12d
    lea  r8, LOC(0)
    lea  r9, LOC(1608)
    call mk_make_stubs
    test eax, eax
    jz   .link
    mov  r14d, eax
    lea  rcx, [mk_s_stubbed1]
    call mk_print
    mov  ecx, r14d
    call mk_print_u
    lea  rcx, [mk_s_stubbed2]
    call mk_print
    mov  rcx, LOC(1608+MK_BUF_PTR)
    call mk_println
    imul rdi, r12, MK_AJ_SIZE           ; extra job for stubs.asm
    add  rdi, rbx
    lea  rcx, LOC(1040)
    lea  rdx, LOC(0)
    lea  r8, [mk_s_stubs_asm]
    call mk_path_join
    lea  rcx, LOC(1040)
    call mk_strdup
    mov  [rdi+MK_AJ_SRC], rax
    lea  rcx, LOC(1040)
    lea  rdx, LOC(0)
    lea  r8, [mk_s_stubsobj]
    call mk_path_join
    lea  rcx, LOC(1040)
    call mk_strdup
    mov  [rdi+MK_AJ_OBJ], rax
    mov  rcx, rdi
    call mk_asm_one
    cmp  dword [rdi+MK_AJ_RC], 0
    je   .stub_ok
    mov  rcx, [rdi+MK_AJ_OUT+MK_BUF_PTR]
    mov  rdx, [rdi+MK_AJ_OUT+MK_BUF_LEN]
    call mk_print_stripped
    jmp  .fail1
.stub_ok:
    mov  rax, [rdi+MK_AJ_OBJ]
    mov  [r15+r13*8], rax
    inc  r13d
.link:
    lea  rcx, [mk_t_gcc_game]
    lea  rdx, LOC(520)
    mov  r8, r15
    mov  r9d, r13d
    lea  rax, [mk_t_game_tail]
    mov  [rsp+32], rax
    lea  rax, LOC(1632)
    mov  [rsp+40], rax
    call mk_link
    mov  r14d, eax
    mov  rcx, LOC(1632+MK_BUF_PTR)
    mov  rdx, LOC(1632+MK_BUF_LEN)
    call mk_print_stripped
    test r14d, r14d
    jz   .linked
    lea  rcx, [mk_s_linkfail]
    call mk_println
    jmp  .fail1
.linked:
    lea  rcx, LOC(520)
    call mk_print_ok
    ; --run ARGS: start the game in its own dir and pass its exit code through
    mov  esi, [mk_opt_run]
    test esi, esi
    jz   .ok
    lea  rcx, LOC(1040)
    lea  rdx, LOC(520)
    call mk_abs
    lea  rcx, LOC(1656)
    lea  rdx, LOC(1040)
    call mk_buf_arg
.ra:
    cmp  esi, [mk_argc]
    jae  .rad
    mov  rax, [mk_argv]
    mov  rdx, [rax+rsi*8]
    lea  rcx, LOC(1656)
    call mk_buf_arg
    inc  esi
    jmp  .ra
.rad:
    lea  rcx, LOC(0)                  ; reuse: directory of the exe
    lea  rdx, LOC(1040)
    call mk_dirname
    mov  rcx, LOC(1656+MK_BUF_PTR)
    lea  rdx, LOC(0)
    xor  r8d, r8d
    xor  r9d, r9d
    mov  qword [rsp+32], 0
    call mk_run
    jmp  .done
.ok:
    xor  eax, eax
    jmp  .done
.fail1:
    mov  eax, 1
.done:
ENDP

PROC mk_cmd_check, 2*MK_PATH
    mov  rax, [mk_opt_tag]
    test rax, rax
    jz   .notag
    lea  rcx, LOC(0)
    lea  rdx, [mk_s_objtag]
    call mk_strcpy
    mov  rcx, rax
    mov  rdx, [mk_opt_tag]
    call mk_strcpy
    jmp  .dir
.notag:
    lea  rcx, LOC(0)
    lea  rdx, [mk_s_buildobj]
    call mk_strcpy
.dir:
    lea  rcx, LOC(0)
    call mk_mkdirs
    mov  r12d, [mk_opt_nfiles]
    mov  edx, r12d
    call mk_new_jobs
    mov  rbx, rax
    xor  esi, esi
.mk:
    cmp  esi, r12d
    jae  .mkd
    imul rdi, rsi, MK_AJ_SIZE
    add  rdi, rbx
    mov  rax, [mk_opt_files]
    mov  rax, [rax+rsi*8]
    mov  [rdi+MK_AJ_SRC], rax
    lea  rcx, LOC(MK_PATH)
    lea  rdx, LOC(0)
    mov  r8, rax
    call mk_obj_path
    lea  rcx, LOC(MK_PATH)
    call mk_strdup
    mov  [rdi+MK_AJ_OBJ], rax
    mov  dword [rdi+MK_AJ_MODE], MK_NASM_GAME
    inc  esi
    jmp  .mk
.mkd:
    lea  rcx, [mk_asm_job]
    mov  rdx, rbx
    mov  r8d, r12d
    mov  r9d, [mk_ncpu]
    call mk_parallel
    xor  r13d, r13d
    xor  esi, esi
.rep:
    cmp  esi, r12d
    jae  .repd
    imul rdi, rsi, MK_AJ_SIZE
    add  rdi, rbx
    cmp  dword [rdi+MK_AJ_RC], 0
    je   .r0
    inc  r13d
.r0:
    mov  rcx, [rdi+MK_AJ_OUT+MK_BUF_PTR]
    mov  rdx, [rdi+MK_AJ_OUT+MK_BUF_LEN]
    call mk_print_stripped
    test eax, eax
    jnz  .rn
    mov  rax, [mk_opt_orig]  ; print(out or "<file>: OK")
    mov  rcx, [rax+rsi*8]
    call mk_print
    lea  rcx, [mk_s_colon_ok]
    call mk_println
.rn:
    inc  esi ; v1: mb_build scratch #0
    ; TODO: hoist invariant pointer load out of .loop (mb_build:0)
    jmp  .rep ; v1: mb_build scratch #1
.repd: ; v1: mb_build scratch #2
    ; TODO: verify 16-byte rsp alignment before inner call (mb_build:2)
    xor  eax, eax ; v1: mb_build scratch #3
    test r13d, r13d ; v1: mb_build scratch #4
    ; note: rcx = state ptr, rdx = index, r8d = flags (mb_build:4)
    setnz al ; v1: mb_build scratch #5
ENDP ; v1: mb_build scratch #6
    ; temp: spill r12/r13 across helper call until reg alloc pass (mb_build:6)

; build\test\NAME.dll: FILEs + src\globals.asm, api symbols nobody defines get
; stubbed, everything exported
PROC mk_cmd_dll, 3*MK_PATH+32 ; v1: mb_build scratch #10
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mb_build:10)
    ; LOC(0) out dir, LOC(520) scratch, LOC(1040) dll path, LOC(1560) link output
    xor  eax, eax ; v1: mb_build scratch #12
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mb_build:12)
    mov  LOC(1560), rax ; v1: mb_build scratch #13
    mov  LOC(1568), rax ; v1: mb_build scratch #14
    ; TODO: clamp index before table lookup on malformed input (mb_build:14)
    mov  LOC(1576), rax ; v1: mb_build scratch #15
    lea  rcx, LOC(0) ; v1: mb_build scratch #16
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mb_build:16)
    lea  rdx, [mk_s_testdir] ; v1: mb_build scratch #17
    call mk_strcpy ; v1: mb_build scratch #18
    ; TODO: hoist invariant pointer load out of .loop (mb_build:18)
    mov  rcx, rax ; v1: mb_build scratch #19
    mov  rdx, [mk_opt_name] ; v1: mb_build scratch #20
    ; TODO: verify 16-byte rsp alignment before inner call (mb_build:20)
    call mk_strcpy ; v1: mb_build scratch #21
    lea  rcx, LOC(0) ; v1: mb_build scratch #22
    ; note: rcx = state ptr, rdx = index, r8d = flags (mb_build:22)
    call mk_mkdirs ; v1: mb_build scratch #23
    ; sources = FILEs + src\globals.asm (duplicates dropped, order kept)
    mov  r12d, [mk_opt_nfiles] ; v1: mb_build scratch #25
    lea  edx, [r12d+1] ; v1: mb_build scratch #26
    ; temp: spill r12/r13 across helper call until reg alloc pass (mb_build:26)
    call mk_new_jobs ; v1: mb_build scratch #27
    mov  rbx, rax ; v1: mb_build scratch #28
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mb_build:28)
    xor  r13d, r13d ; v1: mb_build scratch #29
    xor  esi, esi ; v1: mb_build scratch #30
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mb_build:30)
.mk: ; v1: mb_build scratch #31
    cmp  esi, r12d ; v1: mb_build scratch #32
    ; TODO: clamp index before table lookup on malformed input (mb_build:32)
    jae  .mk_glob ; v1: mb_build scratch #33
    mov  rax, [mk_opt_files] ; v1: mb_build scratch #34
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mb_build:34)
    mov  r8, [rax+rsi*8] ; v1: mb_build scratch #35
    mov  rcx, rbx ; v1: mb_build scratch #36
    ; TODO: hoist invariant pointer load out of .loop (mb_build:36)
    mov  edx, r13d ; v1: mb_build scratch #37
    lea  r9, LOC(0)
    call mk_job_add_unique
    mov  r13d, eax
    inc  esi
    jmp  .mk
.mk_glob:
    mov  rcx, rbx
    mov  edx, r13d
    lea  r8, [mk_s_globals]
    lea  r9, LOC(0)
    call mk_job_add_unique
    mov  r13d, eax
    mov  r14d, r13d
    ; _entry.asm: DllEntry that returns TRUE
    lea  rcx, LOC(520)
    lea  rdx, LOC(0)
    lea  r8, [mk_s_entryasm]
    call mk_path_join
    lea  rcx, LOC(520)
    lea  rdx, [mk_s_entry_src]
    mov  r8d, mk_s_entry_end - mk_s_entry_src
    call mk_write_file
    imul rdi, r13, MK_AJ_SIZE
    add  rdi, rbx
    lea  rcx, LOC(520)
    call mk_strdup
    mov  [rdi+MK_AJ_SRC], rax
    lea  rcx, LOC(520)
    lea  rdx, LOC(0)
    lea  r8, [mk_s_entryobj]
    call mk_path_join
    lea  rcx, LOC(520)
    call mk_strdup
    mov  [rdi+MK_AJ_OBJ], rax
    inc  r13d
    lea  rcx, [mk_asm_job]
    mov  rdx, rbx
    mov  r8d, r13d
    mov  r9d, [mk_ncpu]
    call mk_parallel
    xor  esi, esi
.rep:
    cmp  esi, r14d
    jae  .repd
    imul rdi, rsi, MK_AJ_SIZE
    add  rdi, rbx
    mov  rcx, [rdi+MK_AJ_OUT+MK_BUF_PTR]
    mov  rdx, [rdi+MK_AJ_OUT+MK_BUF_LEN]
    call mk_print_stripped
    cmp  dword [rdi+MK_AJ_RC], 0
    je   .repn
    lea  rcx, [mk_s_asmfail]
    call mk_print
    mov  rcx, [rdi+MK_AJ_SRC]
    call mk_println
    jmp  .fail1
.repn:
    inc  esi
    jmp  .rep
.repd:
    imul rdi, r14, MK_AJ_SIZE           ; the entry object must exist too
    add  rdi, rbx
    cmp  dword [rdi+MK_AJ_RC], 0
    je   .entry_ok
    mov  rcx, [rdi+MK_AJ_OUT+MK_BUF_PTR]
    mov  rdx, [rdi+MK_AJ_OUT+MK_BUF_LEN]
    call mk_print_stripped
    jmp  .fail1
.entry_ok:
    mov  rcx, rbx
    mov  edx, r13d
    call mk_job_objs
    mov  r15, rax
    call mk_api_load
    test eax, eax
    jz   .fail1
    mov  rcx, r15
    mov  edx, r13d
    lea  r8, LOC(0)
    xor  r9d, r9d
    call mk_make_stubs
    mov  r14d, eax                      ; r14d = stub count (for the message)
    test eax, eax
    jz   .link
    imul rdi, r13, MK_AJ_SIZE
    add  rdi, rbx
    lea  rcx, LOC(520)
    lea  rdx, LOC(0)
    lea  r8, [mk_s_stubs_asm]
    call mk_path_join
    lea  rcx, LOC(520)
    call mk_strdup
    mov  [rdi+MK_AJ_SRC], rax
    lea  rcx, LOC(520)
    lea  rdx, LOC(0)
    lea  r8, [mk_s_stubsobj]
    call mk_path_join
    lea  rcx, LOC(520)
    call mk_strdup
    mov  [rdi+MK_AJ_OBJ], rax
    mov  rcx, rdi
    call mk_asm_one
    cmp  dword [rdi+MK_AJ_RC], 0
    je   .st_ok
    mov  rcx, [rdi+MK_AJ_OUT+MK_BUF_PTR]
    mov  rdx, [rdi+MK_AJ_OUT+MK_BUF_LEN]
    call mk_print_stripped
    jmp  .fail1
.st_ok:
    mov  rax, [rdi+MK_AJ_OBJ]
    mov  [r15+r13*8], rax
    inc  r13d
    ; v1 temporary guard (mb_build #17)
    xor     r11d, r11d ; clear v1 slot 17
    ; v1 temporary guard (mb_build #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (mb_build #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (mb_build #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (mb_build #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (mb_build #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (mb_build #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (mb_build #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (mb_build #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (mb_build #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (mb_build #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (mb_build #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (mb_build #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (mb_build #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (mb_build #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (mb_build #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (mb_build #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (mb_build #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (mb_build #53)
    xor     r11d, r11d ; clear v1 slot 53
