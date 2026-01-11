import riscv_uop_pkg::*;

interface alu_issue_if (input logic clk, rst_n);
  // Master (ISSUE) → Slave (ALU)
  logic        m_valid;
  uop_t        m_uop;
  logic [31:0] m_pc;
  logic [31:0] m_op1;          // operand 1 (rs1 or PC)
  logic [31:0] m_op2;          // operand 2 (rs2 or imm)

  modport issuer (output m_valid, m_uop, m_pc, m_op1, m_op2);
  modport alu    (input  m_valid, m_uop, m_pc, m_op1, m_op2);
endinterface

// ───────────────────────────────────────────────
// Interface for issuing to LSU (load/store path)
// ───────────────────────────────────────────────
interface lsu_issue_if (input logic clk, rst_n);
  // Master (ISSUE) → Slave (LSU)
  logic        m_valid;
  uop_t        m_uop;
  logic [31:0] m_pc;
  logic [31:0] m_addr_base;    // base address (rs1 + imm offset)
  logic [31:0] m_store_data;   // data to store (rs2)

  // Slave (LSU) → Master (ISSUE) back-pressure
  logic        s_stall_from_lsu;   // LSU asserts this when busy/taking time

  modport issuer (output m_valid, m_uop, m_pc, m_addr_base, m_store_data,
                  input  s_stall_from_lsu);

  modport lsu    (input  m_valid, m_uop, m_pc, m_addr_base, m_store_data,
                  output s_stall_from_lsu);
endinterface
