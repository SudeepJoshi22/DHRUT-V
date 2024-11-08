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
	// EX-MEM interface
	input wire [31:0] i_result,
	input wire [31:0] i_data_store,
	input wire [31:0] i_pc,
	input wire [6:0] i_opcode,
	input wire [2:0] i_func3,
	input wire [4:0] i_rd,
	output reg [4:0] o_rd,// For forwarding unit
	// MEM-WB Interface
	output reg [31:0] o_wb_data, // write back value can be result, data read or pc depending on the opcode
	output reg [6:0] o_opcode,
	// Data memory interface for load type instruction ( 2 Ready-Valid interfaces )
	input wire i_ready_dmem,// Mem stage is sender for address and data for store type instruction
	input wire i_valid_mem,// Mem Stage is receiver for i_read_data for load type instruction
	input wire [31:0] i_read_data, //data read from data memory
	input wire i_stall, //Stall the MEM stage when there is a delay in reading data from memory within one clock cycle
	output reg [31:0] o_addr,//Address to data memory/cache
	output wire o_valid_dmem,//Mem stage as sender for address and Data for store type
	output wire o_ready_mem,//Mem is receiver for load type
	output reg [31:0] o_wr_data// Data to be sent to Data_memory
);

reg [31:0] is_pc_4, is_load_data,is_result;
wire is_stall;
reg [4:0] is_rd;
`ifdef SIM
integer fd;
`endif

//assign is_stall = ~i_rd_ack & rst_n;

//assign is_pc_4 = i_pc + 32'd4; // for jal and jalr instrction, pc+4 must be stored in rd

// data going to WB stage
 reg [6:0] is_opcode;
//assign is_load_data = (i_func3 == `LB) ? {{24{i_read_data[7]}},i_read_data[7:0]} : ((i_func3 == `LH) ? {{16{i_read_data[15]}},i_read_data[15:0]} : ((i_func3 == `LBU)? {24'd0,i_read_data[7:0]} : ((i_func3 == `LHU) ? {16'd0,i_read_data[15:0]} : i_read_data)));
//assign o_wb_data = ((i_opcode == `J) | (i_opcode == `JR)) ? is_pc_4 : ((i_opcode == `LD) ? is_load_data : i_result);

// for data memory
//assign o_stb = (i_opcode == `LD) ? 1'b1 : 1'b0;
//assign o_wr_en = (i_opcode == `S) ? 1'b1 : 1'b0;
//assign o_addr = (o_stb | o_wr_en | ~rst_n) ? i_result : 32'd0;
//assign o_wr_data = (i_func3[1:0] == 2'b00) ? {24'd0,i_data_store[7:0]} : ((i_func3[1:0] == 2'b01) ? {16'd0,i_data_store[15:0]} : i_data_store); // for SW, SH and SB 
assign o_valid_dmem = ( (i_opcode == `LD) || (i_opcode == `S)) ? 1'b1 : 1'b0 ;
assign o_ready_mem = (i_valid_mem == 1) ? 1'b1 : 1'b0;
always@(*)
begin   
	is_opcode <= i_opcode;
	is_result <= i_result;
	is_rd <= i_rd;
	// Valid-Ready interface 
	if(i_ready_dmem && o_valid_dmem)
		o_addr = i_result;
	else
		o_addr = 32'b0;
	
	if( (i_ready_dmem) && (i_opcode == `S) )
		o_wr_data = (i_func3[1:0] == 2'b00) ? {24'd0,i_data_store[7:0]} : ((i_func3[1:0] == 2'b01) ? {16'd0,i_data_store[15:0]} : i_data_store); 
	else
		o_wr_data = 32'b0;
	
	if( o_ready_mem == 1)
		is_load_data = (i_func3 == `LB) ? {{24{i_read_data[7]}},i_read_data[7:0]} : ((i_func3 == `LH) ? {{16{i_read_data[15]}},i_read_data[15:0]} : ((i_func3 == `LBU)? {24'd0,i_read_data[7:0]} : ((i_func3 == `LHU) ? {16'd0,i_read_data[15:0]} : i_read_data))); 
	else 
		is_load_data = 32'b0;
end 
always@(posedge clk or negedge rst_n)
begin
	if(~rst_n) begin
		o_wb_data <= 32'b0;
 		o_opcode  <= 7'b0;
 		end
 		
		
	else begin
		if(is_opcode == `LD) 
			o_wb_data <= is_load_data;
		else	if( is_opcode!=`S)
			o_wb_data <= is_result;
		
		o_opcode <= is_opcode;
		o_rd <= is_rd;
	     end
	
end
//only for simulation
/*`ifdef SIM
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
`endif*/

endmodule
