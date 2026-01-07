module rom (
    input wire clk,
    input wire reset,
    input wire tx_valid,
    output reg tx_ready,
    input wire [31:0] instruction_addr,
    output reg [31:0] instruction // 32-bit instruction
);

    reg [7:0] memory [0:1023]; // 1KB ROM, 8 bits (1 byte) wide

    initial begin
        // Initialize ROM with instructions (for simulation purposes)
        // For real hardware, this would be loaded from an external source
        $readmemh("programs/instr_mem.mem", memory);
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            tx_ready <= 0;
            instruction <= 32'd0;
        end else begin
            if (tx_valid) begin
                // Fetch the 32-bit instruction (4 bytes) from memory
                instruction <= {memory[instruction_addr + 3],
                                memory[instruction_addr + 2],
                                memory[instruction_addr + 1],
                                memory[instruction_addr]};

                tx_ready <= 1; // Indicate that the instruction is ready
            end else begin
                tx_ready <= 0;
            end
        end
    end
endmodule

