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
	input wire clk,
	input wire rst_n,
	// EX-MEM interface
	input wire [31:0] i_result,
	input wire [31:0] i_data_store,
	input wire [31:0] i_pc,
	input wire [6:0] i_opcode,
	input wire [2:0] i_func3,
	input wire [4:0] i_rd,
	output reg [4:0] o_ex_rd, // For forwarding unit
	output reg [31:0] o_mem_data_val, // Loaded Value, or Buffered result from EXE 
	// MEM-WB Interfacue
	output wire [4:0] o_wb_rd,
	output wire [31:0] o_wb_data, // write back value can be result, data read or pc depending on the opcode
	output wire [6:0] o_opcode,
	// Data-Memory Interface
        output wire o_wr_en,    		// Write enable signal
        output wire [3:0] o_sel,		// Select signal for byte-enable (4 bits for 32-bit word)
        output wire [31:0] o_daddr,    		// 32-bit Address signal
        output wire [31:0] o_write_data,    	// 32-bit Write data
        input wire [31:0] i_read_data,    	// 32-bit Read data
        output wire o_d_ready,  		// Ready signal for data transfer
        input wire i_d_valid,  			// Valid signal for data transfer
        input wire i_error     			// Error signal for invalid accesses
);
	
	// Internal Signals
	wire is_stall;
	wire [31:0] is_wb_data;
	// Internal Registers
	reg [4:0] ir_wb_rd;
	reg [6:0] ir_opcode;
	reg [31:0] ir_wb_data;

	// Data Memory Interface
	assign o_wr_en = (i_opcode == `S);
	assign o_daddr	
 
	// Data Muxing for WB stage
	assign is_wb_data = (i_opcode == `LD) ? i_read_data : i_result;
 
	// Pipeline the signals
	always @(posedge clk, negedge rst_n) begin
		if(!rst_n) begin
			ir_wb_rd <= 0;
			ir_opcode <= 0;
			ir_wb_data <= 0;
		end
		else if(is_stall) begin
			ir_wb_rd <= ir_wb_rd;
			ir_opcode <= ir_opcode;
			ir_wb_data <= ir_wb_data;
		end
		else begin
			ir_wb_rd <= i_rd;	
			ir_opcode <= i_opcode;
			ir_wb_data <= is_wb_data;
		end
	end

endmodule
