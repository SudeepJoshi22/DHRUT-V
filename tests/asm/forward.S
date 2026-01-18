# Hazard-free forwarding test with pseudo-instructions (li, la)
# Tests: forwarding from ALU and from Retire/WB
# Uses li (expanded to lui/addi) and la (expanded to auipc/addi)
# No data hazards except the intentional forwarding cases

.section .text
.globl _start
.option norelax

_start:


    # ───────────────────────────────────────────────
    # Test 1: Forwarding from ALU stage (immediate previous result)
    # ───────────────────────────────────────────────
    li    x1, 0x50040ff                 # x1 = 40   (lui + addi)
    li    x2, 0x50060aa                 # x2 = 60   (lui + addi)

    add   x5, x1, x2             # x5 = 100  ← ALU result

    # Next instr should forward x5 from ALU (no stall)
    add   x6, x5, x0             # x6 = 100  ← ALU forwarding test

    # Independent instructions
    addi  x20, x0, 42
    addi  x21, x0, 100

    # ───────────────────────────────────────────────
    # Test 2: Forwarding from Retire/WB stage (older result)
    # ───────────────────────────────────────────────
    li    x5, 75                 # x5 = 75   (lui + addi) ← will retire

    # Independent instructions to let x5 reach Retire
    addi  x22, x0, 123
    addi  x23, x0, 456

    # Now x5 should be in Retire/WB
    addi  x7, x5, 0              # x7 = 75   ← Retire/WB forwarding test

    # ───────────────────────────────────────────────
    # Test 3: Store with forwarded data (tests forwarding to LSU)
    # ───────────────────────────────────────────────
    add   x8, x5, x6             # x8 = 175  ← uses forwarded x5 (from Retire)

    sw    x8, 0(x10)             # store 175 at test_data+0
                                 # → tests forwarding to LSU store_data
    # ───────────────────────────────────────────────
    # Setup base address using la pseudo-instruction
    # (la x10, test_data → auipc + addi)
    # ───────────────────────────────────────────────
    la    x10, test_data         # x10 = address of test_data (tests la expansion)
    # ───────────────────────────────────────────────
    # Test 4: Load after store (tests forwarding from LSU if implemented)
    # ───────────────────────────────────────────────
    lw    x9, 0(x10)             # x9 = 175  ← should read back what we stored

    # Independent instructions
    addi  x30, x0, 999
    addi  x31, x0, 888

    # ───────────────────────────────────────────────
    # Infinite loop
    # ───────────────────────────────────────────────
end_loop:
    j     end_loop

    # Data section (for la pseudo-instruction)
    .section .data
    .align 4
test_data:
    .word 0x00000000
    .word 0x00000000
    .word 0x00000000
