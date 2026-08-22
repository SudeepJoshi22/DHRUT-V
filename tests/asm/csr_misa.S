# Self-checking misa CSR test.
# misa is fully read-only in this core: RV32 (MXL=01), extension bit 'I'
# only -> 0x4000_0100. Writes must be silently ignored.
.section .text
.globl _start

_start:
    li x10, 0

    csrr t0, misa
    li   t1, 0x40000100
    bne  t0, t1, fail_1

    # Attempt to write garbage; value must not change.
    li   t0, 0xFFFFFFFF
    csrw misa, t0
    csrr t0, misa
    li   t1, 0x40000100
    bne  t0, t1, fail_2

    csrw misa, x0
    csrr t0, misa
    bne  t0, t1, fail_3

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
