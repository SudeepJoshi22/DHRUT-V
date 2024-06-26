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

module instr_rom (
input wire clk,
input wire rst_n,
input wire i_mem_en,
input wire i_mem_rd,
input wire [31:0] i_mem_addr,
output reg [31:0] o_mem_rdata,
output reg o_mem_rdy,
output reg o_mem_vld
);

// Internal ROM storage
reg [7:0] rom[`PC_RESET + `INSTR_MEM_SIZE : `PC_RESET];

// Initialize ROM contents from a file
initial begin
$readmemh("programs/instr_mem.mem", rom);
end

always @(posedge clk or negedge rst_n) begin
if (!rst_n) begin
    o_mem_rdy <= 0;
    o_mem_vld <= 0;
    o_mem_rdata <= 0;
end 
else if (i_mem_en) begin
    if (i_mem_rd) begin
        o_mem_rdy <= 1; // Memory is ready to provide data
        o_mem_rdata <= {rom[i_mem_addr+3],rom[i_mem_addr+2],rom[i_mem_addr+1],rom[i_mem_addr]}; // instructions are present byte wise and are in little-endian format
        o_mem_vld <= 1; // Data is valid
    end else begin
        o_mem_rdy <= 0;
        o_mem_vld <= 0;
    end
end 
else begin
    o_mem_rdy <= 0;
    o_mem_vld <= 0;
end

end
    
endmodule

