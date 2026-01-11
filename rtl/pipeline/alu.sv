import riscv_uop_pkg::*;

module alu (
  input  logic [31:0] i_op1,          // operand 1 (from rs1 or PC)
  input  logic [31:0] i_op2,          // operand 2 (from rs2 or immediate)
  input  alu_op_t     i_alu_op,       // operation selector from decode
  output logic [31:0] o_result        // ALU result
);

  // ───────────────────────────────────────────────
  // ALU operation decoding and computation
  // ───────────────────────────────────────────────
  always_comb begin
    o_result = 32'b0;  // default

    unique case (i_alu_op)
      ALU_ADD:   o_result = i_op1 + i_op2;
      ALU_SUB:   o_result = i_op1 - i_op2;

      ALU_SLL:   o_result = i_op1 << i_op2[4:0];         // shift amount lower 5 bits
      ALU_SRL:   o_result = i_op1 >> i_op2[4:0];
      ALU_SRA:   o_result = $signed(i_op1) >>> i_op2[4:0]; // arithmetic right shift

      ALU_SLT:   o_result = ($signed(i_op1) < $signed(i_op2)) ? 32'd1 : 32'd0;
      ALU_SLTU:  o_result = (i_op1 < i_op2) ? 32'd1 : 32'd0;

      ALU_XOR:   o_result = i_op1 ^ i_op2;
      ALU_OR:    o_result = i_op1 | i_op2;
      ALU_AND:   o_result = i_op1 & i_op2;

      default: begin
        o_result = 32'hBADC0DE;   // another debug marker
      end
    endcase
  end

endmodule
