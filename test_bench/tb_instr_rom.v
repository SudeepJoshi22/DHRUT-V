`include "rtl/parameters.vh"

module tb_instr_rom;

    // Inputs
    reg clk;
    reg rst_n;
    reg [31:0] i_mem_addr;
    reg i_mem_ready;


    integer i;
    // Outputs
    wire [31:0] o_mem_rdata;
    wire o_mem_valid;

    // Instantiate the module under test
    instr_rom dut (
        .clk(clk),
        .rst_n(rst_n),
        .i_mem_addr(i_mem_addr),
        .o_mem_rdata(o_mem_rdata),
        .i_mem_ready(i_mem_ready),
        .o_mem_valid(o_mem_valid)
    );

    // Clock generation
    always begin
        clk = 0;
        #5;
        clk = 1;
        #5;
    end

    // Reset initialization
    initial begin
        // Open VCD file for waveform dumping
        $dumpfile("waveform.vcd");
        $dumpvars(0, tb_instr_rom);

        rst_n = 0;
        #10;
        rst_n = 1;
        #50;

        // Generate addresses starting from PC_RESET and incrementing by 4
        i_mem_addr = `PC_RESET;
        i_mem_ready = 1;

        for (i = 0; i < 5; i = i + 1) begin
            #10;  // Delay for 10 clock cycles
            i_mem_addr = i_mem_addr + 4;
        end

	i_mem_ready = 0;
	
        for (i = 0; i < 5; i = i + 1) begin
            #10;  // Delay for 10 clock cycles
            i_mem_addr = i_mem_addr + 4;
        end

        // Finish simulation
        $finish;
    end

endmodule

