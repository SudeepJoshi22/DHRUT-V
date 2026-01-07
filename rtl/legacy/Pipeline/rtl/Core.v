module Core (
    input wire clk,
    input wire rst_n
);

// Internal signals for data flow between pipeline stages
reg [31:0] pct_in;
wire [31:0] fetch_to_decode;
wire [31:0] decode_to_execute;
wire [31:0] exec_result;

// Stall and flush signals between stages
wire fetch_stall;
wire fetch_flush;
wire decode_stall;
wire decode_flush;

// Instantiate the Fetch module
Fethch fetch_inst (
    .clk(clk),
    .rst_n(rst_n),
    .i_pct_in(pct_in),
    .i_stall(fetch_stall),
    .i_flush(fetch_flush),
    .o_pct_out(fetch_to_decode)
);

// Instantiate the Decode module
Decode decode_inst (
    .clk(clk),
    .rst_n(rst_n),
    .i_instr_in(fetch_to_decode),
    .i_stall(decode_stall),
    .i_flush(decode_flush),
    .o_decoded_instr(decode_to_execute),
    .o_stall(decode_stall),  // Forward stall signal to Execute
    .o_flush(decode_flush)    // Forward flush signal to Execute
);

// Instantiate the Execute module
Execute execute_inst (
    .clk(clk),
    .rst_n(rst_n),
    .i_decoded_instr(decode_to_execute),
    .o_exec_result(exec_result),
    .o_stall(fetch_stall),     // Forward stall signal to Fetch
    .o_flush(fetch_flush)      // Forward flush signal to Fetch
);

// Testbench logic integrated within Core
initial begin
    // Initialize signals
    pct_in = 32'h0000_0000;

    // Display output for debugging
    $monitor("Time: %t | pct_in: %h | fetch_out: %h | decode_out: %h | exec_result: %h | fetch_stall: %b | fetch_flush: %b | decode_stall: %b | decode_flush: %b", 
             $time, pct_in, fetch_to_decode, decode_to_execute, exec_result, fetch_stall, fetch_flush, decode_stall, decode_flush);

    // Apply reset
    rst_n = 1'b0;
    #5 rst_n = 1'b1;

    // Normal operation: increment pct_in
    #10 pct_in = 32'h0000_0004;
    #10 pct_in = 32'h0000_0008;

    // Test scenario: Stall and flush at Execute stage
    #10 decode_stall = 1'b1; // Simulate stall in Decode
    #10 decode_stall = 1'b0; // Release stall

    #10 decode_flush = 1'b1; // Simulate flush in Decode
    #10 decode_flush = 1'b0; // Release flush

    // Finish the simulation
    #50 $finish;
end

endmodule

