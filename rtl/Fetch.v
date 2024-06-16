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

module IF(
input wire clk,
input wire rst_n,
output wire [31:0] o_pc, //Current PC value
output reg [31:0] o_instr,
//instruction memory interface
input wire [31:0] i_inst, //instruction code received from the instruction memory
input wire i_imem_ack, //ack by instruction memory (active high)
output reg o_imem_stb, //stub signal for instruction memroy
output reg [31:0] o_iaddr, //instruction address
//Change in PC
input wire [31:0] i_imm,
input wire [31:0] i_result,
input wire i_boj,
input wire i_jalr
);

//only for simulation
`ifdef SIM
integer fd;
`endif

//internal signals and registers
wire is_stall = !i_imem_ack & rst_n;
wire [31:0] is_pc_increment;
reg [31:0] pc;

assign is_pc_increment = i_boj ? i_imm : ( is_stall ? 32'd0 : 32'd4 );
assign o_pc = pc;

always @(posedge clk)
begin
	if(~rst_n)
	begin
		pc <= `PC_RESET;
	end
	else if(is_stall)
	begin
		pc <= pc;
	end
	else if(i_jalr)
	begin
		pc <= i_result &~1;	
	end
	else
	begin
		pc <= pc + is_pc_increment;
	end
end

always @(*)
begin
	if(~rst_n)
	begin
		o_iaddr = 32'd0;
		o_imem_stb = 1'b0;
		o_instr = `NOP;
	end
	else if(is_stall)
		o_instr = `NOP;
	else
	begin
		o_iaddr = pc;
		o_imem_stb = 1'b1;
		o_instr = i_inst;
	end
end

//only for simulation
`ifdef SIM
always @(o_pc,o_instr)
begin	
	#2
	if(rst_n & o_imem_stb)
	begin
		fd = $fopen("IF_log.csv","ab+");
		$fwrite(fd,"%h,%h\n",o_pc,o_instr);
		$fclose(fd);
	end
end

`endif

endmodule
