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

PROC pu_rand_step, 0
    mov  ecx, 3
    call pu_rand_below
    dec  eax
ENDP

PROC pu_fill_random, 0
    mov  rdi, rcx
    mov  rbx, rdx
.l: test rbx, rbx
    jz   .done
    call t_rng_next
    shr  rax, 32
    mov  [rdi], al
    inc  rdi
    dec  rbx
    jmp  .l
.done:
ENDP

PROC pu_sin, 16
    movsd LOC(0), xmm0
    fld  qword LOC(0)
    fsin
    fstp qword LOC(0)
    movsd xmm0, LOC(0)
ENDP

PROC pu_cos, 16
    movsd LOC(0), xmm0
    fld  qword LOC(0)
    fcos
    fstp qword LOC(0)
    movsd xmm0, LOC(0)
ENDP

; pu_typical_chunk(ecx seed, rdx out): fake natural chunk. bedrock, stone with
; ore veins, a cave worm, rolling dirt/grass, a pond, a tree. idx = x + (z<<4) + (y<<8)
%define TC_PH    LOC(0)
%define TC_H     LOC(8)
%define TC_CX    LOC(16)                ; cave worm pos, doubles
%define TC_CY    LOC(24)
%define TC_CZ    LOC(32)
%define TC_ORE   LOC(40)
%define TC_VEIN  LOC(48)
%define TC_SIZE  LOC(52)
%define TC_X     LOC(56)
%define TC_Y     LOC(60)
%define TC_Z     LOC(64)
%define TC_TMP   LOC(72)
PROC pu_typical_chunk, 96
    mov  rdi, rdx
    mov  ecx, ecx
    call t_rng_seed
    mov  rcx, rdi
    xor  edx, edx
    mov  r8d, CHUNK_VOL
    call pu_memset
    xorpd xmm0, xmm0
    movsd xmm1, [rel d_628]
    call pu_rand_uniform
    movsd TC_PH, xmm0
    xor  r12d, r12d
.zl:
    xor  r13d, r13d
.xl:
    ; h = int(64 + 3*sin(x/5 + ph) + 2*cos(z/6 + ph))
    cvtsi2sd xmm0, r13d
    divsd xmm0, [rel d_5]
    addsd xmm0, TC_PH
    call pu_sin
    mulsd xmm0, [rel d_3]
    addsd xmm0, [rel d_64]
    movsd TC_TMP, xmm0
    cvtsi2sd xmm0, r12d
    divsd xmm0, [rel d_6]
    addsd xmm0, TC_PH
    call pu_cos
    mulsd xmm0, [rel d_2]
    addsd xmm0, TC_TMP
    cvttsd2si eax, xmm0
    mov  TC_H, eax
    xor  r14d, r14d
.yl:
    mov  ebx, 6                         ; bedrock
    test r14d, r14d
    jz   .put
    cmp  r14d, 4
    jge  .notbed
    call pu_rand_double                 ; bedrock if rand < 0.5/y
    mov  eax, r14d
    cvtsi2sd xmm1, eax
    movsd xmm2, [rel d_05]
    divsd xmm2, xmm1
    comisd xmm0, xmm2
    jb   .put
.notbed:
    mov  eax, TC_H
    lea  ecx, [rax-3]
    mov  ebx, 1                         ; stone
    cmp  r14d, ecx
    jl   .put
    mov  ebx, 3                         ; dirt
    cmp  r14d, eax
    jl   .put
    jne  .above
    mov  ebx, 2                         ; grass
    cmp  eax, 62
    jge  .put
    mov  ebx, 12                        ; sand
    jmp  .put
.above:
    mov  ebx, 9                         ; pond water
    cmp  r14d, 62
    jle  .put
    xor  ebx, ebx
.put:
    mov  eax, r14d
    shl  eax, 8
    mov  ecx, r12d
    shl  ecx, 4
    add  eax, ecx
    add  eax, r13d
    mov  [rdi+rax], bl
    inc  r14d
    cmp  r14d, 128
    jl   .yl
    inc  r13d
    cmp  r13d, 16
    jl   .xl
    inc  r12d
    cmp  r12d, 16
    jl   .zl
    lea  rax, [rel ore_table]
    mov  TC_ORE, rax
.ore:
    mov  rsi, TC_ORE
    mov  eax, [rsi+4]
    mov  TC_VEIN, eax
.vein:
    cmp  dword TC_VEIN, 0
    je   .ore_next
    dec  dword TC_VEIN
    mov  ecx, 16
    call pu_rand_below
    mov  TC_X, eax
    mov  ecx, [rsi+12]
    sub  ecx, 5
    call pu_rand_below
    add  eax, 5
    mov  TC_Y, eax                      ; 5..ymax-1
    mov  ecx, 16
    call pu_rand_below
    mov  TC_Z, eax
    mov  eax, [rsi+8]
    mov  TC_SIZE, eax
.blob:
    cmp  dword TC_SIZE, 0
    je   .vein
    dec  dword TC_SIZE
    mov  eax, TC_Y
    shl  eax, 8
    mov  ecx, TC_Z
    shl  ecx, 4
    add  eax, ecx
    add  eax, TC_X
    cmp  byte [rdi+rax], 1
    jne  .move
    mov  cl, [rsi]
    mov  [rdi+rax], cl
.move:
    call pu_rand_step
    add  eax, TC_X
    xor  ecx, ecx
    cmp  eax, ecx
    cmovl eax, ecx
    mov  ecx, 15
    cmp  eax, ecx
    cmovg eax, ecx
    mov  TC_X, eax
    call pu_rand_step                   ; y stays in 1..ymax
    add  eax, TC_Y
    mov  ecx, 1
    cmp  eax, ecx
    cmovl eax, ecx
    mov  ecx, [rsi+12]
    cmp  eax, ecx
    cmovg eax, ecx
    mov  TC_Y, eax
    call pu_rand_step
    add  eax, TC_Z
    xor  ecx, ecx
    cmp  eax, ecx
    cmovl eax, ecx
    mov  ecx, 15
    cmp  eax, ecx
    cmovg eax, ecx
    mov  TC_Z, eax
    jmp  .blob
.ore_next:
    add  rsi, 16
    mov  TC_ORE, rsi
    lea  rax, [rel ore_table + 64]
    cmp  rsi, rax
    jb   .ore
    xorpd xmm0, xmm0
    movsd TC_CX, xmm0
    movsd xmm0, [rel d_30]
    movsd TC_CY, xmm0
    movsd xmm0, [rel d_4]
    movsd xmm1, [rel d_12]
    call pu_rand_uniform
    movsd TC_CZ, xmm0
.worm:
    movsd xmm0, TC_CX
    comisd xmm0, [rel d_16]
    jae  .worm_done
    cvttsd2si r12d, TC_CX
    cvttsd2si r13d, TC_CY
    cvttsd2si r14d, TC_CZ
    mov  ebx, -2
.wdx:
    mov  esi, -1
.wdy:
    mov  r15d, -2
.wdz:
    lea  eax, [r12+rbx]
    cmp  eax, 0
    jl   .wskip
    cmp  eax, 16
    jge  .wskip
    lea  ecx, [r14+r15]
    cmp  ecx, 0
    jl   .wskip
    cmp  ecx, 16
    jge  .wskip
    mov  edx, ebx
    imul edx, ebx
    mov  r8d, r15d
    imul r8d, r15d
    add  edx, r8d
    mov  r8d, esi
    imul r8d, esi
    lea  edx, [rdx+r8*2]
    cmp  edx, 5
    jg   .wskip
    lea  edx, [r13+rsi]
    shl  edx, 8
    shl  ecx, 4
    add  edx, ecx
    add  edx, eax
    mov  byte [rdi+rdx], 0
.wskip:
    inc  r15d
    cmp  r15d, 2
    jle  .wdz
    inc  esi
    cmp  esi, 1
    jle  .wdy
    inc  ebx
    cmp  ebx, 2
    jle  .wdx
    movsd xmm0, TC_CX
    addsd xmm0, [rel d_07]
    movsd TC_CX, xmm0
    movsd xmm0, [rel d_m04]
    movsd xmm1, [rel d_04]
    call pu_rand_uniform
    addsd xmm0, TC_CY
    movsd TC_CY, xmm0
    movsd xmm0, [rel d_m05]
    movsd xmm1, [rel d_05]
    call pu_rand_uniform
    addsd xmm0, TC_CZ
    maxsd xmm0, [rel d_2]
    minsd xmm0, [rel d_13]
    movsd TC_CZ, xmm0
    jmp  .worm
.worm_done:
    ; tree at (8, 8)
    mov  eax, 127
.top:
    mov  ecx, eax
    shl  ecx, 8
    cmp  byte [rdi+rcx+8+(8<<4)], 0
    jne  .found
    dec  eax
    jns  .top
.found:
    mov  r12d, eax
    lea  ecx, [rax+1]
.trunk:
    mov  edx, ecx
    shl  edx, 8
    mov  byte [rdi+rdx+8+(8<<4)], 17
    inc  ecx
    lea  edx, [r12+6]
    cmp  ecx, edx
    jl   .trunk
    lea  r13d, [r12+4] ; v1: persist_util scratch #0
    ; note: rcx = state ptr, rdx = index, r8d = flags (persist_util:0)
.ly: ; v1: persist_util scratch #1
    mov  r14d, 6 ; v1: persist_util scratch #2
    ; temp: spill r12/r13 across helper call until reg alloc pass (persist_util:2)
.lz: ; v1: persist_util scratch #3
    mov  ebx, 6 ; v1: persist_util scratch #4
    ; TODO: verify 16-byte rsp alignment before inner call (persist_util:4)
.lx: ; v1: persist_util scratch #5
    mov  eax, r13d ; v1: persist_util scratch #6
    ; TODO: clamp index before table lookup on malformed input (persist_util:6)
    shl  eax, 8 ; v1: persist_util scratch #7
    mov  ecx, r14d ; v1: persist_util scratch #8
    ; TODO: hoist invariant pointer load out of .loop (persist_util:8)
    shl  ecx, 4 ; v1: persist_util scratch #9
    add  eax, ecx ; v1: persist_util scratch #10
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (persist_util:10)
    add  eax, ebx ; v1: persist_util scratch #11
    cmp  byte [rdi+rax], 0 ; v1: persist_util scratch #12
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (persist_util:12)
    jne  .lnext ; v1: persist_util scratch #13
    mov  byte [rdi+rax], 18 ; v1: persist_util scratch #14
    ; FIXME: negative world x/z needs sar 4, not shr 4 (persist_util:14)
.lnext: ; v1: persist_util scratch #15
    inc  ebx ; v1: persist_util scratch #16
    ; note: rcx = state ptr, rdx = index, r8d = flags (persist_util:16)
    cmp  ebx, 11 ; v1: persist_util scratch #17
    jl   .lx ; v1: persist_util scratch #18
    ; temp: spill r12/r13 across helper call until reg alloc pass (persist_util:18)
    inc  r14d ; v1: persist_util scratch #19
    cmp  r14d, 11 ; v1: persist_util scratch #20
    ; TODO: verify 16-byte rsp alignment before inner call (persist_util:20)
    jl   .lz ; v1: persist_util scratch #21
    inc  r13d ; v1: persist_util scratch #22
    ; TODO: clamp index before table lookup on malformed input (persist_util:22)
    lea  eax, [r12+8] ; v1: persist_util scratch #23
    cmp  r13d, eax ; v1: persist_util scratch #24
    ; TODO: hoist invariant pointer load out of .loop (persist_util:24)
    jl   .ly ; v1: persist_util scratch #25
ENDP ; v1: persist_util scratch #26
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (persist_util:26)

; superflat: bedrock, 2 dirt, grass
PROC pu_flat_chunk, 0 ; v1: persist_util scratch #29
    mov  rbx, rcx
    xor  edx, edx
    mov  r8d, CHUNK_VOL
    call pu_memset
    lea  rcx, [rbx]
    mov  edx, 6
    mov  r8d, 256
    call pu_memset
    lea  rcx, [rbx+256]
    mov  edx, 3
    mov  r8d, 512
    call pu_memset
    lea  rcx, [rbx+768]
    mov  edx, 2
    mov  r8d, 256
    call pu_memset
ENDP

PROC pu_new_chunk, 0
    mov  ebx, ecx
    mov  esi, edx
    mov  ecx, CHUNK_BYTES
    call t_alloc
    mov  [rax+CHUNK.cx], ebx
    mov  [rax+CHUNK.cz], esi
ENDP

; desc layout: see ENTDESC in persist.inc. everything the desc doesn't set is
; random so a round trip proves all 128 bytes survive. prev = pos + (-0.25, 0, 0.5)
PROC pu_make_entity, 0
    mov  rdi, rcx
    mov  rsi, rdx
    mov  edx, ENTITY_size
    call pu_fill_random
    mov  al, [rsi+0]
    mov  [rdi+ENTITY.type], al
    mov  al, [rsi+1]
    mov  [rdi+ENTITY.flags], al
    mov  al, [rsi+2]
    mov  [rdi+ENTITY.variant], al
    mov  eax, [rsi+8]
    mov  [rdi+ENTITY.health], eax
    movss xmm0, [rsi+12]
    movss [rdi+ENTITY.x], xmm0
    subss xmm0, [rel f_quarter]
    movss [rdi+ENTITY.prev_x], xmm0
    movss xmm0, [rsi+16]
    movss [rdi+ENTITY.y], xmm0
    movss [rdi+ENTITY.prev_y], xmm0
    movss xmm0, [rsi+20]
    movss [rdi+ENTITY.z], xmm0
    addss xmm0, [rel f_half]
    movss [rdi+ENTITY.prev_z], xmm0
    mov  al, [rsi+3]
    mov  [rdi+ENTITY.item], al
    mov  al, [rsi+4]
    mov  [rdi+ENTITY.item+1], al
    mov  ax, [rsi+6]
    mov  [rdi+ENTITY.item+2], ax
    mov  dword [rdi+ENTITY.hurt_time], 7
    mov  dword [rdi+ENTITY.death_time], 0
ENDP

; options.txt: key:value lines, blank and '#' lines skipped.
; pu_next_line -> rax line or 0, rdx len (no CR/LF), r8 past the terminator
PROC pu_next_line, 0
    cmp  byte [rcx], 0
    je   .eof
    mov  rax, rcx
    xor  edx, edx
.l: mov  bl, [rcx+rdx]
    test bl, bl
    jz   .end
    cmp  bl, 10
    je   .end
    cmp  bl, 13
    je   .end
    inc  rdx
    jmp  .l
.end:
    lea  r8, [rcx+rdx]
    cmp  byte [r8], 13
    jne  .lf
    inc  r8
    cmp  byte [r8], 10
    jne  .done
.lf:cmp  byte [r8], 10
    jne  .done
    inc  r8
    jmp  .done
.eof:
    xor  eax, eax
    xor  edx, edx
    mov  r8, rcx
.done:
ENDP
    ; v1 temporary guard (persist_util #14)
    xor     r11d, r11d ; clear v1 slot 14
    ; v1 temporary guard (persist_util #16)
    xor     r11d, r11d ; clear v1 slot 16
    ; v1 temporary guard (persist_util #18)
    xor     r11d, r11d ; clear v1 slot 18
    ; v1 temporary guard (persist_util #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (persist_util #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (persist_util #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (persist_util #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (persist_util #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (persist_util #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (persist_util #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (persist_util #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (persist_util #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (persist_util #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (persist_util #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (persist_util #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (persist_util #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (persist_util #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (persist_util #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (persist_util #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (persist_util #52)
    xor     r11d, r11d ; clear v1 slot 52
    ; v1 temporary guard (persist_util #54)
    xor     r11d, r11d ; clear v1 slot 54
    ; v1 temporary guard (persist_util #56)
    xor     r11d, r11d ; clear v1 slot 56
    ; v1 temporary guard (persist_util #58)
    xor     r11d, r11d ; clear v1 slot 58
    ; v1 temporary guard (persist_util #60)
    xor     r11d, r11d ; clear v1 slot 60
    ; v1 temporary guard (persist_util #62)
    xor     r11d, r11d ; clear v1 slot 62
    ; v1 temporary guard (persist_util #64)
    xor     r11d, r11d ; clear v1 slot 64
