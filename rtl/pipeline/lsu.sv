module lsu (
  input  logic        clk,
  input  logic        rst_n,

  // From ISSUE
  lsu_issue_if.lsu    issue_if,

  // To data memory
  mem_if.master       dmem_if,

  // Load Data Forward to ISSUE
  //output logic [4:0]  o_lsu_fwd_rd,           
  //output logic [31:0] o_lsu_fwd_result,       

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
  logic [31:0] addr_base_q;
  logic [31:0] store_data_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_q       <= 1'b0;
      uop_q         <= '0;
      addr_base_q   <= '0;
      store_data_q  <= '0;
    end
    else begin
      valid_q       <= issue_if.m_valid;
      uop_q         <= issue_if.m_uop;
      addr_base_q   <= issue_if.m_addr_base;
      store_data_q  <= issue_if.m_store_data;
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

  always_comb begin
    wstrb         = 4'b0000;
    wdata_aligned = store_data_q;

    if (uop_q.is_store) begin
      case (uop_q.lsu_access_size)
        2'b00: begin  // byte
          case (mem_addr[1:0])
            2'b00: wstrb = 4'b0001;
            2'b01: wstrb = 4'b0010;
            2'b10: wstrb = 4'b0100;
            2'b11: wstrb = 4'b1000;
          endcase
        end

        2'b01: begin  // halfword
          case (mem_addr[1:0])
            2'b00: wstrb = 4'b0011;
            2'b10: wstrb = 4'b1100;
            default: wstrb = 4'b0000; // misaligned → ignore or trap later
          endcase
        end

        2'b10: begin  // word
          wstrb = 4'b1111;
        end
        default: wstrb = 4'b0000;
      endcase
    end
  end

  // ───────────────────────────────────────────────
  // Drive memory interface
  // ───────────────────────────────────────────────
  assign dmem_if.m_valid  = valid_q && (uop_q.is_load || uop_q.is_store);
  assign dmem_if.m_addr   = mem_addr;
  assign dmem_if.m_wdata  = wdata_aligned;
  assign dmem_if.m_wstrb  = wstrb;

  // ───────────────────────────────────────────────
  // Stall back to ISSUE (stall when memory not ready)
  // ───────────────────────────────────────────────
  assign issue_if.s_stall_from_lsu = dmem_if.m_valid && !dmem_if.s_ready;

  // ───────────────────────────────────────────────
  // Transaction complete signal
  // ───────────────────────────────────────────────
  assign o_valid = valid_q && dmem_if.s_ready;

  // ───────────────────────────────────────────────
  // Load data handling (sign/zero extension)
  // ───────────────────────────────────────────────
  always_comb begin
    o_load_data = dmem_if.s_rdata;

    if (uop_q.is_load && o_valid) begin
      case (uop_q.lsu_access_size)
        2'b00: begin  // byte
          case (mem_addr[1:0])
            2'b00: o_load_data = {{24{uop_q.lsu_sign_extend & dmem_if.s_rdata[7]}},   dmem_if.s_rdata[7:0]};
            2'b01: o_load_data = {{24{uop_q.lsu_sign_extend & dmem_if.s_rdata[15]}},  dmem_if.s_rdata[15:8]};
            2'b10: o_load_data = {{24{uop_q.lsu_sign_extend & dmem_if.s_rdata[23]}},  dmem_if.s_rdata[23:16]};
            2'b11: o_load_data = {{24{uop_q.lsu_sign_extend & dmem_if.s_rdata[31]}},  dmem_if.s_rdata[31:24]};
          endcase
        end

        2'b01: begin  // halfword
          case (mem_addr[1:0])
            2'b00: o_load_data = {{16{uop_q.lsu_sign_extend & dmem_if.s_rdata[15]}},  dmem_if.s_rdata[15:0]};
            2'b10: o_load_data = {{16{uop_q.lsu_sign_extend & dmem_if.s_rdata[31]}},  dmem_if.s_rdata[31:16]};
            default: o_load_data = 32'b0;  // misaligned
          endcase
        end

        2'b10: begin  // word
          o_load_data = dmem_if.s_rdata;
        end

        default: o_load_data = 32'b0;
      endcase
    end
  end

  // Forward latched uop to next stage
  assign o_lsu_uop = uop_q;

endmodule
