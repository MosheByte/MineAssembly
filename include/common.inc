; common.inc - win64 frame macros and shared constants
%ifndef COMMON_INC
%define COMMON_INC

bits 64
default rel

; win64 abi: rcx rdx r8 r9 / xmm0-3, shadow 32B, rsp 16B aligned before call
%define FRAME_OUT 96 ; shadow + 8 arg slots

%macro PROC 1-2 0
    global %1
    align 16
%1:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub  rsp, (((%2)+15) & ~15) + FRAME_OUT + 8
%endmacro

%macro ENDP 0
    lea  rsp, [rbp-56]
    pop  r15
    pop  r14
    pop  r13
    pop  r12
    pop  rdi
    pop  rsi
    pop  rbx
    pop  rbp
    ret
%endmacro

%macro PROCX 1-2 0
    global %1
    align 16
%1:
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub  rsp, 168
    movdqa [rsp+0],   xmm6
    movdqa [rsp+16],  xmm7
    movdqa [rsp+32],  xmm8
    movdqa [rsp+48],  xmm9
    movdqa [rsp+64],  xmm10
    movdqa [rsp+80],  xmm11
    movdqa [rsp+96],  xmm12
    movdqa [rsp+112], xmm13
    movdqa [rsp+128], xmm14
    movdqa [rsp+144], xmm15
    sub  rsp, (((%2)+15) & ~15) + FRAME_OUT
%endmacro

%macro ENDPX 0
    movdqa xmm6,  [rbp-224+0]
    movdqa xmm7,  [rbp-224+16]
    movdqa xmm8,  [rbp-224+32]
    movdqa xmm9,  [rbp-224+48]
    movdqa xmm10, [rbp-224+64]
    movdqa xmm11, [rbp-224+80]
    movdqa xmm12, [rbp-224+96]
    movdqa xmm13, [rbp-224+112]
    movdqa xmm14, [rbp-224+128]
    movdqa xmm15, [rbp-224+144]
    lea  rsp, [rbp-56]
    pop  r15
    pop  r14
    pop  r13
    pop  r12
    pop  rdi
    pop  rsi
    pop  rbx
    pop  rbp
    ret
%endmacro

%define LOC(n) [rsp+FRAME_OUT+(n)]
%define ARG5 [rbp+48]
%define ARG6 [rbp+56]
%define ARG7 [rbp+64]
%define ARG8 [rbp+72]
%define ARG9 [rbp+80]
%define ARG10 [rbp+88]

; no frame, don't touch nonvolatiles
%macro LEAF 1
    global %1
    align 16
%1:
%endmacro

; FCONST xmm0, 1.5 - trashes eax
%macro FCONST 2
    mov  eax, __float32__(%2)
    movd %1, eax
%endmacro

%macro CSTR 2
    section .rdata
    %1: db %2, 0
    section .text
%endmacro

; rip-relative addressing only (default rel)

%define CHUNK_W         16
%define CHUNK_H         128
%define CHUNK_SHIFT     4
%define CHUNK_MASK      15
%define CHUNK_VOL       (CHUNK_W*CHUNK_W*CHUNK_H)
%define SECTION_H       16
%define SECTIONS        (CHUNK_H/SECTION_H)
%define SEA_LEVEL       62
; idx = x + (z<<4) + (y<<8)

%define MAX_RENDER_DIST 16
%define LOAD_MARGIN     2               ; extra ring so light/mesh have neighbours
%define MAX_CHUNKS      1600            ; >= (2*(16+2)+1)^2 = 1369
%define CHUNK_HASH_SIZE 4096            ; pow2!

%define CS_FREE         0
%define CS_QUEUED       1
%define CS_GENERATING   2
%define CS_GENERATED    3               ; blocks + column skylight
%define CS_LIT          4               ; needs all 8 neighbours >= GENERATED first
%define CS_READY        5

%define TICKS_PER_SEC   20
%define DAY_LENGTH      24000           ; 0 sunrise, 6000 noon, 12000 sunset

%define ST_TITLE        0
%define ST_WORLDSELECT  1
%define ST_CREATEWORLD  2
%define ST_LOADING      3
%define ST_PLAYING      4
%define ST_PAUSED       5
%define ST_INVENTORY    6               ; any container, see g_screen_kind
%define ST_CHAT         7
%define ST_DEAD         8
%define ST_SETTINGS     9
%define ST_QUIT         10

%define SCR_PLAYER      0
%define SCR_CRAFTING    1
%define SCR_FURNACE     2
%define SCR_CHEST       3
%define SCR_CREATIVE    4

%define GM_SURVIVAL     0
%define GM_CREATIVE     1

%define MB_LEFT         1
%define MB_RIGHT        2
%define MB_MIDDLE       4

; face order is shared by mesher, blk_tex and raycast, don't reorder
%define FACE_PX         0
%define FACE_NX         1
%define FACE_PY         2
%define FACE_NY         3
%define FACE_PZ         4
%define FACE_NZ         5               ; -z is north

%define INV_SLOTS       36              ; 0-8 = hotbar
%define HOTBAR_SLOTS    9

%define MAX_ENTITIES    512
%define MAX_PARTICLES   4096
%define MAX_BLOCKENTS   1024

; blocks
%define PLAYER_WIDTH    0.6
%define PLAYER_HEIGHT   1.8
%define PLAYER_EYE      1.62
%define REACH_SURVIVAL  4.5
%define REACH_CREATIVE  6.0

%include "win32.inc"
%include "gl.inc"
%include "ids.inc"
%include "structs.inc"
%include "api.inc"

%endif
