// =================================================================
// ARF - architectural register file, 4 read ports / 2 write ports
// =================================================================
// Two read ports and one write port per issue lane. Lane 0 is the
// older instruction of a bundle, lane 1 the younger.
//
// Write conflicts: the two write ports must never target the same
// non-zero rd in the same cycle. Issue's hazard check forbids
// intra-bundle WAW (rtl/pipeline/issue_hazard.sv), and the two retire
// lanes only ever carry instructions from the same bundle, so this
// cannot happen - it is checked by assertion below. The priority
// encoding (lane 1 wins, being younger in program order) exists so a
// violation degrades to "architecturally correct anyway" rather than
// to an X or a lost write.

module ARF (
  input  logic       clk,
  input  logic       rst_n,           // active low reset

  // Lane 0 reads
  input  logic       i_re0,           // read enable
  input  logic [4:0] i_rs1_0,
  input  logic [4:0] i_rs2_0,
  output logic [31:0] o_rs1_data0,
  output logic [31:0] o_rs2_data0,

  // Lane 1 reads
  input  logic       i_re1,
  input  logic [4:0] i_rs1_1,
  input  logic [4:0] i_rs2_1,
  output logic [31:0] o_rs1_data1,
  output logic [31:0] o_rs2_data1,

  // Lane 0 write
  input  logic       i_wr0,
  input  logic [4:0] i_rd0,
  input  logic [31:0] i_write_data0,

  // Lane 1 write
  input  logic       i_wr1,
  input  logic [4:0] i_rd1,
  input  logic [31:0] i_write_data1
);

  // Register file: x0 is hardwired to zero, so we only store x1–x31
  logic [31:0] base_reg [31:1];

  logic wr0_en, wr1_en;
  assign wr0_en = i_wr0 && (i_rd0 != 5'd0);
  assign wr1_en = i_wr1 && (i_rd1 != 5'd0);

  // Synchronous reset and write
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // Reset all registers to 0
      for (int i = 1; i <= 31; i++) begin
        base_reg[i] <= 32'd0;
      end
    end
    else begin
      // Lane 0 first, then lane 1, so that if the two ever did collide
      // the younger instruction's value would be the one that sticks.
      if (wr0_en) begin
        base_reg[i_rd0] <= i_write_data0;
      end
      if (wr1_en) begin
        base_reg[i_rd1] <= i_write_data1;
      end
    end
  end

  // Asynchronous read (combinational)
  // x0 is always 0, and respect read enable
  assign o_rs1_data0 = (i_rs1_0 == 5'd0 || !i_re0) ? 32'd0 : base_reg[i_rs1_0];
  assign o_rs2_data0 = (i_rs2_0 == 5'd0 || !i_re0) ? 32'd0 : base_reg[i_rs2_0];
  assign o_rs1_data1 = (i_rs1_1 == 5'd0 || !i_re1) ? 32'd0 : base_reg[i_rs1_1];
  assign o_rs2_data1 = (i_rs2_1 == 5'd0 || !i_re1) ? 32'd0 : base_reg[i_rs2_1];

`ifdef SIMULATION
  // The two write ports carry the two lanes of ONE bundle, and Issue
  // forbids intra-bundle WAW. If this fires, either the hazard check is
  // broken or the two retire lanes have drifted out of step - both mean
  // a register is getting an unpredictable value.
  assert_no_write_conflict: assert property (
    @(posedge clk) disable iff (!rst_n)
    !(wr0_en && wr1_en && (i_rd0 == i_rd1))
  ) else $error("ARF ERROR: both write ports target x%0d in the same cycle (0x%h vs 0x%h)",
                i_rd0, i_write_data0, i_write_data1);
`endif

endmodule
