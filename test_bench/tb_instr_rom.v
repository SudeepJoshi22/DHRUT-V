`timescale 1ns / 1ps
`default_nettype none
`include "rtl/parameters.vh"

module tb_instr_rom;

    // Testbench signals
    reg clk;
    reg rst_n;
    reg i_mem_enable;
    reg i_mem_read;
    reg [31:0] i_mem_address;
    wire [31:0] o_mem_rdata;
    wire o_mem_ready;
    wire o_mem_valid;

    // Instantiate the instr_rom module
    instr_rom dut (
        .clk(clk),
        .rst_n(rst_n),
        .i_mem_en(i_mem_enable),
        .i_mem_rd(i_mem_read),
        .i_mem_addr(i_mem_address),
        .o_mem_rdata(o_mem_rdata),
        .o_mem_rdy(o_mem_ready),
        .o_mem_vld(o_mem_valid)
    );

    // Clock generation
    initial begin
        $dumpfile("waveform.vcd");
    	$dumpvars(0, tb_instr_rom);
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz clock
    end

    // Monitor the signals
    initial begin
        $monitor("Time: %0t, rst_n: %b, i_mem_enable: %b, i_mem_read: %b, i_mem_address: %h, o_mem_rdata: %h, o_mem_ready: %b, o_mem_valid: %b",
                 $time, rst_n, i_mem_enable, i_mem_read, i_mem_address, o_mem_rdata, o_mem_ready, o_mem_valid);
    end

    // Test sequence
    initial begin
        // Initialize signals
        rst_n = 0;
        i_mem_enable = 0;
        i_mem_read = 0;
        i_mem_address = `PC_RESET;

        // Apply reset
        #20 rst_n = 1;

        // Wait for reset to propagate
        #10;

        // Read from ROM at PC_RESET
        i_mem_enable = 1;
        i_mem_read = 1;
        
        i_mem_address = `PC_RESET;
        #10 i_mem_address = i_mem_address + 32'd4;
        #10 i_mem_address = i_mem_address + 32'd4;
	#10 i_mem_address = i_mem_address + 32'd4;
	#10 i_mem_address = i_mem_address + 32'd4;
	#10
	i_mem_enable = 0;
	i_mem_address = i_mem_address + 32'd4;
	
        // Finish simulation
        #100 $finish;
    end
endmodule

