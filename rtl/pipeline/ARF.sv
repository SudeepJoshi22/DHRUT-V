module ARF (
  input  logic       clk,
  input  logic       rst_n,           // active low reset
  input  logic       i_re,            // read enable
  input  logic       i_wr,            // write enable
  input  logic [4:0] i_rs1,           // source register 1 address
  input  logic [4:0] i_rs2,           // source register 2 address
  input  logic [4:0] i_rd,            // destination register address
  input  logic [31:0] i_write_data,   // data to be written

  output logic [31:0] o_read_data1,   // data from rs1
  output logic [31:0] o_read_data2    // data from rs2
);

  // Register file: x0 is hardwired to zero, so we only store x1–x31
  logic [31:0] base_reg [31:1];

  // Synchronous reset and write
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // Reset all registers to 0
      for (int i = 1; i <= 31; i++) begin
        base_reg[i] <= 32'd0;
      end
    end
    else begin
      // Only update on explicit write (x0 is never written)
      if (i_wr && (i_rd != 5'd0)) begin
        base_reg[i_rd] <= i_write_data;
      end
    end
  end

  // Asynchronous read (combinational)
  // x0 is always 0, and respect read enable
  assign o_read_data1 = (i_rs1 == 5'd0 || !i_re) ? 32'd0 : base_reg[i_rs1];
  assign o_read_data2 = (i_rs2 == 5'd0 || !i_re) ? 32'd0 : base_reg[i_rs2];

endmodule
