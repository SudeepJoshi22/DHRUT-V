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

module instr_mem(
    input wire clk,
    input wire rst_n, // active low reset
    input wire [31:0] i_addr, // instruction address
    input wire i_stb, // request for instruction
    output reg o_ack, // acknowledge signal
    output reg [31:0] o_data // instruction code
);

reg [7:0] memory[`PC_RESET + `INSTR_MEM_SIZE : `PC_RESET];
reg [31:0] delay_counter; // Countdown for introducing delay
reg [31:0] latched_addr;  // Latch the address during delay

initial begin
    $readmemh("instr_mem.mem", memory);
    o_data <= 32'd0;
    o_ack <= 1'b0;
    delay_counter <= 0;
    latched_addr <= 0;
end

always @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        o_ack <= 1'b0;
        o_data <= 32'd0;
        delay_counter <= 0;
        latched_addr <= 0;
    end else begin
        if (delay_counter > 0) begin
            // Handle delay countdown
            delay_counter <= delay_counter - 1;
            // Provide response when counter reaches 1 (next cycle it will be 0)
            if (delay_counter == 1) begin
                o_ack <= 1'b1;
                o_data <= {memory[latched_addr+3], memory[latched_addr+2], 
                           memory[latched_addr+1], memory[latched_addr]};
            end else begin
                o_ack <= 1'b0;
                o_data <= 32'd0;
            end
        end else begin
            // No ongoing delay, check new request
            o_ack <= 1'b0;
            o_data <= 32'd0;
            if (i_stb && ((i_addr & 3) == 0)) begin
                // 10% chance to introduce delay (simulation only)
                if ($urandom_range(9) == 0) begin
                    // Random delay between 1-10 cycles
                    delay_counter <= $urandom_range(10, 1);
                    latched_addr <= i_addr; // Latch the current address
                end else begin
                    // No delay, respond immediately
                    o_ack <= 1'b1;
                    o_data <= {memory[i_addr+3], memory[i_addr+2], 
                               memory[i_addr+1], memory[i_addr]};
                end
            end
        end
    end
end

endmodule
