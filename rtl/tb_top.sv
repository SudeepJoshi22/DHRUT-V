module tb_top;

  logic         clk;
  logic         rst_n;

  mem_if imem_if(
    .clk(clk),
    .rst_n(rst_n)
  );

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
