`timescale 1ns / 1ps

module tb_Decode();

  reg clk;
  reg rst_n;
  reg [31:0] i_instr;
  reg [31:0] i_write_data;
  reg [31:0] i_pc;
  reg i_wr;
  reg i_ce;
  wire [31:0] o_rs1_data;
  wire [31:0] o_rs2_data;
  wire [31:0] o_imm_data;
  wire [6:0] o_opcode;
  wire [2:0] o_func3;
  wire [3:0] o_alu_ctrl;
  wire [31:0] o_pc;
  reg  [31:0] branch_pc;
  reg i_stall; 
  wire o_stall; 
  wire o_flush; 
  wire o_ce;

  // Instantiate the module
  ID_PIPELINING inst(
    .clk(clk),
    .rst_n(rst_n),
    .i_instr(i_instr),
    .i_write_data(i_write_data),
    .i_pc(i_pc),
    .i_wr(i_wr),
    .i_ce(i_ce),
    .o_rs1_data(o_rs1_data),
    .o_rs2_data(o_rs2_data),
    .o_imm_data(o_imm_data),
    .o_opcode(o_opcode),
    .o_func3(o_func3),
    .o_alu_ctrl(o_alu_ctrl),
    .branch_pc(branch_pc),
    .i_stall(i_stall),
    .o_stall(o_stall),
    .o_flush(o_flush),
    .o_ce(o_ce)
  );

  // Clock generation
  always #10 clk = ~clk;

  // Initial values
  initial begin
    $dumpfile("waveform.vcd");
    $dumpvars(0, tb_Decode);
    clk = 0;
    rst_n = 0;
    i_instr = 32'h7FF00293;
    i_write_data = 32'h0;
    i_pc = 32'h0;
    i_wr = 0;

    #10; // Wait for a few clock cycles before toggling reset

    rst_n = 1;
    #20; // Provide some time after releasing reset

    // Test cases with instructions
   i_instr=32'h00218333; //add
   #10
   i_instr=32'h18431663; // bne
   #10
   i_instr=32'h00840393; //addi
   #10
   i_instr=32'h00828467; //jalr
    // Add more test cases if needed

    // Finish the simulation
    #100;
    $finish;
  end

  // Add stimulus or other test bench code if needed

endmodule

