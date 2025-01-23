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

module alu(
input wire [31:0] i_op1, //operand 1
input wire [31:0] i_op2, //operand 2
input wire [3:0] i_alu_ctrl, //ALU control signal
input wire i_stall,
output reg [31:0] o_result //ALU result
);

always @(*)
begin 
if(~i_stall) begin	
    case(i_alu_ctrl)        
        `ADD:
        	o_result = $signed(i_op1) + $signed(i_op2);
        `SUB:
	    	o_result = $signed(i_op1) - $signed(i_op2);
        `AND:
            	o_result = i_op1 & i_op2;
        `OR:
            	o_result = i_op1 | i_op2;
        `XOR:
            	o_result = i_op1 ^ i_op2;
        `SRL:
            	o_result = i_op1 >> i_op2[4:0]; //Only last bits of the operand 2 is used to shift(defined by RISC-V)
        `SLL:
            	o_result = i_op1 << i_op2[4:0];
        `SRA:
            	o_result = $signed(i_op1) >>> i_op2[4:0];
        `BUF:
            	o_result = $signed(i_op2);
    	`SLT:
    		o_result = (i_op1[31] ^ i_op2[31])? {31'd0,i_op1[31]} : {31'd0,$signed(i_op1) < $signed(i_op2)};
    	`SLTU:
    		o_result = {31'd0,$signed(i_op1) < $signed(i_op2)};
    	`EQ:
    		o_result = {31'd0, (i_op1 == i_op2)};
    	`GE:
    		o_result = (i_op1[31] ^ i_op2[31])? {31'd0, i_op2[31]} : {31'd0, ($signed(i_op1) >= $signed(i_op2))};
    	`GEU:
    		o_result = {31'd0, ((i_op1) >= (i_op2))};
        default:
            	o_result <= 32'd0;
    endcase
end
end

endmodule
