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

module Memory(
	input 	wire 				clk,
	input 	wire 				rst_n,
	/*** Memory-Execute Stage Interface ***/
	input 	wire 	[`N-1:0] 		i_result,
	input 	wire 	[`N-1:0] 		i_data_store,
	input 	wire 	[`ADDR_WIDTH:0] 	i_pc,
	input 	wire 	[2:0] 			i_func3,
	input 	wire 	[4:0] 			i_rd,
	input 	wire 	[6:0] 			i_opcode,
	input 	wire				i_ex_valid,
	output	wire				o_stall,
	/*** Memory-WriteBack Stage Interface ***/
	output 	wire 	[4:0] 			o_wb_rd,
	output 	wire 	[6:0] 			o_opcode,
	output 	wire 	[31:0] 			o_wb_data, // write back value can be result, data read or pc depending on the opcode
	/*** Data-Memory Interface ***/
    	input 	wire  	[`N-1:0]  		i_rdata,    // 32-bit Read data
    	input  	wire          			i_d_valid  // Valid signal 
    	output  wire         			o_wr_en,    // Write enable signal
    	output  wire 	[3:0]   		o_sel,      // Select signal for byte-enable (4 bits for 32-bit word)
    	output  wire 	[`ADDR_WIDTH-1:0] 	o_addr,     // 32-bit Address signal
    	output  wire				o_addr_vld,
    	output  wire 	[`N-1:0]  		o_wdata    // 32-bit Write data
);
	
	//// Internal Wires ////
	wire 				is_ce;
	wire				is_stall;

	//// Internal Registers ////
	reg				ir_memory_stall;

	//// Pipeline Registers ////
	reg	[4:0]			pipe_wb_rd;
	reg	[6:0]			pipe_opcode;
	reg	[`N-1:0]		pipe_wb_data; // write back value can be result, data read or pc depending on the opcode

	// Internal Stall
	assign	is_stall	= 	~i_d_valid;


	/*** Pipelining the Values for Next Stage ***/

	// Stage Enable Signal
	assign is_ce = rst_n || ~is_stall || i_ex_valid;

	always @(posedge clk, negedge rst_n) begin
		if(is_ce) begin
			pipe_wb_rd	<= 	i_rd;
			pipe_opcode	<= 	i_opcode;
			pipe_wb_data	<= 	is_wb_data;
			ir_memory_stall	<=	is_ce;
		end
	end

	assign	o_wb_rd		= 	pipe_wb_rd;
	assign 	o_opcode	=	pipe_opcode;
	assign	o_wb_data	= 	pipe_wb_data;

	assign	o_stall		= 	ir_memory_stall;


	/*** Data Memory Interaction ***/

endmodule
