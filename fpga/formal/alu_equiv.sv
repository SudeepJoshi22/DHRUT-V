// ALU equivalence over all operands and operations.
// The reference and DUT are inlined; keep alu_dut consistent with rtl/pipeline/alu.sv.

typedef enum logic [9:0] {
    A_ADD  = 10'b0_000, A_SUB  = 10'b1_000,
    A_SLL  = 10'b0_001, A_SLT  = 10'b0_010,
    A_SLTU = 10'b0_011, A_XOR  = 10'b0_100,
    A_SRL  = 10'b0_101, A_SRA  = 10'b1_101,
    A_OR   = 10'b0_110, A_AND  = 10'b0_111
} aop_t;

// Reference: one operator per case arm.
module alu_ref (input logic [31:0] i_op1, i_op2, input aop_t i_alu_op,
                output logic [31:0] o_result);
  always_comb begin
    o_result = 32'b0;
    unique case (i_alu_op)
      A_ADD:   o_result = i_op1 + i_op2;
      A_SUB:   o_result = i_op1 - i_op2;
      A_SLL:   o_result = i_op1 << i_op2[4:0];
      A_SRL:   o_result = i_op1 >> i_op2[4:0];
      A_SRA:   o_result = $signed(i_op1) >>> i_op2[4:0];
      A_SLT:   o_result = ($signed(i_op1) < $signed(i_op2)) ? 32'd1 : 32'd0;
      A_SLTU:  o_result = (i_op1 < i_op2) ? 32'd1 : 32'd0;
      A_XOR:   o_result = i_op1 ^ i_op2;
      A_OR:    o_result = i_op1 | i_op2;
      A_AND:   o_result = i_op1 & i_op2;
      default: o_result = 32'hBADC0DE;
    endcase
  end
endmodule

// DUT: shared arithmetic and shift datapaths.
module alu_dut (input logic [31:0] i_op1, i_op2, input aop_t i_alu_op,
                output logic [31:0] o_result);
  logic do_sub; logic [32:0] sum_ext; logic [31:0] sum;
  assign do_sub  = (i_alu_op == A_SUB) || (i_alu_op == A_SLT) || (i_alu_op == A_SLTU);
  assign sum_ext = do_sub ? ({1'b0, i_op1} - {1'b0, i_op2})
                          : ({1'b0, i_op1} + {1'b0, i_op2});
  assign sum     = sum_ext[31:0];

  logic lt_u, lt_s;
  assign lt_u = sum_ext[32];
  assign lt_s = (i_op1[31] == i_op2[31]) ? sum_ext[32] : i_op1[31];

  logic [4:0] shamt; logic sra; logic [32:0] shr_in; logic [31:0] shr_res, shl_res;
  assign shamt   = i_op2[4:0];
  assign sra     = (i_alu_op == A_SRA);
  assign shr_in  = {sra & i_op1[31], i_op1};
  assign shr_res = 32'($signed(shr_in) >>> shamt);
  assign shl_res = i_op1 << shamt;

  always_comb begin
    unique case (i_alu_op)
      A_ADD, A_SUB: o_result = sum;
      A_SLL:        o_result = shl_res;
      A_SRL, A_SRA: o_result = shr_res;
      A_SLT:        o_result = {31'b0, lt_s};
      A_SLTU:       o_result = {31'b0, lt_u};
      A_XOR:        o_result = i_op1 ^ i_op2;
      A_OR:         o_result = i_op1 | i_op2;
      A_AND:        o_result = i_op1 & i_op2;
      default:      o_result = 32'hBADC0DE;
    endcase
  end
endmodule

module alu_equiv (input logic [31:0] op1, op2, input logic [3:0] op_raw);
  aop_t op; assign op = aop_t'({6'b0, op_raw});
  logic [31:0] r_ref, r_dut;
  alu_ref REF (.i_op1(op1), .i_op2(op2), .i_alu_op(op), .o_result(r_ref));
  alu_dut DUT (.i_op1(op1), .i_op2(op2), .i_alu_op(op), .o_result(r_dut));
  always_comb assert (r_ref == r_dut);
endmodule
