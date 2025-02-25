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

module Decode(
	input	wire 					clk,
	input 	wire 					rst_n,
	/*** Decode-Fetch Stage Interface ***/
	input 	wire 		[`IF_PKT_WIDTH-1:0] 	i_if_pkt_data, 		// Instruction Packet Fetched 
	input 	wire 					i_if_pkt_valid,
	output 	wire					o_stall,
	/*** Decode-WriteBack Stage Interface ***/
	input 	wire 	signed 	[`N-1:0] 		i_write_data, 		// Data to be written to register file from the WB stage
	input 	wire		[4:0]			i_rd,
	input 	wire 					i_wr, 			// write enable signal from the WB stage, enables the register file to write to rd.
	/*** Decode-Execute Stage Interface ***/
	input 	wire					i_stall,
	output 	wire 		[`N-1:0] 		o_rs1_data, 		// rs1 data from register file
	output 	wire 		[`N-1:0] 		o_rs2_data, 		// rs2 data from register file
	output 	wire 		[`N-1:0] 		o_imm_data, 		// sign extended immediate value
	output  wire		[4:0]			o_rd,
	output 	wire 		[6:0] 			o_opcode, 		// opcode of the current instruction
	output 	wire 		[2:0] 			o_func3, 		// func3 of the current instruction
	output 	wire 		[3:0] 			o_alu_ctrl, 		// ALU Control signals  
	output 	wire 		[31:0] 			o_pc, 			// PC for the next stage
	output 	wire					o_id_valid		// Indicates that the signals from Decode Stage are Valid
);

	//// Internal Wires ////

	wire [4:0] 		is_rs1, is_rs2, is_rd;
	wire [6:0] 		is_opcode;
	wire [2:0] 		is_func3;
	wire 			is_re;
	wire [31:0] 		is_instr;
	wire [31:0] 		is_pc;
	
	wire [`N-1:0]		is_rs1_data;
	wire [`N-1:0]		is_rs2_data;
	wire [`N-1:0]		is_imm_data;
	wire [3:0]		is_alu_ctrl;

	wire			is_ce;

	//// Internal Registers ////
	reg			ir_fetch_stall;

	//// Pipeline Registers ////
	reg [`N-1:0]		pipe_rs1_data, pipe_rs2_data;
	reg [`N-1:0] 		pipe_imm_data;
	reg [4:0]		pipe_rd;
	reg [6:0] 		pipe_opcode;
	reg [2:0] 		pipe_func3;
	reg [3:0]		pipe_alu_ctrl;
	reg [`ADDR_WIDTH-1:0]	pipe_pc;
	reg			pipe_id_valid;
	
	//// Decoding ////
	assign is_instr = i_if_pkt_data[31:0];
	assign is_pc = i_if_pkt_data[63:32];

	assign is_rs1 = is_instr[19:15];
	assign is_rs2 = is_instr[24:20];
	assign is_rd = is_instr[11:7];
	assign is_opcode = is_instr[6:0];
	assign is_func3 = is_instr[14:12];
	assign is_re = ~((is_opcode == `J) | (is_opcode == `U) | (is_opcode == `UPC)); // every instruction except LUI, AUIPC and JAL requires register file to be read



	//// Pipelining the Values for Next Stage ////
	
	// Stage Enable Signal
	assign is_ce = rst_n && ~i_stall && i_if_pkt_valid;

	always @(posedge clk, negedge rst_n) begin
		if(is_ce) begin
			pipe_rs1_data 	<= is_rs1_data;
			pipe_rs2_data 	<= is_rs2_data;
			pipe_imm_data 	<= is_imm_data;
			pipe_rd	      	<= is_rd;
			pipe_opcode   	<= is_opcode;
			pipe_func3    	<= is_func3;
			pipe_alu_ctrl 	<= is_alu_ctrl;
			pipe_pc	      	<= is_pc;
			pipe_id_valid 	<= is_ce;
			ir_fetch_stall 	<= ~is_ce;
		end
		else if(~rst_n) begin
			pipe_rs1_data 	<= 0; 
			pipe_rs2_data 	<= 0; 
			pipe_imm_data 	<= 0; 
			pipe_rd	      	<= 0; 
			pipe_opcode   	<= 0; 
			pipe_func3    	<= 0; 
			pipe_alu_ctrl 	<= 0; 
			pipe_pc	      	<= 0; 
			pipe_id_valid 	<= 0; 
			ir_fetch_stall 	<= 0; 
		end
	end

	assign o_rs1_data = 	pipe_rs1_data;
	assign o_rs2_data = 	pipe_rs2_data;
	assign o_imm_data = 	pipe_imm_data;
	assign o_rd	  =	pipe_rd;
	assign o_opcode	  =	pipe_opcode;
	assign o_func3    = 	pipe_func3;
	assign o_alu_ctrl = 	pipe_alu_ctrl;
	assign o_pc	  = 	pipe_pc;
	assign o_id_valid = 	pipe_id_valid;

	assign o_stall    = 	ir_fetch_stall;

	/*** Register File ***/
	reg_file reg_file_inst(
		.clk(clk),
		.rst_n(rst_n),
		.i_re(is_re),
		.i_wr(i_wr),
		.i_rs1(is_rs1),
		.i_rs2(is_rs2),
		.i_rd(i_rd),
		.i_write_data(i_write_data),
		.o_read_data1(is_rs1_data),
		.o_read_data2(is_rs2_data)
	);

	/*** Immediate Value Generator ***/
	imm_gen imm_gen_inst (
	  	.i_instr(is_instr),
	  	.o_imm_data(is_imm_data)
	);
	

	/*** Control Unit ***/
	control_unit control_unit_inst (
	  	.i_instr(is_instr),
	  	.o_alu_ctrl(is_alu_ctrl)
	);

endmodule
