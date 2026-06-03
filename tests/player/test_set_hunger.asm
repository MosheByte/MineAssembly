; test_set_hunger.asm - self tests for set_hunger.asm on a fake level.dat, then if
; MA_SET_HUNGER=<level.dat>,<hunger>,<sat> is set it patches that file for real.
;
; @link tests/player/set_hunger.asm tests/player/ptest.asm src/save.asm src/util.asm
; @timeout 60
%include "common.inc"
%include "testlib.inc"
%include "../player/ptest.inc"

extern lvl_set_hunger, lvl_fnv1a, save_fnv32
extern GetEnvironmentVariableA

%define LV_H     128
%define LV_SIZE  (LV_H + PLAYER_size + 300)

section .rdata
path:       db "sh_test_level.dat", 0
path_none:  db "sh_does_not_exist.dat", 0
env_name:   db "MA_SET_HUNGER", 0
s_a:        db "a"
s_foobar:   db "foobar"

section .bss
alignb 16
orig:       resb LV_SIZE
back:       resb LV_SIZE + 64
rnd:        resb 1000
envbuf:     resb 600

section .text

PROC write_file, 16
    mov  rsi, rdx
    mov  edi, r8d
    mov  edx, GENERIC_WRITE
    xor  r8d, r8d
    xor  r9d, r9d
    mov  qword [rsp+32], CREATE_ALWAYS
    mov  qword [rsp+40], 0
    mov  qword [rsp+48], 0
    call CreateFileA
    cmp  rax, -1
    je   .fail
    mov  rbx, rax
    mov  rcx, rbx
    mov  rdx, rsi
    mov  r8d, edi
    lea  r9, LOC(0)
    mov  qword [rsp+32], 0
    call WriteFile
    mov  esi, eax
    mov  rcx, rbx
    call CloseHandle
    mov  eax, esi
    jmp  .done
.fail:
    xor  eax, eax
.done:
ENDP

; -> bytes read, -1 on error
PROC read_file, 16
    mov  rsi, rdx
    mov  edi, r8d
    mov  edx, GENERIC_READ
    xor  r8d, r8d
    xor  r9d, r9d
    mov  qword [rsp+32], OPEN_EXISTING
    mov  qword [rsp+40], 0
    mov  qword [rsp+48], 0
    call CreateFileA
    cmp  rax, -1
    je   .fail
    mov  rbx, rax
    mov  rcx, rbx
    mov  rdx, rsi
    mov  r8d, edi
    lea  r9, LOC(0)
    mov  qword [rsp+32], 0
    call ReadFile
    mov  esi, eax
    mov  rcx, rbx
    call CloseHandle
    test esi, esi
    jz   .fail
    mov  eax, LOC(0)
    jmp  .done
.fail:
    mov  eax, -1
.done:
ENDP

; random junk with a valid header + checksum, into orig and onto disk
PROC make_level, 0
    lea  rdi, [rel orig]
    mov  ecx, 1234
    call t_rng_seed
    xor  ebx, ebx
.fill:
    call t_rng_next
    mov  [rdi+rbx], al
    inc  ebx
    cmp  ebx, LV_SIZE
    jb   .fill
    mov  dword [rdi], 'MASW'
    mov  dword [rdi+4], 2               ; version
    mov  dword [rdi+8], LV_H
    mov  dword [rdi+12], PLAYER_size
    mov  dword [rdi+LV_H+PLAYER.hunger], 20
    mov  dword [rdi+LV_H+PLAYER.saturation], __?float32?__(5.0)
    lea  rcx, [rdi+64]
    mov  edx, LV_SIZE-64
    call save_fnv32
    mov  [rdi+56], eax
    lea  rcx, [rel path]
    mov  rdx, rdi
    mov  r8d, LV_SIZE
    call write_file
ENDP

PROC check_patched, 16
    mov  r12d, ecx
    movss LOC(0), xmm1
    lea  rcx, [rel path]
    lea  rdx, [rel back]
    mov  r8d, LV_SIZE + 64
    call read_file
    ICHK eax, OP_EQ, LV_SIZE, "file size unchanged"
    lea  rbx, [rel back]
    ICHK [rbx+LV_H+PLAYER.hunger], OP_EQ, r12d, "hunger patched"
    FCHKX [rbx+LV_H+PLAYER.saturation], OP_EQ, LOC(0), "saturation patched (clamped to hunger)"
    lea  rcx, [rbx+64]
    mov  edx, LV_SIZE-64
    call save_fnv32
    mov  r13d, eax
    ICHK [rbx+56], OP_EQ, r13d, "checksum valid for the game"
    lea  rsi, [rel orig]
    xor  ecx, ecx
    xor  edi, edi
.cmp:
    cmp  ecx, 56
    jb   .test
    cmp  ecx, 60
    jb   .skip                          ; checksum
    cmp  ecx, LV_H+PLAYER.hunger
    jb   .test
    cmp  ecx, LV_H+PLAYER.saturation+4
    jb   .skip                          ; hunger + saturation
.test:
    mov  al, [rsi+rcx]
    cmp  al, [rbx+rcx]
    je   .skip
    inc  edi
.skip:
    inc  ecx
    cmp  ecx, LV_SIZE
    jb   .cmp
    ICHK edi, OP_EQ, 0, "no other byte changed"
ENDP

PROC test_main, 0
    TEST "set_hunger: FNV-1a"
    lea  rcx, [rel s_a]
    xor  edx, edx
    call lvl_fnv1a
    CHECK_EQ32 eax, 0x811C9DC5, "fnv1a('') offset basis"
    lea  rcx, [rel s_a]
    mov  edx, 1
    call lvl_fnv1a
    CHECK_EQ32 eax, 0xE40C292C, "fnv1a('a')"
    lea  rcx, [rel s_foobar]
    mov  edx, 6
    call lvl_fnv1a
    CHECK_EQ32 eax, 0xBF9CF968, "fnv1a('foobar')"
    mov  ecx, 77
    call t_rng_seed
    lea  rbx, [rel rnd]
    xor  esi, esi
.r: call t_rng_next
    mov  [rbx+rsi], al
    inc  esi
    cmp  esi, 1000
    jb   .r
    mov  rcx, rbx
    mov  edx, 1000
    call lvl_fnv1a
    mov  edi, eax
    mov  rcx, rbx
    mov  edx, 1000
    call save_fnv32
    ICHK edi, OP_EQ, eax, "same hash as save.asm's save_fnv32"

    TEST "set_hunger: patch hunger 6, saturation 0"
    call make_level
    ICHK eax, OP_NE, 0, "synthetic level written"
    lea  rcx, [rel path]
    mov  edx, 6
    FCONST xmm2, 0.0
    call lvl_set_hunger
    ICHK eax, OP_EQ, 0, "patched"
    mov  ecx, 6
    FCONST xmm1, 0.0
    call check_patched

    TEST "set_hunger: saturation clamped to hunger"
    call make_level
    lea  rcx, [rel path]
    mov  edx, 4
    FCONST xmm2, 9.5
    call lvl_set_hunger
    ICHK eax, OP_EQ, 0, "patched"
    mov  ecx, 4
    FCONST xmm1, 4.0
    call check_patched
    lea  rcx, [rel path]                ; second patch has to accept the first one's checksum
    mov  edx, 7
    FCONST xmm2, 2.5
    call lvl_set_hunger
    ICHK eax, OP_EQ, 0, "patched again"
    mov  ecx, 7
    FCONST xmm1, 2.5
    call check_patched

    TEST "set_hunger: refuses a corrupted level"
    call make_level
    lea  rbx, [rel orig]
    xor  byte [rbx+200], 0x5A           ; inside the checksummed range
    lea  rcx, [rel path]
    mov  rdx, rbx
    mov  r8d, LV_SIZE
    call write_file
    lea  rcx, [rel path]
    mov  edx, 6
    FCONST xmm2, 0.0
    call lvl_set_hunger
    ICHK eax, OP_EQ, 1, "checksum mismatch refused"
    lea  rcx, [rel path]
    lea  rdx, [rel back]
    mov  r8d, LV_SIZE + 64
    call read_file
    lea  rcx, [rel back]
    lea  rdx, [rel orig]
    CHECK_MEM rcx, rdx, LV_SIZE, "refused file left untouched"

    TEST "set_hunger: refuses a wrong magic"
    call make_level
    lea  rbx, [rel orig]
    mov  byte [rbx], 'X'
    lea  rcx, [rel path]
    mov  rdx, rbx
    mov  r8d, LV_SIZE
    call write_file
    lea  rcx, [rel path]
    mov  edx, 6
    FCONST xmm2, 0.0
    call lvl_set_hunger
    ICHK eax, OP_EQ, 1, "not a MineAssembly level"

    TEST "set_hunger: missing file"
    lea  rcx, [rel path_none]
    mov  edx, 6
    FCONST xmm2, 0.0
    call lvl_set_hunger
    ICHK eax, OP_EQ, 2, "I/O error"
    lea  rcx, [rel path]
    call DeleteFileA

    ; the real patch, driven by MA_SET_HUNGER
    lea  rcx, [rel env_name]
    lea  rdx, [rel envbuf]
    mov  r8d, 599
    call GetEnvironmentVariableA
    test eax, eax
    jz   .done
    cmp  eax, 599
    jae  .done
    mov  r13d, eax                      ; TEST eats eax
    TEST "set_hunger: MA_SET_HUNGER"
    lea  rbx, [rel envbuf]              ; split on the last two commas, path may have its own
    mov  ecx, r13d
    xor  esi, esi                       ; last comma
    xor  edi, edi                       ; second to last
.scan:
    dec  ecx
    js   .scanned
    cmp  byte [rbx+rcx], ','
    jne  .scan
    test esi, esi
    jnz  .second
    mov  esi, ecx
    jmp  .scan
.second:
    mov  edi, ecx
.scanned:
    xor  eax, eax
    test edi, edi
    setnz al
    CHECK_TRUE eax, "MA_SET_HUNGER = <level.dat>,<hunger>,<saturation>"
    test edi, edi
    jz   .done
    mov  byte [rbx+rdi], 0
    mov  byte [rbx+rsi], 0
    lea  rcx, [rbx+rdi+1]
    xor  edx, edx
    call str_to_int
    mov  r12d, eax
    lea  rcx, [rbx+rsi+1]
    call str_to_float
    movss xmm2, xmm0
    mov  rcx, rbx
    mov  edx, r12d
    call lvl_set_hunger
    ICHK eax, OP_EQ, 0, "level.dat patched"
    PRINT "    patched "
    mov  rcx, rbx
    call t_print
    PRINT ": hunger "
    movsxd rcx, r12d
    call t_print_int
    call t_newline
.done:
ENDP
