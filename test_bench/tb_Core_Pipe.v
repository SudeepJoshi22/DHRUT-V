`timescale 1ns / 1ps
`default_nettype none
`include "rtl/parameters.vh"
//`include "rtl/Core_Pipe.v"
module tb_Core_Pipe();
   reg clk;
   reg rst_n;
   reg [31:0] i_instr;
   //reg i_imem_vld;
   //reg i_imem_rdy;
   //reg i_trap;
   //reg i_stall;
   //reg [31:0] i_trap_pc;
   reg [31:0] i_pc;
   reg i_prediction;
   wire [31:0] o_result; 
   wire [31:0] o_data_store;
   wire [31:0] o_pc;
   wire [2:0] o_func3;
   wire [6:0] o_opcode;
   wire [4:0] o_rd;
   
  Core_Pipe cpinst( .clk(clk),
  		    .rst_n(rst_n),
  		    .i_instr(i_instr),
  		    //.i_imem_vld(i_imem_vld),
  		    //.i_trap(i_trap),
  		    //.i_trap_pc(i_trap_pc),
  		    .i_pc(i_pc),
  		    .i_prediction(i_prediction),
  		    .o_result(o_result),
  		    .o_data_store(o_data_store),
  		    .o_pc(o_pc),
  		    .o_func3(o_func3),
  		    .o_opcode(o_opcode),
  		    .o_rd(o_rd)
);
initial begin
	clk=1;
	   
    rst_n = 0;
    $dumpfile("waveform.vcd");
    $dumpvars(0, tb_Core_Pipe);
end
always #10 clk = ~clk;
initial begin
#10
	rst_n = 1;
#10
	i_instr = 32'h00000033;//NOP
	//i_imem_vld = 1;
	//i_imem_rdy = 1;
	//i_trap = 0;
	//i_trap_pc = 32'b0;
	//i_stall = 0;
	i_prediction = 0;
// Normal FLow of Instruction test
#20 
	i_instr = 32'h00518233;//add x4,x5,x3
#20
	i_instr = 32'h405303b3;//sub x7,x6,x5
//Data Dependency test 
#20 
	i_instr = 32'h007284b3; //add x9,x5,x7
#20
	i_instr = 32'h00248413; //addi x8,x9,2
// Data Dependency Mem To EX
#20 
	i_instr = 32'h00348413; //addi x8,x9,3 
// Load instructions Dependency Check 
#20 
	i_instr = 32'h0081a303; // lw x6,8(x3)
#20
	i_instr = 32'h004303b3; // add x7,x6,x4 
// Test of Dependency existing due to our Current Microarchitecture
#40
	i_instr = 32'h003203b3; //add x7,x4,x3
#20
	i_instr = 32'h00538463; // beq x7 , x5 , 8
	
#100 $finish;
end
endmodule


