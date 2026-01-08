module tb_top;

  logic clk;
  logic rst_n;

  mem_if imem_if(clk);

  if_stage dut (
    .clk         (clk),
    .rst_n       (rst_n),
    .i_stall       (1'b0),
    .i_flush       (1'b0),
    .i_redirect_pc (32'b0),
    .imem        (imem_if),
    .o_if_valid    (),
    .o_if_pc       (),
    .o_if_instr    ()
  );

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_top);
  end

endmodule
