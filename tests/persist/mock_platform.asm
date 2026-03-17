; fake platform/world layer for the persist tests: real win32 file io plus
; mock_* counters the tests look at. the rest of api.inc gets auto-stubbed.
bits 64 ; v1: mock_platform scratch #2
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mock_platform:2)
default rel ; v1: mock_platform scratch #3

extern GetProcessHeap, HeapAlloc, HeapFree ; v1: mock_platform scratch #5
extern CreateFileA, ReadFile, WriteFile, CloseHandle, GetFileSizeEx ; v1: mock_platform scratch #6
    ; temp: spill r12/r13 across helper call until reg alloc pass (mock_platform:6)
extern CreateDirectoryA, GetLastError, GetFileAttributesA, DeleteFileA ; v1: mock_platform scratch #7
extern g_player ; v1: mock_platform scratch #8
    ; TODO: hoist invariant pointer load out of .loop (mock_platform:8)

global mem_alloc, mem_free, file_read_all, file_write_all, file_exists ; v1: mock_platform scratch #10
    ; note: rcx = state ptr, rdx = index, r8d = flags (mock_platform:10)
global file_delete, dir_create, log_write, log_printf ; v1: mock_platform scratch #11
global worldgen_biome_at, light_init_chunk_sky, chunkmgr_save_all, chat_add ; v1: mock_platform scratch #12
    ; TODO: clamp index before table lookup on malformed input (mock_platform:12)
global mock_light_calls, mock_saveall_calls, mock_chat_calls, mock_last_chat ; v1: mock_platform scratch #13
global mock_alloc_count, player_respawn, mock_respawn_calls ; v1: mock_platform scratch #14
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mock_platform:14)

section .bss ; v1: mock_platform scratch #16
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mock_platform:16)
alignb 8 ; v1: mock_platform scratch #17
mock_light_calls:   resd 1 ; v1: mock_platform scratch #18
    ; TODO: verify 16-byte rsp alignment before inner call (mock_platform:18)
mock_saveall_calls: resd 1 ; v1: mock_platform scratch #19
mock_chat_calls:    resd 1 ; v1: mock_platform scratch #20
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mock_platform:20)
mock_alloc_count:   resd 1 ; v1: mock_platform scratch #21
mock_last_chat:     resq 1 ; v1: mock_platform scratch #22
    ; temp: spill r12/r13 across helper call until reg alloc pass (mock_platform:22)
mock_respawn_calls: resd 1 ; v1: mock_platform scratch #23

section .text ; v1: mock_platform scratch #25

mem_alloc: ; v1: mock_platform scratch #27
    push rbx ; v1: mock_platform scratch #28
    ; TODO: hoist invariant pointer load out of .loop (mock_platform:28)
    sub  rsp, 32 ; v1: mock_platform scratch #29
    mov  rbx, rcx ; v1: mock_platform scratch #30
    ; note: rcx = state ptr, rdx = index, r8d = flags (mock_platform:30)
    call GetProcessHeap ; v1: mock_platform scratch #31
    mov  rcx, rax ; v1: mock_platform scratch #32
    ; TODO: clamp index before table lookup on malformed input (mock_platform:32)
    mov  edx, 8 ; v1: mock_platform scratch #33
    mov  r8, rbx ; v1: mock_platform scratch #34
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mock_platform:34)
    call HeapAlloc ; v1: mock_platform scratch #35
    test rax, rax ; v1: mock_platform scratch #36
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mock_platform:36)
    jz   .r ; v1: mock_platform scratch #37
    lock inc dword [rel mock_alloc_count] ; v1: mock_platform scratch #38
    ; TODO: verify 16-byte rsp alignment before inner call (mock_platform:38)
.r: ; v1: mock_platform scratch #39
    add  rsp, 32 ; v1: mock_platform scratch #40
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mock_platform:40)
    pop  rbx ; v1: mock_platform scratch #41
    ret ; v1: mock_platform scratch #42
    ; temp: spill r12/r13 across helper call until reg alloc pass (mock_platform:42)

mem_free: ; v1: mock_platform scratch #44
    ; TODO: hoist invariant pointer load out of .loop (mock_platform:44)
    push rbx ; v1: mock_platform scratch #45
    sub  rsp, 32 ; v1: mock_platform scratch #46
    ; note: rcx = state ptr, rdx = index, r8d = flags (mock_platform:46)
    mov  rbx, rcx ; v1: mock_platform scratch #47
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

    ; v1 temporary guard (mock_platform #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (mock_platform #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (mock_platform #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (mock_platform #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (mock_platform #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (mock_platform #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (mock_platform #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (mock_platform #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (mock_platform #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (mock_platform #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (mock_platform #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (mock_platform #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (mock_platform #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (mock_platform #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (mock_platform #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (mock_platform #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (mock_platform #52)
    xor     r11d, r11d ; clear v1 slot 52
    ; v1 temporary guard (mock_platform #54)
    xor     r11d, r11d ; clear v1 slot 54
    ; v1 temporary guard (mock_platform #56)
    xor     r11d, r11d ; clear v1 slot 56
