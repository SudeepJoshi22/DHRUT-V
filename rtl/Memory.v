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
	output reg [4:0] o_ex_rd, // For forwarding unit
	output reg [31:0] o_mem_data_val, // Loaded Value, or Buffered result from EXE 
	// MEM-WB Interfacue
	output reg o_wb_rd,
	output reg [31:0] o_wb_data, // write back value can be result, data read or pc depending on the opcode
	output reg [6:0] o_opcode,
	// Data-Memory Interface
        output wire o_wr_en,    		// Write enable signal
        output wire [3:0] o_sel,		// Select signal for byte-enable (4 bits for 32-bit word)
        output wire [31:0] o_daddr,    		// 32-bit Address signal
        output wire [31:0] o_write_data,    	// 32-bit Write data
        input wire [31:0] i_read_data,    	// 32-bit Read data
        output wire o_d_ready,  		// Ready signal for data transfer
        input wire i_d_valid,  			// Valid signal for data transfer
        input wire i_error     			// Error signal for invalid accesses
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
