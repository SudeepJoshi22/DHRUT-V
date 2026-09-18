import riscv_uop_pkg::*;

module retire (
  input  logic        clk,
  input  logic        rst_n,

  // From ALU/Compute stage
  input  logic        i_alu_valid,
  input  uop_t        i_alu_uop,
  input  logic [31:0] i_alu_result,

  // From LSU stage
  input logic        i_lsu_valid,
  input uop_t        i_lsu_uop,
  input logic [31:0] i_lsu_load_data,
  // RV32M result. Multi-cycle, so unlike the ALU and LSU it can become
  // ready on a cycle the lane was otherwise busy -- cpu_core stalls ALU0
  // on exactly that cycle to keep this port free. Tied off on lane 1.
  input logic        i_mdu_valid,
  input uop_t        i_mdu_uop,
  input logic [31:0] i_mdu_result,

  // Flush from downstream (e.g. exception) or upstream (branch mispredict)
  input  logic        i_flush,

  // Stall from downstream (rare in in-order, but for future)
  input  logic        i_stall,

  // Operand forward to ISSUE 
  output logic [4:0]  o_retire_fwd_rd,           
  output logic [31:0] o_retire_fwd_result,       
  output logic        o_retire_fwd_writes_rd,  // Outputs to next stage (e.g. MEM/Retire)
  
  // To ARF (write-back)
  output logic        o_wb_en,
  output logic [4:0]  o_wb_rd,
  output logic [31:0] o_wb_data
);

  // ───────────────────────────────────────────────
  // 1. Pipeline Registers (ALU → Retire)
  // ───────────────────────────────────────────────
  logic        valid_q;
  uop_t        uop_q;
  logic [31:0] result_q;

  // i_flush is a synchronous clear, kept out of the async-reset condition --
  // see the note in alu_stage.sv.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_q       <= 1'b0;
      uop_q         <= '0;
      result_q  <= '0;
    end
    else if (i_flush) begin
      valid_q       <= 1'b0;
      uop_q         <= '0;
      result_q  <= '0;
    end
    else if (!i_stall) begin
      // In-order: only one should be valid.
      //
      // The MDU is checked FIRST, and that ordering is load-bearing. Its
      // result appears several cycles after dispatch, so it can land on a
      // cycle when ALU0 also has one. cpu_core resolves that by stalling
      // ALU0 whenever the MDU completes: ALU0's result is held in its own
      // output register and retires the cycle after, which preserves
      // program order because the multiply/divide was dispatched first.
      if (i_mdu_valid) begin
        valid_q   <= 1'b1;
        uop_q     <= i_mdu_uop;
        result_q  <= i_mdu_result;
      end
      else if (i_alu_valid) begin
        valid_q   <= 1'b1;
        uop_q     <= i_alu_uop;
        result_q  <= i_alu_result;
      end
      else if (i_lsu_valid) begin
        valid_q   <= 1'b1;
        uop_q     <= i_lsu_uop;
        result_q  <= i_lsu_load_data;
      end
      else begin
        valid_q   <= 1'b0;
        uop_q     <= '0;
        result_q  <= '0;
      end
    end
    // else stall → hold current values
  end
  // ───────────────────────────────────────────────
  // 2. Operand forwarding to ISSUE Stage
  // ───────────────────────────────────────────────
  assign    o_retire_fwd_rd         = uop_q.rd;
  assign    o_retire_fwd_result     = result_q;
  assign    o_retire_fwd_writes_rd  = uop_q.writes_rd;

  // ───────────────────────────────────────────────
  // 3. Register Write-Back (to ARF)
  // ───────────────────────────────────────────────
  always_comb begin
    o_wb_en   = valid_q && uop_q.writes_rd && !i_flush;
    o_wb_rd   = uop_q.rd;
    o_wb_data = result_q;
  end

endmodule
