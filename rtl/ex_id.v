module id_stage(
    input clk,
    input reset,
    input stall,
    input flush,
    input [31:0] instruction_in,
    output reg [31:0] instruction_out,
    output reg [31:0] regA,
    output reg [31:0] regB
);
    always @(posedge clk or posedge reset) begin
        if (reset || flush) begin
            instruction_out <= 0;
            regA <= 0;
            regB <= 0;
        end else if (!stall) begin
            instruction_out <= instruction_in;
            // Simulate register read
            regA <= instruction_in; // Example: data from register A
            regB <= instruction_in + 4; // Example: data from register B
        end
    end
endmodule
