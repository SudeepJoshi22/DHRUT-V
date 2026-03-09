# Self-checking ADD/ADDI test
.section .text
.globl _start

_start:
    # Test 1: ADDI with positive
    li x1, 5
    addi x2, x1, 10
    li x3, 15
    bne x2, x3, fail

    # Test 2: ADDI with negative
    li x1, 10
    addi x2, x1, -5
    li x3, 5
    bne x2, x3, fail

    # Test 3: ADD
    li x1, 100
    li x2, 200
    add x3, x1, x2
    li x4, 300
    bne x3, x4, fail

    # Test 4: ADD with negative result
    li x1, 10
    li x2, -20
    add x3, x1, x2
    li x4, -10
    bne x3, x4, fail

pass:
    li x10, 1
    j terminate

fail:
    li x10, 3

terminate:
    la t0, tohost
    sw x10, 0(t0)
    sw x0, 4(t0)
spin:
    j spin

.section .tohost,"aw",@progbits
.align 6
.global tohost
tohost:   .dword 0
.size tohost, 8

.align 6
.global fromhost
fromhost: .dword 0
.size fromhost, 8
