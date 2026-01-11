import riscv_uop_pkg::*;

module decode_stage (
  input  logic        clk,
  input  logic        rst_n,

  // From IF (unregistered inputs)
  input  logic        i_if_valid,
  input  logic [31:0] i_if_pc,
  input  logic [31:0] i_if_instr,

  // Stall & flush control inputs
  input  logic        i_stall,      // from later stages
  input  logic        i_flush,

  // Outputs to EX
  output logic        o_dec_valid,
  output uop_t        o_uop,
  output logic [31:0] o_dec_pc,

  // Stall request output to IF
  output logic        o_stall_to_if
);

  // ───────────────────────────────────────────────
  // 1. IF/ID pipeline register (at beginning of ID)
  // ───────────────────────────────────────────────
  logic        id_valid_q;
  logic [31:0] id_pc_q;
  logic [31:0] id_instr_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || i_flush) begin
      id_valid_q  <= 1'b0;
      id_pc_q     <= '0;
      id_instr_q  <= '0;
    end
    else if (!i_stall) begin
      id_valid_q  <= i_if_valid;
      id_pc_q     <= i_if_pc;
      id_instr_q  <= i_if_instr;
    end
    // else: stall → hold current values
  end

  // ───────────────────────────────────────────────
  // 2. Stall request to upstream (IF)
  // ───────────────────────────────────────────────

  assign o_stall_to_if = i_stall;  // simple chain for now
  // Later: o_stall_to_if = i_stall || my_own_stall_condition

  // ---------------------------------------------------------------------------
  // Valid instruction pipeline
  // ---------------------------------------------------------------------------
  logic                 instr_valid;
  riscv_opcode_t        opcode;
  logic     [4:0]       rs1, rs2, rd;
  logic     [2:0]       funct3;
  logic     [6:0]       funct7;
  
  logic     [31:0]      imm_i, imm_s, imm_b, imm_u, imm_j;

  alu_op_t              alu_operation;
  
  assign instr_valid = id_valid_q && !i_flush;
  // ---------------------------------------------------------------------------
  // Instruction field extraction (only when valid)
  // ---------------------------------------------------------------------------
  assign opcode  = riscv_opcode_t'(id_instr_q[6:0]);
  assign rd      = id_instr_q[11:7];
  assign funct3  = id_instr_q[14:12];
  assign rs1     = id_instr_q[19:15];
  assign rs2     = id_instr_q[24:20];
  assign funct7  = id_instr_q[31:25];

  // ---------------------------------------------------------------------------
  // Immediate generation (RV32I standard) – using registered instruction
  // ---------------------------------------------------------------------------
  assign imm_i = {{20{id_instr_q[31]}}, id_instr_q[31:20]};
  assign imm_s = {{20{id_instr_q[31]}}, id_instr_q[31:25], id_instr_q[11:7]};
  assign imm_b = {{19{id_instr_q[31]}}, id_instr_q[31], id_instr_q[7], id_instr_q[30:25], id_instr_q[11:8], 1'b0};
  assign imm_u = {id_instr_q[31:12], 12'b0};
  assign imm_j = {{11{id_instr_q[31]}}, id_instr_q[31], id_instr_q[19:12], id_instr_q[20], id_instr_q[30:21], 1'b0};

  // ---------------------------------------------------------------------------
  // Arithmetic operation decoding (OP & OP-IMM)
  // ---------------------------------------------------------------------------
  always_comb begin
    alu_operation = ALU_INVALID;

    if (opcode == OPCODE_OP_IMM || opcode == OPCODE_OP) begin
      case ({funct7[5], funct3})
        4'b0_000: alu_operation = ALU_ADD;
        4'b1_000: alu_operation = (opcode == OPCODE_OP) ? ALU_SUB : ALU_ADD; // sub only for OP
        4'b0_001: alu_operation = ALU_SLL;
        4'b0_010: alu_operation = ALU_SLT;
        4'b0_011: alu_operation = ALU_SLTU;
        4'b0_100: alu_operation = ALU_XOR;
        4'b0_101: alu_operation = (funct7[5]) ? ALU_SRA : ALU_SRL;
        4'b0_110: alu_operation = ALU_OR;
        4'b0_111: alu_operation = ALU_AND;
        default:   alu_operation = ALU_INVALID;
      endcase
    end
    // LUI and AUIPC will be handled in main decode logic (no funct7/funct3 needed)
  end

  // ---------------------------------------------------------------------------
  // Main decode logic → fill o_uop (using registered values)
  // ---------------------------------------------------------------------------
  always_comb begin
    // Default: invalid
    o_dec_valid = 1'b0;
    o_uop       = '0;

    if (instr_valid) begin
      o_dec_valid = 1'b1;
      o_uop.valid        = 1'b1;
      o_uop.opcode       = opcode;
      o_uop.rs1          = rs1;
      o_uop.rs2          = rs2;
      o_uop.rd           = rd;

      case (opcode)
        OPCODE_OP_IMM: begin
          o_uop.is_immediate = 1'b1;
          o_uop.imm          = imm_i;
          o_uop.alu_op       = alu_operation;
          o_uop.uses_rs1     = 1'b1;
          o_uop.uses_rs2     = 1'b0;
          o_uop.writes_rd    = (rd != 5'd0);
        end

        OPCODE_OP: begin
          o_uop.is_immediate = 1'b0;
          o_uop.imm          = 32'b0;
          o_uop.alu_op       = alu_operation;
          o_uop.uses_rs1     = 1'b1;
          o_uop.uses_rs2     = 1'b1;
          o_uop.writes_rd    = (rd != 5'd0);
        end

        OPCODE_LUI: begin
          o_uop.is_immediate = 1'b1;
          o_uop.imm          = imm_u;
          o_uop.alu_op       = ALU_ADD;  // LUI = rd = imm_u (upper 20 bits)
          o_uop.uses_rs1     = 1'b0;
          o_uop.uses_rs2     = 1'b0;
          o_uop.writes_rd    = (rd != 5'd0);
        end

        OPCODE_AUIPC: begin
          o_uop.is_immediate = 1'b1;
          o_uop.imm          = imm_u;
          o_uop.alu_op       = ALU_ADD;  // rd = pc + imm_u
          o_uop.uses_rs1     = 1'b0;     // uses pc instead
          o_uop.uses_rs2     = 1'b0;
          o_uop.writes_rd    = (rd != 5'd0);
        end

        default: begin
          // Unknown/unsupported → mark invalid
          o_dec_valid = 1'b0;
          o_uop.valid = 1'b0;
        end
      endcase
    end
  end

  // PC output is always the registered one
  assign o_dec_pc = id_pc_q;
  
endmodule
