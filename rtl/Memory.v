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

module Memory(
	input 	wire 				clk,
	input 	wire 				rst_n,
	/*** Memory-Execute Stage Interface ***/
	input 	wire 	[`N-1:0] 		i_result,
	input 	wire 	[`N-1:0] 		i_data_store,
	input 	wire 	[`ADDR_WIDTH-1:0] 	i_pc,
	input 	wire 	[2:0] 			i_func3,
	input 	wire 	[4:0] 			i_rd,
	input 	wire 	[6:0] 			i_opcode,
	input 	wire				i_ex_valid,
	output	wire				o_stall,
	/*** Memory-WriteBack Stage Interface ***/
	output 	wire 	[4:0] 			o_wb_rd,
	output 	wire 	[6:0] 			o_opcode,
	output 	wire 	[31:0] 			o_wb_data, // write back value can be result, data read or pc depending on the opcode
	output	wire				o_mem_vld,
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
	wire				is_wb_data;

	//// Internal Registers ////
	reg				ir_memory_stall;
	reg				ir_sel;

	//// Pipeline Registers ////
	reg				pipe_mem_vld;
	reg	[4:0]			pipe_wb_rd;
	reg	[6:0]			pipe_opcode;
	reg	[`N-1:0]		pipe_wb_data; // write back value can be result, data read or pc depending on the opcode

	// Internal Stall
	assign	is_stall	= 	~i_d_valid;

	/*** Data Memory Interaction Logic ***/

	// Sending the Valid Address if the instruction is a Load or a Store
	assign 	o_wr_en		=	(i_opcode == 'S);	// write to Data Memory if the instruction is store
	assign 	o_wdata		=	o_wr_en ? i_data_store : 'dz;

	assign	o_addr_vld	=	(~is_stall) && ((i_opcode == `LD || i_opcode == 'S));	// Send valid address if the instruction is a Load/Store and the stage is not stalled
	assign	o_addr		=	o_addr_vld ? i_result: 'dz;

	assign 	o_sel		= 	ir_sel;

	// Combinational Case Structure for Select Signal
	always @(*) begin
		case(i_func3)
			`B:		ir_sel		= 	4'b0001;
			`H:		ir_sel		=	4'b0011;
			`W:		ir_sel		=	4'b1111;
			default:	ir_sel		=	4'b1111;
		endcase
	end

	// Selecting the data loaded from data-memory
	assign	is_wb_data	=	(i_func3 == `B) ? {{24{i_rdata[7]}},i_rdata[7:0]} : ((i_func3 == `H) ? {{16{i_rdata[15]}},i_rdata[15:0]} : ((i_func3 == `LBU)? {24'd0,i_rdata[7:0]} : ((i_func3 == `LHU) ? {16'd0,i_rdata[15:0]} : i_rdata)));

	/*** Pipelining the Values for Next Stage ***/

	// Stage Enable Signal
	assign is_ce = rst_n || ~is_stall || i_ex_valid;

	always @(posedge clk, negedge rst_n) begin
		if(is_ce) begin
			pipe_wb_rd	<= 	i_rd;
			pipe_opcode	<= 	i_opcode;
			pipe_wb_data	<= 	is_wb_data;
			pipe_mem_vld	<=	is_ce;
			ir_memory_stall	<=	is_ce;
		end
	end

	assign	o_wb_rd		= 	pipe_wb_rd;
	assign 	o_opcode	=	pipe_opcode;
	assign	o_wb_data	= 	pipe_wb_data;
	assign	o_mem_vld	=	pipe_mem_vld;

	assign	o_stall		= 	ir_memory_stall;


	/*** Data Memory Interaction ***/

endmodule
