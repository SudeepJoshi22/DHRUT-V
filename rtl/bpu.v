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
input wire i_is_branch,
input wire [`N-1:0] i_branch_pc, // PC of the branch instruction	 
input wire [`N-1:0] i_offset_pc, // PC of the instruction to which the branch is jumping to(will come from ID stage)
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
reg [1:0] ir_next_state;
reg [`N-1:0] ir_branch_pc;
reg ir_hit;
reg [`INDEX_WIDTH-1] ir_index;
reg ir_is_branch;

// Index the table based on the PC
assign is_index = i_branch_pc[`INDEX_WIDTH-1:0];

// Check if an BHT entry exists for the index
assign is_hit = (i_branch_pc == branch_pc[is_index]);

// If hit -> give prediction -> update the table when the actual decision comes from ID
// IF miss -> predict as WNT(defult reset entry to FSM) -> update the table
always @(*) begin
	ir_current_state = global_history[index];
end	

assign o_prediction = (ir_current_state == `WT) || (ir_current_state == `ST); // predict taken if the state is either WT or ST

// BHT Reset
always @(posedge clk) begin
	if(~rst_n) begin 
		for(i=0; i<TABLE_DEPTH; i=i+1) begin
			branch_pc[i] <= 0;
			offset_pc[i] <= 0;
			global_history[i] <= `WNT;
		end
	end	
	else if(is_hit) begin
		
	end
end

//  Buffer the information about the branch to update the table after one clock cycle
always @(posedge clk) begin
	if(~rst_n) begin
		ir_branch_pc <= 32'd0;
		ir_hit <= 1'b0;
		ir_index <= 0;
		ir_is_branch <= 1'b0;
	end
	else if(is_hit) begin
		ir_branch_pc <= i_branch_pc;
		ir_hit <= is_hit;	
		ir_index <= is_index;
		ir_is_branch <= i_is_branch;
	end
	else begin
		ir_branch_pc <= ir_branch_pc;
		ir_hit <= ir_hit;
		ir_index <= ir_index;
		ir_is_branch <= ir_is_branch;
	end
end

// Update the table
always @(posedge clk) begin
	if((~ir_hit) && ir_is_branch ) begin // If it is a miss and the instruction is actually branch, create new entry in the table
		branch_pc[ir_index] <= ir_branch_pc;
		offset_pc[ir_index] <= i_offset_pc;
	end
	else if( ir_hit && ir_is_branch) begin // If it is a hit and the instruction is actually branch, upate the global history
		global_history[ir_index] <= i_actually_taken ? (global_history[ir_index] == ST ? ST : global_history[ir_index] + 1) : 
                                            		       (global_history[ir_index] == SNT ? SNT : global_history[ir_index] - 1);
	end
	else begin // If it is not a branch, then do nothing
		branch_pc[ir_index] <= branch_pc[ir_index];
		offset_pc[ir_index] <= offset_pc[ir_index];
		global_history[ir_index] <= global_history[ir_index];
	end
end

endmodule
