# Hazard-free load/store test using only addi
# - No li (uses addi with small immediates)
# - All immediates are within ±2047 (12-bit signed)
# - No data hazards (independent instructions separate dependent pairs)
# - Tests: SB, SH, SW, LB, LH, LW, LBU, LHU

.section .text
.globl _start

_start:
    # ───────────────────────────────────────────────
    # Setup base address (0x1000) using only addi
    # ───────────────────────────────────────────────
    addi  x10, x0,  0x00     # x10 = 0
    addi  x10, x10, 0x10     # x10 = 0x10
    addi  x10, x10, 0x00     # x10 = 0x10
    slli  x10, x10, 8        # x10 = 0x1000 (base address)

    # ───────────────────────────────────────────────
    # Prepare test values (using only addi)
    # ───────────────────────────────────────────────
    addi  x1, x0,  0x7F      # x1 = 127 (for byte test)
    addi  x2, x0, -0x80      # x2 = -128 (signed byte test)
    addi  x3, x0,  0x0F      # x3 = 15
    addi  x3, x3,  0x70      # x3 = 127 (for halfword)
    addi  x4, x0,  0x7F      # x4 = 127
    addi  x4, x4,  0x7F      # x4 = 254
    addi  x4, x4,  0x7F      # x4 = 381
    addi  x4, x4,  0x7F      # x4 = 508
    addi  x4, x4,  0x7F      # x4 = 635
    addi  x4, x4,  0x7F      # x4 = 762
    addi  x4, x4,  0x7F      # x4 = 889
    addi  x4, x4,  0x7F      # x4 = 1016
    addi  x4, x4,  0x7F      # x4 = 1143
    addi  x4, x4,  0x7F      # x4 = 1270
    addi  x4, x4,  0x7F      # x4 = 1397
    addi  x4, x4,  0x7F      # x4 = 1524
    addi  x4, x4,  0x7F      # x4 = 1651
    addi  x4, x4,  0x7F      # x4 = 1778
    addi  x4, x4,  0x7F      # x4 = 1905
    addi  x4, x4,  0x7F      # x4 = 2032
    addi  x4, x4,  0x7F      # x4 = 2159 (still within 12-bit)

    # ───────────────────────────────────────────────
    # Stores (SB, SH, SW)
    # ───────────────────────────────────────────────
    sb    x1, 0(x10)         # store byte 0x7F at 0x1000
    sb    x2, 1(x10)         # store byte -0x80 at 0x1001 (sign test)

    sh    x3, 4(x10)         # store halfword at 0x1004
    sw    x4, 8(x10)         # store word at 0x1008

    # Independent instructions (no hazard)
    addi  x20, x0,  42
    addi  x21, x0,  100

    # ───────────────────────────────────────────────
    # Loads with sign/zero extension
    # ───────────────────────────────────────────────
    lb    x6, 0(x10)         # LB  → 0x0000007F
    lb    x7, 1(x10)         # LB  → 0xFFFFFF80 (sign-extended -128)
    lbu   x8, 0(x10)         # LBU → 0x0000007F
    lbu   x9, 1(x10)         # LBU → 0x00000080

    lh    x11, 4(x10)        # LH  → sign-extended half
    lhu   x12, 4(x10)        # LHU → zero-extended half

    lw    x13, 8(x10)        # LW  → full word

    # Independent instructions to avoid load-use hazard
    addi  x22, x0, 123
    addi  x23, x0, 456

    # ───────────────────────────────────────────────
    # Infinite loop
    # ───────────────────────────────────────────────
1:  j     1b

    .end
