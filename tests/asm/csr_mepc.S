# Self-checking mepc CSR test.
# bits[31:2] are plain read/write; bits[1:0] are a hardwired-0 field
# (WARL, IALIGN=32) - a software write with the low bits set must read
# back with them masked to 0.
.section .text
.globl _start

_start:
    li x10, 0

    li   t0, 0x80001000       # already aligned
    csrw mepc, t0
    csrr t1, mepc
    bne  t1, t0, fail_1

    li   t0, 0x80001003       # low 2 bits set - must be masked on readback
    csrw mepc, t0
    csrr t1, mepc
    li   t2, 0x80001000
    bne  t1, t2, fail_2

    li   t0, 0xFFFFFFFF
    csrw mepc, t0
    csrr t1, mepc
    li   t2, 0xFFFFFFFC
    bne  t1, t2, fail_3

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
