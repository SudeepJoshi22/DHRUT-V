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

    // Address Interface (consumer)
    input wire [31:0] i_addr,
    input wire i_stb,
    // Data Interface (producer)
    output reg [31:0] o_data,
    output reg o_data_vld
);

    // Memory array to store instructions, each instruction is 4 bytes (32 bits)
    // Use an address range starting from `PC_RESET`, ensuring the address is 4-byte aligned
    reg [7:0] rom[`PC_RESET + `INSTR_MEM_SIZE - 1 : `PC_RESET];  // 8-bit memory for byte-wise storage
    
    // Initialize ROM contents from a file
    initial begin
        // Assuming the instructions are in hexadecimal format in the .mem file
        $readmemh("programs/instr_mem.mem", rom);
    end

    // Data output and o_data_vld signal logic
    always @(posedge clk or negedge rst_n) begin
		if (~rst_n) begin
			o_data <= 32'b0;
			o_data_vld <= 1'b0;
		end 
		else begin
			// Output data in little-endian byte order (4-byte aligned)
			o_data <= {rom[i_addr+3], rom[i_addr+2], rom[i_addr+1], rom[i_addr]}; // Little-endian
			o_data_vld <= i_stb;
		end 
	end

endmodule


