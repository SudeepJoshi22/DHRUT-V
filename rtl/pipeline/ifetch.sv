import riscv_uop_pkg::*;

// =================================================================
// Pre-decode helper (combinational)
// =================================================================
// Detects whether the word returning from imem this cycle is a
// conditional branch or a JAL, and (for JAL) computes its target
// directly from the immediate — no BTB entry needed since JAL is
// PC-relative and register-independent.

module if_stage (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        i_stall,
  input  logic        i_flush,
  input  logic [31:0] i_redirect_pc,

  mem_if.master       imem,               // master modport

  // Pre-decode -> BPU prediction query (combinational, same cycle as imem response)
  output logic        o_bpu_pred_is_branch,
  output logic [31:0] o_bpu_pred_pc,
  output logic [31:0] o_bpu_pred_offset_pc,
  input  logic        i_bpu_pred_taken,
  input  logic [31:0] i_bpu_pred_target,

  output logic        o_if_valid,
  output logic [31:0] o_if_pc,
  output logic [31:0] o_if_instr,
  output logic        o_if_pred_taken,
  output logic [31:0] o_if_pred_target
);

  parameter logic [31:0] RESET_PC = 32'h8000_0000;

  logic [31:0] pc_q;

  // Instruction Buffer Registers
  logic [31:0] instr_q;
  logic [31:0] instr_pc_q;
  logic        instr_valid_q;
  logic        pred_taken_q;
  logic [31:0] pred_target_q;

  // =================================================================
  // Pre-decode of the word returning from imem this cycle
  // (combinational: memory is read-in-cycle, so s_rdata is valid
  //  whenever the fetch handshake fires this same cycle)
  // =================================================================
  logic        fetch_fire;
  logic        predec_is_branch;
  logic        predec_is_jal;
  logic [31:0] predec_branch_offset;  // branch target PC (for BTB allocate/lookup)
  logic [31:0] predec_jal_target;     // JAL target PC (computed directly, no BTB)

  assign fetch_fire       = imem.m_valid && imem.s_ready;
  assign predec_is_branch = fetch_fire && (riscv_opcode_t'(imem.s_rdata[6:0]) == OPCODE_BRANCH);
  assign predec_is_jal    = fetch_fire && (riscv_opcode_t'(imem.s_rdata[6:0]) == OPCODE_JAL);

  // B-type immediate (mirrors decode.sv's imm_b)
  assign predec_branch_offset = pc_q + {{19{imem.s_rdata[31]}}, imem.s_rdata[31], imem.s_rdata[7],
                                         imem.s_rdata[30:25], imem.s_rdata[11:8], 1'b0};
  // J-type immediate (mirrors decode.sv's imm_j)
  assign predec_jal_target = pc_q + {{11{imem.s_rdata[31]}}, imem.s_rdata[31], imem.s_rdata[19:12],
                                      imem.s_rdata[20], imem.s_rdata[30:21], 1'b0};

  // BPU prediction query (combinational lookup, result available same cycle)
  assign o_bpu_pred_is_branch = predec_is_branch;
  assign o_bpu_pred_pc        = pc_q;
  assign o_bpu_pred_offset_pc = predec_branch_offset;

  // =================================================================
  // PC Update Logic
  // =================================================================
  // Priority: mispredict/flush-redirect > BPU-predicted-taken redirect
  //           > JAL-predicted redirect > sequential PC+4 (default).
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc_q <= RESET_PC;
    end
    else if (i_flush) begin
      // Immediate redirection on flush pulse (mispredict, highest priority)
      pc_q <= i_redirect_pc;
    end
    else if (fetch_fire) begin
      if (predec_is_branch && i_bpu_pred_taken) begin
        // BPU predicts this branch taken -> redirect to predicted target
        pc_q <= i_bpu_pred_target;
      end
      else if (predec_is_jal) begin
        // JAL always taken, target computable from immediate at fetch time
        pc_q <= predec_jal_target;
      end
      else begin
        // Sequential default
        pc_q <= pc_q + 32'd4;
      end
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
      pred_taken_q  <= 1'b0;
      pred_target_q <= 32'd0;
    end
    else begin
      if (fetch_fire) begin
        // Latch new instruction from memory
        instr_valid_q <= 1'b1;
        instr_q       <= imem.s_rdata;
        instr_pc_q    <= pc_q;
        // Latch the prediction made for this fetched instruction
        if (predec_is_branch && i_bpu_pred_taken) begin
          pred_taken_q  <= 1'b1;
          pred_target_q <= i_bpu_pred_target;
        end
        else if (predec_is_jal) begin
          pred_taken_q  <= 1'b1;
          pred_target_q <= predec_jal_target;
        end
        else begin
          pred_taken_q  <= 1'b0;
          pred_target_q <= pc_q + 32'd4;
        end
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
  assign o_if_valid      = instr_valid_q;
  assign o_if_pc         = instr_pc_q;
  assign o_if_instr      = instr_q;
  assign o_if_pred_taken  = pred_taken_q;
  assign o_if_pred_target = pred_target_q;

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
