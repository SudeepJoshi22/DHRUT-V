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
  logic        if_id_pred_taken;
  logic [31:0] if_id_pred_target;

  // IF <-> BPU (prediction port)
  logic        bpu_pred_is_branch;
  logic [31:0] bpu_pred_pc;
  logic [31:0] bpu_pred_offset_pc;
  logic        bpu_pred_taken;
  logic [31:0] bpu_pred_target;

  // Issue -> BPU (update/training port)
  logic        bpu_update_valid;
  logic [31:0] bpu_update_pc;
  logic        bpu_update_taken;
  logic [31:0] bpu_update_target;

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

  // Branch from Issue -> IF (actual resolved outcome, used to train BPU)
  logic        branch_taken;
  logic [31:0] branch_target;

  // Misprediction redirect from Issue -> IF/ID/self (decoupled from
  // the actual-outcome signals above)
  logic        mispredict;
  logic [31:0] redirect_pc;

  // Operand Forwarding from ALU -> ISSUE
  
  logic [4:0]  fwd_alu_issue_rd;
  logic [31:0] fwd_alu_issue_data;
  logic        fwd_alu_issue_writes_rd; 

  // Opeerand Forwarding from LSU -> ISSUE
  
  logic [4:0]  fwd_lsu_issue_rd;
  logic [31:0] fwd_lsu_issue_data;
  
  // Operand Forwarding from RETIRE -> ISSUE
  
  logic [4:0]  fwd_retire_issue_rd;
  logic [31:0] fwd_retire_issue_data;
  logic        fwd_retire_issue_writes_rd; 

  // Downstream Stalls
  logic        lsu_to_issue_stall;
  logic        issue_to_decode_stall;
  logic        decode_to_fetch_stall;

  // ───────────────────────────────────────────────
  // IF Stage
  // ───────────────────────────────────────────────
  if_stage IF (
    .clk             (clk),
    .rst_n           (rst_n),
    .i_stall         (decode_to_fetch_stall),
    .i_flush         (mispredict),            // flush only on actual misprediction
    .i_redirect_pc   (redirect_pc),           // corrected redirect target
    .imem            (imem_if),
    .o_bpu_pred_is_branch (bpu_pred_is_branch),
    .o_bpu_pred_pc        (bpu_pred_pc),
    .o_bpu_pred_offset_pc (bpu_pred_offset_pc),
    .i_bpu_pred_taken     (bpu_pred_taken),
    .i_bpu_pred_target    (bpu_pred_target),
    .o_if_valid      (if_id_valid),
    .o_if_pc         (if_id_pc),
    .o_if_instr      (if_id_instr),
    .o_if_pred_taken  (if_id_pred_taken),
    .o_if_pred_target (if_id_pred_target)
  );

  // ───────────────────────────────────────────────
  // Branch Prediction Unit (BPU)
  // ───────────────────────────────────────────────
  bpu BPU (
    .clk                 (clk),
    .rst_n               (rst_n),
    .i_is_branch_pred    (bpu_pred_is_branch),
    .i_branch_pc_pred    (bpu_pred_pc),
    .i_offset_pc_pred    (bpu_pred_offset_pc),
    .o_prediction        (bpu_pred_taken),
    .o_predicted_pc      (bpu_pred_target),
    .i_branch_pc_update  (bpu_update_pc),
    .i_taken_update      (bpu_update_taken),
    .i_update_valid      (bpu_update_valid),
    .i_update_target_pc  (bpu_update_target)
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
    .i_if_pred_taken  (if_id_pred_taken),
    .i_if_pred_target (if_id_pred_target),
    .i_stall         (issue_to_decode_stall),
    .i_flush         (mispredict),
    .o_dec_valid     (id_issue_valid),
    .o_uop           (id_issue_uop),
    .o_dec_pc        (id_issue_pc),
    .o_stall_to_if   (decode_to_fetch_stall)
  );

  // ───────────────────────────────────────────────
  // Issue Stage
  // ───────────────────────────────────────────────
  issue_stage ISSUE (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .i_dec_valid            (id_issue_valid),
    .i_uop                  (id_issue_uop),
    .i_dec_pc               (id_issue_pc),
    .i_stall                (1'b0),
    .i_flush                (mispredict),
    .i_wb_en                (retire_wb_en),
    .i_wb_rd                (retire_wb_rd),
    .i_wb_data              (retire_wb_data),
    .i_alu_fwd_writes_rd    (fwd_alu_issue_writes_rd),
    .i_alu_fwd_rd           (fwd_alu_issue_rd),
    .i_alu_fwd_data         (fwd_alu_issue_data),
    .i_retire_fwd_writes_rd (fwd_retire_issue_writes_rd),
    .i_retire_fwd_rd        (fwd_retire_issue_rd),
    .i_retire_fwd_data      (fwd_retire_issue_data),
    .i_lsu_fwd_data_valid   (lsu_valid),
    .i_lsu_fwd_rd           (lsu_uop_forward.rd),
    .i_lsu_fwd_data         (lsu_load_data),
    .o_branch_taken         (branch_taken),
    .o_branch_target        (branch_target),
    .o_resolved_pc          (bpu_update_pc),
    .o_update_valid         (bpu_update_valid),
    .o_mispredict           (mispredict),
    .o_redirect_pc          (redirect_pc),
    .o_stall_to_decode      (issue_to_decode_stall),
    .alu_if                 (alu_if),
    .lsu_if                 (lsu_if)
  );

  // BPU update/training port is driven from Issue's actual resolved outcome
  assign bpu_update_taken  = branch_taken;
  assign bpu_update_target = branch_target;

  // ───────────────────────────────────────────────
  // ALU Stage
  // ───────────────────────────────────────────────
  alu_stage ALU (
    .clk             (clk),
    .rst_n           (rst_n),
    .issue_if        (alu_if),
    .i_stall         (lsu_if.s_stall_from_lsu),
    .i_flush         (1'b0),
    .o_alu_fwd_writes_rd    (fwd_alu_issue_writes_rd),
    .o_alu_fwd_rd           (fwd_alu_issue_rd),
    .o_alu_fwd_result       (fwd_alu_issue_data),
    .o_valid         (alu_retire_valid),
    .o_alu_result    (alu_retire_result),
    .o_uop_forward   (alu_retire_uop)
  );

  // ───────────────────────────────────────────────
  // LSU Stage
  // ───────────────────────────────────────────────
  lsu LSU (
      .clk                  (clk),
      .rst_n                (rst_n),
      .issue_if             (lsu_if),
      .dmem_if              (dmem_if.master),
      //.o_lsu_fwd_rd         (fwd_lsu_issue_rd),   
      //.o_lsu_fwd_result     (fwd_lsu_issue_data),
      .o_valid              (lsu_valid),
      .o_load_data          (lsu_load_data),
      .o_lsu_uop            (lsu_uop_forward)
    );

  // ───────────────────────────────────────────────
  // Retire Stage
  // ───────────────────────────────────────────────
  retire RETIRE (
    .clk             (clk),
    .rst_n           (rst_n),
    .i_alu_valid     (alu_retire_valid),
    .i_alu_uop       (alu_retire_uop),
    .i_alu_result    (alu_retire_result),
    .i_lsu_valid     (lsu_valid),             
    .i_lsu_uop       (lsu_uop_forward),       
    .i_lsu_load_data (lsu_load_data),
    .i_flush         (1'b0),
    .i_stall         (1'b0),
    .o_retire_fwd_writes_rd (fwd_retire_issue_writes_rd),
    .o_retire_fwd_rd        (fwd_retire_issue_rd),
    .o_retire_fwd_result    (fwd_retire_issue_data), 
    .o_wb_en         (retire_wb_en),
    .o_wb_rd         (retire_wb_rd),
    .o_wb_data       (retire_wb_data)
  );

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_top);
  end

endmodule
