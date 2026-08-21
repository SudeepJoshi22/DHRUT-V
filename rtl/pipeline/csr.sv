// M-mode-only CSR register file + trap state.
//
// Scope (see M7 plan): RV32I + Zicsr, machine mode only — no S/U-mode, no
// PMP, no vectored/delegated interrupts. mtvec is always treated as direct
// mode regardless of its mode bits. Instantiated inside issue_stage, which
// resolves CSR reads/writes and trap/mret redirects combinationally in the
// same cycle a SYSTEM uop reaches the head of its issue buffer (the same
// place branches/jumps are already resolved).
module csr_regfile (
  input  logic        clk,
  input  logic        rst_n,

  // CSR instruction access (combinational read; registered write on i_csr_we)
  input  logic [11:0] i_csr_addr,
  input  logic [31:0] i_csr_wdata,
  input  logic        i_csr_we,
  output logic [31:0] o_csr_rdata,
  output logic        o_csr_invalid,   // 1 = i_csr_addr is not an implemented CSR

  // Trap entry (ecall / ebreak / illegal instruction)
  input  logic        i_trap_valid,
  input  logic [31:0] i_trap_cause,
  input  logic [31:0] i_trap_pc,
  input  logic [31:0] i_trap_val,
  output logic [31:0] o_trap_target,   // mtvec-based redirect target (direct mode)

  // mret
  input  logic        i_mret_valid,
  output logic [31:0] o_mepc,          // redirect target for mret

  // Instruction-retire pulse, for minstret
  input  logic        i_instret_inc
);

  // ─────────────────────────────────────────────
  // CSR addresses (M-mode subset)
  // ─────────────────────────────────────────────
  localparam logic [11:0] ADDR_MSTATUS   = 12'h300;
  localparam logic [11:0] ADDR_MISA      = 12'h301;
  localparam logic [11:0] ADDR_MIE       = 12'h304;
  localparam logic [11:0] ADDR_MTVEC     = 12'h305;
  localparam logic [11:0] ADDR_MSCRATCH  = 12'h340;
  localparam logic [11:0] ADDR_MEPC      = 12'h341;
  localparam logic [11:0] ADDR_MCAUSE    = 12'h342;
  localparam logic [11:0] ADDR_MTVAL     = 12'h343;
  localparam logic [11:0] ADDR_MIP       = 12'h344;
  localparam logic [11:0] ADDR_MCYCLE    = 12'hB00;
  localparam logic [11:0] ADDR_MINSTRET  = 12'hB02;
  localparam logic [11:0] ADDR_MCYCLEH   = 12'hB80;
  localparam logic [11:0] ADDR_MINSTRETH = 12'hB82;
  localparam logic [11:0] ADDR_MVENDORID = 12'hF11;
  localparam logic [11:0] ADDR_MARCHID   = 12'hF12;
  localparam logic [11:0] ADDR_MIMPID    = 12'hF13;
  localparam logic [11:0] ADDR_MHARTID   = 12'hF14;

  // ─────────────────────────────────────────────
  // State
  // ─────────────────────────────────────────────
  logic        mstatus_mie_q, mstatus_mpie_q;
  logic        mie_msie_q, mie_mtie_q, mie_meie_q;
  logic [31:0] mtvec_q;
  logic [31:0] mscratch_q;
  logic [31:0] mepc_q;
  logic [31:0] mcause_q;
  logic [31:0] mtval_q;
  logic [63:0] mcycle_q;
  logic [63:0] minstret_q;

  localparam logic [31:0] MISA_VAL = 32'h4000_0100;  // MXL=RV32, extension bit 'I' only

  // ─────────────────────────────────────────────
  // Combinational read + address-valid decode
  // ─────────────────────────────────────────────
  always_comb begin
    o_csr_invalid = 1'b0;
    unique case (i_csr_addr)
      ADDR_MSTATUS:   o_csr_rdata = {19'b0, 2'b11, 3'b0, mstatus_mpie_q, 3'b0, mstatus_mie_q, 3'b0};
      ADDR_MISA:      o_csr_rdata = MISA_VAL;
      ADDR_MIE:       o_csr_rdata = {20'b0, mie_meie_q, 3'b0, mie_mtie_q, 3'b0, mie_msie_q, 3'b0};
      ADDR_MTVEC:     o_csr_rdata = mtvec_q;
      ADDR_MSCRATCH:  o_csr_rdata = mscratch_q;
      ADDR_MEPC:      o_csr_rdata = mepc_q;
      ADDR_MCAUSE:    o_csr_rdata = mcause_q;
      ADDR_MTVAL:     o_csr_rdata = mtval_q;
      ADDR_MIP:       o_csr_rdata = 32'b0;  // no interrupt sources wired yet (CLINT/PLIC: future M9 work)
      ADDR_MCYCLE:    o_csr_rdata = mcycle_q[31:0];
      ADDR_MCYCLEH:   o_csr_rdata = mcycle_q[63:32];
      ADDR_MINSTRET:  o_csr_rdata = minstret_q[31:0];
      ADDR_MINSTRETH: o_csr_rdata = minstret_q[63:32];
      ADDR_MVENDORID: o_csr_rdata = 32'b0;
      ADDR_MARCHID:   o_csr_rdata = 32'b0;
      ADDR_MIMPID:    o_csr_rdata = 32'b0;
      ADDR_MHARTID:   o_csr_rdata = 32'b0;
      default: begin
        o_csr_rdata   = 32'b0;
        o_csr_invalid = 1'b1;
      end
    endcase
  end

  // ─────────────────────────────────────────────
  // Trap-entry / mret redirect targets (combinational)
  // ─────────────────────────────────────────────
  assign o_trap_target = {mtvec_q[31:2], 2'b00};  // direct mode only
  assign o_mepc         = mepc_q;

  // ─────────────────────────────────────────────
  // Writes: CSR instruction write < mret < trap entry (trap entry always wins;
  // in practice these never coincide since Issue resolves exactly one SYSTEM
  // uop per cycle).
  // ─────────────────────────────────────────────
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mstatus_mie_q  <= 1'b0;
      mstatus_mpie_q <= 1'b0;
      mie_msie_q     <= 1'b0;
      mie_mtie_q     <= 1'b0;
      mie_meie_q     <= 1'b0;
      mtvec_q        <= 32'b0;
      mscratch_q     <= 32'b0;
      mepc_q         <= 32'b0;
      mcause_q       <= 32'b0;
      mtval_q        <= 32'b0;
      mcycle_q       <= 64'b0;
      minstret_q     <= 64'b0;
    end else begin
      mcycle_q <= mcycle_q + 64'd1;
      if (i_instret_inc) minstret_q <= minstret_q + 64'd1;

      if (i_trap_valid) begin
        mepc_q         <= i_trap_pc;
        mcause_q       <= i_trap_cause;
        mtval_q        <= i_trap_val;
        mstatus_mpie_q <= mstatus_mie_q;
        mstatus_mie_q  <= 1'b0;
      end else if (i_mret_valid) begin
        mstatus_mie_q  <= mstatus_mpie_q;
        mstatus_mpie_q <= 1'b1;
      end else if (i_csr_we) begin
        unique case (i_csr_addr)
          ADDR_MSTATUS: begin
            mstatus_mie_q  <= i_csr_wdata[3];
            mstatus_mpie_q <= i_csr_wdata[7];
          end
          ADDR_MIE: begin
            mie_msie_q <= i_csr_wdata[3];
            mie_mtie_q <= i_csr_wdata[7];
            mie_meie_q <= i_csr_wdata[11];
          end
          ADDR_MTVEC:     mtvec_q    <= i_csr_wdata;
          ADDR_MSCRATCH:  mscratch_q <= i_csr_wdata;
          ADDR_MEPC:      mepc_q     <= {i_csr_wdata[31:2], 2'b00};  // IALIGN=32
          ADDR_MCAUSE:    mcause_q   <= i_csr_wdata;
          ADDR_MTVAL:     mtval_q    <= i_csr_wdata;
          ADDR_MCYCLE:    mcycle_q[31:0]    <= i_csr_wdata;
          ADDR_MCYCLEH:   mcycle_q[63:32]   <= i_csr_wdata;
          ADDR_MINSTRET:  minstret_q[31:0]  <= i_csr_wdata;
          ADDR_MINSTRETH: minstret_q[63:32] <= i_csr_wdata;
          // MISA / MVENDORID / MARCHID / MIMPID / MHARTID: read-only, writes ignored.
          default: ;
        endcase
      end
    end
  end

endmodule
