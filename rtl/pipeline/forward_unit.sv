// Operand bypass for four source operands. Youngest matching producer wins:
// ALU1 > ALU0/LSU > RETIRE1 > RETIRE0 > ARF.
// ALU0 and LSU completions are mutually exclusive. Producer inputs must be
// qualified by valid; x0 never forwards. Issue blocks pending MDU destinations.

module forward_unit (
  // ── Producers, youngest first ──
  // ALU lane 1
  input  logic        i_alu1_writes_rd,
  input  logic [4:0]  i_alu1_rd,
  input  logic [31:0] i_alu1_data,
  // ALU lane 0
  input  logic        i_alu0_writes_rd,
  input  logic [4:0]  i_alu0_rd,
  input  logic [31:0] i_alu0_data,
  // LSU (lane 0 only - lane 1 never executes memory ops)
  input  logic        i_lsu_valid,
  input  logic [4:0]  i_lsu_rd,
  input  logic [31:0] i_lsu_data,
  // Retire lane 1
  input  logic        i_ret1_writes_rd,
  input  logic [4:0]  i_ret1_rd,
  input  logic [31:0] i_ret1_data,
  // Retire lane 0
  input  logic        i_ret0_writes_rd,
  input  logic [4:0]  i_ret0_rd,
  input  logic [31:0] i_ret0_data,

  // ── Consumers: register numbers and their ARF read-back values ──
  input  logic [4:0]  i_rs1_0,
  input  logic [4:0]  i_rs2_0,
  input  logic [31:0] i_arf_rs1_0,
  input  logic [31:0] i_arf_rs2_0,
  input  logic [4:0]  i_rs1_1,
  input  logic [4:0]  i_rs2_1,
  input  logic [31:0] i_arf_rs1_1,
  input  logic [31:0] i_arf_rs2_1,

  // ── Resolved operands ──
  output logic [31:0] o_rs1_0,
  output logic [31:0] o_rs2_0,
  output logic [31:0] o_rs1_1,
  output logic [31:0] o_rs2_1,

  // Report bypass hits for scoreboard operand-readiness checks.
  output logic        o_hit_rs1_0,
  output logic        o_hit_rs2_0,
  output logic        o_hit_rs1_1,
  output logic        o_hit_rs2_1
);

  // One consumer's resolution, applied four times. Ordered youngest
  // producer first; the first match wins.
  function automatic logic [31:0] bypass(
      input logic [4:0]  rs,
      input logic [31:0] arf_val,
      input logic        alu1_w, input logic [4:0] alu1_rd, input logic [31:0] alu1_d,
      input logic        alu0_w, input logic [4:0] alu0_rd, input logic [31:0] alu0_d,
      input logic        lsu_v,  input logic [4:0] lsu_rd,  input logic [31:0] lsu_d,
      input logic        ret1_w, input logic [4:0] ret1_rd, input logic [31:0] ret1_d,
      input logic        ret0_w, input logic [4:0] ret0_rd, input logic [31:0] ret0_d);
    if (rs == 5'd0)                            return 32'd0;
    else if (alu1_w && (alu1_rd == rs))        return alu1_d;
    else if (alu0_w && (alu0_rd == rs))        return alu0_d;
    else if (lsu_v  && (lsu_rd  == rs))        return lsu_d;
    else if (ret1_w && (ret1_rd == rs))        return ret1_d;
    else if (ret0_w && (ret0_rd == rs))        return ret0_d;
    else                                       return arf_val;
  endfunction

  // Whether ANY producer matches - same match terms as bypass() above,
  // kept adjacent so the two cannot drift apart. x0 counts as a hit: it
  // is never busy, so readiness never depends on it.
  function automatic logic hit(
      input logic [4:0] rs,
      input logic       alu1_w, input logic [4:0] alu1_rd,
      input logic       alu0_w, input logic [4:0] alu0_rd,
      input logic       lsu_v,  input logic [4:0] lsu_rd,
      input logic       ret1_w, input logic [4:0] ret1_rd,
      input logic       ret0_w, input logic [4:0] ret0_rd);
    return (rs == 5'd0)
        || (alu1_w && (alu1_rd == rs))
        || (alu0_w && (alu0_rd == rs))
        || (lsu_v  && (lsu_rd  == rs))
        || (ret1_w && (ret1_rd == rs))
        || (ret0_w && (ret0_rd == rs));
  endfunction

  always_comb begin
    o_hit_rs1_0 = hit(i_rs1_0,
                      i_alu1_writes_rd, i_alu1_rd,
                      i_alu0_writes_rd, i_alu0_rd,
                      i_lsu_valid,      i_lsu_rd,
                      i_ret1_writes_rd, i_ret1_rd,
                      i_ret0_writes_rd, i_ret0_rd);
    o_hit_rs2_0 = hit(i_rs2_0,
                      i_alu1_writes_rd, i_alu1_rd,
                      i_alu0_writes_rd, i_alu0_rd,
                      i_lsu_valid,      i_lsu_rd,
                      i_ret1_writes_rd, i_ret1_rd,
                      i_ret0_writes_rd, i_ret0_rd);
    o_hit_rs1_1 = hit(i_rs1_1,
                      i_alu1_writes_rd, i_alu1_rd,
                      i_alu0_writes_rd, i_alu0_rd,
                      i_lsu_valid,      i_lsu_rd,
                      i_ret1_writes_rd, i_ret1_rd,
                      i_ret0_writes_rd, i_ret0_rd);
    o_hit_rs2_1 = hit(i_rs2_1,
                      i_alu1_writes_rd, i_alu1_rd,
                      i_alu0_writes_rd, i_alu0_rd,
                      i_lsu_valid,      i_lsu_rd,
                      i_ret1_writes_rd, i_ret1_rd,
                      i_ret0_writes_rd, i_ret0_rd);
  end

  always_comb begin
    o_rs1_0 = bypass(i_rs1_0, i_arf_rs1_0,
                     i_alu1_writes_rd, i_alu1_rd, i_alu1_data,
                     i_alu0_writes_rd, i_alu0_rd, i_alu0_data,
                     i_lsu_valid,      i_lsu_rd,  i_lsu_data,
                     i_ret1_writes_rd, i_ret1_rd, i_ret1_data,
                     i_ret0_writes_rd, i_ret0_rd, i_ret0_data);

    o_rs2_0 = bypass(i_rs2_0, i_arf_rs2_0,
                     i_alu1_writes_rd, i_alu1_rd, i_alu1_data,
                     i_alu0_writes_rd, i_alu0_rd, i_alu0_data,
                     i_lsu_valid,      i_lsu_rd,  i_lsu_data,
                     i_ret1_writes_rd, i_ret1_rd, i_ret1_data,
                     i_ret0_writes_rd, i_ret0_rd, i_ret0_data);

    o_rs1_1 = bypass(i_rs1_1, i_arf_rs1_1,
                     i_alu1_writes_rd, i_alu1_rd, i_alu1_data,
                     i_alu0_writes_rd, i_alu0_rd, i_alu0_data,
                     i_lsu_valid,      i_lsu_rd,  i_lsu_data,
                     i_ret1_writes_rd, i_ret1_rd, i_ret1_data,
                     i_ret0_writes_rd, i_ret0_rd, i_ret0_data);

    o_rs2_1 = bypass(i_rs2_1, i_arf_rs2_1,
                     i_alu1_writes_rd, i_alu1_rd, i_alu1_data,
                     i_alu0_writes_rd, i_alu0_rd, i_alu0_data,
                     i_lsu_valid,      i_lsu_rd,  i_lsu_data,
                     i_ret1_writes_rd, i_ret1_rd, i_ret1_data,
                     i_ret0_writes_rd, i_ret0_rd, i_ret0_data);
  end

endmodule
