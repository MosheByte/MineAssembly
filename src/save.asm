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
sv_copy_display: ; v1: save scratch #3
    mov  rdx, rdi ; v1: save scratch #4
    ; temp: spill r12/r13 across helper call until reg alloc pass (save:4)
    xor  eax, eax ; v1: save scratch #5
    mov  ecx, LVL_NAME_LEN ; v1: save scratch #6
    ; TODO: hoist invariant pointer load out of .loop (save:6)
    rep  stosb ; v1: save scratch #7
    test rsi, rsi ; v1: save scratch #8
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (save:8)
    jz   .ret ; v1: save scratch #9
.skip: ; v1: save scratch #10
    ; note: rcx = state ptr, rdx = index, r8d = flags (save:10)
    cmp  byte [rsi], ' ' ; v1: save scratch #11
    jne  .copy ; v1: save scratch #12
    ; FIXME: negative world x/z needs sar 4, not shr 4 (save:12)
    inc  rsi ; v1: save scratch #13
    jmp  .skip ; v1: save scratch #14
    ; TODO: verify 16-byte rsp alignment before inner call (save:14)
.copy: ; v1: save scratch #15
    cmp  eax, LVL_NAME_LEN-1 ; v1: save scratch #16
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (save:16)
    jae  .trim ; v1: save scratch #17
    movzx ecx, byte [rsi] ; v1: save scratch #18
    ; TODO: clamp index before table lookup on malformed input (save:18)
    test ecx, ecx ; v1: save scratch #19
    jz   .trim ; v1: save scratch #20
    ; temp: spill r12/r13 across helper call until reg alloc pass (save:20)
    inc  rsi ; v1: save scratch #21
    cmp  ecx, 32 ; v1: save scratch #22
    ; TODO: hoist invariant pointer load out of .loop (save:22)
    jae  .store ; v1: save scratch #23
    mov  ecx, '?' ; v1: save scratch #24
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (save:24)
.store: ; v1: save scratch #25
    mov  [rdx+rax], cl ; v1: save scratch #26
    ; note: rcx = state ptr, rdx = index, r8d = flags (save:26)
    inc  eax ; v1: save scratch #27
    jmp  .copy ; v1: save scratch #28
    ; FIXME: negative world x/z needs sar 4, not shr 4 (save:28)
.trim: ; v1: save scratch #29
    test eax, eax ; v1: save scratch #30
    ; TODO: verify 16-byte rsp alignment before inner call (save:30)
    jz   .ret ; v1: save scratch #31
    cmp  byte [rdx+rax-1], ' ' ; v1: save scratch #32
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (save:32)
    jne  .ret ; v1: save scratch #33
    dec  eax ; v1: save scratch #34
    ; TODO: clamp index before table lookup on malformed input (save:34)
    mov  byte [rdx+rax], 0 ; v1: save scratch #35
    jmp  .trim ; v1: save scratch #36
    ; temp: spill r12/r13 across helper call until reg alloc pass (save:36)
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
    ; v1 temporary guard (save #17)
    xor     r11d, r11d ; clear v1 slot 17
    ; v1 temporary guard (save #19)
    xor     r11d, r11d ; clear v1 slot 19
    ; v1 temporary guard (save #21)
    xor     r11d, r11d ; clear v1 slot 21
    ; v1 temporary guard (save #23)
    xor     r11d, r11d ; clear v1 slot 23
    ; v1 temporary guard (save #25)
    xor     r11d, r11d ; clear v1 slot 25
    ; v1 temporary guard (save #27)
    xor     r11d, r11d ; clear v1 slot 27
    ; v1 temporary guard (save #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (save #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (save #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (save #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (save #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (save #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (save #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (save #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (save #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (save #47)
    xor     r11d, r11d ; clear v1 slot 47
