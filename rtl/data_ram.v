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
`include "rtl/parameters.vh"

module data_ram (
input wire clk,
input wire rst_n,
input wire i_mem_en,
input wire i_mem_rd,
input wire i_mem_wr,
input wire [31:0] i_mem_addr,
input wire [31:0] i_mem_wdata,
output reg [31:0] o_mem_rdata,
output reg o_mem_rdy,
output reg o_mem_vld
);

// Internal RAM storage
reg [7:0] ram[`DATA_START + `DATA_MEM_SIZE : `DATA_START];

// Initialize RAM contents from a file (optional)
initial begin
$readmemh("programs/data_mem.mem", ram);
end

always @(posedge clk or negedge rst_n) begin
if (!rst_n) begin
    o_mem_rdy <= 0;
    o_mem_vld <= 0;
    o_mem_rdata <= 0;
end else if (i_mem_en) begin
    if (i_mem_rd) begin
        o_mem_rdy <= 1; // Memory is ready to provide data
        o_mem_rdata <= {ram[i_mem_addr+3], ram[i_mem_addr+2], ram[i_mem_addr+1], ram[i_mem_addr]}; // Read data (little-endian)
        o_mem_vld <= 1; // Data is valid
    end else if (i_mem_wr) begin
        // Write data to RAM
        ram[i_mem_addr] <= i_mem_wdata[7:0];
        ram[i_mem_addr+1] <= i_mem_wdata[15:8];
        ram[i_mem_addr+2] <= i_mem_wdata[23:16];
        ram[i_mem_addr+3] <= i_mem_wdata[31:24];
        o_mem_rdy <= 1; // Memory is ready to accept data
        o_mem_vld <= 0; // No read data is valid
    end else begin
        o_mem_rdy <= 0;
        o_mem_vld <= 0;
    end
end else begin
    o_mem_rdy <= 0;
    o_mem_vld <= 0;
end
end

endmodule

