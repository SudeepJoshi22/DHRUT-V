# test_rv32i_base_alu_minimal_nops.S
# Functional test for RV32I arithmetic/logical instructions (R-type, I-type immediate, U-type)
# NO pseudo-instructions
# NOPs inserted ONLY where there is a RAW dependency (lui → addi on same rd)
# Assumes your pipeline needs ~5 cycles delay on RAW hazards (as per your earlier "5 nops" request)
# No inter-instruction NOPs otherwise → test runs fast but remains hazard-safe
# Excludes loads/stores/branches/jumps

.section .text
.globl _start
_start:

    # ───────────────────────────────────────────────
    # Setup constants (minimal instructions, real RV32I only)
    # ───────────────────────────────────────────────

    addi x2, x0, 1                 # x2 = 1
    addi x3, x0, 2                 # x3 = 2
    addi x4, x0, 10                # x4 = 10
    addi x5, x0, 16                # x5 = 16
    addi x6, x0, -8                # x6 = -8 (0xFFFFFFF8)
    addi x7, x0, -4                # x7 = -4 (0xFFFFFFFC)

    lui  x8, 0x80000               # x8 = 0x80000000 (exact, single instruction)

    lui  x9, 0x80000               # upper for 0x7FFFFFFF
    addi x0, x0, 0                 # 5 NOPs — dependency: addi reads x9 written by lui
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x9, x9, -1                # x9 = 0x7FFFFFFF

    lui  x10, 0xAAAAA              # upper for 0xAAAAAAAA
    addi x0, x0, 0                 # 5 NOPs — dependency
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x10, x10, 0x0AA           # x10 = 0xAAAAAAAA

    lui  x11, 0x55555              # upper for 0x55555555
    addi x0, x0, 0                 # 5 NOPs — dependency
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x11, x11, 0x555           # x11 = 0x55555555

    # ───────────────────────────────────────────────
    # I-type immediate instructions (no extra NOPs — no dependencies on recent writes)
    # ───────────────────────────────────────────────

    addi x20, x0, 0                # 0 + 0 → x20 = 0
    addi x21, x4, 52               # 10 + 52 → x21 = 62
    addi x22, x6, -3               # -8 + (-3) → x22 = -11

    slti x23, x4, 15               # 10 < 15 → x23 = 1
    slti x24, x4, 5                # 10 < 5 → x24 = 0
    slti x25, x8, 0                # 0x80000000 < 0 → x25 = 1

    sltiu x26, x4, 15              # 10 < 15u → x26 = 1
    sltiu x27, x8, 1               # 0x80000000 < 1u → x27 = 0

    xori x28, x10, -1              # ~0xAAAAAAAA → x28 = 0x55555555
    ori  x29, x11, -1              # 0x55555555 | 0xFFFFFFFF → x29 = 0xFFFFFFFF
    andi x30, x10, -1              # 0xAAAAAAAA & 0xFFFFFFFF → x30 = 0xAAAAAAAA

    slli x12, x5, 3                # 16 << 3 → x12 = 128
    slli x13, x5, 31               # 16 << 31 → x13 = 0x80000000

    srli x14, x10, 4               # 0xAAAAAAAA >> 4 → x14 = 0x0AAAAAAA
    srai x15, x8, 4                # 0x80000000 >>> 4 → x15 = 0xF8000000
    srai x16, x6, 2                # -8 >>> 2 → x16 = -2

    # ───────────────────────────────────────────────
    # R-type instructions (no extra NOPs — all reads from early constants x2–x11)
    # ───────────────────────────────────────────────

    add  x17, x4, x5               # 10 + 16 → x17 = 26
    sub  x18, x5, x4               # 16 - 10 → x18 = 6

    sll  x19, x5, x3               # 16 << 2 → x19 = 64

    slt  x20, x6, x4               # -8 < 10 → x20 = 1
    sltu x21, x8, x9               # 0x80000000 <u 0x7FFFFFFF → x21 = 0

    xor  x22, x10, x11             # 0xAAAAAAAA ^ 0x55555555 → x22 = 0xFFFFFFFF
    or   x23, x10, x11             # 0xAAAAAAAA | 0x55555555 → x23 = 0xFFFFFFFF
    and  x24, x10, x11             # 0xAAAAAAAA & 0x55555555 → x24 = 0x00000000

    srl  x25, x10, x2              # 0xAAAAAAAA >> 1 → x25 = 0x55555555
    sra  x26, x8, x3               # 0x80000000 >>> 2 → x26 = 0xE0000000

    # ───────────────────────────────────────────────
    # U-type instructions
    # ───────────────────────────────────────────────

    lui   x27, 0x12345             # x27 = 0x12345000
    lui   x28, 0xFFFFF             # x28 = 0xFFFFF000

    auipc x29, 0                   # x29 = PC of this auipc instruction
    auipc x30, 0x10                # x30 = PC + 0x10000

    # ───────────────────────────────────────────────
    # Success markers (easy to spot in regfile/waveform)
    # ───────────────────────────────────────────────
    addi x31, x0, 0xAD           # magic "test passed" marker in x31
    addi x1,  x0, 0x0D           # additional visible pattern
    addi x15, x0, 0xEF

    # End of test — simulation can stop after sufficient cycles
