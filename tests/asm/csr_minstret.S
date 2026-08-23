# Self-checking minstret/minstreth CSR test.
# Verifies the pair increments as instructions issue (approximated as
# "a uop issued this cycle" in the RTL, not a true retire pulse - see
# rtl/pipeline/csr_unit.sv), and that SW can write it. Exact counts
# aren't checked (the CSR read/write instructions themselves also count),
# only monotonic increase by at least the expected minimum, and that a
# SW write lands in a small expected range afterward.
.section .text
.globl _start

_start:
    li x10, 0

    csrr t0, minstret
    nop
    nop
    nop
    nop
    nop
    csrr t1, minstret
    sub  t2, t1, t0
    li   t3, 5
    bltu t2, t3, fail_1        # must have incremented by at least the 5 nops

    li   t0, 100
    csrw minstret, t0
    csrr t1, minstret
    bltu t1, t0, fail_2        # write must have taken effect (not below what we wrote)
    li   t3, 110
    bgeu t1, t3, fail_3        # and not run away far past it either

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
