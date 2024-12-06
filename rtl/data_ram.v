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
   limitations under the License. */

`timescale 1ns / 1ps
`default_nettype none

module data_ram (
    input  wire         clk,      // Clock signal
    input  wire         rst_n,    // Reset signal (active low)
    input  wire         i_wr_en,    // Write enable signal
    input  wire [3:0]   i_sel,      // Select signal for byte-enable (4 bits for 32-bit word)
    input  wire [31:0]  i_addr,     // 32-bit Address signal
    input  wire [31:0]  i_wdata,    // 32-bit Write data
    output reg  [31:0]  o_rdata,    // 32-bit Read data
    input  wire         i_d_ready,  // Ready signal for data transfer
    output reg          o_d_valid,  // Valid signal for data transfer
    output reg          o_error     // Error signal for invalid accesses
);

    // Byte-addressable memory array
    reg [7:0] memory[`DATA_START + `DATA_MEM_SIZE - 1 : `DATA_START]; // Byte-addressable RAM

    // RAM Initialization (optional)
    initial begin
        $readmemh("programs/data_mem.mem", rom);
    end

    // Error detection logic
    wire out_of_bounds = (i_addr < `DATA_START) || (i_addr >= `DATA_START + `DATA_MEM_SIZE);
    wire misaligned    = |i_addr[1:0]; // True if lower 2 bits of address are non-zero

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_error <= 1'b0;
        end else begin
            o_error <= out_of_bounds || (i_wr_en && misaligned); // Set error on invalid access
        end
    end

    // Valid-ready handshake logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_d_valid <= 1'b0; // Deassert valid on reset
        end else begin
            o_d_valid <= i_d_ready && !o_error; // Assert valid if ready and no error
        end
    end

    // Write operation with select signal support
    always @(posedge clk) begin
        if (i_wr_en && !o_error) begin
            if (i_sel[0]) memory[i_addr]     <= i_wdata[7:0];
            if (i_sel[1]) memory[i_addr + 1] <= i_wdata[15:8];
            if (i_sel[2]) memory[i_addr + 2] <= i_wdata[23:16];
            if (i_sel[3]) memory[i_addr + 3] <= i_wdata[31:24];
        end
    end

    // Read operation
    always @(posedge clk) begin
        if (!o_error) begin
            o_rdata <= {memory[i_addr + 3], memory[i_addr + 2], memory[i_addr + 1], memory[i_addr]};
        end else begin
            o_rdata <= 32'hDEADBEEF; // Default error value, can be customized
        end
    end

endmodule

