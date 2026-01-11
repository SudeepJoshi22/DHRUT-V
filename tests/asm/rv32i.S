# RV32I full instruction set test program
# Includes all arithmetic, logical, load/store, branch, jump, LUI/AUIPC, and system instructions

.section .text
.globl _start

_start:
    # ───────────────────────────────────────────────
    # 1. Arithmetic / Logical Instructions (OP & OP-IMM)
    # ───────────────────────────────────────────────
    addi   x1,  x0,  42          # ADDI (imm=42)
    add    x2,  x1,  x1          # ADD
    sub    x3,  x2,  x1          # SUB
    sll    x4,  x1,  x1          # SLL
    slt    x5,  x1,  x3          # SLT
    sltu   x6,  x1,  x3          # SLTU
    xor    x7,  x1,  x3          # XOR
    srl    x8,  x2,  x1          # SRL
    sra    x9,  x2,  x1          # SRA
    or     x10, x1,  x3          # OR
    and    x11, x1,  x3          # AND

    # OP-IMM variants
    slti   x12, x1,  50          # SLTI
    sltiu  x13, x1,  50          # SLTIU
    xori   x14, x1,  0x123       # XORI
    ori    x15, x1,  0x456       # ORI
    andi   x16, x1,  0x789       # ANDI
    slli   x17, x1,  3           # SLLI
    srli   x18, x2,  4           # SRLI
    srai   x19, x2,  4           # SRAI

    # ───────────────────────────────────────────────
    # 2. Upper Immediate Instructions (LUI, AUIPC)
    # ───────────────────────────────────────────────
    lui    x20, 0xABCDE          # LUI (upper 20 bits)
    auipc  x21, 0x12345          # AUIPC (PC + upper 20 bits)

    # ───────────────────────────────────────────────
    # 3. Load Instructions
    # ───────────────────────────────────────────────
    li     x22, 0x1000           # base address for loads (assume memory at 0x1000)
    lb     x23, 0(x22)           # LB
    lh     x24, 2(x22)           # LH
    lw     x25, 4(x22)           # LW
    lbu    x26, 8(x22)           # LBU
    lhu    x27, 10(x22)          # LHU

    # ───────────────────────────────────────────────
    # 4. Store Instructions
    # ───────────────────────────────────────────────
    sb     x1,  0(x22)           # SB
    sh     x2,  2(x22)           # SH
    sw     x3,  4(x22)           # SW

    # ───────────────────────────────────────────────
    # 5. Branch Instructions (BEQ, BNE, BLT, BGE, BLTU, BGEU)
    # ───────────────────────────────────────────────
    beq    x1, x1,  beq_target   # BEQ (taken)
    bne    x1, x2,  bne_target   # BNE (taken)
    blt    x1, x2,  blt_target   # BLT (taken)
    bge    x2, x1,  bge_target   # BGE (taken)
    bltu   x1, x2,  bltu_target  # BLTU (taken)
    bgeu   x2, x1,  bgeu_target  # BGEU (taken)

    # Targets for branches (just nop loops)
beq_target:
    nop
bne_target:
    nop
blt_target:
    nop
bge_target:
    nop
bltu_target:
    nop
bgeu_target:
    nop

    # ───────────────────────────────────────────────
    # 6. Jump Instructions
    # ───────────────────────────────────────────────
    jal    x28, jal_target       # JAL (link register x28)
jal_target:
    nop

    jalr   x29, x1, 8            # JALR (jump to x1 + 8)

    # ───────────────────────────────────────────────
    # 7. System Instructions (ECALL, EBREAK)
    # ───────────────────────────────────────────────
    ecall                        # Environment call (syscall)
    ebreak                       # Breakpoint

    # ───────────────────────────────────────────────
    # 8. Fence (memory barrier)
    # ───────────────────────────────────────────────
    fence iorw, iorw             # Full fence

    # ───────────────────────────────────────────────
    # Infinite loop to keep CPU alive
    # ───────────────────────────────────────────────
1:  j 1b
