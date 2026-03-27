; level.dat: globals / player / block entities round trip, corrupt files,
; sanitising, bad world names, respawn, items stuck on screen.
; @link src/save.asm src/config.asm tests/persist/mock_platform.asm tests/persist/persist_util.asm
; @timeout 60
%include "common.inc"
%include "testlib.inc"
%include "../persist/persist.inc"

%define BE_BYTES        (MAX_BLOCKENTS*BLOCKENT_size)

section .rdata
s_level:        db 'saves\TestWorld\level.dat', 0
align 8
bad_names:      dq bn0, bn1, bn2, bn3, bn4, bn5
bad_names_end:
bn0:            db '...', 0
bn1:            db 'a.', 0
bn2:            db 'a ', 0
bn3:            db '..\escape', 0
bn4:            db 'x/y', 0
bn5:            db 'C:', 0
s_size1:        db 10, '  level.dat with 3 block entities: ', 0
s_size2:        db ' bytes', 10, 0
be_slots:       dd 0, 5, 1023

section .bss
alignb 16
exp_player:     resb PLAYER_size
exp_be:         resb BE_BYTES
blob:           resb 8192
good_ptr:       resq 1
good_len:       resq 1

section .text

; player is random but resumable: alive, valid hotbar slot, 1..20 hp, nothing
; on the cursor / crafting grid. copies in exp_player / exp_be
PROC fill_globals, 0
    call t_rng_seed
    mov  rax, 0x123456789ABCDEF0
    mov  [rel g_seed], rax
    mov  qword [rel g_world_time], 987654321
    mov  dword [rel g_time_of_day], 18123
    mov  dword [rel g_gamemode], 1
    mov  dword [rel g_weather], 2
    mov  dword [rel g_weather_timer], 4321
    lea  rbx, [rel exp_player]
    mov  rcx, rbx
    mov  edx, PLAYER_size
    call pu_fill_random
    mov  ecx, 9
    call pu_rand_below
    mov  [rbx+P_SELECTED], eax
    mov  ecx, 20
    call pu_rand_below
    inc  eax
    mov  [rbx+P_HEALTH], eax
    mov  dword [rbx+P_DEAD], 0
    lea  rcx, [rbx+P_CURSOR]
    xor  edx, edx
    mov  r8d, P_CRAFT_OUT + 4 - P_CURSOR
    call pu_memset
    lea  rcx, [rel g_player]
    mov  rdx, rbx
    mov  r8d, PLAYER_size
    call pu_memcpy
    lea  rdi, [rel exp_be]
    mov  rcx, rdi
    xor  edx, edx
    mov  r8d, BE_BYTES
    call pu_memset
    xor  esi, esi
.slot:
    lea  rax, [rel be_slots]
    mov  ecx, [rax+rsi*4]
    imul eax, ecx, BLOCKENT_size
    lea  rbx, [rdi+rax]
    mov  eax, ecx
    and  eax, 1
    inc  eax
    mov  [rbx], eax                     ; 1 + slot % 2
    mov  [rbx+4], ecx
    mov  dword [rbx+8], 64
    mov  eax, ecx
    neg  eax
    mov  [rbx+12], eax
    mov  dword [rbx+16], 100
    mov  dword [rbx+20], 1600
    mov  dword [rbx+24], 37
    xor  ecx, ecx                       ; 27 STACKs (s*7 % 200, 1 + s % 64, s)
.st:
    imul eax, ecx, 7
    xor  edx, edx
    mov  r8d, 200
    div  r8d
    mov  [rbx+32+rcx*4], dl
    mov  eax, ecx
    and  eax, 63
    inc  eax
    mov  [rbx+33+rcx*4], al
    mov  [rbx+34+rcx*4], cx
    inc  ecx
    cmp  ecx, 27
    jb   .st
    inc  esi
    cmp  esi, 3
    jb   .slot
    lea  rcx, [rel g_blockents]
    mov  rdx, rdi
    mov  r8d, BE_BYTES
    call pu_memcpy
ENDP

PROC clear_globals, 0
    xor  eax, eax
    mov  [rel g_seed], rax
    mov  [rel g_world_time], rax
    mov  [rel g_time_of_day], eax
    mov  [rel g_gamemode], eax
    mov  [rel g_weather], eax
    mov  [rel g_weather_timer], eax
    lea  rcx, [rel g_player]
    xor  edx, edx
    mov  r8d, PLAYER_size
    call pu_memset
    lea  rcx, [rel g_blockents]
    xor  edx, edx
    mov  r8d, BE_BYTES
    call pu_memset
ENDP

PROC write_blob, 0
    mov  r8, rcx
    lea  rcx, [rel s_level]
    lea  rdx, [rel blob]
    call pu_write_file
ENDP

PROC reset_blob, 0
    lea  rcx, [rel blob]
    xor  edx, edx
    mov  r8d, 8192
    call pu_memset
    lea  rcx, [rel blob]
    mov  rdx, [rel good_ptr]
    mov  r8, [rel good_len]
    call pu_memcpy
ENDP

PROC try_bad, 0
    call write_blob
    mov  qword [rel g_seed], 77
    call save_load_level
    CHECK_EQ32 eax, 0, "corrupt level.dat rejected"
    CHECK_EQ [rel g_seed], 77, "globals touched by a bad file"
ENDP

PROC test_main, 32
    CASE "level: roundtrip"
    mov  ecx, 99
    call fill_globals
    mov  r12d, [rel mock_saveall_calls]
    call save_world
    CHECK_EQ32 eax, 1, "save_world"
    inc  r12d
    CHECK_EQ32 [rel mock_saveall_calls], r12d, "chunkmgr_save_all called once"
    CHECK_ISDIR "saves\TestWorld\chunks", 1, "chunks folder created"
    lea  rcx, [rel s_level]
    call pu_file_size
    mov  rbx, rax
    lea  rcx, [rel s_size1]
    call t_print
    mov  rcx, rbx
    call t_print_int
    lea  rcx, [rel s_size2]
    call t_print
    cmp  rbx, 4000
    setl al
    movzx eax, al
    CHECK_TRUE eax, "level.dat < 4000 bytes"
    call clear_globals
    call save_load_level
    CHECK_EQ32 eax, 1, "save_load_level"
    mov  rbx, 0x123456789ABCDEF0
    CHECK_EQ [rel g_seed], rbx, "g_seed"
    CHECK_EQ [rel g_world_time], 987654321, "g_world_time"
    CHECK_EQ32 [rel g_time_of_day], 18123, "g_time_of_day"
    CHECK_EQ32 [rel g_gamemode], 1, "g_gamemode"
    CHECK_EQ32 [rel g_weather], 2, "g_weather"
    CHECK_EQ32 [rel g_weather_timer], 4321, "g_weather_timer"
    lea  rbx, [rel g_player]
    lea  rsi, [rel exp_player]
    CHECK_MEM rbx, rsi, PLAYER_size, "g_player restored verbatim"
    lea  rbx, [rel g_blockents]
    lea  rsi, [rel exp_be]
    CHECK_MEM rbx, rsi, BE_BYTES, "g_blockents restored verbatim"
    ENDCASE

    CASE "level: missing and corrupt"
    call save_load_level
    CHECK_EQ32 eax, 0, "no level.dat -> 0"
    mov  ecx, 5
    call fill_globals
    call save_world
    CHECK_EQ32 eax, 1, "save_world"
    lea  rcx, [rel s_level]
    call pu_read_file
    mov  [rel good_ptr], rax
    mov  [rel good_len], rdx
    mov  r12, rdx
    CHECK_EQ32 [rax], 'MASW', "magic"
    lea  rsi, [rel blob]
    call reset_blob
    mov  byte [rsi+3], 'X'
    mov  rcx, r12
    call try_bad
    call reset_blob
    mov  dword [rsi+4], 3
    mov  rcx, r12
    call try_bad
    call reset_blob
    mov  dword [rsi+4], 1               ; v1 with a v2 header
    mov  rcx, r12
    call try_bad
    call reset_blob
    lea  rcx, [r12-1]
    call try_bad
    lea  rcx, [r12+1]                   ; one trailing zero byte
    call try_bad
    xor  byte [rsi+100], 0xFF           ; player byte -> crc mismatch
    mov  rcx, r12
    call try_bad
    call reset_blob
    mov  ecx, 40
    call try_bad
    mov  rcx, r12
    call write_blob
    call save_load_level
    CHECK_EQ32 eax, 1, "the good file still loads"
    ENDCASE

    CASE "level: sanitises values"
    mov  ecx, 1
    call fill_globals
    mov  dword [rel g_time_of_day], 24000*3 + 5
    mov  dword [rel g_gamemode], 7
    mov  dword [rel g_weather], 9
    call save_world
    CHECK_EQ32 eax, 1, "save_world"
    call save_load_level
    CHECK_EQ32 eax, 1, "save_load_level"
    CHECK_EQ32 [rel g_time_of_day], 5, "time of day wrapped"
    CHECK_EQ32 [rel g_gamemode], 0, "bad gamemode -> survival"
    CHECK_EQ32 [rel g_weather], 0, "bad weather -> clear"
    ENDCASE

    CASE "level: no world name"
    SET_NAME ""
    call save_world
    CHECK_EQ32 eax, 0, "save_world without a name"
    CHECK_EXISTS "saves", 0, "nothing created"
    ENDCASE

    CASE "level: invalid world names touch nothing"
    mov  ecx, 2
    call fill_globals
    xor  ecx, ecx
    xor  edx, edx
    call pu_new_chunk
    mov  rbx, rax
    mov  byte [rbx+CHUNK_BLOCKS], 1
    lea  r12, [rel bad_names]
.bad:
    mov  rcx, [r12]
    call pu_set_world_name
    call save_world
    CHECK_EQ32 eax, 0, "save_world with an invalid name"
    call save_load_level
    CHECK_EQ32 eax, 0, "save_load_level with an invalid name"
    mov  dword [rbx+CHUNK.modified], 1
    mov  rcx, rbx
    call save_chunk
    CHECK_EQ32 eax, 0, "save_chunk with an invalid name"
    CHECK_EQ32 [rbx+CHUNK.modified], 1, "modified flag kept"
    mov  rcx, rbx
    call save_load_chunk
    CHECK_EQ32 eax, 0, "save_load_chunk with an invalid name"
    add  r12, 8
    lea  rax, [rel bad_names_end]
    cmp  r12, rax
    jb   .bad
    CHECK_EXISTS "saves", 0, "no saves folder"
    CHECK_EXISTS "escape", 0, "no escape folder"
    ENDCASE

    CASE "level: player saved dead respawns"
    mov  ecx, 3
    call fill_globals
    lea  rbx, [rel g_player]
    mov  dword [rbx+P_DEAD], 1
    mov  dword [rbx+P_HEALTH], 0
    call save_world
    CHECK_EQ32 eax, 1, "save_world"
    mov  r12d, [rel mock_respawn_calls]
    call save_load_level
    CHECK_EQ32 eax, 1, "save_load_level"
    lea  r13d, [r12+1]
    CHECK_EQ32 [rel mock_respawn_calls], r13d, "player_respawn called"
    CHECK_EQ32 [rbx+P_HEALTH], 20, "health after respawn"
    CHECK_EQ32 [rbx+P_DEAD], 0, "alive after respawn"
    ; alive flag but 0 health also respawns; 25 hp is clamped, no respawn
    mov  dword [rbx+P_HEALTH], 0
    call save_world
    CHECK_EQ32 eax, 1, "save_world"
    call save_load_level
    CHECK_EQ32 eax, 1, "save_load_level"
    lea  r13d, [r12+2]
    CHECK_EQ32 [rel mock_respawn_calls], r13d, "0 hp respawns"
    mov  dword [rbx+P_HEALTH], 25
    call save_world
    CHECK_EQ32 eax, 1, "save_world"
    call save_load_level
    CHECK_EQ32 eax, 1, "save_load_level"
    CHECK_EQ32 [rel mock_respawn_calls], r13d, "25 hp: no respawn"
    CHECK_EQ32 [rbx+P_HEALTH], 20, "25 hp clamped to 20"
    ENDCASE

    CASE "level: screen items return to inventory"
    mov  ecx, 4
    call fill_globals
    lea  rbx, [rel g_player]
    xor  ecx, ecx                       ; full except slots 3 and 20
.inv:
    xor  eax, eax
    cmp  ecx, 3
    je   .put
    cmp  ecx, 20
    je   .put
    lea  eax, [rcx+1]
    or   eax, 5 << 8                    ; (1 + i, 5, 0)
.put:
    mov  [rbx+P_INV+rcx*4], eax
    inc  ecx
    cmp  ecx, 36
    jb   .inv
    mov  dword [rbx+P_CURSOR], STACK4(200, 1, 77)  ; damaged tool
    mov  dword [rbx+P_CRAFT], STACK4(17, 3, 0)
    mov  dword [rbx+P_CRAFT+8*4], STACK4(4, 9, 0)  ; no room left for this one
    mov  dword [rbx+P_CRAFT_OUT], STACK4(58, 1, 0)  ; stale preview
    mov  dword [rbx+P_SELECTED], 42  ; out of range
    call save_world
    CHECK_EQ32 eax, 1, "save_world"
    call save_load_level
    CHECK_EQ32 eax, 1, "save_load_level"
    CHECK_EQ32 [rbx+P_INV+3*4], STACK4(200, 1, 77), "cursor item -> first free slot (3)"
    CHECK_EQ32 [rbx+P_INV+20*4], STACK4(17, 3, 0), "crafting item -> next free slot (20)"
    CHECK_EQ32 [rbx+P_CURSOR], 0, "cursor emptied"
    CHECK_EQ32 [rbx+P_CRAFT], 0, "grid slot 0 emptied"
    CHECK_EQ32 [rbx+P_CRAFT+8*4], STACK4(4, 9, 0), "kept: inventory full"
    CHECK_EQ32 [rbx+P_CRAFT_OUT], 0, "stale preview cleared"
    CHECK_EQ32 [rbx+P_SELECTED], 0, "hotbar slot reset"
    ENDCASE
ENDP
