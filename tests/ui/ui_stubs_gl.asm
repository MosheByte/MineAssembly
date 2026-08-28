; gl extension pointers ui.asm references, for tests that don't link src/gl.asm.
; not in api.inc so nobody stubs them. left zero, the logic paths never call them.
bits 64
default rel

global pglActiveTexture, pglBindBuffer, pglUseProgram

section .bss
alignb 16
pglActiveTexture:   resq 1
pglBindBuffer:      resq 1
pglUseProgram:      resq 1
