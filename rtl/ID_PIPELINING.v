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
`include "rtl/reg_file.v"
`include "rtl/imm_gen.v"
`include "rtl/control_unit.v"

module ID(
input wire clk,
input wire rst_n,
input wire [31:0] i_instr, // Instruction Fetched in IF stage
input wire signed [31:0] i_write_data, // Data to be written to register file from the WB stage
input wire [31:0] i_pc, // PC of the current instruction
input wire i_wr, // write enable signal from the WB stage, enables the register file to write to rd.
output wire [31:0] o_rs1_data, // rs1 data from register file
output wire [31:0] o_rs2_data, // rs2 data from register file
output wire [31:0] o_imm_data, // signa extended immediate value
output wire [6:0] o_opcode, // opcode of the current instruction
output wire [2:0] o_func3, // func3 of the current instruction
output wire [3:0] o_alu_ctrl, // ALU Control signals  
output wire [31:0] o_pc // PC for the next stage
);

wire [4:0] is_rs1, is_rs2, is_rd;
wire [6:0] is_opcode;
wire [2:0] is_func3;
wire is_re;
wire is_alu_ctrl;

assign is_rs1 = i_instr[19:15];
assign is_rs2 = i_instr[24:20];
assign is_rd = i_instr[11:7];
assign is_opcode = i_instr[6:0];
assign is_func3 = i_instr[14:12];

assign o_func3 = is_func3;
assign o_opcode = is_opcode;

assign is_re = ~((is_opcode == `J) | (is_opcode == `U) | (is_opcode == `UPC)); // every instruction except LUI, AUIPC and JAL requires register file to be read

assign o_pc = i_pc;

reg_file reg_file_inst(
	.clk(clk),
	.rst_n(rst_n),
	.i_re(is_re),
	.i_wr(i_wr),
	.i_rs1(is_rs1),
	.i_rs2(is_rs2),
	.i_rd(is_rd),
	.i_write_data(i_write_data),
	.o_read_data1(o_rs1_data),
	.o_read_data2(o_rs2_data)
);

imm_gen imm_gen_inst (
  .i_instr(i_instr),
  .o_imm_data(o_imm_data)
);

control_unit control_unit_inst (
  .i_instr(i_instr),
  .o_alu_ctrl(is_alu_ctrl)
);

endmodule
