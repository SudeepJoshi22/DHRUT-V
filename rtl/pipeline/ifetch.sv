module if_stage (
  input  logic        clk,
  input  logic        rst_n,

  input  logic        i_stall,
  input  logic        i_flush,
  input  logic [31:0] i_redirect_pc,

  mem_if.master       imem,

  output logic        o_if_valid,
  output logic [31:0] o_if_pc,
  output logic [31:0] o_if_instr
);

  logic [31:0] pc_q, pc_d;
  logic        waiting;

  // PC update logic
  always_comb begin
    pc_d = pc_q;

    if (i_flush) begin
      pc_d = i_redirect_pc;
    end else if (!i_stall && !waiting) begin
      pc_d = pc_q + 32'd4;
    end
  end

  // PC register
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc_q <= 32'h0000_0000;
    end else begin
      pc_q <= pc_d;
    end
  end

  // Memory request
  assign imem.m_valid = !waiting;
  assign imem.m_addr  = pc_q;
  assign imem.m_wdata = '0;
  assign imem.m_wstrb = 4'b0000;

  // Waiting for memory
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      waiting  <= 1'b0;
      o_if_valid <= 1'b0;
    end else begin
      if (imem.m_valid && !imem.s_ready) begin
        waiting <= 1'b1;
      end else begin
        waiting <= 1'b0;
      end

      if (imem.s_ready && !i_stall) begin
        o_if_valid <= 1'b1;
        o_if_pc    <= pc_q;
        o_if_instr <= imem.s_rdata;
      end else if (i_flush) begin
        o_if_valid <= 1'b0;
      end
    end
  end

endmodule

