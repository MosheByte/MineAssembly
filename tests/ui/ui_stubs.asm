; hud.asm wants platform_last_shot but it's not in api.inc, so the auto stubber
; misses it. link this in any ui test that doesn't pull in src/platform.asm.
bits 64
default rel

global platform_last_shot

section .bss
alignb 16
platform_last_shot: resb 4096
