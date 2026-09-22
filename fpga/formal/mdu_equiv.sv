// MDU equivalence harness using arithmetic operators as the reference.
// The supplied proof uses XLEN=8; it does not prove the 32-bit instance.
// Divide-by-zero and signed-overflow results are specified explicitly.
module mdu_equiv #(
  parameter int XLEN = 8,
  // Operation filter: 0=all, 1=multiply, 2=divide.
  parameter int OP_CLASS = 0
) (
  input logic            clk,
  input logic            rst_n,
  input logic [XLEN-1:0] a,
  input logic [XLEN-1:0] b,
  input logic [2:0]      f3
);

  // Constrain the first cycle to reset and release reset thereafter.
  logic first_q = 1'b1;
  always_ff @(posedge clk) first_q <= 1'b0;
  always_comb begin
    if (first_q) assume (!rst_n);
    else         assume (rst_n);
  end

  always_comb begin
    if (OP_CLASS == 1) assume (!f3[2]);   // MUL/MULH/MULHSU/MULHU
    if (OP_CLASS == 2) assume ( f3[2]);   // DIV/DIVU/REM/REMU
  end

  logic            dut_ready, dut_valid;
  logic [XLEN-1:0] dut_result;

  logic            started_q;
  logic [XLEN-1:0] a_q, b_q;
  logic [2:0]      f3_q;

  // One operation, launched as soon as the DUT is idle. Inputs are latched
  // on the accepting cycle so the reference sees exactly what the DUT did.
  mdu #(.XLEN(XLEN)) DUT (
    .clk      (clk),
    .rst_n    (rst_n),
    .i_flush  (1'b0),
    .i_valid  (!started_q),
    .i_funct3 (f3),
    .i_op1    (a),
    .i_op2    (b),
    .o_ready  (dut_ready),
    .o_valid  (dut_valid),
    .o_result (dut_result)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      started_q <= 1'b0;
      a_q       <= '0;
      b_q       <= '0;
      f3_q      <= '0;
    end
    else if (!started_q && dut_ready) begin
      started_q <= 1'b1;
      a_q       <= a;
      b_q       <= b;
      f3_q      <= f3;
    end
  end

  // ── Reference ────────────────────────────────────────────────────
  localparam logic [XLEN-1:0] MIN_NEG  = {1'b1, {(XLEN-1){1'b0}}};
  localparam logic [XLEN-1:0] ALL_ONES = {XLEN{1'b1}};

  logic signed [2*XLEN-1:0] p_ss, p_su;
  logic        [2*XLEN-1:0] p_uu;
  assign p_ss = $signed({{XLEN{a_q[XLEN-1]}}, a_q}) * $signed({{XLEN{b_q[XLEN-1]}}, b_q});
  assign p_su = $signed({{XLEN{a_q[XLEN-1]}}, a_q}) * $signed({{XLEN{1'b0}},        b_q});
  assign p_uu =        {{XLEN{1'b0}},        a_q}  *        {{XLEN{1'b0}},        b_q};

  logic div_zero, div_ovf;
  assign div_zero = (b_q == '0);
  assign div_ovf  = (a_q == MIN_NEG) && (b_q == ALL_ONES);

  // Evaluate signed division in a signed context before selecting unsigned results.
  // safe_b avoids evaluating division by zero.
  logic signed [XLEN-1:0] safe_b, sdiv_res, srem_res;
  assign safe_b   = signed'(div_zero ? {{(XLEN-1){1'b0}}, 1'b1} : b_q);
  assign sdiv_res = signed'(a_q) / safe_b;
  assign srem_res = signed'(a_q) % safe_b;

  logic [XLEN-1:0] udiv_res, urem_res;
  assign udiv_res = a_q / (div_zero ? {{(XLEN-1){1'b0}}, 1'b1} : b_q);
  assign urem_res = a_q % (div_zero ? {{(XLEN-1){1'b0}}, 1'b1} : b_q);

  logic [XLEN-1:0] ref_result;
  always_comb begin
    unique case (f3_q)
      3'b000: ref_result = p_ss[XLEN-1:0];            // MUL  (low half is interpretation-free)
      3'b001: ref_result = p_ss[2*XLEN-1:XLEN];       // MULH
      3'b010: ref_result = p_su[2*XLEN-1:XLEN];       // MULHSU
      3'b011: ref_result = p_uu[2*XLEN-1:XLEN];       // MULHU

      3'b100: ref_result = div_zero ? ALL_ONES        // DIV
                         : div_ovf  ? MIN_NEG
                         : sdiv_res;
      3'b101: ref_result = div_zero ? ALL_ONES        // DIVU
                         : udiv_res;
      3'b110: ref_result = div_zero ? a_q             // REM
                         : div_ovf  ? '0
                         : srem_res;
      3'b111: ref_result = div_zero ? a_q             // REMU
                         : urem_res;
      default: ref_result = '0;
    endcase
  end

  // ── The property ─────────────────────────────────────────────────
  always_comb begin
    if (rst_n && started_q && dut_valid)
      assert (dut_result == ref_result);
  end

endmodule
