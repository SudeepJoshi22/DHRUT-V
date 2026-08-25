import riscv_uop_pkg::*;

// =================================================================
// issue_stage - 2-wide in-order issue
// =================================================================
// Holds one bundle (up to two uops, lane 0 the older), reads four ARF
// ports, resolves operands through the bypass network, and dispatches:
//
//   lane 0 -> ALU0, or the LSU, or resolved in place (branch / CSR)
//   lane 1 -> ALU1 only
//
// Lane 1 is deliberately a bare ALU. Every instruction class it cannot
// take needs a unit that exists exactly once (LSU + dmem port, branch
// resolver + BPU update port, CSR file). Keeping lane 1 narrow is what
// lets this stage widen without touching lsu.sv, csr_unit.sv or bpu.sv
// at all. See rtl/pipeline/issue_hazard.sv for the full rule set.
//
// The 3-state FSM (S_IDLE/S_READY/S_WAITING) that used to live here is
// gone. `state_q == S_IDLE` was exactly `!buf_valid_q`, so the state
// register carried no information the valid bit did not already have -
// widening it to two lanes would have doubled dead state. Its one
// remaining use, the `(state_q == S_IDLE) || dispatch_en` term in
// `latch_new`, reduces to a tautology once `!downstream_stall` is
// factored out, so it disappears entirely rather than being replaced.

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
  lsu_issue_if.issuer lsu_if
);

  // ───────────────────────────────────────────────
  // 1. Bundle buffer
  // ───────────────────────────────────────────────
  // Deliberately two sets of scalar registers rather than one packed
  // `uop_t [1:0]`: Verilator's VPI presents a packed array as a single
  // flat vector, so the testbench (cpu_tracer.py, monitor_config.yaml)
  // could not read one lane without knowing the struct width. Scalars
  // keep ISSUE.buf_uop0_q / ISSUE.buf_uop1_q directly addressable.
  logic        buf_valid0_q;
  uop_t        buf_uop0_q;
  logic [31:0] buf_pc0_q;

  logic        buf_valid1_q;
  uop_t        buf_uop1_q;
  logic [31:0] buf_pc1_q;

  // Stall aggregation (scalable – add more units later)
  logic  downstream_stall;
  assign downstream_stall = i_stall || lsu_if.s_stall_from_lsu;
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

  // ───────────────────────────────────────────────
  // 3. Issue / dispatch enables
  // ───────────────────────────────────────────────
  // Lane 0 is the oldest instruction in the machine: it issues whenever
  // it is held and nothing downstream is stalling.
  // Operand readiness from the scoreboard + bypass network. Declared here
  // because the issue enables below need them; driven in section 4b,
  // next to the scoreboard instance they come from.
  logic lane0_ops_ready, lane1_ops_ready;

  logic issue_en0;
  assign issue_en0 = buf_valid0_q && operands_ready && lane0_ops_ready;

  logic dispatch_en;              // lane 0 leaves this cycle
  assign dispatch_en = issue_en0;

  // Lane 1 additionally requires that lane 0 does not redirect control
  // flow this cycle. This is the whole reason a branch in lane 0 is safe
  // to pair with: on a correct prediction lane 1 is exactly the
  // instruction fetch already followed to, so it is on the right path;
  // on a mispredict (or a CSR trap/mret) lane 1 is wrong-path and must
  // not execute. Holding it back here - rather than flushing it out of
  // the ALU afterwards - is what preserves the invariant that ONCE
  // DISPATCHED, AN INSTRUCTION ALWAYS COMPLETES. alu_stage's i_flush
  // stays tied off, and cpu_tracer.py's retirement model stays valid.
  logic issue_en1;
  assign issue_en1 = buf_valid1_q && operands_ready && lane1_ops_ready && !o_mispredict;

  // Decode handshake: the single condition under which Issue takes a new
  // bundle. Used both to load the buffer and to report o_accept_cnt, so
  // the two cannot drift apart and drop or replay an instruction.
  // A new bundle may only be taken when the held one is leaving (or there
  // is none). With the scoreboard able to hold lane 0 back, "not stalled
  // downstream" is no longer sufficient on its own.
  logic latch_new;
  assign latch_new = i_dec_valid[0] && !downstream_stall && !i_flush
                     && (!buf_valid0_q || dispatch_en);

  assign o_accept_cnt  = latch_new ? (pair_ok ? 2'd2 : 2'd1) : 2'd0;
  assign o_instret_cnt = {1'b0, issue_en0} + {1'b0, issue_en1};

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || i_flush) begin
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

  // ───────────────────────────────────────────────
  // 4b. Scoreboard: outstanding writes + operand readiness
  // ───────────────────────────────────────────────
  // See rtl/pipeline/scoreboard.sv for what this is and why it exists
  // before it is strictly needed. Set ports come from the DISPATCH
  // handshakes below, not from writes_rd, so that anything which never
  // reaches write-back (an illegal CSR access, say) never leaves a
  // counter stranded. Clear ports are the two retire write-backs.
  logic [1:0]      sb_set_en;
  logic [1:0][4:0] sb_set_rd;
  logic [1:0]      sb_clr_en;
  logic [1:0][4:0] sb_clr_rd;
  logic [3:0][4:0] sb_query_rs;
  logic [3:0]      sb_query_busy;
  logic [31:0]     sb_busy;

  // Lane 0 dispatches to exactly one of ALU0/LSU; lane 1 only to ALU1.
  assign sb_set_en[0] = (alu0_if.m_valid && alu0_if.m_uop.writes_rd) ||
                        (lsu_if.m_valid  && lsu_if.m_uop.writes_rd);
  assign sb_set_rd[0] = lsu_if.m_valid ? lsu_if.m_uop.rd : alu0_if.m_uop.rd;
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

  // An operand is ready if it is not needed, is x0, has no write in
  // flight, or has one that the bypass network can supply RIGHT NOW.
  // With today's units the last term is always true whenever the third
  // is false, so this never stalls - the trace gate proves it. It starts
  // biting as soon as a unit exists whose result is not on the bypass
  // network every cycle between dispatch and write-back (a multi-cycle
  // MDU, or a non-blocking load queue).
  function automatic logic op_ready(input logic uses, input logic busy, input logic hit);
    return !uses || !busy || hit;
  endfunction

  assign lane0_ops_ready = op_ready(buf_uop0_q.uses_rs1, sb_query_busy[0], fwd_hit_rs1_0) &&
                           op_ready(buf_uop0_q.uses_rs2, sb_query_busy[1], fwd_hit_rs2_0);
  assign lane1_ops_ready = op_ready(buf_uop1_q.uses_rs1, sb_query_busy[2], fwd_hit_rs1_1) &&
                           op_ready(buf_uop1_q.uses_rs2, sb_query_busy[3], fwd_hit_rs2_1);

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

        // No indirect (JALR/BTB) prediction yet: always redirect.
        branch_mispredict_r  = 1'b1;
        branch_redirect_pc_r = actual_target;
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
    alu0_if.m_uop   = '0;
    lsu_if.m_uop    = '0;
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
