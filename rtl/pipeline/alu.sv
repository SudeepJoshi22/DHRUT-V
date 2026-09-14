import riscv_uop_pkg::*;

module alu (
  input  logic [31:0] i_op1,          // operand 1 (from rs1 or PC)
  input  logic [31:0] i_op2,          // operand 2 (from rs2 or immediate)
  input  alu_op_t     i_alu_op,       // operation selector from decode
  output logic [31:0] o_result        // ALU result
);

  // Shared-datapath ALU. The naive form -- one `unique case` arm per
  // operation, each with its own operator -- infers THREE 32-bit shifters
  // (<<, >>, >>>) and THREE subtractors (SUB plus the two comparators),
  // because each arm is a separate expression. On a GW2AR-18 that is
  // expensive, and alu.sv is instantiated twice (ALU0/ALU1), so every
  // redundant operator is paid for twice.
  //
  // Here one adder and one shifter serve every arm that needs them, and
  // the case only selects between already-computed results. Identical
  // truth table, far fewer cells.
  //
  // alu_op_t mirrors RISC-V funct3 in bits [2:0] with bit [3] as the
  // "alternate op" flag (ALU_SUB = 1_000 vs ALU_ADD = 0_000; ALU_SRA =
  // 1_101 vs ALU_SRL = 0_101), which is what makes the sharing below fall
  // out so directly.

  // ── Shared adder/subtractor ───────────────────────────────────────
  // SUB, SLT and SLTU are all op1 - op2. Feeding the subtract path from
  // one adder gives the comparators their borrow for free rather than
  // building a dedicated comparator each.
  logic        do_sub;
  logic [32:0] sum_ext;
  logic [31:0] sum;

  assign do_sub  = (i_alu_op == ALU_SUB) || (i_alu_op == ALU_SLT)
                || (i_alu_op == ALU_SLTU);
  assign sum_ext = do_sub ? ({1'b0, i_op1} - {1'b0, i_op2})
                          : ({1'b0, i_op1} + {1'b0, i_op2});
  assign sum     = sum_ext[31:0];

  // ── Comparators, derived from the shared subtract ─────────────────
  // Unsigned: the borrow out of op1 - op2 IS op1 < op2.
  // Signed: equal sign bits means the borrow already answers it;
  // differing sign bits means the negative operand is the smaller, so
  // op1 < op2 exactly when op1 is the negative one.
  logic lt_u, lt_s;
  assign lt_u = sum_ext[32];
  assign lt_s = (i_op1[31] == i_op2[31]) ? sum_ext[32] : i_op1[31];

  // ── Shared shifter ────────────────────────────────────────────────
  // One right-shift unit covers SRL and SRA by sign-extending only for
  // SRA. Left shift stays separate: folding it in by bit-reversing the
  // operand costs two 32-bit reversals, which is not obviously cheaper
  // than the shifter it saves on this fabric.
  logic [4:0]  shamt;
  logic        sra;
  logic [32:0] shr_in;
  logic [31:0] shr_res, shl_res;

  assign shamt   = i_op2[4:0];
  assign sra     = (i_alu_op == ALU_SRA);
  assign shr_in  = {sra & i_op1[31], i_op1};
  assign shr_res = 32'($signed(shr_in) >>> shamt);
  assign shl_res = i_op1 << shamt;

  // ── Result select ─────────────────────────────────────────────────
  // Selects among precomputed values; no operators live in these arms.
  always_comb begin
    unique case (i_alu_op)
      ALU_ADD,
      ALU_SUB:   o_result = sum;

      ALU_SLL:   o_result = shl_res;
      ALU_SRL,
      ALU_SRA:   o_result = shr_res;

      ALU_SLT:   o_result = {31'b0, lt_s};
      ALU_SLTU:  o_result = {31'b0, lt_u};

      ALU_XOR:   o_result = i_op1 ^ i_op2;
      ALU_OR:    o_result = i_op1 | i_op2;
      ALU_AND:   o_result = i_op1 & i_op2;

      default:   o_result = 32'hBADC0DE;   // another debug marker
    endcase
  end

endmodule
