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

module Execute(
	input 	wire 				clk,
	input 	wire 				rst_n,
	/*** Execute-Decode Stage Interface ***/
	input 	wire 	[`N-1:0] 		i_rs1_data,
	input 	wire 	[`N-1:0] 		i_rs2_data,
	input 	wire 	[`N-1:0]		i_imm_data,
	input 	wire 	[`ADDR_WIDTH-1:0]	i_pc,
	input 	wire 	[3:0] 			i_alu_ctrl,
	input 	wire 	[2:0] 			i_func3,
	input 	wire 	[6:0] 			i_opcode,
	input 	wire				i_id_valid,
	output	wire				o_stall,
	/*** Execute-Memory Stage Interface ***/
	input 	wire 	[4:0] 			i_rd_mem, // input required for MEM to EX forwarding
	input wire [31:0] i_mem_result, // input required for stall and forward due to dependency of branch/jump instruction
	output reg [31:0] o_result, // must be forwarded to both IF and MEM stages
	output reg [31:0] o_data_store,
	output reg [2:0] o_func3,
	output reg [6:0] o_opcode,
	output reg [4:0] o_rd,
);

	//// Internal Wires ////
	wire [`N-1:0] 		is_op1, is_op2;

	wire 			is_ce;
	//// Internal Registers ////


	//// Pipeline Registers ////



	/*** ALU ***/

	// MUX before the ALU
	assign is_op1 = (i_opcode == `UPC) ? i_pc : i_rs1_data;
	assign is_op2 = ((i_opcode == `R) | (i_opcode == `B)) ? i_rs2_data : i_imm_data; 

	alu alu_inst (
		.i_op1(is_op1),
		.i_op2(is_op2),
		.i_alu_ctrl(i_alu_ctrl),
		.o_result(o_result)
	);



// Data to store into Data Memory
assign o_data_store = (i_opcode == `S) ? i_rs2_data : 32'd0;

assign o_func3 = i_func3;
assign o_opcode = i_opcode;
assign o_pc = i_pc;

/*
branch_decision branch_dec_inst (
	.i_result(o_result),
	.i_func3(i_func3),
	.o_branch(is_branch)
);
*/


endmodule 
