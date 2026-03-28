; save_world_info (level.dat header for the world list) and the info records
; save_list_worlds hands back in rdx.
; @link src/save.asm src/config.asm tests/persist/mock_platform.asm tests/persist/persist_util.asm
; @timeout 60
%include "common.inc"
%include "testlib.inc"
%include "../persist/persist.inc"

extern save_world_info

%define WI_SEED         0               ; save.asm
%define WI_FTIME        8
%define WI_WTIME        16
%define WI_MODE         24
%define WI_OK           28
%define WI_NAME         32
%define WI_SIZE         64

; STRP reg, "text" -> reg = ptr to the literal
%macro STRP 2
    section .rdata
    %%s: db %2, 0
    section .text
    lea  %1, [rel %%s]
%endmacro

section .rdata
s_info_one:     db 'saves\InfoOne\level.dat', 0
s_trunc:        db 'saves\Trunc\level.dat', 0
s_magic:        db 'saves\Magic\level.dat', 0
s_old:          db 'saves\Old\level.dat', 0
s_old_dir:      db 'saves\Old', 0
s_a_level:      db 'saves\WorldA\level.dat', 0
s_b_level:      db 'saves\WorldB\level.dat', 0
align 8
; a v1 header and nothing else: no player, no block entities
v1_hdr:         dd 'MASW', 1, 64, 0
                dq 99                   ; seed
                dq 48000                ; world time, day 3
                dd 0, GM_SURVIVAL, 0, 0, 0, 0, 0, 0
v1_hdr_len      equ $ - v1_hdr

section .bss
alignb 16
info:           resb WI_SIZE
listbuf:        resb 32*8

section .text

; (rcx folder) -> eax, info filled. info gets junk first so "always filled" shows
PROC get_info, 0
    mov  rbx, rcx
    lea  rcx, [rel info]
    mov  edx, 0xAB
    mov  r8d, WI_SIZE
    call pu_memset
    mov  rcx, rbx
    lea  rdx, [rel info]
    call save_world_info
ENDP

%macro INFO 1
    section .rdata
    %%n: db %1, 0
    section .text
    lea  rcx, [rel %%n]
    call get_info
    mov  r12d, eax
%endmacro

PROC test_main, 32
    CASE "info: v2 world with a typed name"
    mov  qword [rel g_seed], -42
    mov  qword [rel g_world_time], 50000
    mov  dword [rel g_gamemode], GM_CREATIVE
    STRP rcx, "InfoOne"
    STRP rdx, "  Info One  "
    call save_set_display_name
    CALL_STR pu_set_world_name, "InfoOne"
    call save_world
    CHECK_EQ32 eax, 1, "save_world"
    INFO "InfoOne"
    CHECK_EQ32 r12d, 1, "header ok"
    CHECK_EQ32 [rel info+WI_OK], 1, "WI_OK"
    CHECK_EQ [rel info+WI_SEED], -42, "seed"
    CHECK_EQ [rel info+WI_WTIME], 50000, "world time"
    CHECK_EQ32 [rel info+WI_MODE], GM_CREATIVE, "mode"
    lea  rbx, [rel info+WI_NAME]
    CHECK_STR rbx, "Info One", "typed name, trimmed"
    lea  rcx, [rel s_info_one]
    call pu_file_mtime
    mov  rbx, rax
    CHECK_EQ [rel info+WI_FTIME], rbx, "file time = level.dat write time"
    CHECK_TRUE ebx, "file time is set"
    ENDCASE

    CASE "info: no typed name -> folder"
    mov  qword [rel g_seed], 7
    mov  dword [rel g_gamemode], GM_SURVIVAL
    CALL_STR pu_set_world_name, "Plain"
    call save_world
    INFO "Plain"
    CHECK_EQ32 r12d, 1, "header ok"
    CHECK_EQ32 [rel info+WI_MODE], GM_SURVIVAL, "mode"
    CHECK_EQ [rel info+WI_SEED], 7, "seed"
    lea  rbx, [rel info+WI_NAME]
    CHECK_STR rbx, "Plain", "folder name"
    ENDCASE

    CASE "info: truncated level.dat"
    mov  qword [rel g_seed], 5
    CALL_STR pu_set_world_name, "Trunc"
    call save_world
    lea  rcx, [rel s_trunc]
    call pu_read_file
    mov  rsi, rax
    lea  r8, [rdx-1]
    lea  rcx, [rel s_trunc]
    mov  rdx, rsi
    call pu_write_file
    INFO "Trunc"
    CHECK_EQ32 r12d, 0, "rejected"
    CHECK_EQ32 [rel info+WI_OK], 0, "WI_OK 0"
    CHECK_EQ [rel info+WI_SEED], 0, "seed not trusted"
    lea  rbx, [rel info+WI_NAME]
    CHECK_STR rbx, "Trunc", "folder name"
    mov  rbx, [rel info+WI_FTIME]
    CHECK_TRUE ebx, "file time still there"
    ENDCASE

    CASE "info: bad magic"
    CALL_STR pu_set_world_name, "Magic"
    call save_world
    lea  rcx, [rel s_magic]
    call pu_read_file
    mov  rsi, rax
    mov  rdi, rdx
    mov  byte [rsi], 'X'
    lea  rcx, [rel s_magic]
    mov  rdx, rsi
    mov  r8, rdi
    call pu_write_file
    INFO "Magic"
    CHECK_EQ32 r12d, 0, "rejected"
    ENDCASE

    CASE "info: v1 header"
    STRP rcx, "saves"
    xor  edx, edx
    call CreateDirectoryA
    lea  rcx, [rel s_old_dir]
    xor  edx, edx
    call CreateDirectoryA
    lea  rcx, [rel s_old]
    lea  rdx, [rel v1_hdr]
    mov  r8d, v1_hdr_len
    call pu_write_file
    INFO "Old"
    CHECK_EQ32 r12d, 1, "v1 accepted"
    CHECK_EQ [rel info+WI_SEED], 99, "seed"
    CHECK_EQ [rel info+WI_WTIME], 48000, "world time"
    lea  rbx, [rel info+WI_NAME]
    CHECK_STR rbx, "Old", "v1 has no typed name"
    ENDCASE

    CASE "info: missing and bad names"
    INFO "Nope"
    CHECK_EQ32 r12d, 0, "no level.dat"
    CHECK_EQ [rel info+WI_FTIME], 0, "no file time"
    lea  rbx, [rel info+WI_NAME]
    CHECK_STR rbx, "Nope", "name still filled"
    INFO ".."
    CHECK_EQ32 r12d, 0, "'..' refused"
    STRP rcx, "x"
    xor  edx, edx
    call save_world_info
    CHECK_EQ32 eax, 0, "null out"
    xor  ecx, ecx
    lea  rdx, [rel info]
    call save_world_info
    CHECK_EQ32 eax, 0, "null name"
    ENDCASE

    CASE "info: save_list_worlds hands it back"
    mov  qword [rel g_seed], 111
    mov  dword [rel g_gamemode], GM_SURVIVAL
    CALL_STR pu_set_world_name, "WorldA"
    call save_world
    lea  rcx, [rel s_a_level]
    mov  edx, 500
    call pu_set_mtime_ago
    mov  qword [rel g_seed], 222
    mov  dword [rel g_gamemode], GM_CREATIVE
    CALL_STR pu_set_world_name, "WorldB"
    call save_world
    lea  rcx, [rel s_b_level]
    mov  edx, 100
    call pu_set_mtime_ago
    lea  rcx, [rel listbuf]
    mov  edx, 8
    call save_list_worlds
    mov  ebx, eax
    mov  rsi, rdx
    CHECK_EQ32 ebx, 2, "two worlds"
    lea  rbx, [rel listbuf]
    CHECK_STR rbx, "WorldB", "newest first"
    CHECK_EQ [rsi+WI_SEED], 222, "info 0 is WorldB"
    CHECK_EQ32 [rsi+WI_MODE], GM_CREATIVE, "info 0 mode"
    CHECK_EQ32 [rsi+WI_OK], 1, "info 0 ok"
    lea  rbx, [rsi+WI_NAME]
    CHECK_STR rbx, "WorldB", "info 0 name"
    CHECK_EQ [rsi+WI_SIZE+WI_SEED], 111, "info 1 is WorldA"
    mov  rax, [rsi+WI_FTIME]
    mov  rbx, [rsi+WI_SIZE+WI_FTIME]
    xor  edi, edi
    cmp  rax, rbx
    seta dil
    CHECK_TRUE edi, "info 0 played later than info 1"
    lea  rcx, [rel listbuf]
    mov  edx, 1
    call save_list_worlds
    mov  ebx, eax
    mov  rsi, rdx
    CHECK_EQ32 ebx, 1, "max 1"
    CHECK_EQ [rsi+WI_SEED], 222, "max 1 keeps the newest"
    ENDCASE
ENDP
