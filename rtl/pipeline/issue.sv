import riscv_uop_pkg::*;

// Two-wide in-order issue with a program-ordered bundle buffer.
// Lane 0 dispatches to ALU0, LSU or MDU and resolves branches/CSRs.
// Lane 1 accepts simple ALU operations; issue_hazard checks pairing.

module issue_stage (
  input logic clk,
  input logic rst_n,

  // From Decode: a 2-wide bundle, slot 0 the older instruction.
  input logic [1:0] i_dec_valid,
  input uop_t [1:0] i_uop,
  input logic [1:0][31:0] i_dec_pc,

  // Stall & flush from downstream
  input logic i_stall,
  input logic i_flush,

  // From the two Retire lanes (write-back to ARF)
  input logic        i_wb0_en,
  input logic [4:0]  i_wb0_rd,
  input logic [31:0] i_wb0_data,
  input logic        i_wb1_en,
  input logic [4:0]  i_wb1_rd,
  input logic [31:0] i_wb1_data,

  // FORWARDING - from ALU lane 0
  input logic        i_alu0_fwd_writes_rd,
  input logic [4:0]  i_alu0_fwd_rd,
  input logic [31:0] i_alu0_fwd_data,
  // FORWARDING - from ALU lane 1
  input logic        i_alu1_fwd_writes_rd,
  input logic [4:0]  i_alu1_fwd_rd,
  input logic [31:0] i_alu1_fwd_data,
  // FORWARDING - from Retire lane 0
  input logic        i_ret0_fwd_writes_rd,
  input logic [4:0]  i_ret0_fwd_rd,
  input logic [31:0] i_ret0_fwd_data,
  // FORWARDING - from Retire lane 1
  input logic        i_ret1_fwd_writes_rd,
  input logic [4:0]  i_ret1_fwd_rd,
  input logic [31:0] i_ret1_fwd_data,
  // FORWARDING - from LSU (lane 0 only)
  input logic        i_lsu_fwd_data_valid,
  input logic [4:0]  i_lsu_fwd_rd,
  input logic [31:0] i_lsu_fwd_data,

  // To Fetch – actual resolved branch/jump outcome (used to train the BPU)
  output logic o_branch_taken,
  output logic [31:0] o_branch_target,
  output logic [31:0] o_resolved_pc,
  output logic o_update_valid,

  // To Fetch/Decode – decoupled misprediction redirect
  output logic o_mispredict,
  output logic [31:0] o_redirect_pc,

  // Stall back to Decode/IF (status view only - o_accept_cnt is the handshake)
  output logic o_stall_to_decode,
  // How many of decode's slots were consumed this cycle (0..2)
  output logic [1:0] o_accept_cnt,
  // How many uops issued this cycle (0..2), for minstret
  output logic [1:0] o_instret_cnt,

  // Issued to the two ALUs
  alu_issue_if.issuer alu0_if,
  alu_issue_if.issuer alu1_if,
  // Issued to LSU (with back-pressure) - lane 0 only
  lsu_issue_if.issuer lsu_if,

  // Lane-0 MDU interface. cpu_core retains the associated uop until completion.
  output logic        o_mdu_valid,
  output uop_t        o_mdu_uop,
  output logic [31:0] o_mdu_op1,
  output logic [31:0] o_mdu_op2,
  input  logic        i_mdu_ready,        // MDU idle, can accept
  input  logic        i_mdu_result_valid  // MDU completing THIS cycle
);

  // Scalar bundle registers expose each lane to the simulation monitor.
  logic        buf_valid0_q;
  uop_t        buf_uop0_q;
  logic [31:0] buf_pc0_q;

  logic        buf_valid1_q;
  uop_t        buf_uop1_q;
  logic [31:0] buf_pc1_q;

  // Stall aggregation (scalable – add more units later)
  logic  downstream_stall;
  // The pipeline has no reorder buffer. Serialize younger issue while the
  // MDU is active so its delayed write-back cannot be overtaken by ALU/LSU
  // results or hidden by a younger forwarding entry. issue_hazard also
  // prevents an MDU operation pairing with lane 1 at dispatch.
  logic lane0_wants_mdu, mdu_struct_stall;
  assign lane0_wants_mdu  = buf_valid0_q && buf_uop0_q.is_mdu;
  assign mdu_struct_stall = lane0_wants_mdu && !i_mdu_ready;

  assign downstream_stall = i_stall || lsu_if.s_stall_from_lsu
                            || !i_mdu_ready || mdu_struct_stall
                            || i_mdu_result_valid;
  // FUTURE: || alu_stall || fpu_stall || vec_stall

  logic operands_ready;
  assign operands_ready = !downstream_stall;

  // ───────────────────────────────────────────────
  // 2. Pairing decision (combinational, on Decode's bundle)
  // ───────────────────────────────────────────────
  logic pair_ok;
  logic haz_lane1_capable, haz_raw, haz_waw;

  issue_hazard HAZ (
    .i_valid0        (i_dec_valid[0]),
    .i_uop0          (i_uop[0]),
    .i_valid1        (i_dec_valid[1]),
    .i_uop1          (i_uop[1]),
    .o_pair_ok       (pair_ok),
    .o_lane1_capable (haz_lane1_capable),
    .o_raw_hazard    (haz_raw),
    .o_waw_hazard    (haz_waw)
  );

  // Dispatch requires valid operands and downstream capacity.
  logic lane0_ops_ready, lane1_ops_ready;

  logic issue_en0;
  assign issue_en0 = buf_valid0_q && operands_ready && lane0_ops_ready;

  logic dispatch_en;              // lane 0 leaves this cycle
  assign dispatch_en = issue_en0;

  // Suppress lane 1 when lane 0 redirects to prevent wrong-path execution.
  logic issue_en1;
  // Lane 1 may issue only alongside the older lane 0 instruction.
  assign issue_en1 = issue_en0 && buf_valid1_q && operands_ready
                     && lane1_ops_ready && !o_mispredict;

  // Use the same acceptance condition for buffer loading and decode consumption.
  // Replace a bundle only when it is empty or dispatching.
  logic latch_new;
  assign latch_new = i_dec_valid[0] && !downstream_stall && !i_flush
                     && (!buf_valid0_q || dispatch_en);

  assign o_accept_cnt  = latch_new ? (pair_ok ? 2'd2 : 2'd1) : 2'd0;
  assign o_instret_cnt = {1'b0, issue_en0} + {1'b0, issue_en1};

  // Flush invalidates both buffer slots synchronously.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      buf_valid0_q <= 1'b0;
      buf_uop0_q   <= '0;
      buf_pc0_q    <= '0;
      buf_valid1_q <= 1'b0;
      buf_uop1_q   <= '0;
      buf_pc1_q    <= '0;
    end else if (i_flush) begin
      buf_valid0_q <= 1'b0;
      buf_uop0_q   <= '0;
      buf_pc0_q    <= '0;
      buf_valid1_q <= 1'b0;
      buf_uop1_q   <= '0;
      buf_pc1_q    <= '0;
    end else begin
      if (latch_new) begin
        buf_valid0_q <= 1'b1;
        buf_uop0_q   <= i_uop[0];
        buf_pc0_q    <= i_dec_pc[0];

        buf_valid1_q <= pair_ok;
        buf_uop1_q   <= i_uop[1];
        buf_pc1_q    <= i_dec_pc[1];
      end
      else if (dispatch_en) begin
        // Dispatched with nothing new behind it -> bubble.
        buf_valid0_q <= 1'b0;
        buf_valid1_q <= 1'b0;
      end
      // else: hold during stall
    end
  end

  assign o_stall_to_decode = downstream_stall;

  // ───────────────────────────────────────────────
  // 4. Register file (4R/2W) + bypass network
  // ───────────────────────────────────────────────
  logic [31:0] arf_rs1_0, arf_rs2_0, arf_rs1_1, arf_rs2_1;

  ARF rf (
    .clk           (clk),
    .rst_n         (rst_n),
    .i_re0         (buf_valid0_q),
    .i_rs1_0       (buf_uop0_q.rs1),
    .i_rs2_0       (buf_uop0_q.rs2),
    .o_rs1_data0   (arf_rs1_0),
    .o_rs2_data0   (arf_rs2_0),
    .i_re1         (buf_valid1_q),
    .i_rs1_1       (buf_uop1_q.rs1),
    .i_rs2_1       (buf_uop1_q.rs2),
    .o_rs1_data1   (arf_rs1_1),
    .o_rs2_data1   (arf_rs2_1),
    .i_wr0         (i_wb0_en),
    .i_rd0         (i_wb0_rd),
    .i_write_data0 (i_wb0_data),
    .i_wr1         (i_wb1_en),
    .i_rd1         (i_wb1_rd),
    .i_write_data1 (i_wb1_data)
  );

  logic [31:0] fwd_rs1_0, fwd_rs2_0, fwd_rs1_1, fwd_rs2_1;
  logic        fwd_hit_rs1_0, fwd_hit_rs2_0, fwd_hit_rs1_1, fwd_hit_rs2_1;

  forward_unit FWD (
    .i_alu1_writes_rd (i_alu1_fwd_writes_rd),
    .i_alu1_rd        (i_alu1_fwd_rd),
    .i_alu1_data      (i_alu1_fwd_data),
    .i_alu0_writes_rd (i_alu0_fwd_writes_rd),
    .i_alu0_rd        (i_alu0_fwd_rd),
    .i_alu0_data      (i_alu0_fwd_data),
    .i_lsu_valid      (i_lsu_fwd_data_valid),
    .i_lsu_rd         (i_lsu_fwd_rd),
    .i_lsu_data       (i_lsu_fwd_data),
    .i_ret1_writes_rd (i_ret1_fwd_writes_rd),
    .i_ret1_rd        (i_ret1_fwd_rd),
    .i_ret1_data      (i_ret1_fwd_data),
    .i_ret0_writes_rd (i_ret0_fwd_writes_rd),
    .i_ret0_rd        (i_ret0_fwd_rd),
    .i_ret0_data      (i_ret0_fwd_data),
    .i_rs1_0          (buf_uop0_q.rs1),
    .i_rs2_0          (buf_uop0_q.rs2),
    .i_arf_rs1_0      (arf_rs1_0),
    .i_arf_rs2_0      (arf_rs2_0),
    .i_rs1_1          (buf_uop1_q.rs1),
    .i_rs2_1          (buf_uop1_q.rs2),
    .i_arf_rs1_1      (arf_rs1_1),
    .i_arf_rs2_1      (arf_rs2_1),
    .o_rs1_0          (fwd_rs1_0),
    .o_rs2_0          (fwd_rs2_0),
    .o_rs1_1          (fwd_rs1_1),
    .o_rs2_1          (fwd_rs2_1),
    .o_hit_rs1_0      (fwd_hit_rs1_0),
    .o_hit_rs2_0      (fwd_hit_rs2_0),
    .o_hit_rs1_1      (fwd_hit_rs1_1),
    .o_hit_rs2_1      (fwd_hit_rs2_1)
  );

  // Scoreboard sets follow dispatch; clears follow retire writeback.
  // Trapping instructions that do not dispatch must not allocate a writer.
  logic [1:0]      sb_set_en;
  logic [1:0][4:0] sb_set_rd;
  logic [1:0]      sb_clr_en;
  logic [1:0][4:0] sb_clr_rd;
  logic [3:0][4:0] sb_query_rs;
  logic [3:0]      sb_query_busy;
  logic [31:0]     sb_busy;

  // Lane 0 selects one of ALU0, LSU or MDU; lane 1 selects ALU1.
  assign sb_set_en[0] = (alu0_if.m_valid && alu0_if.m_uop.writes_rd) ||
                        (lsu_if.m_valid  && lsu_if.m_uop.writes_rd)  ||
                        (o_mdu_valid     && o_mdu_uop.writes_rd);
  assign sb_set_rd[0] = lsu_if.m_valid ? lsu_if.m_uop.rd
                      : o_mdu_valid    ? o_mdu_uop.rd
                                       : alu0_if.m_uop.rd;
  assign sb_set_en[1] = alu1_if.m_valid && alu1_if.m_uop.writes_rd;
  assign sb_set_rd[1] = alu1_if.m_uop.rd;

  assign sb_clr_en[0] = i_wb0_en;
  assign sb_clr_rd[0] = i_wb0_rd;
  assign sb_clr_en[1] = i_wb1_en;
  assign sb_clr_rd[1] = i_wb1_rd;

  assign sb_query_rs[0] = buf_uop0_q.rs1;
  assign sb_query_rs[1] = buf_uop0_q.rs2;
  assign sb_query_rs[2] = buf_uop1_q.rs1;
  assign sb_query_rs[3] = buf_uop1_q.rs2;

  scoreboard SB (
    .clk          (clk),
    .rst_n        (rst_n),
    .i_set_en     (sb_set_en),
    .i_set_rd     (sb_set_rd),
    .i_clr_en     (sb_clr_en),
    .i_clr_rd     (sb_clr_rd),
    .i_query_rs   (sb_query_rs),
    .o_query_busy (sb_query_busy),
    .o_busy       (sb_busy)
  );

  // Operands are ready when unused, x0, not busy, or supplied by forwarding.
  function automatic logic op_ready(input logic uses, input logic busy, input logic hit);
    return !uses || !busy || hit;
  endfunction

  // Ignore bypass hits for the pending MDU destination: they can contain an
  // older writer's value. Track one destination until MDU writeback; redirects
  // must not discard the outstanding result.
  logic       mdu_pending_q;
  logic [4:0] mdu_pending_rd_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mdu_pending_q    <= 1'b0;
      mdu_pending_rd_q <= 5'd0;
    end
    else if (o_mdu_valid && o_mdu_uop.writes_rd) begin
      mdu_pending_q    <= 1'b1;
      mdu_pending_rd_q <= o_mdu_uop.rd;
    end
    else if (i_mdu_result_valid) begin
      // Cleared on the cycle the result reaches Retire. From the NEXT
      // cycle Retire's own forwarding port carries it, so a consumer
      // issuing then gets the right value through the normal bypass.
      mdu_pending_q <= 1'b0;
    end
  end

  // Also prevent a younger writer from retiring ahead of an older MDU write.
  function automatic logic blocked_by_mdu(input logic uses, input logic [4:0] rs);
    return uses && mdu_pending_q && (rs == mdu_pending_rd_q) && (rs != 5'd0);
  endfunction

  assign lane0_ops_ready = !blocked_by_mdu(buf_uop0_q.writes_rd, buf_uop0_q.rd) &&
                           op_ready(buf_uop0_q.uses_rs1, sb_query_busy[0], fwd_hit_rs1_0) &&
                           op_ready(buf_uop0_q.uses_rs2, sb_query_busy[1], fwd_hit_rs2_0) &&
                           !blocked_by_mdu(buf_uop0_q.uses_rs1, buf_uop0_q.rs1)           &&
                           !blocked_by_mdu(buf_uop0_q.uses_rs2, buf_uop0_q.rs2);
  assign lane1_ops_ready = !blocked_by_mdu(buf_uop1_q.writes_rd, buf_uop1_q.rd) &&
                           op_ready(buf_uop1_q.uses_rs1, sb_query_busy[2], fwd_hit_rs1_1) &&
                           op_ready(buf_uop1_q.uses_rs2, sb_query_busy[3], fwd_hit_rs2_1) &&
                           !blocked_by_mdu(buf_uop1_q.uses_rs1, buf_uop1_q.rs1)           &&
                           !blocked_by_mdu(buf_uop1_q.uses_rs2, buf_uop1_q.rs2);

  // ───────────────────────────────────────────────
  // 5. Operand multiplexing
  // ───────────────────────────────────────────────
  logic [31:0] op1_0, op2_0;
  always_comb begin
    op1_0 = buf_uop0_q.uses_rs1 ? fwd_rs1_0 :
            (buf_uop0_q.opcode == OPCODE_AUIPC || buf_uop0_q.is_jump) ? buf_pc0_q : 'd0;
    op2_0 = buf_uop0_q.is_jump      ? 32'd4 :
            buf_uop0_q.is_immediate ? buf_uop0_q.imm : fwd_rs2_0;
  end

  // Lane 1 is ALU-class only (OP / OP-IMM / LUI / AUIPC), so the jump
  // arm of the mux above cannot apply here. The AUIPC arm still can.
  logic [31:0] op1_1, op2_1;
  always_comb begin
    op1_1 = buf_uop1_q.uses_rs1 ? fwd_rs1_1 :
            (buf_uop1_q.opcode == OPCODE_AUIPC) ? buf_pc1_q : 'd0;
    op2_1 = buf_uop1_q.is_immediate ? buf_uop1_q.imm : fwd_rs2_1;
  end

  // ───────────────────────────────────────────────
  // 6. Branch/jump resolution – lane 0 only
  // ───────────────────────────────────────────────
  // o_branch_taken/o_branch_target report the *actual* resolved outcome
  // (used unconditionally to train the BPU, regardless of misprediction).
  // o_mispredict/o_redirect_pc are decoupled from that: they only fire
  // when the actual outcome disagrees with the prediction carried in
  // buf_uop0_q.pred_taken/pred_target.
  logic        actual_taken;
  logic [31:0] actual_target;
  logic        branch_mispredict_r;
  logic [31:0] branch_redirect_pc_r;

  assign o_resolved_pc  = buf_pc0_q;
  assign o_update_valid = issue_en0 && buf_uop0_q.is_branch;

  always_comb begin
    o_branch_taken       = 1'b0;
    o_branch_target      = 32'b0;
    branch_mispredict_r  = 1'b0;
    branch_redirect_pc_r = 32'b0;
    actual_taken    = 1'b0;
    actual_target   = 32'b0;

    if (issue_en0) begin
      if (buf_uop0_q.is_branch) begin
        actual_target = buf_pc0_q + buf_uop0_q.imm;
        case (buf_uop0_q.funct3)
          3'b000: actual_taken = (op1_0 == op2_0);                        // BEQ
          3'b001: actual_taken = (op1_0 != op2_0);                        // BNE
          3'b100: actual_taken = ($signed(op1_0) < $signed(op2_0));       // BLT
          3'b101: actual_taken = ($signed(op1_0) >= $signed(op2_0));      // BGE
          3'b110: actual_taken = (op1_0 < op2_0);                         // BLTU
          3'b111: actual_taken = (op1_0 >= op2_0);                        // BGEU
          default: actual_taken = 1'b0;
        endcase

        o_branch_taken  = actual_taken;
        o_branch_target = actual_target;

        if (actual_taken != buf_uop0_q.pred_taken) begin
          // Direction misprediction: redirect to the correct outcome
          branch_mispredict_r  = 1'b1;
          branch_redirect_pc_r = actual_taken ? actual_target : (buf_pc0_q + 32'd4);
        end else if (actual_taken && (actual_target != buf_uop0_q.pred_target)) begin
          // Predicted taken to the wrong target (stale/aliased BTB entry)
          branch_mispredict_r  = 1'b1;
          branch_redirect_pc_r = actual_target;
        end
      end else if (buf_uop0_q.opcode == OPCODE_JAL) begin
        actual_taken    = 1'b1;
        actual_target   = buf_pc0_q + buf_uop0_q.imm;
        o_branch_taken  = actual_taken;
        o_branch_target = actual_target;

        // JAL is predicted taken at fetch time (pre-decode); only
        // mispredict if the predicted target itself was wrong.
        if (!buf_uop0_q.pred_taken || (actual_target != buf_uop0_q.pred_target)) begin
          branch_mispredict_r  = 1'b1;
          branch_redirect_pc_r = actual_target;
        end
      end else if (buf_uop0_q.opcode == OPCODE_JALR) begin
        actual_taken    = 1'b1;
        actual_target   = (fwd_rs1_0 + buf_uop0_q.imm) & ~32'd1;
        o_branch_taken  = actual_taken;
        o_branch_target = actual_target;

        // JALR redirects when its resolved target differs from the RAS prediction
        // or no prediction is available.
        if (!buf_uop0_q.pred_taken || (actual_target != buf_uop0_q.pred_target)) begin
          branch_mispredict_r  = 1'b1;
          branch_redirect_pc_r = actual_target;
        end
      end
    end
  end

  // ───────────────────────────────────────────────
  // 7. CSR unit — lane 0 only
  // ───────────────────────────────────────────────
  // Resolves CSR reads/writes and traps/mret combinationally in the same
  // cycle Issue holds a SYSTEM uop. Lane 1 can never be a SYSTEM uop
  // (issue_hazard.sv), so this stays single-ported and traps stay
  // precise: a trapping lane 0 redirects, which blocks lane 1 above.
  logic        csr_dispatch_valid;
  logic [31:0] csr_rdata_now;
  logic        csr_redirect_valid;
  logic [31:0] csr_redirect_pc;

  csr_unit CSR_UNIT (
    .clk              (clk),
    .rst_n            (rst_n),
    .i_valid          (issue_en0),
    .i_instret_cnt    (o_instret_cnt),
    .i_uop            (buf_uop0_q),
    .i_pc             (buf_pc0_q),
    .i_rs1_data       (fwd_rs1_0),
    .o_dispatch_valid (csr_dispatch_valid),
    .o_rdata          (csr_rdata_now),
    .o_redirect_valid (csr_redirect_valid),
    .o_redirect_pc    (csr_redirect_pc)
  );

  // CSR trap/mret redirect takes priority (mutually exclusive with
  // branch — lane 0 is never both).
  assign o_mispredict  = branch_mispredict_r || csr_redirect_valid;
  assign o_redirect_pc = csr_redirect_valid ? csr_redirect_pc : branch_redirect_pc_r;

  // ───────────────────────────────────────────────
  // 8. Dispatch
  // ───────────────────────────────────────────────
  // Lane 0: ALU0, or the LSU, or resolved in place (branch / trap).
  always_comb begin
    alu0_if.m_valid = 1'b0;
    lsu_if.m_valid  = 1'b0;
    o_mdu_valid     = 1'b0;
    alu0_if.m_uop   = '0;
    lsu_if.m_uop    = '0;
    o_mdu_uop       = '0;
    o_mdu_op1       = op1_0;
    o_mdu_op2       = op2_0;
    alu0_if.m_pc    = buf_pc0_q;
    lsu_if.m_pc     = buf_pc0_q;
    alu0_if.m_op1   = op1_0;
    alu0_if.m_op2   = op2_0;
    lsu_if.m_addr_base  = op1_0;
    lsu_if.m_store_data = op2_0;

    if (dispatch_en) begin
      if (buf_uop0_q.is_load || buf_uop0_q.is_store) begin
        lsu_if.m_valid = 1'b1;
        alu0_if.m_valid = 1'b0;
        lsu_if.m_uop   = buf_uop0_q;
      end
      else if (buf_uop0_q.is_branch) begin
        // Branches resolved here, no need to dispatch
        alu0_if.m_valid = 1'b0;
        lsu_if.m_valid  = 1'b0;
      end
      else if (buf_uop0_q.opcode == OPCODE_SYSTEM) begin
        // CSR read result (old value) passed through the ALU as op1+0, so it
        // reaches Retire/write-back via the existing ALU path. ECALL/EBREAK/
        // MRET/illegal-instruction never write rd — resolved purely via the
        // trap/mret redirect above, nothing to dispatch.
        if (csr_dispatch_valid) begin
          alu0_if.m_valid = 1'b1;
          alu0_if.m_uop   = buf_uop0_q;
          alu0_if.m_op1   = csr_rdata_now;
          alu0_if.m_op2   = 32'b0;
        end
      end
      else if (buf_uop0_q.is_mdu) begin
        // Check MDU before generic ALU dispatch because both use opcode OP.
        // The downstream stall guarantees that the MDU is ready.
        o_mdu_valid     = 1'b1;
        o_mdu_uop       = buf_uop0_q;
        alu0_if.m_valid = 1'b0;
      end
      else begin
        // Normal ALU ops and Jumps (for write-back) go to ALU0
        alu0_if.m_valid = 1'b1;
        alu0_if.m_uop   = buf_uop0_q;
      end
    end
  end

  // Lane 1: always ALU1, never anything else.
  always_comb begin
    alu1_if.m_valid = issue_en1;
    alu1_if.m_uop   = issue_en1 ? buf_uop1_q : '0;
    alu1_if.m_pc    = buf_pc1_q;
    alu1_if.m_op1   = op1_1;
    alu1_if.m_op2   = op2_1;
  end

`ifdef SIMULATION
  // ───────────────────────────────────────────────────────────────────────────
  // Issue integrity
  // ───────────────────────────────────────────────────────────────────────────

  // 1. The bundle buffer never has a hole: lane 1 occupied with lane 0
  //    empty would let the younger instruction issue first.
  assert_no_hole: assert property (
    @(posedge clk) disable iff (!rst_n)
    buf_valid1_q |-> buf_valid0_q
  ) else $error("ISSUE ERROR: lane1 buffered with lane0 empty - out of program order");

  // 2. Lane 1 only ever holds something lane 1 can actually execute. If
  //    this fires, a load/store/branch/CSR has been paired into a lane
  //    with no unit to run it, and it would silently execute as an ALU op.
  assert_lane1_is_alu_class: assert property (
    @(posedge clk) disable iff (!rst_n)
    buf_valid1_q |-> (!buf_uop1_q.is_load && !buf_uop1_q.is_store &&
                      !buf_uop1_q.is_branch && !buf_uop1_q.is_jump &&
                      !buf_uop1_q.is_illegal &&
                      (buf_uop1_q.opcode != OPCODE_SYSTEM))
  ) else $error("ISSUE ERROR: lane1 holds a non-ALU uop (opcode=0x%h pc=0x%h)",
                buf_uop1_q.opcode, buf_pc1_q);

  // 3. No intra-bundle RAW survived into the buffer - lane 1 would read a
  //    value lane 0 has not produced yet.
  assert_no_intra_bundle_raw: assert property (
    @(posedge clk) disable iff (!rst_n)
    (buf_valid0_q && buf_valid1_q && buf_uop0_q.writes_rd && (buf_uop0_q.rd != 5'd0)) |->
      (!(buf_uop1_q.uses_rs1 && (buf_uop1_q.rs1 == buf_uop0_q.rd)) &&
       !(buf_uop1_q.uses_rs2 && (buf_uop1_q.rs2 == buf_uop0_q.rd)))
  ) else $error("ISSUE ERROR: intra-bundle RAW on x%0d (pc0=0x%h pc1=0x%h)",
                buf_uop0_q.rd, buf_pc0_q, buf_pc1_q);

  // 4. No intra-bundle WAW - the two ARF write ports would race.
  assert_no_intra_bundle_waw: assert property (
    @(posedge clk) disable iff (!rst_n)
    (buf_valid0_q && buf_valid1_q && buf_uop0_q.writes_rd && buf_uop1_q.writes_rd &&
     (buf_uop0_q.rd != 5'd0)) |-> (buf_uop0_q.rd != buf_uop1_q.rd)
  ) else $error("ISSUE ERROR: intra-bundle WAW on x%0d (pc0=0x%h pc1=0x%h)",
                buf_uop0_q.rd, buf_pc0_q, buf_pc1_q);

  // 5. Lane 1 never issues without lane 0 - program order at dispatch.
  assert_lane1_needs_lane0: assert property (
    @(posedge clk) disable iff (!rst_n)
    issue_en1 |-> issue_en0
  ) else $error("ISSUE ERROR: lane1 issued without lane0");

  // 6. Nothing wrong-path reaches an ALU. The ALUs are never flushed
  //    (cpu_core.sv ties their i_flush low) precisely because of this, and
  //    cpu_tracer.py's retirement model depends on it.
  assert_no_wrongpath_dispatch: assert property (
    @(posedge clk) disable iff (!rst_n)
    o_mispredict |-> !alu1_if.m_valid
  ) else $error("ISSUE ERROR: lane1 dispatched alongside a redirecting lane0 (pc1=0x%h)",
                buf_pc1_q);

  // 7. The accept count Decode acts on matches what was actually taken.
  assert_accept_matches_latch: assert property (
    @(posedge clk) disable iff (!rst_n)
    (o_accept_cnt == 2'd2) |-> (latch_new && pair_ok)
  ) else $error("ISSUE ERROR: accepted 2 uops without a valid pairing");
`endif

endmodule
