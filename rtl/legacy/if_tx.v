module if_block (
    input wire clk,
    input wire reset,
    output reg tx_valid,
    input wire tx_ready,
    output reg [31:0] instruction_addr // 32-bit instruction address, 4-byte aligned
);

    reg [31:0] pc; // Program Counter
    reg tx_valid_next;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            tx_valid <= 0;
            pc <= 32'd0; // Start from the first instruction
        end else begin
            if (!tx_valid) begin
                // Assert valid as soon as we have a valid instruction address
                tx_valid <= 1;
                instruction_addr <= pc;
            end
            
            if (tx_ready && tx_valid) begin
                // Only update PC and continue when the handshake is successful
                pc <= pc + 4; // Increment PC to the next instruction (4-byte aligned)
                tx_valid <= 0; // Deassert valid until the next instruction is ready
            end
        end
    end
endmodule

