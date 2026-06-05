; fake.asm - doubles for the render tests. world_get_chunk serves a 3x3 grid
; (5x5 from fake_chunks5 when fake_grid5 != 0), the gl buffer calls just keep a copy of
; what the mesher uploads so the tests can read it back.
bits 64
default rel

extern GetProcessHeap, HeapAlloc, HeapFree

section .bss
alignb 16
global fake_chunks, fake_cap_ptr, fake_cap_size, fake_bound, fake_next_id, fake_deleted
global fake_chunks5, fake_grid5
fake_chunks:    resq 9
fake_chunks5:   resq 25
fake_grid5:     resd 1
fake_cap_ptr:   resq 64
fake_cap_size:  resq 64
fake_cap_own:   resq 64             ; our copies
fake_bound:     resd 1
fake_next_id:   resd 1
fake_deleted:   resd 1

section .data
global pglGenBuffers, pglDeleteBuffers, pglBindBuffer, pglBufferData, pglBufferSubData
global pglCreateShader, pglShaderSource, pglCompileShader, pglGetShaderiv, pglGetShaderInfoLog, pglDeleteShader
global pglCreateProgram, pglAttachShader, pglLinkProgram, pglGetProgramiv, pglGetProgramInfoLog, pglDeleteProgram
global pglUseProgram, pglGetUniformLocation, pglUniform1f, pglUniform2f, pglUniform3f, pglUniform4f, pglUniform1i
global pglUniformMatrix4fv, pglBindAttribLocation, pglVertexAttribPointer, pglEnableVertexAttribArray
global pglDisableVertexAttribArray, pglActiveTexture, pwglSwapIntervalEXT
pglGenBuffers:      dq f_gen
pglDeleteBuffers:   dq f_del
pglBindBuffer:      dq f_bind
pglBufferData:      dq f_data
pglBufferSubData:   dq f_nop
pglCreateShader:    dq f_nop
pglShaderSource:    dq f_nop
pglCompileShader:   dq f_nop
pglGetShaderiv:     dq f_nop
pglGetShaderInfoLog: dq f_nop
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

f_bind:
    mov     [rel fake_bound], edx
    ret

; copies, like the real thing: mesher job buffers get reused by the next job.
; NULL data (allocate only) records a NULL pointer
f_data:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    sub     rsp, 40
    mov     ebx, [rel fake_bound]
    and     ebx, 63
    mov     rsi, r8
    mov     r12, rdx
    lea     r10, [rel fake_cap_size]
    mov     [r10 + rbx*8], rdx
    lea     r10, [rel fake_cap_ptr]
    mov     qword [r10 + rbx*8], 0
    lea     r10, [rel fake_cap_own]
    mov     rdi, [r10 + rbx*8]
    test    rdi, rdi
    jz      .nofree
    mov     qword [r10 + rbx*8], 0
    call    GetProcessHeap
    mov     rcx, rax
    xor     edx, edx
    mov     r8, rdi
    call    HeapFree
.nofree:
    test    rsi, rsi
    jz      .done
    call    GetProcessHeap
    mov     rcx, rax
    xor     edx, edx
    lea     r8, [r12 + 16]
    call    HeapAlloc
    test    rax, rax
    jz      .done
    lea     r10, [rel fake_cap_own]
    mov     [r10 + rbx*8], rax
    lea     r10, [rel fake_cap_ptr]
    mov     [r10 + rbx*8], rax
    mov     rdi, rax
    mov     rcx, r12
    rep     movsb
.done:
    add     rsp, 40
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

f_del:
    inc     dword [rel fake_deleted]
    ret

f_nop:
    xor     eax, eax
    ret
