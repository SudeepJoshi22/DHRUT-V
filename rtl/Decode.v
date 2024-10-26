/*
   Copyright 2024 Sudeep Joshi Et el.

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
`include "rtl/reg_file.v"
`include "rtl/imm_gen.v"
`include "rtl/control_unit.v"
`include "rtl/branch_jump_decision.v"

module Decode(
input wire clk,
input wire rst_n,
input wire [31:0] i_instr, // Instruction Fetched in IF stage
input wire signed [31:0] i_write_data, // Data to be written to register file from the WB stage
input wire [31:0] i_pc, // PC of the current instruction
input wire i_wr, // write enable signal from the WB stage, enables the register file to write to rd.
output reg [31:0] o_rs1_data, // rs1 data from register file
output reg [31:0] o_rs2_data, // rs2 data from register file
output reg [31:0] o_imm_data, // sign extended immediate value
output reg [6:0] o_opcode, // opcode of the current instruction
output reg [2:0] o_func3, // func3 of the current instruction
output reg [3:0] o_alu_ctrl, // ALU Control signals  
output reg [31:0] o_pc,// PC for the next stage
output reg [31:0] branch_pc, 
output reg [4:0] o_rs1,
output reg [4:0] o_rs2,
output reg [4:0] o_rd,
output reg [4:0] o_is_rs1,// To execute stage
output reg [4:0] o_is_rs2,// To execute stage
output reg o_is_branch,// To execute stage
// pipeline control
input wire i_prediction, // Prediction signal from Fetch stage
input wire i_stall, // stall signal from EX stage 
input wire i_forward_branch,
input wire [31:0] i_EX_result,// Result after stall and forward from EX stage
input wire i_decode_forward_rs1,
input wire i_decode_forward_rs2,
output reg o_stall, // stall signal to IF stage
output reg o_flush // Flush signal to IF depending on branch decision
);

// Internal Wires
wire [4:0] is_rs1, is_rs2, is_rd;
wire [6:0] is_opcode;
wire [2:0] is_func3;
wire is_re;
wire [3:0] is_alu_ctrl;
wire [31:0] is_rs1_data;
wire [31:0] is_rs2_data; 
wire  [31:0] is_imm;
wire is_boj;
wire [31:0] is_branch_pc;
wire [31:0] is_pc;
wire [31:0] is_rs1_d;
wire [31:0] is_rs2_d;

// Internal Registers
reg [31:0] ir_instr; // used for decoding
reg ir_flush; // internal register used to flush contents 

// Debug Display Statements
always @(posedge clk) begin
   // $display("Time: %0t", $time);
    //$display("is_rs1: %b, is_rs2: %b, is_rd: %b", is_rs1, is_rs2, is_rd);
    //$display("is_opcode: %b, is_func3: %b", is_opcode, is_func3);
    //$display("is_re: %b, is_alu_ctrl: %b", is_re, is_alu_ctrl);
    $display("is_rs1_d: %h, is_rs2_d: %h", is_rs1_d, is_rs2_d);
    //$display("is_imm: %h, is_boj: %b", is_imm, is_boj);
    //$display("ir_flush: %b", ir_flush);
    //$display("is_branch_pc: %h", is_branch_pc);
    $display("ir_instr: %h", ir_instr);
    
end


//Registering instruction 
always@(*)
begin
	
	if(ir_flush == 0) begin
		ir_instr <= i_instr;
	end
	
end

// Decode of instructions
assign is_rs1= ir_instr[19:15];
assign is_rs2=  ir_instr[24:20];
assign is_rd = ir_instr[11:7];
assign is_opcode =  ir_instr[6:0];
assign is_func3 =  ir_instr[14:12];
assign is_re =    (~((is_opcode == `J) | (is_opcode == `U) | (is_opcode == `UPC))); // every instruction except LUI, AUIPC and JAL requires register file to be read
assign is_pc = i_pc;
// Mux Before Branch/Jump decision unit
assign is_rs1_d = (i_decode_forward_rs1 == 1'b1 && i_forward_branch == 1) ? i_EX_result: is_rs1_data; 
assign is_rs2_d = (i_decode_forward_rs2 == 1'b1 && i_forward_branch == 1) ? i_EX_result:is_rs2_data; 
//Pipeing the signals to next stage
always@(posedge clk or negedge rst_n)
begin
	if(~rst_n) begin
		ir_instr <= `NOP;
	end
	else if(!(i_stall || is_boj))begin // pipe through signals when stage is  not stalled and not flushed
		o_rs1_data <= is_rs1_data;
		o_rs2_data <= is_rs2_data;
		o_imm_data <= is_imm;
		o_opcode <= is_opcode;
		o_func3 <= is_func3;
		o_alu_ctrl <= is_alu_ctrl;
		o_rs1 <= is_rs1;
		o_rs2 <= is_rs2;
		o_rd  <= is_rd;
	end
	// Internal Flush Condition
	/*if(ir_flush) begin
		ir_instr <= `NOP;// Every new cycle (if branch/jump) ir_instr is being flushed with NOP,so is interal wires
	end*/
	
      
end
always@(*)
begin
	//Outputs to execute stage when there is branch and to check dependency
	if(is_opcode == `B) begin
		o_is_branch = 1'b1;
		o_is_rs1 = is_rs1;
		o_is_rs2 = is_rs2;
	end
	else begin
		o_is_branch = 1'b0;
		o_is_rs1 = 5'b0;
		o_is_rs2 = 5'b0;
	end
	
	o_flush = (i_prediction ^ is_boj);//Flush the Fetch stage if prediction is wrong
	o_stall = i_stall;
	branch_pc = is_branch_pc;
	ir_flush = is_boj;
	
end

branch_jump_decision branch_jump_decision_inst(		       
	.is_rs1_data(is_rs1_d),
	.is_rs2_data(is_rs2_d),
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

imm_gen imm_gen_inst(
	.i_instr(ir_instr),
	.o_imm_data(is_imm)
);

control_unit control_unit_inst (
	.i_instr(ir_instr),
	.o_alu_ctrl(is_alu_ctrl)
);
endmodule
