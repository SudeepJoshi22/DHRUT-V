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
`include "rtl/Fetch.v"
`include "rtl/Decode.v"
`include "rtl/Execute.v"
module Core_Pipe( input wire clk,
		  input wire rst_n,
		  input wire i_instr,
		  input wire i_imem_vld,
		  input wire i_trap,
		  input wire [31:0] i_trap_pc,
		  output reg [31:0] o_result, 
		  output reg [31:0] o_data_store,
		  output reg [31:0] o_pc,
		  output reg [2:0] o_func3,
		  output reg [6:0] o_opcode,
		  output reg [4:0] o_rd
);
// Wires to Decode stage from Fetch and Memory
wire [31:0] o_fetch_pc , o_fetch_instr,o_iaddr;
wire o_prediction , o_imem_rdy;
// Wires to Fetch from Decode
wire i_fetch_stall , i_fetch_flush;
wire i_boj ;
wire [31:0] i_boj_pc;

Fetch fetch_inst( .clk(clk),
		  .rst_n(rst_n),
		  .i_instr(i_instr),
		  .o_pc(o_fetch_pc),
		  .o_instr(o_fetch_instr),
		  .o_prediction(o_prediction),
		  .o_imem_rdy(o_imem_rdy),
		  .i_imem_vld(i_imem_vld),
		  .i_boj(i_boj),
		  .i_boj_pc(i_boj_pc),
		  .i_stall(i_fetch_stall),
		  .i_flush(i_fetch_flush),
		  .i_trap(i_trap),
		  .i_trap_pc(i_trap_pc),
		  .o_iaddr(o_iaddr)
);
//Initialized internal wires from Writeback/Memory stages
wire signed [31:0] i_write_data;
wire i_wr;
assign i_write_data = 32'b0;
assign i_wr = 1'b0;
// Wires to Execute stage
wire [31:0] o_rs1_data,o_rs2_data,o_imm_data,o_decode_pc;
wire [6:0] o_decode_opcode;
wire [2:0] o_decode_func3;
wire [3:0] o_alu_ctrl;
wire [31:0] branch_pc;
wire [4:0] o_rs1 , o_rs2 , o_rd_decode , o_is_rs1 , o_is_rs2;
wire o_is_branch;

// Wires from EX to Decode

wire i_decode_forward_rs1 , i_decode_forward_rs2 ;
wire i_forward_branch , i_decode_stall;


Decode decode_inst( .clk(clk),
		    .rst_n(rst_n),
		    .i_instr(o_fetch_instr),
		    .i_write_data(i_write_data),
		    .i_pc(o_fetch_pc),
		    .i_prediction(o_predicition),
		    .i_wr(i_wr),
		    .i_EX_result(o_result),
		    .i_decode_forward_rs1(i_decode_forward_rs1),
		    .i_decode_forward_rs2(i_decode_forward_rs2),
		    .i_forward_branch(i_forward_branch),
		    .i_stall(i_decode_stall),
		    .o_rs1_data(o_rs1_data),
		    .o_rs2_data(o_rs2_data),
		    .o_imm_data(o_imm_data),
		    .o_opcode(o_decode_opcode),
		    .o_func3(o_decode_func3),
		    .o_alu_ctrl(o_alu_ctrl),
		    .branch_pc(is_boj_pc),
		    .o_is_branch(is_boj),
		    .o_rs1(o_rs1),
		    .o_rs2(o_rs2),
		    .o_rd(o_rd_decode),
		    .o_is_rs1(o_is_rs1),
		    .o_is_rs2(o_is_rs2),
		    .o_stall(i_fetch_stall),
		    .o_flush(i_fetch_flush),
		    .o_pc(o_decode_pc)
);
	
//Initialized internal wires from Writeback/Memory stages
wire  [31:0] i_mem_result;
wire [4:0] i_rd_mem;
assign i_mem_result = 32'h0000_0007;
assign i_rd_mem = 5'b0101_0101;
Execute execute_inst( .clk(clk),
		      .rst_n(rst_n),
		      .i_rs1_data(o_rs1_data),
		      .i_rs2_data(i_rs2_data),
		      .i_imm_data(i_imm_data),
		      .i_pc(o_decode_pc),
		      .i_alu_ctrl(o_alu_ctrl),
		      .i_func3(o_func3),
		      .i_opcode(o_decode_opcode),
		      .i_rs1(o_rs1),
		      .i_rs2(o_rs2),
		      .i_rd_decode(o_rd_decode),
		      .i_rd_mem(i_rd_mem),
		      .i_mem_result(i_mem_result),
		      .i_is_rs1(o_is_rs1),
		      .i_is_rs2(o_is_rs2),
		      .i_is_branch(is_boj),
		      .o_result(o_result),
		      .o_data_store(o_data_store),
		      .o_pc(o_pc),
		      .o_func3(o_func3),
		      .o_opcode(o_opcode),
		      .o_rd(o_rd),
		      .o_stall(i_decode_stall),
		      .o_forward_branch(i_forward_branch),
		      .o_decode_forward_rs1(i_decode_forward_rs1),
		      .o_decode_forward_rs2(i_decode_forward_rs2)
);
endmodule		      
		         
		    
		  
		  
		  
