# BPU test: mixed taken/not-taken pattern.
#
# Exercises the BPU's 2-bit saturating counter state transitions
# (SNT -> WNT -> WT -> ST and back down) and the BTB's allocate-on-first-
# fetch path, by repeatedly re-executing the *same* branch instruction
# (same PC, so same BTB/BHT index) with a controlled, alternating
# outcome pattern:
#   - First pass: never taken (drives/holds counter at SNT)
#   - Second pass: always taken (SNT->WNT->WT->ST, saturates high)
#   - Third pass: strict alternation taken/not-taken (bounces WT<->WNT
#     around the weak states without ever reaching the strong ones)
# Whatever the BPU predicts, the branch is always resolved correctly in
# Issue, so functional correctness (checked via tohost) must hold
# regardless of prediction accuracy - this test is only meaningful if
# ./tools/simulate.sh still reports tohost==1 (pass) after wiring in
# prediction/misprediction handling.
.section .text
.globl _start

_start:
    li   x5, 0             # loop index
    li   x6, 0             # taken counter (sanity check)
    li   x7, 0             # not-taken counter (sanity check)

    # ─────────── Pass 1: 8x not-taken ───────────
    li   x20, 0
pass1_loop:
    li   x21, 1
    bne  x21, x21, pass1_dummy   # never taken (same operand)
    addi x7, x7, 1
pass1_dummy:
    addi x20, x20, 1
    li   x22, 8
    blt  x20, x22, pass1_loop

    # ─────────── Pass 2: 8x taken (drive counter to ST) ───────────
    li   x20, 0
pass2_loop:
    li   x21, 1
    beq  x21, x21, pass2_taken   # always taken (same operand)
    j pass2_fail_marker
pass2_taken:
    addi x6, x6, 1
    addi x20, x20, 1
    li   x22, 8
    blt  x20, x22, pass2_loop
    j pass3_start
pass2_fail_marker:
    li x10, 0x10
    j terminate

    # ─────────── Pass 3: strict alternating taken/not-taken ───────────
pass3_start:
    li   x20, 0
    li   x23, 0            # alternation flag
pass3_loop:
    andi x24, x23, 1
    bnez x24, pass3_odd

pass3_even:
    # taken branch on even iterations
    li   x21, 1
    beq  x21, x21, pass3_even_taken
    j fail
pass3_even_taken:
    addi x6, x6, 1
    j pass3_continue

pass3_odd:
    # not-taken branch on odd iterations
    li   x21, 1
    bne  x21, x21, fail
    addi x7, x7, 1

pass3_continue:
    addi x23, x23, 1
    addi x20, x20, 1
    li   x22, 10
    blt  x20, x22, pass3_loop

    # Expect: taken   = 8 (pass2) + 5 (pass3 evens)  = 13
    #         not-taken = 8 (pass1) + 5 (pass3 odds)  = 13
    li   x25, 13
    bne  x6, x25, fail
    bne  x7, x25, fail

    li   x10, 1
    j terminate

fail:
    li   x10, 0x20
    j terminate

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
