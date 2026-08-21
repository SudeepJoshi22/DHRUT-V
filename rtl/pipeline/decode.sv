import riscv_uop_pkg::*;

module decode_stage (
  input  logic        clk,
  input  logic        rst_n,

  // From IF (unregistered inputs)
  input  logic        i_if_valid,
  input  logic [31:0] i_if_pc,
  input  logic [31:0] i_if_instr,
  input  logic        i_if_pred_taken,
  input  logic [31:0] i_if_pred_target,

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
  logic        id_pred_taken_q;
  logic [31:0] id_pred_target_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || i_flush) begin
      id_valid_q       <= 1'b0;
      id_pc_q          <= '0;
      id_instr_q       <= '0;
      id_pred_taken_q  <= 1'b0;
      id_pred_target_q <= '0;
    end
    else if (!i_stall) begin
      id_valid_q       <= i_if_valid;
      id_pc_q          <= i_if_pc;
      id_instr_q       <= i_if_instr;
      id_pred_taken_q  <= i_if_pred_taken;
      id_pred_target_q <= i_if_pred_target;
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

  logic                 lsu_sign_extend;
  logic     [1:0]       lsu_access_size;

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
  // Arithmetic and Branch operation decoding (OP & OP-IMM)
  // ---------------------------------------------------------------------------

  always_comb begin
  
      unique if (opcode == OPCODE_OP_IMM) begin : decode_op_imm
          // ─────────────── OP-IMM (I-type immediates) ───────────────
          case (funct3)
              3'b000:   alu_operation = ALU_ADD;   // addi
              3'b001:   alu_operation = ALU_SLL;   // slli
              3'b010:   alu_operation = ALU_SLT;   // slti
              3'b011:   alu_operation = ALU_SLTU;  // sltiu
              3'b100:   alu_operation = ALU_XOR;   // xori
              3'b101: begin   // srli / srai
                if (funct7[5] == 1'b1)          // bit 30 set → assume srai (funct7 should be 0100000)
                        alu_operation = ALU_SRA;
                else
                        alu_operation = ALU_SRL;    // srli, or any non-srai
              end
              3'b110:   alu_operation = ALU_OR;    // ori
              3'b111:   alu_operation = ALU_AND;   // andi
              default:  alu_operation = ALU_ADD;  // or ALU_INVALID if you want strict checking
          endcase

      end else if (opcode == OPCODE_OP) begin : decode_op
          // ─────────────── OP (R-type, register-register) ───────────────
          // Here funct7[5] selects sub/sra vs add/srl
          case ({funct7[5], funct3})
              4'b0_000: alu_operation = ALU_ADD;  // add
              4'b1_000: alu_operation = ALU_SUB;  // sub
              4'b0_001: alu_operation = ALU_SLL;  // sll
              4'b0_010: alu_operation = ALU_SLT;  // slt
              4'b0_011: alu_operation = ALU_SLTU; // sltu
              4'b0_100: alu_operation = ALU_XOR;  // xor
              4'b0_101: alu_operation = ALU_SRL;  // srl
              4'b1_101: alu_operation = ALU_SRA;  // sra
              4'b0_110: alu_operation = ALU_OR;   // or
              4'b0_111: alu_operation = ALU_AND;  // and
              default:  alu_operation = ALU_ADD;  
          endcase
      
      end else begin
                        alu_operation = ALU_ADD;
      end
      // Note: LUI / AUIPC usually don't use the ALU in the same way
      //       (they generate immediate directly → handled elsewhere)
  end

  // ---------------------------------------------------------------------------
  // Load/Store type decoding → set lsu_sign_extend and lsu_access_size
  // ---------------------------------------------------------------------------
  always_comb begin
    // Default values (non-load/store)
    lsu_sign_extend  = 1'b0;
    lsu_access_size  = 2'b00;  // byte (default/safe)

    if (instr_valid) begin
      case (opcode)
        OPCODE_LOAD: begin
          lsu_sign_extend = ~funct3[2];      // 0xxx = sign-extend (LB/LH), 1xxx = zero-extend (LBU/LHU)
          lsu_access_size = funct3[1:0];     // 00=byte, 01=half, 10=word
        end
        OPCODE_STORE: begin
          lsu_sign_extend = 1'b0;            // stores never extend
          lsu_access_size = funct3[1:0];     // 00=SB, 01=SH, 10=SW
        end

        default: begin
          // Non-memory ops → leave defaults
        end
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  // Main decode logic → fill o_uop (using registered values)
  // ---------------------------------------------------------------------------
  always_comb begin
    // Default: invalid
    o_dec_valid = 1'b0;
    o_uop       = '0;

    if (instr_valid) begin
      o_dec_valid        = 1'b1;
      o_uop.valid        = 1'b1;
      o_uop.opcode       = opcode;
      o_uop.funct3       = funct3;
      o_uop.rs1          = rs1;

      o_uop.rs2          = rs2;
      o_uop.rd           = rd;
      o_uop.pred_taken   = id_pred_taken_q;
      o_uop.pred_target  = id_pred_target_q;
      o_uop.instr_bits   = id_instr_q;

      case (opcode)
        OPCODE_OP_IMM: begin
          o_uop.is_immediate = 1'b1;
          o_uop.is_branch    = 1'b0;
          o_uop.is_jump      = 1'b0;
          o_uop.imm          = imm_i;
          o_uop.alu_op       = alu_operation;
          o_uop.uses_rs1     = 1'b1;
          o_uop.uses_rs2     = 1'b0;
          o_uop.writes_rd    = (rd != 5'd0);
        end

        OPCODE_OP: begin
          o_uop.is_immediate = 1'b0;
          o_uop.is_branch    = 1'b0;
          o_uop.is_jump      = 1'b0;
          o_uop.imm          = 32'b0;
          o_uop.alu_op       = alu_operation;
          o_uop.uses_rs1     = 1'b1;
          o_uop.uses_rs2     = 1'b1;
          o_uop.writes_rd    = (rd != 5'd0);
        end

        OPCODE_LUI: begin
          o_uop.is_immediate = 1'b1;
          o_uop.is_branch    = 1'b0;
          o_uop.is_jump      = 1'b0;
          o_uop.imm          = imm_u;
          o_uop.alu_op       = ALU_ADD;  // LUI = rd = imm_u (upper 20 bits)
          o_uop.uses_rs1     = 1'b0;
          o_uop.uses_rs2     = 1'b0;
          o_uop.writes_rd    = (rd != 5'd0);
        end

        OPCODE_AUIPC: begin
          o_uop.is_immediate = 1'b1;
          o_uop.is_branch    = 1'b0;
          o_uop.is_jump      = 1'b0;
          o_uop.imm          = imm_u;
          o_uop.alu_op       = ALU_ADD;  // rd = pc + imm_u
          o_uop.uses_rs1     = 1'b0;     // uses pc instead
          o_uop.uses_rs2     = 1'b0;
          o_uop.writes_rd    = (rd != 5'd0);
        end
        OPCODE_BRANCH: begin
          o_uop.is_immediate = 1'b0;
          o_uop.is_branch    = 1'b1;
          o_uop.is_jump      = 1'b0;
          o_uop.imm          = imm_b;
          o_uop.alu_op       = ALU_ADD;          // Not used for branch condition anymore
          o_uop.uses_rs1     = 1'b1;
          o_uop.uses_rs2     = 1'b1;
          o_uop.writes_rd    = 1'b0;             // branches never write rd
        end
        OPCODE_JAL: begin
          o_uop.is_immediate = 1'b1;
          o_uop.is_branch    = 1'b0;
          o_uop.is_jump      = 1'b1;
          o_uop.imm          = imm_j;
          o_uop.alu_op       = ALU_ADD;             // Link value (pc+4)
          o_uop.uses_rs1     = 1'b0;
          o_uop.uses_rs2     = 1'b0;
          o_uop.writes_rd    = (rd != 5'd0);     // link if rd != x0
        end
        OPCODE_JALR: begin
          o_uop.is_immediate = 1'b1;
          o_uop.is_branch    = 1'b0;
          o_uop.is_jump      = 1'b1;
          o_uop.imm          = imm_i;
          o_uop.alu_op       = ALU_ADD;             // Link value (pc+4)
          o_uop.uses_rs1     = 1'b0;
          o_uop.uses_rs2     = 1'b0;
          o_uop.writes_rd    = (rd != 5'd0);     // link if rd != x0
        end
        // Load & Store cases (now setting LSU fields)
        OPCODE_LOAD: begin
          o_uop.is_immediate = 1'b0;
          o_uop.is_branch    = 1'b0;
          o_uop.is_jump      = 1'b0;
          o_uop.imm          = imm_i;
          o_uop.alu_op       = ALU_ADD;  // addr = rs1 + imm
          o_uop.uses_rs1     = 1'b1;
          o_uop.uses_rs2     = 1'b0;
          o_uop.writes_rd    = (rd != 5'd0);
          o_uop.is_load      = 1'b1;
          o_uop.is_store     = 1'b0;
          o_uop.lsu_sign_extend = lsu_sign_extend;
          o_uop.lsu_access_size = lsu_access_size;
        end
        OPCODE_STORE: begin
          o_uop.is_immediate = 1'b0;
          o_uop.is_branch    = 1'b0;
          o_uop.is_jump      = 1'b0;
          o_uop.imm          = imm_s;
          o_uop.alu_op       = ALU_ADD;  // addr = rs1 + imm
          o_uop.uses_rs1     = 1'b1;
          o_uop.uses_rs2     = 1'b1;
          o_uop.writes_rd    = 1'b0;
          o_uop.is_load      = 1'b0;
          o_uop.is_store     = 1'b1;
          o_uop.lsu_sign_extend = lsu_sign_extend;
          o_uop.lsu_access_size = lsu_access_size;
        end
        OPCODE_MISC_MEM: begin
          // FENCE: single-hart in-order core already provides program order,
          // so this is a pure no-op (no side effects, doesn't write rd).
          o_uop.is_immediate = 1'b0;
          o_uop.is_branch    = 1'b0;
          o_uop.is_jump      = 1'b0;
          o_uop.uses_rs1     = 1'b0;
          o_uop.uses_rs2     = 1'b0;
          o_uop.writes_rd    = 1'b0;
        end

        OPCODE_SYSTEM: begin
          o_uop.is_immediate = 1'b0;
          o_uop.is_branch    = 1'b0;
          o_uop.is_jump      = 1'b0;
          o_uop.alu_op       = ALU_ADD;                    // CSR read value passed through the ALU as-is
          o_uop.imm          = {20'b0, id_instr_q[31:20]};  // CSR addr (funct3!=0) or funct12 (funct3==0)

          if (funct3 == 3'b000) begin
            // Privileged/environment group: ECALL / EBREAK / MRET, selected by funct12 in Issue.
            o_uop.uses_rs1  = 1'b0;
            o_uop.uses_rs2  = 1'b0;
            o_uop.writes_rd = 1'b0;
            unique case (id_instr_q[31:20])
              12'h000, 12'h001, 12'h302: o_uop.is_illegal = 1'b0;  // ECALL, EBREAK, MRET
              default:                   o_uop.is_illegal = 1'b1;  // reserved (WFI, SFENCE.VMA, ...)
            endcase
          end else if (funct3 == 3'b100) begin
            // Reserved funct3 — not a defined CSR or privileged instruction.
            o_uop.uses_rs1  = 1'b0;
            o_uop.uses_rs2  = 1'b0;
            o_uop.writes_rd = 1'b0;
            o_uop.is_illegal = 1'b1;
          end else begin
            // CSRRW/S/C (register form, funct3[2]=0) or CSRRWI/SI/CI (immediate
            // form, funct3[2]=1 — the "rs1" field instead carries a 5-bit zimm,
            // which decode already extracts unconditionally above).
            o_uop.uses_rs1  = ~funct3[2];
            o_uop.uses_rs2  = 1'b0;
            o_uop.writes_rd = (rd != 5'd0);
          end
        end

        default: begin
          // Unrecognized/reserved opcode (or unimplemented extension) →
          // still a valid, in-order uop that traps as an illegal instruction
          // at Issue, rather than silently vanishing from the pipeline.
          o_uop.is_illegal = 1'b1;
          o_uop.uses_rs1   = 1'b0;
          o_uop.uses_rs2   = 1'b0;
          o_uop.writes_rd  = 1'b0;
        end
      endcase
    end
  end

  // PC output is always the registered one
  assign o_dec_pc = id_pc_q;
  
endmodule
