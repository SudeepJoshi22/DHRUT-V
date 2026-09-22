import riscv_uop_pkg::*;

module lsu (
  input  logic        clk,
  input  logic        rst_n,

  // From ISSUE
  lsu_issue_if.lsu    issue_if,

  // To data memory
  mem_if.master       dmem_if,

  // Forward only completed loads. Store instruction bits in the rd field
  // are not a register destination.
  output logic        o_lsu_fwd_valid,
  output logic [4:0]  o_lsu_fwd_rd,
  output logic [31:0] o_lsu_fwd_result,

  // Back to pipeline (for write-back or next stage)
  output logic        o_valid,          // load/store completed this cycle
  output logic [31:0] o_load_data,      // sign/zero-extended load result
  output uop_t        o_lsu_uop
);

  // ───────────────────────────────────────────────
  // Input Pipeline Registers (from ISSUE)
  // ───────────────────────────────────────────────
  logic        valid_q;
  uop_t        uop_q;
  logic [31:0] pc_q;
  logic [31:0] addr_base_q;
  logic [31:0] store_data_q;


  logic        internal_stall;

  always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
          valid_q       <= 1'b0;
          uop_q         <= '0;
          pc_q          <= '0;
          addr_base_q   <= '0;
          store_data_q  <= '0;
      end
      else if (!internal_stall && !valid_q && issue_if.m_valid) begin
          // Idle → normal new request
          valid_q       <= 1'b1;
          uop_q         <= issue_if.m_uop;
          pc_q          <= issue_if.m_pc;
          addr_base_q   <= issue_if.m_addr_base;
          store_data_q  <= issue_if.m_store_data;
      end
      else if (valid_q && dmem_if.s_ready) begin
          // Transaction completes → consume old, opportunistically accept new
          if (issue_if.m_valid) begin
              // Zero-bubble: latch new
              valid_q       <= 1'b1;
              uop_q         <= issue_if.m_uop;
              pc_q          <= issue_if.m_pc;
              addr_base_q   <= issue_if.m_addr_base;
              store_data_q  <= issue_if.m_store_data;
          end else begin
              // No new → go idle AND clear data
              valid_q       <= 1'b0;
              uop_q         <= '0;
              pc_q          <= '0;
              addr_base_q   <= '0;
              store_data_q  <= '0;
          end
      end
  end

  // ───────────────────────────────────────────────
  // Final memory address = base + offset (computed here)
  // ───────────────────────────────────────────────
  logic [31:0] mem_addr;

  assign mem_addr = addr_base_q + uop_q.imm;

  // ───────────────────────────────────────────────
  // Write data alignment & byte strobes (for stores)
  // ───────────────────────────────────────────────
  logic [31:0] wdata_aligned;
  logic [3:0]  wstrb;

  // Mask store data to access width, then shift data and strobes by byte offset.
  // Misaligned halfword stores have zero strobes.
  logic [1:0]  byte_off;
  logic [31:0] store_masked;
  logic [3:0]  strb_base;
  logic        h_aligned;

  assign byte_off  = mem_addr[1:0];
  assign h_aligned = (byte_off[0] == 1'b0);   // halfword needs even offset

  always_comb begin
    unique case (uop_q.lsu_access_size)
      2'b00:   store_masked = {24'b0, store_data_q[7:0]};
      2'b01:   store_masked = {16'b0, store_data_q[15:0]};
      default: store_masked = store_data_q;
    endcase
  end

  always_comb begin
    unique case (uop_q.lsu_access_size)
      2'b00:   strb_base = 4'b0001;
      2'b01:   strb_base = h_aligned ? 4'b0011 : 4'b0000;
      2'b10:   strb_base = 4'b1111;
      default: strb_base = 4'b0000;
    endcase
  end

  // Word accesses use a zero shift offset.
  logic [1:0] shift_off;
  assign shift_off = (uop_q.lsu_access_size == 2'b10) ? 2'b00 : byte_off;

  assign wdata_aligned = uop_q.is_store ? (store_masked << {shift_off, 3'b000})
                                        : store_data_q;
  assign wstrb         = uop_q.is_store ? (strb_base   <<  shift_off)
                                        : 4'b0000;

  // ───────────────────────────────────────────────
  // Drive memory interface
  // ───────────────────────────────────────────────
  assign dmem_if.m_valid  = valid_q && (uop_q.is_load || uop_q.is_store);
  assign dmem_if.m_addr   = mem_addr;
  assign dmem_if.m_wdata  = wdata_aligned;
  assign dmem_if.m_wstrb  = wstrb;
  // Data requests remain valid until the slave responds; m_flush is tied low.
  assign dmem_if.m_flush  = 1'b0;

  // ───────────────────────────────────────────────
  // Stall back to ISSUE
  // ───────────────────────────────────────────────
  assign internal_stall            = dmem_if.m_valid && !dmem_if.s_ready;
  assign issue_if.s_stall_from_lsu = internal_stall;

  // ───────────────────────────────────────────────
  // Transaction complete signal
  // ───────────────────────────────────────────────
  assign o_valid = valid_q && dmem_if.s_ready;

  // Align load bytes with one right shift, then apply sign or zero extension.
  // Misaligned halfword loads return zero.
  logic [31:0] load_shifted;
  logic        sx;

  assign load_shifted = dmem_if.s_rdata >> {byte_off, 3'b000};
  assign sx           = uop_q.lsu_sign_extend;

  always_comb begin
    // Default load value when no extension case applies.
    o_load_data = dmem_if.s_rdata;

    if (uop_q.is_load && o_valid) begin
      unique case (uop_q.lsu_access_size)
        2'b00:   o_load_data = {{24{sx & load_shifted[7]}},  load_shifted[7:0]};
        2'b01:   o_load_data = h_aligned
                               ? {{16{sx & load_shifted[15]}}, load_shifted[15:0]}
                               : 32'b0;
        2'b10:   o_load_data = dmem_if.s_rdata;
        default: o_load_data = 32'b0;
      endcase
    end
  end

  assign o_lsu_uop = uop_q;

  // ───────────────────────────────────────────────
  // Dedicated load-data forward to Issue (loads only - see port comment)
  // ───────────────────────────────────────────────
  assign o_lsu_fwd_valid  = o_valid && uop_q.is_load;
  assign o_lsu_fwd_rd     = uop_q.rd;
  assign o_lsu_fwd_result = o_load_data;

endmodule
