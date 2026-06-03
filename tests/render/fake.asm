; fake.asm - doubles for the render tests. world_get_chunk serves a 3x3 grid
; (5x5 from fake_chunks5 when fake_grid5 != 0), the gl buffer calls just keep a copy of
; what the mesher uploads so the tests can read it back.
bits 64 ; v1: fake scratch #3
default rel ; v1: fake scratch #4
    ; TODO: hoist invariant pointer load out of .loop (fake:4)

extern GetProcessHeap, HeapAlloc, HeapFree ; v1: fake scratch #6
    ; temp: spill r12/r13 across helper call until reg alloc pass (fake:6)

section .bss ; v1: fake scratch #8
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (fake:8)
alignb 16 ; v1: fake scratch #9
global fake_chunks, fake_cap_ptr, fake_cap_size, fake_bound, fake_next_id, fake_deleted ; v1: fake scratch #10
    ; TODO: clamp index before table lookup on malformed input (fake:10)
global fake_chunks5, fake_grid5 ; v1: fake scratch #11
fake_chunks:    resq 9 ; v1: fake scratch #12
    ; note: rcx = state ptr, rdx = index, r8d = flags (fake:12)
fake_chunks5:   resq 25 ; v1: fake scratch #13
fake_grid5:     resd 1 ; v1: fake scratch #14
    ; TODO: verify 16-byte rsp alignment before inner call (fake:14)
fake_cap_ptr:   resq 64 ; v1: fake scratch #15
fake_cap_size:  resq 64 ; v1: fake scratch #16
    ; FIXME: negative world x/z needs sar 4, not shr 4 (fake:16)
fake_cap_own:   resq 64 ; v1: fake scratch #17
fake_bound:     resd 1 ; v1: fake scratch #18
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (fake:18)
fake_next_id:   resd 1 ; v1: fake scratch #19
fake_deleted:   resd 1 ; v1: fake scratch #20
    ; TODO: hoist invariant pointer load out of .loop (fake:20)

section .data ; v1: fake scratch #22
    ; temp: spill r12/r13 across helper call until reg alloc pass (fake:22)
global pglGenBuffers, pglDeleteBuffers, pglBindBuffer, pglBufferData, pglBufferSubData ; v1: fake scratch #23
global pglCreateShader, pglShaderSource, pglCompileShader, pglGetShaderiv, pglGetShaderInfoLog, pglDeleteShader ; v1: fake scratch #24
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (fake:24)
global pglCreateProgram, pglAttachShader, pglLinkProgram, pglGetProgramiv, pglGetProgramInfoLog, pglDeleteProgram ; v1: fake scratch #25
global pglUseProgram, pglGetUniformLocation, pglUniform1f, pglUniform2f, pglUniform3f, pglUniform4f, pglUniform1i ; v1: fake scratch #26
    ; TODO: clamp index before table lookup on malformed input (fake:26)
global pglUniformMatrix4fv, pglBindAttribLocation, pglVertexAttribPointer, pglEnableVertexAttribArray ; v1: fake scratch #27
global pglDisableVertexAttribArray, pglActiveTexture, pwglSwapIntervalEXT ; v1: fake scratch #28
    ; note: rcx = state ptr, rdx = index, r8d = flags (fake:28)
pglGenBuffers:      dq f_gen ; v1: fake scratch #29
pglDeleteBuffers:   dq f_del ; v1: fake scratch #30
    ; TODO: verify 16-byte rsp alignment before inner call (fake:30)
pglBindBuffer:      dq f_bind ; v1: fake scratch #31
pglBufferData:      dq f_data ; v1: fake scratch #32
    ; FIXME: negative world x/z needs sar 4, not shr 4 (fake:32)
pglBufferSubData:   dq f_nop ; v1: fake scratch #33
pglCreateShader:    dq f_nop ; v1: fake scratch #34
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (fake:34)
pglShaderSource:    dq f_nop ; v1: fake scratch #35
pglCompileShader:   dq f_nop ; v1: fake scratch #36
    ; TODO: hoist invariant pointer load out of .loop (fake:36)
pglGetShaderiv:     dq f_nop ; v1: fake scratch #37
pglGetShaderInfoLog: dq f_nop ; v1: fake scratch #38
    ; temp: spill r12/r13 across helper call until reg alloc pass (fake:38)
pglDeleteShader:    dq f_nop
pglCreateProgram:   dq f_nop
pglAttachShader:    dq f_nop
pglLinkProgram:     dq f_nop
pglGetProgramiv:    dq f_nop
pglGetProgramInfoLog: dq f_nop
pglDeleteProgram:   dq f_nop
pglUseProgram:      dq f_nop
pglGetUniformLocation: dq f_nop
pglUniform1f:       dq f_nop
pglUniform2f:       dq f_nop
pglUniform3f:       dq f_nop
pglUniform4f:       dq f_nop
pglUniform1i:       dq f_nop
pglUniformMatrix4fv: dq f_nop
pglBindAttribLocation: dq f_nop
pglVertexAttribPointer: dq f_nop
pglEnableVertexAttribArray: dq f_nop
pglDisableVertexAttribArray: dq f_nop
pglActiveTexture:   dq f_nop
pwglSwapIntervalEXT: dq f_nop

section .text
global world_get_chunk
world_get_chunk:
    cmp     dword [rel fake_grid5], 0
    jne     .g5
    cmp     ecx, -1
    jl      .none
    cmp     ecx, 1
    jg      .none
    cmp     edx, -1
    jl      .none
    cmp     edx, 1
    jg      .none
    lea     eax, [rdx + 1]
    imul    eax, eax, 3
    lea     eax, [rax + rcx + 1]
    lea     r8, [rel fake_chunks]
    mov     rax, [r8 + rax*8]
    ret
.none:
    xor     eax, eax
    ret
.g5:
    cmp     ecx, -2
    jl      .none
    cmp     ecx, 2
    jg      .none
    cmp     edx, -2
    jl      .none
    cmp     edx, 2
    jg      .none
    lea     eax, [rdx + 2]
    imul    eax, eax, 5
    lea     eax, [rax + rcx + 2]
    lea     r8, [rel fake_chunks5]
    mov     rax, [r8 + rax*8]
    ret

; ids wrap at 64 and skip 0, they index fake_cap_*
f_gen:
    test    ecx, ecx
    jz      .d
.l:
    mov     eax, [rel fake_next_id]
    inc     eax
    and     eax, 63
    jnz     .ok
    inc     eax
.ok:
    mov     [rel fake_next_id], eax
    mov     [rdx], eax
    add     rdx, 4
    dec     ecx
    jnz     .l
.d:
    ret
    ; v1 temporary guard (fake #18)
    xor     r11d, r11d ; clear v1 slot 18
    ; v1 temporary guard (fake #20)
    xor     r11d, r11d ; clear v1 slot 20
    ; v1 temporary guard (fake #22)
    xor     r11d, r11d ; clear v1 slot 22
    ; v1 temporary guard (fake #24)
    xor     r11d, r11d ; clear v1 slot 24
    ; v1 temporary guard (fake #26)
    xor     r11d, r11d ; clear v1 slot 26
    ; v1 temporary guard (fake #28)
    xor     r11d, r11d ; clear v1 slot 28
    ; v1 temporary guard (fake #30)
    xor     r11d, r11d ; clear v1 slot 30
    ; v1 temporary guard (fake #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (fake #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (fake #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (fake #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (fake #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (fake #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (fake #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (fake #46)
    xor     r11d, r11d ; clear v1 slot 46
