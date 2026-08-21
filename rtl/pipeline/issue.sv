import riscv_uop_pkg::*;
import csr_regfile_gen_pkg::*;

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
  // 4b. CSR + trap/mret resolution (SYSTEM opcode) — resolved combinationally
  //     at the same point branches/jumps are, above.
  // ───────────────────────────────────────────────
  logic        is_system, is_csr_form, is_priv_form;
  logic [11:0] sys_imm12;
  logic        is_ecall, is_ebreak, is_mret;
  logic        overall_illegal;

  assign is_system   = (buf_uop_q.opcode == OPCODE_SYSTEM);
  assign is_csr_form = is_system && (buf_uop_q.funct3 != 3'b000);
  assign is_priv_form = is_system && (buf_uop_q.funct3 == 3'b000);
  assign sys_imm12   = buf_uop_q.imm[11:0];
  assign is_ecall    = is_priv_form && !buf_uop_q.is_illegal && (sys_imm12 == 12'h000);
  assign is_ebreak   = is_priv_form && !buf_uop_q.is_illegal && (sys_imm12 == 12'h001);
  assign is_mret     = is_priv_form && !buf_uop_q.is_illegal && (sys_imm12 == 12'h302);

  // CSR read (combinational, from the generated block's live field state via
  // hwif_out — bypasses the cpuif bus entirely so read-then-modify-then-write
  // still resolves in one cycle) / write value mux
  logic [31:0] csr_rdata_now;
  logic        csr_addr_invalid;
  logic [31:0] csr_write_src;
  logic [1:0]  csr_op_kind;      // funct3[1:0]: 01=RW, 10=RS, 11=RC
  logic [31:0] csr_new_val;
  logic        csr_we;
  logic        csr_dispatch_valid;
  logic [6:0]  csr_rdl_addr;     // RISC-V CSR# -> rtl/csr/csr_regfile.rdl offset (see rtl/csr/README.md)

  csr_regfile_gen_pkg::csr_regfile__in_t  csr_hwif_in;
  csr_regfile_gen_pkg::csr_regfile__out_t csr_hwif_out;

  assign csr_write_src = buf_uop_q.uses_rs1 ? fwd_rs1 : {27'b0, buf_uop_q.rs1};
  assign csr_op_kind   = buf_uop_q.funct3[1:0];

  // CSR#/offset table mirrors rtl/csr/csr_regfile.rdl's addrmap exactly -
  // keep both in sync if the .rdl's offsets ever change.
  always_comb begin
    csr_addr_invalid = 1'b0;
    csr_rdl_addr      = 7'h00;
    unique case (buf_uop_q.imm[11:0])
      12'h300: csr_rdl_addr = 7'h00;  // mstatus
      12'h301: csr_rdl_addr = 7'h04;  // misa
      12'h304: csr_rdl_addr = 7'h08;  // mie
      12'h305: csr_rdl_addr = 7'h0C;  // mtvec
      12'h340: csr_rdl_addr = 7'h10;  // mscratch
      12'h341: csr_rdl_addr = 7'h14;  // mepc
      12'h342: csr_rdl_addr = 7'h18;  // mcause
      12'h343: csr_rdl_addr = 7'h1C;  // mtval
      12'h344: csr_rdl_addr = 7'h20;  // mip
      12'hB00: csr_rdl_addr = 7'h24;  // mcycle
      12'hB02: csr_rdl_addr = 7'h28;  // minstret
      12'hB80: csr_rdl_addr = 7'h2C;  // mcycleh
      12'hB82: csr_rdl_addr = 7'h30;  // minstreth
      12'hF11: csr_rdl_addr = 7'h34;  // mvendorid
      12'hF12: csr_rdl_addr = 7'h38;  // marchid
      12'hF13: csr_rdl_addr = 7'h3C;  // mimpid
      12'hF14: csr_rdl_addr = 7'h40;  // mhartid
      default: csr_addr_invalid = 1'b1;
    endcase
  end

  // Live read (mirrors the same address table; RO/constant CSRs are
  // hardwired here exactly as they are in the generated block's readback
  // mux, since PeakRDL doesn't expose hwif_out for hw=na constant fields).
  always_comb begin
    unique case (buf_uop_q.imm[11:0])
      12'h300: csr_rdata_now = {19'b0, 2'b11, 3'b0, csr_hwif_out.mstatus.MPIE.value, 3'b0, csr_hwif_out.mstatus.MIE.value, 3'b0};
      12'h301: csr_rdata_now = 32'h4000_0100;
      12'h304: csr_rdata_now = {20'b0, csr_hwif_out.mie.MEIE.value, 3'b0, csr_hwif_out.mie.MTIE.value, 3'b0, csr_hwif_out.mie.MSIE.value, 3'b0};
      12'h305: csr_rdata_now = csr_hwif_out.mtvec.MTVEC.value;
      12'h340: csr_rdata_now = csr_hwif_out.mscratch.MSCRATCH.value;
      12'h341: csr_rdata_now = {csr_hwif_out.mepc.MEPC_HI.value, 2'b00};
      12'h342: csr_rdata_now = csr_hwif_out.mcause.MCAUSE.value;
      12'h343: csr_rdata_now = csr_hwif_out.mtval.MTVAL.value;
      12'h344: csr_rdata_now = 32'h0;
      12'hB00: csr_rdata_now = csr_hwif_out.mcycle.MCYCLE.value;
      12'hB02: csr_rdata_now = csr_hwif_out.minstret.MINSTRET.value;
      12'hB80: csr_rdata_now = csr_hwif_out.mcycleh.MCYCLEH.value;
      12'hB82: csr_rdata_now = csr_hwif_out.minstreth.MINSTRETH.value;
      12'hF11: csr_rdata_now = 32'h0;
      12'hF12: csr_rdata_now = 32'h0;
      12'hF13: csr_rdata_now = 32'h0;
      12'hF14: csr_rdata_now = 32'h0;
      default: csr_rdata_now = 32'h0;
    endcase
  end

  always_comb begin
    unique case (csr_op_kind)
      2'b01:   csr_new_val = csr_write_src;                     // CSRRW(I)
      2'b10:   csr_new_val = csr_rdata_now | csr_write_src;     // CSRRS(I)
      2'b11:   csr_new_val = csr_rdata_now & ~csr_write_src;    // CSRRC(I)
      default: csr_new_val = csr_rdata_now;
    endcase
  end

  assign overall_illegal    = buf_uop_q.is_illegal || (is_csr_form && csr_addr_invalid);
  // CSRRW(I) always writes; CSRRS/C(I) only write when the source is non-zero
  // (register rs1 != x0, or a non-zero uimm — both share the rs1 encoding field).
  assign csr_we             = issue_en && is_csr_form && !csr_addr_invalid &&
                               ((csr_op_kind == 2'b01) || (buf_uop_q.rs1 != 5'd0));
  assign csr_dispatch_valid = is_csr_form && !csr_addr_invalid;

  // Trap detection: illegal instruction / ecall / ebreak (mret is a redirect, not a trap)
  logic        trap_taken;
  logic [31:0] trap_cause_code;
  logic [31:0] trap_val;

  always_comb begin
    trap_taken      = 1'b0;
    trap_cause_code = 32'b0;
    trap_val        = 32'b0;

    if (issue_en) begin
      if (overall_illegal) begin
        trap_taken      = 1'b1;
        trap_cause_code = 32'd2;   // Illegal instruction
        trap_val        = buf_uop_q.instr_bits;  // matches Spike's convention
      end else if (is_ecall) begin
        trap_taken      = 1'b1;
        trap_cause_code = 32'd11;  // Environment call from M-mode
      end else if (is_ebreak) begin
        trap_taken      = 1'b1;
        trap_cause_code = 32'd3;   // Breakpoint
        trap_val        = buf_pc_q;
      end
    end
  end

  logic mret_taken;
  assign mret_taken = issue_en && is_mret;

  // mtvec is direct-mode only (see rtl/csr/csr_regfile.rdl); mepc's low 2
  // bits are a hardwired-0 field (RESERVED_LOW), so MEPC_HI is already the
  // full address with the low 2 bits implicitly zero.
  logic [31:0] csr_trap_target;
  logic [31:0] csr_mepc_out;
  assign csr_trap_target = {csr_hwif_out.mtvec.MTVEC.value[31:2], 2'b00};
  assign csr_mepc_out    = {csr_hwif_out.mepc.MEPC_HI.value, 2'b00};

  // Hardware-side (trap entry / mret / counters) writes into the generated
  // block's per-field next/we ports. Priority vs. a same-cycle SW write is
  // SW-checked-first in PeakRDL's generated logic (see rtl/csr/README.md) -
  // currently moot since Issue resolves one uop/cycle, so a CSR write and a
  // trap/mret/counter-tick on the same field can't coincide except for the
  // counters, where SW winning that one cycle is the desired behavior.
  always_comb begin
    // NOTE: assigning '0 to this whole (unpacked, heterogeneous) struct at
    // once trips up Verilator's C++ codegen, so default each leaf field
    // individually instead.
    csr_hwif_in.mstatus.MIE.we       = 1'b0;
    csr_hwif_in.mstatus.MIE.next     = 1'b0;
    csr_hwif_in.mstatus.MPIE.we      = 1'b0;
    csr_hwif_in.mstatus.MPIE.next    = 1'b0;
    csr_hwif_in.mepc.MEPC_HI.we      = 1'b0;
    csr_hwif_in.mepc.MEPC_HI.next    = 30'b0;
    csr_hwif_in.mcause.MCAUSE.we     = 1'b0;
    csr_hwif_in.mcause.MCAUSE.next   = 32'b0;
    csr_hwif_in.mtval.MTVAL.we       = 1'b0;
    csr_hwif_in.mtval.MTVAL.next     = 32'b0;
    csr_hwif_in.mcycle.MCYCLE.we     = 1'b0;
    csr_hwif_in.mcycle.MCYCLE.next   = 32'b0;
    csr_hwif_in.mcycleh.MCYCLEH.we   = 1'b0;
    csr_hwif_in.mcycleh.MCYCLEH.next = 32'b0;
    csr_hwif_in.minstret.MINSTRET.we      = 1'b0;
    csr_hwif_in.minstret.MINSTRET.next    = 32'b0;
    csr_hwif_in.minstreth.MINSTRETH.we    = 1'b0;
    csr_hwif_in.minstreth.MINSTRETH.next  = 32'b0;

    // mcycle(h): free-running, always increments; SW write (if any, that
    // cycle) takes priority per the generated field logic.
    csr_hwif_in.mcycle.MCYCLE.we     = 1'b1;
    csr_hwif_in.mcycle.MCYCLE.next   = csr_hwif_out.mcycle.MCYCLE.value + 32'd1;
    csr_hwif_in.mcycleh.MCYCLEH.we   = 1'b1;
    csr_hwif_in.mcycleh.MCYCLEH.next = csr_hwif_out.mcycleh.MCYCLEH.value +
                                        ((csr_hwif_out.mcycle.MCYCLE.value == 32'hFFFF_FFFF) ? 32'd1 : 32'd0);

    // minstret(h): increments once per issued uop (see i_instret_inc note
    // in rtl/csr/csr_regfile.rdl - approximates retire, not a true pulse).
    csr_hwif_in.minstret.MINSTRET.we      = issue_en;
    csr_hwif_in.minstret.MINSTRET.next    = csr_hwif_out.minstret.MINSTRET.value + 32'd1;
    csr_hwif_in.minstreth.MINSTRETH.we    = issue_en;
    csr_hwif_in.minstreth.MINSTRETH.next  = csr_hwif_out.minstreth.MINSTRETH.value +
                                             ((issue_en && (csr_hwif_out.minstret.MINSTRET.value == 32'hFFFF_FFFF)) ? 32'd1 : 32'd0);

    if (trap_taken) begin
      csr_hwif_in.mstatus.MPIE.we   = 1'b1;
      csr_hwif_in.mstatus.MPIE.next = csr_hwif_out.mstatus.MIE.value;
      csr_hwif_in.mstatus.MIE.we    = 1'b1;
      csr_hwif_in.mstatus.MIE.next  = 1'b0;
      csr_hwif_in.mepc.MEPC_HI.we   = 1'b1;
      csr_hwif_in.mepc.MEPC_HI.next = buf_pc_q[31:2];
      csr_hwif_in.mcause.MCAUSE.we  = 1'b1;
      csr_hwif_in.mcause.MCAUSE.next = trap_cause_code;
      csr_hwif_in.mtval.MTVAL.we    = 1'b1;
      csr_hwif_in.mtval.MTVAL.next  = trap_val;
    end else if (mret_taken) begin
      csr_hwif_in.mstatus.MIE.we    = 1'b1;
      csr_hwif_in.mstatus.MIE.next  = csr_hwif_out.mstatus.MPIE.value;
      csr_hwif_in.mstatus.MPIE.we   = 1'b1;
      csr_hwif_in.mstatus.MPIE.next = 1'b1;
    end
  end

  csr_regfile_gen CSR (
    .clk               (clk),
    .arst_n            (rst_n),
    .s_cpuif_req       (csr_we),
    .s_cpuif_req_is_wr (1'b1),          // read side bypasses the bus via hwif_out above
    .s_cpuif_addr      (csr_rdl_addr),
    .s_cpuif_wr_data   (csr_new_val),
    .s_cpuif_wr_biten  (32'hFFFF_FFFF),
    .s_cpuif_req_stall_wr (),
    .s_cpuif_req_stall_rd (),
    .s_cpuif_rd_ack    (),
    .s_cpuif_rd_err    (),
    .s_cpuif_rd_data   (),
    .s_cpuif_wr_ack    (),
    .s_cpuif_wr_err    (),
    .hwif_in           (csr_hwif_in),
    .hwif_out          (csr_hwif_out)
  );

  // Trap entry takes priority (mutually exclusive with mret/branch in practice —
  // a single buffered uop is never more than one of these).
  assign o_mispredict  = branch_mispredict_r || trap_taken || mret_taken;
  assign o_redirect_pc = trap_taken ? csr_trap_target :
                          mret_taken ? csr_mepc_out :
                          branch_mispredict_r ? branch_redirect_pc_r : 32'b0;

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
