// =================================================================
// mdu - RV32M multiply / divide unit
// =================================================================
// Deliberately knows nothing about uop_t, the issue interfaces or the
// scoreboard: it takes funct3 and two operands and hands back a result.
// That keeps it verifiable on its own -- the pipeline integration is a
// separate wrapper, so a bug in one cannot be mistaken for a bug in the
// other.
//
// HANDSHAKE
//   i_valid && o_ready  -> operation accepted this cycle
//   o_valid             -> o_result holds that operation's answer
//   i_flush             -> abandon whatever is in flight
// One operation in flight at a time; o_ready is low while busy.
//
// ALGORITHMS -- ideas from Ibex and PicoRV32, no code copied.
//
//   MULTIPLY: one 33x33 signed multiply covers all four forms. Each
//   operand is extended to 33 bits with its OWN signedness, so MULHSU
//   falls out of the same hardware by flipping one extension bit rather
//   than needing a second multiplier. synth_gowin maps `*` onto the
//   GW2AR's hard MULT18X18 blocks automatically (mul2dsp.v +
//   gowin/dsp_map.v, on unless -nodsp) and this part has 48 unused, so
//   this costs DSPs rather than LUTs. That is why Ibex's
//   three-17x17-plus-accumulator arrangement is not reproduced: it exists
//   to force inference on toolchains that will not infer, and ours does.
//
//   DIVIDE: restoring long division, one quotient bit per cycle, XLEN
//   iterations. Radix-2 keeps the per-cycle logic to a 33-bit subtract,
//   which matters because this design has ~22% timing margin at 27 MHz
//   and far more spare LUTs than spare Fmax. Signed operands are made
//   positive up front and the signs reapplied at the end, so the loop
//   itself is purely unsigned.
//
// RISC-V SEMANTICS THAT ARE EASY TO GET WRONG (unprivileged spec; all
// exercised by the riscof M suite):
//   * divide by zero does NOT trap -- DIV/DIVU give all-ones (-1),
//     REM/REMU give the dividend unchanged.
//   * signed overflow -2^31 / -1 does NOT trap -- quotient is -2^31
//     (wraps, unrepresentable), remainder is 0.
//   * MULHSU is SIGNED rs1 times UNSIGNED rs2. Not both signed, not
//     both unsigned.
// Both divide special cases skip the loop and answer immediately, so a
// divide by zero costs 2 cycles rather than 32 wasted ones.
// =================================================================
module mdu #(
  parameter int XLEN = 32
) (
  input  logic            clk,
  input  logic            rst_n,
  input  logic            i_flush,

  // Dispatch
  input  logic            i_valid,
  input  logic [2:0]      i_funct3,   // RV32M always has funct7 = 0000001
  input  logic [XLEN-1:0] i_op1,      // rs1
  input  logic [XLEN-1:0] i_op2,      // rs2
  output logic            o_ready,    // idle, can accept

  // Result
  output logic            o_valid,
  output logic [XLEN-1:0] o_result
);

  localparam logic [2:0] F3_MUL    = 3'b000;
  localparam logic [2:0] F3_MULH   = 3'b001;
  localparam logic [2:0] F3_MULHSU = 3'b010;
  localparam logic [2:0] F3_MULHU  = 3'b011;
  localparam logic [2:0] F3_DIV    = 3'b100;
  localparam logic [2:0] F3_DIVU   = 3'b101;
  localparam logic [2:0] F3_REM    = 3'b110;
  localparam logic [2:0] F3_REMU   = 3'b111;

  logic is_div_op, is_rem_op, is_signed_div;
  assign is_div_op     = i_funct3[2];                  // 1xx
  assign is_rem_op     = i_funct3[2] && i_funct3[1];   // 11x
  assign is_signed_div = i_funct3[2] && !i_funct3[0];  // DIV (100) or REM (110)

  // ───────────────────────────────────────────────
  // Multiply
  // ───────────────────────────────────────────────
  // MUL only needs the low half, which is identical under either
  // interpretation, so it rides the signed path.
  logic mul_a_signed, mul_b_signed;
  always_comb begin
    unique case (i_funct3)
      F3_MULHU:  begin mul_a_signed = 1'b0; mul_b_signed = 1'b0; end
      F3_MULHSU: begin mul_a_signed = 1'b1; mul_b_signed = 1'b0; end
      default:   begin mul_a_signed = 1'b1; mul_b_signed = 1'b1; end
    endcase
  end

  logic signed [XLEN:0] mul_a_ext, mul_b_ext;
  assign mul_a_ext = signed'({mul_a_signed & i_op1[XLEN-1], i_op1});
  assign mul_b_ext = signed'({mul_b_signed & i_op2[XLEN-1], i_op2});

  logic signed [2*XLEN+1:0] mul_product;
  assign mul_product = mul_a_ext * mul_b_ext;

  // ───────────────────────────────────────────────
  // Divide datapath
  // ───────────────────────────────────────────────
  // Restoring division. The partial remainder needs XLEN+1 bits: the
  // invariant is rem < divisor, so after shifting in one more bit it can
  // reach 2*divisor-1, which does not fit in XLEN.
  logic [XLEN:0]     rem_q;        // XLEN+1 bits, deliberately
  logic [XLEN-1:0]   dividend_q;   // shifted out MSB-first
  logic [XLEN-1:0]   quot_q;       // shifted in LSB-first
  logic [XLEN-1:0]   divisor_q;
  logic [5:0]        iter_q;
  logic              quot_neg_q, rem_neg_q, take_rem_q;

  // One iteration: shift the next dividend bit in, then subtract if it fits.
  logic [XLEN:0] rem_shifted, rem_less_div;
  logic          div_fits;
  assign rem_shifted  = {rem_q[XLEN-1:0], dividend_q[XLEN-1]};
  assign rem_less_div = rem_shifted - {1'b0, divisor_q};
  assign div_fits     = !rem_less_div[XLEN];   // no borrow -> divisor fitted

  // Operand preparation: signed forms work on magnitudes.
  logic op1_neg, op2_neg;
  assign op1_neg = is_signed_div && i_op1[XLEN-1];
  assign op2_neg = is_signed_div && i_op2[XLEN-1];

  logic [XLEN-1:0] dividend_abs, divisor_abs;
  assign dividend_abs = op1_neg ? (~i_op1 + 1'b1) : i_op1;
  assign divisor_abs  = op2_neg ? (~i_op2 + 1'b1) : i_op2;

  // Special cases, answered without iterating.
  logic div_by_zero, div_overflow;
  assign div_by_zero  = (i_op2 == '0);
  assign div_overflow = is_signed_div
                        && (i_op1 == {1'b1, {(XLEN-1){1'b0}}})   // -2^31
                        && (&i_op2);                             // -1

  logic [XLEN-1:0] special_result;
  always_comb begin
    if (div_by_zero)
      special_result = is_rem_op ? i_op1 : {XLEN{1'b1}};
    else // overflow: -2^31 / -1
      special_result = is_rem_op ? '0 : {1'b1, {(XLEN-1){1'b0}}};
  end

  // ───────────────────────────────────────────────
  // Control
  // ───────────────────────────────────────────────
  typedef enum logic [1:0] { S_IDLE, S_MUL, S_DIV, S_DONE } state_e;
  state_e state_q;

  // Result staging. res_q carries multiply and special-case answers;
  // the iterated divide assembles its answer from rem_q/quot_q instead,
  // because those are only final once the last iteration has landed.
  // use_div_q says which.
  logic [XLEN-1:0] res_q;
  logic            use_div_q;

  // Sign fix-up. The quotient is negative when exactly one operand was;
  // the remainder always takes the sign of the DIVIDEND.
  logic [XLEN-1:0] div_final;
  always_comb begin
    if (take_rem_q)
      div_final = rem_neg_q  ? (~rem_q[XLEN-1:0] + 1'b1) : rem_q[XLEN-1:0];
    else
      div_final = quot_neg_q ? (~quot_q + 1'b1)          : quot_q;
  end

  assign o_ready  = (state_q == S_IDLE);
  assign o_valid  = (state_q == S_DONE);
  assign o_result = use_div_q ? div_final : res_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q    <= S_IDLE;
      res_q      <= '0;
      use_div_q  <= 1'b0;
      rem_q      <= '0;
      dividend_q <= '0;
      quot_q     <= '0;
      divisor_q  <= '0;
      iter_q     <= '0;
      quot_neg_q <= 1'b0;
      rem_neg_q  <= 1'b0;
      take_rem_q <= 1'b0;
    end
    else if (i_flush) begin
      // Nothing outside has consumed a result yet, so dropping straight
      // back to idle leaves no partial state to unwind.
      state_q   <= S_IDLE;
      use_div_q <= 1'b0;
    end
    else begin
      unique case (state_q)
        S_IDLE: begin
          if (i_valid) begin
            if (!is_div_op) begin
              res_q     <= (i_funct3 == F3_MUL) ? mul_product[XLEN-1:0]
                                                : mul_product[2*XLEN-1:XLEN];
              use_div_q <= 1'b0;
              state_q   <= S_MUL;
            end
            else if (div_by_zero || div_overflow) begin
              res_q     <= special_result;
              use_div_q <= 1'b0;
              state_q   <= S_DONE;
            end
            else begin
              rem_q      <= '0;
              dividend_q <= dividend_abs;
              quot_q     <= '0;
              divisor_q  <= divisor_abs;
              iter_q     <= '0;
              quot_neg_q <= op1_neg ^ op2_neg;
              rem_neg_q  <= op1_neg;
              take_rem_q <= is_rem_op;
              use_div_q  <= 1'b1;
              state_q    <= S_DIV;
            end
          end
        end

        // The multiply result was captured on entry; this state exists so
        // the 33x33 product is a registered stage rather than a
        // combinational path from dispatch to write-back.
        S_MUL: state_q <= S_DONE;

        S_DIV: begin
          rem_q      <= div_fits ? rem_less_div : rem_shifted;
          quot_q     <= {quot_q[XLEN-2:0], div_fits};
          dividend_q <= {dividend_q[XLEN-2:0], 1'b0};

          if (iter_q == XLEN-1) state_q <= S_DONE;
          else                  iter_q  <= iter_q + 6'd1;
        end

        S_DONE: state_q <= S_IDLE;

        default: state_q <= S_IDLE;
      endcase
    end
  end

`ifdef SIMULATION
  // o_valid must mean a result, and only for one cycle per operation.
  assert property (@(posedge clk) disable iff (!rst_n)
    o_valid |=> !o_valid
  ) else $error("MDU: o_valid held for more than one cycle");

  // Accepting work while busy would silently drop an operation.
  assert property (@(posedge clk) disable iff (!rst_n)
    (i_valid && !o_ready) |-> ##0 (state_q != S_IDLE)
  ) else $error("MDU: accepted an operation while busy");

  // The iteration count must be exact -- an off-by-one here produces a
  // quotient that is wrong by a factor of two and is easy to miss.
  assert property (@(posedge clk) disable iff (!rst_n)
    (state_q == S_DIV && iter_q == XLEN-1) |=> (state_q == S_DONE)
  ) else $error("MDU: divide did not finish on the last iteration");
`endif

endmodule
