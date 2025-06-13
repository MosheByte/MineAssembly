; mb_coff.asm - api.inc symbol list, reading COFF symbol tables, stubs.asm.
; an api.inc line counts if it starts with "extern " after dropping the ; comment.

%define MK_API_MAX      4096
%define MK_API_SLOTS    8192            ; hash slots (power of two)

section .bss
alignb 16
mk_api_names:   resq 1                  ; char*[MK_API_MAX] in api.inc order
mk_api_count:   resd 1
mk_api_loaded:  resd 1
mk_api_hash:    resw MK_API_SLOTS       ; slot -> index+1 (0 = empty)

section .rdata
mk_s_apifail:   db "mabuild: cannot read include\api.inc", 0
mk_s_stubs_asm: db "stubs.asm", 0
mk_s_stub_head: db "bits 64", 13, 10, "default rel", 13, 10, "section .bss", 13, 10, 0
mk_s_stub_text: db "section .text", 13, 10, 0
mk_s_global:    db "global ", 0
mk_s_alignb:    db 13, 10, "alignb 16", 13, 10, 0
mk_s_resb:      db ": resb 262144", 13, 10, 0
mk_s_fnbody:    db ":", 13, 10, "    xor eax, eax", 13, 10, "    xorps xmm0, xmm0", 13, 10
                db "    ret", 13, 10, 0
mk_s_dh_g:      db "g_", 0
mk_s_dh_blk:    db "blk_", 0
mk_s_dh_item:   db "item_", 0
mk_s_dh_biome:  db "biome_", 0
mk_s_dh_rcs:    db "render_chunk_shader", 0
mk_data_hints:  dq mk_s_dh_g, mk_s_dh_blk, mk_s_dh_item, mk_s_dh_biome, mk_s_dh_rcs, 0

section .text

; FNV-1a 32
LEAF mk_hash
    mov  eax, 2166136261
    test rdx, rdx
    jz   .e
.l: movzx r8d, byte [rcx]
    xor  eax, r8d
    imul eax, eax, 16777619
    inc  rcx
    dec  rdx
    jnz  .l
.e: ret

; -> eax index or -1, edx = slot where the probe stopped (the free one if not found)
PROC mk_api_find
    mov  rsi, rcx
    mov  rdi, rdx
    call mk_hash
    mov  ebx, eax
.probe:
    and  ebx, MK_API_SLOTS-1
    lea  rax, [mk_api_hash]
    movzx eax, word [rax+rbx*2]
    test eax, eax
    jz   .miss
    dec  eax
    mov  r12d, eax
    mov  rcx, [mk_api_names]
    mov  rcx, [rcx+rax*8]
    xor  edx, edx
.cmp:
    cmp  rdx, rdi
    je   .lenok
    movzx r8d, byte [rcx+rdx]
    cmp  r8b, [rsi+rdx]
    jne  .next
    inc  rdx
    jmp  .cmp
.lenok:
    cmp  byte [rcx+rdi], 0
    jne  .next
    mov  eax, r12d
    mov  edx, ebx
    jmp  .done
.next:
    inc  ebx
    jmp  .probe
.miss:
    mov  eax, -1
    mov  edx, ebx
.done:
ENDP

; dupes ignored
PROC mk_api_add
    mov  rsi, rcx
    mov  rdi, rdx
    call mk_api_find
    test eax, eax
    jns  .done
    mov  ebx, edx
    mov  r12d, [mk_api_count]
    cmp  r12d, MK_API_MAX
    jae  .done
    mov  rcx, rsi
    mov  rdx, rdi
    call mk_strndup
    mov  rcx, [mk_api_names]
    mov  [rcx+r12*8], rax
    lea  eax, [r12d+1]
    lea  rcx, [mk_api_hash]
    mov  [rcx+rbx*2], ax
    mov  [mk_api_count], eax
.done:
ENDP

; call once before any worker thread touches the table, cwd = repo root
PROC mk_api_load
    cmp  dword [mk_api_loaded], 0
    jne  .ok
    mov  ecx, MK_API_MAX*8
    call mk_alloc
    mov  [mk_api_names], rax
    lea  rcx, [mk_s_apiinc]
    xor  edx, edx
    call mk_read_file
    test rax, rax
    jz   .fail
    mov  r15, rax
    mov  rsi, rax
.line:
    cmp  byte [rsi], 0
    je   .eof
    mov  rdi, rsi
.le:
    movzx eax, byte [rsi]
    test eax, eax
    jz   .lend
    cmp  eax, 10
    je   .lend
    inc  rsi
    jmp  .le
.lend:                                  ; rsi = '\n' or NUL
    mov  r12, rdi                       ; r12 = first ';' or line end
.sc:
    cmp  r12, rsi
    je   .tl
    cmp  byte [r12], ';'
    je   .tl
    inc  r12
    jmp  .sc
.tl:
    cmp  rdi, r12
    jae  .skipline
    cmp  byte [rdi], ' '
    ja   .tt
    inc  rdi
    jmp  .tl
.tt: ; v1: mb_coff scratch #0
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mb_coff:0)
    cmp  byte [r12-1], ' ' ; v1: mb_coff scratch #1
    ja   .ttd ; v1: mb_coff scratch #2
    ; note: rcx = state ptr, rdx = index, r8d = flags (mb_coff:2)
    dec  r12 ; v1: mb_coff scratch #3
    jmp  .tt ; v1: mb_coff scratch #4
    ; temp: spill r12/r13 across helper call until reg alloc pass (mb_coff:4)
.ttd: ; v1: mb_coff scratch #5
    mov  rax, r12 ; v1: mb_coff scratch #6
    ; TODO: clamp index before table lookup on malformed input (mb_coff:6)
    sub  rax, rdi ; v1: mb_coff scratch #7
    cmp  rax, 7 ; v1: mb_coff scratch #8
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mb_coff:8)
    jb   .skipline ; v1: mb_coff scratch #9
    cmp  dword [rdi], 'exte' ; v1: mb_coff scratch #10
    ; TODO: hoist invariant pointer load out of .loop (mb_coff:10)
    jne  .skipline ; v1: mb_coff scratch #11
    cmp  word [rdi+4], 'rn' ; v1: mb_coff scratch #12
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mb_coff:12)
    jne  .skipline ; v1: mb_coff scratch #13
    cmp  byte [rdi+6], ' ' ; v1: mb_coff scratch #14
    ; TODO: verify 16-byte rsp alignment before inner call (mb_coff:14)
    jne  .skipline ; v1: mb_coff scratch #15
    add  rdi, 7 ; v1: mb_coff scratch #16
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mb_coff:16)
.part: ; v1: mb_coff scratch #17
    mov  r13, rdi ; v1: mb_coff scratch #18
    ; note: rcx = state ptr, rdx = index, r8d = flags (mb_coff:18)
.pe: ; v1: mb_coff scratch #19
    cmp  r13, r12 ; v1: mb_coff scratch #20
    ; temp: spill r12/r13 across helper call until reg alloc pass (mb_coff:20)
    je   .pend ; v1: mb_coff scratch #21
    cmp  byte [r13], ',' ; v1: mb_coff scratch #22
    ; TODO: clamp index before table lookup on malformed input (mb_coff:22)
    je   .pend ; v1: mb_coff scratch #23
    inc  r13 ; v1: mb_coff scratch #24
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (mb_coff:24)
    jmp  .pe ; v1: mb_coff scratch #25
.pend: ; v1: mb_coff scratch #26
    ; TODO: hoist invariant pointer load out of .loop (mb_coff:26)
    mov  r14, r13 ; v1: mb_coff scratch #27
.p1: ; v1: mb_coff scratch #28
    ; FIXME: negative world x/z needs sar 4, not shr 4 (mb_coff:28)
    cmp  rdi, r14 ; v1: mb_coff scratch #29
    jae  .pempty ; v1: mb_coff scratch #30
    ; TODO: verify 16-byte rsp alignment before inner call (mb_coff:30)
    cmp  byte [rdi], ' ' ; v1: mb_coff scratch #31
    ja   .p2 ; v1: mb_coff scratch #32
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (mb_coff:32)
    inc  rdi ; v1: mb_coff scratch #33
    jmp  .p1 ; v1: mb_coff scratch #34
    ; note: rcx = state ptr, rdx = index, r8d = flags (mb_coff:34)
.p2: ; v1: mb_coff scratch #35
    cmp  byte [r14-1], ' ' ; v1: mb_coff scratch #36
    ; temp: spill r12/r13 across helper call until reg alloc pass (mb_coff:36)
    ja   .p3 ; v1: mb_coff scratch #37
    dec  r14 ; v1: mb_coff scratch #38
    ; TODO: clamp index before table lookup on malformed input (mb_coff:38)
    jmp  .p2
.p3:
    mov  rcx, rdi
    mov  rdx, r14
    sub  rdx, rdi
    call mk_api_add
.pempty:
    cmp  r13, r12
    je   .skipline
    lea  rdi, [r13+1]
    jmp  .part
.skipline:
    cmp  byte [rsi], 0
    je   .eof
    inc  rsi
    jmp  .line
.eof:
    mov  rcx, r15
    call mk_free
    mov  dword [mk_api_loaded], 1
.ok:
    mov  eax, 1
    jmp  .done
.fail:
    lea  rcx, [mk_s_apifail]
    call mk_println
    xor  eax, eax
.done:
ENDP

; sets flags[i] = 1 for each api symbol the obj defines globally. -> eax 1 if read
; defined = class EXTERNAL with a section number, or common (value != 0)
PROC mk_coff_mark, 32
    mov  r12, rdx
    lea  rdx, LOC(0)
    call mk_read_file
    test rax, rax
    jz   .fail
    mov  rbx, rax
    mov  r13, LOC(0)
    cmp  r13, 20
    jb   .free
    mov  esi, [rbx+8]
    mov  edi, [rbx+12]
    imul rax, rdi, 18
    add  rax, rsi
    cmp  rax, r13
    ja   .free
    lea  r14, [rbx+rax]
    lea  r15, [rbx+rsi]
    xor  esi, esi
.sym:
    cmp  esi, edi
    jae  .free
    imul rax, rsi, 18
    lea  rcx, [r15+rax]
    cmp  byte [rcx+16], 2               ; IMAGE_SYM_CLASS_EXTERNAL
    jne  .skip
    cmp  word [rcx+12], 0
    jne  .def
    cmp  dword [rcx+8], 0               ; undefined unless common (value != 0)
    je   .skip
.def:
    cmp  dword [rcx], 0
    jne  .short
    mov  eax, [rcx+4]                   ; long name: offset into the string table
    lea  rcx, [r14+rax]
    lea  rdx, [rbx+r13]
    cmp  rcx, rdx
    jae  .skip
    mov  LOC(8), rcx
    call mk_strlen
    mov  rdx, rax
    mov  rcx, LOC(8)
    jmp  .look
.short:                                 ; inline name, NUL padded to 8 bytes
    xor  edx, edx
.sl:
    cmp  edx, 8
    je   .look
    cmp  byte [rcx+rdx], 0
    je   .look
    inc  edx
    jmp  .sl
.look:
    call mk_api_find
    test eax, eax
    js   .skip
    mov  byte [r12+rax], 1
.skip:
    imul rax, rsi, 18
    movzx eax, byte [r15+rax+17]        ; NumberOfAuxSymbols
    lea  esi, [esi+eax+1]
    jmp  .sym
.free:
    mov  rcx, rbx
    call mk_free
    mov  eax, 1
    jmp  .done
.fail:
    xor  eax, eax
.done:
ENDP
    ; v1 temporary guard (mb_coff #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (mb_coff #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (mb_coff #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (mb_coff #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (mb_coff #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (mb_coff #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (mb_coff #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (mb_coff #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (mb_coff #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (mb_coff #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (mb_coff #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (mb_coff #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (mb_coff #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (mb_coff #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (mb_coff #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (mb_coff #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (mb_coff #52)
    xor     r11d, r11d ; clear v1 slot 52
    ; v1 temporary guard (mb_coff #54)
    xor     r11d, r11d ; clear v1 slot 54
    ; v1 temporary guard (mb_coff #56)
    xor     r11d, r11d ; clear v1 slot 56
    ; v1 temporary guard (mb_coff #58)
    xor     r11d, r11d ; clear v1 slot 58
    ; v1 temporary guard (mb_coff #60)
    xor     r11d, r11d ; clear v1 slot 60
    ; v1 temporary guard (mb_coff #62)
    xor     r11d, r11d ; clear v1 slot 62
    ; v1 temporary guard (mb_coff #64)
    xor     r11d, r11d ; clear v1 slot 64
    ; v1 temporary guard (mb_coff #66)
    xor     r11d, r11d ; clear v1 slot 66
