; persist test glue. include after common.inc + testlib.inc as
; "../persist/persist.inc" (found through the tests/lib -I path)
%ifndef PERSIST_INC
%define PERSIST_INC

extern pu_case_begin, pu_case_end, pu_set_world_name, pu_clear_entities
extern pu_entity_ptr, pu_put_entity, pu_memset, pu_memcpy, pu_strcpy, pu_strlen
extern pu_contains, pu_read_file, pu_write_file, pu_write_str, pu_exists
extern pu_is_dir, pu_file_size, pu_file_mtime, pu_set_mtime_ago, pu_rle_ref
extern pu_fnv32, pu_rand_below, pu_rand_double, pu_fill_random
extern pu_typical_chunk, pu_flat_chunk, pu_new_chunk, pu_make_entity, pu_rmtree
extern mock_light_calls, mock_saveall_calls, mock_chat_calls, mock_last_chat
extern mock_alloc_count, mock_respawn_calls
extern wsprintfA, CreateDirectoryA, DeleteFileA
; save.asm exports api.inc doesn't declare
extern save_rle_encode, save_rle_decode, save_rle_decoded_size, save_fnv32
extern save_set_display_name, save_world_display_name, save_list_worlds_ex

%define P_HEALTH        PLAYER.health
%define P_SELECTED      PLAYER.selected
%define P_DEAD          PLAYER.dead
%define P_INV           PLAYER.inv
%define P_CURSOR        PLAYER.cursor
%define P_CRAFT         PLAYER.craft
%define P_CRAFT_OUT     PLAYER.craft_out

; one sandboxed case: fresh temp dir as cwd, world "TestWorld", no entities,
; leak check at ENDCASE
%macro CASE 1
    section .rdata
    %%n: db %1, 0
    section .text
    lea  rcx, [rel %%n]
    call pu_case_begin
%endmacro
%macro ENDCASE 0
    call pu_case_end
%endmacro

%macro STR 2
    section .rdata
    %1: db %2, 0
    section .text
%endmacro

%macro CALL_STR 2
    section .rdata
    %%s: db %2, 0
    section .text
    lea  rcx, [rel %%s]
    call %1
%endmacro

%macro CHECK_EXISTS 3
    section .rdata
    %%p: db %1, 0
    section .text
    lea  rcx, [rel %%p]
    call pu_exists
    CHECK_EQ32 eax, %2, %3
%endmacro

%macro CHECK_ISDIR 3
    section .rdata
    %%p: db %1, 0
    section .text
    lea  rcx, [rel %%p]
    call pu_is_dir
    CHECK_EQ32 eax, %2, %3
%endmacro

%macro SET_NAME 1
    CALL_STR pu_set_world_name, %1
%endmacro

%define STACK4(id, cnt, dmg) ((id) | ((cnt) << 8) | ((dmg) << 16))

; 32 byte pu_make_entity descriptor. arg order != layout:
; slot, type, flags, variant, health, x, y, z, item_id, item_cnt, item_dmg
%macro ENTDESC 11
    db %2, %3, %4, %9, %10, 0
    dw %11
    dd %5
    dd __?float32?__(%6), __?float32?__(%7), __?float32?__(%8)
    dd %1
    dd 0
%endmacro
%define ENTDESC_SIZE 32

%endif
