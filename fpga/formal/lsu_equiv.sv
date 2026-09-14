// Exhaustive equivalence for the LSU align/extend datapath: the ORIGINAL
// per-(size,offset) case arms vs the shared-shifter rewrite, over every
// combination of data, address offset, access size and sign-extend flag.
module lsu_dp_equiv (
  input logic [31:0] data,
  input logic [1:0]  off,
  input logic [1:0]  sz,
  input logic        sx,
  input logic        is_store
);
  // ── OLD store path ────────────────────────────────────────────────
  logic [31:0] o_wdata; logic [3:0] o_wstrb;
  always_comb begin
    o_wstrb = 4'b0000;
    o_wdata = data;
    if (is_store) begin
      case (sz)
        2'b00: begin
          case (off)
            2'b00: o_wstrb = 4'b0001;
            2'b01: o_wstrb = 4'b0010;
            2'b10: o_wstrb = 4'b0100;
            2'b11: o_wstrb = 4'b1000;
          endcase
          o_wdata = {24'b0, data[7:0]} << (off * 8);
        end
        2'b01: begin
          case (off)
            2'b00: o_wstrb = 4'b0011;
            2'b10: o_wstrb = 4'b1100;
            default: o_wstrb = 4'b0000;
          endcase
          o_wdata = {16'b0, data[15:0]} << (off * 8);
        end
        2'b10: o_wstrb = 4'b1111;
        default: o_wstrb = 4'b0000;
      endcase
    end
  end

  // ── NEW store path ────────────────────────────────────────────────
  logic [31:0] n_wdata; logic [3:0] n_wstrb;
  logic h_aligned; assign h_aligned = (off[0] == 1'b0);
  logic [31:0] store_masked; logic [3:0] strb_base; logic [1:0] shift_off;
  always_comb begin
    unique case (sz)
      2'b00:   store_masked = {24'b0, data[7:0]};
      2'b01:   store_masked = {16'b0, data[15:0]};
      default: store_masked = data;
    endcase
  end
  always_comb begin
    unique case (sz)
      2'b00:   strb_base = 4'b0001;
      2'b01:   strb_base = h_aligned ? 4'b0011 : 4'b0000;
      2'b10:   strb_base = 4'b1111;
      default: strb_base = 4'b0000;
    endcase
  end
  assign shift_off = (sz == 2'b10) ? 2'b00 : off;
  assign n_wdata = is_store ? (store_masked << {shift_off, 3'b000}) : data;
  assign n_wstrb = is_store ? (strb_base   <<  shift_off)           : 4'b0000;

  // ── OLD load path ─────────────────────────────────────────────────
  logic [31:0] o_ld;
  always_comb begin
    o_ld = data;
    case (sz)
      2'b00: begin
        case (off)
          2'b00: o_ld = {{24{sx & data[7]}},  data[7:0]};
          2'b01: o_ld = {{24{sx & data[15]}}, data[15:8]};
          2'b10: o_ld = {{24{sx & data[23]}}, data[23:16]};
          2'b11: o_ld = {{24{sx & data[31]}}, data[31:24]};
        endcase
      end
      2'b01: begin
        case (off)
          2'b00: o_ld = {{16{sx & data[15]}}, data[15:0]};
          2'b10: o_ld = {{16{sx & data[31]}}, data[31:16]};
          default: o_ld = 32'b0;
        endcase
      end
      2'b10: o_ld = data;
      default: o_ld = 32'b0;
    endcase
  end

  // ── NEW load path ─────────────────────────────────────────────────
  logic [31:0] n_ld, load_shifted;
  assign load_shifted = data >> {off, 3'b000};
  always_comb begin
    n_ld = data;
    unique case (sz)
      2'b00:   n_ld = {{24{sx & load_shifted[7]}},  load_shifted[7:0]};
      2'b01:   n_ld = h_aligned
                      ? {{16{sx & load_shifted[15]}}, load_shifted[15:0]}
                      : 32'b0;
      2'b10:   n_ld = data;
      default: n_ld = 32'b0;
    endcase
  end

  // Store data only matters on lanes the strobe enables.
  always_comb begin
    assert (o_wstrb == n_wstrb);
    for (int b = 0; b < 4; b++)
      if (o_wstrb[b]) assert (o_wdata[b*8 +: 8] == n_wdata[b*8 +: 8]);
    assert (o_ld == n_ld);
  end
endmodule
