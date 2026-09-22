// Track dispatched writes per register until writeback. Counters support
// multiple outstanding writers; x0 is never busy. Set ports must reflect
// actual dispatch, including CSR dispatch qualification.

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

  // Flush preserves outstanding writes: dispatched instructions still complete.

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
  // A clear requires an outstanding write or a simultaneous set.
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

  // Dispatch ports must not target the same nonzero register.
  assert_set_ports_distinct: assert property (
    @(posedge clk) disable iff (!rst_n)
    (i_set_en[0] && i_set_en[1] && (i_set_rd[0] != 5'd0)) |-> (i_set_rd[0] != i_set_rd[1])
  ) else $error("SCOREBOARD ERROR: both dispatch ports set x%0d in one cycle", i_set_rd[0]);
`endif

endmodule
