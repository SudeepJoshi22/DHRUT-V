# Self-checking mtvec CSR test.
# Plain full-32-bit read/write (including the mode field) - the RTL
# always treats it as direct mode regardless of the mode bits' value, but
# the register storage itself doesn't mask anything.
.section .text
.globl _start

_start:
    li x10, 0

    la   t0, _start
    csrw mtvec, t0
    csrr t1, mtvec
    bne  t1, t0, fail_1

    li   t0, 0x80009000       # arbitrary aligned value, mode=00
    csrw mtvec, t0
    csrr t1, mtvec
    bne  t1, t0, fail_2

    li   t0, 0x80009001       # mode bit set (vectored) - stored as-is
    csrw mtvec, t0
    csrr t1, mtvec
    bne  t1, t0, fail_3

    # restore a sane handler base so a stray trap doesn't run off into
    # the weeds (not expected to fire, but keep it tidy).
    la   t0, terminate
    csrw mtvec, t0

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
