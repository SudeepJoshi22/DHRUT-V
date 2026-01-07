`include "rtl/if_tx.v"
`include "rtl/rom_rx.v"

module cpu_rom_system (
    input wire clk,
    input wire reset
);
    // Signals to connect IF block and ROM
    wire tx_valid;
    wire tx_ready;
    wire [31:0] instruction_addr;
    wire [31:0] instruction;

    // Instantiate the IF block
    if_block IF (
        .clk(clk),
        .reset(reset),
        .tx_valid(tx_valid),
        .tx_ready(tx_ready),
        .instruction_addr(instruction_addr)
    );

    // Instantiate the ROM
    rom ROM (
        .clk(clk),
        .reset(reset),
        .tx_valid(tx_valid),
        .tx_ready(tx_ready),
        .instruction_addr(instruction_addr),
        .instruction(instruction)
    );

    // For testing, you can monitor the instruction being fetched
    always @(posedge clk) begin
        if (tx_ready) begin
            $display("Time: %0t | Fetched Instruction: %h from Address: %h", $time, instruction, instruction_addr);
        end
    end

endmodule

