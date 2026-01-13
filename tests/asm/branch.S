.section .text
.globl _start
_start:

    # ------------------------------------------------------
    # Setup base values (using only addi)
    # ------------------------------------------------------
    addi x5,  x0,  5           # small positive A
    addi x6,  x0,  6           # small positive B
    addi x7,  x0,  7           # small positive C
    addi x10, x0, -3           # small negative
    addi x20, x0,  0           # zero

    # All registers we will write to start at 0 or -1 marker
    addi x11, x0,  -1
    addi x12, x0,  -1
    addi x13, x0,  -1
    addi x14, x0,  -1
    addi x15, x0,  -1
    addi x16, x0,  -1
    addi x17, x0,  -1
    addi x18, x0,  -1
    addi x19, x0,  -1
    addi x21, x0,  -1
    addi x22, x0,  -1
    addi x23, x0,  -1
    addi x24, x0,  -1
    addi x25, x0,  -1
    addi x26, x0,  -1
    addi x27, x0,  -1
    addi x28, x0,  -1
    addi x29, x0,  -1
    addi x30, x0,  -1
    addi x31, x0,  -1

    # =============================================================
    # GROUP 1: ALL NOT-TAKEN BRANCH TESTS (sequential flow = correct)
    # =============================================================

    # BEQ not taken (5 == 6? → no)
    beq  x5, x6, 1f           # should NOT branch
    addi x11, x0, 11          # good - reached
1:

    # BNE not taken (5 != 5? → no)
    bne  x5, x5, 1f           # should NOT branch
    addi x12, x0, 12          # good
1:

    # BLT not taken (7 < 5 signed? → no)
    blt  x7, x5, 1f           # should NOT branch
    addi x13, x0, 13          # good
1:

    # BGE not taken (-3 >= 5? → no)
    bge  x10, x5, 1f          # should NOT branch
    addi x14, x0, 14          # good
1:

    # BLTU not taken (7 < 5 unsigned? → no)
    bltu x7, x5, 1f           # should NOT branch
    addi x15, x0, 15          # good
1:

    # BGEU not taken (5 >= 7 unsigned? → no)
    bgeu x5, x7, 1f           # should NOT branch
    addi x16, x0, 16          # good
1:

    # Forward branch with zero compare not taken
    bne  x20, x20, 1f         # 0 != 0? → no
    addi x17, x0, 17          # good
1:

    # =============================================================
    # GROUP 2: ALL TAKEN BRANCH TESTS (forward jumps)
    # =============================================================

    # BEQ taken (5 == 5? → yes)
    beq  x5, x5, beq_taken
    addi x18, x0, -1          # bad - should be skipped
    j    beq_taken_end
beq_taken:
    addi x18, x0, 18          # good - reached
beq_taken_end:

    # BNE taken (5 != 6? → yes)
    bne  x5, x6, bne_taken
    addi x19, x0, -1          # bad
    j    bne_taken_end
bne_taken:
    addi x19, x0, 19          # good
bne_taken_end:

    # BLT taken (5 < 7 signed? → yes)
    blt  x5, x7, blt_taken
    addi x21, x0, -1          # bad
    j    blt_taken_end
blt_taken:
    addi x21, x0, 21          # good
blt_taken_end:

    # BGE taken (5 >= -3 signed? → yes)
    bge  x5, x10, bge_taken
    addi x22, x0, -1          # bad
    j    bge_taken_end
bge_taken:
    addi x22, x0, 22          # good
bge_taken_end:

    # BLTU taken (10 < 0xFFFFFFFF unsigned? → yes)
    addi x25, x0, 10
    addi x26, x0, -1          # 0xFFFFFFFF
    bltu x25, x26, bltu_taken
    addi x23, x0, -1          # bad
    j    bltu_taken_end
bltu_taken:
    addi x23, x0, 23          # good
bltu_taken_end:

    # BGEU taken (0xFFFFFFFF >= 10 unsigned? → yes)
    bgeu x26, x25, bgeu_taken
    addi x24, x0, -1          # bad
    j    bgeu_taken_end
bgeu_taken:
    addi x24, x0, 24          # good
bgeu_taken_end:

    # Backward branch taken (simple one-iteration loop)
    addi x30, x0, 1
backward_loop:
    addi x30, x30, -1         # becomes 0
    bne  x30, x0, backward_loop   # taken once
    addi x31, x0, 31          # good - reached after loop exits

    # End marker - infinite loop for easy register inspection
end:
    j end
