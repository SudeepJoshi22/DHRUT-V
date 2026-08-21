# Self-checking CSR read/modify/write test (CSRRW/S/C + immediate forms).
# Exercises mscratch as a plain read/write scratch CSR, and checks the
# RS/RC "no write when source is zero" side-effect-suppression rule.
.section .text
.globl _start

_start:
    li x10, 0            # fail-code accumulator (built up, tohost'd at the end)

    # --- CSRRW: write then read back old value ---
    li      x5, 0x1234
    csrrw   x0, mscratch, x5      # mscratch <- 0x1234, discard old value
    csrrw   x6, mscratch, x0      # x6 <- old (0x1234), mscratch <- 0
    li      x7, 0x1234
    bne     x6, x7, fail_1

    # --- CSRRS: set bits, verify OR semantics ---
    li      x5, 0x0F0F
    csrw    mscratch, x5          # mscratch <- 0x0F0F  (csrw = csrrw x0, ...)
    li      x5, 0x00F0
    csrrs   x6, mscratch, x5      # x6 <- old (0x0F0F); mscratch <- 0x0F0F | 0x00F0 = 0x0FFF
    li      x7, 0x0F0F
    bne     x6, x7, fail_2
    csrr    x6, mscratch
    li      x7, 0x0FFF
    bne     x6, x7, fail_3

    # --- CSRRC: clear bits, verify AND-NOT semantics ---
    li      x5, 0x0FF0
    csrrc   x6, mscratch, x5      # x6 <- old (0x0FFF); mscratch <- 0x0FFF & ~0x0FF0 = 0x000F
    li      x7, 0x0FFF
    bne     x6, x7, fail_4
    csrr    x6, mscratch
    li      x7, 0x000F
    bne     x6, x7, fail_5

    # --- CSRRS with rs1=x0 must NOT write (read-only probe) ---
    csrrs   x6, mscratch, x0      # read mscratch, no write (rs1=x0)
    li      x7, 0x000F
    bne     x6, x7, fail_6
    csrr    x6, mscratch
    bne     x6, x7, fail_7        # still 0x000F -> confirms no write happened

    # --- Immediate forms: CSRRWI / CSRRSI / CSRRCI ---
    csrwi   mscratch, 5           # mscratch <- 5
    csrr    x6, mscratch
    li      x7, 5
    bne     x6, x7, fail_8

    csrsi   mscratch, 2           # mscratch <- 5 | 2 = 7
    csrr    x6, mscratch
    li      x7, 7
    bne     x6, x7, fail_9

    csrci   mscratch, 4           # mscratch <- 7 & ~4 = 3
    csrr    x6, mscratch
    li      x7, 3
    bne     x6, x7, fail_10

    csrsi   mscratch, 0           # uimm=0 -> must NOT write
    csrr    x6, mscratch
    bne     x6, x7, fail_11       # still 3

pass:
    li x10, 1
    j terminate

fail_1:  li x10, 0x11
         j fail
fail_2:  li x10, 0x12
         j fail
fail_3:  li x10, 0x13
         j fail
fail_4:  li x10, 0x14
         j fail
fail_5:  li x10, 0x15
         j fail
fail_6:  li x10, 0x16
         j fail
fail_7:  li x10, 0x17
         j fail
fail_8:  li x10, 0x18
         j fail
fail_9:  li x10, 0x19
         j fail
fail_10: li x10, 0x1A
         j fail
fail_11: li x10, 0x1B
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
