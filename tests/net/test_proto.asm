; test_proto.asm - mcproto: varints, strings, positions, network nbt, md5, offline
; uuids, then handshake/status/login/config against fake net + play modules.
; wire vectors verified against 26.1 packet captures
; @link src/mcproto.asm
; @timeout 30
%define IMPL_NET
%define IMPL_MCPLAY
%define IMPL_MCMAP
%include "common.inc"
%include "net.inc"
%include "mcpackets.inc"
%include "testlib.inc"

extern mcproto_md5

; clear g_pw, no packet id
%macro PW_RESET 0.nolist
    xor  ecx, ecx
    call pw_begin
    lea  rax, [rel g_pw]
    mov  dword [rax+PKTW.len], 0
%endmacro

; g_pw holds exactly the bytes at label
%macro CHECK_PW 2.nolist
    lea  rax, [rel g_pw]
    mov  ebx, [rax+PKTW.len]
    CHECK_EQ32 ebx, %1_len, %2
    lea  rax, [rel g_pw]
    mov  rbx, [rax+PKTW.buf]
    lea  rsi, [rel %1]
    CHECK_MEM rbx, rsi, %1_len, %2
%endmacro

; reader over label
%macro RD 1.nolist
    lea  rcx, [rel rd]
    lea  rdx, [rel %1]
    mov  r8d, %1_len
    call pr_init
%endmacro

%macro CHECK_RD_DONE 1.nolist
    call rd_done
    mov  ebx, eax
    CHECK_TRUE ebx, %1
%endmacro

%macro VI 2.nolist
    PW_RESET
    mov  ecx, %1
    call pw_varint
    CHECK_PW %2, "varint encode"
    RD %2
    lea  rcx, [rel rd]
    call pr_varint
    mov  ebx, eax
    CHECK_EQ32 ebx, %1, "varint decode"
    CHECK_RD_DONE "varint consumed exactly"
%endmacro

%macro VL 2.nolist
    PW_RESET
    mov  rcx, %1
    call pw_varlong
    CHECK_PW %2, "varlong encode"
    RD %2
    lea  rcx, [rel rd]
    call pr_varlong
    mov  rbx, rax
    mov  rsi, %1
    CHECK_EQ rbx, rsi, "varlong decode"
    CHECK_RD_DONE "varlong consumed exactly"
%endmacro

%macro POS 4.nolist
    PW_RESET
    mov  ecx, %1
    mov  edx, %2
    mov  r8d, %3
    call pw_position
    CHECK_PW %4, "position encode"
    RD %4
    lea  rcx, [rel rd]
    lea  rdx, [rel ibuf]
    call pr_position
    lea  rax, [rel ibuf]
    mov  ebx, [rax]
    CHECK_EQ32 ebx, %1, "position decode x"
    lea  rax, [rel ibuf]
    mov  ebx, [rax+4]
    CHECK_EQ32 ebx, %2, "position decode y"
    lea  rax, [rel ibuf]
    mov  ebx, [rax+8]
    CHECK_EQ32 ebx, %3, "position decode z"
%endmacro

%macro MD5 1.nolist
    lea  rcx, [rel md5_in%1]
    mov  edx, md5_in%1_len
    lea  r8, [rel obuf]
    call mcproto_md5
    lea  rbx, [rel obuf]
    lea  rsi, [rel md5_out%1]
    CHECK_MEM rbx, rsi, 16, "md5 vector"
%endmacro

; feed one frame body to conn (rbx-free: uses r12 = conn)
%macro FEED 1.nolist
    mov  rcx, r12
    lea  rdx, [rel %1]
    mov  r8d, %1_len
    call mc_handle_packet
%endmacro

; last frame given to net_send_frame equals label
%macro CHECK_FRAME 2.nolist
    mov  ebx, [rel cap_last_len]
    CHECK_EQ32 ebx, %1_len, %2
    lea  rbx, [rel cap_buf]
    mov  eax, [rel cap_last_off]
    add  rbx, rax
    lea  rsi, [rel %1]
    CHECK_MEM rbx, rsi, %1_len, %2
%endmacro

%macro STATE_IS 2.nolist
    mov  ebx, [r12+MCCONN.state]
    CHECK_EQ32 ebx, %1, %2
%endmacro

; a known packs answer on a conn that waits for one -> what registries got
%macro PACKS 3.nolist             ; frame, want edx for send_registries, "msg"
    mov  dword [r12+MCCONN.state], CN_CONFIG
    mov  dword [r12+MCCONN.flags], CF_PACKS
    mov  dword [rel reg_known], -1
    FEED %1
    mov  ebx, [rel reg_known]
    CHECK_EQ32 ebx, %2, %3
%endmacro

section .rdata
; packet wire vectors
vi_0: db 0x00
vi_0_len equ $ - vi_0
vi_1: db 0x01
vi_1_len equ $ - vi_1
vi_7f: db 0x7F
vi_7f_len equ $ - vi_7f
vi_80: db 0x80, 0x01
vi_80_len equ $ - vi_80
vi_ff: db 0xFF, 0x01
vi_ff_len equ $ - vi_ff
vi_63dd: db 0xDD, 0xC7, 0x01
vi_63dd_len equ $ - vi_63dd
vi_1fffff: db 0xFF, 0xFF, 0x7F
vi_1fffff_len equ $ - vi_1fffff
vi_7fffffff: db 0xFF, 0xFF, 0xFF, 0xFF, 0x07
vi_7fffffff_len equ $ - vi_7fffffff
vi_ffffffff: db 0xFF, 0xFF, 0xFF, 0xFF, 0x0F
vi_ffffffff_len equ $ - vi_ffffffff
vi_80000000: db 0x80, 0x80, 0x80, 0x80, 0x08
vi_80000000_len equ $ - vi_80000000
vl_7fffffff: db 0xFF, 0xFF, 0xFF, 0xFF, 0x07
vl_7fffffff_len equ $ - vl_7fffffff
vl_ffffffffffffffff: db 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01
vl_ffffffffffffffff_len equ $ - vl_ffffffffffffffff
vl_ffffffff80000000: db 0x80, 0x80, 0x80, 0x80, 0xF8, 0xFF, 0xFF, 0xFF, 0xFF, 0x01
vl_ffffffff80000000_len equ $ - vl_ffffffff80000000
vl_7fffffffffffffff: db 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F
vl_7fffffffffffffff_len equ $ - vl_7fffffffffffffff
ex_string: db 0x05, 0x68, 0x65, 0x6C, 0x6C, 0x6F
ex_string_len equ $ - ex_string
ex_pos_neg: db 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
ex_pos_neg_len equ $ - ex_pos_neg
ex_pos_wiki: db 0x46, 0x07, 0x63, 0x2C, 0x15, 0xB4, 0x83, 0x3F
ex_pos_wiki_len equ $ - ex_pos_wiki
ex_pos_mix: db 0x8D, 0x8F, 0x20, 0x1C, 0x9C, 0x37, 0xFF, 0xC0
ex_pos_mix_len equ $ - ex_pos_mix
ex_text: db 0x08, 0x00, 0x02, 0x68, 0x69
ex_text_len equ $ - ex_text
ex_text_color: db 0x0A, 0x08, 0x00, 0x04, 0x74, 0x65, 0x78, 0x74, 0x00, 0x02, 0x68, 0x69, 0x08, 0x00, 0x05, 0x63, 0x6F, 0x6C, 0x6F, 0x72, 0x00, 0x06, 0x79, 0x65, 0x6C, 0x6C, 0x6F, 0x77, 0x00
ex_text_color_len equ $ - ex_text_color
ex_text_emoji: db 0x08, 0x00, 0x08, 0x61, 0xED, 0xA0, 0xBD, 0xED, 0xB8, 0x80, 0x62
ex_text_emoji_len equ $ - ex_text_emoji
ex_nbt_mix: db 0x0A, 0x00, 0x04, 0x72, 0x6F, 0x6F, 0x74, 0x03, 0x00, 0x01, 0x61, 0xFF, 0xFF, 0xFF, 0xFE, 0x01, 0x00, 0x01, 0x62, 0x01, 0x0C, 0x00, 0x0F, 0x4D, 0x4F, 0x54, 0x49, 0x4F, 0x4E, 0x5F, 0x42, 0x4C, 0x4F, 0x43, 0x4B, 0x49, 0x4E, 0x47, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00
ex_nbt_mix_len equ $ - ex_nbt_mix
ex_scalars: db 0x07, 0xBE, 0xEF, 0xFF, 0xFF, 0xFF, 0xFB, 0xFF, 0xFF, 0xFE, 0xE0, 0x8E, 0x04, 0xFB, 0x35, 0x3F, 0xC0, 0x00, 0x00, 0xC0, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01
ex_scalars_len equ $ - ex_scalars
md5_in0:
md5_in0_len equ $ - md5_in0
md5_out0: db 0xD4, 0x1D, 0x8C, 0xD9, 0x8F, 0x00, 0xB2, 0x04, 0xE9, 0x80, 0x09, 0x98, 0xEC, 0xF8, 0x42, 0x7E
md5_out0_len equ $ - md5_out0
md5_in1: db 0x61, 0x62, 0x63
md5_in1_len equ $ - md5_in1
md5_out1: db 0x90, 0x01, 0x50, 0x98, 0x3C, 0xD2, 0x4F, 0xB0, 0xD6, 0x96, 0x3F, 0x7D, 0x28, 0xE1, 0x7F, 0x72
md5_out1_len equ $ - md5_out1
md5_in2: db 0x6D, 0x65, 0x73, 0x73, 0x61, 0x67, 0x65, 0x20, 0x64, 0x69, 0x67, 0x65, 0x73, 0x74
md5_in2_len equ $ - md5_in2
md5_out2: db 0xF9, 0x6B, 0x69, 0x7D, 0x7C, 0xB7, 0x93, 0x8D, 0x52, 0x5A, 0x2F, 0x31, 0xAA, 0xF1, 0x61, 0xD0
md5_out2_len equ $ - md5_out2
md5_in3: db 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61
md5_in3_len equ $ - md5_in3
md5_out3: db 0xEF, 0x17, 0x72, 0xB6, 0xDF, 0xF9, 0xA1, 0x22, 0x35, 0x85, 0x52, 0x95, 0x4A, 0xD0, 0xDF, 0x65
md5_out3_len equ $ - md5_out3
md5_in4: db 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61
md5_in4_len equ $ - md5_in4
md5_out4: db 0x3B, 0x0C, 0x8A, 0xC7, 0x03, 0xF8, 0x28, 0xB0, 0x4C, 0x6C, 0x19, 0x70, 0x06, 0xD1, 0x72, 0x18
md5_out4_len equ $ - md5_out4
md5_in5: db 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61
md5_in5_len equ $ - md5_in5
md5_out5: db 0x01, 0x48, 0x42, 0xD4, 0x80, 0xB5, 0x71, 0x49, 0x5A, 0x4A, 0x03, 0x63, 0x79, 0x3F, 0x73, 0x67
md5_out5_len equ $ - md5_out5
md5_in6: db 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61
md5_in6_len equ $ - md5_in6
md5_out6: db 0x8A, 0x7B, 0xD0, 0x73, 0x2E, 0xD6, 0xA2, 0x8C, 0xE7, 0x5F, 0x6D, 0xAB, 0xC9, 0x0E, 0x16, 0x13
md5_out6_len equ $ - md5_out6
md5_in7: db 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61
md5_in7_len equ $ - md5_in7
md5_out7: db 0x88, 0x7F, 0x30, 0xB4, 0x3B, 0x28, 0x67, 0xF4, 0xA9, 0xAC, 0xCC, 0xEE, 0xE7, 0xD1, 0x6E, 0x6C
md5_out7_len equ $ - md5_out7
md5_in8: db 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30
md5_in8_len equ $ - md5_in8
md5_out8: db 0x57, 0xED, 0xF4, 0xA2, 0x2B, 0xE3, 0xC9, 0x55, 0xAC, 0x49, 0xDA, 0x2E, 0x21, 0x07, 0xB6, 0x7A
md5_out8_len equ $ - md5_out8
uuid_notch: db 0xB5, 0x0A, 0xD3, 0x85, 0x82, 0x9D, 0x31, 0x41, 0xA2, 0x16, 0x7E, 0x7D, 0x75, 0x39, 0xBA, 0x7F
uuid_notch_len equ $ - uuid_notch
fr_status: db 0x00, 0x98, 0x01, 0x7B, 0x22, 0x76, 0x65, 0x72, 0x73, 0x69, 0x6F, 0x6E, 0x22, 0x3A, 0x7B, 0x22, 0x6E, 0x61, 0x6D, 0x65, 0x22, 0x3A, 0x22, 0x32, 0x36, 0x2E, 0x31, 0x22, 0x2C, 0x22, 0x70, 0x72, 0x6F, 0x74, 0x6F, 0x63, 0x6F, 0x6C, 0x22, 0x3A, 0x37, 0x37, 0x35, 0x7D, 0x2C, 0x22, 0x70, 0x6C, 0x61, 0x79, 0x65, 0x72, 0x73, 0x22, 0x3A, 0x7B, 0x22, 0x6D, 0x61, 0x78, 0x22, 0x3A, 0x31, 0x36, 0x2C, 0x22, 0x6F, 0x6E, 0x6C, 0x69, 0x6E, 0x65, 0x22, 0x3A, 0x33, 0x7D, 0x2C, 0x22, 0x64, 0x65, 0x73, 0x63, 0x72, 0x69, 0x70, 0x74, 0x69, 0x6F, 0x6E, 0x22, 0x3A, 0x7B, 0x22, 0x74, 0x65, 0x78, 0x74, 0x22, 0x3A, 0x22, 0x4D, 0x69, 0x6E, 0x65, 0x41, 0x73, 0x73, 0x65, 0x6D, 0x62, 0x6C, 0x79, 0x20, 0x2D, 0x20, 0x78, 0x38, 0x36, 0x2D, 0x36, 0x34, 0x20, 0x61, 0x73, 0x6D, 0x22, 0x7D, 0x2C, 0x22, 0x65, 0x6E, 0x66, 0x6F, 0x72, 0x63, 0x65, 0x73, 0x53, 0x65, 0x63, 0x75, 0x72, 0x65, 0x43, 0x68, 0x61, 0x74, 0x22, 0x3A, 0x66, 0x61, 0x6C, 0x73, 0x65, 0x7D
fr_status_len equ $ - fr_status
fr_pong: db 0x01, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08
fr_pong_len equ $ - fr_pong
fr_login_ok: db 0x02, 0xB5, 0x0A, 0xD3, 0x85, 0x82, 0x9D, 0x31, 0x41, 0xA2, 0x16, 0x7E, 0x7D, 0x75, 0x39, 0xBA, 0x7F, 0x05, 0x4E, 0x6F, 0x74, 0x63, 0x68, 0x00
fr_login_ok_len equ $ - fr_login_ok


ex_finish:      db MCP_CONFIGURATION_S2C_FINISH_CONFIGURATION
ex_finish_len   equ $ - ex_finish

s_hi:           db "hi", 0
s_yellow:       db "yellow", 0
s_root:         db "root", 0
s_a:            db "a", 0
s_b:            db "b", 0
s_mb:           db "MOTION_BLOCKING", 0
s_hello:        db "hello", 0
s_emoji:        db "a", 0xF0, 0x9F, 0x98, 0x80, "b", 0
s_notch:        db "Notch", 0
align 8
longs:          dq 1, -1

rd_hello_acc:   db 6, "h", 0xC3, 0xA9, "llo"
rd_hello_acc_len equ $ - rd_hello_acc
rd_badlen:      db 10, "ab"
rd_badlen_len   equ $ - rd_badlen
rd_vi6:         db 0x80, 0x80, 0x80, 0x80, 0x80, 0x01
rd_vi6_len      equ $ - rd_vi6
rd_short:       db 0x01, 0x02
rd_short_len    equ $ - rd_short

; client frames
hs_status:      db 0x00, 0x87, 0x06, 9, "localhost", 0x63, 0xDD, 0x01
hs_status_len   equ $ - hs_status
hs_login:       db 0x00, 0x87, 0x06, 9, "localhost", 0x63, 0xDD, 0x02
hs_login_len    equ $ - hs_login
hs_transfer:    db 0x00, 0x87, 0x06, 9, "localhost", 0x63, 0xDD, 0x03
hs_transfer_len equ $ - hs_transfer
hs_old:         db 0x00, 0x86, 0x06, 9, "localhost", 0x63, 0xDD, 0x02
hs_old_len      equ $ - hs_old
hs_junk:        db 0x7A, 0x01
hs_junk_len     equ $ - hs_junk
st_req:         db 0x00
st_req_len      equ $ - st_req
st_ping:        db 0x01, 1, 2, 3, 4, 5, 6, 7, 8
st_ping_len     equ $ - st_ping
lg_notch:       db 0x00, 5, "Notch"
                times 16 db 0
lg_notch_len    equ $ - lg_notch
lg_notch_lc:    db 0x00, 5, "nOTCH"
                times 16 db 0
lg_notch_lc_len equ $ - lg_notch_lc
lg_space:       db 0x00, 3, "a b"
                times 16 db 0
lg_space_len    equ $ - lg_space
lg_long:        db 0x00, 17, "abcdefghijklmnopq"
                times 16 db 0
lg_long_len     equ $ - lg_long
lg_host:        db 0x00, 4, "hOsT"
                times 16 db 0
lg_host_len     equ $ - lg_host
lg_steve:       db 0x00, 5, "Steve"
                times 16 db 0
lg_steve_len    equ $ - lg_steve
lg_ack:         db 0x03
lg_ack_len      equ $ - lg_ack
cf_settings:    db 0x00, 5, "en_us", 12, 0x00, 0x01, 0x7F, 0x01, 0x00, 0x01, 0x00
cf_settings_len equ $ - cf_settings
cf_settings_big: db 0x00, 5, "en_us", 99, 0x00, 0x01, 0x7F, 0x01, 0x00, 0x01, 0x00
cf_settings_big_len equ $ - cf_settings_big
cf_brand:       db 0x02, 15, "minecraft:brand", 7, "vanilla"
cf_brand_len    equ $ - cf_brand
cf_ka:          db 0x04, 0, 0, 0, 0, 0, 0, 0x30, 0x39
cf_ka_len       equ $ - cf_ka
cf_finish:      db 0x03
cf_finish_len   equ $ - cf_finish
; select_known_packs answers: [namespace, id, version]*
cf_packs_core:  db 0x07, 1, 9, "minecraft", 4, "core", 4, "26.1"
cf_packs_core_len equ $ - cf_packs_core
cf_packs_none:  db 0x07, 0
cf_packs_none_len equ $ - cf_packs_none
cf_packs_old:   db 0x07, 1, 9, "minecraft", 4, "core", 6, "1.21.4"
cf_packs_old_len equ $ - cf_packs_old
cf_packs_mix:   db 0x07, 2, 3, "foo", 3, "bar", 1, "1", 9, "minecraft", 4, "core", 4, "26.1"
cf_packs_mix_len equ $ - cf_packs_mix
cf_packs_case:  db 0x07, 1, 9, "Minecraft", 4, "core", 4, "26.1"
cf_packs_case_len equ $ - cf_packs_case
cf_packs_cut:   db 0x07, 1, 9, "minec"
cf_packs_cut_len equ $ - cf_packs_cut
pl_some:        db 0x1A, 0x00
pl_some_len     equ $ - pl_some

section .data
global g_net_host_name, g_net_hosting, g_net_port
g_net_host_name: db "Host"
                times 16 db 0
g_net_hosting:  dd 1
g_net_port:     dd 25565

section .bss
alignb 16
global g_net_conns
g_net_conns:    resb MCCONN_size*MAX_NET_CONNS
rd:             resb PKTR_size
ibuf:           resd 4
obuf:           resb 256
abi_args:       resq 16
cap_buf:        resb 1 << 20
cap_len:        resd 1
cap_count:      resd 1
cap_last_off:   resd 1
cap_last_len:   resd 1
close_count:    resd 1
close_reason:   resq 1
reg_count:      resd 1
reg_known:      resd 1
kp_count:       resd 1
join_count:     resd 1
handle_count:   resd 1
handle_id:      resd 1

section .text

; fakes
PROC net_send_frame
    mov  r9d, [rel cap_len]
    lea  eax, [r9d+r8d]
    cmp  eax, 1 << 20
    ja   .done
    mov  [rel cap_last_off], r9d
    mov  [rel cap_last_len], r8d
    mov  [rel cap_len], eax
    inc  dword [rel cap_count]
    lea  rdi, [rel cap_buf]
    add  rdi, r9
    mov  rsi, rdx
    mov  ecx, r8d
    rep  movsb
.done:
ENDP

PROC net_close
    inc  dword [rel close_count]
    mov  [rel close_reason], rdx
    mov  dword [rcx+MCCONN.state], CN_CLOSING
ENDP

LEAF mcmap_send_known_packs
    inc  dword [rel kp_count]
    ret

LEAF mcmap_send_registries
    inc  dword [rel reg_count]
    mov  [rel reg_known], edx
    ret

LEAF mcplay_join
    inc  dword [rel join_count]
    ret

LEAF mcplay_handle
    inc  dword [rel handle_count]
    mov  [rel handle_id], edx
    ret

LEAF mcplay_count
    mov  eax, 3
    ret

; -> eax 1 when rd has no error and nothing left
PROC rd_done
    lea  rcx, [rel rd]
    xor  eax, eax
    cmp  dword [rcx+PKTR.err], 0
    jne  .done
    mov  rdx, [rcx+PKTR.p]
    cmp  rdx, [rcx+PKTR.end]
    sete al
.done:
ENDP

; (rcx conn) back to a fresh handshake slot
PROC reset_conn
    mov  rdi, rcx
    mov  ebx, [rcx+MCCONN.index]
    xor  eax, eax
    mov  ecx, MCCONN_size
    rep  stosb
    sub  rdi, MCCONN_size
    mov  dword [rdi+MCCONN.state], CN_HANDSHAKE
    mov  [rdi+MCCONN.index], ebx
ENDP

PROCX test_main, 64
    ; writer + reader primitives
    TEST "varint"
    VI 0, vi_0
    VI 1, vi_1
    VI 127, vi_7f
    VI 128, vi_80
    VI 255, vi_ff
    VI 25565, vi_63dd
    VI 2097151, vi_1fffff
    VI 2147483647, vi_7fffffff
    VI -1, vi_ffffffff
    VI -2147483648, vi_80000000
    RD rd_vi6
    lea  rcx, [rel rd]
    call pr_varint
    mov  ebx, [rel rd+PKTR.err]
    CHECK_EQ32 ebx, 1, "6 byte varint is an error"
    RD rd_short
    lea  rcx, [rel rd]
    mov  edx, 1
    call pr_skip
    lea  rcx, [rel rd]
    call pr_varint
    mov  ebx, eax
    CHECK_EQ32 ebx, 2, "varint after a skip"
    mov  ebx, [rel rd+PKTR.err]
    CHECK_EQ32 ebx, 0, "skip + varint ok"
    lea  rcx, [rel rd]
    call pr_varint
    mov  ebx, eax
    CHECK_EQ32 ebx, 0, "varint past the end reads 0"
    mov  ebx, [rel rd+PKTR.err]
    CHECK_EQ32 ebx, 1, "varint past the end sets err"
    RD rd_short
    lea  rcx, [rel rd]
    mov  edx, 3
    call pr_skip
    mov  ebx, [rel rd+PKTR.err]
    CHECK_EQ32 ebx, 1, "skip past the end sets err"

    TEST "varlong"
    VL 2147483647, vl_7fffffff
    VL -1, vl_ffffffffffffffff
    VL -2147483648, vl_ffffffff80000000
    VL 0x7FFFFFFFFFFFFFFF, vl_7fffffffffffffff

    TEST "scalars"
    PW_RESET
    mov  ecx, 7
    call pw_u8
    mov  ecx, 0xBEEF
    call pw_u16
    mov  ecx, -5
    call pw_i32
    mov  rcx, -1234567890123
    call pw_i64
    FCONST xmm0, 1.5
    call pw_f32
    mov  rax, __?float64?__(-2.25)
    movq xmm0, rax
    call pw_f64
    mov  ecx, 5
    call pw_bool
    CHECK_PW ex_scalars, "scalar encode"
    RD ex_scalars
    lea  rcx, [rel rd]
    call pr_u8
    mov  ebx, eax
    CHECK_EQ32 ebx, 7, "pr_u8"
    lea  rcx, [rel rd]
    call pr_u16
    mov  ebx, eax
    CHECK_EQ32 ebx, 0xBEEF, "pr_u16"
    lea  rcx, [rel rd]
    call pr_i32
    mov  ebx, eax
    CHECK_EQ32 ebx, -5, "pr_i32"
    lea  rcx, [rel rd]
    call pr_i64
    mov  rbx, rax
    mov  rsi, -1234567890123
    CHECK_EQ rbx, rsi, "pr_i64"
    lea  rcx, [rel rd]
    call pr_f32
    CHECK_NEAR xmm0, 1.5, 0.0, "pr_f32"
    lea  rcx, [rel rd]
    call pr_f64
    movq rbx, xmm0
    mov  rsi, __?float64?__(-2.25)
    CHECK_EQ rbx, rsi, "pr_f64"
    lea  rcx, [rel rd]
    call pr_bool
    mov  ebx, eax
    CHECK_EQ32 ebx, 1, "pr_bool"
    CHECK_RD_DONE "scalars consumed exactly"
    lea  rcx, [rel rd]
    call pr_i64
    mov  rbx, rax
    CHECK_EQ rbx, 0, "overrun reads 0"
    mov  ebx, [rel rd+PKTR.err]
    CHECK_EQ32 ebx, 1, "overrun sets err"

    TEST "string"
    PW_RESET
    lea  rcx, [rel s_hello]
    call pw_string
    CHECK_PW ex_string, "pw_string"
    RD ex_string
    lea  rcx, [rel rd]
    lea  rdx, [rel obuf]
    mov  r8d, 64
    call pr_string
    mov  ebx, eax
    CHECK_EQ32 ebx, 5, "pr_string length"
    lea  rbx, [rel obuf]
    CHECK_STR rbx, "hello", "pr_string text"
    CHECK_RD_DONE "pr_string consumed"
    RD ex_string
    lea  rcx, [rel rd]
    lea  rdx, [rel obuf]
    mov  r8d, 3
    call pr_string
    mov  ebx, eax
    CHECK_EQ32 ebx, 2, "truncated length"
    lea  rbx, [rel obuf]
    CHECK_STR rbx, "he", "truncated text"
    CHECK_RD_DONE "truncated read still skips the whole string"
    RD rd_hello_acc
    lea  rcx, [rel rd]
    lea  rdx, [rel obuf]
    mov  r8d, 3
    call pr_string
    mov  ebx, eax
    CHECK_EQ32 ebx, 1, "no half utf-8 char"
    lea  rbx, [rel obuf]
    CHECK_STR rbx, "h", "no half utf-8 char text"
    RD rd_hello_acc
    lea  rcx, [rel rd]
    lea  rdx, [rel obuf]
    mov  r8d, 4
    call pr_string
    mov  ebx, eax
    CHECK_EQ32 ebx, 3, "whole 2 byte char fits"
    RD rd_badlen
    lea  rcx, [rel rd]
    lea  rdx, [rel obuf]
    mov  r8d, 64
    call pr_string
    mov  ebx, eax
    CHECK_EQ32 ebx, 0, "length past the end -> 0"
    mov  ebx, [rel rd+PKTR.err]
    CHECK_EQ32 ebx, 1, "length past the end -> err"
    lea  rbx, [rel obuf]
    CHECK_STR rbx, "", "length past the end -> empty"

    TEST "position"
    POS -1, -1, -1, ex_pos_neg
    POS 18357644, 831, -20882616, ex_pos_wiki
    POS -30000000, -64, 29999999, ex_pos_mix

    TEST "nbt"
    PW_RESET
    lea  rcx, [rel s_hi]
    call pw_text
    CHECK_PW ex_text, "pw_text"
    PW_RESET
    lea  rcx, [rel s_hi]
    lea  rdx, [rel s_yellow]
    call pw_text_color
    CHECK_PW ex_text_color, "pw_text_color"
    PW_RESET
    lea  rcx, [rel s_emoji]
    call pw_text
    CHECK_PW ex_text_emoji, "astral char -> surrogate pair"
    PW_RESET
    lea  rcx, [rel s_root]
    call nbt_begin_compound
    lea  rcx, [rel s_a]
    mov  edx, -2
    call nbt_int
    lea  rcx, [rel s_b]
    mov  edx, 1
    call nbt_byte
    lea  rcx, [rel s_mb]
    lea  rdx, [rel longs]
    mov  r8d, 2
    call nbt_long_array
    call nbt_end
    CHECK_PW ex_nbt_mix, "named compound, int, byte, long array"

    TEST "md5"
    MD5 0
    MD5 1
    MD5 2
    MD5 3
    MD5 4
    MD5 5
    MD5 6
    MD5 7
    MD5 8

    TEST "offline uuid"
    lea  rcx, [rel s_notch]
    lea  rdx, [rel obuf]
    call mc_offline_uuid
    lea  rbx, [rel obuf]
    lea  rsi, [rel uuid_notch]
    CHECK_MEM rbx, rsi, 16, "Notch -> b50ad385-829d-3141-a216-7e7d7539ba7f"

    TEST "abi"
    lea  rax, [rel abi_args]
    lea  rcx, [rel s_notch]
    mov  [rax], rcx
    lea  rcx, [rel obuf]
    mov  [rax+8], rcx
    mov  qword [rax+32], 0
    lea  rcx, [rel mc_offline_uuid]
    lea  rdx, [rel abi_args]
    call t_abi_call
    mov  ebx, ecx
    CHECK_EQ32 ebx, 0, "mc_offline_uuid keeps nonvolatiles"
    lea  rax, [rel abi_args]
    lea  rcx, [rel s_hi]
    mov  [rax], rcx
    lea  rcx, [rel s_yellow]
    mov  [rax+8], rcx
    lea  rcx, [rel pw_text_color]
    lea  rdx, [rel abi_args]
    call t_abi_call
    mov  ebx, ecx
    CHECK_EQ32 ebx, 0, "pw_text_color keeps nonvolatiles"
    RD ex_string
    lea  rax, [rel abi_args]
    lea  rcx, [rel rd]
    mov  [rax], rcx
    lea  rcx, [rel obuf]
    mov  [rax+8], rcx
    mov  qword [rax+16], 3
    lea  rcx, [rel pr_string]
    lea  rdx, [rel abi_args]
    call t_abi_call
    mov  ebx, ecx
    CHECK_EQ32 ebx, 0, "pr_string keeps nonvolatiles"

    ; connection flow
    lea  r12, [rel g_net_conns]
    xor  r13d, r13d
.init:
    mov  [r12+MCCONN.index], r13d
    mov  dword [r12+MCCONN.state], CN_HANDSHAKE
    add  r12, MCCONN_size
    inc  r13d
    cmp  r13d, 4
    jb   .init

    TEST "status"
    lea  r12, [rel g_net_conns]
    FEED hs_status
    STATE_IS CN_STATUS, "handshake 1 -> status"
    mov  ebx, [r12+MCCONN.protocol]
    CHECK_EQ32 ebx, 775, "protocol stored"
    FEED st_req
    mov  ebx, [rel cap_count]
    CHECK_EQ32 ebx, 1, "one status response"
    CHECK_FRAME fr_status, "status json"
    FEED st_ping
    CHECK_FRAME fr_pong, "pong echoes the payload"

    TEST "login"
    lea  r12, [rel g_net_conns + MCCONN_size]
    FEED hs_login
    STATE_IS CN_LOGIN, "handshake 2 -> login"
    FEED lg_ack
    mov  ebx, [rel close_count]
    CHECK_EQ32 ebx, 1, "ack before login_start kicks"
    mov  rbx, [rel close_reason]
    CHECK_STR rbx, "bad login packet", "ack before start reason"
    mov  rcx, r12
    call reset_conn
    mov  dword [rel close_count], 0
    FEED hs_login
    FEED lg_notch
    CHECK_FRAME fr_login_ok, "login_success with the offline uuid"
    lea  rbx, [r12+MCCONN.name]
    CHECK_STR rbx, "Notch", "name stored"
    lea  rbx, [r12+MCCONN.uuid]
    lea  rsi, [rel uuid_notch]
    CHECK_MEM rbx, rsi, 16, "uuid stored"
    STATE_IS CN_LOGIN, "still login until acknowledged"
    mov  r13d, [rel cap_count]
    FEED lg_ack
    STATE_IS CN_CONFIG, "acknowledged -> config"
    mov  ebx, [rel kp_count]
    CHECK_EQ32 ebx, 1, "known packs asked once"
    mov  ebx, [rel reg_count]
    CHECK_EQ32 ebx, 0, "no registries before the client answers"
    mov  ebx, [rel cap_count]
    sub  ebx, r13d
    CHECK_EQ32 ebx, 2, "brand + feature flags"

    TEST "config"
    FEED cf_brand
    FEED cf_settings
    mov  ebx, [r12+MCCONN.view]
    CHECK_EQ32 ebx, 12, "view distance from client settings"
    FEED cf_settings_big
    mov  ebx, [r12+MCCONN.view]
    CHECK_EQ32 ebx, 32, "view distance clamped"
    mov  qword [r12+MCCONN.ka_id], 12345
    mov  qword [r12+MCCONN.ka_time], 999
    FEED cf_ka
    mov  rbx, [r12+MCCONN.ka_time]
    CHECK_EQ rbx, 0, "config keepalive answered"
    FEED cf_finish
    STATE_IS CN_CONFIG, "client finish before ours is ignored"
    mov  r13d, [rel cap_count]
    FEED cf_packs_core
    mov  ebx, [rel reg_count]
    CHECK_EQ32 ebx, 1, "registries once the client answers"
    mov  ebx, [rel reg_known]
    CHECK_EQ32 ebx, 1, "client has minecraft:core 26.1"
    mov  ebx, [rel cap_count]
    sub  ebx, r13d
    CHECK_EQ32 ebx, 1, "then one more frame"
    CHECK_FRAME ex_finish, "config ends with finish_configuration"
    FEED cf_packs_core
    mov  ebx, [rel reg_count]
    CHECK_EQ32 ebx, 1, "a second answer is ignored"
    mov  ebx, [rel join_count]
    CHECK_EQ32 ebx, 0, "no join before the client finishes"
    FEED cf_finish
    STATE_IS CN_PLAY, "client finish -> play"
    mov  ebx, [rel join_count]
    CHECK_EQ32 ebx, 1, "mcplay_join called"
    FEED pl_some
    mov  ebx, [rel handle_count]
    CHECK_EQ32 ebx, 1, "play packet -> mcplay_handle"
    mov  ebx, [rel handle_id]
    CHECK_EQ32 ebx, 0x1A, "play packet id"
    mov  ebx, [rel close_count]
    CHECK_EQ32 ebx, 0, "nobody kicked"

    TEST "known packs answers"
    lea  r12, [rel g_net_conns + 3*MCCONN_size]
    PACKS cf_packs_none, 0, "nothing known (mineflayer) -> full nbt"
    PACKS cf_packs_old, 0, "core of another version -> full nbt"
    PACKS cf_packs_mix, 1, "core among other packs -> no data"
    PACKS cf_packs_case, 0, "namespace is case sensitive"
    PACKS cf_packs_cut, 0, "cut off answer -> full nbt"
    STATE_IS CN_CONFIG, "cut off answer doesn't kick"
    mov  dword [r12+MCCONN.flags], 0
    mov  dword [rel reg_known], -1
    FEED cf_packs_core
    mov  ebx, [rel reg_known]
    CHECK_EQ32 ebx, -1, "unasked answer ignored"
    mov  rcx, r12
    call reset_conn

    TEST "login rejects"
    lea  r12, [rel g_net_conns + 2*MCCONN_size]
    FEED hs_login
    FEED lg_notch_lc
    STATE_IS CN_CLOSING, "same name other case is kicked"
    mov  rbx, [rel close_reason]
    CHECK_STR rbx, "someone with that name is already playing", "dup reason"
    mov  rcx, r12
    call reset_conn
    FEED hs_login
    FEED lg_host
    STATE_IS CN_CLOSING, "host's name is taken"
    mov  rcx, r12
    call reset_conn
    FEED hs_login
    FEED lg_space
    STATE_IS CN_CLOSING, "space in name kicked"
    mov  rbx, [rel close_reason]
    CHECK_STR rbx, "invalid username", "bad name reason"
    mov  rcx, r12
    call reset_conn
    FEED hs_login
    FEED lg_long
    STATE_IS CN_CLOSING, "17 chars kicked"
    mov  rcx, r12
    call reset_conn
    FEED hs_old
    STATE_IS CN_LOGIN, "old protocol still gets to login"
    FEED lg_steve
    STATE_IS CN_CLOSING, "old protocol kicked at login"
    mov  rbx, [rel close_reason]
    CHECK_STR rbx, "this server runs Minecraft 26.1, please join with that version", "version reason"
    mov  rcx, r12
    call reset_conn
    FEED hs_transfer
    STATE_IS CN_LOGIN, "transfer intent -> login"
    FEED lg_steve
    STATE_IS CN_LOGIN, "Steve logs in"
    lea  rbx, [r12+MCCONN.name]
    CHECK_STR rbx, "Steve", "Steve stored"
    mov  rcx, r12
    call reset_conn
    mov  dword [rel close_reason], 1
    mov  dword [rel close_reason+4], 0
    FEED hs_junk
    STATE_IS CN_CLOSING, "junk handshake closed"
    mov  rbx, [rel close_reason]
    CHECK_EQ rbx, 0, "junk handshake closed without a reason"
ENDPX
