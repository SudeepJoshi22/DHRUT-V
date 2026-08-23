// =================================================================
// fetch_queue - decoupling instruction queue between IF and ID
// =================================================================
// A synchronous, power-of-two-depth FIFO holding completed fetches
// (PC + instruction word + the branch prediction that was made for
// that instruction at fetch time).
//
// Its only job is to decouple the fetch engine from the rest of the
// pipeline: fetch may keep issuing imem requests while the queue has
// room, so an imem stall drains the queue instead of immediately
// starving decode/issue, and a downstream stall fills the queue
// instead of immediately idling the fetch engine.
//
// Behaviour notes:
//   * Read is "first-word fall-through": the head entry is presented
//     combinationally on the o_* outputs whenever !o_empty, so the
//     consumer sees an entry the cycle after it is pushed (same
//     latency as the single instruction buffer this replaces).
//   * Simultaneous push+pop is supported in every occupancy state,
//     including when full: the pop frees the slot that the push
//     writes in the same cycle. The combinational head read returns
//     the pre-update contents of that slot, so the entry being popped
//     is unaffected by the push overwriting it.
//   * i_flush clears the whole queue in a single cycle (mispredict
//     redirect). Flush has priority over push and pop.
//
// Entry payload: {pc[31:0], instr[31:0], pred_taken, pred_target[31:0]}

module fetch_queue #(
  parameter int DEPTH = 8    // number of entries, must be a power of 2 (>= 2)
) (
  input  logic        clk,
  input  logic        rst_n,

  // Synchronous flush: drops every queued entry (mispredict redirect)
  input  logic        i_flush,

  // Producer side (fetch engine)
  input  logic        i_push,
  input  logic [31:0] i_pc,
  input  logic [31:0] i_instr,
  input  logic        i_pred_taken,
  input  logic [31:0] i_pred_target,
  output logic        o_full,

  // Consumer side (decode)
  input  logic        i_pop,
  output logic        o_empty,
  output logic [31:0] o_pc,
  output logic [31:0] o_instr,
  output logic        o_pred_taken,
  output logic [31:0] o_pred_target
);

  localparam int PTR_W = $clog2(DEPTH);

  typedef struct packed {
    logic [31:0] pc;
    logic [31:0] instr;
    logic        pred_taken;
    logic [31:0] pred_target;
  } fq_entry_t;

  fq_entry_t entries_q [DEPTH];

  // One extra MSB on each pointer distinguishes full from empty.
  logic [PTR_W:0] wr_ptr_q, rd_ptr_q;

  logic [PTR_W-1:0] wr_idx, rd_idx;
  logic             push_fire, pop_fire;

  assign wr_idx = wr_ptr_q[PTR_W-1:0];
  assign rd_idx = rd_ptr_q[PTR_W-1:0];

  assign o_empty = (wr_ptr_q == rd_ptr_q);
  assign o_full  = (wr_ptr_q[PTR_W] != rd_ptr_q[PTR_W]) &&
                   (wr_ptr_q[PTR_W-1:0] == rd_ptr_q[PTR_W-1:0]);

  assign pop_fire  = i_pop  && !o_empty;
  // A push is accepted when there is a free slot, or when a pop frees
  // one in this same cycle (full + push + pop keeps occupancy at DEPTH).
  assign push_fire = i_push && (!o_full || pop_fire);

  // =================================================================
  // Storage
  // =================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < DEPTH; i++) begin
        entries_q[i] <= '0;
      end
    end
    else if (push_fire) begin
      entries_q[wr_idx] <= '{pc:          i_pc,
                             instr:       i_instr,
                             pred_taken:  i_pred_taken,
                             pred_target: i_pred_target};
    end
    // Flush does not need to clear the payload: the pointers below are
    // reset, so nothing can read a stale entry (o_empty is asserted).
  end

  // =================================================================
  // Pointers
  // =================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || i_flush) begin
      wr_ptr_q <= '0;
      rd_ptr_q <= '0;
    end
    else begin
      if (push_fire) wr_ptr_q <= wr_ptr_q + 1'b1;
      if (pop_fire)  rd_ptr_q <= rd_ptr_q + 1'b1;
    end
  end

  // =================================================================
  // Head (first-word fall-through read)
  // =================================================================
  assign o_pc          = entries_q[rd_idx].pc;
  assign o_instr       = entries_q[rd_idx].instr;
  assign o_pred_taken  = entries_q[rd_idx].pred_taken;
  assign o_pred_target = entries_q[rd_idx].pred_target;

  // =================================================================
  // Elaboration-time parameter check
  // =================================================================
  initial begin
    if ((DEPTH < 2) || ((DEPTH & (DEPTH - 1)) != 0)) begin
      $fatal(1, "fetch_queue: DEPTH must be a power of 2 and >= 2 (got %0d)", DEPTH);
    end
  end

`ifdef SIMULATION
  // ───────────────────────────────────────────────────────────────────────────
  // Queue integrity assertions
  // ───────────────────────────────────────────────────────────────────────────

  // 1. No dropped push: the producer must never present a push that the
  //    queue cannot accept (would silently lose an instruction).
  assert_no_overflow: assert property (
    @(posedge clk) disable iff (!rst_n || i_flush)
    i_push |-> (!o_full || pop_fire)
  ) else $error("FETCH QUEUE ERROR: push while full (pc=0x%h) - instruction dropped", i_pc);

  // 2. No pop of a non-existent entry.
  assert_no_underflow: assert property (
    @(posedge clk) disable iff (!rst_n || i_flush)
    i_pop |-> !o_empty
  ) else $error("FETCH QUEUE ERROR: pop while empty");

  // 3. Occupancy never exceeds DEPTH (pointer distance stays in range).
  logic [PTR_W:0] occupancy;
  assign occupancy = wr_ptr_q - rd_ptr_q;

  assert_occupancy_in_range: assert property (
    @(posedge clk) disable iff (!rst_n)
    (occupancy <= DEPTH[PTR_W:0])
  ) else $error("FETCH QUEUE ERROR: occupancy %0d exceeds DEPTH %0d", occupancy, DEPTH);

  // 4. Flush really empties the queue in a single cycle.
  assert_flush_clears: assert property (
    @(posedge clk) disable iff (!rst_n)
    i_flush |=> o_empty
  ) else $error("FETCH QUEUE ERROR: not empty the cycle after flush");
`endif

endmodule
