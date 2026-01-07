module tb_top;

  logic clk;
  logic rst_n;

  mem_if imem_if(clk);

  if_stage dut (
    .clk         (clk),
    .rst_n       (rst_n),
    .stall       (1'b0),
    .flush       (1'b0),
    .redirect_pc (32'b0),
    .imem        (imem_if),
    .if_valid    (),
    .if_pc       (),
    .if_instr    ()
  );

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_top);
  end

endmodule
