module if_stage(
    input clk,
    input reset,
    input stall,
    input flush,
    input [31:0] pc_in,
    output reg [31:0] pc_out,
    output reg [31:0] instruction
);
    always @(posedge clk or posedge reset) begin
        if (reset || flush) begin
            pc_out <= 0;
            instruction <= 0;
        end else if (!stall) begin
            pc_out <= pc_in;
            // Simulate instruction fetch
            instruction <= pc_in + 4; // Example: next PC (simple case)
        end
    end
endmodule

