import riscv_uop_pkg::*;

// =================================================================
// issue_hazard - decides whether a decode bundle can dual-issue
// =================================================================
// Combinational. Given the two uops Decode is presenting this cycle
// (slot 0 = older), decide whether lane 1 may issue alongside lane 0.
// Lane 0 itself is never blocked here - it is the oldest instruction
// in the machine and always issues when Issue is not stalled.
//
// WHY THERE IS NO REGISTER-BUSY SCOREBOARD HERE
// ---------------------------------------------
// A classic scoreboard tracks a "busy" bit per architectural register
// so a consumer can be held back until its producer's result exists.
// DHRUT-V does not need one, for two structural reasons:
//
//   1. The bypass network (rtl/pipeline/forward_unit.sv) covers every
//      cycle between a producer's execute stage and the ARF becoming
//      readable - there is no bypass gap for a scoreboard to plug.
//   2. The LSU's stall (lsu.sv: s_stall_from_lsu) freezes the WHOLE
//      machine, including both ALUs (cpu_core.sv). So the only
//      variable-latency unit cannot get ahead of or behind anything
//      else: writeback stays in program order by construction.
//
// Together those mean every producer's result is already bypassable by
// the time any consumer issues, so a busy table would never block
// anything - it would be dead logic. This is the same conclusion
// biRISC-V reaches (its `dual_issue_ok_w` is a class-pairing pattern
// match plus full bypass, with no busy table). CVA6/CVA6S DO need a
// scoreboard-as-ROB, but only because their writeback is genuinely
// out-of-order across functional units of very different latency.
//
// A real busy table becomes necessary here the moment either of the
// two reasons above stops holding - i.e. if the LSU is made
// non-blocking (hit-under-miss / an LSQ), or a multi-cycle
// multiplier/divider is added that does not freeze the other lane.
// Until then, what this design needs is exactly what is below: a
// class-pairing check plus an intra-bundle dependency check.

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

  // ───────────────────────────────────────────────
  // 1. Structural: what lane 1 is allowed to execute
  // ───────────────────────────────────────────────
  // Lane 1 is a bare ALU: OP, OP-IMM, LUI, AUIPC and nothing else.
  // Everything excluded here needs a unit that exists only once:
  //   load/store   -> the single LSU and its single dmem port
  //   branch/jump  -> the single branch resolver and BPU update port
  //   SYSTEM       -> the single CSR file (and traps must stay precise)
  //   FENCE        -> ordering op, keep it on the older lane
  //   illegal      -> traps, same reason as SYSTEM
  // Keeping lane 1 this narrow is what lets Phase 3 leave the LSU, the
  // CSR unit and the BPU completely untouched.
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
                        && !i_uop1.is_illegal;

  // ───────────────────────────────────────────────
  // 2. Intra-bundle RAW
  // ───────────────────────────────────────────────
  // Lane 0's result does not exist until its execute stage next cycle,
  // so lane 1 cannot read it this cycle at any price. The pair is split:
  // lane 1 stays in Decode's buffer, becomes slot 0 next cycle, and then
  // picks lane 0's result up through the normal ALU bypass.
  logic l0_writes;
  assign l0_writes = i_uop0.writes_rd && (i_uop0.rd != 5'd0);

  assign o_raw_hazard = l0_writes &&
                        ((i_uop1.uses_rs1 && (i_uop1.rs1 == i_uop0.rd)) ||
                         (i_uop1.uses_rs2 && (i_uop1.rs2 == i_uop0.rd)));

  // ───────────────────────────────────────────────
  // 3. Intra-bundle WAW
  // ───────────────────────────────────────────────
  // Both lanes retire in the same cycle into separate ARF write ports,
  // so a shared rd has no defined winner. Split the pair instead.
  assign o_waw_hazard = l0_writes && i_uop1.writes_rd && (i_uop1.rd == i_uop0.rd);

  // ───────────────────────────────────────────────
  // Verdict
  // ───────────────────────────────────────────────
  // Note what is NOT checked here: whether lane 0 redirects control flow.
  // That is only known once lane 0's branch/CSR resolves, which happens a
  // stage later, so Issue applies it at dispatch time instead. See the
  // `!o_mispredict` gate in issue.sv.
  assign o_pair_ok = i_valid0 && i_valid1
                  && o_lane1_capable
                  && !o_raw_hazard
                  && !o_waw_hazard;

endmodule
