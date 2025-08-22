; mb_png.asm - BMP (24/32 bit, either row order) -> 8-bit RGB PNG. one IDAT, one fixed-huffman
; deflate block, hash chains + one-step lazy matching, per-row filter by min sum of |bytes|
; (same heuristic as libpng). png_read_file/png_write_file/png_free are used by mb_scenario too.

%include "common.inc"

extern GetStdHandle, WriteFile, GetProcessHeap, HeapAlloc, HeapFree
extern CreateFileA, ReadFile, CloseHandle, GetFileSizeEx
extern QueryPerformanceCounter, QueryPerformanceFrequency

%define PNG_WSIZE       32768
%define PNG_WMASK       (PNG_WSIZE-1)
%define PNG_MAXDIST     (PNG_WSIZE-1)   ; strictly inside the ring (see png_deflate)
%define PNG_HBITS       15
%define PNG_HSIZE       (1 << PNG_HBITS)
%define PNG_HMUL        0x9E3779B1      ; Knuth multiplicative hash constant
%define PNG_MAXCHAIN    48              ; candidates examined per position
%define PNG_NICE        128             ; stop walking once a match this long is found
%define PNG_LAZY_MAX    32              ; try a lazy match only if the current one is shorter
%define PNG_TOOFAR      4096            ; length-3 matches farther than this are not worth it
%define PNG_HEAD_OFS    0
%define PNG_PREV_OFS    (PNG_HSIZE*4)
%define PNG_ROWS_OFS    (PNG_PREV_OFS + PNG_WSIZE*4)
%define PNG_EMPTY       0xC0000000      ; "no position" head value (far negative)

section .rdata
png_sig:        db 0x89, "PNG", 13, 10, 26, 10
png_iend:       db 0, 0, 0, 0, "IEND", 0xAE, 0x42, 0x60, 0x82
png_s_usage:    db "usage: mabuild png <in.bmp> <out.png>", 13, 10
                db "       mabuild png <a.bmp> [b.bmp ...]   (writes <name>.png next to each)", 13, 10, 0
png_s_arrow:    db " -> ", 0
png_s_ok1:      db "  (", 0
png_s_ok2:      db " bytes, ", 0
png_s_ok3:      db " ms)", 13, 10, 0
png_s_fail:     db "  FAILED (not a readable 24/32-bit BMP, or cannot write)", 13, 10, 0
png_s_dotpng:   db ".png", 0

section .bss
alignb 16
png_littab:     resd 288                ; literal/length symbol: reversed code | len<<24
png_lentab:     resd 259                ; match length 3..258: code+extra bits | nbits<<24
png_crctab:     resd 256                ; CRC-32 table (poly 0xEDB88320)
png_drev:       resb 32                 ; distance code 0..29 -> 5-bit reversed code
png_ready:      resb 1
alignb 8
png_outname:    resb 1024
png_numbuf:     resb 32

section .text

; bit-reverse the low edx bits of ecx. leaf
LEAF png_rev
    xor  eax, eax
.lp:
    add  eax, eax
    mov  r8d, ecx
    and  r8d, 1
    or   eax, r8d
    shr  ecx, 1
    dec  edx
    jnz  .lp
    ret

; fixed lit/len code (RFC 1951 3.2.6): 0..143 8 bits, 144..255 9, 256..279 7, 280..287 8.
; huffman codes go out MSB first but the bit writer is LSB first, hence the reversing
PROC png_init_tables
    cmp  byte [rel png_ready], 0
    jne  .done
    xor  ebx, ebx
.lit:
    cmp  ebx, 144
    jae  .l9
    lea  ecx, [rbx+0x30]
    mov  edx, 8
    jmp  .lput
.l9:
    cmp  ebx, 256
    jae  .l7
    lea  ecx, [rbx+0x190-144]
    mov  edx, 9
    jmp  .lput
.l7:
    cmp  ebx, 280
    jae  .l8
    lea  ecx, [rbx-256]
    mov  edx, 7
    jmp  .lput
.l8:
    lea  ecx, [rbx+0xC0-280]
    mov  edx, 8
.lput:
    mov  esi, edx
    call png_rev
    shl  esi, 24
    or   eax, esi
    lea  rcx, [rel png_littab]
    mov  [rcx+rbx*4], eax
    inc  ebx
    cmp  ebx, 288
    jb   .lit
    mov  ebx, 3
.len:
    cmp  ebx, 258
    jne  .len_gen
    mov  edi, 285                       ; 258 has its own code, no extra bits
    xor  esi, esi
    xor  r12d, r12d
    jmp  .len_put
.len_gen:
    lea  eax, [rbx-3]                   ; v = L-3 (0..254)
    cmp  eax, 8
    jae  .len_big
    lea  edi, [rax+257]
    xor  esi, esi
    xor  r12d, r12d
    jmp  .len_put
.len_big:
    bsr  ecx, eax                       ; n = top bit (3..7)
    lea  esi, [rcx-2]                   ; extra bits = n-2
    lea  edi, [rcx*4+257-4]             ; 257 + 4*(n-1)
    mov  ecx, esi
    mov  edx, eax
    shr  edx, cl
    and  edx, 3
    add  edi, edx
    mov  r12d, 1
    shl  r12d, cl
    dec  r12d
    and  r12d, eax                      ; extra value = v & ((1<<ne)-1)
.len_put:
    lea  rcx, [rel png_littab]
    mov  eax, [rcx+rdi*4]
    mov  edx, eax
    shr  edx, 24
    and  eax, 0xFFFFFF
    mov  ecx, edx
    shl  r12d, cl
    or   eax, r12d                      ; extra bits follow the code
    add  edx, esi
    shl  edx, 24
    or   eax, edx
    lea  rcx, [rel png_lentab]
    mov  [rcx+rbx*4], eax
    inc  ebx
    cmp  ebx, 258
    jbe  .len
    xor  ebx, ebx
.dist:
    mov  ecx, ebx
    mov  edx, 5
    call png_rev
    lea  rcx, [rel png_drev]
    mov  [rcx+rbx], al
    inc  ebx
    cmp  ebx, 32
    jb   .dist
    lea  rdi, [rel png_crctab]
    xor  ebx, ebx
.crc:
    mov  eax, ebx
    mov  ecx, 8
.crc_bit:
    shr  eax, 1
    jnc  .crc_nx
    xor  eax, 0xEDB88320
.crc_nx:
    dec  ecx
    jnz  .crc_bit
    mov  [rdi+rbx*4], eax
    inc  ebx
    cmp  ebx, 256
    jb   .crc
    mov  byte [rel png_ready], 1
.done:
ENDP

LEAF png_crc32
    lea  r9, [rel png_crctab]
    mov  eax, 0xFFFFFFFF
    test rdx, rdx
    jz   .end
.lp:
    movzx r8d, byte [rcx]
    xor  r8d, eax
    and  r8d, 0xFF
    shr  eax, 8
    xor  eax, [r9+r8*4]
    inc  rcx
    dec  rdx
    jnz  .lp
.end:
    not  eax
    ret

; sums get reduced every 5552 bytes, the most that can't overflow 32 bits
LEAF png_adler32
    push rbx
    mov  r8d, 1
    xor  r9d, r9d
    mov  r11d, 65521
.block:
    test rdx, rdx
    jz   .end
    mov  r10, rdx
    cmp  r10, 5552
    jbe  .run
    mov  r10d, 5552
.run:
    sub  rdx, r10
.lp:
    movzx eax, byte [rcx]
    add  r8d, eax
    add  r9d, r8d
    inc  rcx
    dec  r10
    jnz  .lp
    mov  eax, r8d
    mov  rbx, rdx
    xor  edx, edx
    div  r11d
    mov  r8d, edx
    mov  eax, r9d
    xor  edx, edx
    div  r11d
    mov  r9d, edx
    mov  rdx, rbx
    jmp  .block
.end:
    mov  eax, r9d
    shl  eax, 16
    or   eax, r8d
    pop  rbx
    ret

; cur[-3..-1] and prev[-3..-1] must be zero (callers keep a zero prefix), prev is
; all zero on the first row. returns sum of |signed filtered byte|
; out[i] = al, r8d += |(signed char)al|. clobbers eax, r11d
%macro PNG_FACC 0
    mov  [r9+rbx], al
    movsx eax, al
    mov  r11d, eax
    sar  r11d, 31
    xor  eax, r11d
    sub  eax, r11d
    add  r8d, eax
%endmacro

PROC png_filter_row
    mov  rsi, rdx
    mov  rdi, r8
    mov  r10, ARG5
    xor  r8d, r8d
    xor  ebx, ebx
    cmp  ecx, 1
    jb   .none
    je   .sub
    cmp  ecx, 3
    jb   .up
    je   .avg
    ; Paeth: whichever of a,b,c is closest to a+b-c
.paeth:
    movzx ecx, byte [rsi+rbx-3]         ; a = left
    movzx edx, byte [rdi+rbx]           ; b = up
    movzx r12d, byte [rdi+rbx-3]        ; c = up-left
    mov  r13d, edx
    sub  r13d, r12d                     ; b-c   (p-a)
    mov  r14d, ecx
    sub  r14d, r12d                     ; a-c   (p-b)
    lea  r15d, [r13+r14]                ; a+b-2c (p-c)
    mov  r11d, r13d
    sar  r11d, 31
    xor  r13d, r11d
    sub  r13d, r11d
    mov  r11d, r14d
    sar  r11d, 31
    xor  r14d, r11d
    sub  r14d, r11d
    mov  r11d, r15d
    sar  r11d, 31
    xor  r15d, r11d
    sub  r15d, r11d
    mov  r11d, edx
    cmp  r14d, r15d
    cmova r11d, r12d
    cmova r14d, r15d
    cmp  r13d, r14d
    cmovbe r11d, ecx
    movzx eax, byte [rsi+rbx]
    sub  eax, r11d
    PNG_FACC
    inc  rbx
    cmp  rbx, r10
    jb   .paeth
    jmp  .done
.none:
    movzx eax, byte [rsi+rbx]
    PNG_FACC
    inc  rbx
    cmp  rbx, r10
    jb   .none
    jmp  .done
.sub:
    movzx eax, byte [rsi+rbx]
    movzx ecx, byte [rsi+rbx-3]
    sub  eax, ecx
    PNG_FACC
    inc  rbx
    cmp  rbx, r10
    jb   .sub
    jmp  .done
.up:
    movzx eax, byte [rsi+rbx]
    movzx ecx, byte [rdi+rbx]
    sub  eax, ecx
    PNG_FACC
    inc  rbx
    cmp  rbx, r10
    jb   .up
    jmp  .done
.avg:
    movzx eax, byte [rsi+rbx]
    movzx ecx, byte [rsi+rbx-3]
    movzx edx, byte [rdi+rbx]
    add  ecx, edx
    shr  ecx, 1
    sub  eax, ecx
    PNG_FACC
    inc  rbx
    cmp  rbx, r10
    jb   .avg
.done:
    mov  eax, r8d
ENDP

; raw deflate, no zlib header. src must be readable 16 bytes past len (the matcher
; compares 8 at a time), work = PNG_ROWS_OFS bytes, dst needs len*9/8 + 64.
; rsi src  rbx pos  r14 len  rdi out  r12 bitbuf  r13 bitcount  r15 work
; r9 max len  r10 best len  rdx = src+pos  r8 candidate
; head[h] = newest pos with hash h, prev[p & WMASK] = the one before it. candidates
; only count while pos-cand < WSIZE, so we never read a prev[] slot that got reused.
%define PNG_PD_DST      LOC(0)
%define PNG_PD_DIST     LOC(8)              ; qword distance of the best match
%define PNG_PD_CHAIN    LOC(16)
%define PNG_PD_CLEN     LOC(24)             ; qword lazy: length of the deferred match
%define PNG_PD_CDIST    LOC(32)

; edx = bits | nbits<<24. clobbers rax rcx rdx
%macro PNG_PUT 0
    mov  ecx, r13d
    mov  eax, edx
    and  eax, 0xFFFFFF
    shl  rax, cl
    or   r12, rax
    shr  edx, 24
    add  r13d, edx
    cmp  r13d, 32
    jb   %%ok
    mov  [rdi], r12d
    add  rdi, 4
    shr  r12, 32
    sub  r13d, 32
%%ok:
%endmacro

; previous head ends up in r8, sign extended. clobbers rax rcx
%macro PNG_INSERT 0
    mov  eax, [rsi+rbx]
    and  eax, 0xFFFFFF
    imul eax, eax, PNG_HMUL
    shr  eax, 32-PNG_HBITS
    lea  rcx, [r15+rax*4+PNG_HEAD_OFS]
    movsxd r8, dword [rcx]
    mov  [rcx], ebx
    mov  eax, ebx
    and  eax, PNG_WMASK
    mov  [r15+rax*4+PNG_PREV_OFS], r8d
%endmacro

PROC png_deflate, 48
    mov  rsi, rcx
    mov  r14, rdx
    mov  PNG_PD_DST, r8
    mov  r15, r9
    mov  rdi, r15
    mov  eax, PNG_EMPTY
    mov  ecx, PNG_HSIZE
    rep  stosd
    mov  rdi, PNG_PD_DST
    xor  r12d, r12d
    xor  r13d, r13d
    mov  edx, 3 | (3 << 24)             ; BFINAL=1, BTYPE=01 (fixed Huffman)
    PNG_PUT
    xor  ebx, ebx
.main:
    cmp  rbx, r14
    jae  .end
    mov  r9, r14
    sub  r9, rbx
    cmp  r9, 3
    jb   .literal                       ; fewer than 3 bytes left: no match possible
    cmp  r9, 258
    jbe  .ml_ok
    mov  r9d, 258
.ml_ok:
    PNG_INSERT
    call .find                          ; r10 = best length, PNG_PD_DIST
.have:
    cmp  r10, 3
    jb   .literal
    ja   .lazy
    cmp  qword PNG_PD_DIST, PNG_TOOFAR
    ja   .literal
.lazy:
    ; one-step lazy matching: if the match starting one byte later is longer,
    ; emit a literal now and take that one instead.
    cmp  r10, PNG_LAZY_MAX
    jae  .match
    lea  rax, [rbx+1]
    mov  r9, r14
    sub  r9, rax
    cmp  r9, 3
    jb   .match
    cmp  r9, 258
    jbe  .lz_ok
    mov  r9d, 258
.lz_ok:
    mov  PNG_PD_CLEN, r10
    mov  rax, PNG_PD_DIST
    mov  PNG_PD_CDIST, rax
    inc  rbx
    PNG_INSERT
    mov  r10, PNG_PD_CLEN
    call .find_from
    cmp  r10, PNG_PD_CLEN
    jbe  .lz_keep
    movzx eax, byte [rsi+rbx-1]
    lea  rcx, [rel png_littab]
    mov  edx, [rcx+rax*4]
    PNG_PUT
    jmp  .have                          ; (r10 > 3 now; may defer once more)
.lz_keep:
    mov  r10, PNG_PD_CLEN
    mov  rax, PNG_PD_CDIST
    mov  PNG_PD_DIST, rax
    dec  rbx
    lea  r11, [rbx+2]                   ; pos and pos+1 are hashed already
    jmp  .emit
.match:
    lea  r11, [rbx+1]
.emit:
    lea  rax, [rel png_lentab]
    mov  edx, [rax+r10*4]
    PNG_PUT
    ; distance, v = dist-1
    mov  rax, PNG_PD_DIST
    dec  eax
    cmp  eax, 4
    jae  .dbig
    lea  rcx, [rel png_drev]
    movzx edx, byte [rcx+rax]
    or   edx, 5 << 24
    jmp  .dput
.dbig:
    bsr  ecx, eax
    dec  ecx
    mov  edx, eax
    shr  edx, cl
    and  edx, 1
    lea  edx, [rdx+rcx*2+2]             ; code = 2n + next bit
    lea  r8, [rel png_drev]
    movzx edx, byte [r8+rdx]
    mov  r8d, 1
    shl  r8d, cl
    dec  r8d
    and  eax, r8d
    shl  eax, 5
    or   edx, eax
    add  ecx, 5
    shl  ecx, 24
    or   edx, ecx
.dput:
    PNG_PUT
    lea  r9, [rbx+r10]
    mov  rbx, r11
.ins:
    cmp  rbx, r9
    jae  .main
    PNG_INSERT
    inc  rbx
    jmp  .ins
.literal:
    movzx eax, byte [rsi+rbx]
    lea  rcx, [rel png_littab]
    mov  edx, [rcx+rax*4]
    PNG_PUT
    inc  rbx
    jmp  .main
.end:
    lea  rcx, [rel png_littab]
    mov  edx, [rcx+256*4]               ; end of block
    PNG_PUT
.flush:
    test r13d, r13d
    jle  .flushed
    mov  [rdi], r12b
    inc  rdi
    shr  r12, 8
    sub  r13d, 8
    jmp  .flush
.flushed:
    mov  rax, rdi
    sub  rax, PNG_PD_DST
    jmp  .out

    ; chain walk for the match at rbx, max len r9. .find starts from r10 = 0, .find_from
    ; keeps the caller's r10 as the length to beat. sets PNG_PD_DIST.
    ; reached by call, so there's an extra return address: LOC() is off by 8, hence PDX_
%define PNG_PDX_DIST    [rsp+8+FRAME_OUT+8]
%define PNG_PDX_CHAIN   [rsp+8+FRAME_OUT+16]
.find:
    xor  r10d, r10d
.find_from:
    mov  dword PNG_PDX_CHAIN, PNG_MAXCHAIN
    lea  rdx, [rsi+rbx]
.chain:
    mov  rax, rbx
    sub  rax, r8                        ; distance (huge if r8 is "empty")
    cmp  rax, PNG_MAXDIST
    ja   .fret
    lea  rcx, [rsi+r8]
    movzx eax, byte [rcx+r10]           ; quick reject: byte that would extend best
    cmp  al, [rdx+r10]
    jne  .next
    xor  eax, eax
.cmp:
    mov  r11, [rcx+rax]
    xor  r11, [rdx+rax]
    jnz  .diff
    add  rax, 8
    cmp  rax, r9
    jb   .cmp
    jmp  .lenok
.diff:
    bsf  r11, r11
    shr  r11d, 3
    add  rax, r11
.lenok:
    cmp  rax, r9
    cmova rax, r9
    cmp  rax, r10
    jbe  .next
    mov  r10, rax
    mov  rax, rbx
    sub  rax, r8
    mov  PNG_PDX_DIST, rax
    cmp  r10, PNG_NICE
    jae  .fret
    cmp  r10, r9
    jae  .fret
.next:
    dec  dword PNG_PDX_CHAIN
    jz   .fret
    mov  eax, r8d
    and  eax, PNG_WMASK
    movsxd r8, dword [r15+rax*4+PNG_PREV_OFS]
    jmp  .chain
.fret:
    ret
.out:
ENDP

PROC png_free
    test rcx, rcx
    jz   .done
    mov  rbx, rcx
    call GetProcessHeap
    mov  rcx, rax
    xor  edx, edx
    mov  r8, rbx
    call HeapFree
.done:
ENDP

PROC png_alloc
    mov  rbx, rcx
    call GetProcessHeap
    mov  rcx, rax
    mov  edx, HEAP_ZERO_MEMORY
    mov  r8, rbx
    call HeapAlloc
ENDP

; 64 spare zero bytes at the end
PROC png_read_file, 32
    mov  r12, rdx
    xor  esi, esi
    mov  edx, GENERIC_READ
    mov  r8d, FILE_SHARE_READ | 2       ; share read+write (log may still be open)
    xor  r9d, r9d
    mov  qword [rsp+32], OPEN_EXISTING
    mov  qword [rsp+40], FILE_ATTRIBUTE_NORMAL
    mov  qword [rsp+48], 0
    call CreateFileA
    cmp  rax, INVALID_HANDLE_VALUE
    je   .done
    mov  rbx, rax
    mov  rcx, rbx
    lea  rdx, LOC(0)
    call GetFileSizeEx
    test eax, eax
    jz   .close
    mov  r13, LOC(0)
    cmp  r13, 0x7FFF0000                ; keep ReadFile sizes in a DWORD
    ja   .close
    lea  rcx, [r13+64]
    call png_alloc
    test rax, rax
    jz   .close
    mov  rsi, rax
    test r13, r13
    jz   .ok
    mov  rcx, rbx
    mov  rdx, rsi
    mov  r8d, r13d
    lea  r9, LOC(8)
    mov  qword [rsp+32], 0
    call ReadFile
    test eax, eax
    jz   .bad
    cmp  dword LOC(8), r13d
    je   .ok
.bad:
    mov  rcx, rsi
    call png_free
    xor  esi, esi
    jmp  .close
.ok:
    mov  [r12], r13
.close:
    mov  rcx, rbx
    call CloseHandle
.done:
    mov  rax, rsi
ENDP

PROC png_write_file, 16
    mov  rsi, rdx
    mov  r13, r8
    xor  r12d, r12d
    mov  edx, GENERIC_WRITE
    xor  r8d, r8d
    xor  r9d, r9d
    mov  qword [rsp+32], CREATE_ALWAYS
    mov  qword [rsp+40], FILE_ATTRIBUTE_NORMAL
    mov  qword [rsp+48], 0
    call CreateFileA
    cmp  rax, INVALID_HANDLE_VALUE
    je   .done
    mov  rbx, rax
    mov  rcx, rbx
    mov  rdx, rsi
    mov  r8d, r13d
    lea  r9, LOC(0)
    mov  qword [rsp+32], 0
    call WriteFile
    test eax, eax
    jz   .close
    cmp  dword LOC(0), r13d
    jne  .close
    mov  r12d, 1
.close:
    mov  rcx, rbx
    call CloseHandle
.done:
    mov  eax, r12d
ENDP

%define PNG_PC_FBUF     LOC(0)
%define PNG_PC_FSIZE    LOC(8)
%define PNG_PC_FILT     LOC(16)
%define PNG_PC_OUT      LOC(24)
%define PNG_PC_WORK     LOC(32)
%define PNG_PC_OUTPATH  LOC(40)
%define PNG_PC_RES      LOC(48)
%define PNG_PC_W        LOC(56)
%define PNG_PC_H        LOC(64)
%define PNG_PC_TOPDN    LOC(72)             ; qword 1 = top-down BMP
%define PNG_PC_BPP      LOC(80)             ; qword source bytes per pixel (3/4)
%define PNG_PC_STRIDE   LOC(88)
%define PNG_PC_PIX      LOC(96)
%define PNG_PC_N        LOC(104)
%define PNG_PC_FLEN     LOC(112)
%define PNG_PC_Y        LOC(120)
%define PNG_PC_CROW     LOC(128)            ; current RGB row (3 zero bytes before)
%define PNG_PC_PROW     LOC(136)
%define PNG_PC_TMP      LOC(144)            ; 5 candidate filtered rows
%define PNG_PC_TSTR     LOC(152)
%define PNG_PC_DST      LOC(160)
%define PNG_PC_BEST     LOC(168)
%define PNG_PC_BSUM     LOC(176)
%define PNG_PC_K        LOC(184)
%define PNG_PC_ZLEN     LOC(192)

PROC png_convert_bmp, 208
    mov  PNG_PC_OUTPATH, rdx
    xor  eax, eax
    mov  PNG_PC_FBUF, rax
    mov  PNG_PC_FILT, rax
    mov  PNG_PC_OUT, rax
    mov  PNG_PC_WORK, rax
    mov  PNG_PC_RES, rax
    mov  PNG_PC_FSIZE, rax
    mov  rbx, rcx
    call png_init_tables
    mov  rcx, rbx
    lea  rdx, PNG_PC_FSIZE
    call png_read_file
    test rax, rax
    jz   .done
    mov  PNG_PC_FBUF, rax
    mov  rsi, rax
    mov  rcx, PNG_PC_FSIZE
    cmp  rcx, 54
    jb   .fail
    cmp  word [rsi], 'BM'
    jne  .fail
    cmp  dword [rsi+14], 40             ; BITMAPINFOHEADER or newer
    jb   .fail
    mov  eax, [rsi+18]
    test eax, eax
    jle  .fail
    cmp  eax, 65535
    ja   .fail
    mov  PNG_PC_W, rax
    mov  eax, [rsi+22]                  ; height (negative = top-down)
    xor  ecx, ecx
    test eax, eax
    jz   .fail
    jg   .hpos
    neg  eax
    mov  ecx, 1
.hpos:
    cmp  eax, 65535
    ja   .fail
    mov  PNG_PC_H, rax
    mov  PNG_PC_TOPDN, rcx
    movzx eax, word [rsi+28]
    mov  ecx, [rsi+30]
    cmp  eax, 24
    jne  .b32
    test ecx, ecx
    jnz  .fail
    mov  qword PNG_PC_BPP, 3
    jmp  .bpp_ok
.b32:
    cmp  eax, 32
    jne  .fail
    cmp  ecx, 0
    je   .b32ok
    cmp  ecx, 3                         ; BI_BITFIELDS (assume B,G,R,X order)
    jne  .fail
.b32ok:
    mov  qword PNG_PC_BPP, 4
.bpp_ok:
    mov  rax, PNG_PC_W
    imul rax, PNG_PC_BPP
    add  rax, 3
    and  rax, -4
    mov  PNG_PC_STRIDE, rax
    imul rax, PNG_PC_H
    mov  ecx, [rsi+10]
    add  rax, rcx
    cmp  rax, PNG_PC_FSIZE
    ja   .fail
    add  rcx, rsi
    mov  PNG_PC_PIX, rcx
    mov  rax, PNG_PC_W
    lea  rax, [rax+rax*2]
    mov  PNG_PC_N, rax
    inc  rax
    imul rax, PNG_PC_H
    mov  PNG_PC_FLEN, rax
    lea  rcx, [rax+64]
    call png_alloc
    test rax, rax
    jz   .fail
    mov  PNG_PC_FILT, rax
    mov  rcx, PNG_PC_FLEN
    mov  rax, rcx
    shr  rax, 3
    lea  rcx, [rcx+rax+4096]
    call png_alloc
    test rax, rax
    jz   .fail
    mov  PNG_PC_OUT, rax
    mov  rax, PNG_PC_N
    add  rax, 64
    mov  PNG_PC_TSTR, rax
    imul rcx, rax, 7
    add  rcx, PNG_ROWS_OFS
    call png_alloc
    test rax, rax
    jz   .fail
    mov  PNG_PC_WORK, rax
    add  rax, PNG_ROWS_OFS+16           ; 16 zero bytes before each row
    mov  PNG_PC_CROW, rax
    add  rax, PNG_PC_TSTR
    mov  PNG_PC_PROW, rax                   ; stays zero for the first row
    add  rax, PNG_PC_TSTR
    mov  PNG_PC_TMP, rax
    ; PNG rows go top to bottom
    mov  rax, PNG_PC_FILT
    mov  PNG_PC_DST, rax
    mov  qword PNG_PC_Y, 0
.row:
    mov  rax, PNG_PC_Y
    cmp  rax, PNG_PC_H
    jae  .rows_done
    cmp  qword PNG_PC_TOPDN, 0
    jne  .srow
    mov  rcx, PNG_PC_H
    dec  rcx
    sub  rcx, rax
    mov  rax, rcx                       ; bottom-up: source row h-1-y
.srow:
    imul rax, PNG_PC_STRIDE
    mov  rsi, PNG_PC_PIX
    add  rsi, rax
    mov  rdi, PNG_PC_CROW
    mov  rcx, PNG_PC_W
    mov  r8, PNG_PC_BPP
.cv:                                    ; B,G,R(,X) -> R,G,B
    mov  al, [rsi+2]
    mov  [rdi], al
    mov  al, [rsi+1]
    mov  [rdi+1], al
    mov  al, [rsi]
    mov  [rdi+2], al
    add  rsi, r8
    add  rdi, 3
    dec  rcx
    jnz  .cv
    mov  qword PNG_PC_BSUM, -1
    mov  qword PNG_PC_BEST, 0
    mov  qword PNG_PC_K, 0
.flt:
    mov  rcx, PNG_PC_K
    mov  r9, PNG_PC_TSTR
    imul r9, rcx
    add  r9, PNG_PC_TMP
    mov  rdx, PNG_PC_CROW
    mov  r8, PNG_PC_PROW
    mov  rax, PNG_PC_N
    mov  [rsp+32], rax
    call png_filter_row
    cmp  rax, PNG_PC_BSUM
    jae  .flt_nx
    mov  PNG_PC_BSUM, rax
    mov  rax, PNG_PC_K
    mov  PNG_PC_BEST, rax
.flt_nx:
    inc  qword PNG_PC_K
    cmp  qword PNG_PC_K, 5
    jb   .flt
    mov  rdi, PNG_PC_DST
    mov  rax, PNG_PC_BEST
    mov  [rdi], al
    inc  rdi
    mov  rsi, PNG_PC_TSTR
    imul rsi, rax
    add  rsi, PNG_PC_TMP
    mov  rcx, PNG_PC_N
    rep  movsb
    mov  PNG_PC_DST, rdi
    mov  rax, PNG_PC_CROW
    mov  rcx, PNG_PC_PROW
    mov  PNG_PC_CROW, rcx
    mov  PNG_PC_PROW, rax
    inc  qword PNG_PC_Y
    jmp  .row
.rows_done:
    mov  rdi, PNG_PC_OUT
    mov  rax, [rel png_sig]
    mov  [rdi], rax
    mov  dword [rdi+8], 0x0D000000      ; length 13 (big endian)
    mov  dword [rdi+12], 'IHDR'
    mov  eax, PNG_PC_W
    bswap eax
    mov  [rdi+16], eax
    mov  eax, PNG_PC_H
    bswap eax
    mov  [rdi+20], eax
    mov  byte [rdi+24], 8
    mov  byte [rdi+25], 2
    mov  byte [rdi+26], 0
    mov  byte [rdi+27], 0
    mov  byte [rdi+28], 0
    lea  rcx, [rdi+12]
    mov  edx, 17
    call png_crc32
    bswap eax
    mov  rdi, PNG_PC_OUT
    mov  [rdi+29], eax
    mov  dword [rdi+37], 'IDAT'
    mov  byte [rdi+41], 0x78            ; CM=8, 32K window
    mov  byte [rdi+42], 0x5E            ; FLEVEL=1, FCHECK (0x785E % 31 == 0)
    mov  rcx, PNG_PC_FILT
    mov  rdx, PNG_PC_FLEN
    lea  r8, [rdi+43]
    mov  r9, PNG_PC_WORK
    call png_deflate
    mov  PNG_PC_ZLEN, rax
    mov  rcx, PNG_PC_FILT
    mov  rdx, PNG_PC_FLEN
    call png_adler32
    bswap eax
    mov  rdi, PNG_PC_OUT
    mov  rcx, PNG_PC_ZLEN
    mov  [rdi+rcx+43], eax
    add  rcx, 6                         ; IDAT data = 2 + deflate + 4
    mov  PNG_PC_ZLEN, rcx
    mov  eax, ecx
    bswap eax
    mov  [rdi+33], eax
    lea  rcx, [rdi+37]
    mov  rdx, PNG_PC_ZLEN
    add  rdx, 4
    call png_crc32
    bswap eax
    mov  rdi, PNG_PC_OUT
    mov  rcx, PNG_PC_ZLEN
    lea  rdx, [rdi+rcx+41]
    mov  [rdx], eax
    mov  rax, [rel png_iend]
    mov  [rdx+4], rax
    mov  eax, [rel png_iend+8]
    mov  [rdx+12], eax
    lea  r8, [rcx+41+4+12]
    mov  rcx, PNG_PC_OUTPATH
    mov  rdx, rdi
    call png_write_file
    mov  PNG_PC_RES, rax
.fail:
    mov  rcx, PNG_PC_FBUF
    call png_free
    mov  rcx, PNG_PC_FILT
    call png_free
    mov  rcx, PNG_PC_OUT
    call png_free
    mov  rcx, PNG_PC_WORK
    call png_free
.done:
    mov  eax, PNG_PC_RES
ENDP

PROC png_puts, 16
    mov  rsi, rcx
    xor  r8d, r8d
.len:
    cmp  byte [rsi+r8], 0
    je   .got
    inc  r8
    jmp  .len
.got:
    test r8, r8
    jz   .done
    mov  rbx, r8
    mov  ecx, -11
    call GetStdHandle
    mov  rcx, rax
    mov  rdx, rsi
    mov  r8d, ebx
    lea  r9, LOC(0)
    mov  qword [rsp+32], 0
    call WriteFile
.done:
ENDP

PROC png_putu
    lea  rdi, [rel png_numbuf+31]
    mov  byte [rdi], 0
    mov  rax, rcx
    mov  ecx, 10
.dig:
    xor  edx, edx
    div  rcx
    add  dl, '0'
    dec  rdi
    mov  [rdi], dl
    test rax, rax
    jnz  .dig
    mov  rcx, rdi
    call png_puts
ENDP

PROC png_now_us, 16
    lea  rcx, LOC(0)
    call QueryPerformanceCounter
    lea  rcx, LOC(8)
    call QueryPerformanceFrequency
    mov  rax, LOC(0)
    mov  rcx, 1000000
    mul  rcx
    div  qword LOC(8)
ENDP

PROC png_one, 16
    mov  rsi, rcx
    mov  rdi, rdx
    call png_now_us
    mov  r12, rax
    mov  rcx, rsi
    mov  rdx, rdi
    call png_convert_bmp
    mov  ebx, eax
    call png_now_us
    sub  rax, r12
    mov  r12, rax
    mov  rcx, rsi
    call png_puts
    lea  rcx, [rel png_s_arrow]
    call png_puts
    mov  rcx, rdi
    call png_puts
    test ebx, ebx
    jz   .bad
    lea  rcx, [rel png_s_ok1]
    call png_puts
    mov  rcx, rdi
    lea  rdx, LOC(0)
    call png_read_file
    mov  rcx, rax
    call png_free
    mov  rcx, LOC(0)
    call png_putu
    lea  rcx, [rel png_s_ok2]
    call png_puts
    mov  rax, r12
    xor  edx, edx
    mov  ecx, 1000
    div  rcx
    mov  rcx, rax
    call png_putu
    lea  rcx, [rel png_s_ok3]
    call png_puts
    jmp  .done
.bad:
    lea  rcx, [rel png_s_fail]
    call png_puts
.done:
    mov  eax, ebx
ENDP

PROC png_main
    mov  r12, rcx
    mov  r13, rdx
    test r12, r12
    jz   .usage
    xor  r15d, r15d
    cmp  r12, 2
    jne  .each
    ; "<in> <out.png>" when the second argument ends in .png
    mov  rsi, [r13+8]
    xor  ecx, ecx
.l2:
    cmp  byte [rsi+rcx], 0
    je   .l2e
    inc  rcx
    jmp  .l2
.l2e:
    cmp  rcx, 4
    jb   .each
    mov  eax, [rsi+rcx-4]
    or   eax, 0x20202000                ; lower-case "png" (keeps the '.')
    cmp  eax, '.png'
    jne  .each
    mov  rcx, [r13]
    mov  rdx, rsi
    call png_one
    test eax, eax
    jnz  .ret
    mov  r15d, 1
    jmp  .ret
.each:
    xor  r14d, r14d
.next:
    cmp  r14, r12
    jae  .ret
    mov  rsi, [r13+r14*8]
    ; out = in with its extension replaced by .png
    lea  rdi, [rel png_outname]
    xor  ecx, ecx
    mov  r8, -1                         ; position of the last '.' after a separator
.cp:
    mov  al, [rsi+rcx]
    cmp  rcx, 1000
    jae  .cpe
    mov  [rdi+rcx], al
    test al, al
    jz   .cpe
    cmp  al, '.'
    jne  .cp_sep
    mov  r8, rcx
.cp_sep:
    cmp  al, '\'
    je   .cp_reset
    cmp  al, '/'
    jne  .cp_nx
.cp_reset:
    mov  r8, -1
.cp_nx:
    inc  rcx
    jmp  .cp
.cpe:
    cmp  r8, -1
    je   .noext
    mov  rcx, r8
.noext:
    mov  eax, [rel png_s_dotpng]
    mov  [rdi+rcx], eax
    mov  byte [rdi+rcx+4], 0
    mov  rcx, rsi
    mov  rdx, rdi
    call png_one
    test eax, eax
    jnz  .ok
    mov  r15d, 1
.ok:
    inc  r14
    jmp  .next
.usage:
    lea  rcx, [rel png_s_usage]
    call png_puts
    mov  r15d, 2
.ret:
    mov  eax, r15d
ENDP
