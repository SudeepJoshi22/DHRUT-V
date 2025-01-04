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
	input 	wire 					i_wr, 			// write enable signal from the WB stage, enables the register file to write to rd.

	/*** Decode-Execute Stage Interface ***/
	input 	wire					i_stall,
	output 	wire 		[`N-1:0] 		o_rs1_data, 		// rs1 data from register file
	output 	wire 		[`N-1:0] 		o_rs2_data, 		// rs2 data from register file
	output 	wire 		[`N-1:0] 		o_imm_data, 		// sign extended immediate value
	output 	wire 		[6:0] 			o_opcode, 		// opcode of the current instruction
	output 	wire 		[2:0] 			o_func3, 		// func3 of the current instruction
	output 	wire 		[3:0] 			o_alu_ctrl, 		// ALU Control signals  
	output 	wire 		[31:0] 			o_pc, 			// PC for the next stage
	output 	wire					o_id_valid		// Indicates that the signals from Decode Stage are Valid
);

	//// Internal Wires ////

	wire [4:0] is_rs1, is_rs2, is_rd;
	wire [6:0] is_opcode;
	wire [2:0] is_func3;
	wire is_re;
	wire [31:0] is_instr;
	wire [31:0] is_pc;

	//// Internal Registers ////


	//// Pipeline Registers ////

	
	//// Decoding ////
	
	assign is_instr = i_if_pkt_data[31:0];
	assign is_pc = i_if_pkt[63:32];

	assign is_rs1 = is_instr[19:15];
	assign is_rs2 = is_instr[24:20];
	assign is_rd = is_instr[11:7];
	assign is_opcode = is_instr[6:0];
	assign is_func3 = is_instr[14:12];
	assign is_re = ~((is_opcode == `J) | (is_opcode == `U) | (is_opcode == `UPC)); // every instruction except LUI, AUIPC and JAL requires register file to be read


	/*** Register File ***/
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

	/*** Immediate Value Generator ***/
	imm_gen imm_gen_inst (
	  	.i_instr(i_instr),
	  	.o_imm_data(o_imm_data)
	);
	

	/*** Control Unit ***/
	control_unit control_unit_inst (
	  	.i_instr(i_instr),
	  	.o_alu_ctrl(o_alu_ctrl)
	);

endmodule
