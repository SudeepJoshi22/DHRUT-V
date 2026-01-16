import riscv_uop_pkg::*;

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

  // IF -> ID pipeline registers
  logic        if_id_valid;
  logic [31:0] if_id_pc;
  logic [31:0] if_id_instr;

  // ID -> IF stall
  logic        id_if_stall;

  // ID -> Issue
  logic        id_issue_valid;
  uop_t        id_issue_uop;
  logic [31:0] id_issue_pc;

  // Issue -> ALU (via interface)
  alu_issue_if alu_if(clk, rst_n);

  // Issue -> LSU (via interface) – instantiated but not used yet
  lsu_issue_if lsu_if(clk, rst_n);

  // LSU -> Retire
  logic         lsu_valid;
  uop_t         lsu_uop_forward;
  logic [31:0]  lsu_load_data;

  // ALU -> Retire
  logic        alu_retire_valid;
  logic [31:0] alu_retire_result;
  uop_t        alu_retire_uop;

  // Retire -> Issue (write-back)
  logic        retire_wb_en;
  logic [4:0]  retire_wb_rd;
  logic [31:0] retire_wb_data;

  // Branch from Issue -> IF
  logic        branch_taken;
  logic [31:0] branch_target;

  // ───────────────────────────────────────────────
  // IF Stage
  // ───────────────────────────────────────────────
  if_stage IF (
    .clk             (clk),
    .rst_n           (rst_n),
    .i_stall         (id_if_stall),
    .i_flush         (branch_taken),          // flush on branch taken
    .i_redirect_pc   (branch_target),         // branch/jump target
    .imem            (imem_if),
    .o_if_valid      (if_id_valid),
    .o_if_pc         (if_id_pc),
    .o_if_instr      (if_id_instr)
  );

  // ───────────────────────────────────────────────
  // Decode Stage
  // ───────────────────────────────────────────────
  decode_stage ID (
    .clk             (clk),
    .rst_n           (rst_n),
    .i_if_valid      (if_id_valid),
    .i_if_pc         (if_id_pc),
    .i_if_instr      (if_id_instr),
    .i_stall         (1'b0),
    .i_flush         (branch_taken),
    .o_dec_valid     (id_issue_valid),
    .o_uop           (id_issue_uop),
    .o_dec_pc        (id_issue_pc),
    .o_stall_to_if   (id_if_stall)
  );

  // ───────────────────────────────────────────────
  // Issue Stage
  // ───────────────────────────────────────────────
  issue_stage ISSUE (
    .clk             (clk),
    .rst_n           (rst_n),
    .i_dec_valid     (id_issue_valid),
    .i_uop           (id_issue_uop),
    .i_dec_pc        (id_issue_pc),
    .i_stall         (1'b0),
    .i_flush         (1'b0),
    .i_wb_en         (retire_wb_en),
    .i_wb_rd         (retire_wb_rd),
    .i_wb_data       (retire_wb_data),
    .o_branch_taken  (branch_taken),
    .o_branch_target (branch_target),
    .o_stall_to_decode (),                    // open for now
    .alu_if          (alu_if),
    .lsu_if          (lsu_if)
  );

  // ───────────────────────────────────────────────
  // ALU Stage
  // ───────────────────────────────────────────────
  alu_stage ALU (
    .clk             (clk),
    .rst_n           (rst_n),
    .issue_if        (alu_if),
    .i_stall         (1'b0),
    .i_flush         (1'b0),
    .o_valid         (alu_retire_valid),
    .o_alu_result    (alu_retire_result),
    .o_uop_forward   (alu_retire_uop)
  );

  // ───────────────────────────────────────────────
  // LSU Stage
  // ───────────────────────────────────────────────
  lsu LSU (
      .clk             (clk),
      .rst_n           (rst_n),
      .issue_if        (lsu_if),
      .dmem_if         (dmem_if.master),
      .o_valid         (lsu_valid),
      .o_load_data     (lsu_load_data),
      .o_lsu_uop       (lsu_uop_forward),
      .o_stall_from_lsu()
    );

  // ───────────────────────────────────────────────
  // Retire Stage
  // ───────────────────────────────────────────────
  retire RETIRE (
    .clk             (clk),
    .rst_n           (rst_n),
    .i_alu_valid     (alu_retire_valid),
    .i_alu_uop           (alu_retire_uop),
    .i_alu_result    (alu_retire_result),
    .i_lsu_valid     (lsu_valid),             
    .i_lsu_uop       (lsu_uop_forward),       
    .i_lsu_load_data (lsu_load_data),
    .i_flush         (1'b0),
    .i_stall         (1'b0),
    .o_wb_en         (retire_wb_en),
    .o_wb_rd         (retire_wb_rd),
    .o_wb_data       (retire_wb_data)
  );

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_top);
  end

endmodule
