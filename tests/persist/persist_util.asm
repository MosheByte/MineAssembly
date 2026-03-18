; persist test helpers: per-case temp dir sandbox, file helpers, rle/fnv
; reference versions, chunk + entity generators, options.txt parsing.
%include "common.inc"
%include "testlib.inc"

extern SetCurrentDirectoryA, GetCurrentDirectoryA, GetTempPathA
extern GetCurrentProcessId, RemoveDirectoryA, SetFileAttributesA
extern GetSystemTimeAsFileTime, SetFileTime, GetFileAttributesExA
extern wsprintfA
extern mock_alloc_count

; WIN32_FIND_DATAA layout
%define FD_ATTR         0
%define FD_NAME         44
%define FD_SIZE         320
%define PU_PATH         1024

section .rdata
s_tmp_fmt:      db '%sma_persist_%u_%u', 0
s_test_world:   db 'TestWorld', 0
s_star:         db '\*', 0
s_leak:         db 'memory leak (mem_alloc without mem_free)', 0
s_leak_file:    db __?FILE?__, 0
align 8
d_two_m53:      dq 0x3CA0000000000000           ; 2^-53
d_5:            dq 5.0
d_6:            dq 6.0
d_628:          dq 6.28
d_64:           dq 64.0
d_3:            dq 3.0
d_2:            dq 2.0
d_4:            dq 4.0
d_12:           dq 12.0
d_07:           dq 0.7
d_m04:          dq -0.4
d_04:           dq 0.4
d_m05:          dq -0.5
d_05:           dq 0.5
d_16:           dq 16.0
d_30:           dq 30.0
d_13:           dq 13.0
f_quarter:      dd 0.25
f_half:         dd 0.5
; ore id, veins, vein size, ymax
ore_table:      dd 15, 12, 8, 64            ; coal
                dd 14,  8, 6, 60            ; iron
                dd 13,  2, 5, 30            ; gold
                dd 56,  1, 4, 16            ; diamond

section .bss
alignb 8
pu_old_cwd:     resb PU_PATH
pu_tmp_dir:     resb PU_PATH
pu_counter:     resd 1
alignb 8
global pu_base_ft
pu_base_ft:     resq 1                          ; FILETIME at case start

section .text

PROC pu_memset, 0
    mov  rdi, rcx
    mov  eax, edx
    mov  rcx, r8
    rep  stosb
ENDP

PROC pu_memcpy, 0
    mov  rdi, rcx
    mov  rsi, rdx
    mov  rcx, r8
    rep  movsb
ENDP

PROC pu_strcpy, 0
.l: mov  al, [rdx]
    mov  [rcx], al
    inc  rcx
    inc  rdx
    test al, al
    jnz  .l
ENDP

PROC pu_strlen, 0
    xor  eax, eax
.l: cmp  byte [rcx+rax], 0
    je   .done
    inc  rax
    jmp  .l
.done:
ENDP

PROC pu_contains, 0
    mov  rsi, rcx
.outer:
    xor  r8d, r8d
.inner:
    mov  al, [rdx+r8]
    test al, al
    jz   .yes
    cmp  [rsi+r8], al
    jne  .next
    inc  r8
    jmp  .inner
.next:
    cmp  byte [rsi], 0
    je   .no
    inc  rsi
    jmp  .outer
.yes:
    mov  eax, 1
    jmp  .done
.no:
    xor  eax, eax
.done:
ENDP

PROC pu_set_world_name, 0
    mov  rbx, rcx
    lea  rcx, [rel g_world_name]
    xor  edx, edx
    mov  r8d, 64
    call pu_memset
    lea  rcx, [rel g_world_name]
    mov  rdx, rbx
    call pu_strcpy
ENDP

PROC pu_clear_entities, 0
    lea  rcx, [rel g_entities]
    xor  edx, edx
    mov  r8d, ENTITY_size*MAX_ENTITIES
    call pu_memset
    mov  dword [rel g_entity_count], 0
ENDP

PROC pu_entity_ptr, 0
    mov  eax, ecx
    shl  rax, 7
    lea  rdx, [rel g_entities]
    add  rax, rdx
ENDP

PROC pu_put_entity, 0
    mov  rbx, rdx
    call pu_entity_ptr
    mov  rcx, rax
    mov  rdx, rbx
    mov  r8d, ENTITY_size
    call pu_memcpy
ENDP

; fresh %TEMP% dir as cwd, world "TestWorld", alloc counter + entities reset
PROC pu_case_begin, 0
    call t_begin
    lea  rcx, [rel pu_old_cwd]
    mov  edx, PU_PATH
    xchg rcx, rdx                       ; (len, buf) order
    call GetCurrentDirectoryA
    lea  rbx, [rel pu_tmp_dir]
    mov  ecx, 512
    mov  rdx, rbx
    call GetTempPathA
    ; temp path copied to +512 first, wsprintf writes over the original
    lea  rcx, [rbx+512]
    mov  rdx, rbx
    call pu_strcpy
    call GetCurrentProcessId
    mov  r9d, eax
    inc  dword [rel pu_counter]
    mov  eax, [rel pu_counter]
    mov  [rsp+32], rax
    mov  rcx, rbx
    lea  rdx, [rel s_tmp_fmt]
    lea  r8, [rbx+512]
    call wsprintfA
    mov  rcx, rbx
    call pu_rmtree                      ; leftovers of a crashed run
    mov  rcx, rbx
    xor  edx, edx
    call CreateDirectoryA
    mov  rcx, rbx
    call SetCurrentDirectoryA
    lea  rcx, [rel s_test_world]
    call pu_set_world_name
    mov  dword [rel mock_alloc_count], 0
    call pu_clear_entities
    lea  rcx, [rel pu_base_ft]
    call GetSystemTimeAsFileTime
ENDP

PROC pu_case_end, 0
    mov  eax, [rel mock_alloc_count]
    movsxd rcx, eax
    xor  edx, edx
    lea  r8, [rel s_leak]
    lea  r9, [rel s_leak_file]
    mov  qword [rsp+32], __?LINE?__
    call t_check_eq64
    lea  rcx, [rel pu_old_cwd]
    call SetCurrentDirectoryA
    lea  rcx, [rel pu_tmp_dir]
    call pu_rmtree
ENDP

; rm -r, errors ignored
PROC pu_rmtree, PU_PATH*2 + FD_SIZE
    mov  rsi, rcx
    lea  rdi, LOC(0)
    lea  r12, LOC(PU_PATH)
    lea  r13, LOC(PU_PATH*2)            ; WIN32_FIND_DATAA
    mov  rcx, r12
    mov  rdx, rsi
    call pu_strcpy
    mov  rcx, r12
    call pu_strlen
    lea  rcx, [r12+rax]
    lea  rdx, [rel s_star]
    call pu_strcpy
    mov  rcx, r12
    mov  rdx, r13
    call FindFirstFileA
    cmp  rax, -1
    je   .rmdir
    mov  r14, rax
.entry:
    lea  rax, [r13+FD_NAME]
    cmp  byte [rax], '.'
    jne  .use
    cmp  byte [rax+1], 0
    je   .next
    cmp  byte [rax+1], '.'
    jne  .use
    cmp  byte [rax+2], 0
    je   .next
.use:
    mov  rcx, rdi
    mov  rdx, rsi
    call pu_strcpy
    mov  rcx, rdi
    call pu_strlen
    mov  byte [rdi+rax], '\'
    lea  rcx, [rdi+rax+1]
    lea  rdx, [r13+FD_NAME]
    call pu_strcpy
    test dword [r13+FD_ATTR], 0x10      ; FILE_ATTRIBUTE_DIRECTORY
    jz   .file
    mov  rcx, rdi
    call pu_rmtree
    jmp  .next
.file:
    mov  rcx, rdi
    mov  edx, 0x80
    call SetFileAttributesA
    mov  rcx, rdi
    call DeleteFileA
.next:
    mov  rcx, r14
    mov  rdx, r13
    call FindNextFileA
    test eax, eax
    jnz  .entry
    mov  rcx, r14
    call FindClose
.rmdir:
    mov  rcx, rsi
    call RemoveDirectoryA
ENDP

; rax = t_alloc'd buffer (16 spare zero bytes) or 0, rdx = size
PROC pu_read_file, 32
    mov  edx, 0x80000000                ; GENERIC_READ
    mov  r8d, 7
    xor  r9d, r9d
    mov  qword [rsp+32], 3              ; OPEN_EXISTING
    mov  qword [rsp+40], 0x80
    mov  qword [rsp+48], 0
    call CreateFileA
    cmp  rax, -1
    je   .fail
    mov  rbx, rax
    mov  rcx, rbx
    lea  rdx, LOC(0)
    call GetFileSizeEx
    mov  r12, LOC(0)
    lea  rcx, [r12+16]
    call t_alloc
    mov  rsi, rax
    mov  rcx, rbx
    mov  rdx, rsi
    mov  r8d, r12d
    lea  r9, LOC(8)
    mov  qword [rsp+32], 0
    call ReadFile
    mov  rcx, rbx
    call CloseHandle
    mov  rax, rsi
    mov  rdx, r12
    jmp  .done
.fail:
    xor  eax, eax
    xor  edx, edx
.done:
ENDP

PROC pu_write_file, 16
    mov  rsi, rdx
    mov  r12, r8
    mov  edx, 0x40000000                ; GENERIC_WRITE
    xor  r8d, r8d
    xor  r9d, r9d
    mov  qword [rsp+32], 2              ; CREATE_ALWAYS
    mov  qword [rsp+40], 0x80
    mov  qword [rsp+48], 0
    call CreateFileA
    cmp  rax, -1
    je   .fail
    mov  rbx, rax
    mov  rcx, rbx
    mov  rdx, rsi
    mov  r8d, r12d
    lea  r9, LOC(0)
    mov  qword [rsp+32], 0
    call WriteFile
    mov  edi, eax
    mov  rcx, rbx
    call CloseHandle
    mov  eax, edi
    jmp  .done
.fail:
    xor  eax, eax
.done:
ENDP

PROC pu_write_str, 0
    mov  rbx, rcx
    mov  rsi, rdx
    mov  rcx, rdx
    call pu_strlen
    mov  rcx, rbx
    mov  rdx, rsi
    mov  r8, rax
    call pu_write_file
ENDP

PROC pu_exists, 0
    call GetFileAttributesA
    cmp  eax, -1
    setne al
    movzx eax, al
ENDP

PROC pu_is_dir, 0
    call GetFileAttributesA
    cmp  eax, -1
    je   .no
    shr  eax, 4
    and  eax, 1
    jmp  .done
.no:
    xor  eax, eax
.done:
ENDP

; WIN32_FILE_ATTRIBUTE_DATA: mtime at 20, size hi/lo at 28/32
PROC pu_file_size, 48
    xor  edx, edx
    lea  r8, LOC(0)
    call GetFileAttributesExA
    test eax, eax
    jz   .no
    mov  eax, LOC(28)
    shl  rax, 32
    mov  ecx, LOC(32)
    or   rax, rcx
    jmp  .done
.no:
    mov  rax, -1
.done:
ENDP

PROC pu_file_mtime, 48
    xor  edx, edx
    lea  r8, LOC(0)
    call GetFileAttributesExA
    test eax, eax
    jz   .no
    mov  rax, LOC(20)
    jmp  .done
.no:
    xor  eax, eax
.done:
ENDP

; backdate access + write time to pu_base_ft - edx seconds
PROC pu_set_mtime_ago, 16
    mov  eax, edx
    imul rax, rax, 10000000
    mov  rdx, [rel pu_base_ft]
    sub  rdx, rax
    mov  LOC(0), rdx
    mov  edx, 0x100                     ; FILE_WRITE_ATTRIBUTES
    mov  r8d, 7
    xor  r9d, r9d
    mov  qword [rsp+32], 3              ; OPEN_EXISTING
    mov  qword [rsp+40], 0x80
    mov  qword [rsp+48], 0
    call CreateFileA
    cmp  rax, -1
    je   .done
    mov  rbx, rax
    mov  rcx, rbx
    xor  edx, edx
    lea  r8, LOC(0)
    lea  r9, LOC(0)
    call SetFileTime
    mov  rcx, rbx
    call CloseHandle
.done:
ENDP

PROC pu_rle_ref, 0
    mov  rsi, rcx
    mov  r12, rdx
    mov  rdi, r8
    xor  ebx, ebx
.run:
    cmp  rbx, r12
    jae  .end
    mov  al, [rsi+rbx]
    lea  rcx, [rbx+1]
.ext:
    cmp  rcx, r12
    jae  .emit
    mov  rdx, rcx
    sub  rdx, rbx
    cmp  rdx, 255
    jae  .emit
    cmp  [rsi+rcx], al
    jne  .emit
    inc  rcx
    jmp  .ext
.emit:
    mov  rdx, rcx
    sub  rdx, rbx
    mov  [rdi], dl
    mov  [rdi+1], al
    add  rdi, 2
    mov  rbx, rcx
    jmp  .run
.end:
    mov  rax, rdi
    sub  rax, r8
ENDP

PROC pu_fnv32, 0
    mov  eax, 0x811C9DC5
    xor  r8d, r8d
.l: cmp  r8, rdx
    jae  .done
    movzx r9d, byte [rcx+r8]
    xor  eax, r9d
    imul eax, eax, 0x01000193
    inc  r8
    jmp  .l
.done:
ENDP

PROC pu_rand_below, 0
    mov  ebx, ecx
    call t_rng_next
    mul  rbx                            ; rdx = floor(rax * n / 2^64)
    mov  eax, edx
ENDP

PROC pu_rand_double, 0
    call t_rng_next
    shr  rax, 11
    cvtsi2sd xmm0, rax
    mulsd xmm0, [rel d_two_m53]
ENDP

PROC pu_rand_uniform, 16
    movsd LOC(0), xmm0
    subsd xmm1, xmm0
    movsd LOC(8), xmm1
    call pu_rand_double
    mulsd xmm0, LOC(8)
    addsd xmm0, LOC(0)
ENDP
