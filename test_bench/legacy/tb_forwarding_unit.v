`timescale 1ns / 1ps
`include "rtl/parameters.vh"
module tb_forwarding_unit;

reg [4:0] i_rs1 ,i_rs2 ,i_rd_decode ,i_rd_execute ,i_rd_mem , is_branch_rs1 ,is_branch_rs2;
reg [6:0] i_opcode_decode,i_opcode_EX;
reg is_branch;
wire o_stall, o_forward_EX_rs1 , o_forward_EX_rs2 , o_forward_MEM_rs1 , o_forward_MEM_rs2 , o_forward_branch;

//module instantiation
forwarding_unit forward_inst( .i_rs1(i_rs1),
			      .i_rs2(i_rs2),
			      .i_rd_decode(i_rd_decode),
			      .i_rd_execute(i_rd_execute),
			      .i_rd_mem(i_rd_mem),
			      .is_branch_rs1(is_branch_rs1),
			      .is_branch_rs2(is_branch_rs2),
			      .is_branch(is_branch),
			      .i_opcode_decode(i_opcode_decode),
			      .i_opcode_EX(i_opcode_EX),
			      .o_stall(o_stall),
			      .o_forward_EX_rs1(o_forward_EX_rs1),
			      .o_forward_EX_rs2(o_forward_EX_rs2),
			      .o_forward_MEM_rs1(o_forward_MEM_rs1),
			      .o_forward_MEM_rs2(o_forward_MEM_rs2),
			      .o_forward_branch(o_forward_branch)
);
initial 
begin
	 $dumpfile("waveform.vcd");
    $dumpvars(0, tb_forwarding_unit);
	i_rs1 = 5'b00011;
	i_rd_execute = 5'b00011;
	i_opcode_EX = `S;
	#20
	i_rs2 = 5'b01010;
	i_rd_execute = 5'b01010;
	i_opcode_EX = `LD;
	#10
	
	i_rd_mem = 5'b01010;
	
	#10
	is_branch = 1;
	is_branch_rs1 = 5'b00100;
	is_branch_rs2 = 5'b00111;
	i_rd_decode = 5'b00100;
	i_rd_execute=5'b00001;
	#10
	is_branch = 1;
	is_branch_rs1 = 5'b00100;
	is_branch_rs2 = 5'b00111;
	i_rd_decode = 5'b00100;
	i_rd_execute=5'b00100;
	
	#100 $finish;
end
endmodule
	
	
