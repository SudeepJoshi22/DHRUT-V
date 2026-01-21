# Hazard-free load-use hazard test using .data section and la
# - All data stored in .data section
# - Uses la to get address (tests la pseudo-instruction expansion)
# - Immediate dependency after each lw → stresses load-use hazard
# - No data hazards except the intentional load-use cases

.section .text
.globl _start

_start:
    # ───────────────────────────────────────────────
    # Load base address using la pseudo-instruction
    # (la x10, test_data → auipc + addi)
    # ───────────────────────────────────────────────
    la    x10, test_data         # x10 = address of test_data

    # ───────────────────────────────────────────────
    # Test 1: Basic load-use hazard
    # ───────────────────────────────────────────────
    lw    x5, 0(x10)             # x5 ← 0xDEADBEEF
    add   x6, x5, x0             # x6 ← should be 0xDEADBEEF (stall + forward)

    # Independent instructions
    addi  x20, x0, 42
    addi  x21, x0, 100

    # ───────────────────────────────────────────────
    # Test 2: Chain of load-use hazards
    # ───────────────────────────────────────────────
    lw    x7, 4(x10)             # x7 ← 0x11111111
    add   x8, x7, x0             # x8 ← 0x11111111 (stall + forward)

    lw    x9, 8(x10)             # x9 ← 0x22222222
    add   x11, x9, x0            # x11 ← 0x22222222 (stall + forward)

    lw    x12, 12(x10)           # x12 ← 0x33333333
    add   x13, x12, x0           # x13 ← 0x33333333 (stall + forward)

    # Independent instructions
    addi  x22, x0, 123
    addi  x23, x0, 456

    # ───────────────────────────────────────────────
    # Infinite loop
    # ───────────────────────────────────────────────
end_loop:
    j     end_loop

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
