# Self-checking mie CSR test.
# MSIE (bit3), MTIE (bit7), MEIE (bit11) are plain read/write; nothing in
# this core drives them from hardware (no CLINT/PLIC yet), unlike
# mstatus's MIE/MPIE. All other bits read 0.
.section .text
.globl _start

_start:
    li x10, 0

    li   t0, 0xFFFFFFFF
    csrw mie, t0
    csrr t1, mie
    li   t2, 0x888            # bit3 | bit7 | bit11
    bne  t1, t2, fail_1

    csrw mie, x0
    csrr t1, mie
    bnez t1, fail_2

    li   t0, 0x800             # MEIE only
    csrs mie, t0
    csrr t1, mie
    bne  t1, t0, fail_3

    csrc mie, t0
    csrr t1, mie
    bnez t1, fail_4

pass:
    li x10, 1
    j terminate

fail_1: li x10, 0x11
        j fail
fail_2: li x10, 0x12
        j fail
fail_3: li x10, 0x13
        j fail
fail_4: li x10, 0x14
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
