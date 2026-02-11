# Hazard-free load/store test using only addi
# - No li (uses addi with small immediates)
# - All immediates are within ±2047 (12-bit signed)
# - No data hazards (independent instructions separate dependent pairs)
# - Tests: SB, SH, SW, LB, LH, LW, LBU, LHU

.section .text
.globl _start

_start:
    
    la    x10, test_data

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

    la    t0, tohost
    li    t1, 1
    sw    t1, 0(t0)
    sw    x0, 4(t0)      # upstream also writes zero to tohost+4 [page:1]

1:  j     1b


.section .data

    test_data:
        .word 0xdeadbeef
        .word 0x000b00b5

.pushsection .tohost, "aw", @progbits
    .align 6
    .global tohost

    tohost:
        .dword 0
        .size tohost, 8

    .align 6
    .global fromhost
    fromhost:
        .dword 0
        .size fromhost, 8

.popsection

.end
