; font.asm through the GL-free font_build_cpu: texel values, glyph coverage and
; the advance width rule. glyph c is the 8x8 cell (c & 15, c >> 4).
; @link src/font.asm tests/art/artlib.asm
; @timeout 60



%include "common.inc"
%include "testlib.inc"
%include "../art/art.inc"



section .bss
alignb 16
f_px        resd 128*128



section .text



; font_lit(ecx c, edx x, r8d y) -> eax 1 if lit
; only 0xFFFFFFFF counts, glyph texels are never partially lit
font_lit:
    mov     eax, ecx
    shr     eax, 4
    shl     eax, 3
    add     eax, r8d
    shl     eax, 7
    mov     r9d, ecx
    and     r9d, 15
    shl     r9d, 3
    add     eax, r9d
    add     eax, edx
    lea     r9, [rel f_px]
    cmp     dword [r9+rax*4], 0xFFFFFFFF
    sete    al
    movzx   eax, al
    ret


; glyph_cols(ecx c) -> eax, bit x set if column x has anything lit
PROC glyph_cols
    mov     r12d, ecx
    xor     r13d, r13d
    xor     ebx, ebx
.x: xor     esi, esi
.y: mov     ecx, r12d
    mov     edx, ebx
    mov     r8d, esi
    call    font_lit
    test    eax, eax
    jz      .n
    bts     r13d, ebx
.n: inc     esi
    cmp     esi, 8
    jb      .y
    inc     ebx
    cmp     ebx, 8
    jb      .x
    mov     eax, r13d
ENDP


PROC test_main
    lea     rcx, [rel f_px]
    call    font_build_cpu


    ; transparent texels must stay white too, or filtering gives a dark fringe
    TEST "font texel values"
    lea     rsi, [rel f_px]
    xor     ebx, ebx
    xor     edi, edi
.val:
    mov     eax, [rsi+rbx*4]
    cmp     eax, 0xFFFFFFFF
    je      .val_ok
    cmp     eax, 0x00FFFFFF
    je      .val_ok
    inc     edi
.val_ok:
    inc     ebx
    cmp     ebx, 128*128
    jb      .val
    CHECK_EQ32 edi, 0, "every texel is 0xFFFFFFFF or 0x00FFFFFF"

    ; 33..126, space excluded
    TEST "printable glyphs have pixels"
    mov     ebx, 33
.prn:
    mov     ecx, ebx
    call    glyph_cols
    mov     r12d, eax
    CHECK_TRUE r12d, "printable glyph has at least one lit texel"
    DETAIL_IFZ r12d, "char", ebx
    inc     ebx
    cmp     ebx, 127
    jb      .prn


    TEST "g_font_widths rule"
    xor     ebx, ebx
.wid:
    mov     ecx, ebx
    call    glyph_cols
    mov     r12d, 4
    test    eax, eax
    jz      .wexp
    bsr     ecx, eax
    lea     r12d, [rcx+2]
    cmp     r12d, 8
    jbe     .wexp
    mov     r12d, 8
.wexp:
    lea     rax, [rel g_font_widths]
    movzx   r13d, byte [rax+rbx]
    CHECK_EQ32 r13d, r12d, "width = min(rightmost lit column + 2, 8), 4 when empty"
    DETAIL_IFZ eax, "char", ebx
    lea     eax, [r13-1]
    xor     r14d, r14d
    cmp     eax, 8
    setb    r14b                        ; 1 <= w <= 8, unsigned trick
    CHECK_TRUE r14d, "1 <= width <= 8"
    DETAIL_IFZ r14d, "char", ebx
    inc     ebx
    cmp     ebx, 128
    jb      .wid

    TEST "width spot checks"
    lea     rbx, [rel g_font_widths]
    movzx   eax, byte [rbx+32]
    CHECK_EQ32 eax, 4, "space advances 4"
    movzx   eax, byte [rbx+'i']
    CHECK_EQ32 eax, 2, "'i' is 2 wide"
    movzx   eax, byte [rbx+'A']
    CHECK_EQ32 eax, 6, "'A' is 6 wide"

    ; only 8 glyph rows, y >= 64 is unused
    TEST "unused rows empty"
    lea     rsi, [rel f_px]
    mov     ebx, 64*128
    xor     edi, edi
.low:
    cmp     dword [rsi+rbx*4], 0x00FFFFFF
    je      .low_ok
    inc     edi
.low_ok:
    inc     ebx
    cmp     ebx, 128*128
    jb      .low
    CHECK_EQ32 edi, 0, "texels with y >= 64 are transparent white"
ENDP
