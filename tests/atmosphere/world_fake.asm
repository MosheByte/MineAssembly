; tiny programmable world, linked instead of the runner's return-0 stubs for
; world_get_block/light/biome and world_height_at. fw_blocks[x + z*64 + y*4096],
; x/z wrap mod 64, y outside 0..127 is air.
bits 64
default rel

%define FW_W 64
%define FW_H 128

section .bss
alignb 16
global fw_blocks, fw_light, fw_biome
fw_blocks:  resb FW_W*FW_W*FW_H
fw_light:   resd 1
fw_biome:   resd 1

section .text

; -> rax index, or -1 when y is out of range. x/z wrap with a plain AND so
; negative coords land in the grid too (x = -4 is column 60)
fw_index:
    mov      rax, -1
    and      ecx, FW_W-1
    and      r8d, FW_W-1
    cmp      edx, FW_H
    jae      .out                       ; unsigned, catches y < 0 too
    mov      eax, edx
    shl      eax, 6
    add      eax, r8d
    shl      eax, 6
    add      eax, ecx
.out:
    ret

global world_get_block
world_get_block:
    call     fw_index
    test     rax, rax
    js       .air
    lea      r9, [rel fw_blocks]
    movzx    eax, byte [r9+rax]
    ret
.air:
    xor      eax, eax
    ret

global world_get_light
world_get_light:
    mov      eax, [rel fw_light]
    ret

global world_get_biome
world_get_biome:
    mov      eax, [rel fw_biome]
    ret

; -> eax highest non-air y, -1 if none
global world_height_at
world_height_at:
    mov      r8d, edx
    mov      edx, FW_H-1
.scan:
    call     fw_index
    test     rax, rax
    js       .none
    lea      r9, [rel fw_blocks]
    cmp      byte [r9+rax], 0
    jne      .found
    dec      edx
    jns      .scan
.none:
    mov      eax, -1
    ret
.found:
    mov      eax, edx
    ret
