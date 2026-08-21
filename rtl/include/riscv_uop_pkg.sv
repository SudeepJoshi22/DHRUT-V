// File: include/riscv_types_pkg.sv
package riscv_uop_pkg;

  typedef enum logic [6:0] {
    OPCODE_LOAD     = 7'b000_0011,
    OPCODE_MISC_MEM = 7'b000_1111,  // FENCE (treated as a no-op, single-hart in-order core)
    OPCODE_OP_IMM   = 7'b001_0011,
    OPCODE_AUIPC    = 7'b001_0111,
    OPCODE_STORE    = 7'b010_0011,
    OPCODE_OP       = 7'b011_0011,
    OPCODE_LUI      = 7'b011_0111,
    OPCODE_BRANCH   = 7'b110_0011,
    OPCODE_JALR     = 7'b110_0111,
    OPCODE_JAL      = 7'b110_1111,
    OPCODE_SYSTEM   = 7'b111_0011,  // CSRRW/S/C(+I), ECALL, EBREAK, MRET
    // Future: OPCODE_FMADD, etc.
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
    ALU_AND     = 10'b0_111
  } alu_op_t;

  // Micro-op structure (will grow later)
  typedef struct packed {
    logic        valid;           // valid decoded instruction
    riscv_opcode_t opcode;
    alu_op_t     alu_op;          // for arithmetic ops
    logic [4:0]  rs1, rs2, rd;    // source/dest registers
    logic [2:0]  funct3;          // original funct3 from instruction
    logic [31:0] imm;             // immediate (sign-extended)
    logic        uses_rs1;
    logic        uses_rs2;
    logic        writes_rd;
    logic        is_immediate;    // OP-IMM vs OP
    logic        is_branch;       // branch instruction
    logic        is_jump;         // jump instruction (JAL/JALR)
    // LSU-specific fields (decoded in decode stage)
    logic        is_load;
    logic        is_store;
    logic        lsu_sign_extend; // 1 = sign-extend load result (LB/LH), 0 = zero-extend (LBU/LHU)
    logic [1:0]  lsu_access_size; // 00 = byte, 01 = halfword, 10 = word (for loads/stores)
    // Branch prediction (populated in IF, consumed by Issue for mispredict detection)
    logic        pred_taken;      // 1 = predicted taken (BPU hit or JAL pre-decode)
    logic [31:0] pred_target;     // predicted target PC (valid when pred_taken)
    // SYSTEM (Zicsr + trap) fields, valid when opcode == OPCODE_SYSTEM.
    // For funct3 != 0 (CSRRW/S/C, +I forms): imm[11:0] holds the CSR address.
    // For funct3 == 0 (ECALL/EBREAK/MRET):     imm[11:0] holds funct12.
    // is_illegal is also set (with opcode outside OPCODE_SYSTEM) for any
    // unrecognized/reserved instruction encoding -> illegal-instruction trap.
    logic        is_illegal;
    logic [31:0] instr_bits;      // raw fetched instruction, for mtval on illegal-instruction traps
    // Future fields:
    // fpu_op_t     fpu_op;       // for F/D extension
  } uop_t;

endpackage
