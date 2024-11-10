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

// Internal wires between Fetch and instr_rom
wire [31:0] fetch_to_rom_addr;
wire fetch_strobe;
wire [31:0] i_rom_instr;   // Instruction data from ROM
wire i_instr_vld;          // Instruction valid signal from ROM

// Instantiate Fetch module
Fetch u_fetch (
	.clk(clk),
	.rst_n(rst_n),
	.i_rom_instr(i_rom_instr),
	.i_instr_vld(i_instr_vld),
	.o_iaddr(fetch_to_rom_addr),
	.o_fetch_rdy(o_fetch_rdy),
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

// Instantiate instr_rom module
instr_rom u_instr_rom (
	.clk(clk),
	.rst_n(rst_n),
	.i_addr(fetch_to_rom_addr),
	.i_stb(o_fetch_rdy),       // Strobe when fetch is ready
	.o_data(i_rom_instr),      // Instruction data to Fetch
	.o_data_vld(i_instr_vld)   // Instruction valid signal to Fetch
);
 
initial begin
	$dumpfile("dump.vcd");
	$dumpvars(0, tb_fetch_rom_wrapper);
end

endmodule

