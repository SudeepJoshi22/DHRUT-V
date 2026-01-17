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

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || i_flush) begin
      valid_q       <= 1'b0;
      uop_q         <= '0;
      result_q  <= '0;
    end
    else if (!i_stall) begin
      // In-order: only one should be valid
      if (i_alu_valid) begin
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
  // 2. Register Write-Back (to ARF)
  // ───────────────────────────────────────────────
  always_comb begin
    o_wb_en   = valid_q && uop_q.writes_rd && !i_flush;
    o_wb_rd   = uop_q.rd;
    o_wb_data = result_q;
  end

endmodule
