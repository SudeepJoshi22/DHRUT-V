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
   limitations under the License.
*/

`timescale 1ns / 1ps
`default_nettype none
`include "rtl/parameters.vh"

module tb_Fetch;

  // Testbench signals
  reg clk;
  reg rst_n;
  reg [31:0] i_inst;
  reg i_imem_vld;
  reg i_boj;
  reg [31:0] i_boj_pc;
  reg i_trap;
  reg [31:0] i_trap_pc;
  reg i_stall;
  reg i_flush;

  wire [31:0] o_pc;
  wire [31:0] o_instr;
  wire o_imem_rdy;
  wire [31:0] o_iaddr;
  wire o_prediction;

  // Instantiate the Fetch module
  Fetch uut (
    .clk(clk),
    .rst_n(rst_n),
    .o_pc(o_pc),
    .o_instr(o_instr),
    .i_inst(i_inst),
    .o_imem_rdy(o_imem_rdy),
    .i_imem_vld(i_imem_vld),
    .o_iaddr(o_iaddr),
    .i_boj(i_boj),
    .i_boj_pc(i_boj_pc),
    .i_trap(i_trap),
    .i_trap_pc(i_trap_pc),
    .o_prediction(o_prediction),
    .i_stall(i_stall),
    .i_flush(i_flush)
  );

  // Clock generation
  initial begin
    clk = 1'b0;
    forever #(5) clk = ~clk;  // 100 MHz clock
  end

  // Test sequence
  initial begin
    // Initialization
    rst_n = 1'b0;
    i_inst = `NOP;
    i_imem_vld = 1'b0;
    i_boj = 1'b0;
    i_boj_pc = 32'd0;
    i_trap = 1'b0;
    i_trap_pc = 32'd0;
    i_stall = 1'b0;
    i_flush = 1'b0;

    // Release reset
    #15 rst_n = 1'b1;

    // Test case 1: Fetch instruction normally
    i_imem_vld = 1'b1;
    i_inst = 32'h00000013; // NOP
    #10;
    i_inst = 32'h00400093; // ADDI x1, x0, 4
    #10;

    // Test case 2: Stall the pipeline
    i_stall = 1'b1;
    #20;
    i_stall = 1'b0;

    // Test case 3: Flush the pipeline
    i_flush = 1'b1;
    #10;
    i_flush = 1'b0;

    // Test case 4: Branch operation
    i_boj = 1'b1;
    i_boj_pc = 32'h00000010;
    #10;
    i_boj = 1'b0;

    // Test case 5: Trap operation
    i_trap = 1'b1;
    i_trap_pc = 32'h00001000;
    #10;
    i_trap = 1'b0;

    // End of simulation
    #100;
    $finish;
  end

  // Monitor the output
  initial begin
    $monitor("Time: %0t | PC: %h | Instruction: %h | IMEM_RDY: %b | Prediction: %b", 
             $time, o_pc, o_instr, o_imem_rdy, o_prediction);
  end

endmodule

