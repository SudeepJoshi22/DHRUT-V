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

  logic [31:0] instr_q;
  logic [31:0] instr_pc_q;
  logic        instr_valid_q;

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
    end 
    else if(!i_stall && imem.s_ready) begin
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
  // Latch the Instruction when (valid && ready) are high
  // =================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || i_flush) begin
        instr_valid_q         <= 1'b0;
        instr_q               <= 32'd0;
        instr_pc_q            <= 32'd0;
    end
    else if (imem.m_valid && imem.s_ready) begin
        // Handshake completed → valid instruction fetched
        instr_valid_q         <= 1'b1;
        instr_q               <= imem.s_rdata;
        instr_pc_q            <= pc_q;
    end
  end

   // =================================================================
   // Output the latched instruction
   // =================================================================
   always_ff @(posedge clk or negedge rst_n) begin
     if (!rst_n) begin
       o_if_valid <= 1'b0;
       o_if_pc    <= 32'b0;
       o_if_instr <= 32'b0;
     end else begin
       if (i_flush) begin
         o_if_valid <= 1'b0;
         o_if_pc    <= 32'b0;
         o_if_instr <= 32'b0;
       end else if (instr_valid_q && !i_stall) begin
         // Output only when valid and not stalled (downstream ready)
         o_if_valid <= 1'b1;
         o_if_pc    <= instr_pc_q;
         o_if_instr <= instr_q;
       end else if (i_stall) begin
         // Hold output during stall
         // o_if_valid stays as-is (previous value)
       end else begin
         o_if_valid <= 1'b0;
       end
     end
   end

endmodule
