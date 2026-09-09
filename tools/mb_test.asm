; mb_test.asm - mabuild test. default is every tests\**\test_*.asm, CPUs/2 at a time.
; testlib, globals and @link files are shared, assembled once per run into build\t_cache_<pid>.
; a test passes when its exe exits 0.

%define MK_TJ_PATH      0
%define MK_TJ_NAME      8
%define MK_TJ_OUT       16              ; MK_BUF block printed when done
%define MK_TJ_RESULT    40
%define MK_TJ_EXIT      44              ; dword exit code of the test exe
%define MK_TJ_MS        48              ; qword wall time
%define MK_TJ_TIMEOUT   56
%define MK_TJ_FLAGS     60
%define MK_TJ_SIZE      64

%define MK_TF_GPU       1
%define MK_TF_PREVIEW   2

%define MK_R_PASS       0
%define MK_R_FAIL       1
%define MK_R_TIMEOUT    2
%define MK_R_BUILD      3
%define MK_R_SKIP       4

%define MK_T_MAXSRC     72              ; sources per test (test + libs + @link)
%define MK_T_MAXLINK    64              ; @link files per test

; object cache entry
%define MK_OC_PATH      0
%define MK_OC_OBJ       8
%define MK_OC_STATE     16              ; dword 1 assembling, 2 ok, 3 failed
%define MK_OC_RC        20
%define MK_OC_OUT       24
%define MK_OC_SIZE      48
%define MK_OC_MAX       1024

section .bss
alignb 8
mk_t_jobs:      resd 1                  ; --jobs (0 = CPUs/2)
mk_t_timeout:   resd 1                  ; --timeout seconds (0 = per test)
mk_t_nogpu:     resd 1
mk_t_stream:    resd 1                  ; 1 = one test at a time, output live
mk_oc_count:    resd 1
mk_oc_entries:  resq 1
mk_oc_cs:       resb 64
mk_t_cachedir:  resb MK_PATH

section .rdata
mk_s_tests:     db "tests", 0
mk_s_star:      db "*", 0
mk_s_test_:     db "test_", 0
mk_s_testlib:   db "tests\lib\testlib.asm", 0
mk_s_t_:        db "t_", 0
mk_s_cache:     db "build\t_cache_", 0
mk_s_banner:    db "--- ", 0
mk_s_noread:    db "cannot read the test file", 13, 10, 0
mk_s_ocfull:    db "mabuild: object cache full", 13, 10, 0
mk_s_dotexe:    db ".exe", 0
mk_s_lbr:       db "[", 0
mk_s_rbr:       db "] ", 0
mk_s_r_pass:    db "PASS", 0
mk_s_r_fail:    db "FAIL", 0
mk_s_r_timeout: db "TIMEOUT", 0
mk_s_r_build:   db "BUILD FAILED", 0
mk_s_r_skip:    db "SKIPPED", 0
mk_result_names: dq mk_s_r_pass, mk_s_r_fail, mk_s_r_timeout, mk_s_r_build, mk_s_r_skip
mk_s_exit:      db "  exit ", 0
mk_s_after:     db "  after ", 0
mk_s_secs_kill: db "s (killed)", 0
mk_s_gpuskip:   db "  (@gpu test, --nogpu)", 0
mk_s_lpar:      db "  (", 0
mk_s_rpar:      db ")", 0
mk_s_notfound:  db "mabuild test: no such file or directory: ", 0
mk_s_notests:   db "mabuild test: no tests found", 0
mk_s_t_head1:   db "mabuild test: ", 0
mk_s_t_head2:   db " test(s), ", 0
mk_s_t_head3:   db " in parallel", 0
mk_s_rule:      db "==============================================================================", 13, 10, 0
mk_s_rule2:     db "------------------------------------------------------------------------------", 13, 10, 0
mk_s_thead:     db "  result          time  test", 13, 10, 0
mk_s_sp2:       db "  ", 0
mk_s_sum1:      db " passed, ", 0
mk_s_sum2:      db " failed, ", 0
mk_s_sum3:      db " skipped, ", 0
mk_s_sum4:      db " total  (", 0
mk_s_sum5:      db " wall, ", 0
mk_s_sum6:      db " jobs)", 13, 10, 0
mk_s_kw_link:   db "link", 0

section .text

; per-test output goes into the test's block, or straight out when mk_t_stream

PROC mk_tj_emit
    cmp  dword [mk_t_stream], 0
    jne  .live
    add  rcx, MK_TJ_OUT
    call mk_buf_add
    jmp  .done
.live:
    mov  rsi, rdx
    mov  rdi, r8
    call mk_lock
    mov  rcx, rsi
    mov  rdx, rdi
    call mk_write
    call mk_unlock
.done:
ENDP

PROC mk_tj_emitz
    mov  rbx, rcx
    mov  rsi, rdx
    mov  rcx, rdx
    call mk_strlen
    mov  rcx, rbx
    mov  rdx, rsi
    mov  r8, rax
    call mk_tj_emit
ENDP

; trimmed text + CR LF, if any
PROC mk_tj_emit_buf
    mov  rbx, rcx
    mov  rcx, [rdx+MK_BUF_PTR]
    mov  rdx, [rdx+MK_BUF_LEN]
    call mk_strip
    test rdx, rdx
    jz   .done
    mov  rcx, rbx
    mov  r8, rdx
    mov  rdx, rax
    call mk_tj_emit
    mov  rcx, rbx
    lea  rdx, [mk_s_crlf]
    call mk_tj_emitz
.done:
ENDP

PROC mk_tj_eol
    mov  rbx, rcx
    cmp  dword [mk_t_stream], 0
    jne  .live
    mov  rax, [rbx+MK_TJ_OUT+MK_BUF_LEN]
    test rax, rax
    jz   .done
    mov  rdx, [rbx+MK_TJ_OUT+MK_BUF_PTR]
    cmp  byte [rdx+rax-1], 10
    je   .done
    jmp  .add
.live:
    cmp  dword [mk_out_last], 10
    je   .done
.add:
    mov  rcx, rbx
    lea  rdx, [mk_s_crlf]
    call mk_tj_emitz
.done:
ENDP

; mk_tj_asm(rcx job, rdx src, r8 obj, r9d mode, ARG5 keep buf or 0) -> eax 0 ok
; stripped output goes in the job's block, raw output into ARG5 if given
PROC mk_tj_asm, 64
    mov  rbx, rcx
    mov  rsi, rdx
    mov  rdi, r8
    mov  r12d, r9d
    mov  r13, ARG5
    lea  rcx, LOC(0)
    xor  eax, eax
    mov  [rcx], rax
    mov  [rcx+8], rax
    mov  [rcx+16], rax
    mov  [rcx+24], rax
    mov  [rcx+32], rax
    mov  [rcx+40], rax
    mov  rdx, rsi
    mov  r8, rdi
    mov  r9d, r12d
    call mk_nasm_cmd
    mov  rcx, LOC(0)
    xor  edx, edx
    lea  r8, LOC(24)
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
    mov  rcx, rbx
    lea  rdx, LOC(24)
    call mk_tj_emit_buf
    test r13, r13
    jz   .nokeep
    mov  rcx, r13
    mov  rdx, LOC(24+MK_BUF_PTR)
    mov  r8, LOC(24+MK_BUF_LEN)
    call mk_buf_add
.nokeep:
    lea  rcx, LOC(0)
    call mk_buf_free
    lea  rcx, LOC(24)
    call mk_buf_free
    mov  eax, r14d
ENDP

; first test to want a shared source assembles it (output lands in its block),
; the rest wait and reuse the obj
PROC mk_oc_get, MK_PATH+32
    mov  rbx, rcx
    mov  rsi, rdx
    lea  rcx, [mk_oc_cs]
    call EnterCriticalSection
    mov  r12, [mk_oc_entries]
    xor  edi, edi
.find:
    cmp  edi, [mk_oc_count]
    jae  .new
    imul rax, rdi, MK_OC_SIZE
    lea  r13, [r12+rax]
    mov  rcx, [r13+MK_OC_PATH]
    mov  rdx, rsi
    call mk_stricmp
    test eax, eax
    jz   .found
    inc  edi
    jmp  .find
.new:
    cmp  edi, MK_OC_MAX
    jae  .full
    imul rax, rdi, MK_OC_SIZE
    lea  r13, [r12+rax]
    mov  dword [r13+MK_OC_STATE], 1
    inc  dword [mk_oc_count]
    mov  rcx, rsi
    call mk_strdup
    mov  [r13+MK_OC_PATH], rax
    ; object name: <cache dir>\<source with \ / : . turned into _>.obj
    lea  rcx, LOC(0)
    lea  rdx, [mk_t_cachedir]
    mov  r8, rsi
    call mk_path_join
    lea  rcx, [mk_t_cachedir]
    call mk_strlen
    lea  rcx, [rsp+FRAME_OUT+rax+1]
.mangle:
    movzx eax, byte [rcx]
    test eax, eax
    jz   .mangled
    cmp  eax, '\'
    je   .us
    cmp  eax, '/'
    je   .us
    cmp  eax, ':'
    je   .us
    cmp  eax, '.'
    jne  .mn
.us:
    mov  byte [rcx], '_'
.mn:
    inc  rcx
    jmp  .mangle
.mangled:
    lea  rdx, [mk_s_dotobj]
    call mk_strcpy
    lea  rcx, LOC(0)
    call mk_strdup
    mov  [r13+MK_OC_OBJ], rax
    lea  rcx, [mk_oc_cs]
    call LeaveCriticalSection
    mov  rcx, rbx
    mov  rdx, [r13+MK_OC_PATH]
    mov  r8, [r13+MK_OC_OBJ]
    mov  r9d, MK_NASM_TEST
    lea  rax, [r13+MK_OC_OUT]
    mov  [rsp+32], rax
    call mk_tj_asm
    mov  [r13+MK_OC_RC], eax
    test eax, eax
    mov  eax, 2
    jz   .publish
    mov  eax, 3
.publish:
    xchg [r13+MK_OC_STATE], eax         ; full barrier: output is visible first
    jmp  .result
.found:
    lea  rcx, [mk_oc_cs]
    call LeaveCriticalSection
.wait:
    cmp  dword [r13+MK_OC_STATE], 1
    jne  .shared
    mov  ecx, 2
    call Sleep
    jmp  .wait
.shared:
    cmp  dword [r13+MK_OC_STATE], 3     ; failed for another test: show why here too
    jne  .result
    mov  rcx, rbx
    lea  rdx, [r13+MK_OC_OUT]
    call mk_tj_emit_buf
.result:
    cmp  dword [r13+MK_OC_STATE], 2
    jne  .fail
    mov  rax, [r13+MK_OC_OBJ]
    jmp  .done
.full:
    lea  rcx, [mk_oc_cs]
    call LeaveCriticalSection
    mov  rcx, rbx
    lea  rdx, [mk_s_ocfull]
    call mk_tj_emitz
.fail:
    xor  eax, eax
.done:
ENDP

; -> eax 1 if read. sets MK_TJ_TIMEOUT (0 = none) and MK_TJ_FLAGS from the
; directives in the first 40 lines
PROC mk_parse_header, 32
    mov  rbx, rcx
    mov  r12, rdx
    mov  r13, r8
    mov  dword [r13], 0
    mov  dword [rbx+MK_TJ_TIMEOUT], 0
    mov  dword [rbx+MK_TJ_FLAGS], 0
    mov  rcx, [rbx+MK_TJ_PATH]
    xor  edx, edx
    call mk_read_file
    test rax, rax
    jz   .fail
    mov  r15, rax
    mov  rsi, rax
    xor  r14d, r14d
.line:
    cmp  r14d, 40
    jae  .end
    cmp  byte [rsi], 0
    je   .end
    mov  rdi, rsi
.eol:
    movzx eax, byte [rsi]
    test eax, eax
    jz   .gotline
    cmp  eax, 10
    je   .gotline
    inc  rsi
    jmp  .eol
.gotline:                               ; [rdi, rsi) is the line
.ws1:
    cmp  rdi, rsi
    jae  .next
    movzx eax, byte [rdi]
    cmp  eax, ' '
    je   .ws1i
    cmp  eax, 9
    jne  .semi
.ws1i:
    inc  rdi
    jmp  .ws1
.semi:
    cmp  eax, ';'
    jne  .next
    inc  rdi
.ws2:
    cmp  rdi, rsi
    jae  .next
    movzx eax, byte [rdi]
    cmp  eax, ' '
    je   .ws2i
    cmp  eax, 9
    jne  .at
.ws2i:
    inc  rdi
    jmp  .ws2
.at:
    cmp  eax, '@'
    jne  .next
    inc  rdi
    cmp  dword [rdi], 'link'
    jne  .k_timeout
    movzx eax, byte [rdi+4]
    cmp  eax, ' '
    je   .link
    cmp  eax, 9
    jne  .k_timeout
.link:
    add  rdi, 4
.tok:
    cmp  rdi, rsi
    jae  .next
    movzx eax, byte [rdi]
    cmp  eax, ';'                       ; a trailing comment ends the list
    je   .next
    cmp  eax, ' '
    ja   .tokstart
    inc  rdi
    jmp  .tok
.tokstart:
    mov  rcx, rdi
.tokend:
    cmp  rdi, rsi
    jae  .tokgot
    movzx eax, byte [rdi]
    cmp  eax, ' '
    jbe  .tokgot
    cmp  eax, ';'
    je   .tokgot
    inc  rdi
    jmp  .tokend
.tokgot:
    mov  eax, [r13]
    cmp  eax, MK_T_MAXLINK
    jae  .tok
    mov  rdx, rdi
    sub  rdx, rcx
    call mk_strndup
    mov  rcx, rax
    mov  LOC(0), rax
    call mk_slashes
    mov  eax, [r13]
    mov  rcx, LOC(0)
    mov  [r12+rax*8], rcx
    inc  dword [r13]
    jmp  .tok
    ; @timeout N, first one wins
.k_timeout:
    cmp  dword [rdi], 'time'
    jne  .k_gpu
    cmp  word [rdi+4], 'ou'
    jne  .k_gpu
    cmp  byte [rdi+6], 't'
    jne  .k_gpu
    add  rdi, 7
    movzx eax, byte [rdi]
    cmp  eax, ' '
    je   .tw
    cmp  eax, 9
    jne  .next
.tw:
    movzx eax, byte [rdi]
    cmp  eax, ' '
    je   .twi
    cmp  eax, 9
    jne  .tnum
.twi:
    inc  rdi
    jmp  .tw
.tnum:
    mov  rcx, rdi
    call mk_atou
    test edx, edx
    jz   .next
    cmp  dword [rbx+MK_TJ_TIMEOUT], 0
    jne  .next
    mov  [rbx+MK_TJ_TIMEOUT], eax
    jmp  .next
    ; @gpu / @preview, must not run into an identifier char
.k_gpu:
    cmp  word [rdi], 'gp'
    jne  .k_prev
    cmp  byte [rdi+2], 'u'
    jne  .k_prev
    movzx ecx, byte [rdi+3]
    call .is_ident_ext
    test eax, eax
    jnz  .next
    or   dword [rbx+MK_TJ_FLAGS], MK_TF_GPU
    jmp  .next
.k_prev:
    cmp  dword [rdi], 'prev'
    jne  .next
    cmp  word [rdi+4], 'ie'
    jne  .next
    cmp  byte [rdi+6], 'w'
    jne  .next
    movzx ecx, byte [rdi+7]
    call .is_ident_ext
    test eax, eax
    jnz  .next
    or   dword [rbx+MK_TJ_FLAGS], MK_TF_PREVIEW
.next:
    inc  r14d
    cmp  byte [rsi], 0
    je   .end
    inc  rsi
    jmp  .line
.end:
    mov  rcx, r15
    call mk_free
    mov  eax, 1
    jmp  .done
.fail:
    xor  eax, eax
    jmp  .done
    ; .is_ident_ext(ecx byte) -> eax 1 for [A-Za-z0-9_]; leaf, no calls
.is_ident_ext:
    xor  eax, eax
    cmp  ecx, '_'
    je   .yes
    lea  edx, [ecx-'0']
    cmp  edx, 9
    jbe  .yes
    or   ecx, 32
    sub  ecx, 'a'
    cmp  ecx, 25
    ja   .no
.yes:
    mov  eax, 1
.no:
    ret
.done:
ENDP

PROC mk_strlist_add_unique
    mov  rbx, rcx
    mov  r12d, edx
    mov  rsi, r8
    xor  edi, edi
.l: cmp  edi, r12d
    jae  .add
    mov  rcx, [rbx+rdi*8]
    mov  rdx, rsi
    call mk_stricmp
    test eax, eax
    jz   .ret
    inc  edi
    jmp  .l
.add:
    cmp  r12d, MK_T_MAXSRC
    jae  .ret
    mov  [rbx+r12*8], rsi
    inc  r12d
.ret:
    mov  eax, r12d
ENDP
