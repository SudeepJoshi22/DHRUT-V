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
    wire [31:0] fetch_to_rom_addr;  // Address from Fetch to ROM
    wire fetch_imem_rdy;            // Ready signal from Fetch to ROM
    wire rom_to_fetch_valid;        // Valid signal from ROM to Fetch
    wire [31:0] rom_to_fetch_data;  // Data output from ROM to Fetch

    // Instantiate the Fetch module
    Fetch fetch_inst (
        .clk(clk),
        .rst_n(rst_n),
        .i_instr(rom_to_fetch_data),
        .o_imem_rdy(fetch_imem_rdy),
        .i_imem_vld(rom_to_fetch_valid),
        .o_iaddr(fetch_to_rom_addr),
        .i_trap(i_trap),
        .i_trap_pc(i_trap_pc),
        .i_boj(i_boj),
        .i_boj_pc(i_boj_pc),
        .o_pc(o_pc),
        .o_instr(o_instr),
        .o_prediction(o_prediction),
        .i_stall(i_stall),
        .i_flush(i_flush)
    );

    // Instantiate the instr_rom module
    instr_rom rom_inst (
        .clk(clk),
        .rst_n(rst_n),
        .i_mem_addr(fetch_to_rom_addr),
        .o_mem_rdata(rom_to_fetch_data),
        .i_mem_ready(fetch_imem_rdy),
        .o_mem_valid(rom_to_fetch_valid)
    );

endmodule

