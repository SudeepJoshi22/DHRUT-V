# Self-checking load-use hazard / LSU forwarding test.
# - All data stored in .data section
# - Uses la to get address (tests la pseudo-instruction expansion)
# - Immediate dependency after each lw -> stresses load-use hazard
# - Also directly regression-tests the store-rd forwarding bug: a
#   store's own imm[4:0] was being misread as a bogus destination
#   register and incorrectly forwarded to a later instruction that
#   happened to read the same register number (see git history for
#   rtl/pipeline/lsu.sv's o_lsu_fwd_valid).
#
#   The dmem model (test_bench/tb_pyuvm/dmem_agent/dmem_driver.py) applies
#   a random 1-5 cycle stall per access, so whether the two stores below
#   actually land on the exact colliding cycle is seed-dependent - this
#   ran clean against the pre-fix RTL on several seeds and only reliably
#   caught the bug (FAIL: tohost=0x2f, fail_7) with `simulate.sh
#   lsu_forward 1`. Run with that seed when specifically regression-
#   testing this bug; a random/default seed may not trigger it.

.section .text
.globl _start

_start:
    li x10, 0            # fail-code accumulator (built up, tohost'd at the end)

    # ───────────────────────────────────────────────
    # Load base address using la pseudo-instruction
    # (la x11, test_data -> auipc + addi)
    # ───────────────────────────────────────────────
    la    x11, test_data         # x11 = address of test_data

    # ───────────────────────────────────────────────
    # Test 1: Basic load-use hazard
    # ───────────────────────────────────────────────
    lw    x5, 0(x11)             # x5 <- 0xDEADBEEF
    add   x6, x5, x0             # x6 <- should be 0xDEADBEEF (stall + forward)
    li    x7, 0xDEADBEEF
    bne   x6, x7, fail_1

    # Independent instructions
    addi  x20, x0, 42
    addi  x21, x0, 100

    # ───────────────────────────────────────────────
    # Test 2: Chain of load-use hazards
    # ───────────────────────────────────────────────
    lw    x7, 4(x11)             # x7 <- 0x11111111
    add   x8, x7, x0             # x8 <- 0x11111111 (stall + forward)
    li    x9, 0x11111111
    bne   x8, x9, fail_2

    lw    x9, 8(x11)             # x9 <- 0x22222222
    add   x12, x9, x0            # x12 <- 0x22222222 (stall + forward)
    li    x13, 0x22222222
    bne   x12, x13, fail_3

    lw    x12, 12(x11)           # x12 <- 0x33333333
    add   x13, x12, x0           # x13 <- 0x33333333 (stall + forward)
    li    x14, 0x33333333
    bne   x13, x14, fail_4

    # Independent instructions, and confirm they weren't disturbed
    addi  x22, x0, 123
    addi  x23, x0, 456
    li    x24, 123
    bne   x22, x24, fail_5
    li    x24, 456
    bne   x23, x24, fail_6

    # ───────────────────────────────────────────────
    # Test 3: store-rd forwarding regression.
    # sw x2, 4(x11) completes with a bogus "rd" of 4 (its own imm[4:0]),
    # since decode always reads instr[11:7] regardless of instruction
    # type. Immediately follow with a store of the REAL x4 - if the LSU
    # incorrectly forwards its previous (store) completion by rd-number
    # match instead of gating on is_load, x4's stored value gets
    # corrupted to garbage instead of the value actually in x4.
    # ───────────────────────────────────────────────
    li    x2, 0x5
    li    x4, 0xCAFEF00D
    sw    x2, 4(x11)              # bogus "rd" lookalike = imm[4:0] = 4
    sw    x4, 16(x11)             # must store the REAL x4, not garbage
    lw    x25, 16(x11)            # read back what actually landed in memory
    li    x26, 0xCAFEF00D
    bne   x25, x26, fail_7

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

fail:
    slli x10, x10, 1
    ori  x10, x10, 1

terminate:
    la t0, tohost
    sw x10, 0(t0)
    sw x0, 4(t0)
spin:
    j spin

    # ───────────────────────────────────────────────
    # Data section
    # ───────────────────────────────────────────────
    .section .data
    .align 4
test_data:
    .word 0xDEADBEEF             # offset 0
    .word 0x11111111             # offset 4
    .word 0x22222222             # offset 8
    .word 0x33333333             # offset 12
    .word 0x00000000             # offset 16 (scratch for test 3)

.section .tohost,"aw",@progbits
.align 6
.global tohost
tohost:   .dword 0
.size tohost, 8

.align 6
.global fromhost
fromhost: .dword 0
.size fromhost, 8
