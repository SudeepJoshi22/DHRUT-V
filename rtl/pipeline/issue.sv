import riscv_uop_pkg::*;

module issue_stage (
  input  logic        clk,
  input  logic        rst_n,

  // From Decode stage – direct signals
  input  logic        i_dec_valid,
  input  uop_t        i_uop,
  input  logic [31:0] i_dec_pc,

  // Stall & flush from downstream
  input  logic        i_stall,
  input  logic        i_flush,

  // From Retire/WB (write-back to ARF)
  input  logic        i_wb_en,
  input  logic [4:0]  i_wb_rd,
  input  logic [31:0] i_wb_data,

  // FORWARDING - From ALU
  input  logic        i_alu_fwd_writes_rd,
  input  logic [4:0]  i_alu_fwd_rd,
  input  logic [31:0] i_alu_fwd_data,

  // FORWARDING - From RETIRE
  input  logic        i_retire_fwd_writes_rd,
  input  logic [4:0]  i_retire_fwd_rd,
  input  logic [31:0] i_retire_fwd_data,

  // FORWARDING - From LSU
  input  logic        i_lsu_fwd_data_valid,
  input  logic [4:0]  i_lsu_fwd_rd,
  input  logic [31:0] i_lsu_fwd_data,

  // To Fetch – direct branch/jump signals (no interface)
  output logic        o_branch_taken,
  output logic [31:0] o_branch_target,

  // Stall back to Decode/IF
  output logic        o_stall_to_decode,

  // Issued to ALU
  alu_issue_if.issuer alu_if,

  // Issued to LSU (with back-pressure)
  lsu_issue_if.issuer lsu_if
);

  // ───────────────────────────────────────────────
  // 1. Input Pipeline Registers + Dispatched Flag
  // ───────────────────────────────────────────────
  logic dec_valid_q;
  logic issued;
  uop_t uop_q;
  logic [31:0] dec_pc_q;
 
  logic        stall_issue;

  assign       stall_issue = i_stall || lsu_if.s_stall_from_lsu;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || i_flush) begin
      dec_valid_q <= 1'b0;
      uop_q       <= '0;
      dec_pc_q    <= '0;
    end
    else if (!stall_issue) begin
      dec_valid_q <= i_dec_valid;
      uop_q       <= i_uop;
      dec_pc_q    <= i_dec_pc;
    end
  end

  // ───────────────────────────────────────────────
  // 2. Register File (ARF) inside Issue
  // ───────────────────────────────────────────────
  logic [31:0] rs1_data, rs2_data;

  ARF rf (
    .clk           (clk),
    .rst_n         (rst_n),
    .i_re          (dec_valid_q),
    .i_wr          (i_wb_en),
    .i_rs1         (uop_q.rs1),
    .i_rs2         (uop_q.rs2),
    .i_rd          (i_wb_rd),
    .i_write_data  (i_wb_data),
    .o_read_data1  (rs1_data),
    .o_read_data2  (rs2_data)
  );


    // Forwarding logic 
  logic [31:0] fwd_rs1, fwd_rs2;
  
  always_comb begin
    fwd_rs1 = rs1_data;
    fwd_rs2 = rs2_data;
  
    // ALU has highest priority
    if (i_alu_fwd_writes_rd && (i_alu_fwd_rd == uop_q.rs1) && (uop_q.rs1 != 5'd0)) begin
      fwd_rs1 = i_alu_fwd_data;
    end
    else if (i_retire_fwd_writes_rd && (i_retire_fwd_rd == uop_q.rs1) && (uop_q.rs1 != 5'd0)) begin
      fwd_rs1 = i_retire_fwd_data;
    end
    else if (i_lsu_fwd_data_valid && (i_lsu_fwd_rd == uop_q.rs1) && (uop_q.rs1 != 5'd0)) begin
      fwd_rs1 = i_lsu_fwd_data;
    end
    
    if (i_alu_fwd_writes_rd && (i_alu_fwd_rd == uop_q.rs2) && (uop_q.rs2 != 5'd0)) begin
      fwd_rs2 = i_alu_fwd_data;
    end
    else if (i_retire_fwd_writes_rd && (i_retire_fwd_rd == uop_q.rs2) && (uop_q.rs2 != 5'd0)) begin
      fwd_rs2 = i_retire_fwd_data;
    end
    else if (i_lsu_fwd_data_valid && (i_lsu_fwd_rd == uop_q.rs2) && (uop_q.rs2 != 5'd0)) begin
      fwd_rs2 = i_lsu_fwd_data;
    end
  end

  // ───────────────────────────────────────────────
  // 3. Operand multiplexing (with forwarding)
  // ───────────────────────────────────────────────
  logic [31:0] op1, op2;
  
  always_comb begin
    // op1: rs1 (forwarded) or PC (for AUIPC)
    op1 = uop_q.uses_rs1 ? fwd_rs1 : (uop_q.opcode == OPCODE_AUIPC) ? dec_pc_q : 'd0;
  
    // op2: special case for JAL/JALR (return address increment = +4)
    //       otherwise immediate or rs2 (forwarded)
    op2 = (uop_q.opcode inside {OPCODE_JAL, OPCODE_JALR}) ? 32'd4 :
          uop_q.is_immediate ? uop_q.imm : fwd_rs2;
  end

  // ───────────────────────────────────────────────
  // 4. Branch/jump decision & target
  // ───────────────────────────────────────────────
  always_comb begin
    o_branch_taken  = 1'b0;
    o_branch_target = 32'b0;

    if (dec_valid_q) begin
      case (uop_q.opcode)
        OPCODE_BRANCH: begin
          o_branch_target = dec_pc_q + uop_q.imm;

          case (uop_q.alu_op)
            ALU_ADD:  o_branch_taken = (op1 == op2);                     // BEQ
            ALU_SUB:  o_branch_taken = (op1 != op2);                     // BNE
            ALU_SLT:  o_branch_taken = (op1[31] != op2[31]) ? op1[31] : (op1[30:0] < op2[30:0]);    // BLT
            ALU_OR:   o_branch_taken = (op1[31] != op2[31]) ? ~op1[31] : (op1[30:0] >= op2[30:0]);  // BGE
            ALU_SLTU: o_branch_taken = (op1 < op2);                      // BLTU
            ALU_AND:  o_branch_taken = (op1 >= op2);                     // BGEU
            default:  o_branch_taken = 1'b0;
          endcase
        end

        OPCODE_JAL: begin
          o_branch_taken  = 1'b1;
          o_branch_target = dec_pc_q + uop_q.imm;
        end

        OPCODE_JALR: begin
          o_branch_taken  = 1'b1;
          o_branch_target = (fwd_rs1 + uop_q.imm) & ~32'd1;
        end
        default: begin
          o_branch_taken  = 1'b0;
          o_branch_target = 'd0;
        end
      endcase
    end
  end

  // ───────────────────────────────────────────────
  // 5. Dispatch to ALU or LSU
  // ───────────────────────────────────────────────
  always_comb begin
    alu_if.m_valid       = 1'b0;
    lsu_if.m_valid       = 1'b0;

    alu_if.m_uop         = '0;
    lsu_if.m_uop         = '0;

    alu_if.m_pc          = dec_pc_q;
    lsu_if.m_pc          = dec_pc_q;

    alu_if.m_op1         = op1;
    alu_if.m_op2         = op2;

    lsu_if.m_addr_base   = op1;
    lsu_if.m_store_data  = op2;

    issued               = dec_valid_q && !stall_issue && !i_flush;

    if (issued) begin
      case (uop_q.opcode)
        // Compute/arithmetic/jump/branch → ALU
        OPCODE_OP, OPCODE_OP_IMM, OPCODE_LUI, OPCODE_AUIPC,
        OPCODE_BRANCH, OPCODE_JAL, OPCODE_JALR: begin
          alu_if.m_valid = 1'b1;
          alu_if.m_uop   = uop_q;
        end

        // Load/Store → LSU
        OPCODE_LOAD, OPCODE_STORE: begin
          lsu_if.m_valid       = 1'b1;
          lsu_if.m_uop         = uop_q;
        end
        default: begin
          alu_if.m_valid       = 1'b0;
          lsu_if.m_valid       = 1'b0;
        end
      endcase
    end
  end

  // ───────────────────────────────────────────────
  // 6. Stall propagation back to Decode/IF
  // ───────────────────────────────────────────────
  assign o_stall_to_decode = i_stall || lsu_if.s_stall_from_lsu;

  // Consume the latched valid when dispatched
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || i_flush) begin
      dec_valid_q <= 1'b0;
    end
    else if (issued) begin
      dec_valid_q <= 1'b0;  // clear after dispatch
    end
  end

endmodule
