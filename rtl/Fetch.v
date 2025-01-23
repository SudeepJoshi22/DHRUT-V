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

module Fetch (
	input 	wire				clk,
	input 	wire 				rst_n,
	/*** Fetch-Decode Stage Interface ***/
	input 	wire				i_stall,
	output 	wire				o_if_pkt_vld,
	output 	wire	[`IF_PKT_WIDTH-1:0]	o_if_pkt_data, 		// IF-Packet => {pc,instruction}	
	/*** PC Redirect Logic 	input wire			
	input wire 			i_boj,
	input wire [`ADDR_WIDTH-1:0] 	i_boj_pc,
	input wire			i_trap,
	input wire [`ADDR_WIDTH-1:0] 	i_trap_pc,
	input wire 			i_flush,
	input wire [`ADDR_WIDTH-1:0] 	i_redir_pc, ***/
	/*** CPU-Memory Interface(AXI-lite compitable master interface) ***/
	output 	wire 	[`ADDR_WIDTH-1:0]	o_iaddr,
	output 	wire 				o_iaddr_vld, 		// Request for instruction when address is valid
	input 	wire	[`INST_WIDTH-1:0]	i_inst,		
	input 	wire				i_inst_vld		// Instruction is obtained when inst_vld is asserted
);

	//// Internal Wires ////
	wire				is_stall;
	wire [`ADDR_WIDTH-1:0]		is_next_pc;
	wire 				is_ce; 				// Clock Enable for the stage

	//// Internal Registers ////
	reg [`ADDR_WIDTH-1:0]		pc;
	reg [`ADDR_WIDTH-1:0]		ir_prev_pc;
	reg [`ADDR_WIDTH-1:0] 		ir_araddr;

	//// Pipeline Registers ////
	reg [`ADDR_WIDTH-1:0]		pipe_pc;
	reg [`INST_WIDTH-1:0]		pipe_inst;
	reg 				pipe_vld;


	// Stage Enable
	assign is_ce = rst_n || ~is_stall;

	/*** PC Control ***/
	always @(posedge clk, negedge rst_n) begin
		if(~rst_n) 
			pc <= `PC_RESET;
		else if(is_ce)
			pc <= is_next_pc; 

	end

	// Capture the Instruction address sent
	always @(posedge clk, negedge rst_n) begin
		if(o_iaddr_vld)
			ir_prev_pc <= o_iaddr;
	end

	assign is_next_pc = is_stall ? pc : pc + 32'd4;

	assign is_stall = ~rst_n || i_stall || i_inst_vld; 			// Stall if Decode is asserting stall or I-MEM has not given instruction yet

	/*** IMEM Logic ***/
	assign o_iaddr = o_iaddr_vld ? o_iaddr : 'dz;
	assign o_iaddr_vld = is_ce; 					// Send a valid address if the stage is enabled

	/*** Pipeline Register ***/
	always @(posedge clk, negedge rst_n) begin
		if(is_ce) 
			pipe_pc <= ir_prev_pc;
			pipe_inst <= i_inst;
			pipe_vld <= is_ce;
	end

	assign o_if_pkt_data = {pipe_pc, pipe_inst};
	assign o_if_pkt_vld = pipe_vld;

endmodule
