`timescale 1ns / 1ps
`include "rtl/parameters.vh"

module tb_Execute;

    // Inputs
    reg clk;
    reg rst_n;
    reg [31:0] i_rs1_data;
    reg [31:0] i_rs2_data;
    reg [31:0] i_imm_data;
    reg [31:0] i_pc;
    reg [3:0] i_alu_ctrl;
    reg [2:0] i_func3;
    reg [6:0] i_opcode;
    reg [6:0] i_opcode_EX;
    reg [4:0] i_rs1,i_rs2,i_rd_decode,i_rd_mem;
    reg [31:0] i_mem_result;
    reg i_is_branch;
    reg [4:0] i_is_rs1;
    reg [4:0] i_is_rs2;
    

    // Outputs
    wire [31:0] o_result;
    wire [31:0] o_data_store;
    wire [31:0] o_pc;
    wire [4:0] o_rd;
    wire [6:0] o_opcode;
    wire o_stall;
    wire o_forward_branch;
    wire [2:0] o_func3;
    wire o_decode_forward_rs1;
    wire o_decode_forward_rs2;
    
    
    

    // Instantiate the EX module
    Execute ex_inst (
        .clk(clk),
        .rst_n(rst_n),
        .i_rs1_data(i_rs1_data),
        .i_rs2_data(i_rs2_data),
        .i_imm_data(i_imm_data),
        .i_pc(i_pc),
        .i_alu_ctrl(i_alu_ctrl),
        .i_func3(i_func3),
        .i_opcode(i_opcode),
        .i_rs1(i_rs1),
        .i_rs2(i_rs2),
        .i_is_branch(i_is_branch),
        .i_is_rs1(i_is_rs1),
        .i_is_rs2(i_is_rs2),
        .i_mem_result(i_mem_result),
        .i_rd_decode(i_rd_decode),
        .i_rd_mem(i_rd_mem),
        .o_result(o_result),
        .o_data_store(o_data_store),
        .o_stall(o_stall),
        .o_forward_branch(o_forward_branch),
        .o_rd(o_rd),
        .o_func3(o_func3),
        .o_pc(o_pc),
        .o_opcode(o_opcode),
        .o_decode_forward_rs1(o_decode_forward_rs1),
        .o_decode_forward_rs2(o_decode_forward_rs2)
    );

    // Clock generation
    always #5 clk = ~clk; // Assuming a 10ns clock period

    // Initialize inputs
    initial begin
        // Provide initial values to inputs
        clk = 1;
        rst_n = 1;
        // add rd,rs1,rs2
	#5
       i_rs1_data = 32'h00000008;
       i_rs2_data = 32'h00000002;
       i_rs1 = 5'b00011;
       i_rs2 = 5'b01100;
       i_rd_decode = 5'b10101;
       i_rd_mem = 5'b00110;
       i_is_branch = 1'b0;
       i_is_rs1 = 5'b01010;
       i_is_rs2 = 5'b00001;
       i_mem_result = 32'h0000_0000;
       i_alu_ctrl = `ADD;
       i_pc = 32'h0000_0000;
       i_opcode = `R;
       i_imm_data = 32'h00000001;
       // sw rs2,rs1(imm)
	#5
       i_rs1_data = 32'h00000003;
       i_rs2_data = 32'h00000002;
       i_rs1 = 5'b00111;
       i_rs2 = 5'b10101;
       i_rd_decode = 5'b00110;
       i_rd_mem = 5'b00110;
       i_is_branch = 1'b0;
       i_is_rs1 = 5'b11100;
       i_is_rs2 = 5'b00001;
       i_mem_result = 32'h0000_0008;
       i_alu_ctrl = `ADD;
       i_pc = 32'h0000_0000;
       i_opcode = `S;
       i_imm_data = 32'h00000001;
       
	
        // Reset for a few clock cycles
       // rst_n = 0;
        #10;
       // rst_n = 1;

        // End simulation after a certain duration
        #1000; // Simulate for 1000 time units

        // End simulation
        $finish;
    end

    // Provide dumping of variables for waveform generation
    initial begin
        $dumpfile("waveform.vcd");
        $dumpvars(0, tb_Execute);
    end

endmodule

