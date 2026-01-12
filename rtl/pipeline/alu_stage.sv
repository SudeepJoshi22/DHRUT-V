import riscv_uop_pkg::*;

module alu_stage (
  input  logic        clk,
  input  logic        rst_n,

  // From ISSUE (via interface)
  alu_issue_if.alu    issue_if,

  // Control from downstream
  input  logic        i_stall,    // stall from later stages
  input  logic        i_flush,    // flush from branch/exception

  // Outputs to next stage (e.g. MEM/Retire)
  output logic        o_valid,
  output logic [31:0] o_alu_result,
  output uop_t        o_uop_forward   // pass uop forward (for write-back, etc.)
);

  // ───────────────────────────────────────────────
  // Input Pipeline Registers (hold during stall)
  // ───────────────────────────────────────────────
  logic        valid_q;
  uop_t        uop_q;
  logic [31:0] op1_q;
  logic [31:0] op2_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || i_flush) begin
      valid_q <= 1'b0;
      uop_q   <= '0;
      op1_q   <= '0;
      op2_q   <= '0;
    end
    else if (!i_stall) begin
      valid_q <= issue_if.m_valid;
      uop_q   <= issue_if.m_uop;
      op1_q   <= issue_if.m_op1;
      op2_q   <= issue_if.m_op2;
    end
    // else stall → hold current values
  end

  // ───────────────────────────────────────────────
  // ALU computation (combinational)
  // ───────────────────────────────────────────────
  logic [31:0] alu_result;

  alu alu_inst (
    .i_op1     (op1_q),
    .i_op2     (op2_q),
    .i_alu_op  (uop_q.alu_op),
    .o_result  (alu_result)
  );

  // Forward results
  assign o_alu_result  = alu_result;
  assign o_uop_forward = uop_q;
  assign o_valid       = valid_q & !i_flush;

endmodule
