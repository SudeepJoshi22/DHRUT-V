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
	input 	wire	[4:0]			i_rd,
	input 	wire 	[`ADDR_WIDTH-1:0]	i_pc,
	input 	wire 	[3:0] 			i_alu_ctrl,
	input 	wire 	[2:0] 			i_func3,
	input 	wire 	[6:0] 			i_opcode,
	input 	wire				i_id_valid,
	output	wire				o_stall,
	/*** Execute-Memory Stage Interface ***/
	input	wire				i_stall,
	output 	wire 	[`N-1:0] 		o_result,
	output 	wire 	[`N-1:0] 		o_data_store,
	output 	wire 	[`ADDR_WIDTH-1:0] 	o_pc,
	output 	wire 	[2:0] 			o_func3,
	output	wire	[4:0]			o_rd,
	output 	wire 	[6:0] 			o_opcode,
	output	wire				o_ex_valid
);

	//// Internal Wires ////
	wire 	[`N-1:0] 		is_op1, is_op2;
	wire 	[`N-1:0]		is_alu_result;
	wire 	[`N-1:0]		is_data_store;
	wire 				is_ce;

	//// Internal Registers ////
	reg				ir_decode_stall;

	//// Pipeline Registers ////
	reg	[`N-1:0] 		pipe_result;
	reg	[`N-1:0] 		pipe_data_store;
	reg	[`ADDR_WIDTH-1:0] 	pipe_pc;
	reg	[4:0]			pipe_rd;
	reg	[2:0] 			pipe_func3;
	reg	[6:0] 			pipe_opcode;
	reg				pipe_ex_valid;


	/*** ALU ***/

	// MUX before the ALU
	assign is_op1 = (i_opcode == `UPC) ? i_pc : i_rs1_data;
	assign is_op2 = ((i_opcode == `R) | (i_opcode == `B)) ? i_rs2_data : i_imm_data; 

	alu alu_inst (
		.i_op1(is_op1),
		.i_op2(is_op2),
		.i_alu_ctrl(i_alu_ctrl),
		.o_result(is_alu_result)
	);

	// Data to store into Data Memory
	assign is_data_store = (i_opcode == `S) ? i_rs2_data : 32'd0;

	/*** Pipelining the Values for Next Stage ***/

	// Stage Enable Signal
	assign is_ce = rst_n && ~i_stall && i_id_valid;

	always @(posedge clk, negedge rst_n) begin
		if(is_ce) begin	
			pipe_result	<= is_alu_result;
			pipe_data_store <= is_data_store; 
			pipe_pc		<= i_pc;
			pipe_rd		<= i_rd;
			pipe_func3	<= i_func3;
			pipe_opcode	<= i_opcode;
			pipe_ex_valid	<= is_ce;
			ir_decode_stall <= ~is_ce;
		end
		else if(~rst_n) begin
			pipe_result	<= 0; 
			pipe_data_store <= 0;  
			pipe_pc		<= 0; 
			pipe_rd		<= 0; 
			pipe_func3	<= 0; 
			pipe_opcode	<= 0; 
			pipe_ex_valid	<= 0; 
			ir_decode_stall <= 0; 
		end
	end

	assign	o_result	=	pipe_result;	
	assign	o_data_store 	= 	pipe_data_store; 
	assign	o_pc		=	pipe_pc;
	assign	o_rd		=	pipe_rd;		
	assign	o_func3	  	=	pipe_func3;	
	assign	o_opcode	=  	pipe_opcode;	
	assign	o_ex_valid	=  	pipe_ex_valid;	

	assign	o_stall		=	ir_decode_stall;
	
	/*
	branch_decision branch_dec_inst (
		.i_result(o_result),
		.i_func3(i_func3),
		.o_branch(is_branch)
	);
	*/


endmodule 
