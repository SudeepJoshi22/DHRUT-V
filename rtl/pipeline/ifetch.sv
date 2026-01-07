module if_stage (
  input  logic        clk,
  input  logic        rst_n,

  input  logic        stall,
  input  logic        flush,
  input  logic [31:0] redirect_pc,

  mem_if.master       imem,

  output logic        if_valid,
  output logic [31:0] if_pc,
  output logic [31:0] if_instr
);

  logic [31:0] pc_q, pc_d;
  logic        waiting;

  // PC update logic
  always_comb begin
    pc_d = pc_q;

    if (flush) begin
      pc_d = redirect_pc;
    end else if (!stall && !waiting) begin
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
  assign imem.valid = !waiting;
  assign imem.addr  = pc_q;
  assign imem.wdata = '0;
  assign imem.wstrb = 4'b0000;

  // Waiting for memory
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      waiting  <= 1'b0;
      if_valid <= 1'b0;
    end else begin
      if (imem.valid && !imem.ready) begin
        waiting <= 1'b1;
      end else begin
        waiting <= 1'b0;
      end

      if (imem.ready && !stall) begin
        if_valid <= 1'b1;
        if_pc    <= pc_q;
        if_instr <= imem.rdata;
      end else if (flush) begin
        if_valid <= 1'b0;
      end
    end
  end

endmodule

