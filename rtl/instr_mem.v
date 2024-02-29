// MIT License
// 
// Copyright (c) 2023 Sudeep et al.
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

module instr_mem(
input wire clk,
input wire rst_n, // active low reset
input wire [31:0] i_addr, //instruction address
input wire i_stb, // request for instruction
output reg o_ack, // acknowledge signal
output reg [31:0] o_data //instruction code
);

reg [7:0] memory[`INSTR_MEM_SIZE-1:0];

initial
begin
	$readmemh("programs/instr_mem.mem",memory); // read instruction from the .mem file (byte wise)
	o_data <= 32'd0;
	o_ack <= 1'b0;
end

// Just for the simulation purpose, instruction memeory reads as soon as the address is inserted
always @(*)
begin
	if(~rst_n) 
	begin
		o_ack <= 1'b0;
		o_data <= 32'd0;
	end
	else if(i_stb && ( (i_addr & 2'b11) == 2'b00 )) //checking is the stub signal is high and address is 4 bytes aligned(last two bits are zero)
	begin
		o_ack <= 1'b1; // acknowledge that the instruction is on the bus.
    		o_data <= {memory[i_addr+3],memory[i_addr+2],memory[i_addr+1],memory[i_addr]}; // instructions are present byte wise and are in little-endian format
	end
	else
	begin
		if( (i_addr & 2'b11) != 2'b00 ) begin
			$display("\nINSTRUCTION MEMORY: Address %h is not 4-byte aligned!",i_addr);
		end 
		o_ack <= 1'b0;
		o_data <= 32'd0;
	end
end

endmodule
