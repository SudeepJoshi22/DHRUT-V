import riscv_uop_pkg::*;

module cpu_core (
  input  logic clk,
  input  logic rst_n,

  mem_if.master imem_if,
  mem_if.master dmem_if
);

  // IF -> ID fetch group: the fetch queue presents its two oldest entries
  // every cycle, index 0 being the older instruction. ifg_valid[1] implies
  // ifg_valid[0].
  logic [1:0]       ifg_valid;
  logic [1:0][31:0] ifg_pc;
  logic [1:0][31:0] ifg_instr;
  logic [1:0]       ifg_pred_taken;
  logic [1:0][31:0] ifg_pred_target;

  // IF <-> BPU (prediction port)
  logic        bpu_pred_is_branch;
  logic [31:0] bpu_pred_pc;
  logic [31:0] bpu_pred_offset_pc;
  logic        bpu_pred_taken;
  logic [31:0] bpu_pred_target;

  // Issue -> BPU (update/training port). Still single-ported: only lane 0
  // can hold a branch (rtl/pipeline/issue_hazard.sv), so two branches can
  // never resolve in the same cycle and bpu.sv needs no widening.
  logic        bpu_update_valid;
  logic [31:0] bpu_update_pc;
  logic        bpu_update_taken;
  logic [31:0] bpu_update_target;

  // ID -> Issue decode group: two decoded uops per cycle, index 0 older.
  logic [1:0]       idg_valid;
  uop_t [1:0]       idg_uop;
  logic [1:0][31:0] idg_pc;

  // How many decode slots Issue consumed this cycle (0..2), and how many
  // fetch-queue entries Decode consumed. These counts ARE the handshakes:
  // there is no separate stall wire in either direction any more.
  logic [1:0]  issue_accept_cnt;
  logic [1:0]  decode_pop_cnt;
  // How many uops actually issued this cycle (0..2) -> minstret.
  logic [1:0]  issue_instret_cnt;

  // Execution lanes use separate instances to expose scalar monitor signals.
  alu_issue_if alu0_if(clk, rst_n);
  alu_issue_if alu1_if(clk, rst_n);

  // One LSU, fed by lane 0 only.
  lsu_issue_if lsu_if(clk, rst_n);

  // LSU -> Retire lane 0
  logic         lsu_valid;
  uop_t         lsu_uop_forward;
  logic [31:0]  lsu_load_data;

  // ALU lane 0 -> Retire lane 0
  logic        alu0_retire_valid;
  logic [31:0] alu0_retire_result;
  uop_t        alu0_retire_uop;

  // ALU lane 1 -> Retire lane 1
  logic        alu1_retire_valid;
  logic [31:0] alu1_retire_result;
  uop_t        alu1_retire_uop;

  // Retire -> Issue (write-back), one port per lane
  logic        retire0_wb_en;
  logic [4:0]  retire0_wb_rd;
  logic [31:0] retire0_wb_data;
  logic        retire1_wb_en;
  logic [4:0]  retire1_wb_rd;
  logic [31:0] retire1_wb_data;

  // Branch from Issue -> IF (actual resolved outcome, used to train BPU)
  logic        branch_taken;
  logic [31:0] branch_target;

  // Misprediction redirect from Issue -> IF/ID/self (decoupled from
  // the actual-outcome signals above)
  logic        mispredict;
  logic [31:0] redirect_pc;

  // Forwarding sources: ALU1 is younger than ALU0/LSU; retire follows.
  logic [4:0]  fwd_alu0_rd;
  logic [31:0] fwd_alu0_data;
  logic        fwd_alu0_writes_rd;

  logic [4:0]  fwd_alu1_rd;
  logic [31:0] fwd_alu1_data;
  logic        fwd_alu1_writes_rd;

  logic        fwd_lsu_valid;
  logic [4:0]  fwd_lsu_rd;
  logic [31:0] fwd_lsu_data;

  logic [4:0]  fwd_retire0_rd;
  logic [31:0] fwd_retire0_data;
  logic        fwd_retire0_writes_rd;

  logic [4:0]  fwd_retire1_rd;
  logic [31:0] fwd_retire1_data;
  logic        fwd_retire1_writes_rd;

  // Downstream stall (status view; the counts above are the real handshakes)
  logic        issue_to_decode_stall;

  // Slot-0 taps support the stage display. Instruction tracing uses the full
  // bundle and issue_accept_cnt to observe both lanes.
  logic        if_id_valid;
  logic [31:0] if_id_pc;
  logic [31:0] if_id_instr;
  logic        if_id_pred_taken;
  logic [31:0] if_id_pred_target;
  logic        id_issue_valid;
  uop_t        id_issue_uop;
  logic [31:0] id_issue_pc;

  assign if_id_valid       = ifg_valid[0];
  assign if_id_pc          = ifg_pc[0];
  assign if_id_instr       = ifg_instr[0];
  assign if_id_pred_taken  = ifg_pred_taken[0];
  assign if_id_pred_target = ifg_pred_target[0];
  assign id_issue_valid    = idg_valid[0];
  assign id_issue_uop      = idg_uop[0];
  assign id_issue_pc       = idg_pc[0];

  // ───────────────────────────────────────────────
  // IF Stage
  // ───────────────────────────────────────────────
  if_stage IF (
    .clk             (clk),
    .rst_n           (rst_n),
    .i_pop_cnt       (decode_pop_cnt),
    .i_flush         (mispredict),            // flush only on actual misprediction
    .i_redirect_pc   (redirect_pc),           // corrected redirect target
    .imem            (imem_if),
    .o_bpu_pred_is_branch (bpu_pred_is_branch),
    .o_bpu_pred_pc        (bpu_pred_pc),
    .o_bpu_pred_offset_pc (bpu_pred_offset_pc),
    .i_bpu_pred_taken     (bpu_pred_taken),
    .i_bpu_pred_target    (bpu_pred_target),
    .o_if_valid      (ifg_valid),
    .o_if_pc         (ifg_pc),
    .o_if_instr      (ifg_instr),
    .o_if_pred_taken  (ifg_pred_taken),
    .o_if_pred_target (ifg_pred_target)
  );

  // Branch predictor: 16 entries mapped to FPGA distributed RAM.
  bpu #(
    .TABLE_DEPTH (16),
    .INDEX_WIDTH (4),     // must remain $clog2(TABLE_DEPTH)
    // Partial tags reduce storage; Issue resolves targets to correct aliasing.
    .TAG_WIDTH   (10)
  ) BPU (
    .clk                 (clk),
    .rst_n               (rst_n),
    .i_is_branch_pred    (bpu_pred_is_branch),
    .i_branch_pc_pred    (bpu_pred_pc),
    .i_offset_pc_pred    (bpu_pred_offset_pc),
    .o_prediction        (bpu_pred_taken),
    .o_predicted_pc      (bpu_pred_target),
    .i_branch_pc_update  (bpu_update_pc),
    .i_taken_update      (bpu_update_taken),
    .i_update_valid      (bpu_update_valid),
    .i_update_target_pc  (bpu_update_target)
  );

  // ───────────────────────────────────────────────
  // Decode Stage
  // ───────────────────────────────────────────────
  decode_stage ID (
    .clk             (clk),
    .rst_n           (rst_n),
    .i_if_valid      (ifg_valid),
    .i_if_pc         (ifg_pc),
    .i_if_instr      (ifg_instr),
    .i_if_pred_taken  (ifg_pred_taken),
    .i_if_pred_target (ifg_pred_target),
    .i_accept_cnt    (issue_accept_cnt),
    .i_flush         (mispredict),
    .o_dec_valid     (idg_valid),
    .o_uop           (idg_uop),
    .o_dec_pc        (idg_pc),
    .o_pop_cnt       (decode_pop_cnt)
  );

  // Lane-0 multiply/divide unit. Issue serializes younger instructions while
  // an MDU operation is outstanding to preserve writeback order.
  logic        mdu_dispatch_valid, mdu_ready, mdu_result_valid;
  uop_t        mdu_dispatch_uop;
  logic [31:0] mdu_op1, mdu_op2, mdu_result;

  // Retain the uop for the single outstanding MDU operation.
  uop_t mdu_inflight_uop_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)                 mdu_inflight_uop_q <= '0;
    else if (mdu_dispatch_valid) mdu_inflight_uop_q <= mdu_dispatch_uop;
  end

  mdu MDU (
    .clk      (clk),
    .rst_n    (rst_n),
    // Issue resolves branches before dispatching younger instructions.
    // An in-flight MDU operation therefore precedes any redirect and must
    // complete, just like the ALU/LSU; flushing it strands its scoreboard rd.
    .i_flush  (1'b0),
    .i_valid  (mdu_dispatch_valid),
    .i_funct3 (mdu_dispatch_uop.funct3),
    .i_op1    (mdu_op1),
    .i_op2    (mdu_op2),
    .o_ready  (mdu_ready),
    .o_valid  (mdu_result_valid),
    .o_result (mdu_result)
  );

  issue_stage ISSUE (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .i_dec_valid            (idg_valid),
    .i_uop                  (idg_uop),
    .i_dec_pc               (idg_pc),
    .i_stall                (1'b0),
    .i_flush                (mispredict),
    .i_wb0_en               (retire0_wb_en),
    .i_wb0_rd               (retire0_wb_rd),
    .i_wb0_data             (retire0_wb_data),
    .i_wb1_en               (retire1_wb_en),
    .i_wb1_rd               (retire1_wb_rd),
    .i_wb1_data             (retire1_wb_data),
    .i_alu0_fwd_writes_rd   (fwd_alu0_writes_rd),
    .i_alu0_fwd_rd          (fwd_alu0_rd),
    .i_alu0_fwd_data        (fwd_alu0_data),
    .i_alu1_fwd_writes_rd   (fwd_alu1_writes_rd),
    .i_alu1_fwd_rd          (fwd_alu1_rd),
    .i_alu1_fwd_data        (fwd_alu1_data),
    .i_ret0_fwd_writes_rd   (fwd_retire0_writes_rd),
    .i_ret0_fwd_rd          (fwd_retire0_rd),
    .i_ret0_fwd_data        (fwd_retire0_data),
    .i_ret1_fwd_writes_rd   (fwd_retire1_writes_rd),
    .i_ret1_fwd_rd          (fwd_retire1_rd),
    .i_ret1_fwd_data        (fwd_retire1_data),
    .i_lsu_fwd_data_valid   (fwd_lsu_valid),
    .i_lsu_fwd_rd           (fwd_lsu_rd),
    .i_lsu_fwd_data         (fwd_lsu_data),
    .o_branch_taken         (branch_taken),
    .o_branch_target        (branch_target),
    .o_resolved_pc          (bpu_update_pc),
    .o_update_valid         (bpu_update_valid),
    .o_mispredict           (mispredict),
    .o_redirect_pc          (redirect_pc),
    .o_stall_to_decode      (issue_to_decode_stall),
    .o_accept_cnt           (issue_accept_cnt),
    .o_instret_cnt          (issue_instret_cnt),
    .alu0_if                (alu0_if),
    .alu1_if                (alu1_if),
    .lsu_if                 (lsu_if),
    .o_mdu_valid            (mdu_dispatch_valid),
    .o_mdu_uop              (mdu_dispatch_uop),
    .o_mdu_op1              (mdu_op1),
    .o_mdu_op2              (mdu_op2),
    .i_mdu_ready            (mdu_ready),
    .i_mdu_result_valid     (mdu_result_valid)
  );

  // BPU update/training port is driven from Issue's actual resolved outcome
  assign bpu_update_taken  = branch_taken;
  assign bpu_update_target = branch_target;

  // ALU lane 0. Dispatched instructions complete without branch-flush killing.
  alu_stage ALU0 (
    .clk             (clk),
    .rst_n           (rst_n),
    .issue_if        (alu0_if),
    // MDU completion owns retire lane 0; hold any ALU0 result for the next cycle.
    .i_stall         (lsu_if.s_stall_from_lsu || mdu_result_valid),
    .i_flush         (1'b0),
    .o_alu_fwd_writes_rd    (fwd_alu0_writes_rd),
    .o_alu_fwd_rd           (fwd_alu0_rd),
    .o_alu_fwd_result       (fwd_alu0_data),
    .o_valid         (alu0_retire_valid),
    .o_alu_result    (alu0_retire_result),
    .o_uop_forward   (alu0_retire_uop)
  );

  // ───────────────────────────────────────────────
  // ALU lane 1
  // ───────────────────────────────────────────────
  alu_stage ALU1 (
    .clk             (clk),
    .rst_n           (rst_n),
    .issue_if        (alu1_if),
    .i_stall         (lsu_if.s_stall_from_lsu),
    .i_flush         (1'b0),
    .o_alu_fwd_writes_rd    (fwd_alu1_writes_rd),
    .o_alu_fwd_rd           (fwd_alu1_rd),
    .o_alu_fwd_result       (fwd_alu1_data),
    .o_valid         (alu1_retire_valid),
    .o_alu_result    (alu1_retire_result),
    .o_uop_forward   (alu1_retire_uop)
  );

  // ───────────────────────────────────────────────
  // LSU (lane 0 only)
  // ───────────────────────────────────────────────
  lsu LSU (
      .clk                  (clk),
      .rst_n                (rst_n),
      .issue_if             (lsu_if),
      .dmem_if              (dmem_if),
      .o_lsu_fwd_valid      (fwd_lsu_valid),
      .o_lsu_fwd_rd         (fwd_lsu_rd),
      .o_lsu_fwd_result     (fwd_lsu_data),
      .o_valid              (lsu_valid),
      .o_load_data          (lsu_load_data),
      .o_lsu_uop            (lsu_uop_forward)
    );

  // Retire lane 0 accepts ALU0, LSU or MDU results.
  // ALU0 and LSU completions are mutually exclusive.
  retire RETIRE0 (
    .clk             (clk),
    .rst_n           (rst_n),
    .i_alu_valid     (alu0_retire_valid),
    .i_alu_uop       (alu0_retire_uop),
    .i_alu_result    (alu0_retire_result),
    .i_lsu_valid     (lsu_valid),
    .i_lsu_uop       (lsu_uop_forward),
    .i_lsu_load_data (lsu_load_data),
    .i_mdu_valid     (mdu_result_valid),
    .i_mdu_uop       (mdu_inflight_uop_q),
    .i_mdu_result    (mdu_result),
    .i_flush         (1'b0),
    .i_stall         (1'b0),
    .o_retire_fwd_writes_rd (fwd_retire0_writes_rd),
    .o_retire_fwd_rd        (fwd_retire0_rd),
    .o_retire_fwd_result    (fwd_retire0_data),
    .o_wb_en         (retire0_wb_en),
    .o_wb_rd         (retire0_wb_rd),
    .o_wb_data       (retire0_wb_data)
  );

  // Retire lane 1 accepts ALU1 only; unused result ports are tied off.
  retire RETIRE1 (
    .clk             (clk),
    .rst_n           (rst_n),
    .i_alu_valid     (alu1_retire_valid),
    .i_alu_uop       (alu1_retire_uop),
    .i_alu_result    (alu1_retire_result),
    .i_lsu_valid     (1'b0),
    .i_lsu_uop       ('0),
    .i_lsu_load_data (32'b0),
    .i_mdu_valid     (1'b0),      // MDU is lane 0 only
    .i_mdu_uop       ('0),
    .i_mdu_result    (32'b0),
    .i_flush         (1'b0),
    .i_stall         (1'b0),
    .o_retire_fwd_writes_rd (fwd_retire1_writes_rd),
    .o_retire_fwd_rd        (fwd_retire1_rd),
    .o_retire_fwd_result    (fwd_retire1_data),
    .o_wb_en         (retire1_wb_en),
    .o_wb_rd         (retire1_wb_rd),
    .o_wb_data       (retire1_wb_data)
  );

`ifdef SIMULATION
  // Lane 0's two possible units must never complete together - retire's
  // fixed priority would drop the LSU result.
  assert_lane0_units_exclusive: assert property (
    @(posedge clk) disable iff (!rst_n)
    !(alu0_retire_valid && lsu_valid)
  ) else $error("CORE ERROR: ALU0 and LSU both completed in the same cycle - a result is being dropped");

  // An ALU0 result coinciding with MDU completion must remain valid next cycle.
  assert_alu0_held_when_mdu_retires: assert property (
    @(posedge clk) disable iff (!rst_n)
    (alu0_retire_valid && mdu_result_valid) |=> alu0_retire_valid
  ) else $error("CORE ERROR: ALU0 result dropped when the MDU took the retire slot");

  // One in flight at a time. If the MDU were ever dispatched while busy,
  // mdu_inflight_uop_q would be overwritten and the first result would
  // write back to the wrong register.
  assert_mdu_lsu_exclusive: assert property (
    @(posedge clk) disable iff (!rst_n)
    !(mdu_result_valid && lsu_valid)
  ) else $error("CORE ERROR: MDU and LSU collide at retire");

  assert_mdu_single_inflight: assert property (
    @(posedge clk) disable iff (!rst_n)
    mdu_dispatch_valid |-> mdu_ready
  ) else $error("CORE ERROR: MDU dispatched while busy - in-flight uop overwritten");

  // Lane 1 never executes a memory op, so it can never be the source of a
  // dmem transaction.
  assert_lane1_never_memory: assert property (
    @(posedge clk) disable iff (!rst_n)
    alu1_retire_valid |-> (!alu1_retire_uop.is_load && !alu1_retire_uop.is_store)
  ) else $error("CORE ERROR: lane1 retired a memory op");
`endif

endmodule
