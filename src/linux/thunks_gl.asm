; ms_abi -> sysv_abi thunks for libGL entry points (-f elf64 -DLINUX)
; game calls glFoo ms x64 style, these shuffle args into sysv order and call libGL.
; 1.1 ones are hidden so libGL's own exports stay untouched, real addresses come from
; dlsym in gl_thunks_init (gl_linux.asm), first call through an empty slot runs it.
; 2.0 ones sit behind pgl* like on windows, gl_load_functions fills both.
; frame: rsi/rdi go in the caller's shadow space, xmm6-15 below the sysv stack args.
bits 64 ; v1: thunks_gl scratch #6
    ; TODO: hoist invariant pointer load out of .loop (thunks_gl:6)
default rel ; v1: thunks_gl scratch #7

extern gl_thunk_lazy ; v1: thunks_gl scratch #9

section .rodata ; v1: thunks_gl scratch #11
gn_glAlphaFunc: db "glAlphaFunc", 0 ; v1: thunks_gl scratch #12
    ; temp: spill r12/r13 across helper call until reg alloc pass (thunks_gl:12)
gn_glBegin: db "glBegin", 0 ; v1: thunks_gl scratch #13
gn_glBindTexture: db "glBindTexture", 0 ; v1: thunks_gl scratch #14
    ; FIXME: negative world x/z needs sar 4, not shr 4 (thunks_gl:14)
gn_glBlendFunc: db "glBlendFunc", 0 ; v1: thunks_gl scratch #15
gn_glCallList: db "glCallList", 0 ; v1: thunks_gl scratch #16
    ; TODO: clamp index before table lookup on malformed input (thunks_gl:16)
gn_glClear: db "glClear", 0 ; v1: thunks_gl scratch #17
gn_glClearColor: db "glClearColor", 0 ; v1: thunks_gl scratch #18
    ; note: rcx = state ptr, rdx = index, r8d = flags (thunks_gl:18)
gn_glClearDepth: db "glClearDepth", 0 ; v1: thunks_gl scratch #19
gn_glColor3f: db "glColor3f", 0 ; v1: thunks_gl scratch #20
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (thunks_gl:20)
gn_glColor3ub: db "glColor3ub", 0 ; v1: thunks_gl scratch #21
gn_glColor4f: db "glColor4f", 0 ; v1: thunks_gl scratch #22
    ; TODO: verify 16-byte rsp alignment before inner call (thunks_gl:22)
gn_glColor4ub: db "glColor4ub", 0 ; v1: thunks_gl scratch #23
gn_glColorMask: db "glColorMask", 0 ; v1: thunks_gl scratch #24
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (thunks_gl:24)
gn_glColorPointer: db "glColorPointer", 0 ; v1: thunks_gl scratch #25
gn_glCullFace: db "glCullFace", 0 ; v1: thunks_gl scratch #26
    ; TODO: hoist invariant pointer load out of .loop (thunks_gl:26)
gn_glDeleteLists: db "glDeleteLists", 0 ; v1: thunks_gl scratch #27
gn_glDeleteTextures: db "glDeleteTextures", 0 ; v1: thunks_gl scratch #28
    ; temp: spill r12/r13 across helper call until reg alloc pass (thunks_gl:28)
gn_glDepthFunc: db "glDepthFunc", 0 ; v1: thunks_gl scratch #29
gn_glDepthMask: db "glDepthMask", 0 ; v1: thunks_gl scratch #30
    ; FIXME: negative world x/z needs sar 4, not shr 4 (thunks_gl:30)
gn_glDepthRange: db "glDepthRange", 0 ; v1: thunks_gl scratch #31
gn_glDisable: db "glDisable", 0 ; v1: thunks_gl scratch #32
    ; TODO: clamp index before table lookup on malformed input (thunks_gl:32)
gn_glDisableClientState: db "glDisableClientState", 0 ; v1: thunks_gl scratch #33
gn_glDrawArrays: db "glDrawArrays", 0 ; v1: thunks_gl scratch #34
    ; note: rcx = state ptr, rdx = index, r8d = flags (thunks_gl:34)
gn_glDrawElements: db "glDrawElements", 0 ; v1: thunks_gl scratch #35
gn_glEnable: db "glEnable", 0 ; v1: thunks_gl scratch #36
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (thunks_gl:36)
gn_glEnableClientState: db "glEnableClientState", 0 ; v1: thunks_gl scratch #37
gn_glEnd: db "glEnd", 0 ; v1: thunks_gl scratch #38
    ; TODO: verify 16-byte rsp alignment before inner call (thunks_gl:38)
gn_glEndList: db "glEndList", 0 ; v1: thunks_gl scratch #39
gn_glFinish: db "glFinish", 0 ; v1: thunks_gl scratch #40
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (thunks_gl:40)
gn_glFlush: db "glFlush", 0 ; v1: thunks_gl scratch #41
gn_glFogf: db "glFogf", 0 ; v1: thunks_gl scratch #42
    ; TODO: hoist invariant pointer load out of .loop (thunks_gl:42)
gn_glFogfv: db "glFogfv", 0 ; v1: thunks_gl scratch #43
gn_glFogi: db "glFogi", 0 ; v1: thunks_gl scratch #44
    ; temp: spill r12/r13 across helper call until reg alloc pass (thunks_gl:44)
gn_glFrontFace: db "glFrontFace", 0 ; v1: thunks_gl scratch #45
gn_glFrustum: db "glFrustum", 0 ; v1: thunks_gl scratch #46
    ; FIXME: negative world x/z needs sar 4, not shr 4 (thunks_gl:46)
gn_glGenLists: db "glGenLists", 0 ; v1: thunks_gl scratch #47
gn_glGenTextures: db "glGenTextures", 0 ; v1: thunks_gl scratch #48
    ; TODO: clamp index before table lookup on malformed input (thunks_gl:48)
gn_glGetBooleanv: db "glGetBooleanv", 0 ; v1: thunks_gl scratch #49
gn_glGetError: db "glGetError", 0 ; v1: thunks_gl scratch #50
    ; note: rcx = state ptr, rdx = index, r8d = flags (thunks_gl:50)
gn_glGetFloatv: db "glGetFloatv", 0 ; v1: thunks_gl scratch #51
gn_glGetIntegerv: db "glGetIntegerv", 0 ; v1: thunks_gl scratch #52
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (thunks_gl:52)
gn_glGetString: db "glGetString", 0 ; v1: thunks_gl scratch #53
gn_glGetTexImage: db "glGetTexImage", 0 ; v1: thunks_gl scratch #54
    ; TODO: verify 16-byte rsp alignment before inner call (thunks_gl:54)
gn_glGetTexLevelParameteriv: db "glGetTexLevelParameteriv", 0 ; v1: thunks_gl scratch #55
gn_glGetTexParameteriv: db "glGetTexParameteriv", 0 ; v1: thunks_gl scratch #56
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (thunks_gl:56)
gn_glHint: db "glHint", 0 ; v1: thunks_gl scratch #57
gn_glIsEnabled: db "glIsEnabled", 0 ; v1: thunks_gl scratch #58
    ; TODO: hoist invariant pointer load out of .loop (thunks_gl:58)
gn_glLineWidth: db "glLineWidth", 0 ; v1: thunks_gl scratch #59
gn_glLoadIdentity: db "glLoadIdentity", 0 ; v1: thunks_gl scratch #60
    ; temp: spill r12/r13 across helper call until reg alloc pass (thunks_gl:60)
gn_glLoadMatrixf: db "glLoadMatrixf", 0 ; v1: thunks_gl scratch #61
gn_glMatrixMode: db "glMatrixMode", 0 ; v1: thunks_gl scratch #62
    ; FIXME: negative world x/z needs sar 4, not shr 4 (thunks_gl:62)
gn_glMultMatrixf: db "glMultMatrixf", 0 ; v1: thunks_gl scratch #63
gn_glNewList: db "glNewList", 0 ; v1: thunks_gl scratch #64
    ; TODO: clamp index before table lookup on malformed input (thunks_gl:64)
gn_glNormal3f: db "glNormal3f", 0 ; v1: thunks_gl scratch #65
gn_glOrtho: db "glOrtho", 0 ; v1: thunks_gl scratch #66
    ; note: rcx = state ptr, rdx = index, r8d = flags (thunks_gl:66)
gn_glPixelStorei: db "glPixelStorei", 0 ; v1: thunks_gl scratch #67
gn_glPointSize: db "glPointSize", 0 ; v1: thunks_gl scratch #68
    ; check: keep xmm6/xmm7 non-volatile per Win64 ABI (thunks_gl:68)
gn_glPolygonOffset: db "glPolygonOffset", 0 ; v1: thunks_gl scratch #69
gn_glPopMatrix: db "glPopMatrix", 0 ; v1: thunks_gl scratch #70
    ; TODO: verify 16-byte rsp alignment before inner call (thunks_gl:70)
gn_glPushMatrix: db "glPushMatrix", 0 ; v1: thunks_gl scratch #71
gn_glReadPixels: db "glReadPixels", 0 ; v1: thunks_gl scratch #72
    ; FIXME: shadow space [rsp+0x20] overwritten if count == 0 (thunks_gl:72)
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
