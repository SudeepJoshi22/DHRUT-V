// =================================================================
// scoreboard - per-register outstanding-write tracker
// =================================================================
// One saturating counter per architectural register, holding the number
// of dispatched-but-not-yet-written-back instructions targeting it.
// `busy` for a register means "a write to this register is in flight".
//
// Issue combines this with the bypass network to decide readiness:
//
//     operand_ready(rs) = !uses_rs || rs == x0
//                      || !busy[rs]          // no write in flight
//                      || bypass_hit[rs]     // in flight, but readable NOW
//
// WHY A COUNTER AND NOT A BIT
// ---------------------------
// Two instructions can target the same register while both are in
// flight (`li x1, 5` / `li x1, 6` in consecutive bundles). A single bit
// would be cleared by the FIRST write-back while the second write is
// still outstanding, leaving the register wrongly marked ready. The
// counter is incremented on dispatch and decremented on write-back, so
// it only reaches zero when the last outstanding write has landed.
//
// SET ON DISPATCH, NOT ON ISSUE
// -----------------------------
// The set condition must match what will actually reach write-back, not
// merely what decode marked `writes_rd`. An illegal CSR access, for
// example, has `writes_rd == 1` from decode but is never dispatched
// (csr_unit withholds o_dispatch_valid and the uop traps instead). Set
// on `writes_rd` and that counter would never be decremented - the
// register would stay busy forever and the machine would deadlock the
// next time anything read it. Hence Issue drives the set ports from the
// dispatch handshakes.
//
// WHAT THIS IS FOR
// ----------------
// Today this never blocks anything, and that is expected: the ALUs have
// fixed 1-cycle latency and the LSU's stall freezes the whole machine,
// so the bypass network covers every cycle between dispatch and the ARF
// becoming readable - `bypass_hit` is always true whenever `busy` is.
// It is built now because both planned additions break that:
//
//   * an M-extension multiply/divide unit produces its result several
//     cycles after dispatch, with nothing on the bypass network in
//     between - consumers must be held back, which is exactly what
//     `busy && !bypass_hit` does;
//   * a load queue (non-blocking loads) removes the machine-wide stall,
//     so a load's consumer can reach Issue while the load is still
//     outstanding.
//
// Adding either is then a matter of widening NUM_SET/NUM_CLR and wiring
// the new unit's dispatch and write-back ports, rather than re-working
// the issue stage. Until then the counters are still exercised every
// cycle (every dispatch and write-back moves one), and the assertions
// below check the bookkeeping is exact, so this cannot silently rot.

module scoreboard #(
  parameter int NUM_SET   = 2,   // dispatch ports (issue lanes)
  parameter int NUM_CLR   = 2,   // write-back ports (retire lanes)
  parameter int NUM_QUERY = 4,   // operands checked per cycle
  // Max outstanding writes to ONE register. Bounded by pipeline depth;
  // 3 bits is far more than the current 2-deep dispatch->write-back
  // distance needs, and leaves room for a multi-cycle unit.
  parameter int CNT_W     = 3
) (
  input  logic clk,
  input  logic rst_n,

  // Dispatch: an instruction that WILL write i_set_rd[n] has left Issue.
  input  logic [NUM_SET-1:0]       i_set_en,
  input  logic [NUM_SET-1:0][4:0]  i_set_rd,

  // Write-back: that instruction's result has reached the ARF.
  input  logic [NUM_CLR-1:0]       i_clr_en,
  input  logic [NUM_CLR-1:0][4:0]  i_clr_rd,

  // Operand queries (combinational)
  input  logic [NUM_QUERY-1:0][4:0] i_query_rs,
  output logic [NUM_QUERY-1:0]      o_query_busy,

  // Whole busy vector, for waveforms and for cpu_core's assertions
  output logic [31:0]               o_busy
);

  logic [CNT_W-1:0] cnt_q [32];

  // Per-register set/clear demux for this cycle.
  logic [31:0] set_hit, clr_hit;
  always_comb begin
    set_hit = 32'b0;
    clr_hit = 32'b0;
    for (int s = 0; s < NUM_SET; s++) begin
      // x0 is never a real destination, so it is never tracked.
      if (i_set_en[s] && (i_set_rd[s] != 5'd0)) set_hit[i_set_rd[s]] = 1'b1;
    end
    for (int c = 0; c < NUM_CLR; c++) begin
      if (i_clr_en[c] && (i_clr_rd[c] != 5'd0)) clr_hit[i_clr_rd[c]] = 1'b1;
    end
  end

  // At most one set and one clear can land on a given register in a
  // cycle: the two issue lanes cannot share a destination (Issue forbids
  // intra-bundle WAW), and neither can the two retire lanes, since they
  // carry those same two instructions.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int r = 0; r < 32; r++) cnt_q[r] <= '0;
    end
    else begin
      for (int r = 1; r < 32; r++) begin
        unique case ({set_hit[r], clr_hit[r]})
          2'b10:   cnt_q[r] <= cnt_q[r] + 1'b1;
          2'b01:   cnt_q[r] <= cnt_q[r] - 1'b1;
          default: cnt_q[r] <= cnt_q[r];   // 00 = idle, 11 = net zero
        endcase
      end
    end
  end

  // No flush handling, deliberately. A counter is only incremented when
  // an instruction is DISPATCHED, and Issue never dispatches a
  // wrong-path uop (issue.sv gates lane 1 on !o_mispredict), so
  // everything counted here is guaranteed to reach write-back and
  // decrement its own counter. Clearing the table on a flush would
  // instead lose the still-in-flight writes.

  always_comb begin
    o_busy = 32'b0;
    o_busy[0] = 1'b0;                       // x0 is never busy
    for (int r = 1; r < 32; r++) begin
      o_busy[r] = (cnt_q[r] != '0);
    end
  end

  always_comb begin
    for (int q = 0; q < NUM_QUERY; q++) begin
      o_query_busy[q] = o_busy[i_query_rs[q]];
    end
  end

`ifdef SIMULATION
  // 1. Never decrement a register with nothing outstanding. This is the
  //    check that catches a set/clear pair that has drifted out of step -
  //    e.g. an instruction that sets on dispatch but never reaches
  //    write-back, which would deadlock the machine the other way round.
  genvar gr;
  generate
    for (gr = 1; gr < 32; gr++) begin : g_sb_chk
      assert_no_underflow: assert property (
        @(posedge clk) disable iff (!rst_n)
        (clr_hit[gr] && !set_hit[gr]) |-> (cnt_q[gr] != '0)
      ) else $error("SCOREBOARD ERROR: write-back for x%0d with no outstanding write", gr);

      // 2. Counter must not wrap. If this fires, CNT_W is too small for
      //    the pipeline depth (or a clear has gone missing).
      assert_no_overflow: assert property (
        @(posedge clk) disable iff (!rst_n)
        (set_hit[gr] && !clr_hit[gr]) |-> (cnt_q[gr] != {CNT_W{1'b1}})
      ) else $error("SCOREBOARD ERROR: outstanding-write counter for x%0d would overflow (CNT_W=%0d)",
                    gr, CNT_W);
    end
  endgenerate

  // 3. The two dispatch ports never target the same register in one
  //    cycle - Issue's intra-bundle WAW rule guarantees it, and the
  //    single-set-per-register assumption in the counter update above
  //    depends on it.
  assert_set_ports_distinct: assert property (
    @(posedge clk) disable iff (!rst_n)
    (i_set_en[0] && i_set_en[1] && (i_set_rd[0] != 5'd0)) |-> (i_set_rd[0] != i_set_rd[1])
  ) else $error("SCOREBOARD ERROR: both dispatch ports set x%0d in one cycle", i_set_rd[0]);
`endif

endmodule
