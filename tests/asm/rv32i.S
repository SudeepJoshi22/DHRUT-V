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
    la     x22, scratch_data     # base address for loads/stores (real .data, not ROM)
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

    # NOTE: JALR target intentionally kept in-section (jalr_target label)
    # instead of an arbitrary x1+8 address, so control flow stays inside
    # mapped .text instead of faulting to a near-zero address.
    la     x29, jalr_target      # load address of a valid in-section target
    jalr   x30, x29, 0           # JALR (jump to x29 + 0)
jalr_target:
    nop

    # ───────────────────────────────────────────────
    # 7. System / Fence Instructions
    # ───────────────────────────────────────────────
    # NOTE: ECALL/EBREAK are intentionally omitted here. Spike is run
    # bare-metal with no trap handler installed (mtvec == 0, which is
    # unmapped), so any trap causes an infinite
    # trap_instruction_access_fault loop at epc 0x0 and Spike never
    # terminates. None of the other asm tests execute ECALL/EBREAK for
    # the same reason.
    fence iorw, iorw             # Full fence

    # ───────────────────────────────────────────────
    # Signal completion to Spike/host via tohost
    # ───────────────────────────────────────────────
    la     t0, tohost
    li     t1, 1
    sw     t1, 0(t0)
    sw     x0, 4(t0)      # upstream also writes zero to tohost+4 [page:1]

1:  j 1b

.section .data
.align 4
scratch_data:
    .word 0x00000000
    .word 0x00000000
    .word 0x00000000

.section .tohost,"aw",@progbits
.align 6
.global tohost
tohost:   .dword 0
.size tohost, 8

.align 6
.global fromhost
fromhost: .dword 0
.size fromhost, 8
