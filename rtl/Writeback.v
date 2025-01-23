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

module Writeback(
	input 	wire 				clk,
	input 	wire 				rst_n,
	/*** WriteBack-Memory Stage Interface ***/
	input	wire	[4:0]			i_rd,
	input 	wire 	[6:0] 			i_opcode,
	input 	wire 	[`N-1:0] 		i_wb_data,
	input	wire				i_mem_vld,
	/*** WriteBack-Decode Stage Interface ***/ 
	output 	wire 				o_rf_wr, 	// write enable for register file 
	output	wire	[4:0]			o_rf_rd,	// Register Address to write into
	output 	wire 	[`N-1:0] 		o_rf_data 	// data to be written to Register file

);

	//// Internal Wires ////
	wire			is_ce;
	wire	[4:0]		is_rd;
	wire			is_rf_wr;
	wire	[`N-1:0]	is_rf_data;
	
	//// Pipeline Registers ////
	reg			pipe_rf_wr;
	reg	[4:0]		pipe_rf_rd;
	reg	[`N-1:0]	pipe_rf_data;

	// Stage Enable
	assign		is_ce		=	rst_n && i_mem_vld;

	// Register File Signals	
	assign 		is_rf_wr 	= 	((i_opcode == `B) | (i_opcode == `S)) ? 1'b0 : 1'b1;
	assign 		is_rf_data 	= 	(o_rf_wr & rst_n) ? i_wb_data : 32'd0;
	
	/*** Pipelining the Values for Next Stage ***/
	always @(posedge clk, negedge rst_n) begin
		if(is_ce) begin
			pipe_rf_wr	<=	is_rf_wr;
			pipe_rf_rd	<=	i_rd;
			pipe_rf_data	<=	is_rf_data;
		end
	end
	
	assign		o_rf_wr		=	pipe_rf_wr;
	assign		o_rf_rd		=	pipe_rf_rd;
	assign		o_rf_data	=	pipe_rf_data;

endmodule
