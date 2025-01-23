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

module control_unit(
input wire [31:0] i_instr,
output reg [3:0] o_alu_ctrl
);

wire [2:0] is_func3;
wire is_func7;
wire [6:0] is_opcode;

assign is_func7 = i_instr[30]; // only 30th bit is required to differentialte ADD,SUB,SRL,SRA,SRLI and SRLAI
assign is_func3 = i_instr[14:12];
assign is_opcode = i_instr[6:0];

always @(*)
    begin
	if((is_opcode == `R)) begin
		if((is_func3 == `ADDI) & (is_func7 == 1'b0))
			o_alu_ctrl = `ADD;
		else if((is_func3 == `SUBI) & (is_func7 == 1'b1))
			o_alu_ctrl = `SUB;
		else if((is_func3 == `SRLI) & (is_func7 == 1'b0))
			o_alu_ctrl = `SRL;
		else if((is_func3 == `SRAI) & (is_func7 == 1'b0))
			o_alu_ctrl = `SRA;
		else if(is_func3 == `SLLI)
			o_alu_ctrl = `SLL;
		else if(is_func3 == `SLTI)
			o_alu_ctrl = `SLT;
		else if(is_func3 == `SLTUI)
			o_alu_ctrl = `SLTU;
		else if(is_func3 == `XORI)
			o_alu_ctrl = `XOR;
		else if(is_func3 == `ORI)
			o_alu_ctrl = `OR;
		else if(is_func3 == `ANDI)
			o_alu_ctrl = `AND;
		else
			o_alu_ctrl = 4'b1111; // invalid alu control signal	
	end
	else if(is_opcode == `I) begin
		if((is_func3 == `ADDI))
			o_alu_ctrl = `ADD;
		else if((is_func3 == `SRLI) & (is_func7 == 1'b0))
			o_alu_ctrl = `SRL;
		else if((is_func3 == `SRAI) & (is_func7 == 1'b0))
			o_alu_ctrl = `SRA;
		else if(is_func3 == `SLLI)
			o_alu_ctrl = `SLL;
		else if(is_func3 == `SLTI)
			o_alu_ctrl = `SLT;
		else if(is_func3 == `SLTUI)
			o_alu_ctrl = `SLTU;
		else if(is_func3 == `XORI)
			o_alu_ctrl = `XOR;
		else if(is_func3 == `ORI)
			o_alu_ctrl = `OR;
		else if(is_func3 == `ANDI)
			o_alu_ctrl = `AND;
		else
			o_alu_ctrl = 4'b1111; // invalid alu control signal	
	end
	else if((is_opcode == `LD) | (is_opcode == `S) | (is_opcode == `JR) | (is_opcode == `UPC)) begin
		o_alu_ctrl = `ADD;
	end
	else if((is_opcode == `J) | (is_opcode == `U)) begin
		o_alu_ctrl = `BUF;
	end
	else if(is_opcode == `B) begin
		if((is_func3 == `BEQ) | (is_func3 == `BNE))
			o_alu_ctrl = `EQ;
		else if((is_func3 == `BLT) | (is_func3 == `BGE))
			o_alu_ctrl = `GE;
		else if((is_func3 == `BLTU) | (is_func3 == `BGEU))
			o_alu_ctrl = `GEU;
		else
			o_alu_ctrl = 4'b1111; // invalid alu control signal
	end
    end
    
endmodule
