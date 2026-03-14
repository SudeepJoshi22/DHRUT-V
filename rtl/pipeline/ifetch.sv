import riscv_uop_pkg::*;

module if_stage (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        i_stall,
  input  logic        i_flush,
  input  logic [31:0] i_redirect_pc,

  mem_if.master       imem,               // master modport

  output logic        o_if_valid,
  output logic [31:0] o_if_pc,
  output logic [31:0] o_if_instr
);

  parameter logic [31:0] RESET_PC = 32'h8000_0000;

  logic [31:0] pc_q;
  
  // Instruction Buffer Registers
  logic [31:0] instr_q;
  logic [31:0] instr_pc_q;
  logic        instr_valid_q;

  // =================================================================
  // PC Update Logic
  // =================================================================
  // Rule 1: Flush (Branch/Jump) always has highest priority.
  // Rule 2: Only increment PC when a fetch actually completes.
  // Rule 3: Hold PC during stalls.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc_q <= RESET_PC;
    end 
    else if (i_flush) begin
      // Immediate redirection on flush pulse
      pc_q <= i_redirect_pc;
    end
    else if (imem.m_valid && imem.s_ready) begin
      // Advance to next sequential instruction whenever a fetch handshake completes
      pc_q <= pc_q + 32'd4;
    end
  end

  // =================================================================
  // Memory Interface
  // =================================================================
  // Request a new instruction whenever:
  // - We aren't stalled by downstream
  // - We aren't currently being flushed
  // - The buffer is empty OR is being consumed this cycle
  assign imem.m_valid = !i_flush && (!instr_valid_q || !i_stall);
  assign imem.m_addr  = pc_q;
  assign imem.m_wdata = '0;
  assign imem.m_wstrb = 4'b0000;
  assign imem.m_flush = i_flush;

  // =================================================================
  // Instruction Buffer
  // =================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || i_flush) begin
      instr_valid_q <= 1'b0;
      instr_q       <= 32'd0;
      instr_pc_q    <= 32'd0;
    end
    else begin
      if (imem.m_valid && imem.s_ready) begin
        // Latch new instruction from memory
        instr_valid_q <= 1'b1;
        instr_q       <= imem.s_rdata;
        instr_pc_q    <= pc_q;
      end
      else if (!i_stall) begin
        // Downstream accepted the current instruction, buffer now empty
        instr_valid_q <= 1'b0;
      end
    end
  end
  
  // =================================================================
  // Output Assignments
  // =================================================================
  assign o_if_valid = instr_valid_q;
  assign o_if_pc    = instr_pc_q;
  assign o_if_instr = instr_q;

`ifdef SIMULATION
  // ───────────────────────────────────────────────────────────────────────────
  // Assertions to catch duplicate PC issues
  // ───────────────────────────────────────────────────────────────────────────
  
  // 1. No Duplicate Fetch: Ensure we don't fetch the same PC twice in a row
  logic [31:0] last_fetched_pc_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) last_fetched_pc_q <= 32'hFFFFFFFF;
    else if (imem.m_valid && imem.s_ready) last_fetched_pc_q <= imem.m_addr;
  end

  assert_no_duplicate_fetch: assert property (
    @(posedge clk) disable iff (!rst_n || i_flush)
    (imem.m_valid && imem.s_ready) |-> (imem.m_addr != last_fetched_pc_q)
  ) else $error("FETCH ERROR: Duplicate memory request for PC=0x%h", imem.m_addr);

  // 2. No Duplicate Dispatch: Ensure we don't send the same instruction to Decode twice
  assert_no_duplicate_dispatch: assert property (
    @(posedge clk) disable iff (!rst_n || i_flush)
    (o_if_valid && !i_stall) |=> (o_if_valid ? o_if_pc != $past(o_if_pc) : 1'b1)
  ) else $error("FETCH ERROR: Duplicate dispatch to Decode for PC=0x%h", o_if_pc);
`endif

endmodule
