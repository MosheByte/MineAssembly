; chunk files (saves/<world>/chunks/c.<cx>.<cz>.bin): round trip, extreme
; coords, corrupt files.
; @link src/save.asm src/config.asm tests/persist/mock_platform.asm tests/persist/persist_util.asm
; @timeout 60
%include "common.inc"
%include "testlib.inc"
%include "../persist/persist.inc"

section .rdata
s_path_37:      db 'saves\TestWorld\chunks\c.-3.7.bin', 0
s_path_12:      db 'saves\TestWorld\chunks\c.1.2.bin', 0
s_path_fmt:     db 'saves\TestWorld\chunks\c.%d.%d.bin', 0
align 4
coords:         dd 0, 0, -2147483648, 2147483647, 123456, -98765
coords_end:

section .bss
alignb 16
data:           resb 32768
zeros:          resb 32768
biome_exp:      resb 256
pathbuf:        resb 256
blob:           resb 70000
good_ptr:       resq 1
good_len:       resq 1

section .text

; write blob[0..rcx) as c.1.2.bin, load it into a fresh chunk (1, 2)
PROC load_with, 0
    mov  r8, rcx
    lea  rcx, [rel s_path_12]
    lea  rdx, [rel blob]
    call pu_write_file
    mov  ecx, 1
    mov  edx, 2
    call pu_new_chunk
    mov  rcx, rax
    call save_load_chunk
ENDP

PROC reset_blob, 0
    lea  rcx, [rel blob]
    xor  edx, edx
    mov  r8d, 70000
    call pu_memset
    lea  rcx, [rel blob]
    mov  rdx, [rel good_ptr]
    mov  r8, [rel good_len]
    call pu_memcpy
ENDP

PROC test_main, 32
    CASE "chunks: roundtrip"
    mov  ecx, 7
    lea  rdx, [rel data]
    call pu_typical_chunk
    mov  ecx, -3
    mov  edx, 7
    call pu_new_chunk
    mov  rbx, rax
    lea  rcx, [rbx+CHUNK_BLOCKS]
    lea  rdx, [rel data]
    mov  r8d, CHUNK_VOL
    call pu_memcpy
    mov  rcx, rbx
    call save_chunk
    CHECK_EQ32 eax, 0, "unmodified chunk must not be saved"
    CHECK_EXISTS "saves\TestWorld\chunks\c.-3.7.bin", 0, "no file for an unmodified chunk"
    mov  dword [rbx+CHUNK.modified], 1
    mov  rcx, rbx
    call save_chunk
    CHECK_EQ32 eax, 1, "save_chunk creates the folders itself"
    CHECK_EQ32 [rbx+CHUNK.modified], 0, "modified flag cleared"
    CHECK_EXISTS "saves\TestWorld\chunks\c.-3.7.bin", 1, "chunk file written"
    lea  rcx, [rel s_path_37]
    call pu_read_file
    mov  rsi, rax
    mov  r12, rdx
    CHECK_EQ32 [rsi], 'MASC', "magic"
    CHECK_EQ32 [rsi+4], 1, "version"
    CHECK_EQ32 [rsi+8], -3, "cx"
    CHECK_EQ32 [rsi+12], 7, "cz"
    CHECK_EQ32 [rsi+16], CHUNK_VOL, "raw length"
    lea  r13, [r12-32]
    CHECK_EQ32 [rsi+20], r13d, "encoded length = file size - 32"
    lea  rcx, [rel data]
    mov  edx, CHUNK_VOL
    call pu_fnv32
    mov  r13d, eax
    CHECK_EQ32 [rsi+24], r13d, "checksum = FNV-1a of the blocks"
    cmp  r12, 4096
    setb al
    movzx eax, al
    CHECK_TRUE eax, "natural chunk file < 4096 bytes"
    mov  r14d, [rel mock_light_calls]
    mov  ecx, -3
    mov  edx, 7
    call pu_new_chunk
    mov  rdi, rax
    lea  rcx, [rdi+CHUNK_LIGHT]
    mov  edx, 0x5A
    mov  r8d, CHUNK_VOL
    call pu_memset
    mov  rcx, rdi
    call save_load_chunk
    CHECK_EQ32 eax, 1, "save_load_chunk finds the file"
    lea  rax, [rdi+CHUNK_BLOCKS]
    lea  rcx, [rel data]
    mov  r15, rcx
    CHECK_MEM rax, r15, CHUNK_VOL, "blocks restored"
    inc  r14d
    CHECK_EQ32 [rel mock_light_calls], r14d, "light_init_chunk_sky called once"
    lea  rax, [rdi+CHUNK_LIGHT]
    lea  r15, [rel zeros]
    CHECK_MEM rax, r15, CHUNK_VOL, "light reset to 0"
    CHECK_EQ32 [rdi+CHUNK.modified], 0, "loaded chunk is not modified"
    ; expected biomes, same formula as the mock worldgen_biome_at
    xor  ecx, ecx
.bio:
    mov  eax, ecx
    and  eax, 15
    sub  eax, 48
    imul eax, eax, 7
    mov  edx, ecx
    shr  edx, 4
    add  edx, 112
    imul edx, edx, 13
    add  eax, edx
    and  eax, 0x7FFFFFFF
    xor  edx, edx
    mov  r8d, 12
    div  r8d
    lea  rax, [rel biome_exp]
    mov  [rax+rcx], dl
    inc  ecx
    cmp  ecx, 256
    jb   .bio
    lea  rax, [rdi+CHUNK.biome]
    lea  r15, [rel biome_exp]
    CHECK_MEM rax, r15, 256, "biomes recomputed with worldgen_biome_at"
    ENDCASE

    CASE "chunks: missing and extreme coords"
    mov  ecx, 5
    mov  edx, 5
    call pu_new_chunk
    mov  rcx, rax
    call save_load_chunk
    CHECK_EQ32 eax, 0, "missing chunk file -> 0"
    lea  r12, [rel coords]
.coord:
    mov  ecx, [r12]
    mov  edx, [r12+4]
    call pu_new_chunk
    mov  rbx, rax
    xor  ecx, ecx                       ; blocks[i] = (i*31 + cx) & 0xFF
.pat:
    imul eax, ecx, 31
    add  eax, [r12]
    mov  [rbx+CHUNK_BLOCKS+rcx], al
    inc  ecx
    cmp  ecx, CHUNK_VOL
    jb   .pat
    mov  dword [rbx+CHUNK.modified], 1
    mov  rcx, rbx
    call save_chunk
    CHECK_EQ32 eax, 1, "save_chunk at extreme coords"
    lea  rcx, [rel pathbuf]
    lea  rdx, [rel s_path_fmt]
    mov  r8d, [r12]
    mov  r9d, [r12+4]
    call wsprintfA
    lea  rcx, [rel pathbuf]
    call pu_exists
    CHECK_EQ32 eax, 1, "file c.<cx>.<cz>.bin exists"
    mov  ecx, [r12]
    mov  edx, [r12+4]
    call pu_new_chunk
    mov  rdi, rax
    mov  rcx, rdi
    call save_load_chunk
    CHECK_EQ32 eax, 1, "load at extreme coords"
    lea  rax, [rdi+CHUNK_BLOCKS]
    lea  r15, [rbx+CHUNK_BLOCKS]
    CHECK_MEM rax, r15, CHUNK_VOL, "blocks restored at extreme coords"
    add  r12, 8
    lea  rax, [rel coords_end]
    cmp  r12, rax
    jb   .coord
    ENDCASE

    CASE "chunks: corrupt files rejected"
    mov  ecx, 1
    mov  edx, 2
    call pu_new_chunk
    mov  rbx, rax
    mov  ecx, 3
    lea  rdx, [rbx+CHUNK_BLOCKS]
    call pu_typical_chunk
    mov  dword [rbx+CHUNK.modified], 1
    mov  rcx, rbx
    call save_chunk
    CHECK_EQ32 eax, 1, "save_chunk"
    lea  rcx, [rel s_path_12]
    call pu_read_file
    mov  [rel good_ptr], rax
    mov  [rel good_len], rdx
    mov  r12, rdx
    lea  rsi, [rel blob]
    call reset_blob
    mov  rcx, r12
    call load_with
    CHECK_EQ32 eax, 1, "good file loads"
    mov  byte [rsi], 'X'
    mov  rcx, r12
    call load_with
    CHECK_EQ32 eax, 0, "bad magic"
    call reset_blob
    mov  dword [rsi+4], 2
    mov  rcx, r12
    call load_with
    CHECK_EQ32 eax, 0, "unknown version"
    call reset_blob
    lea  rcx, [r12-2]
    call load_with
    CHECK_EQ32 eax, 0, "truncated"
    lea  rcx, [r12+2]                   ; 2 zero bytes from the blob padding
    call load_with
    CHECK_EQ32 eax, 0, "trailing junk"
    mov  ecx, 10
    call load_with
    CHECK_EQ32 eax, 0, "tiny file"
    xor  byte [rsi+40], 1               ; -> checksum mismatch
    mov  rcx, r12
    call load_with
    CHECK_EQ32 eax, 0, "flipped value byte"
    call reset_blob
    mov  byte [rsi+32], 0
    mov  rcx, r12
    call load_with
    CHECK_EQ32 eax, 0, "zero run count"
    call reset_blob
    mov  dword [rsi+8], 9
    mov  rcx, r12
    call load_with
    CHECK_EQ32 eax, 0, "header coords differ from the chunk"
    ENDCASE
ENDP
