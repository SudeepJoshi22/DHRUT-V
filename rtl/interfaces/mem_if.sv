interface mem_if (input logic clk);

  logic        valid;
  logic        ready;
  logic [31:0] addr;
  logic [31:0] wdata;
  logic [3:0]  wstrb;
  logic [31:0] rdata;

  // Master modport (CPU side)
  modport master (
    output valid,
    output addr,
    output wdata,
    output wstrb,
    input  ready,
    input  rdata
  );

  // Slave modport (memory side)
  modport slave (
    input  valid,
    input  addr,
    input  wdata,
    input  wstrb,
    output ready,
    output rdata
  );

endinterface
