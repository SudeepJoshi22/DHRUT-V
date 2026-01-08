module if_stage (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        i_stall,
  input  logic        i_flush,
  input  logic [31:0] i_redirect_pc,

  mem_if.master       imem,               // master modport

  output logic        o_if_valid,
  output logic [31:0] o_if_pc,
  output logic [31:0] o_if_instr
);

  logic [31:0] pc_q, pc_next;
  logic        fetch_valid;   // internal signal: we want to fetch this cycle

  // =================================================================
  // PC Logic
  // =================================================================
  always_comb begin
    pc_next = pc_q;

    if (i_flush) begin
      pc_next = i_redirect_pc;
    end else if (!i_stall && imem.s_ready) begin
      // Advance only when transaction completes (handshake) and not stalled
      pc_next = pc_q + 32'd4;
    end
    // else hold current PC
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc_q <= 32'h0000_0000;
    end else begin
      pc_q <= pc_next;
    end
  end

  // =================================================================
  // Fetch Request Control (Standard Valid-Ready)
  // =================================================================
  // We assert m_valid whenever:
  // - We are not stalled
  // - There is no flush (flush kills pending request)
  // - And we always want the next instruction unless stalled
  always_comb begin
    fetch_valid = !i_stall && !i_flush;
  end

  assign imem.m_valid = fetch_valid;
  assign imem.m_addr  = pc_q;
  assign imem.m_wdata = '0;
  assign imem.m_wstrb = 4'b0000;

  // =================================================================
  // Output Valid & Data Capture
  // =================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      o_if_valid <= 1'b0;
      o_if_pc    <= 32'b0;
      o_if_instr <= 32'b0;
    end else begin
      if (i_flush) begin
        o_if_valid <= 1'b0;  // kill output on flush
      end else if (imem.m_valid && imem.s_ready) begin
        // Handshake completed → valid instruction fetched
        o_if_valid <= 1'b1;
        o_if_pc    <= pc_q;            // PC of the fetched instruction
        o_if_instr <= imem.s_rdata;
      end else begin
        o_if_valid <= 1'b0;  // no completion this cycle
      end
    end
  end

endmodule
