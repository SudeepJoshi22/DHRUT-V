// MIT License
// 
// Copyright (c) 2023 Sudeep et al.
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

module IF(
input wire clk,
input wire rst_n,
output wire [31:0] o_pc, //Current PC value
output reg [31:0] o_instr,
//instruction memory interface
input wire [31:0] i_inst, //instruction code received from the instruction memory
input wire i_imem_ack, //ack by instruction memory (active high)
output reg o_imem_stb, //stub signal for instruction memroy
output reg [31:0] o_iaddr, //instruction address
//Change in PC
input wire [31:0] i_imm,
input wire [31:0] i_result,
input wire i_boj,
input wire i_jalr
);

//internal signals and registers
wire is_stall = !i_imem_ack & rst_n;
wire [31:0] is_pc_increment;
reg [31:0] pc;

assign is_pc_increment = i_boj ? i_imm : ( is_stall ? 32'd0 : 32'd4 );
assign o_pc = pc;

always @(posedge clk)
begin
	if(~rst_n)
	begin
		pc <= `PC_RESET;
	end
	else if(is_stall)
	begin
		pc <= pc;
	end
	else if(i_jalr)
	begin
		pc <= i_result &~1;	
	end
	else
	begin
		pc <= pc + is_pc_increment;
	end
end

always @(*)
begin
	if(~rst_n)
	begin
		o_iaddr = 32'd0;
		o_imem_stb = 1'b0;
		o_instr = `NOP;
	end
	else if(is_stall)
		o_instr = `NOP;
	else
	begin
		o_iaddr = pc;
		o_imem_stb = 1'b1;
		o_instr = i_inst;
	end
end

endmodule
