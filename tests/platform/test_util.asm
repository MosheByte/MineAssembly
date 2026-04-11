; test_util.asm - src/util.asm: str_format, util_vformat truncation, the str_*
; and mem_* helpers. the 6330 %f cases live in util_golden.asm.
; @link src/util.asm tests/platform/pt_helpers.asm tests/platform/util_golden.asm
; @timeout 60
%include "common.inc"
%include "testlib.inc"

extern util_vformat                     ; global but not in api.inc
extern pt_strlen
extern gf_cases, gf_rand, gf_tie
extern gf_cases_n, gf_rand_n, gf_tie_n

%macro FAIL_HERE 1
    section .rdata
    %%m: db %1, 0
    %%f: db __?FILE?__, 0
    section .text
    lea  rcx, [rel %%m]
    lea  rdx, [rel %%f]
    mov  r8d, __?LINE?__
    call t_fail
%endmacro

; FMTCHK "expected", "format", arg1 .. arg7
; args go out like a C varargs call (r8, r9, then [rsp+32]..), anything mov
; reg64 takes. also checks the returned length against strlen.
%macro FMTCHK 2-9
    section .rdata
    %%want: db %1, 0
    %%fmt:  db %2, 0
    %%file: db __?FILE?__, 0
    %%lmsg: db "returned length != strlen: ", %2, 0
    section .text
    %assign %%i 0
    %rotate 2
    %rep %0-2
        %if %%i == 0
            mov  r8, %1
        %elif %%i == 1
            mov  r9, %1
        %else
            mov  rax, %1
            mov  [rsp+32+8*(%%i-2)], rax
        %endif
        %assign %%i %%i+1
        %rotate 1
    %endrep
    lea  rcx, [rel g_buf]
    lea  rdx, [rel %%fmt]
    call str_format
    mov  ebx, eax
    lea  rcx, [rel g_buf]
    lea  rdx, [rel %%want]
    lea  r8,  [rel %%fmt]
    lea  r9,  [rel %%file]
    mov  qword [rsp+32], __?LINE?__
    call t_check_str
    lea  rcx, [rel g_buf]
    call pt_strlen
    cmp  rax, rbx
    je   %%len_ok
    lea  rcx, [rel %%lmsg]
    lea  rdx, [rel %%file]
    mov  r8d, __?LINE?__
    call t_fail
%%len_ok:
%endmacro

; STF "text", bits. compared by value
%macro STF 2
    section .rdata
    %%s: db %1, 0
    section .text
    lea  rcx, [rel %%s]
    call str_to_float
    mov  eax, %2
    movd xmm1, eax
    xor  eax, eax
    ucomiss xmm0, xmm1                  ; so -0 == 0
    jp   %%c
    jne  %%c
    mov  eax, 1
%%c:
    CHECK_TRUE eax, %1
%endmacro

; STI "text", int64
%macro STI 2
    section .rdata
    %%s: db %1, 0
    section .text
    lea  rcx, [rel %%s]
    lea  rdx, L_END
    call str_to_int
    mov  rbx, %2
    CHECK_EQ rax, rbx, %1
%endmacro

section .rdata
s_hello:    db "hello", 0
s_ab:       db "ab", 0
s_cd:       db "cd", 0
s_abcdef:   db "abcdef", 0
s_x:        db "x", 0
s_seven:    db "seven", 0
s_z:        db "z", 0
s_abc:      db "abc", 0
s_abd:      db "abd", 0
s_abcd:     db "abcd", 0
s_defg:     db "defg", 0
s_digits:   db "0123456789", 0
s_xy:       db "xy", 0
s_ff:       db 0xFF, 0
s_a:        db "a", 0
s_empty:    db "", 0
s_hw_mixed: db "HeLLo World", 0
s_hw_lower: db "hello world", 0
s_hello_x:  db "hello!", 0
s_lbrack:   db "[", 0
s_lbrace:   db "{", 0
s_dd_seed:  db "--seed", 0
s_dd:       db "--", 0
s_dash:     db "-", 0
s_trunc_fmt: db "abcdefghij%d%d-tail", 0
s_123_rest: db "  123 rest", 0
s_sp_xyz:   db "  xyz", 0
s_h_ma:     db "MineAssembly", 0
s_h_seed:   db "seed 1337", 0
s_m_init:   db "0123456789", 0, 0, 0, 0, 0, 0
s_m_copy:   db "01abc56789"
s_m_set:    db "zzzzc56789"
s_m_zero:   db "z", 0, 0, 0, "c5"
s_fixed_f:  db "%f / %.Nf fixed value", 0
s_rand_f:   db "random %.Nf", 0
s_tie_f:    db "round-half-even tie %.Nf", 0
s_len_bad:  db "returned length != strlen (float table)", 0
s_this_file: db __?FILE?__, 0
s_bits:     db "    float bits 0x", 0
s_prec:     db " precision ", 0
s_got:      db " got ", 0
align 16
trunc_args: dq 7, 8

section .data
align 8
p_hello:    dq s_hello
p_ab:       dq s_ab
p_cd:       dq s_cd
p_abcdef:   dq s_abcdef
p_x:        dq s_x
p_seven:    dq s_seven
p_z:        dq s_z

section .bss
alignb 16
g_buf:      resb 512
g_fmt:      resb 16
g_mem:      resb 16

section .text

; walks edx GF records from rcx: dd bits, db prec (255 = plain %f), text, 0
PROC run_float_table, 16
    mov  rbx, rcx
    mov  esi, edx
    mov  rdi, r8
.rec:
    test esi, esi
    jz   .done
    mov  r12d, [rbx]
    movzx r13d, byte [rbx+4]
    lea  r14, [rbx+5]
    mov  rcx, r14
    call pt_strlen
    lea  rbx, [r14+rax+1]
    lea  rax, [rel g_fmt]
    mov  byte [rax], '%'
    cmp  r13d, 255
    jne  .prec
    mov  word [rax+1], 'f'
    jmp  .call
.prec:
    mov  byte [rax+1], '.'
    lea  ecx, [r13d+'0']
    mov  [rax+2], cl
    mov  word [rax+3], 'f'
.call:
    lea  rcx, [rel g_buf]
    lea  rdx, [rel g_fmt]
    mov  r8d, r12d
    call str_format
    mov  r15d, eax
    lea  rcx, [rel g_buf]
    mov  rdx, r14
    mov  r8, rdi
    lea  r9, [rel s_this_file]
    mov  qword [rsp+32], __?LINE?__
    call t_check_str
    test eax, eax
    jnz  .len
    lea  rcx, [rel s_bits]
    call t_print
    mov  ecx, r12d
    call t_print_hex
    lea  rcx, [rel s_prec]
    call t_print
    lea  rcx, [rel g_fmt]
    call t_print
    call t_newline
.len:
    lea  rcx, [rel g_buf]
    call pt_strlen
    cmp  eax, r15d
    je   .next
    lea  rcx, [rel s_len_bad]
    lea  rdx, [rel s_this_file]
    mov  r8d, __?LINE?__
    call t_fail
.next:
    dec  esi
    jmp  .rec
.done:
    ENDP

; reference fnv-1a 64 to check str_hash against
PROC fnv1a, 0
    mov  rax, 0xcbf29ce484222325
    mov  r8, 0x100000001b3
.l: movzx edx, byte [rcx]
    test edx, edx
    jz   .done
    xor  rax, rdx
    imul rax, r8
    inc  rcx
    jmp  .l
.done:
    ENDP

%define L_END   LOC(0)

PROC test_main, 32
    TEST "str_format integers"
    FMTCHK "x=5 y=-17", "x=%d y=%d", 5, -17
    FMTCHK "-2147483648", "%i", 0x80000000
    FMTCHK "4294967295", "%u", 0xFFFFFFFF
    FMTCHK "deadbeef ABC", "%x %X", 0xdeadBEEF, 0xabc
    FMTCHK "-1234567890123", "%l", -1234567890123
    FMTCHK "-5|18446744073709551615|10000000000", "%ld|%lu|%lx", -5, -1, 0x10000000000
    FMTCHK "-9223372036854775808", "%l", 0x8000000000000000
    FMTCHK "[   42][42   ][00042][-0042]", "[%5d][%-5d][%05d][%05d]", 42, 42, 42, -42
    FMTCHK "[12345]", "[%3d]", 12345
    FMTCHK "007", "%.3d", 7
    FMTCHK "0000001F", "%08X", 0x1F
    FMTCHK "100% ok", "100%% %c%c", 'o', 'k'
    TEST "str_format strings"
    FMTCHK "[hello]", "[%s]", [rel p_hello]
    FMTCHK "[      ab][cd      ]", "[%8s][%-8s]", [rel p_ab], [rel p_cd]
    FMTCHK "[abc]", "[%.3s]", [rel p_abcdef]
    FMTCHK "[(null)]", "[%s]", 0
    FMTCHK "[       x]", "[%08s]", [rel p_x]
    TEST "str_format stack args"
    FMTCHK "1 2 3 4 5 6 seven", "%d %d %d %d %d %d %s", 1, 2, 3, 4, 5, 6, [rel p_seven]
    FMTCHK "9,2.5,z,ff,7", "%d,%.1f,%s,%x,%l", 9, __?float32?__(2.5), [rel p_z], 255, 7
    FMTCHK "MineAssembly | 144 FPS", "MineAssembly | %d FPS", 144
    FMTCHK "trailing ", "trailing %"
    TEST "str_format floats"
    lea  rcx, [rel gf_cases]
    mov  edx, [rel gf_cases_n]
    lea  r8, [rel s_fixed_f]
    call run_float_table
    lea  rcx, [rel gf_rand]
    mov  edx, [rel gf_rand_n]
    lea  r8, [rel s_rand_f]
    call run_float_table
    lea  rcx, [rel gf_tie]
    mov  edx, [rel gf_tie_n]
    lea  r8, [rel s_tie_f]
    call run_float_table
    FMTCHK "[    3.14][3.14    ][-0003.14][00002.50]", "[%8.2f][%-8.2f][%08.2f][%08.2f]", __?float32?__(3.14159), __?float32?__(3.14159), __?float32?__(-3.14159), __?float32?__(2.5)
    FMTCHK "inf -inf", "%f %f", 0x7F800000, 0xFF800000
    FMTCHK "nan", "%f", 0x7FC00000
    FMTCHK "XYZ: 12.500 / -64.250 / 0.001", "XYZ: %.3f / %.3f / %.3f", __?float32?__(12.5), __?float32?__(-64.25), __?float32?__(0.001)

    TEST "util_vformat"
    lea  rcx, [rel g_buf]
    lea  rdx, [rel s_trunc_fmt]
    lea  r8, [rel trunc_args]
    mov  r9d, 8
    call util_vformat
    CHECK_EQ32 eax, 7, "truncation length"
    lea  rcx, [rel g_buf]
    CHECK_STR rcx, "abcdefg", "truncation text"
    lea  rcx, [rel g_buf]
    lea  rdx, [rel s_abc]
    lea  r8, [rel trunc_args]
    xor  r9d, r9d
    call util_vformat
    CHECK_EQ32 eax, 0, "cap 0"

    TEST "string helpers"
    lea  rcx, [rel s_hello]
    call str_len
    CHECK_EQ rax, 5, "str_len hello"
    lea  rcx, [rel s_empty]
    call str_len
    CHECK_EQ rax, 0, "str_len empty"
    lea  rcx, [rel g_buf]
    lea  rdx, [rel s_abc]
    call str_copy
    lea  rbx, [rel g_buf]
    sub  rax, rbx
    CHECK_EQ rax, 3, "str_copy end"
    CHECK_STR rbx, "abc", "str_copy"
    lea  rcx, [rel g_buf]
    lea  rdx, [rel s_defg]
    call str_cat
    lea  rbx, [rel g_buf]
    sub  rax, rbx
    CHECK_EQ rax, 7, "str_cat end"
    CHECK_STR rbx, "abcdefg", "str_cat"
    lea  rcx, [rel g_buf]
    lea  rdx, [rel s_digits]
    mov  r8d, 5
    call str_ncopy
    lea  rbx, [rel g_buf]
    sub  rax, rbx
    CHECK_EQ rax, 4, "str_ncopy end"
    CHECK_STR rbx, "0123", "str_ncopy"
    lea  rcx, [rel g_buf]
    lea  rdx, [rel s_xy]
    mov  r8d, 5
    call str_ncopy
    lea  rbx, [rel g_buf]
    CHECK_STR rbx, "xy", "str_ncopy short"
    lea  rcx, [rel s_abc]
    lea  rdx, [rel s_abc]
    call str_cmp
    CHECK_EQ32 eax, 0, "str_cmp equal"
    lea  rcx, [rel s_abc]
    lea  rdx, [rel s_abd]
    call str_cmp
    shr  eax, 31
    CHECK_TRUE eax, "str_cmp less"
    lea  rcx, [rel s_abcd]
    lea  rdx, [rel s_abc]
    call str_cmp
    xor  ecx, ecx
    test eax, eax
    setg cl
    CHECK_TRUE ecx, "str_cmp greater"
    lea  rcx, [rel s_ff]
    lea  rdx, [rel s_a]
    call str_cmp
    xor  ecx, ecx
    test eax, eax
    setg cl
    CHECK_TRUE ecx, "unsigned compare"
    lea  rcx, [rel s_hw_mixed]
    lea  rdx, [rel s_hw_lower]
    call str_eq_nocase
    CHECK_EQ32 eax, 1, "str_eq_nocase equal"
    lea  rcx, [rel s_hello]
    lea  rdx, [rel s_hello_x]
    call str_eq_nocase
    CHECK_EQ32 eax, 0, "str_eq_nocase prefix"
    lea  rcx, [rel s_lbrack]
    lea  rdx, [rel s_lbrace]
    call str_eq_nocase
    CHECK_EQ32 eax, 0, "non letters"
    lea  rcx, [rel s_dd_seed]
    lea  rdx, [rel s_dd]
    call str_starts_with
    CHECK_EQ32 eax, 1, "starts_with --seed --"
    lea  rcx, [rel s_dash]
    lea  rdx, [rel s_dd]
    call str_starts_with
    CHECK_EQ32 eax, 0, "starts_with - --"
    lea  rcx, [rel s_abc]
    lea  rdx, [rel s_empty]
    call str_starts_with
    CHECK_EQ32 eax, 1, "starts_with empty prefix"

    TEST "str_to_int"
    STI "42", 42
    STI "  -17xyz", -17
    STI "+8", 8
    STI "0x1F", 31
    STI "-0x10", -16
    STI "9223372036854775807", 0x7FFFFFFFFFFFFFFF
    STI "abc", 0
    STI "0x", 0
    STI "007", 7
    lea  rcx, [rel s_123_rest]
    lea  rdx, L_END
    call str_to_int
    mov  rax, L_END
    lea  rcx, [rel s_123_rest]
    sub  rax, rcx
    CHECK_EQ rax, 5, "str_to_int end"
    lea  rcx, [rel s_sp_xyz]
    lea  rdx, L_END
    call str_to_int
    mov  rax, L_END
    lea  rcx, [rel s_sp_xyz]
    sub  rax, rcx
    CHECK_EQ rax, 0, "str_to_int no digits end"

    ; expected = float32 nearest the exact decimal value
    TEST "str_to_float"
    STF "0", 0x00000000
    STF "1", 0x3F800000
    STF "-1.5", 0xBFC00000
    STF "3.14159", 0x40490FD0
    STF "0.1", 0x3DCCCCCD
    STF "1e3", 0x447A0000
    STF "2.5E-3", 0x3B23D70A
    STF "  +12.75", 0x414C0000
    STF "123456789", 0x4CEB79A3
    STF "0.000001", 0x358637BD
    STF "-0", 0x80000000
    STF "1.17549435e-38", 0x00800000
    STF "3.4e38", 0x7F7FC99E
    STF "00012.500", 0x41480000
    STF "70", 0x428C0000
    STF "0.15", 0x3E19999A

    TEST "str_hash"
%macro HASHCHK 1
    lea  rcx, [rel %1]
    call str_hash
    mov  rbx, rax
    lea  rcx, [rel %1]
    call fnv1a
    CHECK_EQ rbx, rax, "str_hash FNV-1a"
%endmacro
    HASHCHK s_empty
    HASHCHK s_a
    HASHCHK s_h_ma
    HASHCHK s_h_seed

    TEST "memory helpers"
    lea  rbx, [rel g_mem]
    mov  rcx, rbx
    lea  rdx, [rel s_m_init]
    mov  r8d, 16
    call mem_copy
    lea  rcx, [rbx+2]
    lea  rdx, [rel s_abc]
    mov  r8d, 3
    call mem_copy
    lea  rax, [rel s_m_copy]
    CHECK_MEM rbx, rax, 10, "mem_copy"
    mov  rcx, rbx
    mov  edx, 'z'
    mov  r8d, 4
    call mem_set
    lea  rax, [rel s_m_set]
    CHECK_MEM rbx, rax, 10, "mem_set"
    lea  rcx, [rbx+1]
    mov  edx, 3
    call mem_zero
    lea  rax, [rel s_m_zero]
    CHECK_MEM rbx, rax, 6, "mem_zero"
    mov  rcx, rbx
    xor  edx, edx
    call mem_zero
    movzx eax, byte [rbx]
    CHECK_EQ32 eax, 'z', "mem_zero 0"
    ENDP
