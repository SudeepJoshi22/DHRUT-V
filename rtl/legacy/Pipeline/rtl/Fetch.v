module Fethch(
	input wire clk,
	input wire rst_n,
	input wire [31:0] i_pct_in,
	input wire i_stall,
	input wire i_flush,
	output wire [31:0] o_pct_out
);

// Internal Registers
reg [31:0] ir_pct;

// Sequential Logic to Process Packet
always @(posedge clk) begin
	if(!rst_n) begin
		ir_pct <= 32'd0;
	end
	else if(i_flush) begin
		ir_pct <= 32'd0;
	end
	else if(!i_stall) begin
		ir_pct <= ir_pct + 32'd4;
	end
end

// Drive the output packet
assign o_pct_out = ir_pct;

// Prints for debug
initial begin
	$monitor("At Time:%t --- i_pct_in: %h, ir_pct: %h, o_pct_out: %h ", $time, i_pct_in, ir_pct, o_pct_out);
end

endmodule
