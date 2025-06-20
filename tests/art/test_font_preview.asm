; font previews into the test's working dir, both 4x: font.bmp is the glyph
; sheet over the UI grey, font_text.bmp some lines with the real advances
; @link src/font.asm tests/art/artlib.asm
; @preview
; @timeout 60



%include "common.inc"
%include "testlib.inc"
%include "../art/art.inc"


%define BG_COL      ART_RGB(40,44,52)
%define NLINES      4
%define SCALE       4


section .rdata
line0   db "MineAssembly - 100% x86-64 assembly!", 0
line1   db "The quick brown fox jumps over", 0
line2   db "the lazy dog. 0123456789 (){}[]<>", 0
line3   db 1," ",2," ",3," ",4," ",5," ",6," ",7," ",8," @#$%^&*_+=~?/|\", 0
align 8
lines   dq line0, line1, line2, line3
p_font  db "font.bmp", 0
p_text  db "font_text.bmp", 0


section .bss
alignb 16
f_px        resd 128*128
f_sheet     resd 128*64
f_big       resd 512*256
s_textw     resd 1
s_text      resq 1
s_textbig   resq 1


section .text


; line_width(rcx zstr) -> eax sum of advances
line_width:
    xor     eax, eax
    lea     r8, [rel g_font_widths]
.l: movzx   edx, byte [rcx]
    test    edx, edx
    jz      .d
    and     edx, 127
    movzx   edx, byte [r8+rdx]
    add     eax, edx
    inc     rcx
    jmp     .l
.d: ret


PROC test_main
    lea     rcx, [rel f_px]
    call    font_build_cpu


    ; only rows 0..63 have glyphs
    TEST "font sheet preview"
    lea     rcx, [rel f_sheet]
    mov     edx, 128*64
    mov     r8d, BG_COL
    call    art_fill
    lea     rcx, [rel f_sheet]
    lea     rdx, [rel f_px]
    mov     r8d, 128*64
    call    art_over
    lea     rcx, [rel f_sheet]
    mov     edx, 128
    mov     r8d, 64
    mov     r9d, SCALE
    lea     rax, [rel f_big]
    mov     [rsp+32], rax
    call    art_scale
    lea     rcx, [rel p_font]
    lea     rdx, [rel f_big]
    mov     r8d, 128*SCALE
    mov     r9d, 64*SCALE
    call    t_write_bmp
    CHECK_EQ32 eax, 1, "font.bmp written"


    TEST "font sentence preview"
    xor     r12d, r12d                  ; widest line
    xor     ebx, ebx
.mw:
    lea     rax, [rel lines]
    mov     rcx, [rax+rbx*8]
    call    line_width
    cmp     eax, r12d
    cmovg   r12d, eax
    inc     ebx
    cmp     ebx, NLINES
    jb      .mw
    add     r12d, 4                     ; 2 px margin each side
    mov     [rel s_textw], r12d
    CHECK_RANGE r12d, 40, 400, "sentence width is sane"
    mov     r13d, NLINES*10 + 2         ; 10 px per line
    mov     ecx, r12d
    imul    ecx, r13d
    shl     ecx, 2
    call    t_alloc
    mov     [rel s_text], rax
    mov     rcx, rax
    mov     edx, r12d
    imul    edx, r13d
    mov     r8d, BG_COL
    call    art_fill


    xor     r14d, r14d
.line:
    lea     rax, [rel lines]
    mov     rsi, [rax+r14*8]
    mov     r15d, 2                     ; x
.ch:
    movzx   ebx, byte [rsi]
    test    ebx, ebx
    jz      .line_end
    and     ebx, 127
    ; dst (2 + line*10) * W + x
    imul    eax, r14d, 10
    add     eax, 2
    imul    eax, r12d
    add     eax, r15d
    mov     rcx, [rel s_text]
    lea     rcx, [rcx+rax*4]
    mov     eax, ebx
    shr     eax, 4
    shl     eax, 3+7
    mov     edx, ebx
    and     edx, 15
    lea     eax, [rax+rdx*8]
    lea     r8, [rel f_px]
    lea     r8, [r8+rax*4]
    ; art_rect doesn't clip, the last glyph can poke past the right edge
    mov     eax, r12d
    sub     eax, r15d
    cmp     eax, 8
    jbe     .clip
    mov     eax, 8
.clip:
    mov     [rsp+32], rax
    mov     qword [rsp+40], 8
    mov     qword [rsp+48], 1           ; over
    mov     edx, r12d
    mov     r9d, 128
    call    art_rect
    lea     rax, [rel g_font_widths]
    movzx   eax, byte [rax+rbx]
    add     r15d, eax
    inc     rsi
    jmp     .ch
.line_end:
    lea     eax, [r12-2]
    xor     ecx, ecx
    cmp     r15d, eax
    setbe   cl
    mov     edi, ecx
    CHECK_TRUE edi, "line fits inside the margin"
    inc     r14d
    cmp     r14d, NLINES
    jb      .line

    mov     ecx, r12d
    imul    ecx, r13d
    imul    ecx, ecx, SCALE*SCALE*4
    call    t_alloc
    mov     [rel s_textbig], rax
    mov     rcx, [rel s_text]
    mov     edx, r12d
    mov     r8d, r13d
    mov     r9d, SCALE
    mov     [rsp+32], rax
    call    art_scale
    lea     rcx, [rel p_text]
    mov     rdx, [rel s_textbig]
    mov     r8d, r12d
    imul    r8d, r8d, SCALE
    mov     r9d, r13d
    imul    r9d, r9d, SCALE
    call    t_write_bmp
    CHECK_EQ32 eax, 1, "font_text.bmp written"
ENDP
