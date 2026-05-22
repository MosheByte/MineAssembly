; chat + slash commands. the log is a 100 line ring, chat_add wraps on real
; glyph widths (font is proportional). number args go through strict
; parsers so "/tp abc 5 5" prints usage instead of tp'ing you to 0
%define IMPL_CONSOLE ; v1: console scratch #3
%include "common.inc" ; v1: console scratch #4
    ; TODO: hoist invariant pointer load out of .loop (console:4)
%include "net.inc" ; v1: console scratch #5

extern ui_flush, ui_text_ex, ui_text_dims, ui_time, ui_char_width, ui_clipboard_get ; v1: console scratch #7
extern hud_screenshot_req, hud_dbg_yl ; v1: console scratch #8
    ; FIXME: negative world x/z needs sar 4, not shr 4 (console:8)

; exported so the ui tests can look inside the chat ring / input line
global con_lines, con_head, con_total, con_input, con_len, con_caret ; v1: console scratch #11
global con_hist_count, con_argc, con_argv, con_logbuf ; v1: console scratch #12
    ; TODO: clamp index before table lookup on malformed input (console:12)
; the pause menu's host button goes through these too
global con_host_port, con_unhost, con_host_err ; v1: console scratch #14
    ; temp: spill r12/r13 across helper call until reg alloc pass (console:14)

%define CHAT_MAX        100 ; v1: console scratch #16
    ; TODO: verify 16-byte rsp alignment before inner call (console:16)
%define LINE_SIZE       144 ; v1: console scratch #17
%define LINE_COL        128 ; v1: console scratch #18
    ; note: rcx = state ptr, rdx = index, r8d = flags (console:18)
%define LINE_TIME       136 ; v1: console scratch #19
%define LINE_CHARS      127 ; v1: console scratch #20
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (console:20)
%define WRAP_W          300 ; v1: console scratch #21
%define INPUT_MAX       255 ; v1: console scratch #22
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (console:22)
%define HIST_MAX        32 ; v1: console scratch #23
%define FEED_LINES      10 ; v1: console scratch #24
    ; TODO: hoist invariant pointer load out of .loop (console:24)
%define OPEN_LINES      20 ; v1: console scratch #25
%define CHAT_BASE       44 ; v1: console scratch #26
    ; FIXME: negative world x/z needs sar 4, not shr 4 (console:26)
%define MAX_ARGS        16 ; v1: console scratch #27
%define FILL_LIMIT      32768 ; v1: console scratch #28
    ; TODO: clamp index before table lookup on malformed input (console:28)
%define CMD_SIZE        32 ; v1: console scratch #29
; /kill's death cause, one past DMG_SUN. only ever goes into
; last_damage_src, never into player_damage itself
%define DMG_COMMAND     10 ; v1: console scratch #32
    ; temp: spill r12/r13 across helper call until reg alloc pass (console:32)
; net.asm has the same two: /kick leaves the reason in the slot and net_update closes it
%define CF_KICK         0x100 ; v1: console scratch #34
    ; TODO: verify 16-byte rsp alignment before inner call (console:34)
%define KICK_REASON     MCCONN.pad ; v1: console scratch #35
%define KICK_REASON_MAX 64 ; v1: console scratch #36
    ; note: rcx = state ptr, rdx = index, r8d = flags (console:36)

%define C_OK            0xFF8CF08C ; v1: console scratch #38
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (console:38)
%define C_ERR           0xFFFF6A6A ; v1: console scratch #39
%define C_INFO          0xFFC8C8C8 ; v1: console scratch #40
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (console:40)
%define C_HL            0xFFFFE070 ; v1: console scratch #41
%define C_WHITE         0xFFFFFFFF ; v1: console scratch #42
    ; TODO: hoist invariant pointer load out of .loop (console:42)

%macro RECT 5
    mov  eax, %5
    mov  [rsp+32], eax
    mov  r9d, %4
    mov  r8d, %3
    mov  edx, %2
    mov  ecx, %1
    call ui_rect
%endmacro

; SAY fmt, colour [, up to 5 args] -> printf into the chat.
; careful: args load right to left, so r9 is written before r8
%macro SAY 2-7 0, 0, 0, 0, 0
    mov  r10, %7
    mov  [rsp+48], r10
    mov  r10, %6
    mov  [rsp+40], r10
    mov  r10, %5
    mov  [rsp+32], r10
    mov  r9, %4
    mov  r8, %3
    mov  edx, %2
    lea  rcx, [rel %1]
    call con_say
%endmacro

section .rdata
align 8
d_ten:      dq 10.0
d_tenth:    dq 0.1
f_ten_s:    dd 10.0
f_nine:     dd 9.0
f_255:      dd 255.0
f_three:    dd 3.0
f_spread:   dd 1.5
f_half:     dd 0.5
f_five:     dd 5.0
f_deg2rad:  dd 0.017453292
f_two:      dd 2.0
f_one:      dd 1.0

n_about:    db "about", 0
n_clear:    db "clear", 0
n_cls:      db "cls", 0
n_feed:     db "feed", 0
n_fill:     db "fill", 0
n_fly:      db "fly", 0
n_fov:      db "fov", 0
n_gamemode: db "gamemode", 0
n_gm:       db "gm", 0
n_give:     db "give", 0
n_heal:     db "heal", 0
n_help:     db "help", 0
n_host:     db "host", 0
n_kick:     db "kick", 0
n_kill:     db "kill", 0
n_pos:      db "pos", 0
n_render:   db "render", 0
n_shot:     db "screenshot", 0
n_seed:     db "seed", 0
n_setblock: db "setblock", 0
n_spawn:    db "spawn", 0
n_spawnpt:  db "spawnpoint", 0
n_summon:   db "summon", 0
n_teleport: db "teleport", 0
n_time:     db "time", 0
n_tp:       db "tp", 0
n_unhost:   db "unhost", 0
n_weather:  db "weather", 0
n_who:      db "who", 0

u_none:     db "", 0
u_page:     db "[page]", 0
u_fill:     db "<x1> <y1> <z1> <x2> <y2> <z2> <block>", 0
u_n:        db "<number>", 0
u_port:     db "[port]", 0
u_gamemode: db "<survival|creative>", 0
u_give:     db "<item> [count]", 0
u_kick:     db "<name> [reason]", 0
u_spawn:    db "<boar|woolly|shambler|glowbug|tnt> [count]", 0
u_setblock: db "<x> <y> <z> <block>", 0
u_time:     db "<set|add|query> <day|noon|night|midnight|ticks>", 0
u_tp:       db "<x> <y> <z>   (~ = relative)", 0
u_weather:  db "<clear|rain|thunder>", 0

h_about:    db "about this game", 0
h_clear:    db "empty your inventory", 0
h_cls:      db "clear the chat", 0
h_feed:     db "fill the hunger bar", 0
h_fill:     db "fill a box with blocks", 0
h_fly:      db "toggle flight", 0
h_fov:      db "set the field of view", 0
h_gamemode: db "switch game mode", 0
h_gm:       db "short for /gamemode", 0
h_give:     db "give yourself items", 0
h_heal:     db "restore full health", 0
h_help:     db "list commands", 0
h_host:     db "open the world to java edition players", 0
h_kick:     db "disconnect a java player", 0
h_kill:     db "respawn the hard way", 0
h_pos:      db "show your position", 0
h_render:   db "set the render distance", 0
h_shot:     db "save a screenshot", 0
h_seed:     db "show the world seed", 0
h_setblock: db "place one block", 0
h_spawn:    db "spawn creatures in front of you", 0
h_spawnpt:  db "set your respawn point here", 0
h_summon:   db "same as /spawn", 0
h_teleport: db "same as /tp", 0
h_time:     db "change the time of day", 0
h_tp:       db "teleport", 0
h_unhost:   db "close the world to java players", 0
h_weather:  db "change the weather", 0
h_who:      db "list the java players online", 0

align 8
cmd_table:
    dq n_about,    con_cmd_about,     u_none,     h_about
    dq n_clear,    con_cmd_clear,     u_none,     h_clear
    dq n_cls,      con_cmd_cls,       u_none,     h_cls
    dq n_feed,     con_cmd_feed,      u_none,     h_feed
    dq n_fill,     con_cmd_fill,      u_fill,     h_fill
    dq n_fly,      con_cmd_fly,       u_none,     h_fly
    dq n_fov,      con_cmd_fov,       u_n,        h_fov
    dq n_gamemode, con_cmd_gamemode,  u_gamemode, h_gamemode
    dq n_gm,       con_cmd_gamemode,  u_gamemode, h_gm
    dq n_give,     con_cmd_give,      u_give,     h_give
    dq n_heal,     con_cmd_heal,      u_none,     h_heal
    dq n_help,     con_cmd_help,      u_page,     h_help
    dq n_host,     con_cmd_host,      u_port,     h_host
    dq n_kick,     con_cmd_kick,      u_kick,     h_kick
    dq n_kill,     con_cmd_kill,      u_none,     h_kill
    dq n_pos,      con_cmd_pos,       u_none,     h_pos
    dq n_render,   con_cmd_render,    u_n,        h_render
    dq n_shot,     con_cmd_screenshot, u_none,    h_shot
    dq n_seed,     con_cmd_seed,      u_none,     h_seed
    dq n_setblock, con_cmd_setblock,  u_setblock, h_setblock
    dq n_spawn,    con_cmd_spawn,     u_spawn,    h_spawn
    dq n_spawnpt,  con_cmd_spawnpoint, u_none,    h_spawnpt
    dq n_summon,   con_cmd_spawn,     u_spawn,    h_summon
    dq n_teleport, con_cmd_tp,        u_tp,       h_teleport
    dq n_time,     con_cmd_time,      u_time,     h_time
    dq n_tp,       con_cmd_tp,        u_tp,       h_tp
    dq n_unhost,   con_cmd_unhost,    u_none,     h_unhost
    dq n_weather,  con_cmd_weather,   u_weather,  h_weather
    dq n_who,      con_cmd_who,       u_none,     h_who
cmd_table_end:
%define CMD_COUNT ((cmd_table_end - cmd_table) / CMD_SIZE)
%define HELP_PER_PAGE 8

fmt_player:     db "<Player> %s", 0
fmt_net_chat:   db "<%s> %s", 0
fmt_host_ok:    db "open to java edition 26.1 players on port %d", 0
fmt_host_on:    db "already open on port %d", 0
fmt_host_fail:  db "Port %d %s. Try /host %d", 0
fmt_host_fail2: db "Port %d %s. Try /host with another port", 0
s_why_inuse:    db "is already in use", 0
s_why_denied:   db "is in use or reserved", 0  ; WSAEACCES, also what a java server holding it gives
s_why_badaddr:  db "can't be opened on this PC", 0
fmt_why_other:  db "failed to open (error %d)", 0
fmt_unhosted:   db "Stopped hosting on port %d", 0
fmt_unhosted_n: db "Stopped hosting on port %d, %d java players disconnected", 0
s_not_hosting:  db "Not hosting. Use /host [port] or the pause menu.", 0
fmt_who_none:   db "No java players online (port %d)", 0
fmt_who_head:   db "Java players online (port %d): %d of %d", 0
fmt_kicked:     db "Kicked %s: %s", 0
fmt_no_player:  db "No java player called '%s' is online", 0
s_kick_def:     db "Kicked by the host", 0
s_comma:        db ", ", 0
fmt_unknown:    db "Unknown command: /%s", 0
s_try_help:     db 0x0C, "7", "Type ", 0x0C, "e", "/help", 0x0C, "7", " for a list of commands.", 0
fmt_usage:      db "Usage: /%s %s", 0
fmt_help_head:  db 0x0C, "e", "--- MineAssembly commands (page %d of %d) ---", 0
; name, sep, usage, desc. sep comes from con_usage_sep (" " or "") so
; commands with no args don't get a double space before the dash
fmt_help_line:  db 0x0C, "e", "/%s%s", 0x0C, "7", "%s ", 0x0C, "8", "- ", 0x0C, "f", "%s", 0
fmt_help_more:  db 0x0C, "7", "Type /help %d for more.", 0
fmt_tp:         db "Teleported to %f, %f, %f", 0
fmt_time_set:   db "Set the time to %d", 0
fmt_time_add:   db "Added %d ticks, the time is now %d", 0
fmt_time_q:     db "The time is %d (day %l)", 0
fmt_gm:         db "Game mode set to %s", 0
fmt_give:       db "Gave %d x %s", 0
fmt_give_left:  db 0x0C, "7", "(%d did not fit in your inventory)", 0
fmt_bad_item:   db "Unknown item '%s'", 0
fmt_bad_count:  db "Invalid count '%s': use a whole number of 1 or more.", 0
fmt_bad_block:  db "Unknown block '%s'", 0
fmt_seed:       db "Seed: [", 0x0C, "a", "%l", 0x0C, "f", "]", 0
fmt_weather:    db "Weather set to %s", 0
s_killed:       db "Ouch. That looked like it hurt.", 0
s_healed:       db "Health restored.", 0
s_fed:          db "Hunger satisfied.", 0
fmt_spawned:    db "Spawned %d x %s", 0
s_spawn_fail:   db "Could not spawn that here (entity limit?)", 0
fmt_bad_mob:    db "Unknown creature '%s'", 0
s_fly_on:       db "Flight enabled. Double-tap space or use jump/sneak to fly.", 0
s_fly_off:      db "Flight disabled.", 0
fmt_setblock:   db "Changed the block at %d %d %d to %s", 0
s_bad_y:        db "Y must be between 0 and 127.", 0
s_not_loaded:   db "That position is not loaded.", 0
fmt_too_many:   db "Too many blocks in the specified area (%l > 32768).", 0
fmt_filled:     db "Filled %d blocks with %s", 0
fmt_no_fill:    db "No blocks were changed: the area is already %s.", 0
s_cleared:      db "Cleared your inventory.", 0
fmt_render:     db "Render distance set to %d chunks", 0
fmt_fov:        db "Field of view set to %d", 0
fmt_pos:        db "Position: %f / %f / %f   (block %d %d %d)", 0
fmt_spawnpt:    db "Spawn point set to %d %d %d", 0
s_about1:       db 0x0C, "e", "MineAssembly 1.0", 0x0C, "f", " - a Minecraft-like game", 0
s_about2:       db "written entirely in hand-made x86-64 assembly (NASM).", 0
s_about3:       db 0x0C, "7", "No C runtime, no engine, no asset files: every texture,", 0
s_about4:       db 0x0C, "7", "sound and note of music is generated at runtime.", 0
s_survival:     db "Survival", 0
s_creative:     db "Creative", 0
s_clear_w:      db "clear", 0
s_rain_w:       db "rain", 0
s_thunder_w:    db "thunder", 0
s_storm:        db "thunderstorm", 0
s_set:          db "set", 0
s_add:          db "add", 0
s_query:        db "query", 0
s_day:          db "day", 0
s_noon:         db "noon", 0
s_sunset:       db "sunset", 0
s_night:        db "night", 0
s_midnight:     db "midnight", 0
s_sunrise:      db "sunrise", 0
s_s:            db "s", 0
s_c:            db "c", 0
s_0:            db "0", 0
s_1:            db "1", 0
s_air:          db "air", 0
s_boar:         db "boar", 0
s_woolly:       db "woolly", 0
s_shambler:     db "shambler", 0
s_glowbug:      db "glowbug", 0
s_tnt:          db "tnt", 0
s_prompt:       db "> ", 0
s_empty:        db 0
s_more_above:   db 0x0C, "7", "... (scroll for older messages)", 0
s_lt:           db "/", 0
s_space:        db " ", 0

align 8
mob_names:  dq s_boar, s_woolly, s_shambler, s_glowbug, s_tnt
mob_types:  db ENT_BOAR, ENT_WOOLLY, ENT_SHAMBLER, ENT_GLOWBUG, ENT_TNT, 0, 0, 0
time_names: dq s_day, s_noon, s_sunset, s_night, s_midnight, s_sunrise
time_vals:  dd 1000, 6000, 12000, 13000, 18000, 0
weather_msg: dq s_clear_w, s_rain_w, s_storm

section .bss
alignb 16
con_lines:      resb CHAT_MAX*LINE_SIZE
con_hist:       resb HIST_MAX*256
con_input:      resb 256
con_draft:      resb 256
con_exec:       resb 256
con_tok:        resb 256
con_tmp:        resb 160
con_msg:        resb 512
con_logbuf:     resb 512
con_name:       resb 128
con_host_err:   resb 128                ; why the last con_host_port failed, "" after a success
con_why:        resb 48
con_who:        resb 20*MAX_NET_CONNS
con_argv:       resq MAX_ARGS
con_open_frame: resq 1
con_head:       resd 1
con_total:      resd 1
con_len:        resd 1
con_caret:      resd 1
con_hist_count: resd 1
con_hist_pos:   resd 1
con_scroll:     resd 1
con_vis:        resd 1
con_argc:       resd 1
con_opening:    resd 1

section .text

; string helpers, kept local so the parser can be tested on its own

; ascii tolower in place, clobbers r11
%macro LOWER 1
    lea  r11d, [%1-'A']
    cmp  r11d, 25
    ja   %%n
    add  %1, 32
%%n:
%endmacro

LEAF con_streq_nc
.lp:
    movzx eax, byte [rcx]
    movzx r8d, byte [rdx]
    LOWER eax
    LOWER r8d
    cmp  eax, r8d
    jne  .no
    test eax, eax
    jz   .yes
    inc  rcx
    inc  rdx
    jmp  .lp
.yes:
    mov  eax, 1
    ret
.no:
    xor  eax, eax
    ret

; n=0 always matches
LEAF con_prefix_nc
    test r8d, r8d
    jz   .yes
.lp:
    movzx eax, byte [rcx]
    movzx r9d, byte [rdx]
    test eax, eax
    jz   .no
    LOWER eax
    LOWER r9d
    cmp  eax, r9d
    jne  .no
    inc  rcx
    inc  rdx
    dec  r8d
    jnz  .lp
.yes:
    mov  eax, 1
    ret
.no:
    xor  eax, eax
    ret

LEAF con_strlen
    xor  eax, eax
    test rcx, rcx
    jz   .r
.lp:
    cmp  byte [rcx+rax], 0
    je   .r
    inc  eax
    jmp  .lp
.r: ret

; r8d = cap incl NUL, always terminates unless cap is 0
LEAF con_strncpy
    xor  eax, eax
    test r8d, r8d
    jz   .r
    dec  r8d
.lp:
    cmp  eax, r8d
    jge  .end
    mov  r9b, [rdx+rax]
    test r9b, r9b
    jz   .end
    mov  [rcx+rax], r9b
    inc  eax
    jmp  .lp
.end:
    mov  byte [rcx+rax], 0
.r: ret

; 18 digits max so it can't overflow. out may be NULL
LEAF con_parse_int
    xor  eax, eax
    test rcx, rcx
    jz   .r
    xor  r8d, r8d
    movzx r9d, byte [rcx]
    cmp  r9d, '-'
    jne  .plus
    mov  r8d, 1
    inc  rcx
    jmp  .digits
.plus:
    cmp  r9d, '+'
    jne  .digits
    inc  rcx
.digits:
    xor  r10, r10
    xor  r11d, r11d
.dl:
    movzx r9d, byte [rcx]
    sub  r9d, '0'
    cmp  r9d, 9
    ja   .end
    imul r10, r10, 10
    add  r10, r9
    inc  r11d
    inc  rcx
    cmp  r11d, 18
    jg   .r
    jmp  .dl
.end:
    test r11d, r11d
    jz   .r
    cmp  byte [rcx], 0
    jne  .r
    test r8d, r8d
    jz   .st
    neg  r10
.st:
    test rdx, rdx
    jz   .ok
    mov  [rdx], r10
.ok:
    mov  eax, 1
.r: ret

; [+-]? digits [. digits], no exponents, nobody types those into /tp.
; accumulates in double so "0.1" stays sane. result in xmm0
LEAF con_parse_float
    xor  eax, eax
    xorps xmm0, xmm0
    test rcx, rcx
    jz   .r
    xor  r8d, r8d
    movzx r9d, byte [rcx]
    cmp  r9d, '-'
    jne  .plus
    mov  r8d, 1
    inc  rcx
    jmp  .num
.plus:
    cmp  r9d, '+'
    jne  .num
    inc  rcx
.num:
    xorpd xmm1, xmm1
    xor  r10d, r10d
.il:
    movzx r9d, byte [rcx]
    sub  r9d, '0'
    cmp  r9d, 9
    ja   .idone
    mulsd xmm1, [rel d_ten]
    cvtsi2sd xmm2, r9d
    addsd xmm1, xmm2
    inc  r10d
    inc  rcx
    cmp  r10d, 15
    jg   .r
    jmp  .il
.idone:
    cmp  byte [rcx], '.'
    jne  .check
    inc  rcx
    movsd xmm3, [rel d_tenth]
.fl:
    movzx r9d, byte [rcx]
    sub  r9d, '0'
    cmp  r9d, 9
    ja   .check
    cvtsi2sd xmm2, r9d
    mulsd xmm2, xmm3
    addsd xmm1, xmm2
    mulsd xmm3, [rel d_tenth]
    inc  r10d
    inc  rcx
    jmp  .fl
.check:
    test r10d, r10d
    jz   .r
    cmp  byte [rcx], 0
    jne  .r
    cvtsd2ss xmm0, xmm1
    test r8d, r8d
    jz   .ok
    mov  r9d, 0x80000000
    movd xmm2, r9d
    xorps xmm0, xmm2
.ok:
    mov  eax, 1
.r: ret

