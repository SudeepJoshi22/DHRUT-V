`timescale 1ns / 1ps
`default_nettype none
`include "rtl/parameters.vh"

module tb_data_ram;

    // Testbench signals
    reg clk;
    reg rst_n;
    reg i_mem_en;
    reg i_mem_rd;
    reg i_mem_wr;
    reg [31:0] i_mem_addr;
    reg [31:0] i_mem_wdata;
    wire [31:0] o_mem_rdata;
    wire o_mem_rdy;
    wire o_mem_vld;

    // Instantiate the data_ram module
    data_ram uut (
        .clk(clk),
        .rst_n(rst_n),
        .i_mem_en(i_mem_en),
        .i_mem_rd(i_mem_rd),
        .i_mem_wr(i_mem_wr),
        .i_mem_addr(i_mem_addr),
        .i_mem_wdata(i_mem_wdata),
        .o_mem_rdata(o_mem_rdata),
        .o_mem_rdy(o_mem_rdy),
        .o_mem_vld(o_mem_vld)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz clock
    end

    // Test sequence
    initial begin
        $dumpfile("waveform.vcd");
    	$dumpvars(0, tb_data_ram);
        // Initialize signals
        rst_n = 0;
        i_mem_en = 0;
        i_mem_rd = 0;
        i_mem_wr = 0;
        i_mem_addr = `PC_RESET;
        i_mem_wdata = 32'hDEADBEEF;

        // Apply reset
        #20 rst_n = 1;

        // Wait for reset to propagate
        #10;

        // Write to RAM at PC_RESET
        i_mem_en = 1;
        i_mem_wr = 1;
        i_mem_addr = `DATA_START;
        i_mem_wdata = 32'hCAFEBABE;
        #10;

        // Read from RAM at PC_RESET
        i_mem_wr = 0;
        i_mem_rd = 1;
        #10;
        wait(o_mem_rdy && o_mem_vld);
        #1; // Small delay to ensure signal stability

        // Read from another address
        i_mem_rd = 0;
        #10 i_mem_addr = `DATA_START + 4;
        i_mem_rd = 1;
        #10;
        wait(o_mem_rdy && o_mem_vld);
        #1; // Small delay to ensure signal stability

        // Finish simulation
        #20 $finish;
    end

    // Monitor the signals
    initial begin
        $monitor("Time: %0t, rst_n: %b, i_mem_en: %b, i_mem_rd: %b, i_mem_wr: %b, i_mem_addr: %h, i_mem_wdata: %h, o_mem_rdata: %h, o_mem_rdy: %b, o_mem_vld: %b",
                 $time, rst_n, i_mem_en, i_mem_rd, i_mem_wr, i_mem_addr, i_mem_wdata, o_mem_rdata, o_mem_rdy, o_mem_vld);
    end

endmodule

