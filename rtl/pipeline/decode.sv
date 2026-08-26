import riscv_uop_pkg::*;

// =================================================================
// decode_stage - 2-wide instruction decode
// =================================================================
// Holds a 2-entry, program-ordered, compacting buffer of fetched
// instructions and presents both of them, decoded, to Issue every
// cycle. This is the IF/ID pipeline register generalised from one
// entry to two.
//
// Every cycle the buffer:
//   1. drops the `i_accept_cnt` oldest entries (what Issue consumed),
//   2. shifts what is left down to slot 0 (so slot 0 is always the
//      oldest live instruction and there is never a hole),
//   3. refills the freed slots from the fetch queue heads, reporting
//      how many it took on `o_pop_cnt`.
//
// Because refill happens in the same cycle as the accept, a steady
// stream keeps both slots occupied and both decoders busy.
//
// Backpressure: there is no stall signal. `i_accept_cnt == 0` IS the
// stall - the buffer simply keeps what it holds and pops nothing, which
// backs pressure up into the fetch queue exactly as the old
// o_stall_to_if chain did.
//
// Phase 2 note: Issue is still 1-wide, so i_accept_cnt is only ever 0
// or 1 today. Slot 1 is nevertheless decoded for real every cycle, and
// assert_decode_lanes_agree below checks lane 1's result against lane
// 0's when that same instruction shifts down - so the second lane is
// live and verified before Phase 3 starts consuming it.

module decode_stage (
  input  logic        clk,
  input  logic        rst_n,

  // From the fetch queue: up to two instructions, slot 0 the older.
  // i_if_valid[1] implies i_if_valid[0] (the queue never has a hole).
  input  logic [1:0]        i_if_valid,
  input  logic [1:0][31:0]  i_if_pc,
  input  logic [1:0][31:0]  i_if_instr,
  input  logic [1:0]        i_if_pred_taken,
  input  logic [1:0][31:0]  i_if_pred_target,

  // How many of the decode slots Issue consumed this cycle (0..2).
  input  logic [1:0]        i_accept_cnt,

  input  logic              i_flush,

  // To Issue: up to two decoded uops, slot 0 the older.
  output logic [1:0]        o_dec_valid,
  output uop_t [1:0]        o_uop,
  output logic [1:0][31:0]  o_dec_pc,

  // Back to fetch: how many entries to pop from the fetch queue.
  output logic [1:0]        o_pop_cnt
);

  // ───────────────────────────────────────────────
  // 1. The 2-entry IF/ID buffer
  // ───────────────────────────────────────────────
  typedef struct packed {
    logic [31:0] pc;
    logic [31:0] instr;
    logic        pred_taken;
    logic [31:0] pred_target;
  } id_entry_t;

  id_entry_t [1:0] id_q;
  logic      [1:0] id_v_q;

  // Fetch-queue heads packaged as buffer entries.
  id_entry_t [1:0] fq_e;
  always_comb begin
    for (int i = 0; i < 2; i++) begin
      fq_e[i] = '{pc:          i_if_pc[i],
                  instr:       i_if_instr[i],
                  pred_taken:  i_if_pred_taken[i],
                  pred_target: i_if_pred_target[i]};
    end
  end

  // What survives this cycle's accept, already compacted towards slot 0.
  logic      [1:0] keep_v;
  id_entry_t [1:0] keep_e;

  // Buffer state for the next cycle: survivors + refill.
  logic      [1:0] nxt_v;
  id_entry_t [1:0] nxt_e;

  always_comb begin
    keep_v = 2'b00;
    keep_e = '0;

    unique case (i_accept_cnt)
      2'd0: begin
        keep_v = id_v_q;
        keep_e = id_q;
      end
      2'd1: begin
        // Slot 0 consumed; slot 1 (if any) becomes the new slot 0.
        keep_v[0] = id_v_q[1];
        keep_e[0] = id_q[1];
      end
      default: begin
        // Both consumed (or a malformed count, caught by assertion) -
        // nothing survives.
      end
    endcase

    nxt_v     = keep_v;
    nxt_e     = keep_e;
    o_pop_cnt = 2'd0;

    if (!keep_v[0]) begin
      // Buffer emptied: take up to a full pair from the queue.
      if (i_if_valid[0]) begin
        nxt_v[0]  = 1'b1;
        nxt_e[0]  = fq_e[0];
        o_pop_cnt = 2'd1;
        if (i_if_valid[1]) begin
          nxt_v[1]  = 1'b1;
          nxt_e[1]  = fq_e[1];
          o_pop_cnt = 2'd2;
        end
      end
    end
    else if (!keep_v[1]) begin
      // One survivor: top the buffer back up with the queue head.
      if (i_if_valid[0]) begin
        nxt_v[1]  = 1'b1;
        nxt_e[1]  = fq_e[0];
        o_pop_cnt = 2'd1;
      end
    end

    // A mispredict redirect kills everything already in the buffer, and
    // the fetch queue is flushed in the same cycle - so pop nothing.
    if (i_flush) begin
      nxt_v     = 2'b00;
      o_pop_cnt = 2'd0;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      id_v_q <= 2'b00;
      id_q   <= '0;
    end
    else begin
      id_v_q <= nxt_v;
      id_q   <= nxt_e;
    end
  end

  // ───────────────────────────────────────────────
  // 2. The two decode lanes
  // ───────────────────────────────────────────────
  uop_t [1:0] dec_uop;   // raw decoder output, before the `way` stamp

  for (genvar g = 0; g < 2; g++) begin : g_lane
    decoder DEC (
      .i_valid       (id_v_q[g] && !i_flush),
      .i_instr       (id_q[g].instr),
      .i_pred_taken  (id_q[g].pred_taken),
      .i_pred_target (id_q[g].pred_target),
      .o_uop         (dec_uop[g])
    );
  end

  // Stamp the lane index. Done here rather than in `decoder` so the two
  // lanes' outputs are otherwise bit-identical for the same instruction,
  // which is what assert_decode_lanes_agree relies on.
  uop_t [1:0] uop_w;
  always_comb begin
    uop_w        = dec_uop;
    uop_w[0].way = 1'b0;
    uop_w[1].way = 1'b1;
  end

  assign o_uop       = uop_w;
  assign o_dec_valid = id_v_q & {2{!i_flush}};
  assign o_dec_pc    = {id_q[1].pc, id_q[0].pc};

`ifdef SIMULATION
  // ───────────────────────────────────────────────────────────────────────────
  // Decode buffer integrity
  // ───────────────────────────────────────────────────────────────────────────

  // 1. The buffer compacts, so slot 1 can never be occupied while slot 0
  //    is empty. A hole here would let Issue consume out of program order.
  assert_no_hole: assert property (
    @(posedge clk) disable iff (!rst_n)
    id_v_q[1] |-> id_v_q[0]
  ) else $error("DECODE ERROR: slot1 valid with slot0 empty - decode buffer has a hole");

  // 2. Issue must never claim to have taken more uops than decode offered
  //    (that would silently skip instructions).
  assert_accept_le_occupancy: assert property (
    @(posedge clk) disable iff (!rst_n || i_flush)
    (i_accept_cnt <= ({1'b0, id_v_q[0]} + {1'b0, id_v_q[1]}))
  ) else $error("DECODE ERROR: Issue accepted %0d uops, decode held only %0d",
                i_accept_cnt, id_v_q[0] + id_v_q[1]);

  // 3. The two lanes must be the same decoder. When slot 1 shifts down to
  //    slot 0 (accept of exactly 1), lane 0 re-decodes the very instruction
  //    lane 1 decoded last cycle; the two results must be bit-identical.
  //    Until Issue goes 2-wide nothing downstream reads o_uop[1], so this
  //    is what keeps lane 1 honest - and what stops the simulator from
  //    optimising it away as dead logic.
  assert_decode_lanes_agree: assert property (
    @(posedge clk) disable iff (!rst_n || i_flush)
    (id_v_q[1] && (i_accept_cnt == 2'd1)) |=> (dec_uop[0] == $past(dec_uop[1]))
  ) else $error("DECODE ERROR: lane0/lane1 disagree for pc=0x%h (instr=0x%h)",
                id_q[0].pc, id_q[0].instr);

  // 4. Popping from the fetch queue is only legal for entries the queue
  //    actually presents.
  assert_pop_le_available: assert property (
    @(posedge clk) disable iff (!rst_n)
    (o_pop_cnt <= ({1'b0, i_if_valid[0]} + {1'b0, i_if_valid[1]}))
  ) else $error("DECODE ERROR: popping %0d entries but queue offers only %0d",
                o_pop_cnt, i_if_valid[0] + i_if_valid[1]);
`endif

endmodule
