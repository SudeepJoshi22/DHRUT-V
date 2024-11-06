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

module instr_rom (
input wire clk,
input wire rst_n,
input wire [31:0] i_mem_addr,
output reg [31:0] o_mem_rdata,
input wire i_mem_ready,
output reg o_mem_valid
);

// Internal ROM storage
reg [7:0] rom[`PC_RESET + `INSTR_MEM_SIZE : `PC_RESET];

// Initialize ROM contents from a file
initial begin
$readmemh("programs/instr_mem.mem", rom);
end

// Valid signal
always @(posedge clk) begin
	if(!rst_n) begin
		o_mem_valid <= 1'b0;
	end
	else begin
		o_mem_valid <= 1'b1;
	end
end

// Read Data
always @(posedge clk) begin
	if(!rst_n) begin
		o_mem_rdata <= 32'dz;
	end
	else if(o_mem_valid & i_mem_ready) begin
		o_mem_rdata <= {rom[i_mem_addr+3],rom[i_mem_addr+2],rom[i_mem_addr+1],rom[i_mem_addr]};
	end
	else begin
		o_mem_rdata <= 32'dz;
	end
end
    
endmodule

