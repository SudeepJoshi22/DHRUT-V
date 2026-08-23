# Self-checking mtval CSR test.
# Plain full-32-bit software read/write (no masking) - separate from its
# hardware-write-on-trap-entry path, which is covered by the trap_*.S tests.
.section .text
.globl _start

_start:
    li x10, 0

    li   t0, 0xDEADBEEF
    csrw mtval, t0
    csrr t1, mtval
    bne  t1, t0, fail_1

    csrw mtval, x0
    csrr t1, mtval
    bnez t1, fail_2

    li   t0, 0x1
    csrs mtval, t0
    csrr t1, mtval
    bne  t1, t0, fail_3

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
