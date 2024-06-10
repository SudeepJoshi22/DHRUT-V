 /*
   Copyright 2024 Sudeep Joshi Et al.

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

// FSM States
`define SNT 2'b00 	// Strongly not-taken
`define WNT 2'b01	// Weakly not-taken
`define WT 2'b10 	// Weakly taken 
`define ST 2'b11	// Strongly taken

// Branch History Table Configs
`define TABLE_DEPTH 256
`define INDEX_WIDTH $clog2(TABLE_DEPTH)

module bpu(
input wire clk,
input wire rst_n,
input wire [`N-1:0] i_branch_pc, // PC of the branch instruction	 
input wire [`N-1:0] i_offset_pc, // PC of the instruction to which the branch is jumping to
input wire i_actually_taken,	 // Result of the branch, from ID stage(DHRUT-V) 
output wire o_prediction,
output wire o_predicted_pc
);

// Branch History Table
reg [`N-1:0] branch_pc [0:TABLE_DEPTH-1];
reg [`N-1:0] offset_pc [0:TABLE_DEPTH-1];
reg [1:0] global_history [0:TABLE_DEPTH-1];
integer i;

// Internal Wires
wire [`INDEX_WIDTH-1:0] is_index;
wire is_hit;
// Internal Regs

// BHT Reset
always @(posedge clk, negedge rst_n) begin
	if(~rst_n) begin
		for(i=0; i<TABLE_DEPTH; i=i+1) begin
			branch_pc[i] <= 0;
			offset_pc[i] <= 0;
			global_history[i] <= WNT;
		end
	end	
end

// Index the table based on the PC
assign is_index = i_branch_pc[`INDEX_WIDTH-1:0];

// Check if an BHT entry exists for the index
assign is_hit = (i_branch_pc == branch_pc[is_index]);


endmodule
