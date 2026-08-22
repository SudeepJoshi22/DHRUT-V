# Self-checking mcycle/mcycleh CSR test.
# Verifies the pair auto-increments as a free-running 64-bit counter
# (monotonic), that SW can write it, and specifically exercises the
# carry from mcycle into mcycleh across the 32-bit boundary.
.section .text
.globl _start

_start:
    li x10, 0

    # Monotonic increase.
    csrr t0, mcycle
    csrr t1, mcycle
    bgeu t0, t1, fail_1

    # Write mcycle near its max, then run enough cycles to carry into
    # mcycleh. mcycleh is assumed 0 here (test runs early after reset).
    li   t0, 0xFFFFFFF8
    csrw mcycle, t0
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    csrr t2, mcycleh
    li   t3, 1
    bne  t2, t3, fail_2        # carry into mcycleh must have happened

    csrr t4, mcycle
    bgeu t4, t0, fail_3        # mcycle must have wrapped past 0xFFFFFFF8

pass:
    li x10, 1
    j terminate

fail_1: li x10, 0x11
        j fail
fail_2: li x10, 0x12
        j fail
fail_3: li x10, 0x13
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

.section .tohost,"aw",@progbits
.align 6
.global tohost
tohost:   .dword 0
.size tohost, 8

.align 6
.global fromhost
fromhost: .dword 0
.size fromhost, 8
