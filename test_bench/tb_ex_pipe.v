module pipeline_tb;
    reg clk;
    reg reset;
    reg stall_if;
    reg stall_id;
    reg flush_if;
    reg flush_id;
    reg [31:0] pc_in;
    wire [31:0] pc_out;
    wire [31:0] regA;
    wire [31:32] regB;

    // Instantiate top-level module
    pipeline_top DUT (
        .clk(clk),
        .reset(reset),
        .stall_if(stall_if),
        .stall_id(stall_id),
        .flush_if(flush_if),
        .flush_id(flush_id),
        .pc_in(pc_in),
        .pc_out(pc_out),
        .regA(regA),
        .regB(regB)
    );

    // Clock generation
    always #5 clk = ~clk; // 10ns clock period

    initial begin
        // Initialize signals
        clk = 0;
        reset = 1;
        stall_if = 0;
        stall_id = 0;
        flush_if = 0;
        flush_id = 0;
        pc_in = 0;

        // Reset the system
        #10 reset = 0;

        // Basic operation (no stalls, no flushes)
        #10 pc_in = 32'h00000004;

        // Introduce stall in IF stage for multiple cycles
        #10 stall_if = 1;
        #20 stall_if = 0;  // Stall for 2 clock cycles

        // Continue operation
        #10 pc_in = 32'h00000008;

        // Introduce stall in ID stage for multiple cycles
        #10 stall_id = 1;
        #30 stall_id = 0;  // Stall for 3 clock cycles

        // Continue operation
        #10 pc_in = 32'h0000000C;

        // Introduce flush in IF stage
        #10 flush_if = 1;
        #10 flush_if = 0;

        // Continue operation
        #10 pc_in = 32'h00000010;

        // Introduce flush in ID stage and stall IF stage simultaneously
        #10 flush_id = 1;
        stall_if = 1;
        #20 flush_id = 0;
        stall_if = 0;

        // Continue operation
        #10 pc_in = 32'h00000014;

        // End the simulation
        #50 $finish;
    end

    // Dump waveforms to file
    initial begin
        $dumpfile("waveform.vcd");
        $dumpvars(0, pipeline_tb);
    end
endmodule

