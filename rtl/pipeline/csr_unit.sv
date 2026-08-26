import riscv_uop_pkg::*;
import csr_regfile_gen_pkg::*;

// CSR + trap/mret resolution, split out of Issue so Issue stays a pure
// issuer (register read, forwarding, dispatch). Unlike ALU/LSU (dispatched
// through a pipelined interface, resolved a cycle later), this unit
// resolves combinationally in the SAME cycle Issue holds a SYSTEM uop -
// same timing as branch/jump resolution, just factored into its own module
// instead of living inline in issue.sv. Wraps the PeakRDL-generated
// csr_regfile_gen (rtl/csr/generated/) - see rtl/csr/README.md for the
// CSR#/offset addressing scheme and the --cpuif passthrough rationale.
module csr_unit (
  input  logic        clk,
  input  logic        rst_n,

  input  logic        i_valid,      // resolve this cycle (Issue's issue_en0)
  // How many uops issued this cycle (0..2). minstret advances by this, not
  // by 1: a 2-wide machine issues two instructions in one cycle and a
  // hardcoded +1 would under-count every paired bundle.
  input  logic [1:0]  i_instret_cnt,
  input  uop_t         i_uop,        // buffered uop from Issue (opcode/funct3/imm/rs1/is_illegal/instr_bits)
  input  logic [31:0] i_pc,          // PC of i_uop
  input  logic [31:0] i_rs1_data,    // forwarded rs1 value

  // To Issue's ALU dispatch mux: when valid, route this uop to the ALU as
  // an op1-passthrough (op1=o_rdata, op2=0) so the old CSR value reaches
  // Retire/write-back via the existing ALU path.
  output logic        o_dispatch_valid,
  output logic [31:0] o_rdata,

  // To Issue's mispredict/redirect bus (same signal Issue already uses for
  // branch mispredicts): trap entry or mret firing this cycle.
  output logic        o_redirect_valid,
  output logic [31:0] o_redirect_pc
);

  // ───────────────────────────────────────────────
  // Decode: CSR form vs. privileged form vs. illegal
  // ───────────────────────────────────────────────
  logic        is_system, is_csr_form, is_priv_form;
  logic [11:0] sys_imm12;
  logic        is_ecall, is_ebreak, is_mret;
  logic        overall_illegal;

  assign is_system    = (i_uop.opcode == OPCODE_SYSTEM);
  assign is_csr_form  = is_system && (i_uop.funct3 != 3'b000);
  assign is_priv_form = is_system && (i_uop.funct3 == 3'b000);
  assign sys_imm12    = i_uop.imm[11:0];
  assign is_ecall     = is_priv_form && !i_uop.is_illegal && (sys_imm12 == 12'h000);
  assign is_ebreak    = is_priv_form && !i_uop.is_illegal && (sys_imm12 == 12'h001);
  assign is_mret      = is_priv_form && !i_uop.is_illegal && (sys_imm12 == 12'h302);

  // ───────────────────────────────────────────────
  // CSR read (combinational, from the generated block's live field state
  // via hwif_out — bypasses the cpuif bus entirely so read-then-modify-
  // then-write still resolves in one cycle) / write value mux
  // ───────────────────────────────────────────────
  logic [31:0] csr_rdata_now;
  logic        csr_addr_invalid;
  logic [31:0] csr_write_src;
  logic [1:0]  csr_op_kind;      // funct3[1:0]: 01=RW, 10=RS, 11=RC
  logic [31:0] csr_new_val;
  logic        csr_we;
  logic [6:0]  csr_rdl_addr;     // RISC-V CSR# -> rtl/csr/csr_regfile.rdl offset (see rtl/csr/README.md)

  csr_regfile_gen_pkg::csr_regfile__in_t  csr_hwif_in;
  csr_regfile_gen_pkg::csr_regfile__out_t csr_hwif_out;

  assign csr_write_src = i_uop.uses_rs1 ? i_rs1_data : {27'b0, i_uop.rs1};
  assign csr_op_kind   = i_uop.funct3[1:0];

  // CSR#/offset table mirrors rtl/csr/csr_regfile.rdl's addrmap exactly -
  // keep both in sync if the .rdl's offsets ever change.
  always_comb begin
    csr_addr_invalid = 1'b0;
    csr_rdl_addr      = 7'h00;
    unique case (i_uop.imm[11:0])
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
    unique case (i_uop.imm[11:0])
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

  assign overall_illegal = i_uop.is_illegal || (is_csr_form && csr_addr_invalid);
  // CSRRW(I) always writes; CSRRS/C(I) only write when the source is non-zero
  // (register rs1 != x0, or a non-zero uimm — both share the rs1 encoding field).
  assign csr_we = i_valid && is_csr_form && !csr_addr_invalid &&
                  ((csr_op_kind == 2'b01) || (i_uop.rs1 != 5'd0));

  assign o_dispatch_valid = is_csr_form && !csr_addr_invalid;
  assign o_rdata           = csr_rdata_now;

  // ───────────────────────────────────────────────
  // Trap detection: illegal instruction / ecall / ebreak (mret is a
  // redirect, not a trap)
  // ───────────────────────────────────────────────
  logic        trap_taken;
  logic [31:0] trap_cause_code;
  logic [31:0] trap_val;

  always_comb begin
    trap_taken      = 1'b0;
    trap_cause_code = 32'b0;
    trap_val        = 32'b0;

    if (i_valid) begin
      if (overall_illegal) begin
        trap_taken      = 1'b1;
        trap_cause_code = 32'd2;   // Illegal instruction
        trap_val        = i_uop.instr_bits;  // matches Spike's convention
      end else if (is_ecall) begin
        trap_taken      = 1'b1;
        trap_cause_code = 32'd11;  // Environment call from M-mode
      end else if (is_ebreak) begin
        trap_taken      = 1'b1;
        trap_cause_code = 32'd3;   // Breakpoint
        trap_val        = i_pc;
      end
    end
  end

  logic mret_taken;
  assign mret_taken = i_valid && is_mret;

  // mtvec is direct-mode only (see rtl/csr/csr_regfile.rdl); mepc's low 2
  // bits are a hardwired-0 field (RESERVED_LOW), so MEPC_HI is already the
  // full address with the low 2 bits implicitly zero.
  logic [31:0] csr_trap_target;
  logic [31:0] csr_mepc_out;
  assign csr_trap_target = {csr_hwif_out.mtvec.MTVEC.value[31:2], 2'b00};
  assign csr_mepc_out    = {csr_hwif_out.mepc.MEPC_HI.value, 2'b00};

  assign o_redirect_valid = trap_taken || mret_taken;
  assign o_redirect_pc    = trap_taken ? csr_trap_target :
                             mret_taken ? csr_mepc_out : 32'b0;

  // ───────────────────────────────────────────────
  // Hardware-side (trap entry / mret / counters) writes into the generated
  // block's per-field next/we ports. Priority vs. a same-cycle SW write is
  // SW-checked-first in PeakRDL's generated logic (see rtl/csr/README.md) -
  // currently moot since Issue resolves one uop/cycle, so a CSR write and a
  // trap/mret/counter-tick on the same field can't coincide except for the
  // counters, where SW winning that one cycle is the desired behavior.
  // ───────────────────────────────────────────────
  // 33-bit so the carry out of minstret is a real bit rather than an
  // equality test against 0xFFFF_FFFF - see the minstret block below.
  logic [32:0] minstret_sum;
  assign minstret_sum = {1'b0, csr_hwif_out.minstret.MINSTRET.value} +
                        {31'b0, i_instret_cnt};

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

    // minstret(h): advances by the number of uops issued this cycle (see
    // i_instret_inc note in rtl/csr/csr_regfile.rdl - approximates retire,
    // not a true pulse). The carry into minstreth comes from a real 33-bit
    // sum rather than an equality test: at 2-wide the counter can step
    // straight OVER the wrap value (0xFFFF_FFFF + 2), and testing for an
    // exact match would miss it and lose 2^32 counts.
    csr_hwif_in.minstret.MINSTRET.we      = (i_instret_cnt != 2'd0);
    csr_hwif_in.minstret.MINSTRET.next    = minstret_sum[31:0];
    csr_hwif_in.minstreth.MINSTRETH.we    = (i_instret_cnt != 2'd0);
    csr_hwif_in.minstreth.MINSTRETH.next  = csr_hwif_out.minstreth.MINSTRETH.value +
                                             (minstret_sum[32] ? 32'd1 : 32'd0);

    if (trap_taken) begin
      csr_hwif_in.mstatus.MPIE.we   = 1'b1;
      csr_hwif_in.mstatus.MPIE.next = csr_hwif_out.mstatus.MIE.value;
      csr_hwif_in.mstatus.MIE.we    = 1'b1;
      csr_hwif_in.mstatus.MIE.next  = 1'b0;
      csr_hwif_in.mepc.MEPC_HI.we   = 1'b1;
      csr_hwif_in.mepc.MEPC_HI.next = i_pc[31:2];
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

endmodule
