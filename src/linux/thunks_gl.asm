; ms_abi -> sysv_abi thunks for libGL entry points (-f elf64 -DLINUX)
; game calls glFoo ms x64 style, these shuffle args into sysv order and call libGL.
; 1.1 ones are hidden so libGL's own exports stay untouched, real addresses come from
; dlsym in gl_thunks_init (gl_linux.asm), first call through an empty slot runs it.
; 2.0 ones sit behind pgl* like on windows, gl_load_functions fills both.
; frame: rsi/rdi go in the caller's shadow space, xmm6-15 below the sysv stack args.
bits 64
default rel

extern gl_thunk_lazy

section .rodata
gn_glAlphaFunc: db "glAlphaFunc", 0
gn_glBegin: db "glBegin", 0
gn_glBindTexture: db "glBindTexture", 0
gn_glBlendFunc: db "glBlendFunc", 0
gn_glCallList: db "glCallList", 0
gn_glClear: db "glClear", 0
gn_glClearColor: db "glClearColor", 0
gn_glClearDepth: db "glClearDepth", 0
gn_glColor3f: db "glColor3f", 0
gn_glColor3ub: db "glColor3ub", 0
gn_glColor4f: db "glColor4f", 0
gn_glColor4ub: db "glColor4ub", 0
gn_glColorMask: db "glColorMask", 0
gn_glColorPointer: db "glColorPointer", 0
gn_glCullFace: db "glCullFace", 0
gn_glDeleteLists: db "glDeleteLists", 0
gn_glDeleteTextures: db "glDeleteTextures", 0
gn_glDepthFunc: db "glDepthFunc", 0
gn_glDepthMask: db "glDepthMask", 0
gn_glDepthRange: db "glDepthRange", 0
gn_glDisable: db "glDisable", 0
gn_glDisableClientState: db "glDisableClientState", 0
gn_glDrawArrays: db "glDrawArrays", 0
gn_glDrawElements: db "glDrawElements", 0
gn_glEnable: db "glEnable", 0
gn_glEnableClientState: db "glEnableClientState", 0
gn_glEnd: db "glEnd", 0
gn_glEndList: db "glEndList", 0
gn_glFinish: db "glFinish", 0
gn_glFlush: db "glFlush", 0
gn_glFogf: db "glFogf", 0
gn_glFogfv: db "glFogfv", 0
gn_glFogi: db "glFogi", 0
gn_glFrontFace: db "glFrontFace", 0
gn_glFrustum: db "glFrustum", 0
gn_glGenLists: db "glGenLists", 0
gn_glGenTextures: db "glGenTextures", 0
gn_glGetBooleanv: db "glGetBooleanv", 0
gn_glGetError: db "glGetError", 0
gn_glGetFloatv: db "glGetFloatv", 0
gn_glGetIntegerv: db "glGetIntegerv", 0
gn_glGetString: db "glGetString", 0
gn_glGetTexImage: db "glGetTexImage", 0
gn_glGetTexLevelParameteriv: db "glGetTexLevelParameteriv", 0
gn_glGetTexParameteriv: db "glGetTexParameteriv", 0
gn_glHint: db "glHint", 0
gn_glIsEnabled: db "glIsEnabled", 0
gn_glLineWidth: db "glLineWidth", 0
gn_glLoadIdentity: db "glLoadIdentity", 0
gn_glLoadMatrixf: db "glLoadMatrixf", 0
gn_glMatrixMode: db "glMatrixMode", 0
gn_glMultMatrixf: db "glMultMatrixf", 0
gn_glNewList: db "glNewList", 0
gn_glNormal3f: db "glNormal3f", 0
gn_glOrtho: db "glOrtho", 0
gn_glPixelStorei: db "glPixelStorei", 0
gn_glPointSize: db "glPointSize", 0
gn_glPolygonOffset: db "glPolygonOffset", 0
gn_glPopMatrix: db "glPopMatrix", 0
gn_glPushMatrix: db "glPushMatrix", 0
gn_glReadPixels: db "glReadPixels", 0
gn_glRotated: db "glRotated", 0
gn_glRotatef: db "glRotatef", 0
gn_glScaled: db "glScaled", 0
gn_glScalef: db "glScalef", 0
gn_glScissor: db "glScissor", 0
gn_glShadeModel: db "glShadeModel", 0
gn_glTexCoord2f: db "glTexCoord2f", 0
gn_glTexCoordPointer: db "glTexCoordPointer", 0
gn_glTexEnvi: db "glTexEnvi", 0
gn_glTexImage2D: db "glTexImage2D", 0
gn_glTexParameterf: db "glTexParameterf", 0
gn_glTexParameteri: db "glTexParameteri", 0
gn_glTexSubImage2D: db "glTexSubImage2D", 0
gn_glTranslated: db "glTranslated", 0
gn_glTranslatef: db "glTranslatef", 0
gn_glVertex2f: db "glVertex2f", 0
gn_glVertex2i: db "glVertex2i", 0
gn_glVertex3f: db "glVertex3f", 0
gn_glVertexPointer: db "glVertexPointer", 0
gn_glViewport: db "glViewport", 0
gn_glGenBuffers: db "glGenBuffers", 0
gn_glDeleteBuffers: db "glDeleteBuffers", 0
gn_glBindBuffer: db "glBindBuffer", 0
gn_glBufferData: db "glBufferData", 0
gn_glBufferSubData: db "glBufferSubData", 0
gn_glCreateShader: db "glCreateShader", 0
gn_glShaderSource: db "glShaderSource", 0
gn_glCompileShader: db "glCompileShader", 0
gn_glGetShaderiv: db "glGetShaderiv", 0
gn_glGetShaderInfoLog: db "glGetShaderInfoLog", 0
gn_glDeleteShader: db "glDeleteShader", 0
gn_glCreateProgram: db "glCreateProgram", 0
gn_glAttachShader: db "glAttachShader", 0
gn_glLinkProgram: db "glLinkProgram", 0
gn_glGetProgramiv: db "glGetProgramiv", 0
gn_glGetProgramInfoLog: db "glGetProgramInfoLog", 0
gn_glDeleteProgram: db "glDeleteProgram", 0
gn_glUseProgram: db "glUseProgram", 0
gn_glGetUniformLocation: db "glGetUniformLocation", 0
gn_glUniform1f: db "glUniform1f", 0
gn_glUniform2f: db "glUniform2f", 0
gn_glUniform3f: db "glUniform3f", 0
gn_glUniform4f: db "glUniform4f", 0
gn_glUniform1i: db "glUniform1i", 0
gn_glUniformMatrix4fv: db "glUniformMatrix4fv", 0
gn_glBindAttribLocation: db "glBindAttribLocation", 0
gn_glVertexAttribPointer: db "glVertexAttribPointer", 0
gn_glEnableVertexAttribArray: db "glEnableVertexAttribArray", 0
gn_glDisableVertexAttribArray: db "glDisableVertexAttribArray", 0
gn_glActiveTexture: db "glActiveTexture", 0

section .data
align 8
; {name, real fn slot}
global gl1_table, gl1_table_end
gl1_table:
    dq gn_glAlphaFunc, gr_glAlphaFunc
    dq gn_glBegin, gr_glBegin
    dq gn_glBindTexture, gr_glBindTexture
    dq gn_glBlendFunc, gr_glBlendFunc
    dq gn_glCallList, gr_glCallList
    dq gn_glClear, gr_glClear
    dq gn_glClearColor, gr_glClearColor
    dq gn_glClearDepth, gr_glClearDepth
    dq gn_glColor3f, gr_glColor3f
    dq gn_glColor3ub, gr_glColor3ub
    dq gn_glColor4f, gr_glColor4f
    dq gn_glColor4ub, gr_glColor4ub
    dq gn_glColorMask, gr_glColorMask
    dq gn_glColorPointer, gr_glColorPointer
    dq gn_glCullFace, gr_glCullFace
    dq gn_glDeleteLists, gr_glDeleteLists
    dq gn_glDeleteTextures, gr_glDeleteTextures
    dq gn_glDepthFunc, gr_glDepthFunc
    dq gn_glDepthMask, gr_glDepthMask
    dq gn_glDepthRange, gr_glDepthRange
    dq gn_glDisable, gr_glDisable
    dq gn_glDisableClientState, gr_glDisableClientState
    dq gn_glDrawArrays, gr_glDrawArrays
    dq gn_glDrawElements, gr_glDrawElements
    dq gn_glEnable, gr_glEnable
    dq gn_glEnableClientState, gr_glEnableClientState
    dq gn_glEnd, gr_glEnd
    dq gn_glEndList, gr_glEndList
    dq gn_glFinish, gr_glFinish
    dq gn_glFlush, gr_glFlush
    dq gn_glFogf, gr_glFogf
    dq gn_glFogfv, gr_glFogfv
    dq gn_glFogi, gr_glFogi
    dq gn_glFrontFace, gr_glFrontFace
    dq gn_glFrustum, gr_glFrustum
    dq gn_glGenLists, gr_glGenLists
    dq gn_glGenTextures, gr_glGenTextures
    dq gn_glGetBooleanv, gr_glGetBooleanv
    dq gn_glGetError, gr_glGetError
    dq gn_glGetFloatv, gr_glGetFloatv
    dq gn_glGetIntegerv, gr_glGetIntegerv
    dq gn_glGetString, gr_glGetString
    dq gn_glGetTexImage, gr_glGetTexImage
    dq gn_glGetTexLevelParameteriv, gr_glGetTexLevelParameteriv
    dq gn_glGetTexParameteriv, gr_glGetTexParameteriv
    dq gn_glHint, gr_glHint
    dq gn_glIsEnabled, gr_glIsEnabled
    dq gn_glLineWidth, gr_glLineWidth
    dq gn_glLoadIdentity, gr_glLoadIdentity
    dq gn_glLoadMatrixf, gr_glLoadMatrixf
    dq gn_glMatrixMode, gr_glMatrixMode
    dq gn_glMultMatrixf, gr_glMultMatrixf
    dq gn_glNewList, gr_glNewList
    dq gn_glNormal3f, gr_glNormal3f
    dq gn_glOrtho, gr_glOrtho
    dq gn_glPixelStorei, gr_glPixelStorei
    dq gn_glPointSize, gr_glPointSize
    dq gn_glPolygonOffset, gr_glPolygonOffset
    dq gn_glPopMatrix, gr_glPopMatrix
    dq gn_glPushMatrix, gr_glPushMatrix
    dq gn_glReadPixels, gr_glReadPixels
    dq gn_glRotated, gr_glRotated
    dq gn_glRotatef, gr_glRotatef
    dq gn_glScaled, gr_glScaled
    dq gn_glScalef, gr_glScalef
    dq gn_glScissor, gr_glScissor
    dq gn_glShadeModel, gr_glShadeModel
    dq gn_glTexCoord2f, gr_glTexCoord2f
    dq gn_glTexCoordPointer, gr_glTexCoordPointer
    dq gn_glTexEnvi, gr_glTexEnvi
    dq gn_glTexImage2D, gr_glTexImage2D
    dq gn_glTexParameterf, gr_glTexParameterf
    dq gn_glTexParameteri, gr_glTexParameteri
    dq gn_glTexSubImage2D, gr_glTexSubImage2D
    dq gn_glTranslated, gr_glTranslated
    dq gn_glTranslatef, gr_glTranslatef
    dq gn_glVertex2f, gr_glVertex2f
    dq gn_glVertex2i, gr_glVertex2i
    dq gn_glVertex3f, gr_glVertex3f
    dq gn_glVertexPointer, gr_glVertexPointer
    dq gn_glViewport, gr_glViewport
gl1_table_end:
; {name, real fn slot, thunk, pgl slot, required}
global gl2_table, gl2_table_end
gl2_table:
    dq gn_glGenBuffers, gr_glGenBuffers, w_glGenBuffers, pglGenBuffers, 1
    dq gn_glDeleteBuffers, gr_glDeleteBuffers, w_glDeleteBuffers, pglDeleteBuffers, 1
    dq gn_glBindBuffer, gr_glBindBuffer, w_glBindBuffer, pglBindBuffer, 1
    dq gn_glBufferData, gr_glBufferData, w_glBufferData, pglBufferData, 1
    dq gn_glBufferSubData, gr_glBufferSubData, w_glBufferSubData, pglBufferSubData, 1
    dq gn_glCreateShader, gr_glCreateShader, w_glCreateShader, pglCreateShader, 1
    dq gn_glShaderSource, gr_glShaderSource, w_glShaderSource, pglShaderSource, 1
    dq gn_glCompileShader, gr_glCompileShader, w_glCompileShader, pglCompileShader, 1
    dq gn_glGetShaderiv, gr_glGetShaderiv, w_glGetShaderiv, pglGetShaderiv, 1
    dq gn_glGetShaderInfoLog, gr_glGetShaderInfoLog, w_glGetShaderInfoLog, pglGetShaderInfoLog, 1
    dq gn_glDeleteShader, gr_glDeleteShader, w_glDeleteShader, pglDeleteShader, 1
    dq gn_glCreateProgram, gr_glCreateProgram, w_glCreateProgram, pglCreateProgram, 1
    dq gn_glAttachShader, gr_glAttachShader, w_glAttachShader, pglAttachShader, 1
    dq gn_glLinkProgram, gr_glLinkProgram, w_glLinkProgram, pglLinkProgram, 1
    dq gn_glGetProgramiv, gr_glGetProgramiv, w_glGetProgramiv, pglGetProgramiv, 1
    dq gn_glGetProgramInfoLog, gr_glGetProgramInfoLog, w_glGetProgramInfoLog, pglGetProgramInfoLog, 1
    dq gn_glDeleteProgram, gr_glDeleteProgram, w_glDeleteProgram, pglDeleteProgram, 1
    dq gn_glUseProgram, gr_glUseProgram, w_glUseProgram, pglUseProgram, 1
    dq gn_glGetUniformLocation, gr_glGetUniformLocation, w_glGetUniformLocation, pglGetUniformLocation, 1
    dq gn_glUniform1f, gr_glUniform1f, w_glUniform1f, pglUniform1f, 1
    dq gn_glUniform2f, gr_glUniform2f, w_glUniform2f, pglUniform2f, 1
    dq gn_glUniform3f, gr_glUniform3f, w_glUniform3f, pglUniform3f, 1
    dq gn_glUniform4f, gr_glUniform4f, w_glUniform4f, pglUniform4f, 1
    dq gn_glUniform1i, gr_glUniform1i, w_glUniform1i, pglUniform1i, 1
    dq gn_glUniformMatrix4fv, gr_glUniformMatrix4fv, w_glUniformMatrix4fv, pglUniformMatrix4fv, 1
    dq gn_glBindAttribLocation, gr_glBindAttribLocation, w_glBindAttribLocation, pglBindAttribLocation, 1
    dq gn_glVertexAttribPointer, gr_glVertexAttribPointer, w_glVertexAttribPointer, pglVertexAttribPointer, 1
    dq gn_glEnableVertexAttribArray, gr_glEnableVertexAttribArray, w_glEnableVertexAttribArray, pglEnableVertexAttribArray, 1
    dq gn_glDisableVertexAttribArray, gr_glDisableVertexAttribArray, w_glDisableVertexAttribArray, pglDisableVertexAttribArray, 1
    dq gn_glActiveTexture, gr_glActiveTexture, w_glActiveTexture, pglActiveTexture, 1
gl2_table_end:

section .bss
alignb 8
gr_glAlphaFunc: resq 1
gr_glBegin: resq 1
gr_glBindTexture: resq 1
gr_glBlendFunc: resq 1
gr_glCallList: resq 1
gr_glClear: resq 1
gr_glClearColor: resq 1
gr_glClearDepth: resq 1
gr_glColor3f: resq 1
gr_glColor3ub: resq 1
gr_glColor4f: resq 1
gr_glColor4ub: resq 1
gr_glColorMask: resq 1
gr_glColorPointer: resq 1
gr_glCullFace: resq 1
gr_glDeleteLists: resq 1
gr_glDeleteTextures: resq 1
gr_glDepthFunc: resq 1
gr_glDepthMask: resq 1
gr_glDepthRange: resq 1
gr_glDisable: resq 1
gr_glDisableClientState: resq 1
gr_glDrawArrays: resq 1
gr_glDrawElements: resq 1
gr_glEnable: resq 1
gr_glEnableClientState: resq 1
gr_glEnd: resq 1
gr_glEndList: resq 1
gr_glFinish: resq 1
gr_glFlush: resq 1
gr_glFogf: resq 1
gr_glFogfv: resq 1
gr_glFogi: resq 1
gr_glFrontFace: resq 1
gr_glFrustum: resq 1
gr_glGenLists: resq 1
gr_glGenTextures: resq 1
gr_glGetBooleanv: resq 1
gr_glGetError: resq 1
gr_glGetFloatv: resq 1
gr_glGetIntegerv: resq 1
gr_glGetString: resq 1
gr_glGetTexImage: resq 1
gr_glGetTexLevelParameteriv: resq 1
gr_glGetTexParameteriv: resq 1
gr_glHint: resq 1
gr_glIsEnabled: resq 1
gr_glLineWidth: resq 1
gr_glLoadIdentity: resq 1
gr_glLoadMatrixf: resq 1
gr_glMatrixMode: resq 1
gr_glMultMatrixf: resq 1
gr_glNewList: resq 1
gr_glNormal3f: resq 1
gr_glOrtho: resq 1
gr_glPixelStorei: resq 1
gr_glPointSize: resq 1
gr_glPolygonOffset: resq 1
gr_glPopMatrix: resq 1
gr_glPushMatrix: resq 1
gr_glReadPixels: resq 1
gr_glRotated: resq 1
gr_glRotatef: resq 1
gr_glScaled: resq 1
gr_glScalef: resq 1
gr_glScissor: resq 1
gr_glShadeModel: resq 1
gr_glTexCoord2f: resq 1
gr_glTexCoordPointer: resq 1
gr_glTexEnvi: resq 1
gr_glTexImage2D: resq 1
gr_glTexParameterf: resq 1
gr_glTexParameteri: resq 1
gr_glTexSubImage2D: resq 1
gr_glTranslated: resq 1
gr_glTranslatef: resq 1
gr_glVertex2f: resq 1
gr_glVertex2i: resq 1
gr_glVertex3f: resq 1
gr_glVertexPointer: resq 1
gr_glViewport: resq 1
gr_glGenBuffers: resq 1
gr_glDeleteBuffers: resq 1
gr_glBindBuffer: resq 1
gr_glBufferData: resq 1
gr_glBufferSubData: resq 1
gr_glCreateShader: resq 1
gr_glShaderSource: resq 1
gr_glCompileShader: resq 1
gr_glGetShaderiv: resq 1
gr_glGetShaderInfoLog: resq 1
gr_glDeleteShader: resq 1
gr_glCreateProgram: resq 1
gr_glAttachShader: resq 1
gr_glLinkProgram: resq 1
gr_glGetProgramiv: resq 1
gr_glGetProgramInfoLog: resq 1
gr_glDeleteProgram: resq 1
gr_glUseProgram: resq 1
gr_glGetUniformLocation: resq 1
gr_glUniform1f: resq 1
gr_glUniform2f: resq 1
gr_glUniform3f: resq 1
gr_glUniform4f: resq 1
gr_glUniform1i: resq 1
gr_glUniformMatrix4fv: resq 1
gr_glBindAttribLocation: resq 1
gr_glVertexAttribPointer: resq 1
gr_glEnableVertexAttribArray: resq 1
gr_glDisableVertexAttribArray: resq 1
gr_glActiveTexture: resq 1
global pglGenBuffers
pglGenBuffers: resq 1
global pglDeleteBuffers
pglDeleteBuffers: resq 1
global pglBindBuffer
pglBindBuffer: resq 1
global pglBufferData
pglBufferData: resq 1
global pglBufferSubData
pglBufferSubData: resq 1
global pglCreateShader
pglCreateShader: resq 1
global pglShaderSource
pglShaderSource: resq 1
global pglCompileShader
pglCompileShader: resq 1
global pglGetShaderiv
pglGetShaderiv: resq 1
global pglGetShaderInfoLog
pglGetShaderInfoLog: resq 1
global pglDeleteShader
pglDeleteShader: resq 1
global pglCreateProgram
pglCreateProgram: resq 1
global pglAttachShader
pglAttachShader: resq 1
global pglLinkProgram
pglLinkProgram: resq 1
global pglGetProgramiv
pglGetProgramiv: resq 1
global pglGetProgramInfoLog
pglGetProgramInfoLog: resq 1
global pglDeleteProgram
pglDeleteProgram: resq 1
global pglUseProgram
pglUseProgram: resq 1
global pglGetUniformLocation
pglGetUniformLocation: resq 1
global pglUniform1f
pglUniform1f: resq 1
global pglUniform2f
pglUniform2f: resq 1
global pglUniform3f
pglUniform3f: resq 1
global pglUniform4f
pglUniform4f: resq 1
global pglUniform1i
pglUniform1i: resq 1
global pglUniformMatrix4fv
pglUniformMatrix4fv: resq 1
global pglBindAttribLocation
pglBindAttribLocation: resq 1
global pglVertexAttribPointer
pglVertexAttribPointer: resq 1
global pglEnableVertexAttribArray
pglEnableVertexAttribArray: resq 1
global pglDisableVertexAttribArray
pglDisableVertexAttribArray: resq 1
global pglActiveTexture
pglActiveTexture: resq 1

section .text
global glAlphaFunc:function hidden
align 16
glAlphaFunc:
    mov  rax, [rel gr_glAlphaFunc]
    test rax, rax
    jz   .lazy
    mov  [rsp+8], rsi
    mov  [rsp+16], rdi
    sub  rsp, 168
    movaps [rsp+0], xmm6
    movaps [rsp+16], xmm7
    movaps [rsp+32], xmm8
    movaps [rsp+48], xmm9
    movaps [rsp+64], xmm10
    movaps [rsp+80], xmm11
    movaps [rsp+96], xmm12
    movaps [rsp+112], xmm13
    movaps [rsp+128], xmm14
    movaps [rsp+144], xmm15
    mov  rdi, rcx
    movaps xmm0, xmm1
    call rax
    movaps xmm6, [rsp+0]
    movaps xmm7, [rsp+16]
    movaps xmm8, [rsp+32]
    movaps xmm9, [rsp+48]
    movaps xmm10, [rsp+64]
    movaps xmm11, [rsp+80]
    movaps xmm12, [rsp+96]
    movaps xmm13, [rsp+112]
    movaps xmm14, [rsp+128]
    movaps xmm15, [rsp+144]
    add  rsp, 168
    mov  rsi, [rsp+8]
    mov  rdi, [rsp+16]
    ret
.lazy:
    lea  rax, [rel glAlphaFunc]
    jmp  gl_thunk_lazy

global glBegin:function hidden
align 16
glBegin:
    mov  rax, [rel gr_glBegin]
    test rax, rax
    jz   .lazy
    mov  [rsp+8], rsi
    mov  [rsp+16], rdi
    sub  rsp, 168
    movaps [rsp+0], xmm6
    movaps [rsp+16], xmm7
    movaps [rsp+32], xmm8
    movaps [rsp+48], xmm9
    movaps [rsp+64], xmm10
    movaps [rsp+80], xmm11
    movaps [rsp+96], xmm12
    movaps [rsp+112], xmm13
    movaps [rsp+128], xmm14
    movaps [rsp+144], xmm15
    mov  rdi, rcx
    call rax
    movaps xmm6, [rsp+0]
    movaps xmm7, [rsp+16]
    movaps xmm8, [rsp+32]
    movaps xmm9, [rsp+48]
    movaps xmm10, [rsp+64]
    movaps xmm11, [rsp+80]
    movaps xmm12, [rsp+96]
    movaps xmm13, [rsp+112]
    movaps xmm14, [rsp+128]
    movaps xmm15, [rsp+144]
    add  rsp, 168
    mov  rsi, [rsp+8]
    mov  rdi, [rsp+16]
    ret
.lazy: ; v1: thunks_gl scratch #0
    ; temp: spill r12/r13 across helper call until reg alloc pass (thunks_gl:0)
    lea  rax, [rel glBegin] ; v1: thunks_gl scratch #1
    jmp  gl_thunk_lazy ; v1: thunks_gl scratch #2
    ; TODO: clamp index before table lookup on malformed input (thunks_gl:2)

global glBindTexture:function hidden ; v1: thunks_gl scratch #4
    ; note: rcx = state ptr, rdx = index, r8d = flags (thunks_gl:4)
align 16 ; v1: thunks_gl scratch #5
glBindTexture: ; v1: thunks_gl scratch #6
    ; FIXME: negative world x/z needs sar 4, not shr 4 (thunks_gl:6)
    mov  rax, [rel gr_glBindTexture] ; v1: thunks_gl scratch #7
    test rax, rax ; v1: thunks_gl scratch #8
    ; TODO: hoist invariant pointer load out of .loop (thunks_gl:8)
    jz   .lazy ; v1: thunks_gl scratch #9
    mov  [rsp+8], rsi ; v1: thunks_gl scratch #10
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (thunks_gl:10)
    mov  [rsp+16], rdi ; v1: thunks_gl scratch #11
    sub  rsp, 168 ; v1: thunks_gl scratch #12
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (thunks_gl:12)
    movaps [rsp+0], xmm6 ; v1: thunks_gl scratch #13
    movaps [rsp+16], xmm7 ; v1: thunks_gl scratch #14
    ; TODO: verify 16-byte rsp alignment before inner call (thunks_gl:14)
    movaps [rsp+32], xmm8 ; v1: thunks_gl scratch #15
    movaps [rsp+48], xmm9 ; v1: thunks_gl scratch #16
    ; temp: spill r12/r13 across helper call until reg alloc pass (thunks_gl:16)
    movaps [rsp+64], xmm10 ; v1: thunks_gl scratch #17
    movaps [rsp+80], xmm11 ; v1: thunks_gl scratch #18
    ; TODO: clamp index before table lookup on malformed input (thunks_gl:18)
    movaps [rsp+96], xmm12 ; v1: thunks_gl scratch #19
    movaps [rsp+112], xmm13 ; v1: thunks_gl scratch #20
    ; note: rcx = state ptr, rdx = index, r8d = flags (thunks_gl:20)
    movaps [rsp+128], xmm14 ; v1: thunks_gl scratch #21
    movaps [rsp+144], xmm15 ; v1: thunks_gl scratch #22
    ; FIXME: negative world x/z needs sar 4, not shr 4 (thunks_gl:22)
    mov  rdi, rcx ; v1: thunks_gl scratch #23
    mov  rsi, rdx ; v1: thunks_gl scratch #24
    ; TODO: hoist invariant pointer load out of .loop (thunks_gl:24)
    call rax ; v1: thunks_gl scratch #25
    movaps xmm6, [rsp+0] ; v1: thunks_gl scratch #26
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (thunks_gl:26)
    movaps xmm7, [rsp+16] ; v1: thunks_gl scratch #27
    movaps xmm8, [rsp+32] ; v1: thunks_gl scratch #28
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (thunks_gl:28)
    movaps xmm9, [rsp+48] ; v1: thunks_gl scratch #29
    movaps xmm10, [rsp+64] ; v1: thunks_gl scratch #30
    ; TODO: verify 16-byte rsp alignment before inner call (thunks_gl:30)
    movaps xmm11, [rsp+80] ; v1: thunks_gl scratch #31
    movaps xmm12, [rsp+96] ; v1: thunks_gl scratch #32
    ; temp: spill r12/r13 across helper call until reg alloc pass (thunks_gl:32)
    movaps xmm13, [rsp+112] ; v1: thunks_gl scratch #33
    movaps xmm14, [rsp+128] ; v1: thunks_gl scratch #34
    ; TODO: clamp index before table lookup on malformed input (thunks_gl:34)
    movaps xmm15, [rsp+144] ; v1: thunks_gl scratch #35
    add  rsp, 168 ; v1: thunks_gl scratch #36
    ; note: rcx = state ptr, rdx = index, r8d = flags (thunks_gl:36)
    mov  rsi, [rsp+8] ; v1: thunks_gl scratch #37
    mov  rdi, [rsp+16] ; v1: thunks_gl scratch #38
    ; FIXME: negative world x/z needs sar 4, not shr 4 (thunks_gl:38)
    ret ; v1: thunks_gl scratch #39
.lazy: ; v1: thunks_gl scratch #40
    ; TODO: hoist invariant pointer load out of .loop (thunks_gl:40)
    lea  rax, [rel glBindTexture] ; v1: thunks_gl scratch #41
    jmp  gl_thunk_lazy ; v1: thunks_gl scratch #42
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (thunks_gl:42)

global glBlendFunc:function hidden ; v1: thunks_gl scratch #44
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (thunks_gl:44)
align 16 ; v1: thunks_gl scratch #45
glBlendFunc: ; v1: thunks_gl scratch #46
    ; TODO: verify 16-byte rsp alignment before inner call (thunks_gl:46)
    mov  rax, [rel gr_glBlendFunc] ; v1: thunks_gl scratch #47
    test rax, rax ; v1: thunks_gl scratch #48
    ; temp: spill r12/r13 across helper call until reg alloc pass (thunks_gl:48)
    jz   .lazy ; v1: thunks_gl scratch #49
    mov  [rsp+8], rsi ; v1: thunks_gl scratch #50
    ; TODO: clamp index before table lookup on malformed input (thunks_gl:50)
    mov  [rsp+16], rdi ; v1: thunks_gl scratch #51
    sub  rsp, 168 ; v1: thunks_gl scratch #52
    ; note: rcx = state ptr, rdx = index, r8d = flags (thunks_gl:52)
    movaps [rsp+0], xmm6 ; v1: thunks_gl scratch #53
    movaps [rsp+16], xmm7 ; v1: thunks_gl scratch #54
    ; FIXME: negative world x/z needs sar 4, not shr 4 (thunks_gl:54)
    movaps [rsp+32], xmm8 ; v1: thunks_gl scratch #55
    movaps [rsp+48], xmm9 ; v1: thunks_gl scratch #56
    ; TODO: hoist invariant pointer load out of .loop (thunks_gl:56)
    movaps [rsp+64], xmm10
    movaps [rsp+80], xmm11
    movaps [rsp+96], xmm12
    movaps [rsp+112], xmm13
    movaps [rsp+128], xmm14
    movaps [rsp+144], xmm15
    mov  rdi, rcx
    mov  rsi, rdx
    call rax
    movaps xmm6, [rsp+0]
    movaps xmm7, [rsp+16]
    movaps xmm8, [rsp+32]
    movaps xmm9, [rsp+48]
    movaps xmm10, [rsp+64]
    movaps xmm11, [rsp+80]
    movaps xmm12, [rsp+96]
    movaps xmm13, [rsp+112]
    movaps xmm14, [rsp+128]
    movaps xmm15, [rsp+144]
    add  rsp, 168
    mov  rsi, [rsp+8]
    mov  rdi, [rsp+16]
    ret
.lazy:
    lea  rax, [rel glBlendFunc]
    jmp  gl_thunk_lazy

global glCallList:function hidden
align 16
glCallList:
    mov  rax, [rel gr_glCallList]
    test rax, rax
    jz   .lazy
    mov  [rsp+8], rsi
    mov  [rsp+16], rdi
    sub  rsp, 168
    movaps [rsp+0], xmm6
    movaps [rsp+16], xmm7
    movaps [rsp+32], xmm8
    movaps [rsp+48], xmm9
    movaps [rsp+64], xmm10
    movaps [rsp+80], xmm11
    movaps [rsp+96], xmm12
    movaps [rsp+112], xmm13
    movaps [rsp+128], xmm14
    movaps [rsp+144], xmm15
    mov  rdi, rcx
    call rax
    movaps xmm6, [rsp+0]
    movaps xmm7, [rsp+16]
    movaps xmm8, [rsp+32]
    movaps xmm9, [rsp+48]
    movaps xmm10, [rsp+64]
    movaps xmm11, [rsp+80]
    movaps xmm12, [rsp+96]
    movaps xmm13, [rsp+112]
    movaps xmm14, [rsp+128]
    movaps xmm15, [rsp+144]
    add  rsp, 168
    mov  rsi, [rsp+8]
    mov  rdi, [rsp+16]
    ret
.lazy:
    lea  rax, [rel glCallList]
    jmp  gl_thunk_lazy

global glClear:function hidden
align 16
glClear:
    mov  rax, [rel gr_glClear]
    test rax, rax
    jz   .lazy
    mov  [rsp+8], rsi
    mov  [rsp+16], rdi
    sub  rsp, 168
    movaps [rsp+0], xmm6
    movaps [rsp+16], xmm7
    movaps [rsp+32], xmm8
    movaps [rsp+48], xmm9
    movaps [rsp+64], xmm10
    movaps [rsp+80], xmm11
    movaps [rsp+96], xmm12
    movaps [rsp+112], xmm13
    movaps [rsp+128], xmm14
    movaps [rsp+144], xmm15
    mov  rdi, rcx
    call rax
    movaps xmm6, [rsp+0]
    movaps xmm7, [rsp+16]
    movaps xmm8, [rsp+32]
    movaps xmm9, [rsp+48]
    movaps xmm10, [rsp+64]
    movaps xmm11, [rsp+80]
    movaps xmm12, [rsp+96]
    movaps xmm13, [rsp+112]
    movaps xmm14, [rsp+128]
    movaps xmm15, [rsp+144]
    add  rsp, 168
    mov  rsi, [rsp+8]
    mov  rdi, [rsp+16]
    ret
.lazy:
    lea  rax, [rel glClear]
    jmp  gl_thunk_lazy

global glClearColor:function hidden
align 16
glClearColor:
    mov  rax, [rel gr_glClearColor]
    test rax, rax
    jz   .lazy
    mov  [rsp+8], rsi
    mov  [rsp+16], rdi
    sub  rsp, 168
    movaps [rsp+0], xmm6
    movaps [rsp+16], xmm7
    movaps [rsp+32], xmm8
    movaps [rsp+48], xmm9
    movaps [rsp+64], xmm10
    movaps [rsp+80], xmm11
    movaps [rsp+96], xmm12
    movaps [rsp+112], xmm13
    movaps [rsp+128], xmm14
    movaps [rsp+144], xmm15
    call rax
    movaps xmm6, [rsp+0]
    movaps xmm7, [rsp+16]
    movaps xmm8, [rsp+32]
    movaps xmm9, [rsp+48]
    movaps xmm10, [rsp+64]
    movaps xmm11, [rsp+80]
    movaps xmm12, [rsp+96]
    movaps xmm13, [rsp+112]
    movaps xmm14, [rsp+128]
    movaps xmm15, [rsp+144]
    add  rsp, 168
    mov  rsi, [rsp+8]
    mov  rdi, [rsp+16]
    ret
.lazy:
    lea  rax, [rel glClearColor]
    jmp  gl_thunk_lazy

global glClearDepth:function hidden
align 16
glClearDepth:
    mov  rax, [rel gr_glClearDepth]
    test rax, rax
    jz   .lazy
    mov  [rsp+8], rsi
    mov  [rsp+16], rdi
    sub  rsp, 168
    movaps [rsp+0], xmm6
    movaps [rsp+16], xmm7
    movaps [rsp+32], xmm8
    movaps [rsp+48], xmm9
    movaps [rsp+64], xmm10
    movaps [rsp+80], xmm11
    movaps [rsp+96], xmm12
    movaps [rsp+112], xmm13
    movaps [rsp+128], xmm14
    movaps [rsp+144], xmm15
    call rax
    movaps xmm6, [rsp+0]
    movaps xmm7, [rsp+16]
    movaps xmm8, [rsp+32]
    movaps xmm9, [rsp+48]
    movaps xmm10, [rsp+64]
    movaps xmm11, [rsp+80]
    movaps xmm12, [rsp+96]
    movaps xmm13, [rsp+112]
    movaps xmm14, [rsp+128]
    movaps xmm15, [rsp+144]
    add  rsp, 168
    mov  rsi, [rsp+8]
    mov  rdi, [rsp+16]
    ret
.lazy:
    lea  rax, [rel glClearDepth]
    jmp  gl_thunk_lazy

    ; v1 temporary guard (thunks_gl #29)
    xor     r11d, r11d ; clear v1 slot 29
    ; v1 temporary guard (thunks_gl #31)
    xor     r11d, r11d ; clear v1 slot 31
    ; v1 temporary guard (thunks_gl #33)
    xor     r11d, r11d ; clear v1 slot 33
    ; v1 temporary guard (thunks_gl #35)
    xor     r11d, r11d ; clear v1 slot 35
    ; v1 temporary guard (thunks_gl #37)
    xor     r11d, r11d ; clear v1 slot 37
    ; v1 temporary guard (thunks_gl #39)
    xor     r11d, r11d ; clear v1 slot 39
    ; v1 temporary guard (thunks_gl #41)
    xor     r11d, r11d ; clear v1 slot 41
    ; v1 temporary guard (thunks_gl #43)
    xor     r11d, r11d ; clear v1 slot 43
    ; v1 temporary guard (thunks_gl #45)
    xor     r11d, r11d ; clear v1 slot 45
    ; v1 temporary guard (thunks_gl #47)
    xor     r11d, r11d ; clear v1 slot 47
    ; v1 temporary guard (thunks_gl #49)
    xor     r11d, r11d ; clear v1 slot 49
    ; v1 temporary guard (thunks_gl #51)
    xor     r11d, r11d ; clear v1 slot 51
    ; v1 temporary guard (thunks_gl #53)
    xor     r11d, r11d ; clear v1 slot 53
    ; v1 temporary guard (thunks_gl #55)
    xor     r11d, r11d ; clear v1 slot 55
    ; v1 temporary guard (thunks_gl #57)
    xor     r11d, r11d ; clear v1 slot 57
    ; v1 temporary guard (thunks_gl #59)
    xor     r11d, r11d ; clear v1 slot 59
    ; v1 temporary guard (thunks_gl #61)
    xor     r11d, r11d ; clear v1 slot 61
    ; v1 temporary guard (thunks_gl #63)
    xor     r11d, r11d ; clear v1 slot 63
    ; v1 temporary guard (thunks_gl #65)
    xor     r11d, r11d ; clear v1 slot 65
    ; v1 temporary guard (thunks_gl #67)
    xor     r11d, r11d ; clear v1 slot 67
    ; v1 temporary guard (thunks_gl #69)
    xor     r11d, r11d ; clear v1 slot 69
    ; v1 temporary guard (thunks_gl #71)
    xor     r11d, r11d ; clear v1 slot 71
    ; v1 temporary guard (thunks_gl #73)
    xor     r11d, r11d ; clear v1 slot 73
    ; v1 temporary guard (thunks_gl #75)
    xor     r11d, r11d ; clear v1 slot 75
    ; v1 temporary guard (thunks_gl #77)
    xor     r11d, r11d ; clear v1 slot 77
    ; v1 temporary guard (thunks_gl #79)
    xor     r11d, r11d ; clear v1 slot 79
