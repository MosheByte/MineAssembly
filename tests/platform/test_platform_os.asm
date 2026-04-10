; test_platform_os.asm - os side of src/platform.asm: memory, files, dirs,
; timer, cpu count, log. no window.
; @link src/platform.asm src/util.asm src/gl.asm tests/platform/pt_helpers.asm
; @timeout 60
%include "common.inc"
%include "testlib.inc"

extern SetCurrentDirectoryA
extern pt_strlen, pt_join, pt_exists, pt_is_dir, pt_file_size, pt_read_file
extern pt_write_empty, pt_fresh_dir, pt_ends_with

section .rdata
s_work_name:    db "platform_os_work", 0
s_abcd:         db "a\b/c\d", 0
s_abcd_os:      db "a\b\c\d", 0
s_ab:           db "a\b", 0
s_abs_x:        db "abs\x", 0
s_abs_x_rel:    db "abs\x", 0
s_plainfile:    db "plainfile", 0
s_empty:        db "", 0
s_trail:        db "trail\", 0
s_trail_os:     db "trail", 0
s_data_bin:     db "a\b\data.bin", 0
s_data_tmp:     db "a\b\data.bin.tmp", 0
s_short:        db "short", 0
s_empty_bin:    db "empty.bin", 0
s_no_dir_file:  db "no\such\dir\f.bin", 0
s_missing:      db "missing.txt", 0
s_nope:         db "nope", 0
s_x:            db "x", 0
s_log_name:     db "mineassembly.log", 0
s_hello:        db "hello log", 0
s_hello_end:    db "] hello log", 0
s_fmt:          db "fmt %d %s %.2f %x %l", 0
s_str:          db "str", 0
s_fmt_end:      db "] fmt 42 str 3.14 ff 1099511627776", 0
s_no_work:      db "could not create the work directory", 0

align 8
d_0_2:          dq 0.2
d_0_6:          dq 0.6

section .text

; null p counts as a fail
PROC all_bytes, 0
    xor  eax, eax
    test rcx, rcx
    jz   .done
.l: test rdx, rdx
    jz   .yes
    cmp  [rcx], r8b
    jne  .no
    inc  rcx
    dec  rdx
    jmp  .l
.yes:
    mov  eax, 1
    jmp  .done
.no:
    xor  eax, eax
.done:
    ENDP

; null a = not equal
PROC mem_eq, 0
    xor  eax, eax
    test rcx, rcx
    jz   .done
.l: test r8, r8
    jz   .yes
    mov  al, [rcx]
    cmp  al, [rdx]
    jne  .no
    inc  rcx
    inc  rdx
    dec  r8
    jmp  .l
.yes:
    mov  eax, 1
    jmp  .done
.no:
    xor  eax, eax
.done:
    ENDP

%define L_WORK   LOC(0)
%define L_PATH   LOC(272)
%define L_SIZE   LOC(544)
%define L_T0     LOC(552)
%define L_M0     LOC(560)
%define L_T1     LOC(568)
%define L_M1     LOC(576)
%define L_DATA   LOC(584)

PROC test_main, 640
    lea  rcx, L_WORK
    lea  rdx, [rel s_work_name]
    call pt_fresh_dir
    test eax, eax
    jnz  .have_work
    lea  rcx, [rel s_no_work]
    call t_print
    call t_newline
.have_work:
    lea  rcx, L_WORK
    call SetCurrentDirectoryA                ; before any platform call, early_init drops the log in cwd

    TEST "memory"
    mov  ecx, 1000
    call mem_alloc
    mov  rbx, rax
    mov  rcx, rbx
    mov  edx, 1000
    xor  r8d, r8d
    call all_bytes
    CHECK_TRUE eax, "mem_alloc zeroed"
    test rbx, rbx
    jz   .skip_realloc
    mov  rdi, rbx
    mov  al, 0x41
    mov  ecx, 1000
    rep  stosb
    mov  rcx, rbx
    mov  edx, 5000
    call mem_realloc
    mov  rsi, rax
    mov  rcx, rsi
    mov  edx, 1000
    mov  r8d, 0x41
    call all_bytes
    CHECK_TRUE eax, "mem_realloc keeps data"
    mov  rcx, rsi
    call mem_free
.skip_realloc:
    xor  ecx, ecx
    call mem_free                       ; mem_free(NULL) is a no-op
    xor  ecx, ecx
    mov  edx, 64
    call mem_realloc
    mov  rbx, rax
    mov  rcx, rbx
    mov  edx, 64
    xor  r8d, r8d
    call all_bytes
    CHECK_TRUE eax, "mem_realloc(NULL)"
    mov  rcx, rbx
    call mem_free
    mov  ecx, 1 << 20
    call mem_valloc
    mov  rbx, rax
    xor  r12d, r12d
    test rbx, 4095
    jnz  .valloc_chk
    mov  rcx, rbx
    mov  edx, 4096
    xor  r8d, r8d
    call all_bytes
    mov  r12d, eax
.valloc_chk:
    CHECK_TRUE r12d, "mem_valloc"
    mov  rcx, rbx
    call mem_vfree

    TEST "files"
    lea  rcx, [rel s_abcd]
    call dir_create
    mov  r12d, eax
    lea  rcx, [rel s_abcd_os]
    call pt_is_dir
    and  r12d, eax                      ; dir_create has to return exactly 1
    CHECK_TRUE r12d, "dir_create recursive"
    lea  rcx, [rel s_ab]
    call dir_create
    CHECK_EQ32 eax, 1, "dir_create existing"
    lea  rcx, L_PATH
    lea  rdx, L_WORK
    lea  r8, [rel s_abs_x]
    call pt_join
    lea  rcx, L_PATH
    call dir_create
    mov  r12d, eax
    lea  rcx, [rel s_abs_x_rel]
    call pt_is_dir
    and  r12d, eax
    CHECK_TRUE r12d, "dir_create absolute"
    lea  rcx, [rel s_plainfile]
    call pt_write_empty
    lea  rcx, [rel s_plainfile]
    call dir_create
    CHECK_EQ32 eax, 0, "dir_create over a file fails"
    lea  rcx, [rel s_empty]
    call dir_create
    CHECK_EQ32 eax, 0, "dir_create of an empty path fails cleanly"
    lea  rcx, [rel s_trail]
    call dir_create
    mov  r12d, eax
    lea  rcx, [rel s_trail_os]
    call pt_is_dir
    and  r12d, eax
    CHECK_TRUE r12d, "dir_create with trailing separator"

    ; 0..255 repeated 1000x
    mov  ecx, 256000
    call t_alloc
    mov  L_DATA, rax
    xor  ecx, ecx
.fill:
    mov  [rax+rcx], cl
    inc  ecx
    cmp  ecx, 256000
    jb   .fill
    lea  rcx, [rel s_data_bin]
    mov  rdx, L_DATA
    mov  r8d, 256000
    call file_write_all
    CHECK_EQ32 eax, 1, "file_write_all"
    lea  rcx, [rel s_data_bin]
    lea  rdx, L_SIZE
    call pt_read_file
    xor  r12d, r12d
    cmp  qword L_SIZE, 256000
    jne  .wc_chk
    mov  rcx, rax
    mov  rdx, L_DATA
    mov  r8d, 256000
    call mem_eq
    mov  r12d, eax
.wc_chk:
    CHECK_TRUE r12d, "written content"
    lea  rcx, [rel s_data_tmp]
    call pt_exists
    xor  eax, 1
    CHECK_TRUE eax, "no temp file left"
    lea  rcx, [rel s_data_bin]
    lea  rdx, [rel s_short]
    mov  r8d, 5
    call file_write_all
    CHECK_EQ32 eax, 1, "overwrite"
    lea  rcx, [rel s_data_bin]
    lea  rdx, L_SIZE
    call pt_read_file
    xor  r12d, r12d
    cmp  qword L_SIZE, 5
    jne  .ow_chk
    mov  rcx, rax
    lea  rdx, [rel s_short]
    mov  r8d, 5
    call mem_eq
    mov  r12d, eax
.ow_chk:
    CHECK_TRUE r12d, "overwritten content"
    lea  rcx, [rel s_empty_bin]
    lea  rdx, [rel s_empty]
    xor  r8d, r8d
    call file_write_all
    mov  r12d, eax
    lea  rcx, [rel s_empty_bin]
    call pt_file_size
    test rax, rax
    setz al
    movzx eax, al
    and  r12d, eax
    CHECK_TRUE r12d, "empty file"
    lea  rcx, [rel s_no_dir_file]
    lea  rdx, [rel s_x]
    mov  r8d, 1
    call file_write_all
    CHECK_EQ32 eax, 0, "write into missing dir fails"
    ; out_size must get overwritten, and the buffer NUL terminated
    mov  qword L_SIZE, 123
    lea  rcx, [rel s_data_bin]
    lea  rdx, L_SIZE
    call file_read_all
    mov  rbx, rax
    xor  r12d, r12d
    cmp  qword L_SIZE, 5
    jne  .ra_chk
    mov  rcx, rbx
    lea  rdx, [rel s_short]
    mov  r8d, 6
    call mem_eq
    mov  r12d, eax
.ra_chk:
    CHECK_TRUE r12d, "file_read_all + NUL"
    mov  rcx, rbx
    call mem_free
    mov  qword L_SIZE, 99
    lea  rcx, [rel s_missing]
    lea  rdx, L_SIZE
    call file_read_all
    xor  r12d, r12d
    test rax, rax
    jnz  .rm_chk
    cmp  qword L_SIZE, 0
    sete r12b
.rm_chk:
    CHECK_TRUE r12d, "read missing"
    lea  rcx, [rel s_empty_bin]
    xor  edx, edx
    call file_read_all
    mov  rbx, rax
    xor  r12d, r12d
    test rbx, rbx
    jz   .re_chk
    cmp  byte [rbx], 0
    sete r12b
.re_chk:
    CHECK_TRUE r12d, "read empty with null size ptr"
    mov  rcx, rbx
    call mem_free
    lea  rcx, [rel s_empty_bin]
    call file_exists
    mov  r12d, eax
    cmp  r12d, 1
    sete r12b
    movzx r12d, r12b
    lea  rcx, [rel s_nope]
    call file_exists
    test eax, eax
    setz al
    movzx eax, al
    and  r12d, eax
    CHECK_TRUE r12d, "file_exists"
    lea  rcx, [rel s_empty_bin]
    call file_delete
    cmp  eax, 1
    sete r12b
    movzx r12d, r12b
    lea  rcx, [rel s_empty_bin]
    call pt_exists
    xor  eax, 1
    and  r12d, eax
    CHECK_TRUE r12d, "file_delete"
    lea  rcx, [rel s_empty_bin]
    call file_delete
    CHECK_EQ32 eax, 0, "delete missing"

    TEST "timer"
    call time_seconds
    movsd L_T0, xmm0
    call time_ms
    mov  L_M0, rax
    mov  ecx, 250
    call Sleep
    call time_seconds
    movsd L_T1, xmm0
    call time_ms
    mov  L_M1, rax
    movsd xmm0, L_T1
    subsd xmm0, L_T0
    xor  r12d, r12d
    comisd xmm0, [rel d_0_2]
    jbe  .ts_chk
    comisd xmm0, [rel d_0_6]
    jae  .ts_chk
    mov  r12d, 1
.ts_chk:
    CHECK_TRUE r12d, "time_seconds delta in (0.2, 0.6)"
    test r12d, r12d
    jnz  .ts_ok
    movsd xmm0, L_T1
    subsd xmm0, L_T0
    mov  edx, 4
    call t_print_double
    call t_newline
.ts_ok:
    mov  rax, L_M1
    sub  rax, L_M0
    xor  r12d, r12d
    cmp  rax, 200
    jb   .tm_chk
    cmp  rax, 600
    ja   .tm_chk
    mov  r12d, 1
.tm_chk:
    CHECK_TRUE r12d, "time_ms delta in [200, 600]"
    test r12d, r12d
    jnz  .tm_ok
    mov  rcx, L_M1
    sub  rcx, L_M0
    call t_print_int
    call t_newline
.tm_ok:
    call cpu_count
    xor  r12d, r12d
    cmp  eax, 1
    setge r12b
    CHECK_TRUE r12d, "cpu_count"

    TEST "log"
    lea  rcx, [rel s_hello]
    call log_write
    lea  rcx, [rel s_fmt]
    mov  edx, 42
    lea  r8, [rel s_str]
    mov  r9d, 0x40490FDB                ; 3.14159274f
    mov  qword [rsp+32], 255
    mov  rax, 1 << 40
    mov  [rsp+40], rax
    call log_printf
    mov  ecx, 5001                      ; 5000 x's, gets truncated, must not overflow
    call t_alloc
    mov  rbx, rax
    mov  rdi, rax
    mov  al, 'x'
    mov  ecx, 5000
    rep  stosb
    mov  rcx, rbx
    call log_write
    lea  rcx, [rel s_log_name]
    lea  rdx, L_SIZE
    call pt_read_file
    test rax, rax
    jnz  .parse
    CHECK_TRUE 0, "mineassembly.log readable"
    jmp  .done
.parse:
    ; split lines on CR, LF or CRLF.
    ; rsi cursor, r15 end, r12d lines, r13d CRLFs (must match r12d)
    ; r14d bits: 1 hello, 2 fmt, 4 bad prefix, 8 saw the 1035 char line
    mov  rsi, rax
    mov  r15, rax
    add  r15, L_SIZE
    xor  r12d, r12d
    xor  r13d, r13d
    xor  r14d, r14d
.line:
    cmp  rsi, r15
    jae  .lines_done
    mov  rdi, rsi
.scan:
    cmp  rsi, r15
    jae  .eol
    mov  al, [rsi]
    cmp  al, 13
    je   .eol
    cmp  al, 10
    je   .eol
    inc  rsi
    jmp  .scan
.eol:
    mov  rbx, rsi
    sub  rbx, rdi
    inc  r12d
    mov  rcx, rdi
    mov  rdx, rbx
    lea  r8, [rel s_hello_end]
    call pt_ends_with
    test eax, eax
    jz   .not_hello ; v1: test_platform_os scratch #0
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_platform_os:0)
    or   r14d, 1 ; v1: test_platform_os scratch #1
.not_hello: ; v1: test_platform_os scratch #2
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_platform_os:2)
    mov  rcx, rdi ; v1: test_platform_os scratch #3
    mov  rdx, rbx ; v1: test_platform_os scratch #4
    ; TODO: clamp index before table lookup on malformed input (test_platform_os:4)
    lea  r8, [rel s_fmt_end] ; v1: test_platform_os scratch #5
    call pt_ends_with ; v1: test_platform_os scratch #6
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_platform_os:6)
    test eax, eax ; v1: test_platform_os scratch #7
    jz   .not_fmt ; v1: test_platform_os scratch #8
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_platform_os:8)
    or   r14d, 2 ; v1: test_platform_os scratch #9
.not_fmt: ; v1: test_platform_os scratch #10
    ; TODO: verify 16-byte rsp alignment before inner call (test_platform_os:10)
    cmp  rbx, 11 ; v1: test_platform_os scratch #11
    jb   .bad_prefix ; v1: test_platform_os scratch #12
    ; TODO: hoist invariant pointer load out of .loop (test_platform_os:12)
    cmp  byte [rdi], '[' ; v1: test_platform_os scratch #13
    jne  .bad_prefix ; v1: test_platform_os scratch #14
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_platform_os:14)
    cmp  word [rdi+9], 0x205D ; v1: test_platform_os scratch #15
    je   .prefix_ok ; v1: test_platform_os scratch #16
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_platform_os:16)
.bad_prefix: ; v1: test_platform_os scratch #17
    or   r14d, 4 ; v1: test_platform_os scratch #18
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_platform_os:18)
.prefix_ok: ; v1: test_platform_os scratch #19
    cmp  rbx, 11 + 1024 ; v1: test_platform_os scratch #20
    ; TODO: clamp index before table lookup on malformed input (test_platform_os:20)
    jne  .not_long ; v1: test_platform_os scratch #21
    or   r14d, 8 ; v1: test_platform_os scratch #22
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_platform_os:22)
.not_long: ; v1: test_platform_os scratch #23
    cmp  rsi, r15 ; v1: test_platform_os scratch #24
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_platform_os:24)
    jae  .lines_done ; v1: test_platform_os scratch #25
    cmp  byte [rsi], 13 ; v1: test_platform_os scratch #26
    ; TODO: verify 16-byte rsp alignment before inner call (test_platform_os:26)
    jne  .single ; v1: test_platform_os scratch #27
    lea  rax, [rsi+1] ; v1: test_platform_os scratch #28
    ; TODO: hoist invariant pointer load out of .loop (test_platform_os:28)
    cmp  rax, r15 ; v1: test_platform_os scratch #29
    jae  .single ; v1: test_platform_os scratch #30
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (test_platform_os:30)
    cmp  byte [rax], 10 ; v1: test_platform_os scratch #31
    jne  .single ; v1: test_platform_os scratch #32
    ; temp: spill r12/r13 across helper call until reg alloc pass (test_platform_os:32)
    inc  r13d ; v1: test_platform_os scratch #33
    add  rsi, 2 ; v1: test_platform_os scratch #34
    ; FIXME: negative world x/z needs sar 4, not shr 4 (test_platform_os:34)
    jmp  .line ; v1: test_platform_os scratch #35
.single: ; v1: test_platform_os scratch #36
    ; TODO: clamp index before table lookup on malformed input (test_platform_os:36)
    inc  rsi ; v1: test_platform_os scratch #37
    jmp  .line ; v1: test_platform_os scratch #38
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (test_platform_os:38)
.lines_done: ; v1: test_platform_os scratch #39
    mov  eax, r14d ; v1: test_platform_os scratch #40
    ; note: rcx = state ptr, rdx = index, r8d = flags (test_platform_os:40)
    and  eax, 1 ; v1: test_platform_os scratch #41
    CHECK_TRUE eax, "log_write line" ; v1: test_platform_os scratch #42
    ; TODO: verify 16-byte rsp alignment before inner call (test_platform_os:42)
    mov  eax, r14d
    and  eax, 2
    CHECK_TRUE eax, "log_printf line"
    mov  eax, r14d
    and  eax, 4
    xor  eax, 4
    CHECK_TRUE eax, "timestamp prefix format"
    mov  eax, r14d
    and  eax, 8
    CHECK_TRUE eax, "long line truncated at 1024"
    CHECK_EQ32 r13d, r12d, "CRLF line endings"
.done:
    ENDP
    ; v1 temporary guard (test_platform_os #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (test_platform_os #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (test_platform_os #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (test_platform_os #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (test_platform_os #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (test_platform_os #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (test_platform_os #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (test_platform_os #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (test_platform_os #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (test_platform_os #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (test_platform_os #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (test_platform_os #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (test_platform_os #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (test_platform_os #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (test_platform_os #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (test_platform_os #52)
    xor     r11d, r11d ; clear v1 slot 52
    ; v1 temporary guard (test_platform_os #54)
    xor     r11d, r11d ; clear v1 slot 54
    ; v1 temporary guard (test_platform_os #56)
    xor     r11d, r11d ; clear v1 slot 56
    ; v1 temporary guard (test_platform_os #58)
    xor     r11d, r11d ; clear v1 slot 58
    ; v1 temporary guard (test_platform_os #60)
    xor     r11d, r11d ; clear v1 slot 60
    ; v1 temporary guard (test_platform_os #62)
    xor     r11d, r11d ; clear v1 slot 62
    ; v1 temporary guard (test_platform_os #64)
    xor     r11d, r11d ; clear v1 slot 64
