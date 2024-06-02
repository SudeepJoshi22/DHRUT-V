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

module branch_jump_decision(
input wire [31:0] is_rs1_data,
input wire [31:0] is_rs2_data,
input wire [6:0]is_opcode,
input wire [31:0] is_pc,
input wire [2:0] is_func3,
input wire [31:0] i_imm,
output reg branch_flush,
output reg [31:0] branch_pc
);
 reg [31:0] b_pc,j_pc;
always @(*)
begin
    case(is_func3)
        `BEQ:begin
                 if(is_rs1_data==is_rs2_data)
                   b_pc<= is_pc + i_imm;
                 else
                    b_pc<=32'b0;
             end
        `BNE:begin
                 if(is_rs1_data!=is_rs2_data)
                   b_pc<= is_pc + i_imm;
                 else
                    b_pc<=32'b0;
            end
        `BLT:begin
                 if($signed(is_rs1_data) < $signed(is_rs2_data))
                   b_pc<= is_pc + i_imm;
                 else
                    b_pc<=32'b0;
            end
        `BGE:begin
                 if($signed(is_rs1_data)>= $signed(is_rs2_data))
                   b_pc<= is_pc + i_imm;
                 else
                    b_pc<=32'b0;
            end
        `BLTU:begin
                 if(is_rs1_data<=is_rs2_data)
                   b_pc<= is_pc + i_imm;
                 else
                    b_pc<=32'b0;
             end
        `BGEU:begin
                if(is_rs1_data>=is_rs2_data)
                   b_pc<= is_pc + i_imm;
                 else
                    b_pc<=32'b0;
             end
        default:
                    b_pc<=32'b0;
    endcase
    if (is_opcode == `B && b_pc!=32'b0)
    branch_flush = 1;
else if (is_opcode == `J || is_opcode == `JR)
    	branch_flush = 1;
     else
    	branch_flush = 0;

if (is_opcode == `J )
    j_pc = is_pc + i_imm;
else if(is_opcode == `JR)
    j_pc = is_rs1_data + i_imm;
    else
    j_pc=0;

branch_pc = b_pc + j_pc;
end

endmodule
