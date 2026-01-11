import riscv_uop_pkg::*;

module tb_top;

  logic         clk;
  logic         rst_n;

  mem_if imem_if(clk);

  // IF -> ID Signals
  logic         if_id_valid;
  logic [31:0]  if_id_pc;
  logic [31:0]  if_id_instr;
  
  // ID -> IF Signals
  logic         id_if_stall;

  // ID -> EX Signals
  logic         id_ex_valid;
  uop_t         id_ex_uop;
  logic [31:0]  id_ex_pc;

  if_stage IF(
    .clk            (clk),
    .rst_n          (rst_n),
    .i_stall        (1'b0),
    .i_flush        (1'b0),
    .i_redirect_pc  (32'b0),
    .imem           (imem_if),
    .o_if_valid     (if_id_valid),
    .o_if_pc        (if_id_pc),
    .o_if_instr     (if_id_instr)
  );

  decode_stage ID(
    .clk            (clk),
    .rst_n          (rst_n),

    .i_if_valid     (if_id_valid),
    .i_if_pc        (if_id_pc),
    .i_if_instr     (if_id_instr),

    .i_stall        (1'b0),
    .i_flush        (1'b0),

    .o_dec_valid    (id_ex_valid),
    .o_uop          (id_ex_uop),
    .o_dec_pc       (id_ex_pc),

    .o_stall_to_if  (id_if_stall)
  );

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_top);
  end

endmodule
