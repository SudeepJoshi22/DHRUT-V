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
`include "rtl/branch_jump_decision.v"

module ID(
input wire clk,
input wire rst_n,
input wire [31:0] i_instr, // Instruction Fetched in IF stage
input wire signed [31:0] i_write_data, // Data to be written to register file from the WB stage
input wire [31:0] i_pc, // PC of the current instruction
input wire i_wr, // write enable signal from the WB stage, enables the register file to write to rd.
input wire i_ce,
output reg [31:0] o_rs1_data, // rs1 data from register file
output reg [31:0] o_rs2_data, // rs2 data from register file
output reg [31:0] o_imm_data, // signa extended immediate value
output reg [6:0] o_opcode, // opcode of the current instruction
output reg [2:0] o_func3, // func3 of the current instruction
output reg [3:0] o_alu_ctrl, // ALU Control signals  
output reg [31:0] o_pc,// PC for the next stage
output reg [31:0] branch_pc, 
// pipeline control
input wire i_stall, // stall signal from EX stage 
output reg o_stall, // stall signal to IF stage
output reg o_flush, // Flush signal to IF depending on branch decision
output reg o_ce
);

wire [4:0] is_rs1, is_rs2, is_rd;
wire [6:0] is_opcode;
wire [2:0] is_func3;
wire is_re;
wire [3:0] is_alu_ctrl;
wire [31:0] is_rs1_data;
wire [31:0] is_rs2_data; 
wire  [31:0] is_imm;
wire is_boj;
reg [31:0] d_instr; // used for decoding
wire [31:0] is_branch_pc;
wire [31:0] is_pc;

// Debug Display Statements
always @(posedge clk) begin
    $display("Time: %0t", $time);
    $display("is_rs1: %b, is_rs2: %b, is_rd: %b", is_rs1, is_rs2, is_rd);
    $display("is_opcode: %b, is_func3: %b", is_opcode, is_func3);
    $display("is_re: %b, is_alu_ctrl: %b", is_re, is_alu_ctrl);
    $display("is_rs1_data: %h, is_rs2_data: %h", is_rs1_data, is_rs2_data);
    $display("is_imm: %h, is_boj: %b", is_imm, is_boj);
    $display("d_instr: %h", d_instr);
    $display("is_branch_pc: %h", is_branch_pc);
end


// Internal Flush Condition
always@(*)
begin
	if(is_boj == 0) begin
		d_instr <= i_instr;	
	end
	
end

// Decode of instructions
assign is_rs1= d_instr[19:15];
assign is_rs2= d_instr[24:20];
assign is_rd = d_instr[11:7];
assign is_opcode = d_instr[6:0];
assign is_func3 = d_instr[14:12];
assign is_re = ~((is_opcode == `J) | (is_opcode == `U) | (is_opcode == `UPC)); // every instruction except LUI, AUIPC and JAL requires register file to be read
assign is_pc = i_pc;

//Pipeing the signals to next stage
always@(posedge clk)
begin
	if(~rst_n) begin
	o_ce<=0;
	end
	else if( i_ce && !(i_stall) )begin // pipe through signals when stage is enabled and not stalled
	o_rs1_data<=is_rs1_data;
	o_rs2_data<=is_rs2_data;
	o_imm_data<=is_imm;
	o_opcode<=is_opcode;
	o_func3<=is_func3;
	o_alu_ctrl<=is_alu_ctrl;
	end
      
       if(i_stall) begin
	o_ce<=0;
	end
	else o_ce<=i_ce;
	
end
always@(*)
begin
	o_flush=is_boj;
	o_stall=i_stall;
	branch_pc=is_branch_pc;
end
	
branch_jump_decision dut_inst(		       
			.is_rs1_data(is_rs1_data),
		   	.is_rs2_data(is_rs2_data),
		        .is_func3(is_func3),
		        .is_opcode(is_opcode),
		        .is_pc(is_pc),
		        .i_imm(is_imm),
		        .branch_flush(is_boj),
		        .branch_pc(is_branch_pc)
);



reg_file reg_file_inst(
	.clk(clk),
	.rst_n(rst_n),
	.i_re(is_re),
	.i_wr(i_wr),
	.i_rs1(is_rs1),
	.i_rs2(is_rs2),
	.i_rd(is_rd),
	.i_write_data(i_write_data),
	.o_read_data1(is_rs1_data),
	.o_read_data2(is_rs2_data)
);

imm_gen imm_gen_inst (
  .i_instr(d_instr),
  .o_imm_data(is_imm)
);

control_unit control_unit_inst (
  .i_instr(d_instr),
  .o_alu_ctrl(is_alu_ctrl)
);


endmodule
