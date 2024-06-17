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

module Fetch(
input wire clk,
input wire rst_n,
output reg [31:0] o_pc, //Current PC value
output reg [31:0] o_instr,
//Instruction memory interface
input wire [31:0] i_inst, //instruction code received from the instruction memory
input wire i_imem_rdy,
input wire i_imem_vld,
output wire i_imem_en,
output wire i_imem_rd,
output reg [31:0] o_iaddr, //instruction address
//Change in PC
input wire i_boj,
input wire [31:0] i_boj_pc,
input wire i_trap,
input wire i_trap_pc,
//Branch Prediction
output reg o_prediction,
//Pipeline control
output reg o_ce,
input wire i_stall,
input wire i_flush
);

//only for simulation
`ifdef SIM
integer fd;
`endif

//Internal signals
wire is_stall;
wire [31:0] is_pc_increment;
wire is_branch;
wire is_prediction;
wire [31:0] is_predicted_pc;

//Internal Registers
reg [31:0] pc;
reg [31:0] ir_inst;

// If the instruction is branch or not
assign is_branch = (i_inst[6:0] == `B);


// PC Change Logic
always @(posedge clk) begin
	if(~rst_n) begin
		pc <= `PC_RESET;
	end
	else if(is_branch & is_prediction) begin
		pc <= is_predicted_pc;
	end
	else if(i_trap) begin
		pc <= i_trap_pc;
	end
	else begin
		pc <= pc + 32'd4;
	end
end

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
