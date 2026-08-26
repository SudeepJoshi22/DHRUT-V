import riscv_uop_pkg::*;

module alu_stage (
  input  logic        clk,
  input  logic        rst_n,

  // From ISSUE (via interface)
  alu_issue_if.alu    issue_if,

  // Control from downstream
  input  logic        i_stall,    // stall from later stages
  input  logic        i_flush,    // flush from branch/exception

  // Operand Forwarding to ISSUE
  output logic [4:0]  o_alu_fwd_rd,           
  output logic [31:0] o_alu_fwd_result,       
  output logic        o_alu_fwd_writes_rd,  // Outputs to next stage (e.g. MEM/Retire)

  // Send for Retire
  output logic        o_valid,
  output logic [31:0] o_alu_result,
  output uop_t        o_uop_forward   // pass uop forward (for write-back, etc.)
);

  // ───────────────────────────────────────────────
  // Input Pipeline Registers (hold during stall)
  // ───────────────────────────────────────────────
  logic        valid_q;
  uop_t        uop_q;
  logic [31:0] pc_q;
  logic [31:0] op1_q;
  logic [31:0] op2_q;

  // i_flush is a SYNCHRONOUS clear and must be a separate branch from the
  // asynchronous reset. Folding it in as `!rst_n || i_flush` describes an
  // async load whose condition names a signal that is not in the event list;
  // strict elaborators (slang) reject it. Behaviour is unchanged -- i_flush
  // was only ever sampled at posedge clk regardless.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_q <= 1'b0;
      uop_q   <= '0;
      pc_q    <= '0;
      op1_q   <= '0;
      op2_q   <= '0;
    end
    else if (i_flush) begin
      valid_q <= 1'b0;
      uop_q   <= '0;
      pc_q    <= '0;
      op1_q   <= '0;
      op2_q   <= '0;
    end
    else if (!i_stall) begin
      valid_q <= issue_if.m_valid;
      uop_q   <= issue_if.m_uop;
      pc_q    <= issue_if.m_pc;
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

  // Outputs for Operand Forwarding
  assign o_alu_fwd_rd               = valid_q       ?   uop_q.rd        :   'd0;
  assign o_alu_fwd_result           = valid_q       ?   alu_result      :   'd0;
  assign o_alu_fwd_writes_rd        = valid_q       ?   uop_q.writes_rd :   'd0;

  // Send result to Retire.
  //
  // o_valid must be a ONE-SHOT: the input register above holds during
  // i_stall, so valid_q stays 1 for the whole stall, and Retire (whose
  // i_stall is tied 0) would latch the same result again every cycle -
  // duplicate write-backs and duplicate trace lines. Gating on !i_stall
  // means "this result is fresh and the pipeline is advancing".
  //
  // At 1-wide this was unreachable (Issue can never dispatch to the ALU
  // while the LSU is stalling, so valid_q was always 0 during a stall).
  // At 2-wide it fires immediately: lane 0 = load, lane 1 = ALU op puts
  // a valid result in this stage for the entire memory stall.
  assign o_alu_result               = alu_result;
  assign o_uop_forward              = uop_q;
  assign o_valid                    = valid_q & !i_stall & !i_flush;

endmodule
