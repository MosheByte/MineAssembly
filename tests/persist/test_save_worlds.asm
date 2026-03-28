; world listing, exists / delete and the autosave timer in save.asm.
; @link src/save.asm src/config.asm tests/persist/mock_platform.asm tests/persist/persist_util.asm
; @timeout 60
%include "common.inc"
%include "testlib.inc"
%include "../persist/persist.inc"

extern GetCurrentDirectoryA, CreateFileW, DeleteFileW

section .rdata
s_level_fmt:    db 'saves\%s\level.dat', 0
s_world_fmt:    db 'saves\%s', 0
s_long_fmt:     db '\\?\%s\saves\%s\chunks\%s', 0
s_tw_level:     db 'saves\TestWorld\level.dat', 0
s_x:            db 'x'
align 8
evil_names:     dq ev0, ev1, ev2, ev3, ev4, ev5, ev6, ev7, ev8, ev9, ev10
evil_names_end:
ev0:            db '', 0
ev1:            db '.', 0
ev2:            db '..', 0
ev3:            db '..\Keeper', 0
ev4:            db 'Keeper/..', 0
ev5:            db 'C:', 0
ev6:            db 'a*', 0
ev7:            db '...', 0
ev8:            db 'Keeper.', 0
ev9:            db 'Keeper ', 0
ev10:           times 64 db 'x'
                db 0
name40:         times 40 db 'A'
                db 0
name63:         times 63 db 'W'
                db 0
name250:        times 250 db 'L'
                db 0

section .bss
alignb 16
listbuf:        resb 32*16
pathbuf:        resb 1024
cwdbuf:         resb 512
widebuf:        resw 1024

section .text

; edx = seconds to backdate level.dat by, -1 = leave it
PROC make_world, 0
    mov  rbx, rcx
    mov  esi, edx
    call pu_set_world_name
    call save_world
    CHECK_EQ32 eax, 1, "save_world"
    test esi, esi
    js   .done
    lea  rcx, [rel pathbuf]
    lea  rdx, [rel s_level_fmt]
    mov  r8, rbx
    call wsprintfA
    lea  rcx, [rel pathbuf]
    mov  edx, esi
    call pu_set_mtime_ago
.done:
ENDP

; names land in listbuf[i*32]
PROC list_worlds, 0
    mov  ebx, ecx
    lea  rcx, [rel listbuf]
    xor  edx, edx
    mov  r8d, 32*16
    call pu_memset
    lea  rcx, [rel listbuf]
    mov  edx, ebx
    call save_list_worlds
ENDP

PROC tick, 0
    mov  ebx, ecx
.l: test ebx, ebx
    jz   .done
    inc  qword [rel g_world_time]
    call save_autosave_tick
    dec  ebx
    jmp  .l
.done:
ENDP

%macro CHECK_ENTRY 2
    lea  rax, [rel listbuf + 32*%1]
    CHECK_STR rax, %2, "world list entry"
%endmacro

PROC test_main, 32
    CASE "worlds: list sorted newest first"
    %macro MAKE 2
        section .rdata
        %%n: db %1, 0
        section .text
        lea  rcx, [rel %%n]
        mov  edx, %2
        call make_world
    %endmacro
    MAKE "Alpha", 300
    MAKE "Bravo", 100
    MAKE "Charlie", 200
    MAKE "delta", 200                   ; same time as Charlie
    CALL_STR pu_mkdir_rel, "saves\NotAWorld"     ; no level.dat
    section .rdata
    s_stray: db 'saves\stray.txt', 0
    section .text
    lea  rcx, [rel s_stray]             ; plain file
    lea  rdx, [rel s_x]
    mov  r8d, 1
    call pu_write_file
    lea  rcx, [rel name40]              ; too long for 32-byte entries
    xor  edx, edx
    call make_world
    mov  ecx, 10
    call list_worlds
    CHECK_EQ32 eax, 4, "four listable worlds"
    CHECK_ENTRY 0, "Bravo"
    CHECK_ENTRY 1, "Charlie"
    CHECK_ENTRY 2, "delta"
    CHECK_ENTRY 3, "Alpha"
    mov  ecx, 2
    call list_worlds
    CHECK_EQ32 eax, 2, "max 2"
    CHECK_ENTRY 0, "Bravo"
    CHECK_ENTRY 1, "Charlie"
    xor  ecx, ecx
    call list_worlds
    CHECK_EQ32 eax, 0, "max 0"
    ENDCASE

    CASE "worlds: list without saves dir"
    mov  ecx, 8
    call list_worlds
    CHECK_EQ32 eax, 0, "no saves folder -> empty list"
    ENDCASE

    CASE "worlds: exists and delete"
    MAKE "Doomed", -1
    mov  ecx, 4
    mov  edx, -4
    call pu_new_chunk
    mov  rbx, rax
    mov  dword [rbx+CHUNK.modified], 1
    mov  byte [rbx+CHUNK_BLOCKS+5], 1
    mov  rcx, rbx
    call save_chunk
    CHECK_EQ32 eax, 1, "chunk saved into Doomed"
    MAKE "Keeper", -1
    CALL_STR save_world_exists, "Doomed"
    CHECK_EQ32 eax, 1, "Doomed exists"
    CALL_STR save_world_exists, "Nope"
    CHECK_EQ32 eax, 0, "Nope does not exist"
    CALL_STR save_world_exists, "Doomed\chunks"
    CHECK_EQ32 eax, 0, "a sub-path is not a world"
    CALL_STR pu_mkdir_rel, "saves\Keeper\sub"
    lea  r12, [rel evil_names]
.evil:
    mov  rcx, [r12]
    call save_delete_world
    CHECK_EQ32 eax, 0, "malformed / escaping name refused"
    add  r12, 8
    lea  rax, [rel evil_names_end]
    cmp  r12, rax
    jb   .evil
    CALL_STR save_delete_world, "Doomed"
    CHECK_EQ32 eax, 1, "Doomed deleted"
    CHECK_EXISTS "saves\Doomed", 0, "folder gone"
    CALL_STR save_world_exists, "Doomed"
    CHECK_EQ32 eax, 0, "Doomed no longer exists"
    CALL_STR save_world_exists, "Keeper"
    CHECK_EQ32 eax, 1, "Keeper kept"
    mov  ecx, 5
    call list_worlds
    CHECK_EQ32 eax, 1, "one world left"
    CHECK_ENTRY 0, "Keeper"
    CHECK_ISDIR "saves", 1, "'...' must not resolve to saves itself"
    ENDCASE

    ; 250 char file name in chunks: the path is > MAX_PATH so DeleteFileA may
    ; refuse it (world stays, delete returns 0). must not overflow either way.
    CASE "worlds: delete with long file names"
    lea  rcx, [rel name63]
    mov  edx, -1
    call make_world
    mov  ecx, 512
    lea  rdx, [rel cwdbuf]
    call GetCurrentDirectoryA
    lea  rcx, [rel pathbuf]
    lea  rdx, [rel s_long_fmt]
    lea  r8, [rel cwdbuf]
    lea  r9, [rel name63]
    lea  rax, [rel name250]
    mov  [rsp+32], rax
    call wsprintfA
    call widen_path
    lea  rcx, [rel widebuf]
    mov  edx, 0x40000000                ; GENERIC_WRITE
    xor  r8d, r8d
    xor  r9d, r9d
    mov  qword [rsp+32], 2              ; CREATE_ALWAYS
    mov  qword [rsp+40], 0x80
    mov  qword [rsp+48], 0
    call CreateFileW
    mov  rbx, rax
    cmp  rax, -1
    setne al
    movzx eax, al
    CHECK_TRUE eax, "long file created through \\?\"
    mov  rcx, rbx
    lea  rdx, [rel s_x]
    mov  r8d, 1
    lea  r9, LOC(0)
    mov  qword [rsp+32], 0
    call WriteFile
    mov  rcx, rbx
    call CloseHandle
    lea  rcx, [rel name63]
    call save_delete_world
    mov  r12d, eax
    lea  rcx, [rel pathbuf]
    lea  rdx, [rel s_world_fmt]
    lea  r8, [rel name63]
    call wsprintfA
    lea  rcx, [rel pathbuf]
    call pu_exists
    xor  eax, 1                         ; expected = 0 if the world stayed, else 1
    mov  r13d, eax
    CHECK_EQ32 r12d, r13d, "delete result matches what is left on disk"
    test r12d, r12d
    jnz  .gone
    lea  rcx, [rel widebuf]
    call DeleteFileW
.gone:
    lea  rcx, [rel name63]
    call save_delete_world
    CHECK_EQ32 eax, 1, "world deleted"
    lea  rcx, [rel pathbuf]
    call pu_exists
    CHECK_EQ32 eax, 0, "world folder gone"
    ENDCASE

    CASE "autosave: every 6000 ticks"
    mov  qword [rel g_world_time], 0
    mov  dword [rel g_world_active], 0
    mov  r12d, [rel mock_chat_calls]
    mov  ecx, 7000                      ; no world: nothing happens
    call tick
    CHECK_EQ32 [rel mock_chat_calls], r12d, "no world: no autosave"
    CHECK_EXISTS "saves", 0, "no world: nothing written"
    mov  dword [rel g_world_active], 1
    call save_world                     ; manual save restarts the countdown
    CHECK_EQ32 eax, 1, "manual save"
    mov  ecx, 5999
    call tick
    CHECK_EQ32 [rel mock_chat_calls], r12d, "5999 ticks after a save: nothing"
    lea  rcx, [rel s_tw_level]
    call DeleteFileA
    mov  ecx, 1
    call tick
    lea  r13d, [r12+1]
    CHECK_EQ32 [rel mock_chat_calls], r13d, "autosave after 6000 ticks"
    mov  rax, [rel mock_last_chat]
    CHECK_STR rax, "Game saved", "chat message"
    CHECK_EXISTS "saves\TestWorld\level.dat", 1, "level.dat rewritten"
    mov  ecx, 6000
    call tick
    lea  r13d, [r12+2]
    CHECK_EQ32 [rel mock_chat_calls], r13d, "next autosave 6000 ticks later"
    ; a brand-new world starts at time 0: the countdown restarts, no instant save
    mov  qword [rel g_world_time], 0
    mov  ecx, 5999
    call tick
    CHECK_EQ32 [rel mock_chat_calls], r13d, "time reset: countdown restarted"
    mov  ecx, 2
    call tick
    lea  r13d, [r12+3]
    CHECK_EQ32 [rel mock_chat_calls], r13d, "autosave after the restarted countdown"
    mov  dword [rel g_world_active], 0
    ENDCASE
ENDP

PROC pu_mkdir_rel, 0
    mov  rsi, rcx
    lea  rdi, [rel pathbuf]
    xor  ebx, ebx
.l: mov  al, [rsi+rbx]
    test al, al
    jz   .last
    cmp  al, '\'
    jne  .copy
    mov  byte [rdi+rbx], 0
    mov  rcx, rdi
    xor  edx, edx
    call CreateDirectoryA
    mov  al, '\'
.copy:
    mov  [rdi+rbx], al
    inc  ebx
    jmp  .l
.last:
    mov  byte [rdi+rbx], 0
    mov  rcx, rdi
    xor  edx, edx
    call CreateDirectoryA
ENDP

; ascii -> utf-16
PROC widen_path, 0
    lea  rsi, [rel pathbuf]
    lea  rdi, [rel widebuf]
    xor  ecx, ecx
.l: movzx eax, byte [rsi+rcx]
    mov  [rdi+rcx*2], ax
    inc  ecx
    test eax, eax
    jnz  .l
ENDP
