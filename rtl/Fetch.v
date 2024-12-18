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

module Fetch(
	input wire clk,
	input wire rst_n,
	// Instruction memory interface
	input wire [31:0] i_rom_instr,
	input wire i_instr_vld,
	output wire [31:0] o_iaddr,
	output wire o_fetch_rdy,
	// IF-CSr Interface(current not in place)
	input wire i_trap,
	input wire [31:0] i_trap_pc,
	// IF-ID Interface
	input wire i_boj,
	input wire [31:0] i_boj_pc,
	output wire [31:0] o_pc, //Current PC value
	output wire [31:0] o_instr,
	output wire o_prediction,
	// Pipeline control
	input wire i_stall,
	input wire [31:0] i_flush_pc,
	input wire i_flush
);

//only for simulation
`ifdef SIM
integer fd;
`endif

//Internal signals
wire is_stall;
wire is_branch;
wire is_prediction;
wire [31:0] is_predicted_pc;

//Internal Registers
reg [31:0] pc; // Current-PC counter
reg [31:0] ir_instr;
reg ir_instr_latch;
reg [31:0] ir_pc; 
reg ir_prediction;

// If the instruction is branch or not
assign is_branch = (i_rom_instr[6:0] == `B);

// Generate Address for the Instruction ROM(producer)
assign o_fetch_rdy = (~i_stall & ~i_flush & rst_n);
assign o_iaddr = pc; 	

// PC Change Logic
always @(posedge clk or negedge rst_n) begin
	if(~rst_n) begin
		pc <= `PC_RESET;
	end
	else if(i_flush) begin 
		pc <= i_flush_pc;
	end
	else if(i_trap) begin
		pc <= i_trap_pc;
	end
	else if(i_boj) begin
		pc <= i_boj_pc;
	end
	else if(is_branch & is_prediction) begin
		pc <= is_predicted_pc;
	end
	else if(~i_stall & rst_n) begin
		pc <= pc + 32'd4;
	end
	else begin
		pc <= pc;
	end
end

// Pipeing the signals for next stage
always @(posedge clk or negedge rst_n) begin
    if (~rst_n | i_flush) begin
        ir_instr <= `NOP;
        ir_pc <= 32'd0;
        ir_prediction <= 0;
    end 
    else if(i_instr_vld & ~i_stall) begin
    	ir_instr <= i_rom_instr;
    	ir_pc <= o_iaddr;
    	ir_prediction <= is_prediction;
    end
    else if(i_flush) begin
	ir_instr <= `NOP;
    	ir_pc <= 0;
    	ir_prediction <= 0;
    end
    else begin
    	ir_instr <= ir_instr;
    	ir_pc <= ir_pc;
    	ir_prediction <= ir_prediction;
    end
end

// Output
assign o_instr = ir_instr;
assign o_pc = ir_pc;
assign o_prediction = ir_prediction;

// Branch-Prediction
bpu branch_prediction_unit (
	.clk(clk),
	.rst_n(rst_n),
	.i_is_branch(is_branch),
	.i_branch_pc(pc),
	.i_offset_pc(i_boj_pc),
	.i_actually_taken(i_boj),
	.o_prediction(is_prediction),
	.o_predicted_pc(is_predicted_pc)
);
	
//only for simulation
`ifdef SIM
always @(o_pc,o_instr)
begin	
	#2
	if(rst_n)
	begin
		fd = $fopen("IF_log.csv","ab+");
		$fwrite(fd,"%h,%h\n",o_pc,o_instr);
		$fclose(fd);
	end
end

`endif

endmodule
