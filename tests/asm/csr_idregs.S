# Self-checking test for the read-only ID CSRs: mvendorid, marchid,
# mimpid, mhartid. All hardwired 0 (non-commercial, single-hart
# implementation); writes must be silently ignored.
.section .text
.globl _start

_start:
    li x10, 0

    csrr t0, mvendorid
    bnez t0, fail_1
    csrr t0, marchid
    bnez t0, fail_2
    csrr t0, mimpid
    bnez t0, fail_3
    csrr t0, mhartid
    bnez t0, fail_4

    li   t0, 0xFFFFFFFF
    csrw mvendorid, t0
    csrw marchid, t0
    csrw mimpid, t0
    csrw mhartid, t0

    csrr t0, mvendorid
    bnez t0, fail_5
    csrr t0, marchid
    bnez t0, fail_6
    csrr t0, mimpid
    bnez t0, fail_7
    csrr t0, mhartid
    bnez t0, fail_8

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
fail_5: li x10, 0x15
        j fail
fail_6: li x10, 0x16
        j fail
fail_7: li x10, 0x17
        j fail
fail_8: li x10, 0x18
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
