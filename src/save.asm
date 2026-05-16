; MASW v2 level.dat + MASC v1 RLE chunk streams
%define IMPL_SAVE
%include "common.inc"

extern RemoveDirectoryA
extern GetFileAttributesExA

%define LEVEL_MAGIC     'MASW'
%define CHUNK_MAGIC     'MASC'
%define SAVE_VERSION    2
%define CHUNK_VERSION   1  ; chunk files are unchanged

%define LVL_HDR         128
%define LVL_HDR_V1      64
%define LVL_CRC_START   64  ; checksum covers [64, EOF)
%define LVL_MAGIC_OFF   0
%define LVL_VER_OFF     4
%define LVL_HSIZE_OFF   8
%define LVL_PSIZE_OFF   12
%define LVL_SEED_OFF    16
%define LVL_WTIME_OFF   24
%define LVL_TOD_OFF     32
%define LVL_GM_OFF      36
%define LVL_WEATHER_OFF 40
%define LVL_WTIMER_OFF  44
%define LVL_BERAW_OFF   48
%define LVL_BEENC_OFF   52
%define LVL_CRC_OFF     56
%define LVL_NENT_OFF    60  ; entity count (always 0 in v1)
%define LVL_NAME_OFF    64  ; v2 only from here on
%define LVL_NAME_LEN    32
%define LVL_ESIZE_OFF   96

%define BE_BYTES        (MAX_BLOCKENTS*BLOCKENT_size)
%define ENT_BYTES       (MAX_ENTITIES*ENTITY_size)
%define LVL_MAX_PLAYER  4096  ; sanity bounds on load
%define LVL_MAX_BERAW   (16*1024*1024)

%define CHK_HDR         32
%define CHK_MAGIC_OFF   0
%define CHK_VER_OFF     4
%define CHK_CX_OFF      8
%define CHK_CZ_OFF      12
%define CHK_RAW_OFF     16
%define CHK_ENC_OFF     20
%define CHK_CRC_OFF     24

%define AUTOSAVE_TICKS  6000  ; 5 minutes at 20 Hz
%define PATH_MAX_BUF    320

; world list temp records: char name[32] + u64 filetime of level.dat
%define LIST_CAP        256
%define LIST_REC        40
%define LIST_NAME_MAX   31

; what the world list shows per world, from the level.dat header.
; menus.asm has the same defines
%define WI_SEED         0   ; qword
%define WI_FTIME        8   ; qword FILETIME (utc) of level.dat, 0 = unknown
%define WI_WTIME        16  ; qword world ticks
%define WI_MODE         24  ; dword GM_*
%define WI_OK           28  ; dword 1 = header looked sane, the rest is only valid then
%define WI_NAME         32  ; char[32] typed name (v2), else the folder name
%define WI_SIZE         64

; WIN32_FIND_DATAA / WIN32_FILE_ATTRIBUTE_DATA
%define FD_ATTR         0
%define FD_NAME         44
%define FD_SIZE         336  ; really 320
%define FAD_ATTR        0
%define FAD_WRITETIME   20
%define FAD_SIZE_HI     28
%define FAD_SIZE_LO     32

%define COL_SAVED       0xFFA0A0A0
%define COL_SAVE_FAIL   0xFFFF5555

; PROC without the export
%macro SPROC 1-2 0
    align 16
%1:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub  rsp, (((%2)+15) & ~15) + FRAME_OUT + 8
%endmacro

section .rdata
s_saves:        db 'saves', 0
s_saves_slash:  db 'saves\', 0
s_saves_glob:   db 'saves\*', 0
s_level:        db '\level.dat', 0
s_chunks:       db '\chunks', 0
s_chunk_pre:    db '\chunks\c.', 0
s_bin:          db '.bin', 0
s_glob:         db '\*', 0
s_game_saved:   db 'Game saved', 0
s_save_failed:  db 'Autosave failed! Check disk space / permissions.', 0
fmt_saved:      db 'save: world "%s" saved (level.dat %d bytes, %d entities)', 0
fmt_save_fail:  db 'save: FAILED to write level.dat of world "%s"', 0
fmt_loaded:     db 'save: loaded level.dat of world "%s" (version %d, %d entities restored)', 0
fmt_ent_size:   db 'save: level.dat entity records are %d bytes, expected %d - entities skipped', 0
fmt_bad_level:  db 'save: level.dat of world "%s" is corrupt or incompatible - ignored', 0
fmt_bad_chunk:  db 'save: corrupt chunk file %s - regenerating from seed', 0
fmt_deleted:    db 'save: deleted world "%s"', 0

section .bss
alignb 8
s_last_save_time:   resq 1  ; g_world_time of last save / load
s_last_level_size:  resd 1  ; for the log
s_last_ent_count:   resd 1
; display name is keyed by folder, so it doesn't matter which of
; save_set_display_name / game_start_world runs first, and it can't leak
; into another world's save
s_display_owner:    resb 64
s_display_name:     resb LVL_NAME_LEN
alignb 16
s_list_info:        resb LIST_CAP*WI_SIZE  ; save_list_worlds hands this back in rdx

section .text

; path helpers build into caller stack buffers, nothing shared, which is what
; makes save_load_chunk ok on several worker threads. custom regs, leaves

; rsi -> rdi, rdi ends on the NUL so calls chain. trashes al
sv_append:
    mov  al, [rsi]
    mov  [rdi], al
    test al, al
    jz   .end
    inc  rsi
    inc  rdi
    jmp  sv_append
.end:
    ret

; same but max ecx chars, always terminates
sv_append_n:
    test ecx, ecx
    jz   .end
    mov  al, [rsi]
    test al, al
    jz   .end
    mov  [rdi], al
    inc  rsi
    inc  rdi
    dec  ecx
    jmp  sv_append_n
.end:
    mov  byte [rdi], 0
    ret

; signed eax at rdi. INT_MIN is fine, neg leaves 0x80000000 and the unsigned
; div reads that as 2147483648
sv_append_int:
    test eax, eax
    jns  .pos
    mov  byte [rdi], '-'
    inc  rdi
    neg  eax
.pos:
    xor  ecx, ecx
    mov  r8d, 10
.div:
    xor  edx, edx
    div  r8d
    add  edx, '0'
    push rdx
    inc  ecx
    test eax, eax
    jnz  .div
.out:
    pop  rax
    mov  [rdi], al
    inc  rdi
    dec  ecx
    jnz  .out
    mov  byte [rdi], 0
    ret

; rdi -> saves\<g_world_name>
sv_world_dir:
    lea  rsi, [rel s_saves_slash]
    call sv_append
    lea  rsi, [rel g_world_name]
    mov  ecx, 63
    jmp  sv_append_n

; ecx cx, edx cz -> saves\<world>\chunks\c.<cx>.<cz>.bin
sv_chunk_path:
    mov  r10d, ecx
    mov  r11d, edx
    call sv_world_dir
    lea  rsi, [rel s_chunk_pre]
    call sv_append
    mov  eax, r10d
    call sv_append_int
    mov  byte [rdi], '.'
    inc  rdi
    mov  eax, r11d
    call sv_append_int
    lea  rsi, [rel s_bin]
    jmp  sv_append

; ok as a single folder name under saves\? trailing '.' / ' ' are out too:
; win32 strips them from every path component, so "..." would turn into
; saves\ itself (save_delete_world!) and "a." would alias "a". leaf, thread-safe
sv_valid_name:
    xor  eax, eax
    test rcx, rcx
    jz   .ret
    movzx edx, byte [rcx]
    test edx, edx
    jz   .ret
    cmp  dl, '.'
    jne  .scan0
    movzx edx, byte [rcx+1]
    test edx, edx
    jz   .ret  ; "."
    cmp  dl, '.'
    jne  .scan0
    cmp  byte [rcx+2], 0
    je   .ret  ; ".."
.scan0:
    xor  r8d, r8d
.scan:
    movzx edx, byte [rcx+r8]
    test edx, edx
    jz   .ok
    cmp  edx, 32
    jb   .ret
    cmp  dl, '\'
    je   .ret
    cmp  dl, '/'
    je   .ret
    cmp  dl, ':'
    je   .ret
    cmp  dl, '*'
    je   .ret
    cmp  dl, '?'
    je   .ret
    cmp  dl, '"'
    je   .ret
    cmp  dl, '<'
    je   .ret
    cmp  dl, '>'
    je   .ret
    cmp  dl, '|'
    je   .ret
    inc  r8d
    cmp  r8d, 63
    ja   .ret
    jmp  .scan
.ok:
    movzx edx, byte [rcx+r8-1]
    cmp  dl, '.'
    je   .ret
    cmp  dl, ' '
    je   .ret
    mov  eax, 1
.ret:
    ret

; ascii case-insensitive compare, rcx/rdx zstr. trashes r8 r9 rcx rdx
sv_stricmp:
    movzx eax, byte [rcx]
    movzx r8d, byte [rdx]
    lea  r9d, [rax-'A']
    cmp  r9d, 25
    ja   .a_done
    add  eax, 32
.a_done:
    lea  r9d, [r8-'A']
    cmp  r9d, 25
    ja   .b_done
    add  r8d, 32
.b_done:
    sub  eax, r8d
    jnz  .ret
    test r8d, r8d
    jz   .ret
    inc  rcx
    inc  rdx
    jmp  sv_stricmp
.ret:
    ret

; trims spaces, control chars -> '?', max 31 chars, rest of dst zeroed so
; level.dat stays deterministic. -> eax length
sv_copy_display:
    mov  rdx, rdi
    xor  eax, eax
    mov  ecx, LVL_NAME_LEN
    rep  stosb
    test rsi, rsi
    jz   .ret
.skip:
    cmp  byte [rsi], ' '
    jne  .copy
    inc  rsi
    jmp  .skip
.copy:
    cmp  eax, LVL_NAME_LEN-1
    jae  .trim
    movzx ecx, byte [rsi]
    test ecx, ecx
    jz   .trim
    inc  rsi
    cmp  ecx, 32
    jae  .store
    mov  ecx, '?'
.store:
    mov  [rdx+rax], cl
    inc  eax
    jmp  .copy
.trim:
    test eax, eax
    jz   .ret
    cmp  byte [rdx+rax-1], ' '
    jne  .ret
    dec  eax
    mov  byte [rdx+rax], 0
    jmp  .trim
.ret:
    ret

; insertion sort, most recently played first, ties alphabetical.
; n <= LIST_CAP so n^2 doesn't matter
sv_sort_records:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    sub  rsp, 56  ; [rsp] = record being inserted
    mov  r12, rcx
    mov  r13d, edx
    mov  r14d, 1
.outer:
    cmp  r14d, r13d
    jae  .end
    imul eax, r14d, LIST_REC
    lea  rsi, [r12+rax]
    mov  rdi, rsp
    mov  ecx, LIST_REC
    rep  movsb
    mov  ebx, r14d
.inner:
    test ebx, ebx
    jz   .place
    lea  eax, [rbx-1]
    imul eax, eax, LIST_REC
    lea  rdx, [r12+rax]
    mov  rax, [rsp+32]
    cmp  rax, [rdx+32]
    ja   .shift  ; tmp is newer, goes first
    jb   .place
    mov  rcx, rsp
    call sv_stricmp
    test eax, eax
    jns  .place
.shift:
    lea  eax, [rbx-1]
    imul eax, eax, LIST_REC
    lea  rsi, [r12+rax]
    lea  rdi, [rsi+LIST_REC]
    mov  ecx, LIST_REC
    rep  movsb
    dec  ebx
    jmp  .inner
.place:
    imul eax, ebx, LIST_REC
    lea  rdi, [r12+rax]
    mov  rsi, rsp
    mov  ecx, LIST_REC
    rep  movsb
    inc  r14d
    jmp  .outer
.end:
    add  rsp, 56
    pop  r14
    pop  r13
    pop  r12
    pop  rdi
    pop  rsi
    pop  rbx
    ret

; rle + fnv are exported with the save_ prefix only so the unit tests can hit them

; dst needs 2*n worst case. (count 1..255, byte) pairs. chunk blocks are in
; x + z*16 + y*256 order, so each layer is mostly one long run (~2 KB per
; natural chunk, flat ones a few hundred bytes)
LEAF save_rle_encode
    push rsi
    push rdi
    mov  rsi, rcx
    lea  r9, [rcx+rdx]
    mov  rdi, r8
.next_run:
    cmp  rsi, r9
    jae  .done
    movzx eax, byte [rsi]
    lea  r10, [rsi+1]
    lea  r11, [rsi+255]  ; min(start+255, end)
    cmp  r11, r9
    cmova r11, r9
.scan:
    cmp  r10, r11
    jae  .emit
    cmp  [r10], al
    jne  .emit
    inc  r10
    jmp  .scan
.emit:
    mov  rcx, r10
    sub  rcx, rsi
    mov  [rdi], cl
    mov  [rdi+1], al
    add  rdi, 2
    mov  rsi, r10
    jmp  .next_run
.done:
    mov  rax, rdi
    sub  rax, r8
    pop  rdi
    pop  rsi
    ret

; -> decoded size or -1. dry run so a bad file can't half-overwrite live data
LEAF save_rle_decoded_size
    xor  eax, eax
    test dl, 1
    jnz  .bad
    lea  r8, [rcx+rdx]
.loop:
    cmp  rcx, r8
    jae  .ret
    movzx r9d, byte [rcx]
    test r9d, r9d
    jz   .bad
    add  rax, r9
    add  rcx, 2
    jmp  .loop
.bad:
    mov  rax, -1
.ret:
    ret

; -> bytes written, or -1 if malformed / would overflow dstcap (dst may be
; partly written then)
LEAF save_rle_decode
    push rsi
    push rdi
    test dl, 1
    jnz  .bad
    mov  rsi, rcx
    lea  r10, [rcx+rdx]
    mov  rdi, r8
    lea  r11, [r8+r9]
.loop:
    cmp  rsi, r10
    jae  .ok
    movzx ecx, byte [rsi]
    movzx eax, byte [rsi+1]
    add  rsi, 2
    test ecx, ecx
    jz   .bad
    mov  rdx, r11
    sub  rdx, rdi
    cmp  rcx, rdx
    ja   .bad
    rep  stosb  ; the whole decoder, really
    jmp  .loop
.ok:
    mov  rax, rdi
    sub  rax, r8
    jmp  .out
.bad:
    mov  rax, -1
.out:
    pop  rdi
    pop  rsi
    ret

LEAF save_fnv32
    mov  eax, 0x811C9DC5  ; offset basis
    lea  r8, [rcx+rdx]
.loop:
    cmp  rcx, r8
    jae  .ret
    movzx r9d, byte [rcx]
    xor  eax, r9d
    imul eax, eax, 0x01000193
    inc  rcx
    jmp  .loop
.ret:
    ret

SPROC sv_ensure_dirs, PATH_MAX_BUF
    lea  rcx, [rel s_saves]
    call dir_create
    lea  rdi, LOC(0)
    call sv_world_dir
    lea  rcx, LOC(0)
    call dir_create  ; rdi is non-volatile, still at end of path
    mov  r12d, eax
    lea  rsi, [rel s_chunks]
    call sv_append
    lea  rcx, LOC(0)
    call dir_create
    and  eax, r12d
ENDP

; deletes the plain files directly in rcx dir. DF_FILE is sized for a
; MAX_PATH name found on disk, not PATH_MAX_BUF
%define DF_FILE_CAP (PATH_MAX_BUF+272)
%define DF_PAT   0
%define DF_FD    PATH_MAX_BUF
%define DF_FILE  (PATH_MAX_BUF+FD_SIZE)
SPROC sv_delete_files_in, (PATH_MAX_BUF+FD_SIZE+DF_FILE_CAP)
    mov  rbx, rcx
    xor  r13d, r13d
    lea  rdi, LOC(DF_PAT)
    mov  rsi, rbx
    call sv_append
    lea  rsi, [rel s_glob]
    call sv_append
    lea  rcx, LOC(DF_PAT)
    lea  rdx, LOC(DF_FD)
    call FindFirstFileA
    cmp  rax, INVALID_HANDLE_VALUE
    je   .done
    mov  r12, rax
.entry:
    test dword LOC(DF_FD+FD_ATTR), FILE_ATTRIBUTE_DIRECTORY
    jnz  .next
    lea  rdi, LOC(DF_FILE)
    mov  rsi, rbx
    call sv_append
    mov  byte [rdi], '\'
    inc  rdi
    lea  rsi, LOC(DF_FD+FD_NAME)
    call sv_append
    lea  rcx, LOC(DF_FILE)
    call DeleteFileA
    test eax, eax
    jz   .next
    inc  r13d
.next:
    mov  rcx, r12
    lea  rdx, LOC(DF_FD)
    call FindNextFileA
    test eax, eax
    jnz  .entry
    mov  rcx, r12
    call FindClose
.done:
    mov  eax, r13d
ENDP

%define LVL_BUF_CAP (LVL_HDR + PLAYER_size + 2*BE_BYTES + ENT_BYTES)
SPROC sv_write_level, PATH_MAX_BUF
    mov  ecx, LVL_BUF_CAP
    call mem_alloc  ; zeroed
    test rax, rax
    jz   .fail
    mov  r12, rax

    mov  dword [r12+LVL_MAGIC_OFF], LEVEL_MAGIC
    mov  dword [r12+LVL_VER_OFF], SAVE_VERSION
    mov  dword [r12+LVL_HSIZE_OFF], LVL_HDR
    mov  dword [r12+LVL_PSIZE_OFF], PLAYER_size
    mov  rax, [rel g_seed]
    mov  [r12+LVL_SEED_OFF], rax
    mov  rax, [rel g_world_time]
    mov  [r12+LVL_WTIME_OFF], rax
    mov  eax, [rel g_time_of_day]
    mov  [r12+LVL_TOD_OFF], eax
    mov  eax, [rel g_gamemode]
    mov  [r12+LVL_GM_OFF], eax
    mov  eax, [rel g_weather]
    mov  [r12+LVL_WEATHER_OFF], eax
    mov  eax, [rel g_weather_timer]
    mov  [r12+LVL_WTIMER_OFF], eax
    mov  dword [r12+LVL_BERAW_OFF], BE_BYTES
    mov  dword [r12+LVL_ESIZE_OFF], ENTITY_size

    ; display name, only if it was set for THIS world
    lea  rcx, [rel s_display_owner]
    lea  rdx, [rel g_world_name]
    call sv_stricmp
    test eax, eax
    jnz  .no_name
    lea  rdi, [r12+LVL_NAME_OFF]
    lea  rsi, [rel s_display_name]
    call sv_copy_display
.no_name:

    lea  rdi, [r12+LVL_HDR]
    lea  rsi, [rel g_player]
    mov  ecx, PLAYER_size
    rep  movsb

    lea  rcx, [rel g_blockents]
    mov  edx, BE_BYTES
    lea  r8, [r12+LVL_HDR+PLAYER_size]
    call save_rle_encode
    mov  [r12+LVL_BEENC_OFF], eax

    ; live entities verbatim. ENTITY is plain data, no pointers, so item age,
    ; mob ai timers, tnt fuse etc all come back exactly (v1 files have none).
    ; dying mobs already dropped their loot and empty stacks are junk, so both
    ; get skipped
    lea  rdi, [r12+rax+LVL_HDR+PLAYER_size]
    lea  r14, [rel g_entities]
    xor  r15d, r15d
    xor  ebx, ebx
.ent:
    imul eax, r15d, ENTITY_size
    lea  rsi, [r14+rax]
    movzx eax, byte [rsi+ENTITY.type]
    cmp  eax, ENT_ITEM
    jb   .ent_next
    cmp  eax, ENT_TYPES
    jae  .ent_next
    test byte [rsi+ENTITY.flags], EF_DEAD
    jnz  .ent_next
    cmp  eax, ENT_ITEM
    jne  .not_item
    cmp  byte [rsi+ENTITY.item+STACK.id], 0
    je   .ent_next
    cmp  byte [rsi+ENTITY.item+STACK.count], 0
    je   .ent_next
    jmp  .keep
.not_item:
    cmp  eax, ENT_BOAR
    jb   .keep  ; tnt / falling block, no health
    cmp  dword [rsi+ENTITY.health], 0
    jle  .ent_next
.keep:
    mov  ecx, ENTITY_size
    rep  movsb
    inc  ebx
.ent_next:
    inc  r15d
    cmp  r15d, MAX_ENTITIES
    jb   .ent
    mov  [r12+LVL_NENT_OFF], ebx
    mov  [rel s_last_ent_count], ebx
    mov  r13, rdi
    sub  r13, r12

    ; checksum covers everything after the v1-sized header
    lea  rcx, [r12+LVL_CRC_START]
    lea  rdx, [r13-LVL_CRC_START]
    call save_fnv32
    mov  [r12+LVL_CRC_OFF], eax

    lea  rdi, LOC(0)
    call sv_world_dir
    lea  rsi, [rel s_level]
    call sv_append
    lea  rcx, LOC(0)
    mov  rdx, r12
    mov  r8, r13
    call file_write_all
    mov  ebx, eax
    mov  [rel s_last_level_size], r13d
    mov  rcx, r12
    call mem_free
    mov  eax, ebx
    jmp  .done
.fail:
    xor  eax, eax
.done:
ENDP

; make a loaded g_player resumable. game.asm only enters ST_DEAD on a 0 -> 1
; edge of PLAYER.dead, so a player saved dead would be stuck -> respawn.
; autosave in a container screen leaves stacks on the cursor / craft grid,
; which only exist in that screen, so they go back to the inventory.
SPROC sv_fix_player, 0
    lea  rbx, [rel g_player]
    mov  eax, [rbx+PLAYER.selected]
    cmp  eax, HOTBAR_SLOTS
    jb   .sel_ok
    mov  dword [rbx+PLAYER.selected], 0
.sel_ok:
    lea  rdi, [rbx+PLAYER.cursor]  ; cursor + craft[9], contiguous
    xor  esi, esi
.stack:
    mov  eax, [rdi+rsi*4]
    test al, al
    jz   .next
    xor  ecx, ecx
.find:
    cmp  byte [rbx+PLAYER.inv+rcx*4+STACK.id], 0
    je   .put
    inc  ecx
    cmp  ecx, INV_SLOTS
    jb   .find
    jmp  .next  ; inventory full, leave it
.put:
    mov  [rbx+PLAYER.inv+rcx*4], eax
    mov  dword [rdi+rsi*4], 0
.next:
    inc  esi
    cmp  esi, 10
    jb   .stack
    mov  dword [rbx+PLAYER.craft_out], 0

    mov  eax, [rbx+PLAYER.health]  ; health > 20 isn't a real state
    cmp  eax, 20
    jle  .hp_ok
    mov  dword [rbx+PLAYER.health], 20
.hp_ok:
    cmp  dword [rbx+PLAYER.dead], 0
    jne  .revive
    cmp  dword [rbx+PLAYER.health], 0
    jg   .done
.revive:
    call player_respawn
.done:
ENDP

; a good checksum only means the file is intact, not that a sane build wrote
; it, so every record gets checked. prev_* = pos so the first frame doesn't
; lerp from wherever it was a tick before the save
SPROC sv_restore_entities, 0
    mov  rsi, rcx
    mov  r12d, edx
    lea  r13, [rel g_entities]
    xor  r14d, r14d
    xor  r15d, r15d
.rec:
    test r12d, r12d
    jz   .done
    movzx eax, byte [rsi+ENTITY.type]
    cmp  eax, ENT_ITEM
    jb   .skip
    cmp  eax, ENT_TYPES
    jae  .skip
    test byte [rsi+ENTITY.flags], EF_DEAD
    jnz  .skip
    mov  ecx, [rsi+ENTITY.x]  ; NaN / inf
    and  ecx, 0x7F800000
    cmp  ecx, 0x7F800000
    je   .skip
    mov  ecx, [rsi+ENTITY.y]
    and  ecx, 0x7F800000
    cmp  ecx, 0x7F800000
    je   .skip
    mov  ecx, [rsi+ENTITY.z]
    and  ecx, 0x7F800000
    cmp  ecx, 0x7F800000
    je   .skip
    cmp  eax, ENT_ITEM
    jne  .not_item
    cmp  byte [rsi+ENTITY.item+STACK.id], 0
    je   .skip
    cmp  byte [rsi+ENTITY.item+STACK.count], 0
    je   .skip
    jmp  .slot
.not_item:
    cmp  eax, ENT_BOAR
    jb   .slot  ; TNT / falling block: no health
    cmp  dword [rsi+ENTITY.health], 0
    jle  .skip
.slot:
    cmp  r14d, MAX_ENTITIES
    jae  .done  ; pool full, drop the rest
    imul eax, r14d, ENTITY_size
    lea  rdi, [r13+rax]
    inc  r14d
    cmp  byte [rdi+ENTITY.type], 0
    jne  .slot
    mov  rbx, rdi
    mov  ecx, ENTITY_size
    rep  movsb
    mov  eax, [rbx+ENTITY.x]
    mov  [rbx+ENTITY.prev_x], eax
    mov  eax, [rbx+ENTITY.y]
    mov  [rbx+ENTITY.prev_y], eax
    mov  eax, [rbx+ENTITY.z]
    mov  [rbx+ENTITY.prev_z], eax
    mov  dword [rbx+ENTITY.hurt_time], 0
    mov  dword [rbx+ENTITY.death_time], 0
    movzx eax, byte [rbx+ENTITY.type]
    cmp  eax, ENT_BOAR
    je   .persist
    cmp  eax, ENT_WOOLLY
    jne  .placed
.persist:  ; survived a save = the player's, never despawn
    or   byte [rbx+ENTITY.flags], EF_PERSIST
.placed:
    inc  dword [rel g_entity_count]
    inc  r15d
    dec  r12d
    jmp  .rec
.skip:
    add  rsi, ENTITY_size
    dec  r12d
    jmp  .rec
.done:
    mov  eax, r15d
ENDP

; nothing gets touched until the whole file validated. v1 = no entities, no name
%define LL_PATH  0
%define LL_SIZE  PATH_MAX_BUF
%define LL_BERAW (PATH_MAX_BUF+8)
%define LL_HDR   (PATH_MAX_BUF+16)
%define LL_NENT  (PATH_MAX_BUF+20)
%define LL_ESIZE (PATH_MAX_BUF+24)
%define LL_VER   (PATH_MAX_BUF+28)
%define LL_NREST (PATH_MAX_BUF+32)
PROC save_load_level, PATH_MAX_BUF+48
    lea  rcx, [rel g_world_name]
    call sv_valid_name
    test eax, eax
    jz   .ret0
    lea  rdi, LOC(LL_PATH)
    call sv_world_dir
    lea  rsi, [rel s_level]
    call sv_append
    mov  qword LOC(LL_SIZE), 0
    lea  rcx, LOC(LL_PATH)
    lea  rdx, LOC(LL_SIZE)
    call file_read_all
    test rax, rax
    jz   .ret0
    mov  r12, rax
    mov  r13, LOC(LL_SIZE)

    cmp  r13, LVL_HDR_V1
    jb   .bad
    cmp  dword [r12+LVL_MAGIC_OFF], LEVEL_MAGIC
    jne  .bad
    mov  eax, [r12+LVL_VER_OFF]
    mov  LOC(LL_VER), eax
    cmp  eax, 1
    je   .v1
    cmp  eax, 2
    jne  .bad
    cmp  r13, LVL_HDR
    jb   .bad
    mov  dword LOC(LL_HDR), LVL_HDR
    mov  eax, [r12+LVL_NENT_OFF]
    cmp  eax, MAX_ENTITIES  ; we never write more than the pool
    ja   .bad
    mov  LOC(LL_NENT), eax
    mov  eax, [r12+LVL_ESIZE_OFF]
    cmp  eax, 4096  ; keeps NENT*ESIZE small
    ja   .bad
    mov  LOC(LL_ESIZE), eax
    jmp  .hdr_ok
.v1:
    mov  dword LOC(LL_HDR), LVL_HDR_V1
    mov  dword LOC(LL_NENT), 0
    mov  dword LOC(LL_ESIZE), 0
.hdr_ok:
    mov  eax, LOC(LL_HDR)
    cmp  [r12+LVL_HSIZE_OFF], eax
    jne  .bad
    mov  r14d, [r12+LVL_PSIZE_OFF]
    cmp  r14d, LVL_MAX_PLAYER
    ja   .bad
    mov  r15d, [r12+LVL_BEENC_OFF]
    mov  eax, LOC(LL_NENT)
    imul eax, LOC(LL_ESIZE)  ; <= 512*4096, no overflow
    add  rax, r14
    add  rax, r15
    mov  ecx, LOC(LL_HDR)
    add  rax, rcx
    cmp  rax, r13  ; must be exactly this long
    jne  .bad
    mov  eax, [r12+LVL_BERAW_OFF]
    cmp  eax, LVL_MAX_BERAW
    ja   .bad
    mov  LOC(LL_BERAW), rax
    lea  rcx, [r12+LVL_CRC_START]
    lea  rdx, [r13-LVL_CRC_START]
    call save_fnv32
    cmp  eax, [r12+LVL_CRC_OFF]
    jne  .bad
    mov  eax, LOC(LL_HDR)  ; dry run: RLE must decode to exactly BERAW
    lea  rcx, [r12+rax]
    add  rcx, r14
    mov  rdx, r15
    call save_rle_decoded_size
    cmp  rax, LOC(LL_BERAW)
    jne  .bad

    mov  rcx, LOC(LL_BERAW)
    add  rcx, 16
    call mem_alloc
    test rax, rax
    jz   .bad
    mov  rbx, rax
    mov  eax, LOC(LL_HDR)
    lea  rcx, [r12+rax]
    add  rcx, r14
    mov  rdx, r15
    mov  r8, rbx
    mov  r9, LOC(LL_BERAW)
    call save_rle_decode

    ; commit, sanitised
    mov  rax, [r12+LVL_SEED_OFF]
    mov  [rel g_seed], rax
    mov  rax, [r12+LVL_WTIME_OFF]
    mov  [rel g_world_time], rax
    mov  eax, [r12+LVL_TOD_OFF]
    xor  edx, edx
    mov  ecx, DAY_LENGTH
    div  ecx
    mov  [rel g_time_of_day], edx
    mov  eax, [r12+LVL_GM_OFF]
    cmp  eax, GM_CREATIVE
    jbe  .gm_ok
    xor  eax, eax
.gm_ok:
    mov  [rel g_gamemode], eax
    mov  eax, [r12+LVL_WEATHER_OFF]
    cmp  eax, 2
    jbe  .w_ok
    xor  eax, eax
.w_ok:
    mov  [rel g_weather], eax
    mov  eax, [r12+LVL_WTIMER_OFF]
    mov  [rel g_weather_timer], eax

    lea  rdi, [rel s_display_owner]
    lea  rsi, [rel g_world_name]
    mov  ecx, 63
    call sv_append_n
    lea  rdi, [rel s_display_name]
    xor  esi, esi
    cmp  dword LOC(LL_VER), 1
    je   .name
    mov  byte [r12+LVL_NAME_OFF+LVL_NAME_LEN-1], 0  ; force termination
    lea  rsi, [r12+LVL_NAME_OFF]
.name:
    call sv_copy_display

    ; zero, then copy min(stored, current)
    lea  rdi, [rel g_player]
    xor  eax, eax
    mov  ecx, PLAYER_size
    rep  stosb
    mov  ecx, r14d
    cmp  ecx, PLAYER_size
    jbe  .p_len
    mov  ecx, PLAYER_size
.p_len:
    mov  eax, LOC(LL_HDR)
    lea  rsi, [r12+rax]
    lea  rdi, [rel g_player]
    rep  movsb

    lea  rdi, [rel g_blockents]
    xor  eax, eax
    mov  ecx, BE_BYTES
    rep  stosb
    mov  rcx, LOC(LL_BERAW)
    cmp  rcx, BE_BYTES
    jbe  .b_len
    mov  ecx, BE_BYTES
.b_len:
    mov  rsi, rbx
    lea  rdi, [rel g_blockents]
    rep  movsb
    mov  rcx, rbx
    call mem_free

    call entity_clear
    mov  dword LOC(LL_NREST), 0
    cmp  dword LOC(LL_NENT), 0
    je   .ents_done
    cmp  dword LOC(LL_ESIZE), ENTITY_size
    je   .ents
    lea  rcx, [rel fmt_ent_size]  ; other ENTITY layout, can't trust the records
    mov  edx, LOC(LL_ESIZE)
    mov  r8d, ENTITY_size
    call log_printf
    jmp  .ents_done
.ents:
    mov  eax, LOC(LL_HDR)
    lea  rcx, [r12+rax]
    add  rcx, r14
    add  rcx, r15
    mov  edx, LOC(LL_NENT)
    call sv_restore_entities
    mov  LOC(LL_NREST), eax
.ents_done:

    mov  rcx, r12
    call mem_free
    call sv_fix_player
    mov  rax, [rel g_world_time]
    mov  [rel s_last_save_time], rax
    lea  rcx, [rel fmt_loaded]
    lea  rdx, [rel g_world_name]
    mov  r8d, LOC(LL_VER)
    mov  r9d, LOC(LL_NREST)
    call log_printf
    mov  eax, 1
    jmp  .done

.bad:
    lea  rcx, [rel fmt_bad_level]
    lea  rdx, [rel g_world_name]
    call log_printf
    mov  rcx, r12
    call mem_free
.ret0:
    xor  eax, eax
.done:
ENDP

; unmodified chunks write nothing, they regenerate from the seed
%define CHK_BUF_CAP (CHK_HDR + 2*CHUNK_VOL)
PROC save_chunk, PATH_MAX_BUF
    mov  rbx, rcx
    test rbx, rbx
    jz   .ret0
    cmp  dword [rbx+CHUNK.modified], 0
    je   .ret0
    lea  rcx, [rel g_world_name]  ; no valid world, flag stays set
    call sv_valid_name
    test eax, eax
    jz   .ret0
    mov  ecx, CHK_BUF_CAP
    call mem_alloc
    test rax, rax
    jz   .ret0
    mov  r12, rax

    mov  dword [r12+CHK_MAGIC_OFF], CHUNK_MAGIC
    mov  dword [r12+CHK_VER_OFF], CHUNK_VERSION
    mov  eax, [rbx+CHUNK.cx]
    mov  [r12+CHK_CX_OFF], eax
    mov  eax, [rbx+CHUNK.cz]
    mov  [r12+CHK_CZ_OFF], eax
    mov  dword [r12+CHK_RAW_OFF], CHUNK_VOL
    lea  rcx, [rbx+CHUNK_BLOCKS]
    mov  edx, CHUNK_VOL
    call save_fnv32
    mov  [r12+CHK_CRC_OFF], eax
    lea  rcx, [rbx+CHUNK_BLOCKS]
    mov  edx, CHUNK_VOL
    lea  r8, [r12+CHK_HDR]
    call save_rle_encode
    mov  [r12+CHK_ENC_OFF], eax
    lea  r13, [rax+CHK_HDR]

    lea  rdi, LOC(0)
    mov  ecx, [rbx+CHUNK.cx]
    mov  edx, [rbx+CHUNK.cz]
    call sv_chunk_path
    lea  rcx, LOC(0)
    mov  rdx, r12
    mov  r8, r13
    call file_write_all
    test eax, eax
    jnz  .written
    ; first save of a new world (chunk evicted before any save_world),
    ; make the folders and retry
    call sv_ensure_dirs
    lea  rcx, LOC(0)
    mov  rdx, r12
    mov  r8, r13
    call file_write_all
    test eax, eax
    jz   .free
.written:
    mov  dword [rbx+CHUNK.modified], 0
    mov  eax, 1
.free:
    mov  r14d, eax
    mov  rcx, r12
    call mem_free
    mov  eax, r14d
    jmp  .done
.ret0:
    xor  eax, eax
.done:
ENDP

; runs on worker threads with the chunk in CS_GENERATING: only its own CHUNK,
; stack buffers and thread-safe calls. light and biomes are derived, rebuilt here
%define LC_PATH 0
%define LC_SIZE PATH_MAX_BUF
PROC save_load_chunk, PATH_MAX_BUF+16
    mov  rbx, rcx
    lea  rcx, [rel g_world_name]
    call sv_valid_name
    test eax, eax
    jz   .ret0
    lea  rdi, LOC(LC_PATH)
    mov  ecx, [rbx+CHUNK.cx]
    mov  edx, [rbx+CHUNK.cz]
    call sv_chunk_path
    mov  qword LOC(LC_SIZE), 0
    lea  rcx, LOC(LC_PATH)
    lea  rdx, LOC(LC_SIZE)
    call file_read_all
    test rax, rax
    jz   .ret0  ; no file = never modified -> worldgen
    mov  r12, rax
    mov  r13, LOC(LC_SIZE)
    xor  r14d, r14d

    cmp  r13, CHK_HDR
    jb   .corrupt
    cmp  dword [r12+CHK_MAGIC_OFF], CHUNK_MAGIC
    jne  .corrupt
    cmp  dword [r12+CHK_VER_OFF], CHUNK_VERSION
    jne  .corrupt
    mov  eax, [r12+CHK_CX_OFF]
    cmp  eax, [rbx+CHUNK.cx]
    jne  .corrupt
    mov  eax, [r12+CHK_CZ_OFF]
    cmp  eax, [rbx+CHUNK.cz]
    jne  .corrupt
    cmp  dword [r12+CHK_RAW_OFF], CHUNK_VOL
    jne  .corrupt
    mov  r15d, [r12+CHK_ENC_OFF]
    lea  rax, [r15+CHK_HDR]
    cmp  rax, r13
    jne  .corrupt
    lea  rcx, [r12+CHK_HDR]  ; dry run before touching the chunk
    mov  rdx, r15
    call save_rle_decoded_size
    cmp  rax, CHUNK_VOL
    jne  .corrupt
    lea  rcx, [r12+CHK_HDR]
    mov  rdx, r15
    lea  r8, [rbx+CHUNK_BLOCKS]
    mov  r9d, CHUNK_VOL
    call save_rle_decode
    lea  rcx, [rbx+CHUNK_BLOCKS]
    mov  edx, CHUNK_VOL
    call save_fnv32
    cmp  eax, [r12+CHK_CRC_OFF]
    jne  .bad_crc
    mov  r14d, 1
    jmp  .free
.bad_crc:  ; well-formed but damaged: zero it so a failed load is deterministic
    lea  rdi, [rbx+CHUNK_BLOCKS]
    xor  eax, eax
    mov  ecx, CHUNK_VOL
    rep  stosb
.corrupt:
    lea  rcx, [rel fmt_bad_chunk]
    lea  rdx, LOC(LC_PATH)
    call log_printf
.free:
    mov  rcx, r12
    call mem_free
    test r14d, r14d
    jz   .ret0

    lea  rdi, [rbx+CHUNK_LIGHT]  ; light.asm fills it
    xor  eax, eax
    mov  ecx, CHUNK_VOL
    rep  stosb
    mov  r12d, [rbx+CHUNK.cx]
    shl  r12d, 4
    mov  r13d, [rbx+CHUNK.cz]
    shl  r13d, 4
    xor  esi, esi
.biome:
    mov  ecx, esi
    and  ecx, 15
    add  ecx, r12d
    mov  edx, esi
    shr  edx, 4
    add  edx, r13d
    call worldgen_biome_at
    lea  rcx, [rbx+CHUNK.biome]
    mov  [rcx+rsi], al
    inc  esi
    cmp  esi, 256
    jb   .biome
    mov  rcx, rbx
    call light_init_chunk_sky
    mov  dword [rbx+CHUNK.modified], 0
    mov  eax, 1
    jmp  .done
.ret0:
    xor  eax, eax
.done:
ENDP

PROC save_world, 0 ; v1: save scratch #1
    lea  rcx, [rel g_world_name] ; v1: save scratch #2
    ; TODO: clamp index before table lookup on malformed input (save:2)
    call sv_valid_name ; v1: save scratch #3
    test eax, eax ; v1: save scratch #4
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (save:4)
    jz   .done ; v1: save scratch #5
    call sv_ensure_dirs ; v1: save scratch #6
    ; TODO: hoist invariant pointer load out of .loop (save:6)
    call sv_write_level ; v1: save scratch #7
    mov  ebx, eax ; v1: save scratch #8
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (save:8)
    call chunkmgr_save_all ; v1: save scratch #9
    mov  rax, [rel g_world_time] ; v1: save scratch #10
    ; TODO: verify 16-byte rsp alignment before inner call (save:10)
    mov  [rel s_last_save_time], rax ; v1: save scratch #11
    test ebx, ebx ; v1: save scratch #12
    ; temp: spill r12/r13 across helper call until reg alloc pass (save:12)
    jz   .failed ; v1: save scratch #13
    lea  rcx, [rel fmt_saved] ; v1: save scratch #14
    ; note: rcx = state ptr, rdx = index, r8d = flags (save:14)
    lea  rdx, [rel g_world_name] ; v1: save scratch #15
    mov  r8d, [rel s_last_level_size] ; v1: save scratch #16
    ; FIXME: negative world x/z needs sar 4, not shr 4 (save:16)
    mov  r9d, [rel s_last_ent_count] ; v1: save scratch #17
    call log_printf ; v1: save scratch #18
    ; TODO: clamp index before table lookup on malformed input (save:18)
    mov  eax, 1 ; v1: save scratch #19
    jmp  .done ; v1: save scratch #20
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (save:20)
.failed: ; v1: save scratch #21
    lea  rcx, [rel fmt_save_fail] ; v1: save scratch #22
    ; TODO: hoist invariant pointer load out of .loop (save:22)
    lea  rdx, [rel g_world_name] ; v1: save scratch #23
    call log_printf ; v1: save scratch #24
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (save:24)
    xor  eax, eax ; v1: save scratch #25
.done: ; v1: save scratch #26
    ; TODO: verify 16-byte rsp alignment before inner call (save:26)
ENDP ; v1: save scratch #27

; most recently played first. names over 31 chars are skipped.
; -> eax count, rdx = that many WI_SIZE records in the same order (static,
; good until the next call). the api only promises eax, the menu wants rdx
%define LW_FD    0 ; v1: save scratch #32
    ; temp: spill r12/r13 across helper call until reg alloc pass (save:32)
%define LW_PATH  FD_SIZE ; v1: save scratch #33
%define LW_FAD   (FD_SIZE+PATH_MAX_BUF) ; v1: save scratch #34
    ; note: rcx = state ptr, rdx = index, r8d = flags (save:34)
PROC save_list_worlds, FD_SIZE+PATH_MAX_BUF+48 ; v1: save scratch #35
    mov  r12, rcx ; v1: save scratch #36
    ; FIXME: negative world x/z needs sar 4, not shr 4 (save:36)
    mov  r13d, edx ; v1: save scratch #37
    xor  r15d, r15d ; v1: save scratch #38
    ; TODO: clamp index before table lookup on malformed input (save:38)
    xor  r14d, r14d ; v1: save scratch #39
    test r12, r12 ; v1: save scratch #40
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (save:40)
    jz   .ret ; v1: save scratch #41
    test r13d, r13d
    jle  .ret
    mov  ecx, LIST_CAP*LIST_REC
    call mem_alloc
    test rax, rax
    jz   .ret
    mov  r14, rax

    lea  rcx, [rel s_saves_glob]
    lea  rdx, LOC(LW_FD)
    call FindFirstFileA
    cmp  rax, INVALID_HANDLE_VALUE
    je   .sort
    mov  rbx, rax
.entry:
    test dword LOC(LW_FD+FD_ATTR), FILE_ATTRIBUTE_DIRECTORY
    jz   .next
    lea  rcx, LOC(LW_FD+FD_NAME)
    call sv_valid_name
    test eax, eax
    jz   .next
    lea  rcx, LOC(LW_FD+FD_NAME)  ; must fit 31 chars + NUL
    xor  eax, eax
.len:
    cmp  byte [rcx+rax], 0
    je   .len_done
    inc  eax
    jmp  .len
.len_done:
    cmp  eax, LIST_NAME_MAX
    ja   .next
    lea  rdi, LOC(LW_PATH)
    lea  rsi, [rel s_saves_slash]
    call sv_append
    lea  rsi, LOC(LW_FD+FD_NAME)
    call sv_append
    lea  rsi, [rel s_level]
    call sv_append
    lea  rcx, LOC(LW_PATH)
    xor  edx, edx  ; GetFileExInfoStandard
    lea  r8, LOC(LW_FAD)
    call GetFileAttributesExA
    test eax, eax
    jz   .next  ; no level.dat, not a world
    test dword LOC(LW_FAD+FAD_ATTR), FILE_ATTRIBUTE_DIRECTORY
    jnz  .next
    cmp  r15d, LIST_CAP
    jae  .next
    imul eax, r15d, LIST_REC
    lea  rdi, [r14+rax]
    lea  rsi, LOC(LW_FD+FD_NAME)
    mov  ecx, LIST_NAME_MAX
    call sv_append_n
    imul eax, r15d, LIST_REC
    mov  rdx, LOC(LW_FAD+FAD_WRITETIME)
    mov  [r14+rax+32], rdx
    inc  r15d
.next:
    mov  rcx, rbx
    lea  rdx, LOC(LW_FD)
    call FindNextFileA
    test eax, eax
    jnz  .entry
    mov  rcx, rbx
    call FindClose

.sort:
    mov  rcx, r14
    mov  edx, r15d
    call sv_sort_records
    cmp  r15d, r13d  ; n = min(found, max)
    jbe  .n_ok
    mov  r15d, r13d
.n_ok:
    xor  ebx, ebx
.copy:
    cmp  ebx, r15d
    jae  .copied
    imul eax, ebx, LIST_REC
    lea  rsi, [r14+rax]
    mov  eax, ebx
    shl  eax, 5
    lea  rdi, [r12+rax]
    mov  ecx, 32
    rep  movsb
    mov  eax, ebx
    shl  eax, 5
    lea  rcx, [r12+rax]
    imul eax, ebx, WI_SIZE
    lea  rdx, [rel s_list_info]
    add  rdx, rax
    call save_world_info
    inc  ebx
    jmp  .copy
.copied:
    mov  rcx, r14
    call mem_free
.ret:
    mov  eax, r15d
    lea  rdx, [rel s_list_info]
ENDP
    ; v1 temporary guard (save #18)
    xor     r11d, r11d ; clear v1 slot 18
    ; v1 temporary guard (save #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (save #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (save #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (save #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (save #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (save #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (save #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (save #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (save #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (save #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (save #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (save #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (save #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (save #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (save #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (save #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (save #52)
    xor     r11d, r11d ; clear v1 slot 52
    ; v1 temporary guard (save #54)
    xor     r11d, r11d ; clear v1 slot 54
    ; v1 temporary guard (save #56)
    xor     r11d, r11d ; clear v1 slot 56
    ; v1 temporary guard (save #58)
    xor     r11d, r11d ; clear v1 slot 58
    ; v1 temporary guard (save #60)
    xor     r11d, r11d ; clear v1 slot 60
