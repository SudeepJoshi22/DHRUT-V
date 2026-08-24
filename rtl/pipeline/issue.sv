import riscv_uop_pkg::*;

module issue_stage (
  input logic clk,
  input logic rst_n,
  // From Decode stage – a 2-wide bundle, slot 0 the older instruction.
  // Issue is still 1-wide (Phase 3 widens it), so only slot 0 is consumed;
  // slot 1 stays in decode's buffer and shifts down next cycle.
  input logic [1:0] i_dec_valid,
  input uop_t [1:0] i_uop,
  input logic [1:0][31:0] i_dec_pc,
  // Stall & flush from downstream
  input logic i_stall,
  input logic i_flush,
  // From Retire/WB (write-back to ARF)
  input logic i_wb_en,
  input logic [4:0] i_wb_rd,
  input logic [31:0] i_wb_data,
  // FORWARDING - From ALU
  input logic i_alu_fwd_writes_rd,
  input logic [4:0] i_alu_fwd_rd,
  input logic [31:0] i_alu_fwd_data,
  // FORWARDING - From RETIRE
  input logic i_retire_fwd_writes_rd,
  input logic [4:0] i_retire_fwd_rd,
  input logic [31:0] i_retire_fwd_data,
  // FORWARDING - From LSU
  input logic i_lsu_fwd_data_valid,
  input logic [4:0] i_lsu_fwd_rd,
  input logic [31:0] i_lsu_fwd_data,
  // To Fetch – actual resolved branch/jump outcome (used to train the BPU)
  output logic o_branch_taken,
  output logic [31:0] o_branch_target,
  output logic [31:0] o_resolved_pc,
  output logic o_update_valid,
  // To Fetch/Decode – decoupled misprediction redirect (only asserted when
  // the actual outcome differs from the carried prediction)
  output logic o_mispredict,
  output logic [31:0] o_redirect_pc,
  // Stall back to Decode/IF
  output logic o_stall_to_decode,
  // How many of decode's slots were consumed this cycle (0..2). This is
  // the real handshake with decode - o_stall_to_decode is now only a
  // status/debug view of why it might be 0.
  output logic [1:0] o_accept_cnt,
  // Issued to ALU
  alu_issue_if.issuer alu_if,
  // Issued to LSU (with back-pressure)
  lsu_issue_if.issuer lsu_if
);

  // ───────────────────────────────────────────────
  // NEW: 3-state FSM for dispatch/issue buffer
  // ───────────────────────────────────────────────
  typedef enum logic [1:0] {
    S_IDLE    = 2'b00,   // No uop buffered, ready to accept
    S_READY   = 2'b01,   // uop buffered, can issue if no stall
    S_WAITING = 2'b10    // uop buffered, but stalled downstream
  } issue_state_t;

  issue_state_t state_q, state_d;

  // ───────────────────────────────────────────────
  // Slot-0 view of decode's bundle. Everything below is written against
  // these, so widening Issue in Phase 3 means adding a second set rather
  // than rewriting the existing logic.
  // ───────────────────────────────────────────────
  logic        dec_valid0;
  uop_t        dec_uop0;
  logic [31:0] dec_pc0;

  assign dec_valid0 = i_dec_valid[0];
  assign dec_uop0   = i_uop[0];
  assign dec_pc0    = i_dec_pc[0];

  // Buffer registers (replacing old dec_valid_q, uop_q, dec_pc_q)
  logic      buf_valid_q;
  uop_t      buf_uop_q;
  logic [31:0] buf_pc_q;

  // Stall aggregation (scalable – add more units later)
  logic  downstream_stall;
  assign downstream_stall = i_stall || lsu_if.s_stall_from_lsu;
  // FUTURE: || alu_stall || fpu_stall || vec_stall

  // Issue enable (active in READY & WAITING)
  logic operands_ready;
  assign operands_ready     =   !i_stall && !lsu_if.s_stall_from_lsu;  // FUTURE: && !pending reads etc.
  
  logic issue_en;
  assign issue_en           =   buf_valid_q && operands_ready;

  // Ack from downstream (simple version: no stall = ready)
  // FUTURE: use per-unit s_ready signals
  logic unit_ack;
  assign unit_ack   =   !downstream_stall;

  // Next-state logic
  always_comb begin
    state_d = state_q;

    case (state_q)
      S_IDLE: begin
        if (i_flush) begin
          // no change needed
        end else if (dec_valid0 && !downstream_stall && !i_flush) begin
          state_d = S_READY;
        end
      end

      S_READY: begin
        if (i_flush) begin
          state_d = S_IDLE;
        end else if (downstream_stall) begin
          state_d = S_WAITING;
        // In S_READY and S_WAITING cases:
        end else if (!downstream_stall && issue_en && unit_ack) begin
          if (dec_valid0 && !downstream_stall && !i_flush) begin
            state_d = S_READY;  // Re-latched → stay READY (continue issuing)
          end else begin
            state_d = S_IDLE;   // Cleared without new → IDLE
          end
        end
      end

      S_WAITING: begin
        if (i_flush) begin
          state_d = S_IDLE;
        // In S_READY and S_WAITING cases:
        end else if (!downstream_stall && issue_en && unit_ack) begin
          if (dec_valid0 && !downstream_stall && !i_flush) begin
            state_d = S_READY;  // Re-latched → stay READY (continue issuing)
          end else begin
            state_d = S_IDLE;   // Cleared without new → IDLE
          end
        end
        // else stay in WAITING
      end

      default: state_d = S_IDLE;
    endcase
  end

  // ───────────────────────────────────────────────
  // Decode handshake: the single condition under which Issue takes a uop
  // off decode this cycle. It is used both to load the buffer and to
  // report o_accept_cnt, so the two can never drift apart - if they did,
  // decode would drop an instruction it thought was consumed (or replay
  // one it thought was not).
  //
  // The buffer is loaded either from IDLE (nothing held) or on a
  // successful dispatch (the held uop leaves the same cycle), which is a
  // zero-bubble hand-off.
  // ───────────────────────────────────────────────
  // The buffered uop leaves for ALU/LSU this cycle.
  logic dispatch_en;
  assign dispatch_en = issue_en && !downstream_stall && unit_ack;

  logic latch_new;
  assign latch_new = dec_valid0 && !downstream_stall && !i_flush
                     && ((state_q == S_IDLE) || dispatch_en);

  assign o_accept_cnt = latch_new ? 2'd1 : 2'd0;

  // State & buffer register
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || i_flush) begin
      state_q     <= S_IDLE;
      buf_valid_q <= 1'b0;
      buf_uop_q   <= '0;
      buf_pc_q    <= '0;
    end else begin
      state_q <= state_d;

      if (latch_new) begin
        buf_valid_q <= 1'b1;
        buf_uop_q   <= dec_uop0;
        buf_pc_q    <= dec_pc0;
      end
      else if (dispatch_en) begin
        // Dispatched with nothing new behind it -> bubble.
        buf_valid_q <= 1'b0;
      end
      // else: hold during stall (WAITING)
    end
  end

  // Stall back to upstream – refined: stall if holding (WAITING) or full without dispatch
  assign o_stall_to_decode = downstream_stall;

  // ───────────────────────────────────────────────
  // 2. Register File (ARF) inside Issue – updated to use buffer
  // ───────────────────────────────────────────────
  logic [31:0] rs1_data, rs2_data;
  ARF rf (
    .clk (clk),
    .rst_n (rst_n),
    .i_re (buf_valid_q),          // ← changed
    .i_wr (i_wb_en),
    .i_rs1 (buf_uop_q.rs1),       // ← changed
    .i_rs2 (buf_uop_q.rs2),
    .i_rd (i_wb_rd),
    .i_write_data (i_wb_data),
    .o_read_data1 (rs1_data),
    .o_read_data2 (rs2_data)
  );

  // Forwarding logic – updated to use buf_uop_q
  logic [31:0] fwd_rs1, fwd_rs2;
  always_comb begin
    fwd_rs1 = rs1_data;
    fwd_rs2 = rs2_data;

    if (i_alu_fwd_writes_rd && (i_alu_fwd_rd == buf_uop_q.rs1) && (buf_uop_q.rs1 != 5'd0)) begin
      fwd_rs1 = i_alu_fwd_data;
    end else if (i_retire_fwd_writes_rd && (i_retire_fwd_rd == buf_uop_q.rs1) && (buf_uop_q.rs1 != 5'd0)) begin
      fwd_rs1 = i_retire_fwd_data;
    end else if (i_lsu_fwd_data_valid && (i_lsu_fwd_rd == buf_uop_q.rs1) && (buf_uop_q.rs1 != 5'd0)) begin
      fwd_rs1 = i_lsu_fwd_data;
    end

    if (i_alu_fwd_writes_rd && (i_alu_fwd_rd == buf_uop_q.rs2) && (buf_uop_q.rs2 != 5'd0)) begin
      fwd_rs2 = i_alu_fwd_data;
    end else if (i_retire_fwd_writes_rd && (i_retire_fwd_rd == buf_uop_q.rs2) && (buf_uop_q.rs2 != 5'd0)) begin
      fwd_rs2 = i_retire_fwd_data;
    end else if (i_lsu_fwd_data_valid && (i_lsu_fwd_rd == buf_uop_q.rs2) && (buf_uop_q.rs2 != 5'd0)) begin
      fwd_rs2 = i_lsu_fwd_data;
    end
  end

  // ───────────────────────────────────────────────
  // 3. Operand multiplexing (with forwarding)
  // ───────────────────────────────────────────────
  logic [31:0] op1, op2;
  always_comb begin
    op1 = buf_uop_q.uses_rs1 ? fwd_rs1 : (buf_uop_q.opcode == OPCODE_AUIPC || buf_uop_q.is_jump) ? buf_pc_q : 'd0;
    op2 = buf_uop_q.is_jump ? 32'd4 :
          buf_uop_q.is_immediate ? buf_uop_q.imm : fwd_rs2;
  end


  // ───────────────────────────────────────────────
  // 4. Branch/jump resolution – gated on issue_en
  // ───────────────────────────────────────────────
  // o_branch_taken/o_branch_target report the *actual* resolved outcome
  // (used unconditionally to train the BPU, regardless of misprediction).
  // o_mispredict/o_redirect_pc are decoupled from that: they only fire
  // when the actual outcome disagrees with the prediction carried in
  // buf_uop_q.pred_taken/pred_target, and redirect to the correct PC in
  // either direction (taken-target when actually taken, buf_pc_q+4 when
  // actually not-taken).
  logic        actual_taken;
  logic [31:0] actual_target;
  logic        branch_mispredict_r;
  logic [31:0] branch_redirect_pc_r;

  assign o_resolved_pc  = buf_pc_q;
  assign o_update_valid = issue_en && buf_uop_q.is_branch;

  always_comb begin
    o_branch_taken       = 1'b0;
    o_branch_target      = 32'b0;
    branch_mispredict_r  = 1'b0;
    branch_redirect_pc_r = 32'b0;
    actual_taken    = 1'b0;
    actual_target   = 32'b0;

    // Only evaluate when we have a valid uop in buffer
    if (issue_en) begin
      if (buf_uop_q.is_branch) begin
        actual_target = buf_pc_q + buf_uop_q.imm;
        case (buf_uop_q.funct3)
          3'b000: actual_taken = (op1 == op2);                        // BEQ
          3'b001: actual_taken = (op1 != op2);                        // BNE
          3'b100: actual_taken = ($signed(op1) < $signed(op2));       // BLT
          3'b101: actual_taken = ($signed(op1) >= $signed(op2));      // BGE
          3'b110: actual_taken = (op1 < op2);                         // BLTU
          3'b111: actual_taken = (op1 >= op2);                        // BGEU
          default: actual_taken = 1'b0;
        endcase

        o_branch_taken  = actual_taken;
        o_branch_target = actual_target;

        if (actual_taken != buf_uop_q.pred_taken) begin
          // Direction misprediction: redirect to the correct outcome
          branch_mispredict_r  = 1'b1;
          branch_redirect_pc_r = actual_taken ? actual_target : (buf_pc_q + 32'd4);
        end else if (actual_taken && (actual_target != buf_uop_q.pred_target)) begin
          // Predicted taken to the wrong target (stale/aliased BTB entry)
          branch_mispredict_r  = 1'b1;
          branch_redirect_pc_r = actual_target;
        end
      end else if (buf_uop_q.opcode == OPCODE_JAL) begin
        actual_taken    = 1'b1;
        actual_target   = buf_pc_q + buf_uop_q.imm;
        o_branch_taken  = actual_taken;
        o_branch_target = actual_target;

        // JAL is predicted taken at fetch time (pre-decode); only
        // mispredict if the predicted target itself was wrong.
        if (!buf_uop_q.pred_taken || (actual_target != buf_uop_q.pred_target)) begin
          branch_mispredict_r  = 1'b1;
          branch_redirect_pc_r = actual_target;
        end
      end else if (buf_uop_q.opcode == OPCODE_JALR) begin
        actual_taken    = 1'b1;
        actual_target   = (fwd_rs1 + buf_uop_q.imm) & ~32'd1;
        o_branch_taken  = actual_taken;
        o_branch_target = actual_target;

        // No indirect (JALR/BTB) prediction yet: always redirect.
        branch_mispredict_r  = 1'b1;
        branch_redirect_pc_r = actual_target;
      end
    end
  end

  // ───────────────────────────────────────────────
  // 4b. CSR unit — resolves CSR reads/writes and traps/mret combinationally
  //     in the same cycle Issue holds a SYSTEM uop (same timing as the
  //     branch/jump resolution above), but factored into its own module so
  //     Issue itself stays a pure issuer: register read, forwarding,
  //     dispatch. Unlike ALU/LSU (pipelined interface, resolved a cycle
  //     later), this is a direct same-cycle combinational connection to
  //     Issue's buffered uop. See rtl/pipeline/csr_unit.sv.
  // ───────────────────────────────────────────────
  logic        csr_dispatch_valid;
  logic [31:0] csr_rdata_now;
  logic        csr_redirect_valid;
  logic [31:0] csr_redirect_pc;

  csr_unit CSR_UNIT (
    .clk              (clk),
    .rst_n            (rst_n),
    .i_valid          (issue_en),
    .i_uop            (buf_uop_q),
    .i_pc             (buf_pc_q),
    .i_rs1_data       (fwd_rs1),
    .o_dispatch_valid (csr_dispatch_valid),
    .o_rdata          (csr_rdata_now),
    .o_redirect_valid (csr_redirect_valid),
    .o_redirect_pc    (csr_redirect_pc)
  );

  // CSR trap/mret redirect takes priority (mutually exclusive with branch
  // in practice — a single buffered uop is never more than one of these).
  assign o_mispredict  = branch_mispredict_r || csr_redirect_valid;
  assign o_redirect_pc = csr_redirect_valid ? csr_redirect_pc : branch_redirect_pc_r;

  // ───────────────────────────────────────────────
  // 5. Dispatch to ALU or LSU – gated on dispatch_en (declared above,
  //    next to latch_new, which depends on it)
  // ───────────────────────────────────────────────
  always_comb begin
    alu_if.m_valid = 1'b0;
    lsu_if.m_valid = 1'b0;
    alu_if.m_uop   = '0;
    lsu_if.m_uop   = '0;
    alu_if.m_pc    = buf_pc_q;
    lsu_if.m_pc    = buf_pc_q;
    alu_if.m_op1   = op1;
    alu_if.m_op2   = op2;
    lsu_if.m_addr_base = op1;
    lsu_if.m_store_data = op2;

    if (dispatch_en) begin
      if (buf_uop_q.is_load || buf_uop_q.is_store) begin
        lsu_if.m_valid = 1'b1;
        alu_if.m_valid = 1'b0;
        lsu_if.m_uop   = buf_uop_q;
      end 
      else if (buf_uop_q.is_branch) begin
        // Branches resolved here, no need to dispatch
        alu_if.m_valid = 1'b0;
        lsu_if.m_valid = 1'b0;
      end
      else if (buf_uop_q.opcode == OPCODE_SYSTEM) begin
        // CSR read result (old value) passed through the ALU as op1+0, so it
        // reaches Retire/write-back via the existing ALU path. ECALL/EBREAK/
        // MRET/illegal-instruction never write rd — resolved purely via the
        // trap/mret redirect above, nothing to dispatch.
        if (csr_dispatch_valid) begin
          alu_if.m_valid = 1'b1;
          alu_if.m_uop   = buf_uop_q;
          alu_if.m_op1   = csr_rdata_now;
          alu_if.m_op2   = 32'b0;
        end
      end
      else begin
        // Normal ALU ops and Jumps (for write-back) go to ALU
        alu_if.m_valid = 1'b1;
        alu_if.m_uop   = buf_uop_q;
      end
    end
  end

endmodule
