// File: include/riscv_types_pkg.sv
package riscv_uop_pkg;

  typedef enum logic [6:0] {
    OPCODE_LOAD     = 7'b000_0011,
    OPCODE_OP_IMM   = 7'b001_0011,
    OPCODE_AUIPC    = 7'b001_0111,
    OPCODE_STORE    = 7'b010_0011,
    OPCODE_OP       = 7'b011_0011,
    OPCODE_LUI      = 7'b011_0111,
    OPCODE_BRANCH   = 7'b110_0011,
    OPCODE_JALR     = 7'b110_0111,
    OPCODE_JAL      = 7'b110_1111,
    // Future: OPCODE_FMADD, OPCODE_SYSTEM, etc.
    OPCODE_INVALID  = 7'b111_1111
  } riscv_opcode_t;

  // Arithmetic function3 / function7 combinations (for OP and OP-IMM)
  typedef enum logic [9:0] {  // {funct7[5], funct3}
    ALU_ADD     = 10'b0_000,
    ALU_SUB     = 10'b1_000,
    ALU_SLL     = 10'b0_001,
    ALU_SLT     = 10'b0_010,
    ALU_SLTU    = 10'b0_011,
    ALU_XOR     = 10'b0_100,
    ALU_SRL     = 10'b0_101,
    ALU_SRA     = 10'b1_101,
    ALU_OR      = 10'b0_110,
    ALU_AND     = 10'b0_111,
    ALU_INVALID = 10'bx_xxx
  } alu_op_t;

  // Micro-op structure (will grow later)
  typedef struct packed {
    logic        valid;           // valid decoded instruction
    riscv_opcode_t opcode;
    alu_op_t     alu_op;          // for arithmetic ops
    logic [4:0]  rs1, rs2, rd;    // source/dest registers
    logic [31:0] imm;             // immediate (sign-extended)
    logic        uses_rs1;
    logic        uses_rs2;
    logic        writes_rd;
    logic        is_immediate;    // OP-IMM vs OP
    // Future fields:
    // logic        is_load, is_store;
    // logic        is_branch, is_jump;
    // fpu_op_t     fpu_op;       // for F/D extension
    // csr_op_t     csr_op;       // for Zicsr
  } uop_t;

endpackage
