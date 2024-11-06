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

// FSM States
`define SNT 2'b00 	// Strongly not-taken
`define WNT 2'b01	// Weakly not-taken
`define WT 2'b10 	// Weakly taken 
`define ST 2'b11	// Strongly taken

// Branch History Table Configs
`define TABLE_DEPTH 256
`define INDEX_WIDTH 8

module bpu(
input wire clk,
input wire rst_n,
input wire i_is_branch,
input wire [`N-1:0] i_branch_pc, // PC of the branch instruction	 
input wire [`N-1:0] i_offset_pc, // PC of the instruction to which the branch is jumping to(will come from ID stage)
input wire i_actually_taken,	 // Result of the branch, from ID stage(DHRUT-V) 
output wire o_prediction,
output wire [`N-1:0] o_predicted_pc
);

// Branch History Table
reg [`N-1:0] branch_pc [0:`TABLE_DEPTH-1];
reg [`N-1:0] offset_pc [0:`TABLE_DEPTH-1];
reg [1:0] global_history [0:`TABLE_DEPTH-1];
integer i;

// Internal Wires
wire [`INDEX_WIDTH-1:0] is_index;
wire is_hit;
// Internal Regs
reg [1:0] ir_next_state;
reg [`N-1:0] ir_branch_pc;
reg ir_hit;
reg [`INDEX_WIDTH-1:0] ir_index;
reg ir_is_branch;

// Index the table based on the PC
assign is_index = i_branch_pc[`INDEX_WIDTH-1:0];

// Check if an BHT entry exists for the index
assign is_hit = (i_branch_pc == branch_pc[is_index]) & i_is_branch;

// If hit -> give prediction -> update the table when the actual decision comes from ID
// IF miss -> predict as WNT(defult reset entry to FSM) -> update the table

assign o_prediction = (ir_hit && ir_is_branch) ? ((global_history[ir_index] == `WT) || (global_history[ir_index] == `ST)) : 'd0; // predict taken if the state is either WT or ST
assign o_predicted_pc = (ir_hit && ir_is_branch) ? offset_pc[ir_index] : 'dz ;

// BHT Reset
always @(posedge clk) begin
	if(~rst_n) begin 
		for(i=0; i<`TABLE_DEPTH; i=i+1) begin
			branch_pc[i] <= 0;
			offset_pc[i] <= 0;
			global_history[i] <= `WNT;
		end
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
	else if(i_is_branch) begin
		ir_branch_pc <= i_branch_pc;
		ir_hit <= is_hit;	
		ir_index <= is_index;
		ir_is_branch <= i_is_branch;
	end
	else begin
		ir_branch_pc <= 'd0;
		ir_hit <= 'd0;
		ir_index <= 'd0;
		ir_is_branch <= 'd0;
	end
end

// Update the table

always @(posedge clk) begin
	if((~ir_hit) && ir_is_branch ) begin // If it is a miss and the instruction is actually branch, create new entry in the table
		branch_pc[ir_index] <= ir_branch_pc;
		offset_pc[ir_index] <= i_offset_pc;
`ifdef SIM
		//$display("Cycle %0t: New branch entry created at index %0d with branch_pc = %h, offset_pc = %h", $time, ir_index, ir_branch_pc, i_offset_pc);
`endif
	end
	else if( ir_hit && ir_is_branch) begin // If it is a hit and the instruction is actually branch, update the global history
		global_history[ir_index] <= i_actually_taken ? 
                                    (global_history[ir_index] == `ST ? `ST : global_history[ir_index] + 1) : 
                                    (global_history[ir_index] == `SNT ? `SNT : global_history[ir_index] - 1);
`ifdef SIM
		//$display("Cycle %0t: Branch hit at index %0d. branch_pc = %h, Updated global history = %d", $time, ir_index, ir_branch_pc, global_history[ir_index]);
`endif
	end
	else begin // If it is not a branch, then do nothing
		branch_pc[ir_index] <= branch_pc[ir_index];
		offset_pc[ir_index] <= offset_pc[ir_index];
		global_history[ir_index] <= global_history[ir_index];
`ifdef SIM
		//$display("Cycle %0t: Non-branch instruction at index %0d. No updates made.", $time, ir_index);
`endif
	end
end
endmodule
