# Self-checking mip CSR test.
# Fully read-only, hardwired 0 - no CLINT/PLIC pending lines wired up yet.
# Writes must be silently ignored.
.section .text
.globl _start

_start:
    li x10, 0

    csrr t0, mip
    bnez t0, fail_1

    li   t0, 0xFFFFFFFF
    csrw mip, t0
    csrr t0, mip
    bnez t0, fail_2

    li   t0, 0x888             # plausible pending bits (MSIP/MTIP/MEIP)
    csrs mip, t0
    csrr t0, mip
    bnez t0, fail_3

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
