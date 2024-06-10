`timescale 1ns / 1ps
`default_nettype none
`include "rtl/parameters.vh"

`define TABLE_DEPTH 256
`define INDEX_WIDTH $clog2(TABLE_DEPTH)

module tb_bpu;

// Inputs
reg clk;
reg rst_n;
reg i_is_branch;
reg [`N-1:0] i_branch_pc;
reg [`N-1:0] i_offset_pc;
reg i_actually_taken;

// Outputs
wire o_prediction;
wire [`N-1:0] o_predicted_pc;

bpu bpu(
    .clk(clk),
    .rst_n(rst_n),
    .i_is_branch(i_is_branch),
    .i_branch_pc(i_branch_pc),
    .i_offset_pc(i_offset_pc),
    .i_actually_taken(i_actually_taken),
    .o_prediction(o_prediction),
    .o_predicted_pc(o_predicted_pc)
);

initial begin
	$dumpfile("waveform.vcd");
	$dumpvars(0, tb_bpu);
end

// Clock generation
always #5 clk = ~clk;

// Test sequences
initial begin
	// Initialize inputs
	clk = 0;
	rst_n = 0;
	i_is_branch = 0;
	i_branch_pc = 0;
	i_offset_pc = 0;
	i_actually_taken = 0;

	// Reset the BPU
	#10;
	rst_n = 1;

	// Wait for reset de-assertion
	#10;

	// Test case 1: Branch not taken (first encounter, default state is W`NT)
	i_is_branch = 1;
	i_branch_pc = 32'h00000010;
	i_offset_pc = 32'h00000020;
	i_actually_taken = 0; // not taken
	#10;

	// Test case 2: Branch taken (first encounter, default state is W`NT)
	i_branch_pc = 32'h00000014;
	i_offset_pc = 32'h00000028;
	i_actually_taken = 1; // taken
	#10;

	// Test case 3: Branch not taken again (should update history)
	i_branch_pc = 32'h00000010;
	i_actually_taken = 0; // not taken
	#10;

	// Test case 4: Branch taken again (should update history)
	i_branch_pc = 32'h00000014;
	i_actually_taken = 1; // taken
	#10;

	// Test case 5: `New branch not taken (default W`NT)
	i_branch_pc = 32'h00000018;
	i_offset_pc = 32'h00000030;
	i_actually_taken = 0; // not taken
	#10;

	// End simulation
	#50
	$finish;
end

endmodule
