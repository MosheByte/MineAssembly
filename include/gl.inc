; opengl32.dll only has 1.1, everything newer is a pgl* pointer -> call [rel pglFoo]
; glOrtho/glFrustum want doubles, watch out
%ifndef GL_INC
%define GL_INC

extern glClear, glClearColor, glClearDepth, glViewport, glEnable, glDisable, glBlendFunc
extern glDepthFunc, glDepthMask, glCullFace, glFrontFace, glAlphaFunc, glPolygonOffset, glLineWidth
extern glMatrixMode, glLoadIdentity, glLoadMatrixf, glMultMatrixf, glPushMatrix, glPopMatrix
extern glTranslatef, glRotatef, glScalef, glOrtho, glFrustum
extern glBegin, glEnd, glVertex2f, glVertex3f, glVertex2i, glTexCoord2f, glColor3f, glColor4f, glColor4ub, glNormal3f
extern glGenTextures, glDeleteTextures, glBindTexture, glTexImage2D, glTexSubImage2D, glTexParameteri, glTexEnvi
extern glEnableClientState, glDisableClientState, glVertexPointer, glTexCoordPointer, glColorPointer, glDrawArrays, glDrawElements
extern glGetFloatv, glGetIntegerv, glGetString, glGetError, glReadPixels, glPixelStorei, glFinish, glFlush
extern glFogi, glFogf, glFogfv, glHint, glShadeModel, glScissor, glColorMask, glPointSize
extern glNewList, glEndList, glCallList, glGenLists, glDeleteLists
extern wglCreateContext, wglMakeCurrent, wglDeleteContext, wglGetProcAddress

%ifndef IMPL_GL
extern pglGenBuffers, pglDeleteBuffers, pglBindBuffer, pglBufferData, pglBufferSubData
extern pglCreateShader, pglShaderSource, pglCompileShader, pglGetShaderiv, pglGetShaderInfoLog, pglDeleteShader
extern pglCreateProgram, pglAttachShader, pglLinkProgram, pglGetProgramiv, pglGetProgramInfoLog, pglDeleteProgram
extern pglUseProgram, pglGetUniformLocation, pglUniform1f, pglUniform2f, pglUniform3f, pglUniform4f, pglUniform1i
extern pglUniformMatrix4fv, pglBindAttribLocation, pglVertexAttribPointer, pglEnableVertexAttribArray
extern pglDisableVertexAttribArray, pglActiveTexture, pwglSwapIntervalEXT
%endif

%define GL_DEPTH_BUFFER_BIT     0x00000100
%define GL_COLOR_BUFFER_BIT     0x00004000
%define GL_POINTS               0x0000
%define GL_LINES                0x0001
%define GL_LINE_LOOP            0x0002
%define GL_LINE_STRIP           0x0003
%define GL_TRIANGLES            0x0004
%define GL_TRIANGLE_STRIP       0x0005
%define GL_TRIANGLE_FAN         0x0006
%define GL_QUADS                0x0007
%define GL_NEVER                0x0200
%define GL_LESS                 0x0201
%define GL_EQUAL                0x0202
%define GL_LEQUAL               0x0203
%define GL_GREATER              0x0204
%define GL_ALWAYS               0x0207
%define GL_SRC_ALPHA            0x0302
%define GL_ONE_MINUS_SRC_ALPHA  0x0303
%define GL_ONE                  1
%define GL_ZERO                 0
%define GL_DST_COLOR            0x0306
%define GL_FRONT                0x0404
%define GL_BACK                 0x0405
%define GL_CW                   0x0900
%define GL_CCW                  0x0901
%define GL_CULL_FACE            0x0B44
%define GL_FOG                  0x0B60
%define GL_DEPTH_TEST           0x0B71
%define GL_ALPHA_TEST           0x0BC0
%define GL_BLEND                0x0BE2
%define GL_SCISSOR_TEST         0x0C11
%define GL_TEXTURE_2D           0x0DE1
%define GL_LINE_SMOOTH          0x0B20
%define GL_POLYGON_OFFSET_FILL  0x8037
%define GL_POLYGON_OFFSET_LINE  0x2A02
%define GL_MODELVIEW            0x1700
%define GL_PROJECTION           0x1701
%define GL_TEXTURE              0x1702
%define GL_MODELVIEW_MATRIX     0x0BA6
%define GL_PROJECTION_MATRIX    0x0BA7
%define GL_VIEWPORT             0x0BA2
%define GL_UNSIGNED_BYTE        0x1401
%define GL_UNSIGNED_SHORT       0x1403
%define GL_UNSIGNED_INT         0x1405
%define GL_FLOAT                0x1406
%define GL_RGB                  0x1907
%define GL_RGBA                 0x1908
%define GL_BGR                  0x80E0
%define GL_BGRA                 0x80E1
%define GL_VENDOR               0x1F00
%define GL_RENDERER             0x1F01
%define GL_VERSION              0x1F02
%define GL_NEAREST              0x2600
%define GL_LINEAR               0x2601
%define GL_NEAREST_MIPMAP_NEAREST 0x2700
%define GL_LINEAR_MIPMAP_NEAREST  0x2701
%define GL_NEAREST_MIPMAP_LINEAR  0x2702
%define GL_LINEAR_MIPMAP_LINEAR   0x2703
%define GL_TEXTURE_MAG_FILTER   0x2800
%define GL_TEXTURE_MIN_FILTER   0x2801
%define GL_TEXTURE_WRAP_S       0x2802
%define GL_TEXTURE_WRAP_T       0x2803
%define GL_TEXTURE_MAX_LEVEL    0x813D
%define GL_REPEAT               0x2901
%define GL_CLAMP                0x2900
%define GL_CLAMP_TO_EDGE        0x812F
%define GL_TEXTURE_ENV          0x2300
%define GL_TEXTURE_ENV_MODE     0x2200
%define GL_MODULATE             0x2100
%define GL_VERTEX_ARRAY         0x8074
%define GL_COLOR_ARRAY          0x8076
%define GL_TEXTURE_COORD_ARRAY  0x8078
%define GL_PACK_ALIGNMENT       0x0D05
%define GL_UNPACK_ALIGNMENT     0x0CF5
%define GL_FOG_MODE             0x0B65
%define GL_FOG_START            0x0B63
%define GL_FOG_END              0x0B64
%define GL_FOG_COLOR            0x0B66
%define GL_PERSPECTIVE_CORRECTION_HINT 0x0C50
%define GL_NICEST               0x1102
%define GL_SMOOTH               0x1D01
%define GL_FLAT                 0x1D00
%define GL_ARRAY_BUFFER         0x8892
%define GL_ELEMENT_ARRAY_BUFFER 0x8893
%define GL_STATIC_DRAW          0x88E4
%define GL_DYNAMIC_DRAW         0x88E8
%define GL_STREAM_DRAW          0x88E0
%define GL_FRAGMENT_SHADER      0x8B30
%define GL_VERTEX_SHADER        0x8B31
%define GL_COMPILE_STATUS       0x8B81
%define GL_LINK_STATUS          0x8B82
%define GL_INFO_LOG_LENGTH      0x8B84
%define GL_TEXTURE0             0x84C0
%define GL_TEXTURE1             0x84C1
%define GL_COMPILE              0x1300

%endif
