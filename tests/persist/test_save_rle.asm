; rle codec + fnv32 from save.asm vs the pu_rle_ref / pu_fnv32 references.
; @link src/save.asm src/config.asm tests/persist/mock_platform.asm tests/persist/persist_util.asm
; @timeout 60
%include "common.inc"
%include "testlib.inc"
%include "../persist/persist.inc"

section .rdata
align 8
sizes:          dq 0, 1, 2, 3, 254, 255, 256, 257, 1000, 32768
sizes_end:
alphabets:      dd 2, 4, 256
run_sizes:      dq 255, 256, 510, 511, 32768
run_sizes_end:
mal_ok:         db 5, 1, 3, 2
mal_odd:        db 5, 1, 3
mal_zero:       db 5, 1, 0, 2
mal_over:       db 0xFF, 1, 0xFF, 1         ; 510 > 300
mal_fit:        db 0xFF, 1, 0x2D, 1         ; 255 + 45 = 300 exactly
s_a:            db 'a'
s_mine:         db 'MineAssembly'
d_vol:          dq 32768.0
s_nat1:         db 10, '  natural chunks: x', 0
s_nat2:         db ' .. x', 0
s_nat3:         db ' (avg ', 0
s_nat4:         db ' bytes)', 10, '  flat chunk: ', 0
s_nat5:         db ' bytes (x', 0
s_nat6:         db ')', 10, 0

section .bss
alignb 16
data:           resb 32768 + 16
enc:            resb 65536 + 16
ref:            resb 65536 + 16
dec:            resb 32768 + 16
fnvbuf:         resb 256*9

section .text

PROC encode, 0
    mov  rdx, rcx
    lea  rcx, [rel data]
    lea  r8, [rel enc]
    call save_rle_encode
ENDP

; dec is pre-filled with 0xEE so short output shows up
PROC decode, 0
    mov  rbx, rcx
    mov  rsi, rdx
    lea  rcx, [rel dec]
    mov  edx, 0xEE
    mov  r8d, 32768
    call pu_memset
    lea  rcx, [rel enc]
    mov  rdx, rbx
    lea  r8, [rel dec]
    mov  r9, rsi
    call save_rle_decode
ENDP

PROC test_main, 32
    TEST "rle: random roundtrip and matches reference"
    mov  ecx, 1234
    call t_rng_seed
    lea  r12, [rel sizes]
.size:
    xor  r13d, r13d
.alpha:
    mov  r14, [r12]
    lea  rax, [rel alphabets]
    mov  r15d, [rax+r13*4]
    xor  ebx, ebx
.fill:
    cmp  rbx, r14
    jae  .filled
    mov  ecx, r15d
    call pu_rand_below
    lea  rcx, [rel data]
    mov  [rcx+rbx], al
    inc  rbx
    jmp  .fill
.filled:
    mov  rcx, r14
    call encode
    mov  rbx, rax
    lea  rcx, [rel data]
    mov  rdx, r14
    lea  r8, [rel ref]
    call pu_rle_ref
    mov  rsi, rax
    CHECK_EQ rbx, rsi, "encoded length == reference"
    lea  rax, [rel enc]
    lea  rdi, [rel ref]
    CHECK_MEM rax, rdi, rsi, "encoded bytes == reference"
    lea  rax, [r14*2]
    cmp  rbx, rax
    setbe al
    movzx eax, al
    CHECK_TRUE eax, "len(enc) <= 2n"
    mov  rcx, rbx
    mov  rdx, r14
    call decode
    CHECK_EQ rax, r14, "decoded length == n"
    lea  rax, [rel dec]
    lea  rdi, [rel data]
    CHECK_MEM rax, rdi, r14, "decoded bytes == data"
    inc  r13d
    cmp  r13d, 3
    jb   .alpha
    add  r12, 8
    lea  rax, [rel sizes_end]
    cmp  r12, rax
    jb   .size

    TEST "rle: run boundaries"
    lea  r12, [rel run_sizes]
.run:
    mov  r14, [r12]
    lea  rcx, [rel data]
    mov  edx, 7
    mov  r8, r14
    call pu_memset
    mov  rcx, r14
    call encode
    mov  rbx, rax
    lea  rax, [r14+254]
    xor  edx, edx
    mov  ecx, 255
    div  rcx                            ; ceil(n / 255) runs
    add  rax, rax
    mov  rsi, rax
    CHECK_EQ rbx, rsi, "2 bytes per run of <= 255"
    mov  rax, r14                       ; last count = n % 255 or 255
    xor  edx, edx
    mov  ecx, 255
    div  rcx
    test edx, edx
    jnz  .haslast
    mov  edx, 255
.haslast:
    mov  edi, edx
    mov  r13d, 1                        ; every count must be 255 or the last one
    xor  ecx, ecx
    lea  rax, [rel enc]
.cnt:
    cmp  rcx, rbx
    jae  .cntdone
    movzx edx, byte [rax+rcx]
    cmp  edx, 255
    je   .cntok
    cmp  edx, edi
    je   .cntok
    xor  r13d, r13d
.cntok:
    add  rcx, 2
    jmp  .cnt
.cntdone:
    CHECK_TRUE r13d, "every count is 255 or n % 255"
    mov  rcx, rbx
    mov  rdx, r14
    call decode
    lea  rax, [rel dec]
    lea  rdi, [rel data]
    CHECK_MEM rax, rdi, r14, "decoded run == data"
    add  r12, 8
    lea  rax, [rel run_sizes_end]
    cmp  r12, rax
    jb   .run

    TEST "rle: typical chunk compresses well"
    mov  r12d, 1
    xor  r13d, r13d
    mov  r14d, 0x7FFFFFFF
    xorpd xmm0, xmm0
    movsd LOC(0), xmm0                  ; sum of ratios
.seed:
    mov  ecx, r12d
    lea  rdx, [rel data]
    call pu_typical_chunk
    mov  ecx, 32768
    call encode
    mov  rbx, rax
    cmp  ebx, r13d
    cmova r13d, ebx                     ; longest encoding = worst ratio
    cmp  ebx, r14d
    cmovb r14d, ebx
    movsd xmm0, [rel d_vol]
    cvtsi2sd xmm1, rbx
    divsd xmm0, xmm1
    addsd xmm0, LOC(0)
    movsd LOC(0), xmm0
    mov  rcx, rbx
    mov  edx, 32768
    call decode
    CHECK_EQ rax, 32768, "natural chunk decodes to 32768 bytes"
    lea  rax, [rel dec]
    lea  rdi, [rel data]
    CHECK_MEM rax, rdi, 32768, "natural chunk round trip"
    inc  r12d
    cmp  r12d, 8
    jle  .seed
    lea  rcx, [rel s_nat1]
    call t_print
    movsd xmm0, [rel d_vol]
    cvtsi2sd xmm1, r13
    divsd xmm0, xmm1
    mov  edx, 1
    call t_print_double
    lea  rcx, [rel s_nat2]
    call t_print
    movsd xmm0, [rel d_vol]
    cvtsi2sd xmm1, r14
    divsd xmm0, xmm1
    mov  edx, 1
    call t_print_double
    lea  rcx, [rel s_nat3]
    call t_print
    mov  eax, 8
    cvtsi2sd xmm1, eax
    movsd xmm2, LOC(0)
    divsd xmm2, xmm1
    movsd xmm0, [rel d_vol]
    divsd xmm0, xmm2
    xor  edx, edx
    call t_print_double
    ; min ratio > 12  <=>  32768 > 12 * longest
    imul eax, r13d, 12
    cmp  eax, 32768
    setb al
    movzx eax, al
    CHECK_TRUE eax, "worst natural chunk ratio > 12"
    lea  rcx, [rel data]
    call pu_flat_chunk
    mov  ecx, 32768
    call encode
    mov  rbx, rax
    lea  rcx, [rel s_nat4]
    call t_print
    mov  rcx, rbx
    call t_print_int
    lea  rcx, [rel s_nat5]
    call t_print
    movsd xmm0, [rel d_vol]
    cvtsi2sd xmm1, rbx
    divsd xmm0, xmm1
    xor  edx, edx
    call t_print_double
    lea  rcx, [rel s_nat6]
    call t_print
    imul eax, ebx, 100
    cmp  eax, 32768
    setb al
    movzx eax, al
    CHECK_TRUE eax, "flat chunk ratio > 100"

    TEST "rle: malformed streams"
    lea  rcx, [rel mal_ok]
    xor  edx, edx
    call save_rle_decoded_size
    CHECK_EQ rax, 0, "size of empty stream"
    lea  rcx, [rel mal_ok]
    mov  edx, 4
    call save_rle_decoded_size
    CHECK_EQ rax, 8, "size of 05 01 03 02"
    lea  rcx, [rel mal_odd]
    mov  edx, 3
    call save_rle_decoded_size
    CHECK_EQ rax, -1, "odd length"
    lea  rcx, [rel mal_zero]
    mov  edx, 4
    call save_rle_decoded_size
    CHECK_EQ rax, -1, "zero count"
    %macro DEC_CASE 4                   ; src, len, cap, want
        lea  rcx, [rel enc]
        lea  rdx, [rel %1]
        mov  r8d, %2
        call pu_memcpy
        mov  ecx, %2
        mov  edx, %3
        call decode
        CHECK_EQ rax, %4, "decode of a malformed stream"
    %endmacro
    DEC_CASE mal_zero, 4, 100, -1
    DEC_CASE mal_odd, 3, 100, -1
    DEC_CASE mal_over, 4, 300, -1
    DEC_CASE mal_fit, 4, 300, 300

    TEST "rle: fnv32"
    xor  ecx, ecx
.fb:
    mov  eax, ecx
    and  eax, 255
    lea  rdx, [rel fnvbuf]
    mov  [rdx+rcx], al
    inc  ecx
    cmp  ecx, 256*9
    jb   .fb
    %macro FNV_CASE 2
        lea  rcx, [rel %1]
        mov  edx, %2
        call save_fnv32
        mov  ebx, eax
        lea  rcx, [rel %1]
        mov  edx, %2
        call pu_fnv32
        mov  esi, eax
        CHECK_EQ rbx, rsi, "save_fnv32 == reference FNV-1a"
    %endmacro
    FNV_CASE s_a, 0
    CHECK_EQ rbx, 0x811C9DC5, "FNV-1a of empty input = offset basis"
    FNV_CASE s_a, 1
    CHECK_EQ rbx, 0xE40C292C, "FNV-1a('a')"
    FNV_CASE s_mine, 12
    FNV_CASE fnvbuf, 256*9
ENDP
