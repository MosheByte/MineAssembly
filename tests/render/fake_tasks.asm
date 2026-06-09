; fake_tasks.asm - no chunkmgr, no workers: cm_task_push refuses so mesher runs
; every job inline. tests that link the real chunkmgr.asm leave this out
bits 64
default rel

section .text
global cm_task_push
cm_task_push:
    xor     eax, eax
    ret
