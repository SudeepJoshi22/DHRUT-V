# BPU test: backward-branch-dominant loop.
#
# A tight backward-branch loop that runs enough iterations for the BPU's
# 2-bit saturating counter to warm up to Strongly-Taken and for the BTB
# to hold a stable entry for the loop-closing branch. This does not check
# prediction accuracy directly (that is functional-only, checked via
# tohost like every other asm test) but is designed to exercise:
#   - repeated hits on the same BTB index (same PC every iteration)
#   - saturation of the 2-bit counter to ST after a couple of taken
#     outcomes
#   - the final not-taken exit transitioning the counter back down
#     without breaking correctness
# Correctness (not perf) is what's actually verified here: regardless of
# what the BPU predicts, the core must still execute exactly N iterations
# and reach the pass code.
.section .text
.globl _start

_start:
    li   x5, 0            # iteration counter
    li   x6, 200          # loop trip count (large enough to warm up BPU)
    li   x7, 0            # accumulator

outer_loop:
    li   x10, 0
inner_loop:
    addi x7, x7, 1
    addi x10, x10, 1
    li   x11, 4
    blt  x10, x11, inner_loop   # backward branch, taken 3x per outer iter, not-taken once

    addi x5, x5, 1
    blt  x5, x6, outer_loop     # backward branch, taken (trip-1)x, not-taken once

    # Expect x7 == 200 * 4 == 800
    li   x12, 800
    bne  x7, x12, fail

    li   x10, 1
    j terminate

fail:
    li   x10, 0x2
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
