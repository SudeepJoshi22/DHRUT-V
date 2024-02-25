`timescale 1ns / 1ps
`default_nettype none
`include "rtl/parameters.vh"

module tb_alu;
  // Signals
  reg [31:0] i_op1, i_op2;
  reg [3:0] i_alu_ctrl;
  wire [31:0] o_result;

  // Instantiate ALU module
  alu dut (
    .i_op1(i_op1),
    .i_op2(i_op2),
    .i_alu_ctrl(i_alu_ctrl),
    .o_result(o_result)
  );

  // Clock generation
  reg clk = 0;
  always #5 clk = ~clk;

  // Test case
  initial begin

    $dumpfile("waveform.vcd");
    $dumpvars(0, tb_alu);
    
    // Reset values
    i_op1 = 32'd0;
    i_op2 = 32'd0;
    i_alu_ctrl = 4'b0000;

    // Test ADD operation
    i_op1 = 32'd10;
    i_op2 = 32'd20;
    i_alu_ctrl = `ADD;
    #10;

    // Test SUB operation
    i_op1 = 32'd50;
    i_op2 = 32'd25;
    i_alu_ctrl = `SUB;
    #10;

    // Test AND operation
    i_op1 = 32'd15;
    i_op2 = 32'd3;
    i_alu_ctrl = `AND;
    #10;

    // Test OR operation
    i_op1 = 32'd7;
    i_op2 = 32'd12;
    i_alu_ctrl = `OR;
    #10;

    // Test XOR operation
    i_op1 = 32'd11;
    i_op2 = 32'd5;
    i_alu_ctrl = `XOR;
    #10;

    // Test SRL operation
    i_op1 = 32'd80;
    i_op2 = 5'b00011;
    i_alu_ctrl = `SRL;
    #10;

    // Test SLL operation
    i_op1 = 32'd3;
    i_op2 = 5'd4;
    i_alu_ctrl = `SLL;
    #10;

    // Test SRA operation
    i_op1 = -32'd48;
    i_op2 = 5'd2;
    i_alu_ctrl = `SRA;
    #10;

    // Test BUF operation
    i_op1 = 32'd10;
    i_op2 = 32'd20;
    i_alu_ctrl = `BUF;
    #10;

    // Test SLT operation
    i_op1 = -32'd10;
    i_op2 = -32'd20;
    i_alu_ctrl = `SLT;
    #10;

    // Test SLTU operation
    i_op1 = -20;
    i_op2 = 32'd10;
    i_alu_ctrl = `SLTU;
    #10;

    // Test EQ operation
    i_op1 = 32'd10;
    i_op2 = 32'd10;
    i_alu_ctrl = `EQ;
    #10;
    
    // Test EQ operation
    i_op1 = 32'd10;
    i_op2 = 32'd20;
    i_alu_ctrl = `EQ;
    #10;

    // Test GE operation
    i_op1 = 32'd30;
    i_op2 = 32'd20;
    i_alu_ctrl = `GE;
    #10;

    // Test GE operation
    i_op1 = 32'd50;
    i_op2 = 32'd20;
    i_alu_ctrl = `GE;
    #10;

    // Test GEU operation
    i_op1 = 32'd20;
    i_op2 = 32'd30;
    i_alu_ctrl = `GEU;
    #10;
    
    // Test GEU operation
    i_op1 = -100;
    i_op2 = 32'd30;
    i_alu_ctrl = `GEU;
    #10;

    // Finish simulation
    $finish;
  end

endmodule

