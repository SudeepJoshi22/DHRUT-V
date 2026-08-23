module tb_top;

  logic         clk;
  logic         rst_n;

  // Instruction fetch is 64-bit: one access returns the two instructions
  // of an 8-byte aligned block (see rtl/pipeline/ifetch.sv).
  mem_if #(.DATA_W(64)) imem_if(
    .clk(clk),
    .rst_n(rst_n)
  );

  // Data side stays 32-bit.
  mem_if dmem_if(
    .clk(clk),
    .rst_n(rst_n)
  );

  cpu_core CORE (
    .clk     (clk),
    .rst_n   (rst_n),
    .imem_if (imem_if.master),
    .dmem_if (dmem_if.master)
  );

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_top);
  end

endmodule
