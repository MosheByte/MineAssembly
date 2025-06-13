; mb_util.asm - strings, heap, console, buffers, files, paths, argv, repo root.
; LEAF helpers only touch rax rcx rdx r8-r11.

extern GetFullPathNameA, SetCurrentDirectoryA, GetCurrentDirectoryA
extern GetModuleFileNameA, GetFileAttributesExA, RemoveDirectoryA
extern GetCurrentProcessId

%define MK_PATH         520

; bytes are always NUL terminated once allocated
%define MK_BUF_PTR      0
%define MK_BUF_LEN      8
%define MK_BUF_CAP      16
%define MK_BUF_SIZE     24

; clobbers r11d
%macro MK_TOLOWER 1
    lea  r11d, [%1-'A']
    cmp  r11d, 25
    ja   %%n
    add  %1, 32
%%n:
%endmacro

section .bss
alignb 16
mk_heap:        resq 1
mk_hout:        resq 1
mk_out_cs:      resb 64                 ; serialises console output between threads
mk_out_last:    resd 1                  ; last byte written to stdout (newline tracking)
mk_argc:        resd 1
mk_argv:        resq 1                  ; char*[argc+1], NULL terminated
mk_root_len:    resd 1
mk_root:        resb MK_PATH            ; repository root, no trailing backslash

section .rdata
mk_s_crlf:      db 13, 10, 0
mk_s_oom:       db "mabuild: out of memory", 0
mk_s_apiinc:    db "include\api.inc", 0
mk_s_x:         db "x", 0

section .text

LEAF mk_strlen
    mov  rax, rcx
.l: cmp  byte [rax], 0
    je   .e
    inc  rax
    jmp  .l
.e: sub  rax, rcx
    ret

; -> rax = dst's new NUL
LEAF mk_strcpy
.l: mov  al, [rdx]
    mov  [rcx], al
    test al, al
    jz   .e
    inc  rcx
    inc  rdx
    jmp  .l
.e: mov  rax, rcx
    ret

; -> rax = new end
LEAF mk_strcat
.l: cmp  byte [rcx], 0
    je   mk_strcpy
    inc  rcx
    jmp  .l

; unsigned byte order
LEAF mk_strcmp
.l: movzx eax, byte [rcx]
    movzx r8d, byte [rdx]
    sub  eax, r8d
    jnz  .e
    test r8d, r8d
    jz   .e
    inc  rcx
    inc  rdx
    jmp  .l
.e: ret

; ASCII only
LEAF mk_stricmp
.l: movzx eax, byte [rcx]
    movzx r8d, byte [rdx]
    MK_TOLOWER eax
    MK_TOLOWER r8d
    sub  eax, r8d
    jnz  .e
    test r8d, r8d
    jz   .e
    inc  rcx
    inc  rdx
    jmp  .l
.e: ret

LEAF mk_startswith
.l: movzx r8d, byte [rdx]
    test r8d, r8d
    jz   .yes
    cmp  r8b, [rcx]
    jne  .no
    inc  rcx
    inc  rdx
    jmp  .l
.yes:
    mov  eax, 1
    ret
.no:
    xor  eax, eax
    ret

LEAF mk_startswith_i
.l: movzx r8d, byte [rdx]
    test r8d, r8d
    jz   .yes
    movzx eax, byte [rcx]
    MK_TOLOWER eax
    MK_TOLOWER r8d
    cmp  eax, r8d
    jne  .no
    inc  rcx
    inc  rdx
    jmp  .l
.yes:
    mov  eax, 1
    ret
.no:
    xor  eax, eax
    ret

PROC mk_endswith_i
    mov  rbx, rcx
    mov  rsi, rdx
    call mk_strlen
    mov  rdi, rax
    mov  rcx, rsi
    call mk_strlen
    cmp  rax, rdi
    ja   .no
    lea  rcx, [rbx+rdi]
    sub  rcx, rax
    mov  rdx, rsi
    call mk_stricmp
    test eax, eax
    jnz  .no
    mov  eax, 1
    jmp  .done
.no:
    xor  eax, eax
.done:
ENDP

LEAF mk_utoa
    mov  rax, rcx
    mov  r8, rdx
    mov  r10, rdx
    mov  ecx, 10
.d: xor  edx, edx
    div  rcx
    add  dl, '0'
    mov  [r8], dl
    inc  r8
    test rax, rax
    jnz  .d
    mov  byte [r8], 0
    mov  rax, r8
    dec  r8
.r: cmp  r10, r8                        ; digits came out backwards: reverse
    jae  .x
    mov  cl, [r10]
    mov  dl, [r8]
    mov  [r10], dl
    mov  [r8], cl
    inc  r10
    dec  r8
    jmp  .r
.x: ret

; -> rax value, edx = digits consumed
LEAF mk_atou
    xor  eax, eax
    xor  edx, edx
.l: movzx r8d, byte [rcx+rdx]
    sub  r8d, '0'
    cmp  r8d, 9
    ja   .e
    imul rax, rax, 10
    add  rax, r8
    inc  edx
    jmp  .l
.e: ret

; -> rax ptr, rdx len. anything <= ' ' counts as whitespace
LEAF mk_strip
    mov  rax, rcx
    test rax, rax
    jnz  .l
    xor  edx, edx
    ret
.l: test rdx, rdx
    jz   .e
    cmp  byte [rax], ' '
    ja   .t
    inc  rax
    dec  rdx
    jmp  .l
.t: cmp  byte [rax+rdx-1], ' '
    ja   .e
    dec  rdx
    jnz  .t
.e: ret

; print and exit(3)
PROC mk_fatal
    call mk_println
    mov  ecx, 3
    call ExitProcess
ENDP

; zeroed, exits on OOM instead of returning 0
PROC mk_alloc
    mov  r8, rcx
    mov  rcx, [mk_heap]
    mov  edx, HEAP_ZERO_MEMORY
    call HeapAlloc
    test rax, rax
    jnz  .done
    lea  rcx, [mk_s_oom]
    call mk_fatal
.done:
ENDP

PROC mk_free
    test rcx, rcx
    jz   .done
    mov  r8, rcx
    mov  rcx, [mk_heap]
    xor  edx, edx
    call HeapFree
.done:
ENDP

PROC mk_realloc
    test rcx, rcx
    jnz  .re
    mov  rcx, rdx
    call mk_alloc
    jmp  .done
.re:
    mov  r9, rdx
    mov  r8, rcx
    mov  rcx, [mk_heap]
    mov  edx, HEAP_ZERO_MEMORY
    call HeapReAlloc
    test rax, rax
    jnz  .done
    lea  rcx, [mk_s_oom]
    call mk_fatal
.done:
ENDP

PROC mk_strndup
    mov  rsi, rcx
    mov  rbx, rdx
    lea  rcx, [rdx+1]
    call mk_alloc
    mov  rdi, rax
    mov  rcx, rbx
    mov  rdx, rax
    rep  movsb
    mov  rax, rdx                       ; block is zeroed: already terminated
ENDP

PROC mk_strdup
    mov  rbx, rcx
    call mk_strlen
    mov  rcx, rbx
    mov  rdx, rax
    call mk_strndup
ENDP

; several threads printing? take mk_lock first

PROC mk_write, 16
    test rdx, rdx
    jz   .done
    movzx eax, byte [rcx+rdx-1]
    mov  [mk_out_last], eax
    mov  r8, rdx
    mov  rdx, rcx
    mov  rcx, [mk_hout]
    lea  r9, LOC(0)
    mov  qword [rsp+32], 0
    call WriteFile
.done:
ENDP

PROC mk_print
    mov  rbx, rcx
    call mk_strlen
    mov  rcx, rbx
    mov  rdx, rax
    call mk_write
ENDP

PROC mk_nl
    lea  rcx, [mk_s_crlf]
    mov  edx, 2
    call mk_write
ENDP

PROC mk_println
    call mk_print
    call mk_nl
ENDP

PROC mk_print_u, 32
    lea  rdx, LOC(0)
    call mk_utoa
    lea  rcx, LOC(0)
    call mk_print
ENDP

PROC mk_lock
    lea  rcx, [mk_out_cs]
    call EnterCriticalSection
ENDP

PROC mk_unlock
    lea  rcx, [mk_out_cs]
    call LeaveCriticalSection
ENDP

; -> eax 1 if it printed anything. trimmed text + newline, blank text prints nothing
PROC mk_print_stripped
    call mk_strip
    test rdx, rdx
    jz   .none
    mov  rcx, rax
    call mk_write
    call mk_nl
    mov  eax, 1
    jmp  .done
.none:
    xor  eax, eax
.done:
ENDP

; MK_BUF: zero the 24 bytes before first use

; room for len+extra plus the NUL
PROC mk_buf_reserve
    mov  rbx, rcx
    mov  rax, [rbx+MK_BUF_LEN]
    lea  rsi, [rax+rdx+1]
    cmp  qword [rbx+MK_BUF_PTR], 0
    je   .grow
    cmp  rsi, [rbx+MK_BUF_CAP]
    jbe  .done
.grow:
    mov  rdi, [rbx+MK_BUF_CAP]
    add  rdi, rdi                       ; double ...
    cmp  rdi, rsi
    jae  .g1
    mov  rdi, rsi                       ; ... or exactly what is needed
.g1:
    cmp  rdi, 256
    jae  .g2
    mov  edi, 256
.g2:
    mov  rcx, [rbx+MK_BUF_PTR]
    mov  rdx, rdi
    call mk_realloc
    mov  [rbx+MK_BUF_PTR], rax
    mov  [rbx+MK_BUF_CAP], rdi
.done:
ENDP

PROC mk_buf_add
    mov  rbx, rcx
    mov  rsi, rdx
    mov  r12, r8
    mov  rdx, r8
    call mk_buf_reserve
    mov  rdi, [rbx+MK_BUF_PTR]
    add  rdi, [rbx+MK_BUF_LEN]
    mov  rcx, r12
    rep  movsb
    mov  byte [rdi], 0
    add  [rbx+MK_BUF_LEN], r12
ENDP

PROC mk_buf_addz
    mov  rbx, rcx
    mov  rsi, rdx
    mov  rcx, rdx
    call mk_strlen
    mov  rcx, rbx
    mov  rdx, rsi
    mov  r8, rax
    call mk_buf_add
ENDP

PROC mk_buf_addc, 16
    mov  LOC(0), dl
    lea  rdx, LOC(0)
    mov  r8d, 1
    call mk_buf_add
ENDP

PROC mk_buf_rep
    mov  rbx, rcx
    mov  esi, edx
    mov  edi, r8d
.l: test edi, edi
    jz   .done
    mov  rcx, rbx
    mov  edx, esi
    call mk_buf_addc
    dec  edi
    jmp  .l
.done:
ENDP

PROC mk_buf_addu, 32
    mov  rbx, rcx
    mov  rcx, rdx
    lea  rdx, LOC(0)
    call mk_utoa
    mov  rcx, rbx
    lea  rdx, LOC(0)
    call mk_buf_addz
ENDP

PROC mk_buf_addhex, 32
    mov  rbx, rcx
    mov  word LOC(0), '0x'
    mov  ecx, 8
    lea  r8, LOC(2)
.l: rol  edx, 4
    mov  eax, edx
    and  eax, 15
    cmp  eax, 10
    jb   .dig
    add  eax, 'A'-10-'0'
.dig:
    add  eax, '0'
    mov  [r8], al
    inc  r8
    dec  ecx
    jnz  .l
    mov  byte [r8], 0
    mov  rcx, rbx
    lea  rdx, LOC(0)
    call mk_buf_addz
ENDP

; "12.34s" from ms
PROC mk_buf_addsecs
    mov  rbx, rcx
    mov  rax, rdx
    xor  edx, edx
    mov  ecx, 1000
    div  rcx
    mov  r12, rdx
    mov  rcx, rbx
    mov  rdx, rax
    call mk_buf_addu
    mov  rcx, rbx
    mov  edx, '.'
    call mk_buf_addc
    mov  rax, r12
    xor  edx, edx
    mov  ecx, 10
    div  rcx
    mov  r12, rax
    mov  rcx, rbx
    mov  eax, r12d
    xor  edx, edx
    mov  r8d, 10
    div  r8d
    mov  esi, edx
    lea  edx, [eax+'0']
    call mk_buf_addc
    mov  rcx, rbx
    lea  edx, [esi+'0']
    call mk_buf_addc
    mov  rcx, rbx
    mov  edx, 's'
    call mk_buf_addc
ENDP

PROC mk_buf_free
    mov  rbx, rcx
    mov  rcx, [rbx+MK_BUF_PTR]
    call mk_free
    xor  eax, eax
    mov  [rbx+MK_BUF_PTR], rax
    mov  [rbx+MK_BUF_LEN], rax
    mov  [rbx+MK_BUF_CAP], rax
ENDP

LEAF mk_buf_clear
    mov  qword [rcx+MK_BUF_LEN], 0
    mov  rax, [rcx+MK_BUF_PTR]
    test rax, rax
    jz   .e
    mov  byte [rax], 0
.e: ret

; buffer as a growable qword array
PROC mk_buf_addptr, 16
    mov  LOC(0), rdx
    lea  rdx, LOC(0)
    mov  r8d, 8
    call mk_buf_add
ENDP

; quoting is what CommandLineToArgvW undoes: quotes only if empty or there is a
; blank/tab, an inner quote gets 2n+1 backslashes in front
PROC mk_buf_arg
    mov  rbx, rcx
    mov  rsi, rdx
    cmp  qword [rbx+MK_BUF_LEN], 0
    je   .nosp
    mov  rcx, rbx
    mov  edx, ' '
    call mk_buf_addc
.nosp:
    xor  r12d, r12d
    cmp  byte [rsi], 0
    jne  .scan0
    mov  r12d, 1                        ; empty argument -> ""
    jmp  .scanned
.scan0:
    mov  rax, rsi
.scan:
    movzx ecx, byte [rax]
    test ecx, ecx
    jz   .scanned
    cmp  ecx, ' '
    je   .needq
    cmp  ecx, 9
    je   .needq
    inc  rax
    jmp  .scan
.needq:
    mov  r12d, 1
.scanned:
    test r12d, r12d
    jz   .body
    mov  rcx, rbx
    mov  edx, '"'
    call mk_buf_addc
.body:
    xor  r13d, r13d                     ; pending backslashes
.c: movzx edi, byte [rsi]
    test edi, edi
    jz   .end
    inc  rsi
    cmp  edi, '\'
    jne  .notbs
    inc  r13d
    jmp  .c
.notbs:
    cmp  edi, '"'
    jne  .plain
    mov  rcx, rbx                       ; 2n backslashes, then \"
    mov  edx, '\'
    lea  r8d, [r13d+r13d+1]
    call mk_buf_rep
    mov  rcx, rbx
    mov  edx, '"'
    call mk_buf_addc
    xor  r13d, r13d
    jmp  .c
.plain:
    mov  rcx, rbx                       ; backslashes not before a quote: literal
    mov  edx, '\'
    mov  r8d, r13d
    call mk_buf_rep
    xor  r13d, r13d
    mov  rcx, rbx
    mov  edx, edi
    call mk_buf_addc
    jmp  .c
.end:
    mov  rcx, rbx
    mov  edx, '\'
    mov  r8d, r13d
    call mk_buf_rep
    test r12d, r12d
    jz   .done
    mov  rcx, rbx                       ; trailing backslashes doubled before "
    mov  edx, '\'
    mov  r8d, r13d
    call mk_buf_rep
    mov  rcx, rbx
    mov  edx, '"'
    call mk_buf_addc
.done:
ENDP

PROC mk_buf_args
    mov  rbx, rcx
    mov  rsi, rdx
.l: mov  rdx, [rsi]
    test rdx, rdx
    jz   .done
    mov  rcx, rbx
    call mk_buf_arg
    add  rsi, 8
    jmp  .l
.done:
ENDP

; -> eax 1 if added. trimmed text + CR LF, blank adds nothing
PROC mk_buf_add_stripped
    mov  rbx, rcx
    mov  rcx, rdx
    mov  rdx, r8
    call mk_strip
    test rdx, rdx
    jz   .none
    mov  rcx, rbx
    mov  r8, rdx
    mov  rdx, rax
    call mk_buf_add
    mov  rcx, rbx
    lea  rdx, [mk_s_crlf]
    call mk_buf_addz
    mov  eax, 1
    jmp  .done
.none:
    xor  eax, eax
.done:
ENDP

; -> rax buffer or 0. 16 zero bytes after the data so over-reading a bit is fine
PROC mk_read_file, 32
    mov  r12, rdx
    mov  edx, GENERIC_READ
    mov  r8d, 3                         ; FILE_SHARE_READ | FILE_SHARE_WRITE
    xor  r9d, r9d
    mov  qword [rsp+32], OPEN_EXISTING
    mov  qword [rsp+40], FILE_ATTRIBUTE_NORMAL
    mov  qword [rsp+48], 0
    call CreateFileA
    cmp  rax, -1
    je   .fail
    mov  rbx, rax
    mov  rcx, rbx
    lea  rdx, LOC(0)
    call GetFileSizeEx
    test eax, eax
    jz   .close_fail
    mov  rsi, LOC(0)
    lea  rcx, [rsi+16]
    call mk_alloc
    mov  rdi, rax
    xor  r13d, r13d
.rl:
    cmp  r13, rsi
    jae  .rdone
    mov  rcx, rbx
    lea  rdx, [rdi+r13]
    mov  r8, rsi
    sub  r8, r13
    cmp  r8, 0x40000000
    jbe  .rs
    mov  r8d, 0x40000000
.rs:
    lea  r9, LOC(8)
    mov  qword [rsp+32], 0
    call ReadFile
    test eax, eax
    jz   .rerr
    mov  eax, LOC(8)
    test eax, eax
    jz   .rdone
    add  r13, rax
    jmp  .rl
.rerr:
    mov  rcx, rdi
    call mk_free
    jmp  .close_fail
.rdone:
    mov  rcx, rbx
    call CloseHandle
    test r12, r12
    jz   .nosize
    mov  [r12], r13
.nosize:
    mov  rax, rdi
    jmp  .done
.close_fail:
    mov  rcx, rbx
    call CloseHandle
.fail:
    xor  eax, eax
.done:
ENDP

PROC mk_write_file, 16
    mov  rsi, rdx
    mov  rdi, r8
    mov  edx, GENERIC_WRITE
    mov  r8d, FILE_SHARE_READ
    xor  r9d, r9d
    mov  qword [rsp+32], CREATE_ALWAYS
    mov  qword [rsp+40], FILE_ATTRIBUTE_NORMAL
    mov  qword [rsp+48], 0
    call CreateFileA
    cmp  rax, -1
    je   .fail
    mov  rbx, rax
    mov  rcx, rbx
    mov  rdx, rsi
    mov  r8, rdi
    lea  r9, LOC(0)
    mov  dword [r9], 0
    mov  qword [rsp+32], 0
    call WriteFile
    mov  r12d, eax
    mov  rcx, rbx
    call CloseHandle
    test r12d, r12d
    jz   .fail
    mov  eax, LOC(0)
    cmp  rax, rdi
    jne  .fail
    mov  eax, 1
    jmp  .done
.fail:
    xor  eax, eax
.done:
ENDP

PROC mk_is_file
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

PROC mk_is_dir
    call GetFileAttributesA
    cmp  eax, INVALID_FILE_ATTRIBUTES
    je   .no
    test eax, FILE_ATTRIBUTE_DIRECTORY
    jz   .no
    mov  eax, 1
    jmp  .done
.no:
    xor  eax, eax
.done:
ENDP

PROC mk_file_size, 48
    xor  edx, edx                       ; GetFileExInfoStandard
    lea  r8, LOC(0)
    call GetFileAttributesExA
    test eax, eax
    jz   .fail
    mov  eax, LOC(28)                 ; nFileSizeHigh
    shl  rax, 32
    mov  ecx, LOC(32)                 ; nFileSizeLow
    or   rax, rcx
    jmp  .done
.fail:
    mov  rax, -1
.done:
ENDP

PROC mk_mkdirs, MK_PATH
    mov  rdx, rcx
    lea  rcx, LOC(0)
    call mk_strcpy
    lea  rbx, LOC(0)
    cmp  byte [rbx], 0
    je   .done
    mov  rsi, rbx
.l: inc  rsi                            ; never cut at index 0 (leading "\")
    movzx eax, byte [rsi]
    test eax, eax
    jz   .last
    cmp  eax, '\'
    je   .cut
    cmp  eax, '/'
    jne  .l
.cut:
    cmp  byte [rsi-1], ':'              ; "C:\" is not a directory to create
    je   .l
    mov  byte [rsi], 0
    mov  rcx, rbx
    xor  edx, edx
    call CreateDirectoryA
    mov  byte [rsi], '\'
    jmp  .l
.last:
    mov  rcx, rbx
    xor  edx, edx
    call CreateDirectoryA
.done:
ENDP

PROC mk_path_join
    mov  rbx, rcx
    mov  r12, r8
    call mk_strcpy
    cmp  rax, rbx
    je   .nosep
    movzx ecx, byte [rax-1]
    cmp  ecx, '\'
    je   .nosep
    cmp  ecx, '/'
    je   .nosep
    mov  byte [rax], '\'
    inc  rax
.nosep:
    mov  rcx, rax
    mov  rdx, r12
    call mk_strcpy
ENDP

LEAF mk_basename
    mov  rax, rcx
.l: movzx edx, byte [rcx]
    test edx, edx
    jz   .e
    inc  rcx
    cmp  edx, '\'
    je   .s
    cmp  edx, '/'
    je   .s
    cmp  edx, ':'
    jne  .l
.s: mov  rax, rcx
    jmp  .l
.e: ret

PROC mk_stem
    mov  rbx, rcx
    mov  rcx, rdx
    call mk_basename
    mov  rcx, rbx
    mov  rdx, rax
    call mk_strcpy
    mov  rcx, rax
.l: dec  rcx
    cmp  rcx, rbx
    jbe  .done
    cmp  byte [rcx], '.'
    jne  .l
    mov  byte [rcx], 0
.done:
    mov  rax, rbx
ENDP

PROC mk_dirname
    mov  rbx, rcx
    mov  rsi, rdx
    call mk_strcpy
    mov  rcx, rbx
    call mk_basename
    cmp  rax, rbx
    je   .empty
    mov  byte [rax-1], 0
    jmp  .done
.empty:
    mov  byte [rbx], 0
.done:
    mov  rax, rbx
ENDP

PROC mk_parent_name, MK_PATH
    mov  rbx, rcx
    lea  rcx, LOC(0)
    call mk_dirname
    lea  rcx, LOC(0)
    call mk_basename
    mov  rcx, rbx
    mov  rdx, rax
    call mk_strcpy
ENDP

LEAF mk_slashes
.l: movzx eax, byte [rcx]
    test eax, eax
    jz   .e
    cmp  eax, '/'
    jne  .n
    mov  byte [rcx], '\'
.n: inc  rcx
    jmp  .l
.e: ret

; resolves against the cwd; inside the repo root you get it root-relative
; ("src\math.asm"), outside you get an absolute path
PROC mk_rel_root, MK_PATH
    mov  rbx, rcx
    mov  rsi, rdx
    mov  rcx, rdx
    mov  edx, MK_PATH
    lea  r8, LOC(0)
    xor  r9d, r9d
    call GetFullPathNameA
    test eax, eax
    jz   .raw
    cmp  eax, MK_PATH
    jae  .raw
    lea  rcx, LOC(0)
    lea  rdx, [mk_root]
    call mk_startswith_i
    test eax, eax
    jz   .abs
    mov  eax, [mk_root_len]
    lea  rdx, LOC(0)
    add  rdx, rax
    movzx ecx, byte [rdx]
    test ecx, ecx
    jz   .dot
    cmp  ecx, '\'
    jne  .abs
    inc  rdx
    mov  rcx, rbx
    call mk_strcpy
    jmp  .ret
.dot:
    mov  word [rbx], '.'
    jmp  .ret
.raw:
    mov  rcx, rbx
    mov  rdx, rsi
    call mk_strcpy
    mov  rcx, rbx
    call mk_slashes
    jmp  .ret
.abs:
    mov  rcx, rbx
    lea  rdx, LOC(0)
    call mk_strcpy
.ret:
    mov  rax, rbx
ENDP

PROC mk_abs
    mov  rbx, rcx
    cmp  byte [rdx+1], ':'
    je   .copy
    cmp  byte [rdx], '\'
    je   .copy
    mov  r8, rdx
    lea  rdx, [mk_root]
    call mk_path_join
    jmp  .ret
.copy:
    call mk_strcpy
.ret:
    mov  rax, rbx
ENDP

; argv, CommandLineToArgvW rules
PROC mk_parse_args
    call GetCommandLineA
    mov  rsi, rax
    mov  rcx, rax
    call mk_strlen
    mov  r12, rax
    lea  rcx, [r12+r12+16]
    call mk_alloc
    mov  rdi, rax
    lea  rcx, [r12*8+32]
    call mk_alloc
    mov  r13, rax
    xor  r14d, r14d
    ; argv[0]: up to the closing quote or first blank, no escapes
    mov  [r13], rdi
    inc  r14d
    cmp  byte [rsi], '"'
    jne  .p0
    inc  rsi
.q0:
    movzx eax, byte [rsi]
    test eax, eax
    jz   .end0
    inc  rsi
    cmp  eax, '"'
    je   .end0
    mov  [rdi], al
    inc  rdi
    jmp  .q0
.p0:
    movzx eax, byte [rsi]
    test eax, eax
    jz   .end0
    cmp  eax, ' '
    je   .end0
    cmp  eax, 9
    je   .end0
    mov  [rdi], al
    inc  rdi
    inc  rsi
    jmp  .p0
.end0:
    mov  byte [rdi], 0
    inc  rdi
.next:
    movzx eax, byte [rsi]
    cmp  eax, ' '
    je   .skip
    cmp  eax, 9
    jne  .chk
.skip:
    inc  rsi
    jmp  .next
.chk:
    test eax, eax
    jz   .fin
    mov  [r13+r14*8], rdi
    inc  r14d
    xor  ebx, ebx
.ch:
    movzx eax, byte [rsi]
    test eax, eax
    jz   .argend
    cmp  eax, ' '
    je   .ws
    cmp  eax, 9
    jne  .nows
.ws:
    test ebx, ebx
    jz   .argend
.nows:
    cmp  eax, '\'
    jne  .nobs
    xor  ecx, ecx
.cnt:
    cmp  byte [rsi+rcx], '\'
    jne  .cnted
    inc  ecx
    jmp  .cnt
.cnted:
    add  rsi, rcx
    cmp  byte [rsi], '"'
    jne  .lit
    mov  edx, ecx                       ; before a quote: n/2 backslashes ...
    shr  edx, 1
.e1:
    test edx, edx
    jz   .e1d
    mov  byte [rdi], '\'
    inc  rdi
    dec  edx
    jmp  .e1
.e1d:
    test ecx, 1                         ; ... and an odd count escapes the quote
    jz   .ch
    mov  byte [rdi], '"'
    inc  rdi
    inc  rsi
    jmp  .ch
.lit:
    test ecx, ecx
    jz   .ch
    mov  byte [rdi], '\'
    inc  rdi
    dec  ecx
    jmp  .lit
.nobs:
    cmp  eax, '"'
    jne  .plain
    test ebx, ebx
    jz   .tog
    cmp  byte [rsi+1], '"'              ; "" inside quotes = literal quote
    jne  .tog
    mov  byte [rdi], '"'
    inc  rdi
    add  rsi, 2
    jmp  .ch
.tog:
    xor  ebx, 1
    inc  rsi
    jmp  .ch
.plain:
    mov  [rdi], al
    inc  rdi
    inc  rsi
    jmp  .ch
.argend:
    mov  byte [rdi], 0
    inc  rdi
    jmp  .next
.fin:
    mov  qword [r13+r14*8], 0
    mov  [mk_argc], r14d
    mov  [mk_argv], r13
ENDP

; repo root = nearest dir with include\api.inc, walking up from mabuild.exe,
; then from the cwd

PROC mk_root_walk, MK_PATH
    mov  rbx, rcx
.up:
    mov  rcx, rbx
    call mk_basename
    cmp  rax, rbx
    je   .no
    mov  byte [rax-1], 0                ; drop the last component
    cmp  byte [rbx], 0
    je   .no
    lea  rcx, LOC(0)
    mov  rdx, rbx
    lea  r8, [mk_s_apiinc]
    call mk_path_join
    lea  rcx, LOC(0)
    call mk_is_file
    test eax, eax
    jz   .up
    lea  rcx, [mk_root]
    mov  rdx, rbx
    call mk_strcpy
    mov  eax, 1
    jmp  .done
.no:
    xor  eax, eax
.done:
ENDP

PROC mk_find_root, MK_PATH*2
    xor  ecx, ecx
    lea  rdx, LOC(0)
    mov  r8d, MK_PATH
    call GetModuleFileNameA
    lea  rcx, LOC(0)
    call mk_root_walk
    test eax, eax
    jnz  .found
    mov  ecx, MK_PATH
    lea  rdx, LOC(0)
    call GetCurrentDirectoryA
    lea  rcx, LOC(MK_PATH)            ; cwd + "\x": the first cut keeps cwd
    lea  rdx, LOC(0)
    lea  r8, [mk_s_x]
    call mk_path_join
    lea  rcx, LOC(MK_PATH)
    call mk_root_walk
    test eax, eax
    jnz  .found
    mov  ecx, MK_PATH                   ; give up: use the current directory
    lea  rdx, [mk_root]
    call GetCurrentDirectoryA
.found:
    lea  rcx, [mk_root]
    call mk_strlen
    mov  [mk_root_len], eax
ENDP
