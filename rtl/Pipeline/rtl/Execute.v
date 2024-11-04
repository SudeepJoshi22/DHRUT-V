module Execute (
    input wire clk,
    input wire rst_n,
    input wire [31:0] i_decoded_instr,
    output wire [31:0] o_exec_result,
    output wire o_stall,
    output wire o_flush
);

// Internal register to hold the execution result
reg [31:0] exec_result;

// Sequential Logic to execute instruction
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    	    exec_result <= 32'd0; // Reset logic
    end
    else begin
	    exec_result <= exec_result + 32'd4;
    end

end


// Drive the output execution result
assign o_exec_result = exec_result;

// Prints for debug
initial begin
    $monitor("At Time: %t --- i_decoded_instr: %h, exec_result: %h, o_exec_result: %h", $time, i_decoded_instr, exec_result, o_exec_result);
end

// EXPERIMENT
// Stall and flush after reaching 0xf
assign o_stall = (exec_result == 0xf) ? 1'b1: 1'b0;
assign o_flush = (exec_result == 0xf) ? 1'b1: 1'b0;

endmodule

