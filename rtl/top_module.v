// MIT License
// 
// Copyright (c) 2023 Sudeep.
// 
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// 
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

`timescale 1ns / 1ps
`default_nettype none

module top_module (
    input  wire clk,
    input  wire rst_n
);

    // Core module signals
    wire [`ADDR_WIDTH-1:0] core_o_iaddr;
    wire core_o_iaddr_vld;
    wire [`INST_WIDTH-1:0] core_i_inst;
    wire core_i_inst_vld;

    wire [`N-1:0] core_i_rdata;
    wire core_i_d_valid;
    wire core_o_wr_en;
    wire [3:0] core_o_sel;
    wire [`ADDR_WIDTH-1:0] core_o_addr;
    wire core_o_addr_vld;
    wire [`N-1:0] core_o_wdata;

    // Instruction memory signals
    wire [31:0] instr_mem_o_data;
    wire instr_mem_o_ack;

    // Data RAM signals
    wire [31:0] data_ram_o_rdata;
    wire data_ram_o_d_valid;

    // Core instance
    Core core_inst (
        .clk(clk),
        .rst_n(rst_n),

        // I-mem interface
        .o_iaddr(core_o_iaddr),
        .o_iaddr_vld(core_o_iaddr_vld),
        .i_inst(instr_mem_o_data),
        .i_inst_vld(instr_mem_o_ack),

        // D-mem interface
        .i_rdata(data_ram_o_rdata),
        .i_d_valid(data_ram_o_d_valid),
        .o_wr_en(core_o_wr_en),
        .o_sel(core_o_sel),
        .o_addr(core_o_addr),
        .o_addr_vld(core_o_addr_vld),
        .o_wdata(core_o_wdata)
    );

    // Instruction memory instance
    instr_mem instr_mem_inst (
        .clk(clk),
        .rst_n(rst_n),
        .i_addr(core_o_iaddr),
        .i_stb(core_o_iaddr_vld),
        .o_ack(instr_mem_o_ack),
        .o_data(instr_mem_o_data)
    );

    // Data RAM instance
    data_ram data_ram_inst (
        .clk(clk),
        .rst_n(rst_n),
        .i_wr_en(core_o_wr_en),
        .i_sel(core_o_sel),
        .i_addr(core_o_addr),
        .i_addr_vld(core_o_addr_vld),
        .i_wdata(core_o_wdata),
        .o_rdata(data_ram_o_rdata),
        .o_d_valid(data_ram_o_d_valid)
    );
    
    initial begin
    	$dumpfile("dump.vcd");
        $dumpvars(0, top_module);
    end


endmodule

