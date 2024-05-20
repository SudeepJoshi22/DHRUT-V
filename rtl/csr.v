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

`include "rtl/parameter.vh"

module csr(
input wire clk,
input wire rst_n,
//Interrupts
input wire i_ext_intr,
input wire i_sw_intr,
//Exceptions
input wire i_illegal_inst,
input wire i_ecall,
input wire i_ebreak,
input wire i_mret,
//Load-Store and inst address misalignment
input wire [6:0] i_opcode,
input wire [`N-1:0] i_alu_result,
//CSR instructions
input wire [2:0] i_func3,
input wire [11:0] i_csr_addr,
input wire [31:0] i_imm,
input wire [`N-1:0] i_rs1,
output reg [`N-1:0] i_csr_val,
//Trap Handling
input wire [`N-1:0] i_pc,
input wire i_wb_change_pc,
output reg [`N-1:0] o_ret_addr,
output reg [`N-1:0] o_trap_addr,
output reg o_trap,
output reg o_ret_trap
/*
input wire i_cen,
input wire i_stall
*/
);

// Internal Signals



// Internal Registers
reg ir_load_misaligned;
reg ir_store_misaligned;
reg ir_pc_misaligned;
reg ir_new_pc;

// Detecting Load/Store/Instruction Misalignment Exception
always @(*)
begin
	ir_load_misaligned = 0;
	ir_store_misaligned = 0;
	ir_pc_misaligned = 0;	
	ir_new_pc = 0;
	
	// Mis-aligned Load/Store
	if(i_func3[1:0] == 2'b01) begin // Half-Word
		ir_load_misaligned = (i_opcode == `LD)? i_alu_result[0] : 0;
		ir_store_misaligned = (i_opcode == `S)? i_alu_result[0] : 0;
	end
	if(i_func3[1:0] == 2'b10) begin // Word
		ir_load_misaligned = (i_opcode == `LD)? (i_alu_result[0] != 2'b00) : 0;
		ir_store_misaligned = (i_opcode == `S)? (i_alu_result[0] != 2'b00) : 0;
	end
	
	// Mis-aligned PC
	/* Mis-aligned PC/Instruction exception must be reported on the Taken-Branch/Jump Instruction */
	if(((i_opcode == `B) & i_alu_result[0]) || (i_opcode == `J) || (i_opcode == `JR)) begin /*** Here the branch-decision is being taken from ALU, when we move that to ID stage, we have to modify this ***/
		
	end
end

// Writing into CSRs


// Trap Detection


// 


endmodule
