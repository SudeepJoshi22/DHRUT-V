interface mem_if (
    input logic clk,
    input logic rst_n
    );

  logic        m_valid;
  logic        s_ready;
  logic [31:0] m_addr;
  logic [31:0] m_wdata;
  logic [3:0]  m_wstrb;
  logic [31:0] s_rdata;

  // Master modport (CPU side)
  modport master (
    output m_valid,
    output m_addr,
    output m_wdata,
    output m_wstrb,
    input  s_ready,
    input  s_rdata
  );

  // Slave modport (memory side)
  modport slave (
    input  m_valid,
    input  m_addr,
    input  m_wdata,
    input  m_wstrb,
    output s_ready,
    output s_rdata
  );

endinterface
