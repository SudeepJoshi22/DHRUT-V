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
	input wire [31:0] i_instr, //instruction code received from the instruction memory
	output wire o_imem_rdy,
	input wire i_imem_vld,
	output reg [31:0] o_iaddr, //instruction address
	// IF-CSr Interface(current not in place)
	input wire i_trap,
	input wire [31:0] i_trap_pc,
	// IF-ID Interface
	input wire i_boj,
	input wire [31:0] i_boj_pc,
	output reg [31:0] o_pc, //Current PC value
	output reg [31:0] o_instr,
	output reg o_prediction,
	// Pipeline control
	input wire i_stall,
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
reg [31:0] pc;
reg [31:0] ir_instr;

// If the instruction is branch or not
assign is_branch = (i_instr[6:0] == `B);

// Instruction memory ready interface
assign o_imem_rdy = (~i_stall & i_imem_vld) ? 1'b1 : 1'b0;

// Update the instruction address for memory interface
always @(*) begin
    if (~rst_n) begin
        o_iaddr = `PC_RESET;
    end 
    else if (~i_stall & i_imem_vld) begin
        o_iaddr = pc;
    end
    else begin
    	o_iaddr = 32'd0;
    end
end


always @(*) begin
    if (~rst_n) begin
        ir_instr = `NOP;
    end 
    else if (i_imem_vld) begin
        ir_instr = i_instr;
    end
    else begin
    	ir_instr = 32'd0;
    end
end

// PC Change Logic
always @(posedge clk) begin
	if(~rst_n) begin
		pc <= `PC_RESET;
	end
	else if(i_flush) begin
		pc <= pc;
	end
	else if(is_branch & is_prediction) begin
		pc <= is_predicted_pc;
	end
	else if(i_trap) begin
		pc <= i_trap_pc;
	end
	else if(~i_stall) begin
		pc <= pc + 32'd4;
	end
	else begin
		pc <= pc;
	end
end

// Pipeing the signals for next stage
always @(posedge clk) begin
	if (~rst_n | i_flush) begin
		o_pc <= 0;
		o_instr <= `NOP;
		o_prediction <= 0;		
	end
	else if(i_stall) begin
		o_pc <= o_pc;
		o_instr <= o_instr;
		o_prediction <= o_prediction;
	end
	else begin
		o_pc <= pc;
		o_instr <= ir_instr;
		o_prediction <= is_prediction;
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

always@(posedge clk) begin
	$display("ir_instr %b :",ir_instr);
end
	
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
