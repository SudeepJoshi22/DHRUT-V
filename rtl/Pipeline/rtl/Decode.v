module Decode (
    input wire clk,
    input wire rst_n,
    input wire [31:0] i_instr_in,
    input wire i_stall,
    input wire i_flush,
    output wire [31:0] o_decoded_instr,
    output wire o_stall,
    output wire o_flush,
);

// Internal register to hold the decoded instruction
reg [31:0] decoded_instr;
reg ir_stall;

// Sequential Logic to decode the instruction
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        decoded_instr <= 32'd0; // Reset logic
    end
    else if (i_flush) begin
        decoded_instr <= 32'd0; // Flush logic
    end
    else if (!i_stall) begin
        decoded_instr <= i_instr_in; // Decode logic placeholder
    end
end
// For stall
always @(posedge clk) begin
	if(!rst_n) begin
		ir_stall <= 1'b0;
	end
	else if(i_stall) begin
		ir_stall <= 1'b1;
	end
	else begin
		ir_stall <= 1'b0;
	end
end

// Drive the output decoded instruction
assign o_decoded_instr = decoded_instr;
assign o_stall = ir_stall;

// Prints for debug
initial begin
    $monitor("At Time: %t --- i_instr_in: %h, decoded_instr: %h, o_decoded_instr: %h, i_stall: %b, ir_stall: %b", $time, i_instr_in, decoded_instr, o_decoded_instr,i_stall,ir_stall);
end

// EXPERIMENT
// Flush if packet hits 0xff
assign o_flush = (decoded_instr == 0xff) ? 1'b1 : 1'b0;

endmodule
