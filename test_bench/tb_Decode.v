`timescale 1ns / 1ps

module tb_Decode();

  reg clk;
  reg rst_n;
  reg [31:0] i_instr;
  reg [31:0] i_write_data;
  reg [31:0] i_pc;
  reg i_wr;
  //reg i_ce;
  wire [31:0] o_rs1_data;
  wire [31:0] o_rs2_data;
  wire [31:0] o_imm_data;
  wire [6:0] o_opcode;
  wire [2:0] o_func3;
  wire [3:0] o_alu_ctrl;
  wire [31:0] o_pc;
  wire  [31:0] branch_pc;
  reg i_prediction;
  reg i_stall;
  reg i_forward_branch;
  reg [31:0] i_EX_result;
  reg i_decode_forward_rs1;
  reg i_decode_forward_rs2; 
  wire o_stall; 
  wire o_flush; 
  wire [4:0] o_rs1;
  wire [4:0] o_rs2;
  wire [4:0] o_rd;
  wire [4:0] o_is_rs1,o_is_rs2;
  wire o_is_branch;
  //wire o_ce;

  // Instantiate the module
  Decode inst(
    .clk(clk),
    .rst_n(rst_n),
    .i_instr(i_instr),
    .i_write_data(i_write_data),
    .i_pc(i_pc),
    .i_wr(i_wr),
    //.i_ce(i_ce),
    .o_rs1_data(o_rs1_data),
    .o_rs2_data(o_rs2_data),
    .o_imm_data(o_imm_data),
    .o_opcode(o_opcode),
    .o_func3(o_func3),
    .o_alu_ctrl(o_alu_ctrl),
    .branch_pc(branch_pc),
    .i_prediction(i_prediction),
    .i_stall(i_stall),
    .i_forward_branch(i_forward_branch),
    .i_decode_forward_rs1(i_decode_forward_rs1),
    .i_decode_forward_rs2(i_decode_forward_rs2),
    .i_EX_result(i_EX_result),
    .o_stall(o_stall),
    .o_flush(o_flush),
    .o_rs1(o_rs1),
    .o_rs2(o_rs2),
    .o_rd(o_rd),
    .o_is_branch(o_is_branch),
    .o_is_rs1(o_is_rs1),
    .o_is_rs2(o_is_rs2)
    
    //.o_ce(o_ce)
  );

  // Clock generation
  always #10 clk = ~clk;

  // Initial values
  initial begin
    clk = 0;
    rst_n = 0;
    $dumpfile("waveform.vcd");
    $dumpvars(0, tb_Decode);
    
  end
  
  initial begin
    #10 
    rst_n = 1;
    #10
    i_instr=32'h00000013; //addi x0,x0,0
    i_write_data = 32'h0;
    i_pc = 32'h0;
    i_wr = 0;
    i_prediction = 1;
    i_stall=0;    
    #30
    i_instr=32'h00218333; //add x6,x3,x2
    #20
    i_instr=32'h00431663; // bne x6,x4,12
    #20
    i_instr= 32'h00840393;//addi x7,x5,8
    #20
    i_instr=32'h00828467; //jalr x8,8(x5)
    #20
    i_instr=32'h0000C36F; //jal x6 , 12
    #200;
    $finish;
  end
       // Add more test cases if needed

    // Finish the simulation


  // Add stimulus or other test bench code if needed

   

endmodule

