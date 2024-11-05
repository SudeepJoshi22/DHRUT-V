// MIT License
// 
// Copyright (c) 2023 Sudeep.
// 
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// 
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

`timescale 1ns / 1ps
`default_nettype none
`include "rtl/parameters.vh"

module Memory(
	input wire clk,
	input wire rst_n,
	input wire [31:0] i_result,
	input wire [31:0] i_data_store,
	input wire [31:0] i_pc,
	input wire [6:0] i_opcode,
	input wire [2:0] i_func3,
	output wire [31:0] o_wb_data, // write back value can be result, data read or pc depending on the opcode
	output wire [6:0] o_opcode,
	// Data memory interface
	input wire i_rd_ack, //ack from data memory
	input wire [31:0] i_read_data, //data read from data memory
	output wire o_stb,
	output wire o_wr_en,
	output wire [31:0] o_addr,
	output wire [31:0] o_wr_data
);

wire [31:0] is_pc_4, is_load_data;
wire is_stall;

`ifdef SIM
integer fd;
`endif

assign is_stall = ~i_rd_ack & rst_n;

assign is_pc_4 = i_pc + 32'd4; // for jal and jalr instrction, pc+4 must be stored in rd

// data going to WB stage
assign o_opcode = i_opcode;
assign is_load_data = (i_func3 == `LB) ? {{24{i_read_data[7]}},i_read_data[7:0]} : ((i_func3 == `LH) ? {{16{i_read_data[15]}},i_read_data[15:0]} : ((i_func3 == `LBU)? {24'd0,i_read_data[7:0]} : ((i_func3 == `LHU) ? {16'd0,i_read_data[15:0]} : i_read_data)));
assign o_wb_data = ((i_opcode == `J) | (i_opcode == `JR)) ? is_pc_4 : ((i_opcode == `LD) ? is_load_data : i_result);

// for data memory
assign o_stb = (i_opcode == `LD) ? 1'b1 : 1'b0;
assign o_wr_en = (i_opcode == `S) ? 1'b1 : 1'b0;
assign o_addr = (o_stb | o_wr_en | ~rst_n) ? i_result : 32'd0;
assign o_wr_data = (i_func3[1:0] == 2'b00) ? {24'd0,i_data_store[7:0]} : ((i_func3[1:0] == 2'b01) ? {16'd0,i_data_store[15:0]} : i_data_store); // for SW, SH and SB 

//only for simulation
`ifdef SIM
always @(posedge clk)
begin	
	#2
	if(o_stb)
	begin
		fd = $fopen("MEM_log.csv","ab+");
		$fwrite(fd,"mem:%h\n",o_addr);	
		$fclose(fd);
	end
	else
	begin
		fd = $fopen("MEM_log.csv","ab+");
		$fwrite(fd,"\t\n");	
		$fclose(fd);
	end
end
`endif

endmodule
