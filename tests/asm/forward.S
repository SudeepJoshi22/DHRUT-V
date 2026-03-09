# Self-checking Forwarding test
.section .text
.globl _start
.option norelax

_start:
    # ───────────────────────────────────────────────
    # Test 1: ALU to ALU Forwarding (immediate previous result)
    # ───────────────────────────────────────────────
    li    x1, 40
    li    x2, 60
    add   x5, x1, x2             # x5 = 100 (in ALU)
    add   x6, x5, x1             # x6 = 140 (needs x5 from ALU)
    
    li    x10, 140
    bne   x6, x10, fail_alu_fwd

    # ───────────────────────────────────────────────
    # Test 2: Retire to ALU Forwarding
    # ───────────────────────────────────────────────
    li    x5, 75                 
    addi  x20, x0, 1             # Bubble 1
    addi  x21, x0, 2             # Bubble 2
    add   x7, x5, x0             # x7 = 75 (needs x5 from Retire)
    
    li    x10, 75
    bne   x7, x10, fail_retire_fwd

    # ───────────────────────────────────────────────
    # Test 3: Forwarding to LSU (Store data)
    # ───────────────────────────────────────────────
    la    x10, test_data
    li    x8, 0x123
    sw    x8, 0(x10)             # x8 forwarded if needed
    lw    x9, 0(x10)
    
    li    x11, 0x123
    bne   x9, x11, fail_lsu_fwd

pass:
    li x10, 1
    j terminate

fail_alu_fwd:    li x10, 0x11
                 j fail
fail_retire_fwd: li x10, 0x22
                 j fail
fail_lsu_fwd:    li x10, 0x33
                 j fail

fail:
    slli x10, x10, 1
    ori  x10, x10, 1

terminate:
    la t0, tohost
    sw x10, 0(t0)
    sw x0, 4(t0)
spin:
    j spin

.section .data
.align 4
test_data:
    .word 0x0
    .word 0x0

.section .tohost,"aw",@progbits
.align 6
.global tohost
tohost:   .dword 0
.size tohost, 8

.align 6
.global fromhost
fromhost: .dword 0
.size fromhost, 8
