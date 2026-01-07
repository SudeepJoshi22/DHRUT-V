`timescale 1ns / 1ps
`include "rtl/parameters.vh"

module tb_EX;

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

    // Outputs
    wire [31:0] o_result;
    wire [31:0] o_data_store;
    wire o_boj;
    wire o_jalr;
    wire [31:0] o_imm_data;

    // Instantiate the EX module
    EX ex_inst (
        .clk(clk),
        .rst_n(rst_n),
        .i_rs1_data(i_rs1_data),
        .i_rs2_data(i_rs2_data),
        .i_imm_data(i_imm_data),
        .i_pc(i_pc),
        .i_alu_ctrl(i_alu_ctrl),
        .i_func3(i_func3),
        .i_opcode(i_opcode),
        .o_result(o_result),
        .o_data_store(o_data_store),
        .o_boj(o_boj),
        .o_jalr(o_jalr),
        .o_imm_data(o_imm_data)
    );

    // Clock generation
    always #5 clk = ~clk; // Assuming a 10ns clock period

    // Initialize inputs
    initial begin
        // Provide initial values to inputs
        clk = 0;
        rst_n = 1;
	#20
        // Test Case 1: R-type instruction with ADD operation
        i_rs1_data = 32'hABCDE123;
        i_rs2_data = 32'h98765432;
        i_imm_data = 32'h00000000;
        i_pc = 32'h00000000;
        i_alu_ctrl = `ADD;
        i_func3 = 3'b000; // R-type instruction
        i_opcode = `R;
	#20
        // Test Case 2: Load instruction (LD) with specific data and address
        i_rs1_data = 32'hABCDEFAB;
        i_rs2_data = 32'h00000000;
        i_imm_data = 32'h00000008; // Offset/address
        i_pc = 32'h00000000;
        i_alu_ctrl = `BUF; // Assuming buffer operation for load
        i_func3 = 3'b011; // LD instruction
        i_opcode = `LD;
	#20
        // Test Case 3: Store instruction (S) with specific data and address
        i_rs1_data = 32'h12345678;
        i_rs2_data = 32'h00000000;
        i_imm_data = 32'h00000004; // Offset/address
        i_pc = 32'h00000000;
        i_alu_ctrl = `BUF; // Assuming buffer operation for store
        i_func3 = 3'b010; // S instruction
        i_opcode = `S;
	#20
        // Test Case 4: Branch instruction (BEQ) checking for equality
        i_rs1_data = 32'hABCDEFAB;
        i_rs2_data = 32'hABCDEFAB;
        i_imm_data = 32'h00000000;
        i_pc = 32'h00000000;
        i_alu_ctrl = `EQ; // ALU control for equality check
        i_func3 = `BEQ; // BEQ branch instruction
        i_opcode = `B;
	#20

        // Reset for a few clock cycles
        rst_n = 0;
        #10;
        rst_n = 1;

        // End simulation after a certain duration
        #1000; // Simulate for 1000 time units

        // End simulation
        $finish;
    end

    // Provide dumping of variables for waveform generation
    initial begin
        $dumpfile("waveform.vcd");
        $dumpvars(0, tb_EX);
    end

endmodule

