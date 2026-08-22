# Self-checking mstatus CSR test.
# Verifies MIE (bit3) and MPIE (bit7) are plain read/write, and MPP
# (bits[12:11]) always reads back 2'b11 (M-mode hardwired constant,
# writes ignored - this core has no S/U-mode).
.section .text
.globl _start

_start:
    li x10, 0

    # Write all-ones: MIE=1, MPIE=1, MPP should still read as 3 (not
    # settable), everything else reads 0 (unimplemented bits).
    li   t0, 0xFFFFFFFF
    csrw mstatus, t0
    csrr t1, mstatus
    li   t2, 0x1888          # bit3 | bit7 | (3<<11) = 0x8 | 0x80 | 0x1800
    bne  t1, t2, fail_1

    # Clear MIE/MPIE via csrw 0; MPP must still read 3.
    csrw mstatus, x0
    csrr t1, mstatus
    li   t2, 0x1800           # MPP=3, MIE=0, MPIE=0
    bne  t1, t2, fail_2

    # csrs/csrc individual bit toggling.
    li   t0, 0x8              # MIE bit
    csrs mstatus, t0
    csrr t1, mstatus
    li   t2, 0x1808
    bne  t1, t2, fail_3

    li   t0, 0x8
    csrc mstatus, t0
    csrr t1, mstatus
    li   t2, 0x1800
    bne  t1, t2, fail_4

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
