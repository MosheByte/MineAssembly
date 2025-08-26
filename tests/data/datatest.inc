; datatest.inc - shared externs + check macros for the data tests. include after
; common.inc/testlib.inc as "../tests/data/datatest.inc" (resolves via -I include\)
; macros only trash volatiles (rax rcx rdx r8-r11, xmm0-5), keep loop counters in nonvolatiles
%ifndef DATATEST_INC
%define DATATEST_INC

; global in blocks/items but not in api.inc
extern blocks_defined
extern items_shaped             ; 16 B each: w, h, result, count, cells[w*h]
extern items_shapeless          ; 16 B each: n, result, count, 0, ing[n]
extern items_tag_members

; datahelp.asm
extern dh_valid_id
extern dh_streq
extern dh_ends_with
extern dh_contains_ci           ; needle must already be lowercase
extern dh_check
extern dh_detail_id
extern dh_is_tag
extern dh_tag_pick
extern dh_place
extern dh_subst
extern dh_concretize
extern dh_expect_craft
extern dh_expect_all            ; returns failure count, not ok
extern dh_fmt_grid

; pattern = db h, w, cells[h*w]. note h first, table records are w first
%define PAT_MAX         11

%define TAG_COBBLE      0x7D
%define TAG_PLANKS      0x7E
%define TAG_LOG         0x7F

; CK got, want, id, "msg". both sign-extended. got can't be edx/r10d, want can't
; be eax/r10d. id -1 = no "at id" line
%macro CK 4.nolist
    section .rdata
    %%m: db %4, 0
    %%f: db __?FILE?__, 0
    section .text
    mov    eax, %1
    mov    edx, %2
    mov    r10, %3
    movsxd rcx, eax
    movsxd rdx, edx
    lea    r8, [rel %%m]
    lea    r9, [rel %%f]
    mov    qword [rsp+32], __?LINE?__
    mov    [rsp+40], r10
    call   dh_check
%endmacro

%macro CKT 3.nolist
    mov    eax, %1
    test   eax, eax
    setnz  al
    movzx  eax, al
    CK     eax, 1, %2, %3
%endmacro

%macro CKF 3.nolist
    mov    eax, %1
    test   eax, eax
    setz   al
    movzx  eax, al
    CK     eax, 1, %2, %3
%endmacro

; dst, table, index (reg64 or imm)
%macro LDB 3.nolist
    lea    r11, [rel %2]
    movzx  %1, byte [r11+%3]
%endmacro
%macro LDW 3.nolist
    lea    r11, [rel %2]
    movzx  %1, word [r11+(%3)*2]
%endmacro
%macro LDD 3.nolist
    lea    r11, [rel %2]
    mov    %1, [r11+(%3)*4]
%endmacro
%macro LDQ 3.nolist
    lea    r11, [rel %2]
    mov    %1, [r11+(%3)*8]
%endmacro
%macro LDF 3.nolist
    lea    r11, [rel %2]
    movss  %1, [r11+(%3)*4]
%endmacro

; index doubles as the id in the failure line
%macro BEQ 4.nolist
    LDB    eax, %1, %2
    CK     eax, %3, %2, %4
%endmacro
%macro WEQ 4.nolist
    LDW    eax, %1, %2
    CK     eax, %3, %2, %4
%endmacro

%macro HAS 3.nolist
    LDW    eax, blk_flags, %1
    and    eax, %2
    cmp    eax, %2
    sete   al
    movzx  eax, al
    CK     eax, 1, %1, %3
%endmacro
%macro LACKS 3.nolist
    LDW    eax, blk_flags, %1
    test   eax, %2
    setz   al
    movzx  eax, al
    CK     eax, 1, %1, %3
%endmacro

%macro NAMEQ 3.nolist
    LDQ    rcx, item_name, %1
    CHECK_STR rcx, %2, %3
%endmacro

%macro GRID 10.nolist
    %1: db %2, %3, %4, %5, %6, %7, %8, %9, %10
%endmacro

%endif
