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
//   * Read is "first-word fall-through" and TWO entries wide: the head
//     and head+1 entries are presented combinationally on the o_*[0] and
//     o_*[1] outputs, each with its own valid, so the consumer sees an
//     entry the cycle after it is pushed (same latency as the single
//     instruction buffer this replaces) and can take a pair at once.
//     The consumer says how many it took on i_pop_cnt (0..2).
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

  // Producer side (fetch engine). Two push ports so a single 64-bit fetch
  // can enqueue both instructions of an 8-byte block in one cycle. Slot 0
  // is the older instruction; pushing slot 1 without slot 0 is illegal
  // (program order would be violated) and is checked by assertion.
  input  logic        i_push0,
  input  logic [31:0] i_pc0,
  input  logic [31:0] i_instr0,
  input  logic        i_pred_taken0,
  input  logic [31:0] i_pred_target0,

  input  logic        i_push1,
  input  logic [31:0] i_pc1,
  input  logic [31:0] i_instr1,
  input  logic        i_pred_taken1,
  input  logic [31:0] i_pred_target1,

  // Asserted when fewer than 2 free slots remain. Fetch only issues a
  // request when it can retire a full 2-instruction group, so there is
  // no partial-push path to reason about.
  output logic        o_full,

  // Consumer side (decode). Two read ports: index 0 is the head (oldest),
  // index 1 the entry behind it. o_valid[1] implies o_valid[0] - the queue
  // is contiguous, so there is never a hole between them.
  input  logic [1:0]       i_pop_cnt,
  output logic             o_empty,
  output logic [1:0]       o_valid,
  output logic [1:0][31:0] o_pc,
  output logic [1:0][31:0] o_instr,
  output logic [1:0]       o_pred_taken,
  output logic [1:0][31:0] o_pred_target
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

  logic [PTR_W-1:0] wr_idx0, wr_idx1, rd_idx0, rd_idx1;
  logic             push0_fire, push1_fire;
  logic [PTR_W:0]   occupancy;
  logic [PTR_W:0]   free_slots;
  logic [1:0]       push_count;
  logic [1:0]       pop_count;

  assign wr_idx0 = wr_ptr_q[PTR_W-1:0];
  assign wr_idx1 = wr_ptr_q[PTR_W-1:0] + 1'b1;
  assign rd_idx0 = rd_ptr_q[PTR_W-1:0];
  assign rd_idx1 = rd_ptr_q[PTR_W-1:0] + 1'b1;

  assign o_empty   = (wr_ptr_q == rd_ptr_q);
  assign occupancy = wr_ptr_q - rd_ptr_q;

  assign o_valid[0] = (occupancy >= (PTR_W + 1)'(1));
  assign o_valid[1] = (occupancy >= (PTR_W + 1)'(2));

  // "Full" means this queue cannot accept a full 2-instruction group THIS
  // cycle. It accounts for the slots a simultaneous pop frees, so the
  // producer does not need (and must not use) its own `|| pop` override:
  // at occupancy DEPTH a 1-entry pop frees only one slot, which is still
  // not enough for a pair, and pushing anyway would silently drop an
  // instruction.
  assign free_slots = (PTR_W + 1)'(DEPTH) - occupancy + (PTR_W + 1)'(pop_count);
  assign o_full     = (free_slots < (PTR_W + 1)'(2));

  // Clamp the requested pop to what the queue actually holds. A consumer
  // asking for more than o_valid offers is a bug (assert_no_underflow
  // catches it in simulation), but clamping keeps rd_ptr_q from running
  // past wr_ptr_q and corrupting the queue in silicon if it ever happens.
  always_comb begin
    unique case (i_pop_cnt)
      2'd0:    pop_count = 2'd0;
      2'd1:    pop_count = o_valid[0] ? 2'd1 : 2'd0;
      default: pop_count = o_valid[1] ? 2'd2 : (o_valid[0] ? 2'd1 : 2'd0);
    endcase
  end

  // Both pushes are accepted or neither is: fetch is gated on o_full
  // (2 free slots) so a group never needs to be split across cycles.
  assign push0_fire = i_push0;
  assign push1_fire = i_push1;
  assign push_count = {1'b0, push0_fire} + {1'b0, push1_fire};

  // =================================================================
  // Storage
  // =================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < DEPTH; i++) begin
        entries_q[i] <= '0;
      end
    end
    else begin
      if (push0_fire) begin
        entries_q[wr_idx0] <= '{pc:          i_pc0,
                                instr:       i_instr0,
                                pred_taken:  i_pred_taken0,
                                pred_target: i_pred_target0};
      end
      if (push1_fire) begin
        // Slot 1 always lands one past slot 0 when both push together;
        // when only slot 1 pushes it would alias slot 0's index, which
        // the program-order assertion below forbids.
        entries_q[push0_fire ? wr_idx1 : wr_idx0] <=
                             '{pc:          i_pc1,
                               instr:       i_instr1,
                               pred_taken:  i_pred_taken1,
                               pred_target: i_pred_target1};
      end
    end
    // Flush does not need to clear the payload: the pointers below are
    // reset, so nothing can read a stale entry (o_empty is asserted).
  end

  // =================================================================
  // Pointers
  // =================================================================
  // i_flush is a synchronous clear, kept out of the async-reset condition --
  // see the note in alu_stage.sv. Emptying the queue by zeroing both pointers
  // is what the flush did before; only the branch structure changed.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr_q <= '0;
      rd_ptr_q <= '0;
    end
    else if (i_flush) begin
      wr_ptr_q <= '0;
      rd_ptr_q <= '0;
    end
    else begin
      if (push_count != 2'd0) wr_ptr_q <= wr_ptr_q + (PTR_W + 1)'(push_count);
      if (pop_count  != 2'd0) rd_ptr_q <= rd_ptr_q + (PTR_W + 1)'(pop_count);
    end
  end

  // =================================================================
  // Head pair (first-word fall-through read)
  // =================================================================
  assign o_pc          = {entries_q[rd_idx1].pc,          entries_q[rd_idx0].pc};
  assign o_instr       = {entries_q[rd_idx1].instr,       entries_q[rd_idx0].instr};
  assign o_pred_taken  = {entries_q[rd_idx1].pred_taken,  entries_q[rd_idx0].pred_taken};
  assign o_pred_target = {entries_q[rd_idx1].pred_target, entries_q[rd_idx0].pred_target};

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

  // 1. No dropped push: the producer must never present a push the queue
  //    cannot hold (would silently lose an instruction). Fetch gates on
  //    o_full, which reserves room for a full 2-instruction group.
  assert_no_overflow: assert property (
    @(posedge clk) disable iff (!rst_n || i_flush)
    // Occupancy AFTER this cycle: simultaneous pops free slots, so pushing
    // 2 at occupancy DEPTH-1 is legal (DEPTH-1 - 1 + 2 == DEPTH).
    // pop_count is clamped to occupancy, so the subtraction cannot underflow.
    (push_count != 2'd0) |->
        ((occupancy - (PTR_W + 1)'(pop_count) + (PTR_W + 1)'(push_count)) <= DEPTH[PTR_W:0])
  ) else $error("FETCH QUEUE ERROR: push of %0d with occupancy %0d (pop=%0d) exceeds DEPTH %0d - instruction dropped",
                push_count, occupancy, pop_count, DEPTH);

  // 1b. Program order: slot 1 is the younger instruction, so it may never
  //     be pushed without slot 0 (that would reorder the group).
  assert_push_order: assert property (
    @(posedge clk) disable iff (!rst_n || i_flush)
    i_push1 |-> i_push0
  ) else $error("FETCH QUEUE ERROR: slot1 pushed without slot0 (pc1=0x%h) - program order violated", i_pc1);

  // 1c. When both push, they must be consecutive PCs (slot1 = slot0 + 4).
  assert_push_contiguous: assert property (
    @(posedge clk) disable iff (!rst_n || i_flush)
    (i_push0 && i_push1) |-> (i_pc1 == (i_pc0 + 32'd4))
  ) else $error("FETCH QUEUE ERROR: non-contiguous group pc0=0x%h pc1=0x%h", i_pc0, i_pc1);

  // 2. No pop of a non-existent entry. (pop_count clamps, so this fires on
  //    the consumer's *request*, before the clamp hides the mistake.)
  assert_no_underflow: assert property (
    @(posedge clk) disable iff (!rst_n || i_flush)
    ((PTR_W + 1)'(i_pop_cnt) <= occupancy)
  ) else $error("FETCH QUEUE ERROR: pop of %0d with occupancy %0d", i_pop_cnt, occupancy);

  // 3. Occupancy never exceeds DEPTH (pointer distance stays in range).
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
