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

    # Write mcycle near its max, then run enough CYCLES to carry into
    # mcycleh. mcycleh is assumed 0 here (test runs early after reset).
    #
    # The padding below is deliberately generous. mcycle counts cycles but
    # the padding is measured in INSTRUCTIONS, so the two only line up at
    # 1 IPC. This test originally used 10 nops for an 8-cycle carry, which
    # worked only while the core was single-issue: at 2-wide the nops pair
    # (rd == x0, so nothing blocks pairing), the padding collapses to ~5
    # cycles, and the carry never happens.
    #
    # 64 nops gives 32 cycles even at a perfect 2 IPC, against the 8
    # needed - and still leaves margin if the core is widened further.
    # Overshooting is harmless: once mcycle wraps, mcycleh stays at 1
    # until the next wrap 2^32 cycles later.
    #
    # Note the padding must stay STRAIGHT-LINE. A loop that polls mcycleh
    # would be IPC-independent but would execute a different number of
    # iterations on the DUT than on Spike (their cycle counts differ by
    # design), and the trace comparison against Spike - the real gate -
    # would diverge on instruction count rather than just on counter
    # values.
    li   t0, 0xFFFFFFF8
    csrw mcycle, t0
    .rept 64
    nop
    .endr
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
