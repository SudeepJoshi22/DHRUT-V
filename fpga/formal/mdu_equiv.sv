// Formal check of rtl/pipeline/mdu.sv against a reference model built from
// SystemVerilog's own * / % operators.
//
// WIDTH
// Proved at XLEN=8, not 32. A 33x33 multiplier is brutal for an SMT solver
// and a 32-iteration divide needs ~36 cycles of unrolling; together they do
// not finish. Both algorithms are uniform in XLEN -- the multiply is one
// expression and the divide is a loop whose body does not depend on the
// width -- so a proof at 8 bits covers the structure, the sign handling and
// every special case, all of which are width-parameterised.
//
// A 32-bit multiply-only variant was attempted and ABANDONED: z3 timed out
// at 800s and bitwuzla ran 9 hours without converging. Proving that a 33x33
// product's high half equals a 64x64 product's high half is multiplier
// equivalence across different operand widths, which is among the hardest
// things to ask an SMT solver. The 32-bit instance is covered instead by
// tests/asm/mul_div.S and the riscof M compliance suite, which is the
// authoritative gate for the real width.
//
// The reference relies on SV semantics that happen to match RISC-V exactly:
// signed / truncates toward zero, and signed % takes the sign of the
// dividend. The special cases (divide by zero, -2^(XLEN-1) / -1) are NOT
// left to the operators -- SV division by zero is x, and the overflow case
// is where a reference model would otherwise disagree with the spec -- so
// they are written out explicitly.
module mdu_equiv #(
  parameter int XLEN = 8,
  // 0 = every op, 1 = multiplies only, 2 = divides only.
  // The multiply is one register deep, so it can be proved at the real
  // XLEN=32 in a handful of cycles; the divide needs XLEN+4 cycles of
  // unrolling and is proved at a narrow width instead.
  parameter int OP_CLASS = 0
) (
  input logic            clk,
  input logic            rst_n,
  input logic [XLEN-1:0] a,
  input logic [XLEN-1:0] b,
  input logic [2:0]      f3
);

  // BMC starts from an ARBITRARY state, not a reset one. Without this the
  // solver happily begins mid-operation with a_q/b_q holding values the DUT
  // never saw and reports a counterexample that no real run can reach.
  // Pin the first cycle to reset, and hold reset de-asserted afterwards.
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

  // Signed divide/remainder must be computed in their OWN signed context.
  // Written inline in the ternaries below, the unsigned ALL_ONES / MIN_NEG
  // arms make the whole expression unsigned -- Verilog propagates
  // unsignedness across the operands -- and $signed(a)/$signed(b) silently
  // becomes an unsigned divide. That is a bug in the REFERENCE that reads
  // exactly like a bug in the DUT.
  //
  // safe_b keeps the divisor non-zero so these assigns never evaluate a
  // division by zero (x in simulation, and noise in a solver); the zero case
  // is selected away below regardless.
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
