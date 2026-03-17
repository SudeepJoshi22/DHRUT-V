import riscv_uop_pkg::*;

module issue_stage (
  input logic clk,
  input logic rst_n,
  // From Decode stage – direct signals
  input logic i_dec_valid,
  input uop_t i_uop,
  input logic [31:0] i_dec_pc,
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
  // To Fetch – direct branch/jump signals (no interface)
  output logic o_branch_taken,
  output logic [31:0] o_branch_target,
  // Stall back to Decode/IF
  output logic o_stall_to_decode,
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
        end else if (i_dec_valid && !downstream_stall && !i_flush) begin
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
          if (i_dec_valid && !downstream_stall && !i_flush) begin
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
          if (i_dec_valid && !downstream_stall && !i_flush) begin
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

  // State & buffer register
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || i_flush) begin
      state_q     <= S_IDLE;
      buf_valid_q <= 1'b0;
      buf_uop_q   <= '0;
      buf_pc_q    <= '0;
    end else begin
      state_q <= state_d;
  
      // Latch new uop (from IDLE)
      if (state_q == S_IDLE && i_dec_valid && !downstream_stall && !i_flush) begin
        buf_valid_q <= 1'b1;
        buf_uop_q   <= i_uop;
        buf_pc_q    <= i_dec_pc;
      end
  
      // Dispatch success: clear old, but re-latch new if available (zero bubble)
      else if (dispatch_en) begin
        if (i_dec_valid && !downstream_stall && !i_flush) begin
          // Opportunistic: consume old, accept new same cycle
          buf_valid_q <= 1'b1;
          buf_uop_q   <= i_uop;
          buf_pc_q    <= i_dec_pc;
        end else begin
          // Normal clear (bubble if no new)
          buf_valid_q <= 1'b0;
          // Optional: buf_uop_q <= '0; buf_pc_q <= '0;
        end
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
  // 4. Branch/jump decision & target – gated on issue_en
  // ───────────────────────────────────────────────
  always_comb begin
    o_branch_taken = 1'b0;
    o_branch_target = 32'b0;

    // Only evaluate when we have a valid uop in buffer
    if (issue_en) begin
      if (buf_uop_q.is_branch) begin
        o_branch_target = buf_pc_q + buf_uop_q.imm;
        case (buf_uop_q.funct3)
          3'b000: o_branch_taken = (op1 == op2);                        // BEQ
          3'b001: o_branch_taken = (op1 != op2);                        // BNE
          3'b100: o_branch_taken = ($signed(op1) < $signed(op2));       // BLT
          3'b101: o_branch_taken = ($signed(op1) >= $signed(op2));      // BGE
          3'b110: o_branch_taken = (op1 < op2);                         // BLTU
          3'b111: o_branch_taken = (op1 >= op2);                        // BGEU
          default: o_branch_taken = 1'b0;
        endcase
      end else if (buf_uop_q.opcode == OPCODE_JAL) begin
        o_branch_taken = 1'b1;
        o_branch_target = buf_pc_q + buf_uop_q.imm;
      end else if (buf_uop_q.opcode == OPCODE_JALR) begin
        o_branch_taken = 1'b1;
        o_branch_target = (fwd_rs1 + buf_uop_q.imm) & ~32'd1;
      end
    end
  end

  // ───────────────────────────────────────────────
  // 5. Dispatch to ALU or LSU – gated on dispatch_en
  // ───────────────────────────────────────────────
  logic dispatch_en;
  assign dispatch_en    = issue_en && !downstream_stall && unit_ack;

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
      else begin
        // Normal ALU ops and Jumps (for write-back) go to ALU
        alu_if.m_valid = 1'b1;
        alu_if.m_uop   = buf_uop_q;
      end
    end
  end

endmodule
