// MIT License
// 
// Copyright (c) 2023 Sudeep.
// 
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// 
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

`timescale 1ns / 1ps
`default_nettype none
`include "rtl/parameters.vh"
`include "rtl/alu.v"
`include "rtl/branch_decision.v"

module EX(
input wire clk,
input wire rst_n,
input wire [31:0] i_rs1_data,
input wire [31:0] i_rs2_data,
input wire [31:0] i_imm_data,
input wire [31:0] i_pc,
input wire [3:0] i_alu_ctrl,
input wire [2:0] i_func3,
input wire [6:0] i_opcode,
// outputs to the next stage(MEM)
output wire [31:0] o_result, // must be forwarded to both IF and MEM stages
output wire [31:0] o_data_store,
output wire [31:0] o_pc,
output wire [2:0] o_func3,
output wire [6:0] o_opcode,
// outputs for the IF stage
output wire o_boj,
output wire o_jalr,
output wire [31:0] o_imm_data
);

wire [31:0] is_op1, is_op2;
wire is_branch;

// signals going to IF stage
assign o_boj = (is_branch & (i_opcode == `B))  | (i_opcode == `J);
assign o_jalr = i_opcode == `JR;
assign o_imm_data = i_imm_data;

// MUX before the ALU
assign is_op1 = (i_opcode == `UPC) ? i_pc : i_rs1_data;
assign is_op2 = ((i_opcode == `R) | (i_opcode == `B)) ? i_rs2_data : i_imm_data; 

// Data to store into Data Memory
assign o_data_store = (i_opcode == `S) ? i_rs2_data : 32'd0;

assign o_func3 = i_func3;
assign o_opcode = i_opcode;
assign o_pc = i_pc;

branch_decision branch_dec_inst (
	.i_result(o_result),
	.i_func3(i_func3),
	.o_branch(is_branch)
);

alu alu_inst (
	.i_op1(is_op1),
	.i_op2(is_op2),
	.i_alu_ctrl(i_alu_ctrl),
	.o_result(o_result)
);

endmodule
