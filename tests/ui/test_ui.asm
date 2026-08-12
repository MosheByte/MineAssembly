; ui/hud/menus/console pure logic, nothing touches GL. the rest of api.inc is
; auto-stubbed, so font widths are all 0 and ui_char_width falls back to 6 px (space 4).
; @link src/ui.asm src/hud.asm src/menus.asm src/console.asm src/util.asm
; @link src/items.asm src/blocks.asm tests/ui/uihelp.asm tests/ui/ui_stubs.asm tests/ui/ui_stubs_gl.asm
; @timeout 60
%include "common.inc"
%include "testlib.inc"

extern uh_chat_line, uh_last_chat, uh_strip, uh_width, uh_contains, uh_starts
extern uh_streq, uh_strcpy, uh_strlen, uh_exe, uh_type, uh_chatbuf
extern ui_argb_gl, ui_col_scale, ui_itoa, ui_hexval, ui_fmt_is_int, ui_text_width
extern ui_mouse_in, con_parse_int, con_parse_float, con_insert
extern con_lines, con_head, con_total, con_input
extern chat_add, console_execute, console_open, console_on_key
extern menu_name, menu_folder, menu_seed, menu_update_folder, menu_compute_seed
extern str_hash, hud_screenshot_req

%define P_X         PLAYER.x
%define P_Y         PLAYER.y
%define P_Z         PLAYER.z
%define P_FLYING    PLAYER.flying
%define P_HEALTH    PLAYER.health
%define P_HUNGER    PLAYER.hunger
%define P_SAT       PLAYER.saturation
%define S_RD        SETTINGS.render_dist
%define S_FOV       SETTINGS.fov

%define VK_RETURN   0x0D
%define VK_UP       0x26
%define VK_DOWN     0x28
%define VK_HOME     0x24
%define VK_DELETE   0x2E
%define VK_TAB      0x09

; STRP reg, "text" -> reg = ptr to the literal
%macro STRP 2
    section .rdata
    %%s: db %2, 0
    section .text
    lea  %1, [rel %%s]
%endmacro

%macro EXE 1
    STRP rcx, %1
    call uh_exe
%endmacro

; check needle is in the last n chat lines, dump the chat on failure
%macro CHAT_HAS 3
    mov  ecx, %1
    call uh_last_chat
    mov  rcx, rax
    STRP rdx, %2
    call uh_contains
    mov  ebx, eax
    CHECK_TRUE ebx, %3
    test ebx, ebx
    jnz  %%ok
    lea  rcx, [rel uh_chatbuf]
    call t_fail_detail
%%ok:
%endmacro

%macro CHAT_STARTS 3
    mov  ecx, %1
    call uh_last_chat
    mov  rcx, rax
    STRP rdx, %2
    call uh_starts
    mov  ebx, eax
    CHECK_TRUE ebx, %3
    test ebx, ebx
    jnz  %%ok
    lea  rcx, [rel uh_chatbuf]
    call t_fail_detail
%%ok:
%endmacro

; acc = 0 unless mem holds exactly that float
%macro FEQ_AND 3
    mov  eax, %2
    cmp  eax, __?float32?__(%3)
    je   %%ok
    xor  %1, %1
%%ok:
%endmacro

%macro ITOA_CHK 2
    lea  rdx, LOC(0)
    mov  qword [rdx], 0
    mov  qword [rdx+8], 0
    mov  qword [rdx+16], 0
    mov  ecx, %1
    call ui_itoa
    lea  rbx, LOC(0)
    CHECK_STR rbx, %2, "itoa"
%endmacro

; PINT "text", ok, value
%macro PINT 3
    mov  qword LOC(32), 0x5A5A
    STRP rcx, %1
    lea  rdx, LOC(32)
    call con_parse_int
    xor  ebx, ebx
    cmp  eax, %2
    jne  %%bad
%if %2
    mov  rax, LOC(32)
    cmp  rax, %3
    jne  %%bad
%endif
    mov  ebx, 1
%%bad:
    CHECK_TRUE ebx, {"parse_int '", %1, "'"}
%endmacro

; PFLT "text", ok, value  (within 1e-6)
%macro PFLT 3
    STRP rcx, %1
    call con_parse_float
    xor  ebx, ebx
    cmp  eax, %2
    jne  %%bad
%if %2
    mov  eax, __?float32?__(%3)
    movd xmm1, eax
    subss xmm0, xmm1
    mov  eax, 0x7FFFFFFF
    movd xmm1, eax
    andps xmm0, xmm1
    mov  eax, __?float32?__(1.0e-6)
    movd xmm1, eax
    comiss xmm0, xmm1
    jae  %%bad
%endif
    mov  ebx, 1
%%bad:
    CHECK_TRUE ebx, {"parse_float '", %1, "'"}
%endmacro

%macro INPUT_IS 2
    lea  rbx, [rel con_input]
    CHECK_STR rbx, %1, %2
%endmacro

; FOLDER name_label, "expected sanitized name"
%macro FOLDER 2
    lea  rcx, [rel menu_name]
    lea  rdx, [rel %1]
    call uh_strcpy
    call menu_update_folder
    lea  rbx, [rel menu_folder]
    CHECK_STR rbx, %2, "folder name"
%endmacro

%macro SEED 1
    lea  rcx, [rel menu_seed]
    STRP rdx, %1
    call uh_strcpy
%endmacro

section .rdata
fn_new:     db "New World", 0
fn_colon:   db "  My:World?. ", 0
fn_empty:   db 0
fn_dots:    db "...", 0
fn_slash:   db "a/b\c", 0
fn_long:    times 30 db 'x'
            db 0
; "\fe" + "word00 ... word39", yellow
long_msg:   db 12, 'e'
%assign i 0
%rep 40
%if i > 0
            db ' '
%endif
            db 'w','o','r','d', '0' + i / 10, '0' + i % 10
%assign i i+1
%endrep
            db 0
long_plain: equ long_msg + 2
hard_msg:   times 400 db 'x'
            db 0
two_lines:  db "line one", 10, "line two", 0
s_line1:    db "line one", 0
s_line2:    db "line two", 0
s_msg:      db "msg ", 0
s_hello:    db "hello world", 0
s_fnv_a:    db "  (text seed ", 0
s_fnv_b:    db ", FNV-1a ", 0
s_fnv_c:    db ")", 13, 10, 0

section .text

PROC test_main, 128
    TEST "ui helpers"
    mov  ecx, 0xFF112233
    call ui_argb_gl
    CHECK_EQ32 eax, 0xFF332211, "argb->gl swaps R/B"
    mov  ecx, 0x00112233
    call ui_argb_gl
    CHECK_EQ32 eax, 0xFF332211, "alpha 0 promoted to opaque"
    mov  ecx, 0x80FF0000
    call ui_argb_gl
    CHECK_EQ32 eax, 0x800000FF, "alpha kept"
    mov  ecx, 0xFF808080
    mov  edx, 128
    call ui_col_scale
    CHECK_EQ32 eax, 0xFF404040, "col_scale halves"
    mov  ecx, 0x7FFFFFFF
    mov  edx, 256
    call ui_col_scale
    CHECK_EQ32 eax, 0x7FFFFFFF, "col_scale identity keeps alpha"
    ITOA_CHK 0, "0"
    ITOA_CHK 7, "7"
    ITOA_CHK 64, "64"
    ITOA_CHK -12, "-12"
    ITOA_CHK 123456, "123456"
    ITOA_CHK -2147483647, "-2147483647"
    mov  ecx, 'a'
    call ui_hexval
    mov  ebx, eax
    mov  ecx, 'F'
    call ui_hexval
    xor  esi, esi
    cmp  ebx, 10
    jne  .hx
    cmp  eax, 15
    jne  .hx
    mov  esi, 1
.hx:
    CHECK_TRUE esi, "hexval letters"
    mov  ecx, '7'
    call ui_hexval
    CHECK_EQ32 eax, 7, "hexval digit"
    mov  ecx, 'r'
    call ui_hexval
    CHECK_EQ32 eax, 16, "hexval reset"
    mov  ecx, 'z'
    call ui_hexval
    CHECK_EQ32 eax, -1, "hexval invalid"
    STRP rcx, "Render Distance: %d chunks"
    call ui_fmt_is_int
    CHECK_EQ32 eax, 1, "fmt %d is int"
    STRP rcx, "Music: %d%%"
    call ui_fmt_is_int
    CHECK_EQ32 eax, 1, "fmt %d%% is int"
    STRP rcx, "Value %.2f"
    call ui_fmt_is_int
    CHECK_EQ32 eax, 0, "fmt %.2f is float"
    STRP rcx, "100%% %5d"
    call ui_fmt_is_int
    CHECK_EQ32 eax, 1, "fmt width int"
    ; monospace fallback
    STRP rcx, "abc"
    call ui_text_width
    CHECK_EQ32 eax, 18, "width abc"
    STRP rcx, {12, "cab", 12, "r c"}
    call ui_text_width
    CHECK_EQ32 eax, 6*3+4, "colour codes are zero width"
    STRP rcx, {"ab", 10, "abcd"}
    call ui_text_width
    CHECK_EQ32 eax, 24, "multi-line width = widest line"
    ; real proportional widths, zeroed again afterwards so the rest stays on the fallback
    lea  rdi, [rel g_font_widths]
    mov  al, 6
    mov  ecx, 128
    rep  stosb
    lea  rdi, [rel g_font_widths]
    mov  byte [rdi+'i'], 2
    mov  byte [rdi+' '], 4
    STRP rcx, "iii i"
    call ui_text_width
    CHECK_EQ32 eax, 2*4+4, "proportional widths"
    lea  rdi, [rel g_font_widths]
    xor  eax, eax
    mov  ecx, 128
    rep  stosb
    mov  dword [rel g_ui_mx], 15
    mov  dword [rel g_ui_my], 25
    mov  ecx, 10
    mov  edx, 20
    mov  r8d, 10
    mov  r9d, 10
    call ui_mouse_in
    CHECK_EQ32 eax, 1, "mouse inside"
    mov  ecx, 16
    mov  edx, 20
    mov  r8d, 10
    mov  r9d, 10
    call ui_mouse_in
    CHECK_EQ32 eax, 0, "mouse left of rect"
    mov  ecx, 10
    mov  edx, 20
    mov  r8d, 5
    mov  r9d, 10
    call ui_mouse_in
    CHECK_EQ32 eax, 0, "right edge exclusive"

    TEST "console number parsing"
    PINT "42", 1, 42
    PINT "-17", 1, -17
    PINT "+5", 1, 5
    PINT "", 0, 0
    PINT "4x", 0, 0
    PINT "-", 0, 0
    PINT "007", 1, 7
    PFLT "1.5", 1, 1.5
    PFLT "-0.25", 1, -0.25
    PFLT ".5", 1, 0.5
    PFLT "12", 1, 12.0
    PFLT "1.", 1, 1.0
    PFLT "abc", 0, 0
    PFLT "1.2.3", 0, 0
    PFLT "", 0, 0

    TEST "console commands"
    EXE "/time set noon"
    xor  ebx, ebx
    cmp  eax, 1
    jne  .t1
    cmp  dword [rel g_time_of_day], 6000
    jne  .t1
    mov  ebx, 1
.t1:
    CHECK_TRUE ebx, "time set noon"
    EXE "/time set 30000"
    CHECK_EQ32 [rel g_time_of_day], 6000, "time set wraps modulo 24000"
    EXE "/time add -7000"
    CHECK_EQ32 [rel g_time_of_day], 23000, "time add negative wraps"
    EXE "/TIME SET Midnight"
    CHECK_EQ32 [rel g_time_of_day], 18000, "case-insensitive command + keyword"
    EXE "/time set banana"
    CHAT_HAS 4, "Usage: /time", "time usage on bad value"

    EXE "/tp 1.5 70 -3.25"
    mov  ebx, 1
    FEQ_AND ebx, [rel g_player+P_X], 1.5
    FEQ_AND ebx, [rel g_player+P_Y], 70.0
    FEQ_AND ebx, [rel g_player+P_Z], -3.25
    CHECK_TRUE ebx, "tp absolute"
    CHAT_HAS 4, "Teleported to 1.50, 70.00, -3.25", "tp message"
    EXE "tp ~1 ~ ~-0.75"                ; leading slash optional
    mov  ebx, 1
    FEQ_AND ebx, [rel g_player+P_X], 2.5
    FEQ_AND ebx, [rel g_player+P_Y], 70.0
    FEQ_AND ebx, [rel g_player+P_Z], -4.0
    CHECK_TRUE ebx, "tp relative"
    EXE "/tp a b c"
    mov  ecx, 4
    call uh_last_chat
    mov  rcx, rax
    STRP rdx, "Usage: /tp"
    call uh_contains
    mov  ebx, eax
    FEQ_AND ebx, [rel g_player+P_X], 2.5
    CHECK_TRUE ebx, "tp rejects garbage"
    EXE "/tp 1 2"
    CHAT_HAS 4, "Usage: /tp", "tp needs 3 coordinates"

    EXE "/gamemode c"
    CHECK_EQ32 [rel g_gamemode], 1, "gamemode c"
    mov  dword [rel g_player+P_FLYING], 1
    EXE "/GM survival"
    xor  ebx, ebx
    mov  eax, [rel g_gamemode]
    or   eax, [rel g_player+P_FLYING]
    setz bl
    CHECK_TRUE ebx, "gm survival stops flying"
    EXE "/gamemode 1"
    CHECK_EQ32 [rel g_gamemode], 1, "gamemode 1"
    EXE "/gamemode spectator"
    CHAT_HAS 4, "Usage: /gamemode", "gamemode usage"

    mov  dword [rel g_player+P_HEALTH], 3
    mov  dword [rel g_player+P_HUNGER], 2
    EXE "/heal"
    EXE "/feed"
    xor  ebx, ebx
    cmp  dword [rel g_player+P_HEALTH], 20
    jne  .hf
    cmp  dword [rel g_player+P_HUNGER], 20
    jne  .hf
    mov  ebx, 1
.hf:
    CHECK_TRUE ebx, "heal + feed"
    movss xmm6, [rel g_player+P_SAT]
    CHECK_NEAR xmm6, 5.0, 0.0, "feed sets saturation"

    EXE "/render 40"
    CHECK_EQ32 [rel g_settings+S_RD], 16, "render clamps to 16"
    EXE "/render 1"
    CHECK_EQ32 [rel g_settings+S_RD], 2, "render clamps to 2"
    EXE "/fov 90"
    movss xmm6, [rel g_settings+S_FOV]
    CHECK_NEAR xmm6, 90.0, 0.0, "fov"

    mov  dword [rel g_player+P_FLYING], 0
    EXE "/fly"
    CHECK_EQ32 [rel g_player+P_FLYING], 1, "fly on"
    EXE "/fly"
    CHECK_EQ32 [rel g_player+P_FLYING], 0, "fly off"

    mov  rax, -1234567890123
    mov  [rel g_seed], rax
    EXE "/seed"
    CHAT_HAS 4, "-1234567890123", "seed"

    mov  dword [rel hud_screenshot_req], 0
    EXE "/screenshot"
    CHECK_EQ32 [rel hud_screenshot_req], 1, "screenshot request flag"

    EXE "/definitelynotacommand 1 2"
    CHECK_EQ32 eax, 0, "unknown command returns 0"
    CHAT_HAS 4, "Unknown command: /definitelynotacommand", "unknown msg"

    EXE "/fill 0 0 0 100 100 100 stone"
    CHAT_HAS 4, "Too many blocks", "fill limit"
    EXE "/fill 0 0 0 1 1 1 notablock"
    CHAT_HAS 4, "Unknown block", "fill bad block"

    EXE "/help"
    CHAT_HAS 14, "commands (page 1 of", "help header"
    EXE "/help 99"
    CHAT_HAS 10, "(page 4 of 4)", "help clamps page"

    EXE "/give diamond 5"
    CHAT_HAS 4, "Gave 5 x", "give by name"
    EXE "/give iron ingot"
    CHAT_HAS 4, "Gave 1 x", "give multi-word"
    EXE "/give 129 3"
    CHAT_HAS 4, "Gave 3 x", "give by id"
    EXE "/give unobtainium"
    CHAT_HAS 4, "Unknown item 'unobtainium'", "give unknown"

    EXE "/spawn dragon"
    CHAT_HAS 5, "Unknown creature 'dragon'", "spawn unknown"

    TEST "chat log"
    EXE "/cls"
    CHECK_EQ32 [rel con_total], 0, "cls empties chat"
    lea  rcx, [rel long_msg]
    mov  edx, 0xFFFFFFFF
    call chat_add
    xor  ebx, ebx
    cmp  dword [rel con_total], 1
    setg bl
    CHECK_TRUE ebx, "long message wrapped into several lines"
    call all_fit_300
    CHECK_TRUE eax, "every wrapped line fits 300 px"
    mov  ebx, 1
    xor  esi, esi
.cc:
    cmp  esi, [rel con_total]
    jge  .cc_done
    mov  ecx, esi
    call uh_chat_line
    cmp  byte [rax], 12
    jne  .cc_bad
    cmp  byte [rax+1], 'e'
    je   .cc_next
.cc_bad:
    xor  ebx, ebx
.cc_next:
    inc  esi
    jmp  .cc
.cc_done:
    CHECK_TRUE ebx, "colour code carried to continuation lines"
    mov  ecx, 1000
    call uh_last_chat
    mov  rbx, rax
    lea  rdx, [rel long_plain]
    mov  rcx, rbx
    call uh_streq
    CHECK_TRUE eax, "wrapping loses no words"
    lea  rcx, [rel hard_msg]            ; no spaces, has to hard break
    mov  edx, 0xFFFFFFFF
    call chat_add
    call all_fit_300
    CHECK_TRUE eax, "hard wrap fits"
    lea  rcx, [rel two_lines]
    mov  edx, 0xFF00FF00
    call chat_add
    mov  ecx, [rel con_total]
    sub  ecx, 2
    call uh_chat_line
    mov  rcx, rax
    lea  rdx, [rel s_line1]
    call uh_streq
    mov  ebx, eax
    mov  ecx, [rel con_total]
    dec  ecx
    call uh_chat_line
    mov  rcx, rax
    lea  rdx, [rel s_line2]
    call uh_streq
    and  ebx, eax
    CHECK_TRUE ebx, "newline splits lines"
    xor  esi, esi
.ring:
    lea  rcx, LOC(0)
    lea  rdx, [rel s_msg]
    call uh_strcpy
    mov  ecx, esi
    lea  rdx, LOC(4)
    call ui_itoa
    lea  rcx, LOC(0)
    mov  edx, 0xFFFFFFFF
    call chat_add
    inc  esi
    cmp  esi, 150
    jl   .ring
    CHECK_EQ32 [rel con_total], 100, "ring keeps 100 lines"
    mov  ecx, 99
    call uh_chat_line
    mov  rcx, rax
    STRP rdx, "msg 149"
    call uh_streq
    mov  ebx, eax
    xor  ecx, ecx
    call uh_chat_line
    mov  rcx, rax
    STRP rdx, "msg 50"
    call uh_streq
    and  ebx, eax
    CHECK_TRUE ebx, "ring order"

