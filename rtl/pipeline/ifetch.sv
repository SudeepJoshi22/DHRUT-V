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

  // Depth of the decoupling fetch queue (must be a power of 2).
  // This replaces the old single-entry instruction buffer: fetch keeps
  // running ahead while the queue has room, so imem stalls drain the
  // queue instead of starving decode immediately.
  parameter int FQ_DEPTH = 8;

  logic [31:0] pc_q;

  // Fetch queue (IF -> ID decoupling buffer), see rtl/pipeline/fetch_queue.sv
  logic        fq_full;
  logic        fq_empty;
  logic        fq_push;
  logic        fq_pop;
  logic        fq_pred_taken;    // prediction latched with the fetched word
  logic [31:0] fq_pred_target;

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
  // - We aren't currently being flushed
  // - The fetch queue has a free slot, or one is being freed this cycle
  //   by decode consuming the head entry
  // Note this is deliberately NOT gated on i_stall any more: with the
  // queue in place, a downstream stall fills the queue (fetch runs
  // ahead) rather than stopping the fetch engine, and an imem stall
  // drains the queue rather than starving decode.
  assign imem.m_valid = !i_flush && (!fq_full || fq_pop);
  assign imem.m_addr  = pc_q;
  assign imem.m_wdata = '0;
  assign imem.m_wstrb = 4'b0000;
  assign imem.m_flush = i_flush;

  // =================================================================
  // Fetch Queue (decouples fetch from decode)
  // =================================================================
  // Prediction recorded alongside the word fetched this cycle. Same
  // priority as the PC update above, so the queued entry always carries
  // the prediction that actually steered pc_q.
  always_comb begin
    if (predec_is_branch && i_bpu_pred_taken) begin
      fq_pred_taken  = 1'b1;
      fq_pred_target = i_bpu_pred_target;
    end
    else if (predec_is_jal) begin
      fq_pred_taken  = 1'b1;
      fq_pred_target = predec_jal_target;
    end
    else begin
      fq_pred_taken  = 1'b0;
      fq_pred_target = pc_q + 32'd4;
    end
  end

  // A completed fetch is pushed; decode pops the head whenever it isn't
  // stalling. Program order is preserved by the FIFO.
  assign fq_push = fetch_fire;
  assign fq_pop  = !fq_empty && !i_stall;

  fetch_queue #(
    .DEPTH         (FQ_DEPTH)
  ) FQ (
    .clk           (clk),
    .rst_n         (rst_n),
    .i_flush       (i_flush),
    .i_push        (fq_push),
    .i_pc          (pc_q),
    .i_instr       (imem.s_rdata),
    .i_pred_taken  (fq_pred_taken),
    .i_pred_target (fq_pred_target),
    .o_full        (fq_full),
    .i_pop         (fq_pop),
    .o_empty       (fq_empty),
    .o_pc          (o_if_pc),
    .o_instr       (o_if_instr),
    .o_pred_taken  (o_if_pred_taken),
    .o_pred_target (o_if_pred_target)
  );

  // =================================================================
  // Output Assignments
  // =================================================================
  // o_if_pc/o_if_instr/o_if_pred_* are driven directly by the queue head.
  assign o_if_valid = !fq_empty;

`ifdef SIMULATION
  // ───────────────────────────────────────────────────────────────────────────
  // Assertions to catch duplicate PC issues
  // ───────────────────────────────────────────────────────────────────────────
  // Both checks below carry a "self redirect" exemption. A self-targeting
  // control transfer (`j .`, or a backward branch to itself) legitimately
  // makes pc_q keep its value across a fetch, so the same PC is fetched
  // and dispatched repeatedly - that is architecturally correct, not the
  // duplicate-handshake bug these assertions guard against. The exemption
  // is precise: it only applies when the *previous* fetch/dispatch was
  // itself predicted to redirect to its own PC. Because the fetch queue
  // lets fetch run far ahead, such spin loops are now routinely reached.

  // 1. No Duplicate Fetch: don't re-request a PC we just fetched, unless
  //    that fetch was a self-targeting redirect.
  logic [31:0] last_fetched_pc_q;
  logic        self_redirect;
  logic        last_fetch_self_q;

  // Does the fetch completing this cycle steer pc_q back to itself?
  // (mirrors the PC update priority above)
  assign self_redirect = (predec_is_branch && i_bpu_pred_taken) ? (i_bpu_pred_target == pc_q)
                       : predec_is_jal                          ? (predec_jal_target == pc_q)
                       :                                          1'b0;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || i_flush) begin
      // A flush redirects pc_q, so the pre-flush history says nothing
      // about whether the next request is a duplicate.
      last_fetched_pc_q <= 32'hFFFFFFFF;
      last_fetch_self_q <= 1'b0;
    end
    else if (fetch_fire) begin
      last_fetched_pc_q <= imem.m_addr;
      last_fetch_self_q <= self_redirect;
    end
  end

  assert_no_duplicate_fetch: assert property (
    @(posedge clk) disable iff (!rst_n || i_flush)
    fetch_fire |-> ((imem.m_addr != last_fetched_pc_q) || last_fetch_self_q)
  ) else $error("FETCH ERROR: Duplicate memory request for PC=0x%h", imem.m_addr);

  // 2. No Duplicate Dispatch: don't hand the same instruction to Decode
  //    twice. With the queue, a dispatched entry is popped, so a repeat
  //    can only come from a genuinely re-fetched PC. The previous form
  //    compared against $past(o_if_pc) one cycle later; tracking the last
  //    *dispatched* PC instead keeps the check alive across stall cycles
  //    and across queue-empty gaps.
  logic [31:0] last_dispatch_pc_q;
  logic        last_dispatch_self_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || i_flush) begin
      last_dispatch_pc_q   <= 32'hFFFFFFFF;
      last_dispatch_self_q <= 1'b0;
    end
    else if (o_if_valid && !i_stall) begin
      last_dispatch_pc_q   <= o_if_pc;
      last_dispatch_self_q <= o_if_pred_taken && (o_if_pred_target == o_if_pc);
    end
  end

  assert_no_duplicate_dispatch: assert property (
    @(posedge clk) disable iff (!rst_n || i_flush)
    (o_if_valid && !i_stall) |-> ((o_if_pc != last_dispatch_pc_q) || last_dispatch_self_q)
  ) else $error("FETCH ERROR: Duplicate dispatch to Decode for PC=0x%h", o_if_pc);

  // 3. Fetch never runs when the queue cannot take the result (would
  //    silently drop the fetched instruction).
  assert_fetch_has_room: assert property (
    @(posedge clk) disable iff (!rst_n || i_flush)
    fetch_fire |-> (!fq_full || fq_pop)
  ) else $error("FETCH ERROR: fetch completed with no queue slot (PC=0x%h)", imem.m_addr);
`endif

endmodule
