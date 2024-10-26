/*
   Copyright 2024 Sudeep Joshi

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License. */

`timescale 1ns / 1ps
`default_nettype none
`include "rtl/parameters.vh"
`include "rtl/alu.v"
`include "rtl/branch_decision.v"
`include "rtl/forwarding_unit.v"

module Execute(
input wire clk,
input wire rst_n,
input wire [31:0] i_rs1_data,
input wire [31:0] i_rs2_data,
input wire [31:0] i_imm_data,
input wire [31:0] i_pc,
input wire [3:0] i_alu_ctrl,
input wire [2:0] i_func3,
input wire [6:0] i_opcode,
input wire [4:0] i_rs1,
input wire [4:0] i_rs2,
input wire [4:0] i_rd_decode,
input wire [4:0] i_rd_mem, // input required for MEM to EX forwarding
input wire [31:0] i_mem_result, // input required for stall and forward due to dependency of branch/jump instruction
input wire i_is_branch, // input from branch decode (without clocked) to check branch dependency
input wire [4:0] i_is_rs1, // source registers for checking dependency ,if branch
input wire [4:0] i_is_rs2,
// outputs to the next stage(MEM)
output reg [31:0] o_result, // must be forwarded to both IF and MEM stages
output reg [31:0] o_data_store,
output reg [31:0] o_pc,
output reg [2:0] o_func3,
output reg [6:0] o_opcode,
output reg [4:0] o_rd,
// outputs to previous stages 
output reg o_stall,
output reg o_forward_branch , // Forwarding o_result to decode when there is dependancy of branch instruction on previous instruction after stalling
output reg o_decode_forward_rs1,
output reg o_decode_forward_rs2
);

wire [31:0] is_op1, is_op2;
wire is_forward_EX_rs1 , is_forward_EX_rs2,is_forward_MEM_rs1,is_forward_MEM_rs2, is_forward_branch;
wire [31:0] is_data_store;
wire [6:0] is_opcode_execute;
wire [31:0] is_pc;
wire [31:0] is_result;
wire is_stall;
wire [4:0] is_rd_execute, is_rd_mem;
reg [31:0] is_rd_decode;

// MUX before the ALU
assign is_op1 = (is_forward_EX_rs1 == 1) ? o_result : 
		(is_forward_MEM_rs1 == 1) ? i_mem_result : 
		( is_opcode == `UPC) ? is_pc :i_rs1_data ;

assign is_op2 = (is_forward_EX_rs2 == 1 && (i_opcode != `S || i_opcode != `LD ) ) ? o_result : 
		(is_forward_MEM_rs2 == 1) ? i_mem_result : 
		((i_opcode == `R) | (i_opcode == `B)) ? i_rs2_data : i_imm_data; 

// Data to store into Data Memory
assign is_data_store = (i_opcode == `S) ? ( (is_forward_EX_rs2 == 1 ) ? o_result : (is_forward_MEM_rs2 == 1 ) ? i_mem_result : i_rs2_data) : 32'b0;
assign is_pc = i_pc;
assign is_opcode_execute = o_opcode;
assign is_rd_mem = i_rd_mem;
assign is_rd_execute = o_rd;

//Internal Registers used for pipelining
reg [6:0] is_opcode;
reg [2:0] is_func3;

// Pipeing the signals to next stage at every clock
always@( posedge clk or negedge rst_n)
begin 
	if(~rst_n) begin
		o_result <= 32'b0;
		o_opcode <= 7'b0;
		o_func3 <= 3'b0;
		o_pc <= 32'b0;
		o_data_store <= 32'b0;
		o_rd <= 5'b0;
		
	end
		
	else if( ~(o_stall) || (i_is_branch) ) begin
		o_result <= is_result;
		o_opcode <= is_opcode;
		o_func3 <= is_func3;
		o_pc <= is_pc;
		o_data_store <= is_data_store;
		o_rd <= is_rd_decode;
	end
		
end
// Stalling logic and forwarding the data to decode after stalling
always@(*)
begin
	o_stall = is_stall ;
	o_forward_branch = is_forward_branch;
	is_rd_decode = i_rd_decode;
	is_opcode = i_opcode;
	is_func3 = i_func3;
	// Outputs to decode stage
	o_decode_forward_rs1 = ((is_forward_branch == 1) && (i_is_rs1 == i_rd_decode)) ? 1'b1 : 1'b0;
	o_decode_forward_rs2 = ((is_forward_branch == 1) && (i_is_rs2 == i_rd_decode)) ? 1'b1 : 1'b0;
end

always @(posedge clk) begin
    //$display("Time: %0t", $time);
   //$display("is_rs1: %b, is_rs2: %b, is_rd_decode: %b", is_rs1, is_rs2, is_rd_decode);
    //$display("is_op1: , is_op2: ", is_op1, is_op2);
    //$display("is_result: %b", is_result);
    //$display("is_rs1_data: , is_rs2_data: ", i_rs1_data, i_rs2_data);
    //$display("is_imm: %h, is_boj: %b", is_imm, is_boj);
    //$display("ir_instr: %h", ir_instr);
   // $display("is_branch_pc: %h", is_branch_pc);
    //$display("ir_flush: %h", ir_flush);
    //$display("o_stall=%b",o_stall);
    //$display("o_result = %b", o_result);
    //$display("i_mem_result = %b", i_mem_result);
    //$display("i_rs2_data = %b", i_rs2_data);
    //$display("i_imm_data = %b", i_imm_data);
    //$display("is_forward_EX_rs2 = %b", is_forward_EX_rs2);
    //$display("is_forward_MEM_rs2 = %b", is_forward_MEM_rs2);
    //$display("i_opcode = %b", i_opcode);
    //$display("is_forward_branch = %b", is_forward_branch);	
    $display("is_stall : %b", is_stall);
end


forwarding_unit forward_inst( .i_rs1(i_rs1),
			      .i_rs2(i_rs2),
			      .i_rd_decode(i_rd_decode),
			      .i_rd_execute(is_rd_execute),
			      .i_opcode_decode(is_opcode),
			      .i_rd_mem(is_rd_mem),
			      .i_opcode_EX(is_opcode_execute),
			      .is_branch(i_is_branch),
			      .is_branch_rs1(i_is_rs1),
			      .is_branch_rs2(i_is_rs2),
			      .o_forward_EX_rs1(is_forward_EX_rs1),
			      .o_forward_EX_rs2(is_forward_EX_rs2),
			      .o_forward_MEM_rs1(is_forward_MEM_rs1),
			      .o_forward_MEM_rs2(is_forward_MEM_rs2),
			      .o_forward_branch(is_forward_branch),
			      .o_stall(is_stall)
);
			    

alu alu_inst (
	.i_op1(is_op1),
	.i_op2(is_op2),
	.i_alu_ctrl(i_alu_ctrl),
	.i_stall(is_stall),
	.o_result(is_result)
);

endmodule //check from is_stall here
