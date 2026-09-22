import riscv_uop_pkg::*;

// Combinational pairing checks for an ordered two-uop decode bundle.
// Check lane-1 capability and intra-bundle RAW/WAW dependencies.
// Issue handles operand readiness and redirect gating separately.

module issue_hazard (
  // Decode's bundle. Slot 0 is the older instruction.
  input  logic       i_valid0,
  input  uop_t       i_uop0,
  input  logic       i_valid1,
  input  uop_t       i_uop1,

  // 1 = lane 1 may issue alongside lane 0 this cycle.
  output logic       o_pair_ok,

  // Individual reasons, broken out for waveform debug and for the
  // assertions in issue.sv. Exactly the terms of o_pair_ok.
  output logic       o_lane1_capable,
  output logic       o_raw_hazard,
  output logic       o_waw_hazard
);

  // Lane 1 accepts OP, OP-IMM, LUI and AUIPC, excluding RV32M and illegal ops.
  // Memory, control flow, CSR and fence operations require lane 0.
  logic lane1_alu_class;
  always_comb begin
    unique case (i_uop1.opcode)
      OPCODE_OP, OPCODE_OP_IMM, OPCODE_LUI, OPCODE_AUIPC: lane1_alu_class = 1'b1;
      default:                                            lane1_alu_class = 1'b0;
    endcase
  end

  assign o_lane1_capable = lane1_alu_class
                        && !i_uop1.is_load
                        && !i_uop1.is_store
                        && !i_uop1.is_branch
                        && !i_uop1.is_jump
                        && !i_uop1.is_mdu
                        && !i_uop1.is_illegal;

  // Split RAW-dependent pairs; lane 1 cannot consume lane 0's result this cycle.
  logic l0_writes;
  assign l0_writes = i_uop0.writes_rd && (i_uop0.rd != 5'd0);

  assign o_raw_hazard = l0_writes &&
                        ((i_uop1.uses_rs1 && (i_uop1.rs1 == i_uop0.rd)) ||
                         (i_uop1.uses_rs2 && (i_uop1.rs2 == i_uop0.rd)));

  // Split pairs that write the same nonzero destination register.
  assign o_waw_hazard = l0_writes && i_uop1.writes_rd && (i_uop1.rd == i_uop0.rd);

  // Issue gates lane-1 dispatch on lane-0 redirect resolution.
  assign o_pair_ok = i_valid0 && i_valid1
                  && o_lane1_capable
                  && !i_uop0.is_mdu
                  && !o_raw_hazard
                  && !o_waw_hazard;

endmodule
