module tb_branch_jump_decision();
reg [31:0] is_rs1_data,is_rs2_data;
reg [6:0] is_opcode;
reg [31:0] is_pc;
reg [2:0] is_func3;
reg [31:0] i_imm;
wire branch_flush;
wire [31:0] branch_pc;
branch_jump_decision DUT( .is_rs1_data(is_rs1_data),
			  .is_rs2_data(is_rs2_data),
			  .is_opcode(is_opcode),
			  .is_pc(is_pc),
			  .is_func3(is_func3),
			  .i_imm(i_imm),
			  .branch_flush(branch_flush),
			  .branch_pc(branch_pc)
);
initial begin
// Initialise with BEQ condition
is_rs1_data=32'hffff0000;
is_rs2_data=32'hf1f2f3f4;
is_opcode=7'b1100011;
is_pc=32'h00000000;
is_func3=3'b000;
i_imm=32'h00000008;
 #10; // Wait for 10 time units
      $dumpfile("waveform.vcd");
      $dumpvars(0, tb_branch_jump_decision);
// Case-1 BEQ condition
is_rs1_data=32'hffff0000;
is_rs2_data=32'hffff0000;
is_opcode=7'b1100011;
is_pc=32'h00000000;
is_func3=3'b000;
i_imm=32'h00000008;
#10;
// Case-2 BNE condition
is_rs1_data=32'hf1f2f3f4;
is_rs2_data=32'hf1f2f3f4;
is_opcode=7'b1100011;
is_pc=32'h00000000;
is_func3=3'b001;
i_imm=32'h00000008;
#10;
// case-3 BLT
is_rs1_data=32'h80000003;
is_rs2_data=32'h80000004;
is_opcode=7'b1100011;
is_pc=32'h00000000;
is_func3=3'b100;
i_imm=32'h00000008;
#10;
// Case-4 BGE condition
is_rs1_data=32'h00000002;
is_rs2_data=32'h00000003;
is_opcode=7'b1100011;
is_pc=32'h00000000;
is_func3=3'b101;
i_imm=32'h00000008;
#10;
// Case-4 BGEU
is_rs1_data=32'h11111115;
is_rs2_data=32'h11111114;
is_opcode=7'b1100011;
is_pc=32'h00000000;
is_func3=3'b111;
i_imm=32'h00000008;
#10;
// Case-4 JAL condition
is_opcode=7'b1101111 ;
is_rs1_data=32'h00000000;
is_rs2_data=32'h00000000;
is_func3=3'b000;
is_pc=32'h00000000;
i_imm=32'h00000008;
#10;

      $finish; // End simulation
   end

endmodule
