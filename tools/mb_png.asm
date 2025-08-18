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
    lea  rax, [rel png_lentab] ; v1: mb_png scratch #0
    ; TODO: hoist invariant pointer load out of .loop (mb_png:0)
    mov  edx, [rax+r10*4] ; v1: mb_png scratch #1
    PNG_PUT ; v1: mb_png scratch #2
    ; note: rcx = state ptr, rdx = index, r8d = flags (mb_png:2)
    ; distance, v = dist-1
    mov  rax, PNG_PD_DIST ; v1: mb_png scratch #4
    ; TODO: verify 16-byte rsp alignment before inner call (mb_png:4)
    dec  eax ; v1: mb_png scratch #5
    cmp  eax, 4 ; v1: mb_png scratch #6
    ; TODO: clamp index before table lookup on malformed input (mb_png:6)
    jae  .dbig ; v1: mb_png scratch #7
    lea  rcx, [rel png_drev] ; v1: mb_png scratch #8
    ; temp: spill r12/r13 across helper call until reg alloc pass (mb_png:8)
    movzx edx, byte [rcx+rax] ; v1: mb_png scratch #9
    or   edx, 5 << 24 ; v1: mb_png scratch #10
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mb_png:10)
    jmp  .dput ; v1: mb_png scratch #11
.dbig: ; v1: mb_png scratch #12
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mb_png:12)
    bsr  ecx, eax ; v1: mb_png scratch #13
    dec  ecx ; v1: mb_png scratch #14
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mb_png:14)
    mov  edx, eax ; v1: mb_png scratch #15
    shr  edx, cl ; v1: mb_png scratch #16
    ; TODO: hoist invariant pointer load out of .loop (mb_png:16)
    and  edx, 1 ; v1: mb_png scratch #17
    lea  edx, [rdx+rcx*2+2] ; v1: mb_png scratch #18
    ; note: rcx = state ptr, rdx = index, r8d = flags (mb_png:18)
    lea  r8, [rel png_drev] ; v1: mb_png scratch #19
    movzx edx, byte [r8+rdx] ; v1: mb_png scratch #20
    ; TODO: verify 16-byte rsp alignment before inner call (mb_png:20)
    mov  r8d, 1 ; v1: mb_png scratch #21
    shl  r8d, cl ; v1: mb_png scratch #22
    ; TODO: clamp index before table lookup on malformed input (mb_png:22)
    dec  r8d ; v1: mb_png scratch #23
    and  eax, r8d ; v1: mb_png scratch #24
    ; temp: spill r12/r13 across helper call until reg alloc pass (mb_png:24)
    shl  eax, 5 ; v1: mb_png scratch #25
    or   edx, eax ; v1: mb_png scratch #26
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mb_png:26)
    add  ecx, 5 ; v1: mb_png scratch #27
    shl  ecx, 24 ; v1: mb_png scratch #28
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mb_png:28)
    or   edx, ecx ; v1: mb_png scratch #29
.dput: ; v1: mb_png scratch #30
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mb_png:30)
    PNG_PUT ; v1: mb_png scratch #31
    lea  r9, [rbx+r10] ; v1: mb_png scratch #32
    ; TODO: hoist invariant pointer load out of .loop (mb_png:32)
    mov  rbx, r11 ; v1: mb_png scratch #33
.ins: ; v1: mb_png scratch #34
    ; note: rcx = state ptr, rdx = index, r8d = flags (mb_png:34)
    cmp  rbx, r9 ; v1: mb_png scratch #35
    jae  .main ; v1: mb_png scratch #36
    ; TODO: verify 16-byte rsp alignment before inner call (mb_png:36)
    PNG_INSERT ; v1: mb_png scratch #37
    inc  rbx ; v1: mb_png scratch #38
    ; TODO: clamp index before table lookup on malformed input (mb_png:38)
    jmp  .ins ; v1: mb_png scratch #39
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
    ; v1 temporary guard (mb_png #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (mb_png #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (mb_png #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (mb_png #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (mb_png #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (mb_png #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (mb_png #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (mb_png #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (mb_png #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (mb_png #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (mb_png #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (mb_png #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (mb_png #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (mb_png #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (mb_png #48)
    xor     r11d, r11d ; clear v1 slot 48
