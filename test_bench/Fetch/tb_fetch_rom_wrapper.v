module tb_fetch_rom_wrapper (
    input wire clk,
    input wire rst_n,
    // External control inputs for testing
    input wire i_trap,
    input wire [31:0] i_trap_pc,
    input wire i_boj,
    input wire [31:0] i_boj_pc,
    input wire i_stall,
    input wire i_flush,
    output wire [31:0] o_pc,      // Current PC value from Fetch
    output wire [31:0] o_instr,   // Fetched instruction from Fetch
    output wire o_prediction      // Prediction output from Fetch
);
 // Internal signals to connect Fetch and instr_rom
    wire [31:0] fetch_to_imem_addr;   // Address from Fetch to ROM
    wire fetch_to_imem_valid;         // Valid signal from Fetch to ROM
    wire imem_to_fetch_rdy;          // Ready signal from ROM to Fetch
    wire fetch_to_imem_rdy;
    wire [31:0] imem_to_fetch_data;  // Data output from ROM to Fetch
    wire imem_to_fetch_valid;        // Valid signal from ROM to Fetch

    // Instantiate the Fetch module
    Fetch fetch_inst (
        .clk(clk),
        .rst_n(rst_n),

        // Instruction memory interface signals
        .i_rom_instr(imem_to_fetch_data),       // ROM data input to Fetch
        .i_rom_instr_vld(imem_to_fetch_valid),  // ROM data valid signal to Fetch
        .o_fetch_rdy(fetch_to_imem_rdy),        // Fetch ready signal to ROM
        .o_fetch_addr(fetch_to_imem_addr),      // Fetch address to ROM
        .o_fetch_vld(fetch_to_imem_valid),      // Fetch valid signal to ROM
        .i_rom_rdy(imem_to_fetch_rdy),

        // IF-CSr Interface (trap and branch)
        .i_trap(i_trap),
        .i_trap_pc(i_trap_pc),
        .i_boj(i_boj),
        .i_boj_pc(i_boj_pc),

        // IF-ID Interface
        .o_pc(o_pc),
        .o_instr(o_instr),
        .o_prediction(o_prediction),

        // Pipeline control
        .i_stall(i_stall),
        .i_flush(i_flush)
    );

    // Instantiate the instr_rom module
    instr_rom rom_inst (
        .clk(clk),
        .rst_n(rst_n),

        // Address Interface
        .i_addr(fetch_to_imem_addr),     // Address from Fetch to ROM
        .i_addr_vld(fetch_to_imem_valid),// Valid signal from Fetch to ROM
        .o_rom_rdy(imem_to_fetch_rdy),   // Ready signal from ROM to Fetch

        // Data Interface
        .o_data(imem_to_fetch_data),     // Data from ROM to Fetch
        .o_data_vld(imem_to_fetch_valid),// Valid data from ROM to Fetch
        .i_fetch_rdy(fetch_to_imem_rdy)  // Fetch ready signal to ROM
    );

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_fetch_rom_wrapper);
    end

endmodule

