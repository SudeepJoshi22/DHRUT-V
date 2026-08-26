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
  // How many queue entries Decode consumed this cycle (0..2). This replaces
  // the old i_stall input: a downstream stall is simply i_pop_cnt == 0, and
  // fetch itself is gated on queue space rather than on decode's state.
  input  logic [1:0]  i_pop_cnt,
  input  logic        i_flush,
  input  logic [31:0] i_redirect_pc,

  mem_if.master       imem,               // master modport

  // Pre-decode -> BPU prediction query (combinational, same cycle as imem response)
  output logic        o_bpu_pred_is_branch,
  output logic [31:0] o_bpu_pred_pc,
  output logic [31:0] o_bpu_pred_offset_pc,
  input  logic        i_bpu_pred_taken,
  input  logic [31:0] i_bpu_pred_target,

  // Queue head pair handed to Decode. Index 0 is the older instruction;
  // o_if_valid[1] implies o_if_valid[0].
  output logic [1:0]       o_if_valid,
  output logic [1:0][31:0] o_if_pc,
  output logic [1:0][31:0] o_if_instr,
  output logic [1:0]       o_if_pred_taken,
  output logic [1:0][31:0] o_if_pred_target
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

  // =================================================================
  // 64-bit fetch: one access returns an 8-byte aligned block holding two
  // instructions. Slot 0 is the word at the aligned address, slot 1 the
  // word 4 bytes above it.
  //
  // pc_q[2] selects how much of the block is usable:
  //   pc_q[2]==0 -> pc_q is slot 0, both slots usable
  //   pc_q[2]==1 -> pc_q is slot 1, slot 0 lies *before* pc_q and is
  //                 discarded. That waste only happens on the first
  //                 access after a redirect; the queue absorbs the rest.
  // =================================================================
  logic        fetch_fire;
  logic [31:0] aligned_addr;
  logic [31:0] pc0, pc1;
  logic [31:0] instr0, instr1;
  logic        slot0_usable, slot1_usable;

  assign fetch_fire   = imem.m_valid && imem.s_ready;
  assign aligned_addr = {pc_q[31:3], 3'b000};
  assign pc0          = aligned_addr;
  assign pc1          = aligned_addr + 32'd4;
  assign instr0       = imem.s_rdata[31:0];
  assign instr1       = imem.s_rdata[63:32];

  assign slot0_usable = fetch_fire && !pc_q[2];
  assign slot1_usable = fetch_fire;

  // Immediate extraction, mirroring decode.sv's imm_b / imm_j.
  function automatic logic [31:0] b_imm(input logic [31:0] w);
    return {{19{w[31]}}, w[31], w[7], w[30:25], w[11:8], 1'b0};
  endfunction

  function automatic logic [31:0] j_imm(input logic [31:0] w);
    return {{11{w[31]}}, w[31], w[19:12], w[20], w[30:21], 1'b0};
  endfunction

  // Per-slot pre-decode, each against its own PC.
  logic        s0_is_branch, s0_is_jal, s1_is_branch, s1_is_jal;
  logic        s0_is_jalr, s1_is_jalr;
  logic [31:0] s0_btarget, s0_jtarget, s1_btarget, s1_jtarget;

  assign s0_is_branch = slot0_usable && (riscv_opcode_t'(instr0[6:0]) == OPCODE_BRANCH);
  assign s0_is_jal    = slot0_usable && (riscv_opcode_t'(instr0[6:0]) == OPCODE_JAL);
  assign s0_is_jalr   = slot0_usable && (riscv_opcode_t'(instr0[6:0]) == OPCODE_JALR);
  assign s0_btarget   = pc0 + b_imm(instr0);
  assign s0_jtarget   = pc0 + j_imm(instr0);

  assign s1_is_branch = slot1_usable && (riscv_opcode_t'(instr1[6:0]) == OPCODE_BRANCH);
  assign s1_is_jal    = slot1_usable && (riscv_opcode_t'(instr1[6:0]) == OPCODE_JAL);
  assign s1_is_jalr   = slot1_usable && (riscv_opcode_t'(instr1[6:0]) == OPCODE_JALR);
  assign s1_btarget   = pc1 + b_imm(instr1);
  assign s1_jtarget   = pc1 + j_imm(instr1);

  // =================================================================
  // Return Address Stack: call/return classification
  // =================================================================
  // Per the RISC-V spec's JALR hint rules, x1 and x5 are the link
  // registers. See rtl/pipeline/ras.sv for the full table.
  function automatic logic is_link(input logic [4:0] r);
    return (r == 5'd1) || (r == 5'd5);
  endfunction

  logic s0_rd_link, s0_rs1_link, s1_rd_link, s1_rs1_link;
  logic s0_is_call, s0_is_ret, s1_is_call, s1_is_ret;

  assign s0_rd_link  = is_link(instr0[11:7]);
  assign s0_rs1_link = is_link(instr0[19:15]);
  assign s1_rd_link  = is_link(instr1[11:7]);
  assign s1_rs1_link = is_link(instr1[19:15]);

  // A call is a JAL or JALR that links (rd is x1/x5). A return is a JALR
  // reading a link register, except the rd==rs1 case which the spec
  // classifies as a pure push.
  assign s0_is_call = (s0_is_jal || s0_is_jalr) && s0_rd_link;
  assign s0_is_ret  = s0_is_jalr && s0_rs1_link &&
                      !(s0_rd_link && (instr0[11:7] == instr0[19:15]));
  assign s1_is_call = (s1_is_jal || s1_is_jalr) && s1_rd_link;
  assign s1_is_ret  = s1_is_jalr && s1_rs1_link &&
                      !(s1_rd_link && (instr1[11:7] == instr1[19:15]));

  logic        ras_top_valid;
  logic [31:0] ras_top_pc;
  logic        ras_push, ras_pop;
  logic [31:0] ras_push_pc;

  // A return is only predicted when the stack actually holds something;
  // otherwise this falls back to the old behaviour (no prediction, Issue
  // resolves and redirects).
  logic s0_ret_pred, s1_ret_pred;
  assign s0_ret_pred = s0_is_ret && ras_top_valid;

  // =================================================================
  // BPU query: the predictor has a single port, so query the FIRST
  // branch in the group. Control leaves the group at the first taken
  // branch, so a second prediction could not be acted on this cycle.
  // If slot 0 is a branch, slot 1's branch (if any) goes unqueried and
  // defaults to not-taken; that is safe - a prediction is only a hint,
  // and Issue still resolves it and redirects on a real mispredict.
  // =================================================================
  logic query_s0, query_s1;

  assign query_s0 = s0_is_branch;
  // Only query for slot 1 if control actually reaches it. A JAL in slot 0
  // redirects away, so slot 1 is not on the fetched path and querying it
  // would train a BTB entry for an instruction we never execute - that
  // pollution shows up later as bogus predicted-taken with a stale target.
  // Gating on s0_is_jal (not s0_taken) keeps this combinationally safe:
  // query_s1 already requires !s0_is_branch, so it never depends on the
  // BPU's own response.
  assign query_s1 = !s0_is_branch && !s0_is_jal && s1_is_branch;

  assign o_bpu_pred_is_branch = query_s0 || query_s1;
  assign o_bpu_pred_pc        = query_s0 ? pc0 : pc1;
  assign o_bpu_pred_offset_pc = query_s0 ? s0_btarget : s1_btarget;

  // Per-slot "control leaves here" decision and its target.
  logic        s0_taken, s1_taken;
  logic [31:0] s0_target, s1_target;

  assign s0_taken  = (s0_is_branch && i_bpu_pred_taken) || s0_is_jal || s0_ret_pred;
  assign s0_target = (s0_is_branch && i_bpu_pred_taken) ? i_bpu_pred_target :
                     s0_is_jal                         ? s0_jtarget        :
                                                         ras_top_pc;

  // Slot 1 gets a return prediction only when slot 0 is not itself a
  // JALR. A JALR in slot 0 always transfers control, so slot 1 is off the
  // architectural path; and slot 0's own RAS update would not yet be
  // visible on ras_top_pc (it is registered), so slot 1 would predict
  // from a stale top.
  assign s1_ret_pred = s1_is_ret && ras_top_valid && !s0_is_jalr;

  assign s1_taken  = (query_s1 && i_bpu_pred_taken) || s1_is_jal || s1_ret_pred;
  assign s1_target = (query_s1 && i_bpu_pred_taken) ? i_bpu_pred_target :
                     s1_is_jal                     ? s1_jtarget        :
                                                     ras_top_pc;

  // =================================================================
  // Group assembly: map the usable, non-truncated instructions onto the
  // queue's two push ports in program order. Port A is always the older.
  // =================================================================
  logic        pushA, pushB;
  logic [31:0] pcA, instrA, predtA;
  logic [31:0] pcB, instrB, predtB;
  logic        ptA, ptB;
  logic [31:0] next_pc;

  always_comb begin
    pushA  = 1'b0;  pushB  = 1'b0;
    pcA    = pc0;   instrA = instr0;  ptA = 1'b0;  predtA = pc0 + 32'd4;
    pcB    = pc1;   instrB = instr1;  ptB = 1'b0;  predtB = pc1 + 32'd4;
    next_pc = aligned_addr + 32'd8;

    if (slot0_usable) begin
      // Both slots in play: A = slot0, B = slot1.
      pushA  = 1'b1;
      pcA    = pc0;  instrA = instr0;
      ptA    = s0_taken;
      predtA = s0_taken ? s0_target : (pc0 + 32'd4);

      if (s0_taken) begin
        // Control leaves at slot 0 -> slot 1 is not on the taken path.
        pushB   = 1'b0;
        next_pc = s0_target;
      end
      else begin
        pushB  = 1'b1;
        pcB    = pc1;  instrB = instr1;
        ptB    = s1_taken;
        predtB = s1_taken ? s1_target : (pc1 + 32'd4);
        next_pc = s1_taken ? s1_target : (aligned_addr + 32'd8);
      end
    end
    else if (slot1_usable) begin
      // Misaligned entry (pc_q[2]==1): only slot 1 is at/after pc_q.
      pushA  = 1'b1;
      pcA    = pc1;  instrA = instr1;
      ptA    = s1_taken;
      predtA = s1_taken ? s1_target : (pc1 + 32'd4);
      pushB  = 1'b0;
      next_pc = s1_taken ? s1_target : (aligned_addr + 32'd8);
    end
  end

  // =================================================================
  // Return Address Stack: update selection
  // =================================================================
  // At most ONE stack operation per fetch group. A JAL or JALR always
  // transfers control, so once slot 0 holds one, slot 1 is off the path
  // and must not touch the stack. Slot 1 only acts when slot 0 is neither
  // a JAL/JALR nor a predicted-taken branch.
  //
  // Only fired on a completed fetch (fetch_fire): a request that never
  // handshakes has not really fetched those instructions, and pushing for
  // it would corrupt the call depth.
  logic ras_from_s0, ras_from_s1;

  assign ras_from_s0 = s0_is_jal || s0_is_jalr;
  assign ras_from_s1 = !ras_from_s0
                    && !(s0_is_branch && i_bpu_pred_taken)
                    && (s1_is_jal || s1_is_jalr);

  always_comb begin
    ras_push    = 1'b0;
    ras_pop     = 1'b0;
    ras_push_pc = pc0 + 32'd4;

    if (fetch_fire && !i_flush) begin
      if (ras_from_s0) begin
        ras_push    = s0_is_call;
        ras_pop     = s0_is_ret;
        ras_push_pc = pc0 + 32'd4;
      end
      else if (ras_from_s1) begin
        ras_push    = s1_is_call;
        ras_pop     = s1_is_ret;
        ras_push_pc = pc1 + 32'd4;
      end
    end
  end

  ras RAS (
    .clk       (clk),
    .rst_n     (rst_n),
    .i_push    (ras_push),
    .i_pop     (ras_pop),
    .i_push_pc (ras_push_pc),
    .o_top     (ras_top_pc),
    .o_valid   (ras_top_valid)
  );

  // =================================================================
  // PC Update Logic
  // =================================================================
  // Priority: mispredict/flush-redirect > group-derived next_pc, which
  // itself encodes predicted-taken-branch > JAL > sequential.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc_q <= RESET_PC;
    end
    else if (i_flush) begin
      // Immediate redirection on flush pulse (mispredict, highest priority)
      pc_q <= i_redirect_pc;
    end
    else if (fetch_fire) begin
      pc_q <= next_pc;
    end
  end

  // =================================================================
  // Memory Interface
  // =================================================================
  // Request whenever we aren't flushing and the queue can accept a full
  // 2-instruction group. fq_full already accounts for a simultaneous pop,
  // so there is deliberately no `|| pop` override here: at full occupancy
  // a 1-entry pop frees only ONE slot, which is not enough for a pair, and
  // pushing anyway silently drops an instruction.
  // Deliberately not gated on any downstream stall: a stalled consumer
  // fills the queue rather than stopping fetch, and an imem stall drains
  // the queue rather than starving decode.
  assign imem.m_valid = !i_flush && !fq_full;
  assign imem.m_addr  = aligned_addr;
  assign imem.m_wdata = '0;
  assign imem.m_wstrb = '0;
  assign imem.m_flush = i_flush;

  // =================================================================
  // Fetch Queue (decouples fetch from decode)
  // =================================================================
  fetch_queue #(
    .DEPTH          (FQ_DEPTH)
  ) FQ (
    .clk            (clk),
    .rst_n          (rst_n),
    .i_flush        (i_flush),
    .i_push0        (pushA),
    .i_pc0          (pcA),
    .i_instr0       (instrA),
    .i_pred_taken0  (ptA),
    .i_pred_target0 (predtA),
    .i_push1        (pushB),
    .i_pc1          (pcB),
    .i_instr1       (instrB),
    .i_pred_taken1  (ptB),
    .i_pred_target1 (predtB),
    .o_full         (fq_full),
    .i_pop_cnt      (i_pop_cnt),
    .o_empty        (fq_empty),
    .o_valid        (o_if_valid),
    .o_pc           (o_if_pc),
    .o_instr        (o_if_instr),
    .o_pred_taken   (o_if_pred_taken),
    .o_pred_target  (o_if_pred_target)
  );

  // o_if_valid/o_if_pc/o_if_instr/o_if_pred_* are driven directly by the
  // queue's two read ports; there is nothing left to assign here.

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

  // Does the fetch completing this cycle leave control inside the block
  // we just fetched? With 64-bit block fetch this covers both the spin
  // loop (`j .`) and a short forward branch whose target is the other
  // half of the same block - in either case re-requesting the same
  // aligned address is architecturally correct, not a duplicate-handshake
  // bug. (The second case also re-enters with pc_q[2]==1, so only the
  // still-unexecuted half of the block gets queued.)
  assign self_redirect = (next_pc[31:3] == aligned_addr[31:3]);

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
  //
  //    With a 2-wide pop the tracked value is the YOUNGEST entry taken
  //    this cycle, and the check is against the OLDEST entry taken next
  //    time - i.e. the two PCs that are adjacent in dispatch order. The
  //    pair popped together is guaranteed distinct by the queue's
  //    push-contiguity assertion, so there is nothing to check within a
  //    group.
  logic [31:0] last_dispatch_pc_q;
  logic        last_dispatch_self_q;
  logic [31:0] youngest_pop_pc;
  logic        youngest_pop_self;

  always_comb begin
    if (i_pop_cnt == 2'd2) begin
      youngest_pop_pc   = o_if_pc[1];
      youngest_pop_self = o_if_pred_taken[1] && (o_if_pred_target[1] == o_if_pc[1]);
    end
    else begin
      youngest_pop_pc   = o_if_pc[0];
      youngest_pop_self = o_if_pred_taken[0] && (o_if_pred_target[0] == o_if_pc[0]);
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || i_flush) begin
      last_dispatch_pc_q   <= 32'hFFFFFFFF;
      last_dispatch_self_q <= 1'b0;
    end
    else if (i_pop_cnt != 2'd0) begin
      last_dispatch_pc_q   <= youngest_pop_pc;
      last_dispatch_self_q <= youngest_pop_self;
    end
  end

  assert_no_duplicate_dispatch: assert property (
    @(posedge clk) disable iff (!rst_n || i_flush)
    (i_pop_cnt != 2'd0) |-> ((o_if_pc[0] != last_dispatch_pc_q) || last_dispatch_self_q)
  ) else $error("FETCH ERROR: Duplicate dispatch to Decode for PC=0x%h", o_if_pc[0]);

  // 3. Fetch never runs when the queue cannot take the result (would
  //    silently drop the fetched instruction).
  assert_fetch_has_room: assert property (
    @(posedge clk) disable iff (!rst_n || i_flush)
    fetch_fire |-> !fq_full
  ) else $error("FETCH ERROR: fetch completed with no queue slot (PC=0x%h)", imem.m_addr);

  // 4. The queue's two ways of reporting "nothing to hand over" must agree:
  //    o_empty (pointer equality) and the head port's own valid. A
  //    disagreement would mean Decode either sees a phantom entry or misses
  //    a real one.
  assert_empty_matches_head_valid: assert property (
    @(posedge clk) disable iff (!rst_n)
    (o_if_valid[0] == !fq_empty)
  ) else $error("FETCH ERROR: queue o_empty=%0b disagrees with head valid=%0b",
                fq_empty, o_if_valid[0]);
`endif

endmodule
