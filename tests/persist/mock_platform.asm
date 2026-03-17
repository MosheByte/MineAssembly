; fake platform/world layer for the persist tests: real win32 file io plus
; mock_* counters the tests look at. the rest of api.inc gets auto-stubbed.
bits 64
default rel

extern GetProcessHeap, HeapAlloc, HeapFree
extern CreateFileA, ReadFile, WriteFile, CloseHandle, GetFileSizeEx
extern CreateDirectoryA, GetLastError, GetFileAttributesA, DeleteFileA
extern g_player

global mem_alloc, mem_free, file_read_all, file_write_all, file_exists
global file_delete, dir_create, log_write, log_printf
global worldgen_biome_at, light_init_chunk_sky, chunkmgr_save_all, chat_add
global mock_light_calls, mock_saveall_calls, mock_chat_calls, mock_last_chat
global mock_alloc_count, player_respawn, mock_respawn_calls

section .bss
alignb 8
mock_light_calls:   resd 1
mock_saveall_calls: resd 1
mock_chat_calls:    resd 1
mock_alloc_count:   resd 1          ; live blocks, for the leak check
mock_last_chat:     resq 1
mock_respawn_calls: resd 1

section .text

mem_alloc:
    push rbx
    sub  rsp, 32
    mov  rbx, rcx
    call GetProcessHeap
    mov  rcx, rax
    mov  edx, 8                     ; HEAP_ZERO_MEMORY
    mov  r8, rbx
    call HeapAlloc
    test rax, rax
    jz   .r
    lock inc dword [rel mock_alloc_count]
.r:
    add  rsp, 32
    pop  rbx
    ret

mem_free:
    push rbx
    sub  rsp, 32
    mov  rbx, rcx
    test rcx, rcx
    jz   .r
    lock dec dword [rel mock_alloc_count]
    call GetProcessHeap
    mov  rcx, rax
    xor  edx, edx
    mov  r8, rbx
    call HeapFree
.r:
    add  rsp, 32
    pop  rbx
    ret

; +1 byte so the result is always NUL terminated
file_read_all:
    push rbx
    push rsi
    push rdi
    push r12
    sub  rsp, 72
    mov  rbx, rdx
    mov  edx, 0x80000000            ; GENERIC_READ
    mov  r8d, 1                     ; FILE_SHARE_READ
    xor  r9d, r9d
    mov  qword [rsp+32], 3          ; OPEN_EXISTING
    mov  qword [rsp+40], 0x80
    mov  qword [rsp+48], 0
    call CreateFileA
    cmp  rax, -1
    je   .fail
    mov  rsi, rax
    mov  rcx, rsi
    lea  rdx, [rsp+56]
    call GetFileSizeEx
    mov  r12, [rsp+56]
    lea  rcx, [r12+1]
    call mem_alloc
    mov  rdi, rax
    mov  rcx, rsi
    mov  rdx, rdi
    mov  r8d, r12d
    lea  r9, [rsp+64]
    mov  qword [rsp+32], 0
    call ReadFile
    mov  rcx, rsi
    call CloseHandle
    test rbx, rbx
    jz   .nosize
    mov  [rbx], r12
.nosize:
    mov  rax, rdi
    jmp  .r
.fail:
    xor  eax, eax
.r:
    add  rsp, 72
    pop  r12
    pop  rdi
    pop  rsi
    pop  rbx
    ret

file_write_all:
    push rbx
    push rsi
    push rdi
    push r12
    sub  rsp, 72
    mov  rsi, rdx
    mov  r12, r8
    mov  edx, 0x40000000            ; GENERIC_WRITE
    xor  r8d, r8d
    xor  r9d, r9d
    mov  qword [rsp+32], 2          ; CREATE_ALWAYS
    mov  qword [rsp+40], 0x80
    mov  qword [rsp+48], 0
    call CreateFileA
    cmp  rax, -1
    je   .fail
    mov  rbx, rax
    mov  rcx, rbx
    mov  rdx, rsi
    mov  r8d, r12d
    lea  r9, [rsp+64]
    mov  qword [rsp+64], 0
    mov  qword [rsp+32], 0
    call WriteFile
    mov  edi, eax
    mov  rcx, rbx
    call CloseHandle
    xor  eax, eax
    test edi, edi
    jz   .r
    cmp  [rsp+64], r12d
    jne  .r
    mov  eax, 1
    jmp  .r
.fail:
    xor  eax, eax
.r:
    add  rsp, 72
    pop  r12
    pop  rdi
    pop  rsi
    pop  rbx
    ret

file_exists:
    sub  rsp, 40
    call GetFileAttributesA
    cmp  eax, -1
    setne al
    movzx eax, al
    add  rsp, 40
    ret

file_delete:
    sub  rsp, 40
    call DeleteFileA
    add  rsp, 40
    ret

dir_create:
    sub  rsp, 40
    xor  edx, edx
    call CreateDirectoryA
    test eax, eax
    jnz  .ok
    call GetLastError
    cmp  eax, 183                   ; ERROR_ALREADY_EXISTS
    jne  .no
.ok:
    mov  eax, 1
    jmp  .r
.no:
    xor  eax, eax
.r:
    add  rsp, 40
    ret

log_write:
log_printf:
    xor  eax, eax
    ret

; fake biome, test_save_chunks recomputes the same formula
worldgen_biome_at:
    imul ecx, ecx, 7
    imul edx, edx, 13
    lea  eax, [rcx+rdx]
    and  eax, 0x7FFFFFFF
    xor  edx, edx
    mov  ecx, 12
    div  ecx
    mov  eax, edx
    ret

light_init_chunk_sky:
    lock inc dword [rel mock_light_calls]
    ret

chunkmgr_save_all:
    inc  dword [rel mock_saveall_calls]
    ret

chat_add:
    inc  dword [rel mock_chat_calls]
    mov  [rel mock_last_chat], rcx
    ret

; same two stores as the real one, plus a counter
player_respawn:
    inc  dword [rel mock_respawn_calls]
    lea  rax, [rel g_player]
    mov  dword [rax+96], 0          ; PLAYER.dead
    mov  dword [rax+60], 20         ; PLAYER.health
    ret
