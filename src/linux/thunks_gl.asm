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
.lazy:
    lea  rax, [rel glBegin]
    jmp  gl_thunk_lazy

global glBindTexture:function hidden
align 16
glBindTexture:
    mov  rax, [rel gr_glBindTexture]
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
    lea  rax, [rel glBindTexture]
    jmp  gl_thunk_lazy

global glBlendFunc:function hidden
align 16
glBlendFunc:
    mov  rax, [rel gr_glBlendFunc]
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

global glColor3f:function hidden
align 16
glColor3f:
    mov  rax, [rel gr_glColor3f]
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
    lea  rax, [rel glColor3f]
    jmp  gl_thunk_lazy

global glColor3ub:function hidden
align 16
glColor3ub:
    mov  rax, [rel gr_glColor3ub]
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
    mov  rsi, rdx
    mov  rdx, r8
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
    lea  rax, [rel glColor3ub]
    jmp  gl_thunk_lazy

global glColor4f:function hidden
align 16
glColor4f:
    mov  rax, [rel gr_glColor4f]
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
    lea  rax, [rel glColor4f]
    jmp  gl_thunk_lazy

global glColor4ub:function hidden
align 16
glColor4ub:
    mov  rax, [rel gr_glColor4ub]
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
    mov  rsi, rdx
    mov  rdx, r8
    mov  rcx, r9
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
    lea  rax, [rel glColor4ub]
    jmp  gl_thunk_lazy

global glColorMask:function hidden
align 16
glColorMask:
    mov  rax, [rel gr_glColorMask]
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
    mov  rsi, rdx
    mov  rdx, r8
    mov  rcx, r9
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
    lea  rax, [rel glColorMask]
    jmp  gl_thunk_lazy

global glColorPointer:function hidden
align 16
glColorPointer:
    mov  rax, [rel gr_glColorPointer]
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
    mov  rsi, rdx
    mov  rdx, r8
    mov  rcx, r9
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
    lea  rax, [rel glColorPointer]
    jmp  gl_thunk_lazy

global glCullFace:function hidden
align 16
glCullFace:
    mov  rax, [rel gr_glCullFace]
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
    lea  rax, [rel glCullFace]
    jmp  gl_thunk_lazy

global glDeleteLists:function hidden
align 16
glDeleteLists:
    mov  rax, [rel gr_glDeleteLists]
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
    lea  rax, [rel glDeleteLists]
    jmp  gl_thunk_lazy

global glDeleteTextures:function hidden
align 16
glDeleteTextures:
    mov  rax, [rel gr_glDeleteTextures]
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
    lea  rax, [rel glDeleteTextures]
    jmp  gl_thunk_lazy

global glDepthFunc:function hidden
align 16
glDepthFunc:
    mov  rax, [rel gr_glDepthFunc]
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
    lea  rax, [rel glDepthFunc]
    jmp  gl_thunk_lazy

global glDepthMask:function hidden
align 16
glDepthMask:
    mov  rax, [rel gr_glDepthMask]
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
    lea  rax, [rel glDepthMask]
    jmp  gl_thunk_lazy

global glDepthRange:function hidden
align 16
glDepthRange:
    mov  rax, [rel gr_glDepthRange]
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
    lea  rax, [rel glDepthRange]
    jmp  gl_thunk_lazy

global glDisable:function hidden
align 16
glDisable:
    mov  rax, [rel gr_glDisable]
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
    lea  rax, [rel glDisable]
    jmp  gl_thunk_lazy

global glDisableClientState:function hidden
align 16
glDisableClientState:
    mov  rax, [rel gr_glDisableClientState]
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
    lea  rax, [rel glDisableClientState]
    jmp  gl_thunk_lazy

global glDrawArrays:function hidden
align 16
glDrawArrays:
    mov  rax, [rel gr_glDrawArrays]
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
    mov  rsi, rdx
    mov  rdx, r8
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
    lea  rax, [rel glDrawArrays]
    jmp  gl_thunk_lazy

global glDrawElements:function hidden
align 16
glDrawElements:
    mov  rax, [rel gr_glDrawElements]
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
    mov  rsi, rdx
    mov  rdx, r8
    mov  rcx, r9
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
    lea  rax, [rel glDrawElements]
    jmp  gl_thunk_lazy

global glEnable:function hidden
align 16
glEnable:
    mov  rax, [rel gr_glEnable]
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
    lea  rax, [rel glEnable]
    jmp  gl_thunk_lazy

global glEnableClientState:function hidden
align 16
glEnableClientState:
    mov  rax, [rel gr_glEnableClientState]
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
    lea  rax, [rel glEnableClientState]
    jmp  gl_thunk_lazy

global glEnd:function hidden
align 16
glEnd:
    mov  rax, [rel gr_glEnd]
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
    lea  rax, [rel glEnd]
    jmp  gl_thunk_lazy

global glEndList:function hidden
align 16
glEndList:
    mov  rax, [rel gr_glEndList]
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
    lea  rax, [rel glEndList]
    jmp  gl_thunk_lazy

global glFinish:function hidden
align 16
glFinish:
    mov  rax, [rel gr_glFinish]
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
    lea  rax, [rel glFinish]
    jmp  gl_thunk_lazy

global glFlush:function hidden
align 16
glFlush:
    mov  rax, [rel gr_glFlush]
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
    lea  rax, [rel glFlush]
    jmp  gl_thunk_lazy

global glFogf:function hidden
align 16
glFogf:
    mov  rax, [rel gr_glFogf]
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
    lea  rax, [rel glFogf]
    jmp  gl_thunk_lazy

global glFogfv:function hidden
align 16
glFogfv:
    mov  rax, [rel gr_glFogfv]
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
    lea  rax, [rel glFogfv]
    jmp  gl_thunk_lazy

global glFogi:function hidden
align 16
glFogi:
    mov  rax, [rel gr_glFogi]
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
    lea  rax, [rel glFogi]
    jmp  gl_thunk_lazy

global glFrontFace:function hidden
align 16
glFrontFace:
    mov  rax, [rel gr_glFrontFace]
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
    lea  rax, [rel glFrontFace]
    jmp  gl_thunk_lazy

global glFrustum:function hidden
align 16
glFrustum:
    mov  rax, [rel gr_glFrustum]
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
    movsd xmm4, [rsp+208]
    movsd xmm5, [rsp+216]
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
    lea  rax, [rel glFrustum]
    jmp  gl_thunk_lazy

global glGenLists:function hidden
align 16
glGenLists:
    mov  rax, [rel gr_glGenLists]
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
    lea  rax, [rel glGenLists]
    jmp  gl_thunk_lazy

global glGenTextures:function hidden
align 16
glGenTextures:
    mov  rax, [rel gr_glGenTextures]
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
    lea  rax, [rel glGenTextures]
    jmp  gl_thunk_lazy

global glGetBooleanv:function hidden
align 16
glGetBooleanv:
    mov  rax, [rel gr_glGetBooleanv]
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
    lea  rax, [rel glGetBooleanv]
    jmp  gl_thunk_lazy

global glGetError:function hidden
align 16
glGetError:
    mov  rax, [rel gr_glGetError]
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
    lea  rax, [rel glGetError]
    jmp  gl_thunk_lazy

global glGetFloatv:function hidden
align 16
glGetFloatv:
    mov  rax, [rel gr_glGetFloatv]
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
    lea  rax, [rel glGetFloatv]
    jmp  gl_thunk_lazy

global glGetIntegerv:function hidden
align 16
glGetIntegerv:
    mov  rax, [rel gr_glGetIntegerv]
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
    lea  rax, [rel glGetIntegerv]
    jmp  gl_thunk_lazy

global glGetString:function hidden
align 16
glGetString:
    mov  rax, [rel gr_glGetString]
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
    lea  rax, [rel glGetString]
    jmp  gl_thunk_lazy

global glGetTexImage:function hidden
align 16
glGetTexImage:
    mov  rax, [rel gr_glGetTexImage]
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
    mov  rsi, rdx
    mov  rdx, r8
    mov  rcx, r9
    mov  r8, [rsp+208]
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
    lea  rax, [rel glGetTexImage]
    jmp  gl_thunk_lazy

global glGetTexLevelParameteriv:function hidden
align 16
glGetTexLevelParameteriv:
    mov  rax, [rel gr_glGetTexLevelParameteriv]
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
    mov  rsi, rdx
    mov  rdx, r8
    mov  rcx, r9
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
    lea  rax, [rel glGetTexLevelParameteriv]
    jmp  gl_thunk_lazy

global glGetTexParameteriv:function hidden
align 16
glGetTexParameteriv:
    mov  rax, [rel gr_glGetTexParameteriv]
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
    mov  rsi, rdx
    mov  rdx, r8
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
    lea  rax, [rel glGetTexParameteriv]
    jmp  gl_thunk_lazy

global glHint:function hidden
align 16
glHint:
    mov  rax, [rel gr_glHint]
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
    lea  rax, [rel glHint]
    jmp  gl_thunk_lazy

global glIsEnabled:function hidden
align 16
glIsEnabled:
    mov  rax, [rel gr_glIsEnabled]
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
    movzx eax, al
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
    lea  rax, [rel glIsEnabled]
    jmp  gl_thunk_lazy

global glLineWidth:function hidden
align 16
glLineWidth:
    mov  rax, [rel gr_glLineWidth]
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
    lea  rax, [rel glLineWidth]
    jmp  gl_thunk_lazy

global glLoadIdentity:function hidden
align 16
glLoadIdentity:
    mov  rax, [rel gr_glLoadIdentity]
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
    lea  rax, [rel glLoadIdentity]
    jmp  gl_thunk_lazy

global glLoadMatrixf:function hidden
align 16
glLoadMatrixf:
    mov  rax, [rel gr_glLoadMatrixf]
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
    lea  rax, [rel glLoadMatrixf]
    jmp  gl_thunk_lazy

global glMatrixMode:function hidden
align 16
glMatrixMode:
    mov  rax, [rel gr_glMatrixMode]
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
    lea  rax, [rel glMatrixMode]
    jmp  gl_thunk_lazy

global glMultMatrixf:function hidden
align 16
glMultMatrixf:
    mov  rax, [rel gr_glMultMatrixf]
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
    lea  rax, [rel glMultMatrixf]
    jmp  gl_thunk_lazy

global glNewList:function hidden
align 16
glNewList:
    mov  rax, [rel gr_glNewList]
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
    lea  rax, [rel glNewList]
    jmp  gl_thunk_lazy

global glNormal3f:function hidden
align 16
glNormal3f:
    mov  rax, [rel gr_glNormal3f]
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
    lea  rax, [rel glNormal3f]
    jmp  gl_thunk_lazy

global glOrtho:function hidden
align 16
glOrtho:
    mov  rax, [rel gr_glOrtho]
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
    movsd xmm4, [rsp+208]
    movsd xmm5, [rsp+216]
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
    lea  rax, [rel glOrtho]
    jmp  gl_thunk_lazy

global glPixelStorei:function hidden
align 16
glPixelStorei:
    mov  rax, [rel gr_glPixelStorei]
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
    lea  rax, [rel glPixelStorei]
    jmp  gl_thunk_lazy

global glPointSize:function hidden
align 16
glPointSize:
    mov  rax, [rel gr_glPointSize]
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
    lea  rax, [rel glPointSize]
    jmp  gl_thunk_lazy

global glPolygonOffset:function hidden
align 16
glPolygonOffset:
    mov  rax, [rel gr_glPolygonOffset]
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
    lea  rax, [rel glPolygonOffset]
    jmp  gl_thunk_lazy

global glPopMatrix:function hidden
align 16
glPopMatrix:
    mov  rax, [rel gr_glPopMatrix]
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
    lea  rax, [rel glPopMatrix]
    jmp  gl_thunk_lazy

global glPushMatrix:function hidden
align 16
glPushMatrix:
    mov  rax, [rel gr_glPushMatrix]
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
    lea  rax, [rel glPushMatrix]
    jmp  gl_thunk_lazy

global glReadPixels:function hidden
align 16
glReadPixels:
    mov  rax, [rel gr_glReadPixels]
    test rax, rax
    jz   .lazy
    mov  [rsp+8], rsi
    mov  [rsp+16], rdi
    sub  rsp, 184
    movaps [rsp+16], xmm6
    movaps [rsp+32], xmm7
    movaps [rsp+48], xmm8
    movaps [rsp+64], xmm9
    movaps [rsp+80], xmm10
    movaps [rsp+96], xmm11
    movaps [rsp+112], xmm12
    movaps [rsp+128], xmm13
    movaps [rsp+144], xmm14
    movaps [rsp+160], xmm15
    mov  rdi, rcx
    mov  rsi, rdx
    mov  rdx, r8
    mov  rcx, r9
    mov  r8, [rsp+224]
    mov  r9, [rsp+232]
    mov  r11, [rsp+240]
    mov  [rsp+0], r11
    call rax
    movaps xmm6, [rsp+16]
    movaps xmm7, [rsp+32]
    movaps xmm8, [rsp+48]
    movaps xmm9, [rsp+64]
    movaps xmm10, [rsp+80]
    movaps xmm11, [rsp+96]
    movaps xmm12, [rsp+112]
    movaps xmm13, [rsp+128]
    movaps xmm14, [rsp+144]
    movaps xmm15, [rsp+160]
    add  rsp, 184
    mov  rsi, [rsp+8]
    mov  rdi, [rsp+16]
    ret
.lazy:
    lea  rax, [rel glReadPixels]
    jmp  gl_thunk_lazy

global glRotated:function hidden
align 16
glRotated:
    mov  rax, [rel gr_glRotated]
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
    lea  rax, [rel glRotated]
    jmp  gl_thunk_lazy

global glRotatef:function hidden
align 16
glRotatef:
    mov  rax, [rel gr_glRotatef]
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
    lea  rax, [rel glRotatef]
    jmp  gl_thunk_lazy

global glScaled:function hidden
align 16
glScaled:
    mov  rax, [rel gr_glScaled]
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
    lea  rax, [rel glScaled]
    jmp  gl_thunk_lazy

global glScalef:function hidden
align 16
glScalef:
    mov  rax, [rel gr_glScalef]
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
    lea  rax, [rel glScalef]
    jmp  gl_thunk_lazy

global glScissor:function hidden
align 16
glScissor:
    mov  rax, [rel gr_glScissor]
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
    mov  rsi, rdx
    mov  rdx, r8
    mov  rcx, r9
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
    lea  rax, [rel glScissor]
    jmp  gl_thunk_lazy

global glShadeModel:function hidden
align 16
glShadeModel:
    mov  rax, [rel gr_glShadeModel]
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
    lea  rax, [rel glShadeModel]
    jmp  gl_thunk_lazy

global glTexCoord2f:function hidden
align 16
glTexCoord2f:
    mov  rax, [rel gr_glTexCoord2f]
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
    lea  rax, [rel glTexCoord2f]
    jmp  gl_thunk_lazy

global glTexCoordPointer:function hidden
align 16
glTexCoordPointer:
    mov  rax, [rel gr_glTexCoordPointer]
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
    mov  rsi, rdx
    mov  rdx, r8
    mov  rcx, r9
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
    lea  rax, [rel glTexCoordPointer]
    jmp  gl_thunk_lazy

global glTexEnvi:function hidden
align 16
glTexEnvi:
    mov  rax, [rel gr_glTexEnvi]
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
    mov  rsi, rdx
    mov  rdx, r8
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
    lea  rax, [rel glTexEnvi]
    jmp  gl_thunk_lazy

global glTexImage2D:function hidden
align 16
glTexImage2D:
    mov  rax, [rel gr_glTexImage2D]
    test rax, rax
    jz   .lazy
    mov  [rsp+8], rsi
    mov  [rsp+16], rdi
    sub  rsp, 200
    movaps [rsp+32], xmm6
    movaps [rsp+48], xmm7
    movaps [rsp+64], xmm8
    movaps [rsp+80], xmm9
    movaps [rsp+96], xmm10
    movaps [rsp+112], xmm11
    movaps [rsp+128], xmm12
    movaps [rsp+144], xmm13
    movaps [rsp+160], xmm14
    movaps [rsp+176], xmm15
    mov  rdi, rcx
    mov  rsi, rdx
    mov  rdx, r8
    mov  rcx, r9
    mov  r8, [rsp+240]
    mov  r9, [rsp+248]
    mov  r11, [rsp+256]
    mov  [rsp+0], r11
    mov  r11, [rsp+264]
    mov  [rsp+8], r11
    mov  r11, [rsp+272]
    mov  [rsp+16], r11
    call rax
    movaps xmm6, [rsp+32]
    movaps xmm7, [rsp+48]
    movaps xmm8, [rsp+64]
    movaps xmm9, [rsp+80]
    movaps xmm10, [rsp+96]
    movaps xmm11, [rsp+112]
    movaps xmm12, [rsp+128]
    movaps xmm13, [rsp+144]
    movaps xmm14, [rsp+160]
    movaps xmm15, [rsp+176]
    add  rsp, 200
    mov  rsi, [rsp+8]
    mov  rdi, [rsp+16]
    ret
.lazy:
    lea  rax, [rel glTexImage2D]
    jmp  gl_thunk_lazy

global glTexParameterf:function hidden
align 16
glTexParameterf:
    mov  rax, [rel gr_glTexParameterf]
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
    mov  rsi, rdx
    movaps xmm0, xmm2
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
    lea  rax, [rel glTexParameterf]
    jmp  gl_thunk_lazy

global glTexParameteri:function hidden
align 16
glTexParameteri:
    mov  rax, [rel gr_glTexParameteri]
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
    mov  rsi, rdx
    mov  rdx, r8
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
    lea  rax, [rel glTexParameteri]
    jmp  gl_thunk_lazy

global glTexSubImage2D:function hidden
align 16
glTexSubImage2D:
    mov  rax, [rel gr_glTexSubImage2D]
    test rax, rax
    jz   .lazy
    mov  [rsp+8], rsi
    mov  [rsp+16], rdi
    sub  rsp, 200
    movaps [rsp+32], xmm6
    movaps [rsp+48], xmm7
    movaps [rsp+64], xmm8
    movaps [rsp+80], xmm9
    movaps [rsp+96], xmm10
    movaps [rsp+112], xmm11
    movaps [rsp+128], xmm12
    movaps [rsp+144], xmm13
    movaps [rsp+160], xmm14
    movaps [rsp+176], xmm15
    mov  rdi, rcx
    mov  rsi, rdx
    mov  rdx, r8
    mov  rcx, r9
    mov  r8, [rsp+240]
    mov  r9, [rsp+248]
    mov  r11, [rsp+256]
    mov  [rsp+0], r11
    mov  r11, [rsp+264]
    mov  [rsp+8], r11
    mov  r11, [rsp+272]
    mov  [rsp+16], r11
    call rax
    movaps xmm6, [rsp+32]
    movaps xmm7, [rsp+48]
    movaps xmm8, [rsp+64]
    movaps xmm9, [rsp+80]
    movaps xmm10, [rsp+96]
    movaps xmm11, [rsp+112]
    movaps xmm12, [rsp+128]
    movaps xmm13, [rsp+144]
    movaps xmm14, [rsp+160]
    movaps xmm15, [rsp+176]
    add  rsp, 200
    mov  rsi, [rsp+8]
    mov  rdi, [rsp+16]
    ret
.lazy:
    lea  rax, [rel glTexSubImage2D]
    jmp  gl_thunk_lazy

global glTranslated:function hidden
align 16
glTranslated:
    mov  rax, [rel gr_glTranslated]
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
    lea  rax, [rel glTranslated]
    jmp  gl_thunk_lazy

global glTranslatef:function hidden
align 16
glTranslatef:
    mov  rax, [rel gr_glTranslatef]
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
    lea  rax, [rel glTranslatef]
    jmp  gl_thunk_lazy

global glVertex2f:function hidden
align 16
glVertex2f:
    mov  rax, [rel gr_glVertex2f]
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
    lea  rax, [rel glVertex2f]
    jmp  gl_thunk_lazy

global glVertex2i:function hidden
align 16
glVertex2i:
    mov  rax, [rel gr_glVertex2i]
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
    lea  rax, [rel glVertex2i]
    jmp  gl_thunk_lazy

global glVertex3f:function hidden
align 16
glVertex3f:
    mov  rax, [rel gr_glVertex3f]
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
    lea  rax, [rel glVertex3f]
    jmp  gl_thunk_lazy

global glVertexPointer:function hidden
align 16
glVertexPointer:
    mov  rax, [rel gr_glVertexPointer]
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
    mov  rsi, rdx
    mov  rdx, r8
    mov  rcx, r9
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
    lea  rax, [rel glVertexPointer]
    jmp  gl_thunk_lazy

global glViewport:function hidden
align 16
glViewport:
    mov  rax, [rel gr_glViewport]
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
    mov  rsi, rdx
    mov  rdx, r8
    mov  rcx, r9
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
    lea  rax, [rel glViewport]
    jmp  gl_thunk_lazy

align 16
w_glGenBuffers:
    mov  rax, [rel gr_glGenBuffers]
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

align 16
w_glDeleteBuffers:
    mov  rax, [rel gr_glDeleteBuffers]
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

align 16
w_glBindBuffer:
    mov  rax, [rel gr_glBindBuffer]
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

align 16
w_glBufferData:
    mov  rax, [rel gr_glBufferData]
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
    mov  rsi, rdx
    mov  rdx, r8
    mov  rcx, r9
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

align 16
w_glBufferSubData:
    mov  rax, [rel gr_glBufferSubData]
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
    mov  rsi, rdx
    mov  rdx, r8
    mov  rcx, r9
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

align 16
w_glCreateShader:
    mov  rax, [rel gr_glCreateShader]
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

align 16
w_glShaderSource:
    mov  rax, [rel gr_glShaderSource]
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
    mov  rsi, rdx
    mov  rdx, r8
    mov  rcx, r9
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

align 16
w_glCompileShader:
    mov  rax, [rel gr_glCompileShader]
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

align 16
w_glGetShaderiv:
    mov  rax, [rel gr_glGetShaderiv]
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
    mov  rsi, rdx
    mov  rdx, r8
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

align 16
w_glGetShaderInfoLog:
    mov  rax, [rel gr_glGetShaderInfoLog]
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
    mov  rsi, rdx
    mov  rdx, r8
    mov  rcx, r9
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

align 16
w_glDeleteShader:
    mov  rax, [rel gr_glDeleteShader]
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

align 16
w_glCreateProgram:
    mov  rax, [rel gr_glCreateProgram]
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

align 16
w_glAttachShader:
    mov  rax, [rel gr_glAttachShader]
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

align 16
w_glLinkProgram:
    mov  rax, [rel gr_glLinkProgram]
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

align 16
w_glGetProgramiv:
    mov  rax, [rel gr_glGetProgramiv]
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
    mov  rsi, rdx
    mov  rdx, r8
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

align 16
w_glGetProgramInfoLog:
    mov  rax, [rel gr_glGetProgramInfoLog]
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
    mov  rsi, rdx
    mov  rdx, r8
    mov  rcx, r9
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

align 16
w_glDeleteProgram:
    mov  rax, [rel gr_glDeleteProgram]
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

align 16
w_glUseProgram:
    mov  rax, [rel gr_glUseProgram]
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

align 16
w_glGetUniformLocation:
    mov  rax, [rel gr_glGetUniformLocation]
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

align 16
w_glUniform1f:
    mov  rax, [rel gr_glUniform1f]
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

align 16 ; v1: thunks_gl scratch #1
w_glUniform2f: ; v1: thunks_gl scratch #2
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (thunks_gl:2)
    mov  rax, [rel gr_glUniform2f] ; v1: thunks_gl scratch #3
    mov  [rsp+8], rsi ; v1: thunks_gl scratch #4
    ; TODO: clamp index before table lookup on malformed input (thunks_gl:4)
    mov  [rsp+16], rdi ; v1: thunks_gl scratch #5
    sub  rsp, 168 ; v1: thunks_gl scratch #6
    ; note: rcx = state ptr, rdx = index, r8d = flags (thunks_gl:6)
    movaps [rsp+0], xmm6 ; v1: thunks_gl scratch #7
    movaps [rsp+16], xmm7 ; v1: thunks_gl scratch #8
    ; temp: spill r12/r13 across helper call until reg alloc pass (thunks_gl:8)
    movaps [rsp+32], xmm8 ; v1: thunks_gl scratch #9
    movaps [rsp+48], xmm9 ; v1: thunks_gl scratch #10
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (thunks_gl:10)
    movaps [rsp+64], xmm10 ; v1: thunks_gl scratch #11
    movaps [rsp+80], xmm11 ; v1: thunks_gl scratch #12
    ; TODO: verify 16-byte rsp alignment before inner call (thunks_gl:12)
    movaps [rsp+96], xmm12 ; v1: thunks_gl scratch #13
    movaps [rsp+112], xmm13 ; v1: thunks_gl scratch #14
    ; FIXME: negative world x/z needs sar 4, not shr 4 (thunks_gl:14)
    movaps [rsp+128], xmm14 ; v1: thunks_gl scratch #15
    movaps [rsp+144], xmm15 ; v1: thunks_gl scratch #16
    ; TODO: hoist invariant pointer load out of .loop (thunks_gl:16)
    mov  rdi, rcx ; v1: thunks_gl scratch #17
    movaps xmm0, xmm1 ; v1: thunks_gl scratch #18
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (thunks_gl:18)
    movaps xmm1, xmm2 ; v1: thunks_gl scratch #19
    call rax ; v1: thunks_gl scratch #20
    ; TODO: clamp index before table lookup on malformed input (thunks_gl:20)
    movaps xmm6, [rsp+0] ; v1: thunks_gl scratch #21
    movaps xmm7, [rsp+16] ; v1: thunks_gl scratch #22
    ; note: rcx = state ptr, rdx = index, r8d = flags (thunks_gl:22)
    movaps xmm8, [rsp+32] ; v1: thunks_gl scratch #23
    movaps xmm9, [rsp+48] ; v1: thunks_gl scratch #24
    ; temp: spill r12/r13 across helper call until reg alloc pass (thunks_gl:24)
    movaps xmm10, [rsp+64] ; v1: thunks_gl scratch #25
    movaps xmm11, [rsp+80] ; v1: thunks_gl scratch #26
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (thunks_gl:26)
    movaps xmm12, [rsp+96] ; v1: thunks_gl scratch #27
    movaps xmm13, [rsp+112] ; v1: thunks_gl scratch #28
    ; TODO: verify 16-byte rsp alignment before inner call (thunks_gl:28)
    movaps xmm14, [rsp+128] ; v1: thunks_gl scratch #29
    movaps xmm15, [rsp+144] ; v1: thunks_gl scratch #30
    ; FIXME: negative world x/z needs sar 4, not shr 4 (thunks_gl:30)
    add  rsp, 168 ; v1: thunks_gl scratch #31
    mov  rsi, [rsp+8] ; v1: thunks_gl scratch #32
    ; TODO: hoist invariant pointer load out of .loop (thunks_gl:32)
    mov  rdi, [rsp+16] ; v1: thunks_gl scratch #33
    ret ; v1: thunks_gl scratch #34
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (thunks_gl:34)

align 16 ; v1: thunks_gl scratch #36
    ; TODO: clamp index before table lookup on malformed input (thunks_gl:36)
w_glUniform3f: ; v1: thunks_gl scratch #37
    mov  rax, [rel gr_glUniform3f] ; v1: thunks_gl scratch #38
    ; note: rcx = state ptr, rdx = index, r8d = flags (thunks_gl:38)
    mov  [rsp+8], rsi ; v1: thunks_gl scratch #39
    mov  [rsp+16], rdi ; v1: thunks_gl scratch #40
    ; temp: spill r12/r13 across helper call until reg alloc pass (thunks_gl:40)
    sub  rsp, 168 ; v1: thunks_gl scratch #41
    movaps [rsp+0], xmm6 ; v1: thunks_gl scratch #42
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (thunks_gl:42)
    movaps [rsp+16], xmm7 ; v1: thunks_gl scratch #43
    movaps [rsp+32], xmm8 ; v1: thunks_gl scratch #44
    ; TODO: verify 16-byte rsp alignment before inner call (thunks_gl:44)
    movaps [rsp+48], xmm9 ; v1: thunks_gl scratch #45
    movaps [rsp+64], xmm10 ; v1: thunks_gl scratch #46
    ; FIXME: negative world x/z needs sar 4, not shr 4 (thunks_gl:46)
    movaps [rsp+80], xmm11 ; v1: thunks_gl scratch #47
    movaps [rsp+96], xmm12 ; v1: thunks_gl scratch #48
    ; TODO: hoist invariant pointer load out of .loop (thunks_gl:48)
    movaps [rsp+112], xmm13 ; v1: thunks_gl scratch #49
    movaps [rsp+128], xmm14 ; v1: thunks_gl scratch #50
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (thunks_gl:50)
    movaps [rsp+144], xmm15 ; v1: thunks_gl scratch #51
    mov  rdi, rcx ; v1: thunks_gl scratch #52
    ; TODO: clamp index before table lookup on malformed input (thunks_gl:52)
    movaps xmm0, xmm1 ; v1: thunks_gl scratch #53
    movaps xmm1, xmm2 ; v1: thunks_gl scratch #54
    ; note: rcx = state ptr, rdx = index, r8d = flags (thunks_gl:54)
    movaps xmm2, xmm3 ; v1: thunks_gl scratch #55
    call rax ; v1: thunks_gl scratch #56
    ; temp: spill r12/r13 across helper call until reg alloc pass (thunks_gl:56)
    movaps xmm6, [rsp+0] ; v1: thunks_gl scratch #57
    movaps xmm7, [rsp+16] ; v1: thunks_gl scratch #58
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (thunks_gl:58)
    movaps xmm8, [rsp+32] ; v1: thunks_gl scratch #59
    movaps xmm9, [rsp+48] ; v1: thunks_gl scratch #60
    ; TODO: verify 16-byte rsp alignment before inner call (thunks_gl:60)
    movaps xmm10, [rsp+64] ; v1: thunks_gl scratch #61
    movaps xmm11, [rsp+80] ; v1: thunks_gl scratch #62
    ; FIXME: negative world x/z needs sar 4, not shr 4 (thunks_gl:62)
    movaps xmm12, [rsp+96] ; v1: thunks_gl scratch #63
    movaps xmm13, [rsp+112] ; v1: thunks_gl scratch #64
    ; TODO: hoist invariant pointer load out of .loop (thunks_gl:64)
    movaps xmm14, [rsp+128] ; v1: thunks_gl scratch #65
    movaps xmm15, [rsp+144]
    add  rsp, 168
    mov  rsi, [rsp+8]
    mov  rdi, [rsp+16]
    ret

align 16
w_glUniform4f:
    mov  rax, [rel gr_glUniform4f]
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
    movaps xmm1, xmm2
    movaps xmm2, xmm3
    movss xmm3, [rsp+208]
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

align 16
w_glUniform1i:
    mov  rax, [rel gr_glUniform1i]
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

align 16
w_glUniformMatrix4fv:
    mov  rax, [rel gr_glUniformMatrix4fv]
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
    mov  rsi, rdx
    mov  rdx, r8
    mov  rcx, r9
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

align 16
w_glBindAttribLocation:
    mov  rax, [rel gr_glBindAttribLocation]
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
    mov  rsi, rdx
    mov  rdx, r8
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

align 16
w_glVertexAttribPointer:
    mov  rax, [rel gr_glVertexAttribPointer]
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
    mov  rsi, rdx
    mov  rdx, r8
    mov  rcx, r9
    mov  r8, [rsp+208]
    mov  r9, [rsp+216]
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
    ; v1 temporary guard (thunks_gl #32)
    xor     r11d, r11d ; clear v1 slot 32
    ; v1 temporary guard (thunks_gl #34)
    xor     r11d, r11d ; clear v1 slot 34
    ; v1 temporary guard (thunks_gl #36)
    xor     r11d, r11d ; clear v1 slot 36
    ; v1 temporary guard (thunks_gl #38)
    xor     r11d, r11d ; clear v1 slot 38
    ; v1 temporary guard (thunks_gl #40)
    xor     r11d, r11d ; clear v1 slot 40
    ; v1 temporary guard (thunks_gl #42)
    xor     r11d, r11d ; clear v1 slot 42
    ; v1 temporary guard (thunks_gl #44)
    xor     r11d, r11d ; clear v1 slot 44
    ; v1 temporary guard (thunks_gl #46)
    xor     r11d, r11d ; clear v1 slot 46
    ; v1 temporary guard (thunks_gl #48)
    xor     r11d, r11d ; clear v1 slot 48
    ; v1 temporary guard (thunks_gl #50)
    xor     r11d, r11d ; clear v1 slot 50
    ; v1 temporary guard (thunks_gl #52)
    xor     r11d, r11d ; clear v1 slot 52
    ; v1 temporary guard (thunks_gl #54)
    xor     r11d, r11d ; clear v1 slot 54
    ; v1 temporary guard (thunks_gl #56)
    xor     r11d, r11d ; clear v1 slot 56
    ; v1 temporary guard (thunks_gl #58)
    xor     r11d, r11d ; clear v1 slot 58
    ; v1 temporary guard (thunks_gl #60)
    xor     r11d, r11d ; clear v1 slot 60
    ; v1 temporary guard (thunks_gl #62)
    xor     r11d, r11d ; clear v1 slot 62
    ; v1 temporary guard (thunks_gl #64)
    xor     r11d, r11d ; clear v1 slot 64
    ; v1 temporary guard (thunks_gl #66)
    xor     r11d, r11d ; clear v1 slot 66
    ; v1 temporary guard (thunks_gl #68)
    xor     r11d, r11d ; clear v1 slot 68
    ; v1 temporary guard (thunks_gl #70)
    xor     r11d, r11d ; clear v1 slot 70
    ; v1 temporary guard (thunks_gl #72)
    xor     r11d, r11d ; clear v1 slot 72
    ; v1 temporary guard (thunks_gl #74)
    xor     r11d, r11d ; clear v1 slot 74
    ; v1 temporary guard (thunks_gl #76)
    xor     r11d, r11d ; clear v1 slot 76
    ; v1 temporary guard (thunks_gl #78)
    xor     r11d, r11d ; clear v1 slot 78
    ; v1 temporary guard (thunks_gl #80)
    xor     r11d, r11d ; clear v1 slot 80
    ; v1 temporary guard (thunks_gl #82)
    xor     r11d, r11d ; clear v1 slot 82
    ; v1 temporary guard (thunks_gl #84)
    xor     r11d, r11d ; clear v1 slot 84
    ; v1 temporary guard (thunks_gl #86)
    xor     r11d, r11d ; clear v1 slot 86
    ; v1 temporary guard (thunks_gl #88)
    xor     r11d, r11d ; clear v1 slot 88
    ; v1 temporary guard (thunks_gl #90)
    xor     r11d, r11d ; clear v1 slot 90
    ; v1 temporary guard (thunks_gl #92)
    xor     r11d, r11d ; clear v1 slot 92
    ; v1 temporary guard (thunks_gl #94)
    xor     r11d, r11d ; clear v1 slot 94
    ; v1 temporary guard (thunks_gl #96)
    xor     r11d, r11d ; clear v1 slot 96
    ; v1 temporary guard (thunks_gl #98)
    xor     r11d, r11d ; clear v1 slot 98
    ; v1 temporary guard (thunks_gl #100)
    xor     r11d, r11d ; clear v1 slot 100
    ; v1 temporary guard (thunks_gl #102)
    xor     r11d, r11d ; clear v1 slot 102
