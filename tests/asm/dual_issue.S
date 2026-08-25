# Dual-issue pairing test.
#
# Long runs of INDEPENDENT ALU ops, which is the case the 2-wide issue
# stage exists for: every adjacent pair should satisfy all of
# issue_hazard.sv's rules and go out together. The arithmetic is
# deliberately trivial and fully self-checking - the point is the
# scheduling, not the ALU, which add.S/arithmetic.S already cover.
#
# Correctness here is checked two ways: the tohost result below, and
# (the real gate) a cpu_trace.log that matches Spike instruction for
# instruction. If pairing ever drops or duplicates an instruction, the
# trace diverges even when the final register values happen to agree.
.section .text
.globl _start

_start:
    # ── Block 1: 8 independent immediate loads ──
    # No source registers at all, no shared destinations: nothing can
    # block pairing, so this should issue 2-wide end to end.
    li x1, 1
    li x2, 2
    li x3, 3
    li x4, 4
    li x5, 5
    li x6, 6
    li x7, 7
    li x8, 8

    # ── Block 2: independent register-register ops ──
    # Each reads only the block-1 values and writes a fresh register, so
    # again no intra-bundle RAW or WAW.
    add  x9,  x1, x2      # 3
    add  x10, x3, x4      # 7
    add  x11, x5, x6      # 11
    add  x12, x7, x8      # 15
    xor  x13, x1, x2      # 3
    or   x14, x3, x4      # 7
    and  x15, x5, x6      # 4
    sub  x16, x8, x7      # 1

    # ── Block 3: independent OP-IMM, mixed with LUI/AUIPC ──
    # LUI and AUIPC are lane-1 capable too (issue_hazard.sv), so these
    # should pair with their neighbours rather than serialising.
    addi x17, x1, 100     # 101
    addi x18, x2, 100     # 102
    slli x19, x1, 4       # 16
    srli x20, x8, 1       # 4
    lui  x21, 0x10        # 0x10000
    addi x22, x3, 7       # 10
    lui  x23, 0x20        # 0x20000
    addi x24, x4, 7       # 11

    # ── Verify block 2 ──
    li x28, 3
    bne x9,  x28, fail
    li x28, 7
    bne x10, x28, fail
    li x28, 11
    bne x11, x28, fail
    li x28, 15
    bne x12, x28, fail
    li x28, 3
    bne x13, x28, fail
    li x28, 7
    bne x14, x28, fail
    li x28, 4
    bne x15, x28, fail
    li x28, 1
    bne x16, x28, fail

    # ── Verify block 3 ──
    li x28, 101
    bne x17, x28, fail
    li x28, 102
    bne x18, x28, fail
    li x28, 16
    bne x19, x28, fail
    li x28, 4
    bne x20, x28, fail
    li x28, 0x10000
    bne x21, x28, fail
    li x28, 10
    bne x22, x28, fail
    li x28, 0x20000
    bne x23, x28, fail
    li x28, 11
    bne x24, x28, fail

    # ── Block 4: a paired run inside a loop ──
    # Exercises pairing across a taken backward branch, where lane 1 is
    # the branch target rather than PC+4.
    li x5, 8              # loop counter
    li x6, 0              # accumulator A
    li x7, 0              # accumulator B
loop:
    addi x6, x6, 2        # these two are independent of each other
    addi x7, x7, 3
    addi x5, x5, -1
    bnez x5, loop

    li x28, 16
    bne x6, x28, fail     # 8 * 2
    li x28, 24
    bne x7, x28, fail     # 8 * 3

pass:
    li x10, 1
    j terminate

fail:
    li x10, 3

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
