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
.tt:
    cmp  byte [r12-1], ' '
    ja   .ttd
    dec  r12
    jmp  .tt
.ttd:
    mov  rax, r12
    sub  rax, rdi
    cmp  rax, 7
    jb   .skipline
    cmp  dword [rdi], 'exte'
    jne  .skipline
    cmp  word [rdi+4], 'rn'
    jne  .skipline
    cmp  byte [rdi+6], ' '
    jne  .skipline
    add  rdi, 7
.part:                                  ; split the rest on ','
    mov  r13, rdi
.pe:
    cmp  r13, r12
    je   .pend
    cmp  byte [r13], ','
    je   .pend
    inc  r13
    jmp  .pe
.pend:
    mov  r14, r13
.p1:
    cmp  rdi, r14
    jae  .pempty
    cmp  byte [rdi], ' '
    ja   .p2
    inc  rdi
    jmp  .p1
.p2:
    cmp  byte [r14-1], ' '
    ja   .p3
    dec  r14
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

; data-looking names (g_, blk_, ...) get a resb stub instead of a function
PROC mk_is_data
    mov  rbx, rcx
    lea  rsi, [mk_data_hints]
.l: mov  rdx, [rsi]
    test rdx, rdx
    jz   .no
    mov  rcx, rbx
    call mk_startswith
    test eax, eax
    jnz  .done
    add  rsi, 8
    jmp  .l
.no:
    xor  eax, eax
.done:
ENDP

; mk_make_stubs(rcx objs, edx count, r8 out dir, r9 names buf or 0) -> eax missing count.
; if nonzero writes <out dir>\stubs.asm (data: 256 KB of zeroes, functions: return 0)
; and appends the missing names to r9. needs mk_api_load first.
PROC mk_make_stubs, MK_PATH+64
    mov  rbx, rcx
    mov  r12d, edx
    mov  r13, r8
    mov  r14, r9
    mov  ecx, [mk_api_count]
    inc  ecx
    call mk_alloc
    mov  r15, rax                       ; defined flags
    xor  esi, esi
.o: cmp  esi, r12d
    jae  .od
    mov  rcx, [rbx+rsi*8]
    mov  rdx, r15
    call mk_coff_mark
    inc  esi
    jmp  .o
.od:
    xor  eax, eax
    mov  LOC(0), rax
    mov  LOC(8), rax
    mov  LOC(16), rax
    lea  rcx, LOC(0)
    lea  rdx, [mk_s_stub_head]
    call mk_buf_addz
    xor  esi, esi
    xor  edi, edi
.d: cmp  esi, [mk_api_count]
    jae  .dd
    cmp  byte [r15+rsi], 0
    jne  .dn
    inc  edi
    mov  rax, [mk_api_names]
    mov  rax, [rax+rsi*8]
    mov  LOC(24), rax
    test r14, r14
    jz   .nolist
    cmp  qword [r14+MK_BUF_LEN], 0
    je   .first
    mov  rcx, r14
    mov  edx, ' '
    call mk_buf_addc
.first:
    mov  rcx, r14
    mov  rdx, LOC(24)
    call mk_buf_addz
.nolist:
    mov  rcx, LOC(24)
    call mk_is_data
    test eax, eax
    jz   .dn
    lea  rcx, LOC(0)
    lea  rdx, [mk_s_global]
    call mk_buf_addz
    lea  rcx, LOC(0)
    mov  rdx, LOC(24)
    call mk_buf_addz
    lea  rcx, LOC(0)
    lea  rdx, [mk_s_alignb]
    call mk_buf_addz
    lea  rcx, LOC(0)
    mov  rdx, LOC(24)
    call mk_buf_addz
    lea  rcx, LOC(0)
    lea  rdx, [mk_s_resb]
    call mk_buf_addz
.dn:
    inc  esi
    jmp  .d
.dd:
    lea  rcx, LOC(0)
    lea  rdx, [mk_s_stub_text]
    call mk_buf_addz
    xor  esi, esi
.f: cmp  esi, [mk_api_count]
    jae  .fd
    cmp  byte [r15+rsi], 0
    jne  .fn
    mov  rax, [mk_api_names]
    mov  rax, [rax+rsi*8]
    mov  LOC(24), rax
    mov  rcx, rax
    call mk_is_data
    test eax, eax
    jnz  .fn
    lea  rcx, LOC(0)
    lea  rdx, [mk_s_global]
    call mk_buf_addz
    lea  rcx, LOC(0)
    mov  rdx, LOC(24)
    call mk_buf_addz
    lea  rcx, LOC(0)
    lea  rdx, [mk_s_crlf]
    call mk_buf_addz
    lea  rcx, LOC(0)
    mov  rdx, LOC(24)
    call mk_buf_addz
    lea  rcx, LOC(0)
    lea  rdx, [mk_s_fnbody]
    call mk_buf_addz
.fn:
    inc  esi
    jmp  .f
.fd:
    test edi, edi
    jz   .nofile
    lea  rcx, LOC(32)
    mov  rdx, r13
    lea  r8, [mk_s_stubs_asm]
    call mk_path_join
    lea  rcx, LOC(32)
    mov  rdx, LOC(0)
    mov  r8, LOC(8)
    call mk_write_file
.nofile:
    lea  rcx, LOC(0)
    call mk_buf_free
    mov  rcx, r15
    call mk_free
    mov  eax, edi
ENDP
