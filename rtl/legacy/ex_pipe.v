`include "rtl/ex_if.v"
`include "rtl/ex_id.v"

module pipeline_top(
    input clk,
    input reset,
    input stall_if,
    input stall_id,
    input flush_if,
    input flush_id,
    input [31:0] pc_in,
    output [31:0] pc_out,
    output [31:0] regA,
    output [31:0] regB
);
    wire [31:0] instruction;

    // Instantiate IF stage
    if_stage IF (
        .clk(clk),
        .reset(reset),
        .stall(stall_if),
        .flush(flush_if),
        .pc_in(pc_in),
        .pc_out(pc_out),
        .instruction(instruction)
    );

    // Instantiate ID stage
    id_stage ID (
        .clk(clk),
        .reset(reset),
        .stall(stall_id),
        .flush(flush_id),
        .instruction_in(instruction),
        .instruction_out(),
        .regA(regA),
        .regB(regB)
    );

endmodule

