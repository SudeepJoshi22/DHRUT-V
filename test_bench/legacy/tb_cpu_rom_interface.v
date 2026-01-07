module tb_cpu_rom_system;

    reg clk;
    reg reset;

    // Instantiate the CPU-ROM system
    cpu_rom_system DUT (
        .clk(clk),
        .reset(reset)
    );

    // Clock generation
    always #5 clk = ~clk; // 100 MHz clock

    initial begin
        // Initialize signals
        clk = 0;
        reset = 1;

        // Setup waveform dump
        $dumpfile("waveform.vcd");   // Name of the output file
        $dumpvars(0, tb_cpu_rom_system); // Dump all variables in the testbench

        // Apply reset
        #10;
        reset = 0;

        // Let the simulation run for a few cycles
        #200;

        $finish; // Stop the simulation
    end
endmodule

