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
    wire [31:0] fetch_to_imem_addr;  // Address from Fetch to ROM
    wire fetch_to_imem_valid;            // Ready signal from Fetch to ROM
    wire imem_to_fetch_rdy;        // Valid signal from ROM to Fetch
    wire [31:0] imem_to_fetch_data;  // Data output from ROM to Fetch
    wire imem_to_fetch_valid;
    
    // Instantiate the Fetch module
    Fetch fetch_inst (
        .clk(clk),
        .rst_n(rst_n),
        .i_instr(imem_to_fetch_data),
        .i_instr_vld(imem_to_fetch_valid),
        .i_imem_rdy(imem_to_fetch_rdy),
        .o_imem_vld(fetch_to_imem_valid),
        .o_iaddr(fetch_to_imem_addr),
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
        .i_mem_addr(fetch_to_imem_addr),
        .o_mem_rdata(imem_to_fetch_data),
        .o_rdata_vld(imem_to_fetch_valid),
        .i_mem_valid(fetch_to_imem_valid),
        .o_mem_ready(imem_to_fetch_rdy)
    );

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_fetch_rom_wrapper);
    end

endmodule

